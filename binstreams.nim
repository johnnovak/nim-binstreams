import strformat
import strutils

import stew/endians2


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

  using fs: FileStream

  const
    ReadChunkSize = 512
    WriteBufSize = 512

  proc newFileStream*(f: File, endian: Endianness): FileStream =
    new(result)
    result.f = f
    result.endian = endian

  proc newFileStream*(filename: string, endian: Endianness,
                      mode: FileMode = fmRead,
                      bufSize: int = -1): FileStream =
    var f: File
    if open(f, filename, mode, bufSize):
      result = newFileStream(f, endian)
      result.filename = filename

  proc openFileStream*(filename: string, endian: Endianness,
                       mode: FileMode = fmRead,
                       bufSize: int = -1): FileStream =
    var f: File
    if open(f, filename, mode, bufSize):
      result = newFileStream(f, endian)
      result.filename = filename
    else:
      raise newException(IOError,
        fmt"cannot open file '{filename}' using mode {mode}")

  proc close*(fs) =
    if fs == nil:
      raise newException(IOError,
        "stream has already been closed or has not been properly initialised")
    if fs.f != nil: close(fs.f)
    fs.f = nil

  proc checkStreamOpen(fs) =
    if fs == nil:
      raise newException(IOError,
        "stream has been closed or has not been properly initialised")

  proc flush*(fs) =
    fs.checkStreamOpen()
    flushFile(fs.f)

  proc atEnd*(fs): bool =
    fs.checkStreamOpen()
    endOfFile(fs.f)

  proc filename*(fs): string = fs.filename

  proc endian*(fs): Endianness = fs.endian

  proc `endian=`*(fs; endian: Endianness) = fs.endian = endian

  proc getPosition*(fs): int64 =
    fs.checkStreamOpen()
    getFilePos(fs.f).int64

  proc setPosition*(fs; pos: int64, relativeTo: StreamSeekPos = sspSet) =
    fs.checkStreamOpen()
    setFilePos(fs.f, pos, toFileSeekPos(relativeTo))

  proc raiseReadError(fs) =
    raise newException(IOError,
      fmt"cannot read from stream, filename: '{fs.filename}'")

  proc readAndSwap[T: SomeNumber](fs; buf: var openArray[T],
                                  startIndex, numValues: Natural) =
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
      dec(valuesLeft, valuesRead)

      for i in bufIndex..<bufIndex + valuesRead:
        when sizeof(T) == 1: buf[i] = cast[T](swapBytes(cast[uint8 ](buf[i])))
        elif sizeof(T) == 2: buf[i] = cast[T](swapBytes(cast[uint16](buf[i])))
        elif sizeof(T) == 4: buf[i] = cast[T](swapBytes(cast[uint32](buf[i])))
        elif sizeof(T) == 8: buf[i] = cast[T](swapBytes(cast[uint64](buf[i])))
      inc(bufIndex, valuesRead)


  proc read*[T: SomeNumber](fs; buf: var openArray[T],
                            startIndex, numValues: Natural) =
    fs.checkStreamOpen()
    if system.cpuEndian == fs.endian:
      assert startIndex + numValues <= buf.len
      let
        bytesToRead = numValues * sizeof(T)
        bytesRead = readBuffer(fs.f, buf[startIndex].addr, bytesToRead)
      if bytesRead != bytesToRead:
        fs.raiseReadError()
    else:
      fs.readAndSwap(buf, startIndex, numValues)

  proc read*(fs; T: typedesc[SomeNumber]): T =
    var buf {.noinit.}: array[1, T]
    fs.read(buf, 0, 1)
    result = buf[0]

  proc readStr*(fs; length: Natural): string =
    result = newString(length)
    fs.read(toOpenArrayByte(result, 0, length-1), 0, length)

  proc readChar*(fs): char =
    result = cast[char](fs.read(byte))

  proc readBool*(fs): bool =
    result = fs.read(byte) != 0


  template doPeekFileStream(fs; body: untyped): untyped =
    let pos = fs.getPosition()
    defer: fs.setPosition(pos)
    body

  proc peek*(fs; T: typedesc[SomeNumber]): T =
    doPeekFileStream(fs): fs.read(T)

  proc peek*[T: SomeNumber](fs; buf: var openArray[T],
                            startIndex, numValues: Natural) =
    doPeekFileStream(fs): fs.read(buf, startIndex, numValues)

  proc peekStr*(fs; length: Natural): string =
    doPeekFileStream(fs): fs.readStr(length)

  proc peekChar*(fs): char =
    doPeekFileStream(fs): fs.readChar()

  proc peekBool*(fs): bool =
    doPeekFileStream(fs): fs.readBool()


  proc raiseWriteError(fs) =
    raise newException(IOError,
      fmt"cannot write to stream, filename: '{fs.filename}'")

  proc swapAndWrite[T: SomeNumber](fs; buf: openArray[T],
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
      dec(valuesLeft, valuesToWrite)


  proc write*[T: SomeNumber](fs; buf: openArray[T],
                             startIndex, numValues: Natural) =
    fs.checkStreamOpen()
    if system.cpuEndian == fs.endian:
      assert startIndex + numValues <= buf.len
      let
        bytesToWrite = numValues * sizeof(T)
        bytesWritten = writeBuffer(fs.f, buf[startIndex].unsafeAddr,
                                   bytesToWrite)
      if bytesWritten != bytesToWrite:
        raiseWriteError(fs)
    else:
      fs.swapAndWrite(buf, startIndex, numValues)

  proc write*[T: SomeNumber](fs; value: T) =
    var buf {.noinit.}: array[1, T]
    buf[0] = value
    fs.write(buf, 0, 1)

  proc writeStr*(fs; s: string) =
    fs.write(toOpenArrayByte(s, 0, s.len-1), 0, s.len)

  proc writeChar*(fs; ch: char) =
    fs.write(cast[byte](ch))

  proc writeBool*(fs; b: bool) =
    fs.write(cast[byte](b))

  # }}}
  # {{{ Byte stream

  type
    ByteStream* = ref object
      data*: seq[byte]
      pos: Natural
      endian: Endianness
      open: bool

  using bs: ByteStream

  proc newByteStream*(data: seq[byte], endian: Endianness): ByteStream =
    new(result)
    result.data = data
    result.endian = endian
    result.open = true

  proc newByteStream*(endian: Endianness): ByteStream =
    newByteStream(@[], endian)

  proc close*(bs) =
    bs.data = @[]
    bs.open = false

  proc checkStreamOpen(bs) =
    if not bs.open:
      raise newException(IOError, "stream has been closed")

  proc flush*(bs) = bs.checkStreamOpen()

  proc atEnd*(bs): bool =
    bs.checkStreamOpen()
    bs.pos == bs.data.high

  proc endian*(bs): Endianness = bs.endian

  proc `endian=`*(bs; endian: Endianness) = bs.endian = endian

  proc getPosition*(bs): int64 =
    bs.checkStreamOpen()
    bs.pos.int64


  proc setPosition*(bs; pos: int64, relativeTo: StreamSeekPos = sspSet) =
    bs.checkStreamOpen()

    let newPos = case relativeTo
    of sspSet: pos
    of sspCur: bs.pos + pos
    of sspEnd: bs.data.high + pos

    if newPos < 0:
      raise newException(IOError, fmt"cannot set stream position to {newPos}")
    bs.pos = newPos


  proc read*[T: SomeNumber](bs; buf: var openArray[T],
                            startIndex, numValues: Natural) =
    bs.checkStreamOpen()
    if numValues == 0: return

    if startIndex + numValues > buf.len:
      raise newException(IndexError,
        "Out of bounds: startIndex + numValues > bufLen " &
        fmt"(startIndex: {startIndex}, numValues: {numValues}, " &
        fmt"bufLen: {buf.len})")

    let numBytes = numValues * sizeof(T)
    if numBytes > bs.data.len - bs.pos:
      raise newException(IOError, fmt"cannot read from stream")

    for i in 0..<numValues:
      let bufStart = bs.pos
      let bufEnd = bufStart + sizeof(T) - 1
      let src = bs.data[bufStart..bufEnd]
      when sizeof(T) == 1:
        buf[startIndex + i] = cast[T](fromBytes(uint8, src, bs.endian))
      elif sizeof(T) == 2:
        buf[startIndex + i] = cast[T](fromBytes(uint16, src, bs.endian))
      elif sizeof(T) == 4:
        buf[startIndex + i] = cast[T](fromBytes(uint32, src, bs.endian))
      elif sizeof(T) == 8:
        buf[startIndex + i] = cast[T](fromBytes(uint64, src, bs.endian))
      bs.pos += sizeof(T)


  proc read*(bs; T: typedesc[SomeNumber]): T =
    var buf {.noinit.}: array[1, T]
    bs.read(buf, 0, 1)
    result = buf[0]

  proc readStr*(bs; length: Natural): string =
    result = newString(length)
    bs.read(toOpenArrayByte(result, 0, result.high), 0, length)

  proc readChar*(bs): char =
    result = cast[char](bs.read(byte))

  proc readBool*(bs): bool =
    result = bs.read(byte) != 0


  template doPeekByteStream(bs; body: untyped): untyped =
    let pos = bs.getPosition()
    defer: bs.setPosition(pos)
    body

  proc peek*(bs; T: typedesc[SomeNumber]): T =
    doPeekByteStream(bs): bs.read(T)

  proc peek*[T: SomeNumber](bs; buf: var openArray[T],
                            startIndex, numValues: Natural) =
    doPeekByteStream(bs): bs.read(buf, startIndex, numValues)

  proc peekStr*(bs; length: Natural): string =
    doPeekByteStream(bs): bs.readStr(length)

  proc peekChar*(bs): char =
    doPeekByteStream(bs): bs.readChar()

  proc peekBool*(bs): bool =
    doPeekByteStream(bs): bs.readBool()

  proc write*[T: SomeNumber](bs; buf: openArray[T],
                             startIndex, numValues: Natural) =
    bs.checkStreamOpen()
    if numValues == 0: return

    let capNeeded = bs.pos + numValues*sizeof(T) - bs.data.len
    if capNeeded > 0:
      bs.data.setLen(bs.data.len + capNeeded)

    for i in startIndex..<startIndex + numValues:
      var bytes: array[sizeof(T), byte]
      when sizeof(T) == 1: bytes[0] = cast[byte](buf[i])
      elif sizeof(T) == 2: bytes = toBytes(cast[uint16](buf[i]), bs.endian)
      elif sizeof(T) == 4: bytes = toBytes(cast[uint32](buf[i]), bs.endian)
      elif sizeof(T) == 8: bytes = toBytes(cast[uint64](buf[i]), bs.endian)

      bs.data[bs.pos..<bs.pos+sizeof(T)] = bytes
      inc(bs.pos, sizeof(T))


  proc write*[T: SomeNumber](bs; value: T) =
    var buf {.noinit.}: array[1, T]
    buf[0] = value
    bs.write(buf, 0, 1)

  proc writeStr*(bs; s: string) =
    bs.write(toOpenArrayByte(s, 0, s.len-1), 0, s.len)

  proc writeChar*(bs; ch: char) =
    bs.write(cast[byte](ch))

  proc writeBool*(bs; b: bool) =
    bs.write(cast[byte](b))

  # }}}

when isMainModule:
  import os

  const
    TestFileBE = "endians-testdata-BE"
    TestFileLE = "endians-testdata-LE"
    TestFileBigBE = "endians-testdata-big-BE"
    TestFileBigLE = "endians-testdata-big-LE"
    TestFile = "endians-testfile"

  const
    TestFloat64 = 123456789.123456'f64
    TestFloat32 = 1234.1234'f32
    MagicValue64_1 = 0xdeadbeefcafebabe'u64
    MagicValue64_2 = 0xfeedface0d15ea5e'u64
    TestString = "Some girls wander by mistake"
    TestChar = char(42)
    TestBooleans = @[-127'i8, -1'i8, 0'i8, 1'i8, 127'i8]

  # {{{ Test data file creation
  block:
    var outf = open(TestFileBE, fmWrite)
    var buf: array[2, uint64]
    buf[0] = toBE(MagicValue64_1)
    buf[1] = toBE(MagicValue64_2)
    discard writeBuffer(outf, buf[0].addr, 16)

    var f32 = cast[float32](toBE(cast[uint32](TestFloat32)))
    discard writeBuffer(outf, f32.addr, 4)
    var f64 = cast[float64](toBE(cast[uint64](TestFloat64)))
    discard writeBuffer(outf, f64.addr, 8)

    var str = TestString
    discard writeBuffer(outf, str[0].unsafeAddr, str.len)
    var ch = TestChar
    discard writeBuffer(outf, ch.unsafeAddr, 1)
    discard writeBytes(outf, TestBooleans, 0, TestBooleans.len)
    close(outf)

  block:
    var outf = open(TestFileLE, fmWrite)
    var buf: array[2, uint64]
    buf[0] = toLE(MagicValue64_1)
    buf[1] = toLE(MagicValue64_2)
    discard writeBuffer(outf, buf[0].addr, 16)

    var f32 = cast[float32](toLE(cast[uint32](TestFloat32)))
    discard writeBuffer(outf, f32.addr, 4)
    var f64 = cast[float64](toLE(cast[uint64](TestFloat64)))
    discard writeBuffer(outf, f64.addr, 8)

    var str = TestString
    discard writeBuffer(outf, str[0].unsafeAddr, str.len)
    var ch = TestChar
    discard writeBuffer(outf, ch.unsafeAddr, 1)
    discard writeBytes(outf, TestBooleans, 0, TestBooleans.len)
    close(outf)

  block:
    var outf = open(TestFileBigBE, fmWrite)
    var u64: uint64
    for i in 0..<ReadChunkSize*3:
      u64 = toBE(MagicValue64_1 + i.uint64)
      discard writeBuffer(outf, u64.addr, 8)
    close(outf)

  block:
    var outf = open(TestFileBigLE, fmWrite)
    var u64: uint64
    for i in 0..<ReadChunkSize*3:
      u64 = toLE(MagicValue64_1 + i.uint64)
      discard writeBuffer(outf, u64.addr, 8)
    close(outf)

  # }}}
  # {{{ Test byte buffer creation
  # Big endian
  var testByteBufBE: seq[byte]

  testByteBufBE.add(cast[array[8, byte]](toBE(MagicValue64_1)))
  testByteBufBE.add(cast[array[8, byte]](toBE(MagicValue64_2)))
  testByteBufBE.add(cast[array[4, byte]](toBE(cast[uint32](TestFloat32))))
  testByteBufBE.add(cast[array[8, byte]](toBE(cast[uint64](TestFloat64))))

  for c in TestString:
    testByteBufBE.add(c.byte)

  testByteBufBE.add(TestChar.byte)
  testByteBufBE.add(cast[seq[byte]](TestBooleans))

  var testByteBufBigBE: seq[byte]

  for i in 0..<ReadChunkSize*3:
    testByteBufBigBE.add(
      cast[array[8, byte]](
        toBE(cast[uint64](MagicValue64_1 + i.uint64))))

  # Little endian
  var testByteBufLE: seq[byte]

  testByteBufLE.add(cast[array[8, byte]](toLE(MagicValue64_1)))
  testByteBufLE.add(cast[array[8, byte]](toLE(MagicValue64_2)))
  testByteBufLE.add(cast[array[4, byte]](toLE(cast[uint32](TestFloat32))))
  testByteBufLE.add(cast[array[8, byte]](toLE(cast[uint64](TestFloat64))))

  for c in TestString:
    testByteBufLE.add(c.byte)

  testByteBufLE.add(TestChar.byte)
  testByteBufLE.add(cast[seq[byte]](TestBooleans))

  var testByteBufBigLE: seq[byte]

  for i in 0..<ReadChunkSize*3:
    testByteBufBigLE.add(
      cast[array[8, byte]](
        toLE(cast[uint64](MagicValue64_1 + i.uint64))))

  # }}}

  block: # {{{ Common / Big endian
    block: # {{{ read/func
      template tests(s: untyped) =
        assert s.read(int8)   == 0xde'i8
        assert s.read(int8)   == 0xad'i8
        s.setPosition(0)
        assert s.read(uint8)  == 0xde'u8
        assert s.read(uint8)  == 0xad'u8
        s.setPosition(0)
        assert s.read(int16)  == 0xdead'i16
        assert s.read(int16)  == 0xbeef'i16
        s.setPosition(0)
        assert s.read(uint16) == 0xdead'u16
        assert s.read(uint16) == 0xbeef'u16
        s.setPosition(0)
        assert s.read(int32)  == 0xdeadbeef'i32
        assert s.read(int32)  == 0xcafebabe'i32
        s.setPosition(0)
        assert s.read(uint32) == 0xdeadbeef'u32
        assert s.read(uint32) == 0xcafebabe'u32
        s.setPosition(0)
        assert s.read(int64)  == 0xdeadbeefcafebabe'i64
        assert s.read(int64)  == 0xfeedface0d15ea5e'i64
        s.setPosition(0)
        assert s.read(uint64) == 0xdeadbeefcafebabe'u64
        assert s.read(uint64) == 0xfeedface0d15ea5e'u64
        s.setPosition(0)
        assert s.read(uint64) == 0xdeadbeefcafebabe'u64
        assert s.read(uint64) == 0xfeedface0d15ea5e'u64

        assert s.read(float32) == TestFloat32
        assert s.read(float64) == TestFloat64
        assert s.getPosition == 28

        assert s.readStr(TestString.len) == TestString
        assert s.readChar() == TestChar
        assert s.readBool() == true
        assert s.readBool() == true
        assert s.readBool() == false
        assert s.readBool() == true
        assert s.readBool() == true

      var fs = newFileStream(TestFileBE, bigEndian)
      tests(fs)
      fs.close()

      var bs = newByteStream(testByteBufBE, bigEndian)
      tests(bs)
      bs.close()

    # }}}
    block: # {{{ peek/func
      template tests(s: untyped) =
        assert s.peek(int8)   == 0xde'i8
        assert s.peek(int8)   == 0xde'i8
        assert s.peek(uint8)  == 0xde'u8
        assert s.peek(uint8)  == 0xde'u8
        assert s.peek(int16)  == 0xdead'i16
        assert s.peek(int16)  == 0xdead'i16
        assert s.peek(uint16) == 0xdead'u16
        assert s.peek(uint16) == 0xdead'u16
        assert s.peek(int32)  == 0xdeadbeef'i32
        assert s.peek(int32)  == 0xdeadbeef'i32
        assert s.peek(uint32) == 0xdeadbeef'u32
        assert s.peek(uint32) == 0xdeadbeef'u32
        assert s.peek(int64)  == 0xdeadbeefcafebabe'i64
        assert s.peek(int64)  == 0xdeadbeefcafebabe'i64
        assert s.peek(uint64) == 0xdeadbeefcafebabe'u64
        assert s.peek(uint64) == 0xdeadbeefcafebabe'u64
        assert s.getPosition() == 0

        s.setPosition(16)
        assert s.peek(float32) == TestFloat32
        s.setPosition(20)
        assert s.peek(float64) == TestFloat64
        assert s.getPosition() == 20

        s.setPosition(28)
        assert s.peekStr(TestString.len) == TestString
        s.setPosition(TestString.len, sspCur)
        assert s.peekChar() == TestChar; s.setPosition(1, sspCur)
        assert s.peekBool() == true;     s.setPosition(1, sspCur)
        assert s.peekBool() == true;     s.setPosition(1, sspCur)
        assert s.peekBool() == false;    s.setPosition(1, sspCur)
        assert s.peekBool() == true;     s.setPosition(1, sspCur)
        assert s.peekBool() == true

      var fs = newFileStream(TestFileBE, bigEndian)
      tests(fs)
      fs.close()

      var bs = newByteStream(testByteBufBE, bigEndian)
      tests(bs)
      bs.close()

    # }}}
    block: # {{{ read/openArray
      template tests(s: untyped) =
        var arr_i8: array[4, int8]

        s.read(arr_i8, 1, 2)
        assert arr_i8[0] == 0
        assert arr_i8[1] == 0xde'i8
        assert arr_i8[2] == 0xad'i8
        assert arr_i8[3] == 0

        var arr_u8: array[4, uint8]
        s.setPosition(0)
        s.read(arr_u8, 1, 2)
        assert arr_u8[0] == 0
        assert arr_u8[1] == 0xde'u8
        assert arr_u8[2] == 0xad'u8
        assert arr_u8[3] == 0

        var arr_i16: array[4, int16]
        s.setPosition(0)
        s.read(arr_i16, 1, 2)
        assert arr_i16[0] == 0
        assert arr_i16[1] == 0xdead'i16
        assert arr_i16[2] == 0xbeef'i16
        assert arr_i16[3] == 0

        var arr_u16: array[4, uint16]
        s.setPosition(0)
        s.read(arr_u16, 1, 2)
        assert arr_u16[0] == 0
        assert arr_u16[1] == 0xdead'u16
        assert arr_u16[2] == 0xbeef'u16
        assert arr_u16[3] == 0

        var arr_i32: array[4, int32]
        s.setPosition(0)
        s.read(arr_i32, 1, 2)
        assert arr_i32[0] == 0
        assert arr_i32[1] == 0xdeadbeef'i32
        assert arr_i32[2] == 0xcafebabe'i32
        assert arr_i32[3] == 0

        var arr_u32: array[4, uint32]
        s.setPosition(0)
        s.read(arr_u32, 1, 2)
        assert arr_u32[0] == 0
        assert arr_u32[1] == 0xdeadbeef'u32
        assert arr_u32[2] == 0xcafebabe'u32
        assert arr_u32[3] == 0

        var arr_i64: array[4, int64]
        s.setPosition(0)
        s.read(arr_i64, 1, 2)
        assert arr_i64[0] == 0
        assert arr_i64[1] == 0xdeadbeefcafebabe'i64
        assert arr_i64[2] == 0xfeedface0d15ea5e'i64
        assert arr_i64[3] == 0

        var arr_u64: array[4, uint64]
        s.setPosition(0)
        s.read(arr_u64, 1, 2)
        assert arr_u64[0] == 0
        assert arr_u64[1] == 0xdeadbeefcafebabe'u64
        assert arr_u64[2] == 0xfeedface0d15ea5e'u64
        assert arr_u64[3] == 0

        var arr_f32: array[3, float32]
        s.read(arr_f32, 1, 1)
        assert arr_f32[0] == 0
        assert arr_f32[1] == TestFloat32
        assert arr_f32[2] == 0

        var arr_f64: array[3, float64]
        s.read(arr_f64, 1, 1)
        assert arr_f64[0] == 0
        assert arr_f64[1] == TestFloat64
        assert arr_f64[2] == 0

        assert s.getPosition() == 28

      var fs = newFileStream(TestFileBE, bigEndian)
      tests(fs)
      fs.close()

      var bs = newByteStream(testByteBufBE, bigEndian)
      tests(bs)
      bs.close()

      template readBufTest(s: untyped, numValues: Natural) =
        var buf: array[ReadChunkSize*3, uint64]
        let offs = 123

        s.read(buf, offs, numValues)

        for i in 0..<offs:
          assert buf[i] == 0
        for i in 0..<numValues:
          assert buf[offs + i] == MagicValue64_1 + i.uint64
        for i in offs+numValues..buf.high:
          assert buf[i] == 0

      template readBufTest_FileStream(numValues: Natural) =
        fs = newFileStream(TestFileBigBE, bigEndian)
        readBufTest(fs, numValues)
        fs.close()

      readBufTest_FileStream(0)
      readBufTest_FileStream(10)
      readBufTest_FileStream(ReadChunkSize)
      readBufTest_FileStream(ReadChunkSize * 2)
      readBufTest_FileStream(ReadChunkSize + 10)

      template readBufTest_ByteStream(numValues: Natural) =
        var bs = newByteStream(testByteBufBigBE, bigEndian)
        readBufTest(bs, numValues)
        bs.close()

      readBufTest_ByteStream(0)
      readBufTest_ByteStream(10)
      readBufTest_ByteStream(ReadChunkSize)
      readBufTest_ByteStream(ReadChunkSize * 2)
      readBufTest_ByteStream(ReadChunkSize + 10)

    # }}}
    block: # {{{ peek/openArray
      template tests(s: untyped) =
        var arr_i8: array[4, int8]
        s.peek(arr_i8, 1, 2)
        assert arr_i8[0] == 0
        assert arr_i8[1] == 0xde'i8
        assert arr_i8[2] == 0xad'i8
        assert arr_i8[3] == 0

        var arr_u8: array[4, uint8]
        s.peek(arr_u8, 1, 2)
        assert arr_u8[0] == 0
        assert arr_u8[1] == 0xde'u8
        assert arr_u8[2] == 0xad'u8
        assert arr_u8[3] == 0

        var arr_i16: array[4, int16]
        s.peek(arr_i16, 1, 2)
        assert arr_i16[0] == 0
        assert arr_i16[1] == 0xdead'i16
        assert arr_i16[2] == 0xbeef'i16
        assert arr_i16[3] == 0

        var arr_u16: array[4, uint16]
        s.peek(arr_u16, 1, 2)
        assert arr_u16[0] == 0
        assert arr_u16[1] == 0xdead'u16
        assert arr_u16[2] == 0xbeef'u16
        assert arr_u16[3] == 0

        var arr_i32: array[4, int32]
        s.peek(arr_i32, 1, 2)
        assert arr_i32[0] == 0
        assert arr_i32[1] == 0xdeadbeef'i32
        assert arr_i32[2] == 0xcafebabe'i32
        assert arr_i32[3] == 0

        var arr_u32: array[4, uint32]
        s.peek(arr_u32, 1, 2)
        assert arr_u32[0] == 0
        assert arr_u32[1] == 0xdeadbeef'u32
        assert arr_u32[2] == 0xcafebabe'u32
        assert arr_u32[3] == 0

        var arr_i64: array[4, int64]
        s.peek(arr_i64, 1, 2)
        assert arr_i64[0] == 0
        assert arr_i64[1] == 0xdeadbeefcafebabe'i64
        assert arr_i64[2] == 0xfeedface0d15ea5e'i64
        assert arr_i64[3] == 0

        var arr_u64: array[4, uint64]
        s.peek(arr_u64, 1, 2)
        assert arr_u64[0] == 0
        assert arr_u64[1] == 0xdeadbeefcafebabe'u64
        assert arr_u64[2] == 0xfeedface0d15ea5e'u64
        assert arr_u64[3] == 0

        assert s.getPosition() == 0
        s.setPosition(16)
        var arr_f32: array[3, float32]
        s.peek(arr_f32, 1, 1)
        assert arr_f32[0] == 0
        assert arr_f32[1] == TestFloat32
        assert arr_f32[2] == 0

        s.setPosition(20)
        var arr_f64: array[3, float64]
        s.peek(arr_f64, 1, 1)
        assert arr_f64[0] == 0
        assert arr_f64[1] == TestFloat64
        assert arr_f64[2] == 0

        assert s.getPosition() == 20

      var fs = newFileStream(TestFileBE, bigEndian)
      tests(fs)
      fs.close()

      var bs = newByteStream(testByteBufBE, bigEndian)
      tests(bs)
      bs.close()

      template readBufTest(s: untyped, numValues: Natural) =
        var buf: array[ReadChunkSize*3, uint64]
        let offs = 123

        for n in 0..3:
          s.peek(buf, offs, numValues)

          for i in 0..<offs:
            assert buf[i] == 0
          for i in 0..<numValues:
            assert buf[offs + i] == MagicValue64_1 + i.uint64
          for i in offs+numValues..buf.high:
            assert buf[i] == 0

        assert s.getPosition() == 0

      template readBufTest_FileStream(numValues: Natural) =
        var fs = newFileStream(TestFileBigBE, bigEndian)
        readBufTest(fs, numValues)
        fs.close()

      readBufTest_FileStream(0)
      readBufTest_FileStream(10)
      readBufTest_FileStream(ReadChunkSize)
      readBufTest_FileStream(ReadChunkSize * 2)
      readBufTest_FileStream(ReadChunkSize + 10)

      template readBufTest_ByteStream(numValues: Natural) =
        var bs = newByteStream(testByteBufBigBE, bigEndian)
        readBufTest(bs, numValues)
        bs.close()

      readBufTest_ByteStream(0)
      readBufTest_ByteStream(10)
      readBufTest_ByteStream(ReadChunkSize)
      readBufTest_ByteStream(ReadChunkSize * 2)
      readBufTest_ByteStream(ReadChunkSize + 10)

    # }}}
    block: # {{{ write/func
      template tests_write(s: untyped) =
        s.write(0xde'i8)
        s.write(0xad'u8)
        s.write(0xdead'i16)
        s.write(0xbeef'u16)
        s.write(0xdeadbeef'i32)
        s.write(0xcafebabe'u32)
        s.write(0xdeadbeefcafebabe'i64)
        s.write(0xfeedface0d15ea5e'u64)
        s.write(TestFloat32)
        s.write(TestFloat64)
        s.writeStr(TestString)
        s.writeChar(TestChar)
        s.writeBool(true)
        s.writeBool(false)

      template tests_read(s: untyped) =
        assert s.read(int8)    == 0xde'i8
        assert s.read(uint8)   == 0xad'u8
        assert s.read(int16)   == 0xdead'i16
        assert s.read(uint16)  == 0xbeef'u16
        assert s.read(int32)   == 0xdeadbeef'i32
        assert s.read(uint32)  == 0xcafebabe'u32
        assert s.read(int64)   == 0xdeadbeefcafebabe'i64
        assert s.read(uint64)  == 0xfeedface0d15ea5e'u64
        assert s.read(float32) == TestFloat32
        assert s.read(float64) == TestFloat64
        assert s.readStr(TestString.len) == TestString
        assert s.readChar() == TestChar
        assert s.readBool() == true
        assert s.readBool() == false

      var fs = newFileStream(TestFileBE, bigEndian, fmWrite)
      tests_write(fs)
      fs.close()

      fs = newFileStream(TestFileBE, bigEndian)
      tests_read(fs)
      fs.close()

      var bs = newByteStream(bigEndian)
      tests_write(bs)

      var bs2 = newByteStream(bs.data, bigEndian)
      bs.close()
      tests_read(bs2)
      bs2.close()

    # }}}
    block: # {{{ write/openArray
      const offs = 123

      var buf: array[WriteBufSize*3, uint64]
      for i in 0..buf.high:
        buf[i] = MagicValue64_1 + i.uint64

      template writeTestStream(s: untyped, numValues: Natural) =
        s.write(buf, offs, numValues)

      template assertTestStream(s: untyped, numValues: Natural) =
        var readBuf: array[WriteBufSize*3, uint64]
        s.read(readBuf, offs, numValues)
        for i in 0..<numValues:
          assert readBuf[offs + i] == buf[offs + i]

      proc writeBufTest_FileStream(numValues: Natural) =
        var s = newFileStream(TestFile, bigEndian, fmWrite)
        writeTestStream(s, numValues)
        s.close()
        s = newFileStream(TestFile, bigEndian)
        assertTestStream(s, numValues)
        s.close()

      proc writeBufTest_ByteStream(numValues: Natural) =
        var s = newByteStream(bigEndian)
        writeTestStream(s, numValues)
        var s2 = newByteStream(s.data, bigEndian)
        s.close()
        assertTestStream(s2, numValues)
        s2.close()

      writeBufTest_FileStream(0)
      writeBufTest_FileStream(10)
      writeBufTest_FileStream(WriteBufSize)
      writeBufTest_FileStream(WriteBufSize * 2)
      writeBufTest_FileStream(WriteBufSize + 10)

      writeBufTest_ByteStream(0)
      writeBufTest_ByteStream(10)
      writeBufTest_ByteStream(WriteBufSize)
      writeBufTest_ByteStream(WriteBufSize * 2)
      writeBufTest_ByteStream(WriteBufSize + 10)

    # }}}
  # }}}
  block: # {{{ Common / Little endian
    block: # {{{ read/func
      template tests(s: untyped) =
        assert s.read(int8)   == 0xbe'i8
        assert s.read(int8)   == 0xba'i8
        s.setPosition(0)
        assert s.read(uint8)  == 0xbe'u8
        assert s.read(uint8)  == 0xba'u8
        s.setPosition(0)
        assert s.read(int16)  == 0xbabe'i16
        assert s.read(int16)  == 0xcafe'i16
        s.setPosition(0)
        assert s.read(uint16) == 0xbabe'u16
        assert s.read(uint16) == 0xcafe'u16
        s.setPosition(0)
        assert s.read(int32)  == 0xcafebabe'i32
        assert s.read(int32)  == 0xdeadbeef'i32
        s.setPosition(0)
        assert s.read(uint32) == 0xcafebabe'u32
        assert s.read(uint32) == 0xdeadbeef'u32
        s.setPosition(0)
        assert s.read(int64)  == 0xdeadbeefcafebabe'i64
        assert s.read(int64)  == 0xfeedface0d15ea5e'i64
        s.setPosition(0)
        assert s.read(uint64) == 0xdeadbeefcafebabe'u64
        assert s.read(uint64) == 0xfeedface0d15ea5e'u64
        s.setPosition(0)
        assert s.read(uint64) == 0xdeadbeefcafebabe'u64
        assert s.read(uint64) == 0xfeedface0d15ea5e'u64

        assert s.read(float32) == TestFloat32
        assert s.read(float64) == TestFloat64
        assert s.getPosition == 28

        assert s.readStr(TestString.len) == TestString
        assert s.readChar() == TestChar
        assert s.readBool() == true
        assert s.readBool() == true
        assert s.readBool() == false
        assert s.readBool() == true
        assert s.readBool() == true

      var fs = newFileStream(TestFileLE, littleEndian)
      tests(fs)
      fs.close()

      var bs = newByteStream(testByteBufLE, littleEndian)
      tests(bs)
      bs.close()

    # }}}
    block: # {{{ peek/func
      template tests(s: untyped) =
        assert s.peek(int8)   == 0xbe'i8
        assert s.peek(int8)   == 0xbe'i8
        assert s.peek(uint8)  == 0xbe'u8
        assert s.peek(uint8)  == 0xbe'u8
        assert s.peek(int16)  == 0xbabe'i16
        assert s.peek(int16)  == 0xbabe'i16
        assert s.peek(uint16) == 0xbabe'u16
        assert s.peek(uint16) == 0xbabe'u16
        assert s.peek(int32)  == 0xcafebabe'i32
        assert s.peek(int32)  == 0xcafebabe'i32
        assert s.peek(uint32) == 0xcafebabe'u32
        assert s.peek(uint32) == 0xcafebabe'u32
        assert s.peek(int64)  == 0xdeadbeefcafebabe'i64
        assert s.peek(int64)  == 0xdeadbeefcafebabe'i64
        assert s.peek(uint64) == 0xdeadbeefcafebabe'u64
        assert s.peek(uint64) == 0xdeadbeefcafebabe'u64
        assert s.getPosition() == 0

        s.setPosition(16)
        assert s.peek(float32) == TestFloat32
        s.setPosition(20)
        assert s.peek(float64) == TestFloat64
        assert s.getPosition() == 20

        s.setPosition(28)
        assert s.peekStr(TestString.len) == TestString
        s.setPosition(TestString.len, sspCur)
        assert s.peekChar() == TestChar; s.setPosition(1, sspCur)
        assert s.peekBool() == true;     s.setPosition(1, sspCur)
        assert s.peekBool() == true;     s.setPosition(1, sspCur)
        assert s.peekBool() == false;    s.setPosition(1, sspCur)
        assert s.peekBool() == true;     s.setPosition(1, sspCur)
        assert s.peekBool() == true

      var fs = newFileStream(TestFileLE, littleEndian)
      tests(fs)
      fs.close()

      var bs = newByteStream(testByteBufLE, littleEndian)
      tests(bs)
      bs.close()

    # }}}
    block: # {{{ read/openArray
      template tests(s: untyped) =
        var arr_i8: array[4, int8]

        s.read(arr_i8, 1, 2)
        assert arr_i8[0] == 0
        assert arr_i8[1] == 0xbe'i8
        assert arr_i8[2] == 0xba'i8
        assert arr_i8[3] == 0

        var arr_u8: array[4, uint8]
        s.setPosition(0)
        s.read(arr_u8, 1, 2)
        assert arr_u8[0] == 0
        assert arr_u8[1] == 0xbe'u8
        assert arr_u8[2] == 0xba'u8
        assert arr_u8[3] == 0

        var arr_i16: array[4, int16]
        s.setPosition(0)
        s.read(arr_i16, 1, 2)
        assert arr_i16[0] == 0
        assert arr_i16[1] == 0xbabe'i16
        assert arr_i16[2] == 0xcafe'i16
        assert arr_i16[3] == 0

        var arr_u16: array[4, uint16]
        s.setPosition(0)
        s.read(arr_u16, 1, 2)
        assert arr_u16[0] == 0
        assert arr_u16[1] == 0xbabe'u16
        assert arr_u16[2] == 0xcafe'u16
        assert arr_u16[3] == 0

        var arr_i32: array[4, int32]
        s.setPosition(0)
        s.read(arr_i32, 1, 2)
        assert arr_i32[0] == 0
        assert arr_i32[1] == 0xcafebabe'i32
        assert arr_i32[2] == 0xdeadbeef'i32
        assert arr_i32[3] == 0

        var arr_u32: array[4, uint32]
        s.setPosition(0)
        s.read(arr_u32, 1, 2)
        assert arr_u32[0] == 0
        assert arr_u32[1] == 0xcafebabe'u32
        assert arr_u32[2] == 0xdeadbeef'u32
        assert arr_u32[3] == 0

        var arr_i64: array[4, int64]
        s.setPosition(0)
        s.read(arr_i64, 1, 2)
        assert arr_i64[0] == 0
        assert arr_i64[1] == 0xdeadbeefcafebabe'i64
        assert arr_i64[2] == 0xfeedface0d15ea5e'i64
        assert arr_i64[3] == 0

        var arr_u64: array[4, uint64]
        s.setPosition(0)
        s.read(arr_u64, 1, 2)
        assert arr_u64[0] == 0
        assert arr_u64[1] == 0xdeadbeefcafebabe'u64
        assert arr_u64[2] == 0xfeedface0d15ea5e'u64
        assert arr_u64[3] == 0

        var arr_f32: array[3, float32]
        s.read(arr_f32, 1, 1)
        assert arr_f32[0] == 0
        assert arr_f32[1] == TestFloat32
        assert arr_f32[2] == 0

        var arr_f64: array[3, float64]
        s.read(arr_f64, 1, 1)
        assert arr_f64[0] == 0
        assert arr_f64[1] == TestFloat64
        assert arr_f64[2] == 0

        assert s.getPosition() == 28

      var fs = newFileStream(TestFileLE, littleEndian)
      tests(fs)
      fs.close()

      var bs = newByteStream(testByteBufLE, littleEndian)
      tests(bs)
      bs.close()

      template readBufTest(s: untyped, numValues: Natural) =
        var buf: array[ReadChunkSize*3, uint64]
        let offs = 123

        s.read(buf, offs, numValues)

        for i in 0..<offs:
          assert buf[i] == 0
        for i in 0..<numValues:
          assert buf[offs + i] == MagicValue64_1 + i.uint64
        for i in offs+numValues..buf.high:
          assert buf[i] == 0

      template readBufTest_FileStream(numValues: Natural) =
        fs = newFileStream(TestFileBigLE, littleEndian)
        readBufTest(fs, numValues)
        fs.close()

      readBufTest_FileStream(0)
      readBufTest_FileStream(10)
      readBufTest_FileStream(ReadChunkSize)
      readBufTest_FileStream(ReadChunkSize * 2)
      readBufTest_FileStream(ReadChunkSize + 10)

      template readBufTest_ByteStream(numValues: Natural) =
        var bs = newByteStream(testByteBufBigLE, littleEndian)
        readBufTest(bs, numValues)
        bs.close()

      readBufTest_ByteStream(0)
      readBufTest_ByteStream(10)
      readBufTest_ByteStream(ReadChunkSize)
      readBufTest_ByteStream(ReadChunkSize * 2)
      readBufTest_ByteStream(ReadChunkSize + 10)

    # }}}
    block: # {{{ peek/openArray
      template tests(s: untyped) =
        var arr_i8: array[4, int8]
        s.peek(arr_i8, 1, 2)
        assert arr_i8[0] == 0
        assert arr_i8[1] == 0xbe'i8
        assert arr_i8[2] == 0xba'i8
        assert arr_i8[3] == 0

        var arr_u8: array[4, uint8]
        s.peek(arr_u8, 1, 2)
        assert arr_u8[0] == 0
        assert arr_u8[1] == 0xbe'u8
        assert arr_u8[2] == 0xba'u8
        assert arr_u8[3] == 0

        var arr_i16: array[4, int16]
        s.peek(arr_i16, 1, 2)
        assert arr_i16[0] == 0
        assert arr_i16[1] == 0xbabe'i16
        assert arr_i16[2] == 0xcafe'i16
        assert arr_i16[3] == 0

        var arr_u16: array[4, uint16]
        s.peek(arr_u16, 1, 2)
        assert arr_u16[0] == 0
        assert arr_u16[1] == 0xbabe'u16
        assert arr_u16[2] == 0xcafe'u16
        assert arr_u16[3] == 0

        var arr_i32: array[4, int32]
        s.peek(arr_i32, 1, 2)
        assert arr_i32[0] == 0
        assert arr_i32[1] == 0xcafebabe'i32
        assert arr_i32[2] == 0xdeadbeef'i32
        assert arr_i32[3] == 0

        var arr_u32: array[4, uint32]
        s.peek(arr_u32, 1, 2)
        assert arr_u32[0] == 0
        assert arr_u32[1] == 0xcafebabe'u32
        assert arr_u32[2] == 0xdeadbeef'u32
        assert arr_u32[3] == 0

        var arr_i64: array[4, int64]
        s.peek(arr_i64, 1, 2)
        assert arr_i64[0] == 0
        assert arr_i64[1] == 0xdeadbeefcafebabe'i64
        assert arr_i64[2] == 0xfeedface0d15ea5e'i64
        assert arr_i64[3] == 0

        var arr_u64: array[4, uint64]
        s.peek(arr_u64, 1, 2)
        assert arr_u64[0] == 0
        assert arr_u64[1] == 0xdeadbeefcafebabe'u64
        assert arr_u64[2] == 0xfeedface0d15ea5e'u64
        assert arr_u64[3] == 0

        assert s.getPosition() == 0
        s.setPosition(16)
        var arr_f32: array[3, float32]
        s.peek(arr_f32, 1, 1)
        assert arr_f32[0] == 0
        assert arr_f32[1] == TestFloat32
        assert arr_f32[2] == 0

        s.setPosition(20)
        var arr_f64: array[3, float64]
        s.peek(arr_f64, 1, 1)
        assert arr_f64[0] == 0
        assert arr_f64[1] == TestFloat64
        assert arr_f64[2] == 0

        assert s.getPosition() == 20

      var fs = newFileStream(TestFileLE, littleEndian)
      tests(fs)
      fs.close()

      var bs = newByteStream(testByteBufLE, littleEndian)
      tests(bs)
      bs.close()

      template readBufTest(s: untyped, numValues: Natural) =
        var buf: array[ReadChunkSize*3, uint64]
        let offs = 123

        for n in 0..3:
          s.peek(buf, offs, numValues)

          for i in 0..<offs:
            assert buf[i] == 0
          for i in 0..<numValues:
            assert buf[offs + i] == MagicValue64_1 + i.uint64
          for i in offs+numValues..buf.high:
            assert buf[i] == 0

        assert s.getPosition() == 0

      template readBufTest_FileStream(numValues: Natural) =
        var fs = newFileStream(TestFileBigLE, littleEndian)
        readBufTest(fs, numValues)
        fs.close()

      readBufTest_FileStream(0)
      readBufTest_FileStream(10)
      readBufTest_FileStream(ReadChunkSize)
      readBufTest_FileStream(ReadChunkSize * 2)
      readBufTest_FileStream(ReadChunkSize + 10)

      template readBufTest_ByteStream(numValues: Natural) =
        var bs = newByteStream(testByteBufBigLE, littleEndian)
        readBufTest(bs, numValues)
        bs.close()

      readBufTest_ByteStream(0)
      readBufTest_ByteStream(10)
      readBufTest_ByteStream(ReadChunkSize)
      readBufTest_ByteStream(ReadChunkSize * 2)
      readBufTest_ByteStream(ReadChunkSize + 10)

    # }}}
    block: # {{{ write/func
      template tests_write(s: untyped) =
        s.write(0xde'i8)
        s.write(0xad'u8)
        s.write(0xdead'i16)
        s.write(0xbeef'u16)
        s.write(0xdeadbeef'i32)
        s.write(0xcafebabe'u32)
        s.write(0xdeadbeefcafebabe'i64)
        s.write(0xfeedface0d15ea5e'u64)
        s.write(TestFloat32)
        s.write(TestFloat64)
        s.writeStr(TestString)
        s.writeChar(TestChar)
        s.writeBool(true)
        s.writeBool(false)

      template tests_read(s: untyped) =
        assert s.read(int8)    == 0xde'i8
        assert s.read(uint8)   == 0xad'u8
        assert s.read(int16)   == 0xdead'i16
        assert s.read(uint16)  == 0xbeef'u16
        assert s.read(int32)   == 0xdeadbeef'i32
        assert s.read(uint32)  == 0xcafebabe'u32
        assert s.read(int64)   == 0xdeadbeefcafebabe'i64
        assert s.read(uint64)  == 0xfeedface0d15ea5e'u64
        assert s.read(float32) == TestFloat32
        assert s.read(float64) == TestFloat64
        assert s.readStr(TestString.len) == TestString
        assert s.readChar() == TestChar
        assert s.readBool() == true
        assert s.readBool() == false

      var fs = newFileStream(TestFileLE, littleEndian, fmWrite)
      tests_write(fs)
      fs.close()

      fs = newFileStream(TestFileLE, littleEndian)
      tests_read(fs)
      fs.close()

      var bs = newByteStream(littleEndian)
      tests_write(bs)

      var bs2 = newByteStream(bs.data, littleEndian)
      bs.close()
      tests_read(bs2)
      bs2.close()

    # }}}
    block: # {{{ write/openArray
      const offs = 123

      var buf: array[WriteBufSize*3, uint64]
      for i in 0..buf.high:
        buf[i] = MagicValue64_1 + i.uint64

      template writeTestStream(s: untyped, numValues: Natural) =
        s.write(buf, offs, numValues)

      template assertTestStream(s: untyped, numValues: Natural) =
        var readBuf: array[WriteBufSize*3, uint64]
        s.read(readBuf, offs, numValues)
        for i in 0..<numValues:
          assert readBuf[offs + i] == buf[offs + i]

      proc writeBufTest_FileStream(numValues: Natural) =
        var s = newFileStream(TestFile, littleEndian, fmWrite)
        writeTestStream(s, numValues)
        s.close()
        s = newFileStream(TestFile, littleEndian)
        assertTestStream(s, numValues)
        s.close()

      proc writeBufTest_ByteStream(numValues: Natural) =
        var s = newByteStream(littleEndian)
        writeTestStream(s, numValues)
        var s2 = newByteStream(s.data, littleEndian)
        s.close()
        assertTestStream(s2, numValues)
        s2.close()

      writeBufTest_FileStream(0)
      writeBufTest_FileStream(10)
      writeBufTest_FileStream(WriteBufSize)
      writeBufTest_FileStream(WriteBufSize * 2)
      writeBufTest_FileStream(WriteBufSize + 10)

      writeBufTest_ByteStream(0)
      writeBufTest_ByteStream(10)
      writeBufTest_ByteStream(WriteBufSize)
      writeBufTest_ByteStream(WriteBufSize * 2)
      writeBufTest_ByteStream(WriteBufSize + 10)
    # }}}
  # }}}
  block: # {{{ Common / Mixed endian
    template writeTestStream(s: untyped) =
      s.write(0xde'i8)
      s.write(0xad'u8)
      s.write(0xdead'i16)
      s.write(0xbeef'u16)

      s.endian = littleEndian
      s.write(0xdeadbeef'i32)
      s.write(0xcafebabe'u32)
      s.write(0xdeadbeefcafebabe'i64)
      s.write(0xfeedface0d15ea5e'u64)

      s.endian = bigEndian
      s.write(TestFloat32)
      s.write(TestFloat64)
      s.writeStr(TestString)
      s.writeChar(TestChar)
      s.writeBool(true)
      s.writeBool(false)

    template readTestStream(s: untyped) =
      assert s.read(int8)    == 0xde'i8
      assert s.read(uint8)   == 0xad'u8
      assert s.read(int16)   == 0xdead'i16
      assert s.read(uint16)  == 0xbeef'u16

      s.endian = littleEndian
      assert s.read(int32)   == 0xdeadbeef'i32
      assert s.read(uint32)  == 0xcafebabe'u32
      assert s.read(int64)   == 0xdeadbeefcafebabe'i64
      assert s.read(uint64)  == 0xfeedface0d15ea5e'u64

      s.endian = bigEndian
      assert s.read(float32) == TestFloat32
      assert s.read(float64) == TestFloat64
      assert s.readStr(TestString.len) == TestString
      assert s.readChar() == TestChar
      assert s.readBool() == true
      assert s.readBool() == false

    var fs = newFileStream(TestFileLE, bigEndian, fmWrite)
    writeTestStream(fs)
    fs.close()

    fs = newFileStream(TestFileLE, bigEndian)
    fs.close()

    var bs = newByteStream(bigEndian)
    writeTestStream(bs)
    var bs2 = newByteStream(bs.data, bigEndian)
    bs.close()
    bs2.close()

  # }}}

  # {{{ Test data file cleanup
    removeFile(TestFileBE)
    removeFile(TestFileLE)
    removeFile(TestFileBigBE)
    removeFile(TestFileBigLE)
    removeFile(TestFile)
  # }}}

# vim: et:ts=2:sw=2:fdm=marker
