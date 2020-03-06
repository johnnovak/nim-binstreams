# Package

version       = "0.1.0"
author        = "John Novak <john@johnnovak.net>"
description   = "Endianness aware stream I/O for Nim"
license       = "WTFPL"

skipDirs = @["doc"]

# Dependencies

requires "nim >= 1.0.6", "stew"

# Tasks

task docgen, "Generate HTML documentation":
  exec "nim doc -o:doc/binstreams.html binstreams"
