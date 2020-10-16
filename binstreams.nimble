# Package

version       = "0.1.1"
author        = "John Novak <john@johnnovak.net>"
description   = "Endianness aware stream I/O for Nim"
license       = "WTFPL"

# Dependencies

requires "nim >= 1.2.6"

# Tasks

task tests, "Run all tests":
  exec "nim c -r tests/tests"

task docgen, "Generate HTML documentation":
  exec "nim doc -o:doc/binstreams.html binstreams"
