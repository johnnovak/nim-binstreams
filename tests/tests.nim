import os, unittest
import binstreams/deps/stew/endians2

import binstreams

# {{{ Test data file creation
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
  TestBooleans = @[-127'i8, -1'i8, 0'i8, 1'i8, 64'i8]

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

# {{{ Common / Big-endian
suite "Common / Big-endian":
  # {{{ read/func
  test "read/func":
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
      assert s.read(char) == TestChar
      assert s.read(bool) == true
      assert s.read(bool) == true
      assert s.read(bool) == false
      assert s.read(bool) == true
      assert s.read(bool) == true

    var fs = newFileStream(TestFileBE, bigEndian)
    tests(fs)
    fs.close()

    var ms = newMemStream(testByteBufBE, bigEndian)
    tests(ms)
    ms.close()

  # }}}
  # {{{ peek/func
  test "peek/func":
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
      assert s.peek(char) == TestChar; s.setPosition(1, sspCur)
      assert s.peek(bool) == true;     s.setPosition(1, sspCur)
      assert s.peek(bool) == true;     s.setPosition(1, sspCur)
      assert s.peek(bool) == false;    s.setPosition(1, sspCur)
      assert s.peek(bool) == true;     s.setPosition(1, sspCur)
      assert s.peek(bool) == true

    var fs = newFileStream(TestFileBE, bigEndian)
    tests(fs)
    fs.close()

    var ms = newMemStream(testByteBufBE, bigEndian)
    tests(ms)
    ms.close()

  # }}}
  # {{{ read/openArray
  test "read/openArray":
    template tests(s: untyped) =

      var arr_char: array[4, char]
      s.read(arr_char, 1, 2)
      assert arr_char[0] == 0.char
      assert arr_char[1] == 0xde.char
      assert arr_char[2] == 0xad.char
      assert arr_char[3] == 0.char

      var arr_bool: array[4, bool]
      s.setPosition(0)
      s.read(arr_bool, 1, 2)
      assert arr_bool[0] == false
      assert arr_bool[1] == true
      assert arr_bool[2] == true
      assert arr_bool[3] == false

      var arr_i8: array[4, int8]
      s.setPosition(0)
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

    var ms = newMemStream(testByteBufBE, bigEndian)
    tests(ms)
    ms.close()

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

    template readBufTest_MemStream(numValues: Natural) =
      var ms = newMemStream(testByteBufBigBE, bigEndian)
      readBufTest(ms, numValues)
      ms.close()

    readBufTest_MemStream(0)
    readBufTest_MemStream(10)
    readBufTest_MemStream(ReadChunkSize)
    readBufTest_MemStream(ReadChunkSize * 2)
    readBufTest_MemStream(ReadChunkSize + 10)

  # }}}
  # {{{ peek/openArray
  test "peek/openArray":
    template tests(s: untyped) =
      var arr_char: array[4, char]
      s.peek(arr_char, 1, 2)
      assert arr_char[0] == 0.char
      assert arr_char[1] == 0xde.char
      assert arr_char[2] == 0xad.char
      assert arr_char[3] == 0.char

      var arr_bool: array[4, bool]
      s.setPosition(0)
      s.peek(arr_bool, 1, 2)
      assert arr_bool[0] == false
      assert arr_bool[1] == true
      assert arr_bool[2] == true
      assert arr_bool[3] == false

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

    var ms = newMemStream(testByteBufBE, bigEndian)
    tests(ms)
    ms.close()

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

    template readBufTest_MemStream(numValues: Natural) =
      var ms = newMemStream(testByteBufBigBE, bigEndian)
      readBufTest(ms, numValues)
      ms.close()

    readBufTest_MemStream(0)
    readBufTest_MemStream(10)
    readBufTest_MemStream(ReadChunkSize)
    readBufTest_MemStream(ReadChunkSize * 2)
    readBufTest_MemStream(ReadChunkSize + 10)

  # }}}
  # {{{ write/func
  test "write/func":
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
      s.writeStr("")
      s.writeStr(TestString)
      s.write(TestChar)
      s.write(true)
      s.write(false)

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
      assert s.readStr(0) == ""
      assert s.readStr(TestString.len) == TestString
      assert s.read(char) == TestChar
      assert s.read(bool) == true
      assert s.read(bool) == false

    var fs = newFileStream(TestFileBE, bigEndian, fmWrite)
    tests_write(fs)
    fs.close()

    fs = newFileStream(TestFileBE, bigEndian)
    tests_read(fs)
    fs.close()

    var ms = newMemStream(bigEndian)
    tests_write(ms)

    var ms2 = newMemStream(ms.data, bigEndian)
    ms.close()
    tests_read(ms2)
    ms2.close()

  # }}}
  # {{{ write/openArray
  test "write/openArray":
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

    proc writeBufTest_MemStream(numValues: Natural) =
      var s = newMemStream(bigEndian)
      writeTestStream(s, numValues)
      var s2 = newMemStream(s.data, bigEndian)
      s.close()
      assertTestStream(s2, numValues)
      s2.close()

    writeBufTest_FileStream(0)
    writeBufTest_FileStream(10)
    writeBufTest_FileStream(WriteBufSize)
    writeBufTest_FileStream(WriteBufSize * 2)
    writeBufTest_FileStream(WriteBufSize + 10)

    writeBufTest_MemStream(0)
    writeBufTest_MemStream(10)
    writeBufTest_MemStream(WriteBufSize)
    writeBufTest_MemStream(WriteBufSize * 2)
    writeBufTest_MemStream(WriteBufSize + 10)

  # }}}
  # }}}
# {{{ Common / Little-endian
suite "Common / Little-endian":
  # {{{ read/func
  test "read/func":
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
      assert s.read(char) == TestChar
      assert s.read(bool) == true
      assert s.read(bool) == true
      assert s.read(bool) == false
      assert s.read(bool) == true
      assert s.read(bool) == true

    var fs = newFileStream(TestFileLE, littleEndian)
    tests(fs)
    fs.close()

    var ms = newMemStream(testByteBufLE, littleEndian)
    tests(ms)
    ms.close()

  # }}}
  # {{{ peek/func
  test "peek/func":
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
      assert s.peek(char) == TestChar; s.setPosition(1, sspCur)
      assert s.peek(bool) == true;     s.setPosition(1, sspCur)
      assert s.peek(bool) == true;     s.setPosition(1, sspCur)
      assert s.peek(bool) == false;    s.setPosition(1, sspCur)
      assert s.peek(bool) == true;     s.setPosition(1, sspCur)
      assert s.peek(bool) == true

    var fs = newFileStream(TestFileLE, littleEndian)
    tests(fs)
    fs.close()

    var ms = newMemStream(testByteBufLE, littleEndian)
    tests(ms)
    ms.close()

  # }}}
  # {{{ read/openArray
  test "read/openArray":
    template tests(s: untyped) =
      var arr_char: array[4, char]
      s.read(arr_char, 1, 2)
      assert arr_char[0] == 0.char
      assert arr_char[1] == 0xbe.char
      assert arr_char[2] == 0xba.char
      assert arr_char[3] == 0.char

      var arr_bool: array[4, bool]
      s.setPosition(0)
      s.read(arr_bool, 1, 2)
      assert arr_bool[0] == false
      assert arr_bool[1] == true
      assert arr_bool[2] == true
      assert arr_bool[3] == false

      var arr_i8: array[4, int8]
      s.setPosition(0)
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

    var ms = newMemStream(testByteBufLE, littleEndian)
    tests(ms)
    ms.close()

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

    template readBufTest_MemStream(numValues: Natural) =
      var ms = newMemStream(testByteBufBigLE, littleEndian)
      readBufTest(ms, numValues)
      ms.close()

    readBufTest_MemStream(0)
    readBufTest_MemStream(10)
    readBufTest_MemStream(ReadChunkSize)
    readBufTest_MemStream(ReadChunkSize * 2)
    readBufTest_MemStream(ReadChunkSize + 10)

  # }}}
  # {{{ peek/openArray
  test "peek/openArray":
    template tests(s: untyped) =
      var arr_char: array[4, char]
      s.peek(arr_char, 1, 2)
      assert arr_char[0] == 0.char
      assert arr_char[1] == 0xbe.char
      assert arr_char[2] == 0xba.char
      assert arr_char[3] == 0.char

      var arr_bool: array[4, bool]
      s.setPosition(0)
      s.peek(arr_bool, 1, 2)
      assert arr_bool[0] == false
      assert arr_bool[1] == true
      assert arr_bool[2] == true
      assert arr_bool[3] == false

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

    var ms = newMemStream(testByteBufLE, littleEndian)
    tests(ms)
    ms.close()

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

    template readBufTest_MemStream(numValues: Natural) =
      var ms = newMemStream(testByteBufBigLE, littleEndian)
      readBufTest(ms, numValues)
      ms.close()

    readBufTest_MemStream(0)
    readBufTest_MemStream(10)
    readBufTest_MemStream(ReadChunkSize)
    readBufTest_MemStream(ReadChunkSize * 2)
    readBufTest_MemStream(ReadChunkSize + 10)

  # }}}
  # {{{ write/func
  test "write/func":
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
      s.writeStr("")
      s.writeStr(TestString)
      s.write(TestChar)
      s.write(true)
      s.write(false)

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
      assert s.readStr(0) == ""
      assert s.readStr(TestString.len) == TestString
      assert s.read(char) == TestChar
      assert s.read(bool) == true
      assert s.read(bool) == false

    var fs = newFileStream(TestFileLE, littleEndian, fmWrite)
    tests_write(fs)
    fs.close()

    fs = newFileStream(TestFileLE, littleEndian)
    tests_read(fs)
    fs.close()

    var ms = newMemStream(littleEndian)
    tests_write(ms)

    var ms2 = newMemStream(ms.data, littleEndian)
    ms.close()
    tests_read(ms2)
    ms2.close()

  # }}}
  # {{{ write/openArray
  test "write/openArray":
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

    proc writeBufTest_MemStream(numValues: Natural) =
      var s = newMemStream(littleEndian)
      writeTestStream(s, numValues)
      var s2 = newMemStream(s.data, littleEndian)
      s.close()
      assertTestStream(s2, numValues)
      s2.close()

    writeBufTest_FileStream(0)
    writeBufTest_FileStream(10)
    writeBufTest_FileStream(WriteBufSize)
    writeBufTest_FileStream(WriteBufSize * 2)
    writeBufTest_FileStream(WriteBufSize + 10)

    writeBufTest_MemStream(0)
    writeBufTest_MemStream(10)
    writeBufTest_MemStream(WriteBufSize)
    writeBufTest_MemStream(WriteBufSize * 2)
    writeBufTest_MemStream(WriteBufSize + 10)
  # }}}
# }}}
# {{{ Common / Mixed-endian
suite "Common / Mixed-endian":
  test "read/write":
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
      s.writeStr("")
      s.writeStr(TestString)
      s.write(TestChar)
      s.write(true)
      s.write(false)

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
      assert s.readStr(0) == ""
      assert s.readStr(TestString.len) == TestString
      assert s.read(char) == TestChar
      assert s.read(bool) == true
      assert s.read(bool) == false

    var fs = newFileStream(TestFileLE, bigEndian, fmWrite)
    writeTestStream(fs)
    fs.close()

    fs = newFileStream(TestFileLE, bigEndian)
    readTestStream(fs)
    fs.close()

    var ms = newMemStream(bigEndian)
    writeTestStream(ms)
    var ms2 = newMemStream(ms.data, bigEndian)
    readTestStream(ms2)
    ms.close()
    ms2.close()
# }}}
# {{{ MemStream
suite "MemStream":
  test "seek after end of stream & write":
    var ms = newMemStream(littleEndian)
    ms.setPosition(2)
    ms.write(1'u8)
    assert ms.data == @[0'u8, 0'u8, 1'u8]
    assert ms.getPosition() == 3

  test "seek modes (successes)":
    var ms = newMemStream(@[1'u8, 2'u8, 3'u8, 4'u8], littleEndian)
    ms.setPosition(1)
    assert ms.read(uint8) == 2'u8

    ms.setPosition(0, sspEnd)
    assert ms.read(uint8) == 4'u8

    ms.setPosition(10, sspEnd)
    assert ms.getPosition() == 13

    ms.setPosition(-1, sspEnd)
    assert ms.getPosition() == 2
    assert ms.read(uint8) == 3'u8
    assert ms.getPosition() == 3

    ms.setPosition(-2, sspCur)
    assert ms.getPosition() == 1
    assert ms.read(uint8) == 2'u8
    assert ms.getPosition() == 2

    ms.setPosition(1, sspCur)
    assert ms.read(uint8) == 4'u8

  test "seek modes (failures)":
    let data = @[1'u8, 2'u8, 3'u8, 4'u8]
    doAssertRaises(IOError):
      var ms = newMemStream(data, littleEndian)
      ms.setPosition(-1)

    doAssertRaises(IOError):
      var ms = newMemStream(data, littleEndian)
      ms.setPosition(-10, sspEnd)

    doAssertRaises(IOError):
      var ms = newMemStream(data, littleEndian)
      ms.setPosition(50)
      ms.setPosition(-60, sspCur)

  # }}}
# {{{ Test data file cleanup

removeFile(TestFileBE)
removeFile(TestFileLE)
removeFile(TestFileBigBE)
removeFile(TestFileBigLE)
removeFile(TestFile)

# }}}

# TODO add tests:
#
# - atEnd
# - read past end of the stream
# - operations on uninitialised streams
# - operations on closed streams
#
# - performance tests?
# - string streams on NimVM & JS?
#

# vim: et:ts=2:sw=2:fdm=marker
