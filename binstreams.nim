## :Authors: John Novak
##
## **nim-binstreams** is a no-dependencies Nim library that provides
## endianness aware binary streams. It is a wrapper over the standard `io`
## module, and it uses
## [stew/endians2](https://github.com/status-im/nim-stew/blob/master/stew/endians2.nim)
## for endianness conversions (included in the project), so it should be
## reasonably fast.
##
## Main features:
##
## * Support for file and memory buffer backed streams through a single
##   interface
## * Possibility to switch the endianness of a stream on the fly
## * Mixed read/write streams are supported
## * Generics-friendly API
##

import strformat
import strutils

import binstreams/deps/stew/endians2


type AllTypes = bool | char |
                int8 | int16 | int32 | int64 |
                uint | uint8 | uint16 | uint32 | uint64 |
                float32 | float64

when not defined(js):
  type
    StreamSeekPos* = enum
      sspSet, sspCur, sspEnd

  func toFileSeekPos(s: StreamSeekPos): FileSeekPos =
    case s
    of sspSet: fspSet
    of sspCur: fspCur
    of sspEnd: fspEnd

  # {{{ File stream

  type
    FileStream* = ref object
      f: File
      filename: string
      endian: Endianness
      pos: int64

  const
    ## Size of the internal read buffer
    ReadChunkSize* = 512

    ## Size of the internal write buffer
    WriteBufSize* = 512

  proc newFileStream*(f: File, endian: Endianness): FileStream =
    ## Creates a new file stream from a file handle with the given endianness.
    ## It is possible to change the endianness later on-the-fly. The current
    ## file position is not changed.
    new(result)
    result.f = f
    result.endian = endian

  proc newFileStream*(filename: string, endian: Endianness,
                      mode: FileMode = fmRead,
                      bufSize: int = -1): FileStream =
    ## Creates a new file stream from a file named `filename` with the given
    ## `mode` and endianness. It is possible to change the endianness later
    ## on-the-fly. It is also possible to explicitly set the `bufSize` (the
    ## default is to use whatever default `open` uses). This method does not
    ## raise an exception if the file cannot be opened; it just returns `nil`.
    var f: File
    if open(f, filename, mode, bufSize):
      result = newFileStream(f, endian)
      result.filename = filename

  proc openFileStream*(filename: string, endian: Endianness,
                       mode: FileMode = fmRead,
                       bufSize: int = -1): FileStream =
    ## Creates a new file stream from a file named `filename` with the given
    ## `mode` and endianness. It is possible to change the endianness later
    ## on-the-fly. It is also possible to explicitly set the `bufSize` (the
    ## default is to use whatever default `open` uses).
    ##
    ## Raises an `IOError` if the file cannot be opened.
    var f: File
    if open(f, filename, mode, bufSize):
      result = newFileStream(f, endian)
      result.filename = filename
    else:
      raise newException(IOError,
        fmt"cannot open file '{filename}' using mode {mode}")

  proc close*(fs: FileStream) =
    ## Closes a file stream.
    ##
    ## Raises an `IOError` if the stream has been closed or has not been
    ## initialised.
    if fs == nil:
      raise newException(IOError,
        "stream has already been closed or has not been properly initialised")
    if fs.f != nil: close(fs.f)
    fs.f = nil

  proc checkStreamOpen(fs: FileStream) =
    ## Closes a file stream.
    ##
    ## Raises an `IOError` if the stream is not open.
    if fs == nil:
      raise newException(IOError,
        "stream has been closed or has not been properly initialised")

  proc flush*(fs: FileStream) =
    ## Flushes the file associated with the stream.
    ##
    ## Raises an `IOError` if the stream is not open.
    fs.checkStreamOpen()
    flushFile(fs.f)

  proc atEnd*(fs: FileStream): bool =
    ## Returns true if the file position is at the end of the stream (calls
    ## `endOfFile()` internally).
    ##
    ## Raises an `IOError` if the stream is not open.
    fs.checkStreamOpen()
    endOfFile(fs.f)

  proc filename*(fs: FileStream): string =
    ## Returns the name of the file associated with the stream.
    fs.filename

  proc endian*(fs: FileStream): Endianness =
    ## Returns the current endianness.
    fs.endian

  proc `endian=`*(fs: FileStream, endian: Endianness) =
    ## Sets the endianness (effective from the next read/write operation).
    fs.endian = endian

  proc getPosition*(fs: FileStream): int64 {.inline.} =
    ## Gets the file position of the file associated with the stream.
    ##
    ## **Note:** Even if you created the stream from a file handle, it is
    ## preferable to use this method for querying the current file position to
    ## avoid OS calls (the stream maintains its own file position for better
    ## performance).
    ##
    ## Raises an `IOError` if the stream is not open.
    fs.checkStreamOpen()
    result = fs.pos

  proc setPosition*(fs: FileStream, pos: int64,
                    relativeTo: StreamSeekPos = sspSet) =
    ## Sets the file position of the file associated with the stream.
    ##
    ## Raises an `IOError` if the stream is not open.
    fs.checkStreamOpen()
    setFilePos(fs.f, pos, toFileSeekPos(relativeTo))
    fs.pos = getFilePos(fs.f).int64

  proc raiseReadError(fs: FileStream) =
    raise newException(IOError,
      fmt"cannot read from stream, filename: '{fs.filename}'")

  proc readAndSwap[T: AllTypes](fs: FileStream, buf: var openArray[T],
                                startIndex, numValues: Natural) {.inline.} =
    var
      valuesLeft = numValues
      bufIndex = startIndex

    while valuesLeft > 0:
      let
        valuesToRead = min(valuesLeft, ReadChunkSize)
        bytesToRead = valuesToRead * sizeof(T)
        bytesRead = readBuffer(fs.f, buf[bufIndex].addr, bytesToRead)
        valuesRead = valuesToRead

      if bytesRead != bytesToRead:
        fs.raiseReadError()
      inc(fs.pos, bytesRead)
      dec(valuesLeft, valuesRead)

      for i in bufIndex..<bufIndex + valuesRead:
        when sizeof(T) == 1: buf[i] = cast[T](swapBytes(cast[uint8 ](buf[i])))
        elif sizeof(T) == 2: buf[i] = cast[T](swapBytes(cast[uint16](buf[i])))
        elif sizeof(T) == 4: buf[i] = cast[T](swapBytes(cast[uint32](buf[i])))
        elif sizeof(T) == 8: buf[i] = cast[T](swapBytes(cast[uint64](buf[i])))
      inc(bufIndex, valuesRead)


  proc read*[T: AllTypes](fs: FileStream, buf: var openArray[T],
                          startIndex, numValues: Natural) =
    ## Reads `numValues` number of values from the stream into `buf`, starting
    ## from `startIndex`.
    ##
    ## Raises an `IOError` on read errors.
    fs.checkStreamOpen()
    if numValues == 0: return

    if system.cpuEndian == fs.endian or sizeof(T) == 1:
      assert startIndex + numValues <= buf.len
      let
        bytesToRead = numValues * sizeof(T)
        bytesRead = readBuffer(fs.f, buf[startIndex].addr, bytesToRead)

      # Apparently Nim only looks at the lowest bit when treating an openArray
      # of bytes as an openArray of bools, so we need a conversions step here.
      if T is bool:
        let byteArr = cast[ptr UncheckedArray[byte]](buf)
        for i in startIndex..<startIndex+bytesToRead:
          if byteArr[i] > 0: byteArr[i] = 1

      if bytesRead != bytesToRead:
        fs.raiseReadError()
      inc(fs.pos, bytesRead)
    else:
      fs.readAndSwap(buf, startIndex, numValues)

  proc read*(fs: FileStream, T: typedesc[AllTypes]): T =
    ## Reads a single value of type `T` from the stream.
    ##
    ## Raises an `IOError` on read errors.
    var buf {.noinit.}: array[1, T]
    fs.read(buf, 0, 1)
    result = buf[0]

  proc readStr*(fs: FileStream, length: Natural): string =
    ## Reads `length` number of bytes from the stream as an UTF-8 string.
    ## `length` should be equal to the length of the UTF-8 byte sequence,
    ## excluding any terminating zeroes.
    ##
    ## Raises an `IOError` on read errors.
    result = newString(length)
    fs.read(toOpenArrayByte(result, 0, length-1), 0, length)


  template doPeekFileStream(fs: FileStream, body: untyped): untyped =
    let pos = fs.getPosition()
    defer: fs.setPosition(pos)
    body

  proc peek*(fs: FileStream, T: typedesc[AllTypes]): T =
    ## Peeks (reads without advancing the file position) a single value of
    ## type `T` from the stream.
    ##
    ## Raises an `IOError` on read errors.
    doPeekFileStream(fs): fs.read(T)

  proc peek*[T: AllTypes](fs: FileStream, buf: var openArray[T],
                          startIndex, numValues: Natural) =
    ## Peeks (reads without advancing the file position) `numValues` number of
    ## values into `buf` starting from `startIndex`.
    ##
    ## Raises an `IOError` on read errors.
    doPeekFileStream(fs): fs.read(buf, startIndex, numValues)

  proc peekStr*(fs: FileStream, length: Natural): string =
    ## Peeks (reads without advancing the file position) `length` number of
    ## bytes from the stream as an UTF-8 string. `length` should be equal to
    ## the length of the UTF-8 byte sequence, excluding any terminating
    ## zeroes.
    ##
    ## Raises an `IOError` on read errors.
    doPeekFileStream(fs): fs.readStr(length)


  proc raiseWriteError(fs: FileStream) =
    raise newException(IOError,
      fmt"cannot write to stream, filename: '{fs.filename}'")

  proc swapAndWrite[T: AllTypes](fs: FileStream, buf: openArray[T],
                                 startIndex, numValues: Natural) =
    var
      writeBuf {.noinit.}: array[WriteBufSize, T]
      valuesLeft = numValues
      bufIndex = startIndex

    while valuesLeft > 0:
      let valuesToWrite = min(valuesLeft, writeBuf.len)
      for i in 0..<valuesToWrite:
        when sizeof(T) == 1:
          writeBuf[i] = cast[T](swapBytes(cast[uint8](buf[bufIndex])))
        elif sizeof(T) == 2:
          writeBuf[i] = cast[T](swapBytes(cast[uint16](buf[bufIndex])))
        elif sizeof(T) == 4:
          writeBuf[i] = cast[T](swapBytes(cast[uint32](buf[bufIndex])))
        elif sizeof(T) == 8:
          writeBuf[i] = cast[T](swapBytes(cast[uint64](buf[bufIndex])))
        inc(bufIndex)

      let
        bytesToWrite = valuesToWrite * sizeof(T)
        bytesWritten = writeBuffer(fs.f, writeBuf[0].addr, bytesToWrite)

      if bytesWritten != bytesToWrite:
        raiseWriteError(fs)
      inc(fs.pos, bytesWritten)
      dec(valuesLeft, valuesToWrite)


  proc write*[T: AllTypes](fs: FileStream, buf: openArray[T],
                           startIndex, numValues: Natural) =
    ## Writes `numValues` number of values from `buf` starting from
    ## `startIndex` to the stream.
    ##
    ## Raises an `IOError` on write errors.
    fs.checkStreamOpen()
    if numValues == 0: return

    if system.cpuEndian == fs.endian:
      assert startIndex + numValues <= buf.len
      let
        bytesToWrite = numValues * sizeof(T)
        bytesWritten = writeBuffer(fs.f, buf[startIndex].unsafeAddr,
                                   bytesToWrite)
      if bytesWritten != bytesToWrite:
        raiseWriteError(fs)
      inc(fs.pos, bytesWritten)
    else:
      fs.swapAndWrite(buf, startIndex, numValues)

  proc write*[T: AllTypes](fs: FileStream, value: T) =
    ## Writes a single value to the stream. The width of the written item is
    ## the same as that of `value`.
    ##
    ## Raises an `IOError` on write errors.
    var buf {.noinit.}: array[1, T]
    buf[0] = value
    fs.write(buf, 0, 1)

  proc writeStr*(fs: FileStream, s: string) =
    ## Writes the UTF-8 byte sequence of a string to the stream. No
    ## terminating zero byte is written.
    ##
    ## Raises an `IOError` on write errors.
    fs.write(toOpenArrayByte(s, 0, s.len-1), 0, s.len)

  # }}}

