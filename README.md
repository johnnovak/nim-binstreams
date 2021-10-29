# nim-binstreams

**nim-binstreams** is a no-dependencies Nim library that provides endianness
aware binary streams. It is a wrapper over the standard `io` module, and it
uses [stew/endians2](https://github.com/status-im/nim-stew/blob/master/stew/endians2.nim)
for endianness conversions (included in the project), so it should be
reasonably fast.

Main features:

* Support for file and memory buffer backed streams through a single interface
* Possibility to switch the endianness of a stream on the fly
* Mixed read/write streams are supported
* Generics-friendly API


## Installation

**nim-binstreams** can be installed via Nimble:

    nimble install binstreams


## Usage

The below example should give you a fairly good idea of the basic usage.
Please refer to the API documentation for further details.


```nim
import binstreams

# Create a new big-endian file stream for writing.
# File modes work exactly like with `open`.
var fs = newFileStream("outfile", bigEndian, fmWrite)

# There's just a single generic `write()` proc to write single values.
# The width of the value written is determined by the type of the passed in
# argument. Endianness conversions are handled automatically, if required.
fs.write(3'i8)
fs.write(42'i16)
fs.write(0xcafe'u16)
fs.write('X')
fs.write(true)

# Writing multiple values from a buffer (openArray) is just as easy.
var buf = newSeq[float32](100)
fs.write(buf, startIndex=5, numValues=30)

# It is possible to change the endiannes of the stream on-the-fly.
fs.endian = littleEndian
fs.write(12.34'f32)
fs.write(0xcafebabe'i32)
fs.endian = bigEndian
fs.write(0xffee81'u64)

# Helper for writing strings
fs.writeStr("some UTF-8 string")

# The file position can be queried and changed at any time.
let pos = fs.getPosition()
fs.setPosition(0)
fs.write(88'u8)
fs.setPosition(pos)
fs.write(12'i16)

fs.close()


# It is possible to create a new stream from a valid file handle.
var f = open("infile")
fs = newFileStream(f, bigEndian)

# The type of the value needs to be specified when doing single-value reads.
echo fs.read(int8)
echo fs.read(uint8)

fs.endian = littleEndian
echo fs.read(int16)
echo fs.read(float32)
echo fs.read(bool)
echo fs.read(char)
echo fs.readStr(10)

# Reading multiple values into a buffer
fs.setPosition(5)
var readBuf = newSeq[int16](30)
fs.read(buf, startIndex=5, numValues=10)
```

## License

Copyright © 2020-2021 John Novak <<john@johnnovak.net>>

This work is free. You can redistribute it and/or modify it under the terms of
the [Do What The Fuck You Want To Public License, Version 2](http://www.wtfpl.net/), as published
by Sam Hocevar. See the [COPYING](./COPYING) file for more details.