# {{{ Memory stream

type
  MemStream* = ref object
    data*: seq[byte]
    pos: Natural
    endian: Endianness
    open: bool

proc newMemStream*(data: seq[byte], endian: Endianness): MemStream =
  ## Creates a new memory stream from a sequence of bytes with the given
  ## endianness. It is possible to change the endianness later on-the-fly.
  new(result)
  result.data = data
  result.endian = endian
  result.open = true

proc newMemStream*(endian: Endianness): MemStream =
  ## Creates a new memory stream with an empty internal buffer (typically for
  ## writing) with the given endianness. It is possible to change the
  ## endianness later on-the-fly.
  newMemStream(@[], endian)

proc close*(ms: MemStream) =
  ## Closes the memory stream.
  ms.data = @[]
  ms.open = false

proc checkStreamOpen(ms: MemStream) =
  if not ms.open:
    raise newException(IOError, "stream has been closed")

proc flush*(ms: MemStream) = ms.checkStreamOpen()
  ## `flush` is a no-op for memory streams.
  ##
  ## Raises an `IOError` if the stream is not open.

proc atEnd*(ms: MemStream): bool =
  ## Returns true if the stream position is at the last item of the underlying
  ## memory buffer.
  ##
  ## Raises an `IOError` if the stream is not open.
  ms.checkStreamOpen()
  ms.pos == ms.data.high

proc endian*(ms: MemStream): Endianness =
  ## Returns the current endianness.
  ms.endian

proc `endian=`*(ms: MemStream, endian: Endianness) =
  ## Sets the endianness (effective from the next read/write operation).
  ms.endian = endian

proc getPosition*(ms: MemStream): int64 =
  ## Gets the current read/write position of the memory stream.
  ##
  ## Raises an `IOError` if the stream is not open.
  ms.checkStreamOpen()
  ms.pos.int64

proc setPosition*(ms: MemStream, pos: int64,
                  relativeTo: StreamSeekPos = sspSet) =
  ## Sets the current read/write position of the memory stream.
  ##
  ## Raises an `IOError` if the stream is not open.
  ms.checkStreamOpen()

  let newPos = case relativeTo
  of sspSet: pos
  of sspCur: ms.pos + pos
  of sspEnd: ms.data.high + pos

  if newPos < 0:
    raise newException(IOError, fmt"cannot set stream position to {newPos}")
  ms.pos = newPos


proc read*[T: AllTypes](ms: MemStream, buf: var openArray[T],
                        startIndex, numValues: Natural) =
  ## Reads `numValues` number of values from the stream into `buf`, starting
  ## from `startIndex`.
  ##
  ## Raises an `IOError` if the stream is not open or if an attemp has been
  ## made to read past the end of the in-memory buffer.
  ms.checkStreamOpen()
  if numValues == 0: return

  if startIndex + numValues > buf.len:
    raise newException(IndexDefect,
      "Out of bounds: startIndex + numValues > bufLen " &
      fmt"(startIndex: {startIndex}, numValues: {numValues}, " &
      fmt"bufLen: {buf.len})")

  let numBytes = numValues * sizeof(T)
  if numBytes > ms.data.len - ms.pos:
    raise newException(IOError,
      fmt"cannot read past the end of the from stream")

  for i in 0..<numValues:
    let bufStart = ms.pos
    let bufEnd = bufStart + sizeof(T) - 1
    let src = ms.data[bufStart..bufEnd]
    when sizeof(T) == 1:
      buf[startIndex + i] = cast[T](fromBytes(uint8, src, ms.endian))
    elif sizeof(T) == 2:
      buf[startIndex + i] = cast[T](fromBytes(uint16, src, ms.endian))
    elif sizeof(T) == 4:
      buf[startIndex + i] = cast[T](fromBytes(uint32, src, ms.endian))
    elif sizeof(T) == 8:
      buf[startIndex + i] = cast[T](fromBytes(uint64, src, ms.endian))
    ms.pos += sizeof(T)


proc read*(ms: MemStream, T: typedesc[AllTypes]): T =
  ## Reads a single value of type `T` from the stream.
  ##
  ## Raises an `IOError` if the stream is not open or if an attemp has been
  ## made to read past the end of the in-memory buffer.
  var buf {.noinit.}: array[1, T]
  ms.read(buf, 0, 1)
  result = buf[0]

proc readStr*(ms: MemStream, length: Natural): string =
  ## Reads `length` number of bytes from the stream as an UTF-8 string.
  ## `length` should be equal to the number of bytes in the UTF-8 string,
  ## excluding any terminating zeroes.
  ##
  ## Raises an `IOError` if the stream is not open or if an attemp has been
  ## made to read past the end of the in-memory buffer.
  result = newString(length)
  ms.read(toOpenArrayByte(result, 0, result.high), 0, length)


template doPeekMemStream(ms: MemStream, body: untyped): untyped =
  let pos = ms.getPosition()
  defer: ms.setPosition(pos)
  body

proc peek*(ms: MemStream, T: typedesc[AllTypes]): T =
  ## Peeks (reads without advancing the file position) a single value of
  ## type `T` from the stream.
  ##
  ## Raises an `IOError` if the stream is not open or if an attemp has been
  ## made to read past the end of the in-memory buffer.
  doPeekMemStream(ms): ms.read(T)

proc peek*[T: AllTypes](ms: MemStream, buf: var openArray[T],
                        startIndex, numValues: Natural) =
  ## Peeks (reads without advancing the file position) `numValues` number of
  ## values into `buf` starting from `startIndex`.
  ##
  ## Raises an `IOError` if the stream is not open or if an attemp has been
  ## made to read past the end of the in-memory buffer.
  doPeekMemStream(ms): ms.read(buf, startIndex, numValues)

proc peekStr*(ms: MemStream, length: Natural): string =
  ## Peeks (reads without advancing the file position) `length` number of
  ## bytes from the stream as an UTF-8 string.  `length` should be equal to
  ## the the number of bytes in the UTF-8 string, excluding any terminating
  ## zeroes.
  ##
  ## Raises an `IOError` if the stream is not open or if an attemp has been
  ## made to read past the end of the in-memory buffer.
  doPeekMemStream(ms): ms.readStr(length)

proc write*[T: AllTypes](ms: MemStream, buf: openArray[T],
                         startIndex, numValues: Natural) =
  ## Writes `numValues` number of values from `buf` starting from
  ## `startIndex` to the stream.
  ##
  ## Raises an `IOError` if the memory stream is not open.
  ms.checkStreamOpen()
  if numValues == 0: return

  let capNeeded = ms.pos + numValues*sizeof(T) - ms.data.len
  if capNeeded > 0:
    ms.data.setLen(ms.data.len + capNeeded)

  for i in startIndex..<startIndex + numValues:
    var bytes: array[sizeof(T), byte]
    when sizeof(T) == 1: bytes[0] = cast[byte](buf[i])
    elif sizeof(T) == 2: bytes = toBytes(cast[uint16](buf[i]), ms.endian)
    elif sizeof(T) == 4: bytes = toBytes(cast[uint32](buf[i]), ms.endian)
    elif sizeof(T) == 8: bytes = toBytes(cast[uint64](buf[i]), ms.endian)

    ms.data[ms.pos..<ms.pos+sizeof(T)] = bytes
    inc(ms.pos, sizeof(T))


proc write*[T: AllTypes](ms: MemStream, value: T) =
  ## Writes a single value to the stream. The width of the written item
  ## is the same as that of `value`.
  ##
  ## Raises an `IOError` if the memory stream is not open.
  var buf {.noinit.}: array[1, T]
  buf[0] = value
  ms.write(buf, 0, 1)

proc writeStr*(ms: MemStream, s: string) =
  ## Writes the UTF-8 byte sequence of a string to the stream. No
  ## terminating zero character is written.
  ##
  ## Raises an `IOError` if the memory stream is not open.
  ms.write(toOpenArrayByte(s, 0, s.len-1), 0, s.len)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
