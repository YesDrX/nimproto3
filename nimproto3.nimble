# Package

version       = "0.6.5"
author        = "Yes DrX"
description   = "Nim implementation of protobuf3 based on npeg."
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["tools/protonim"]
installDirs   = @["nimproto3"]


# Dependencies

requires "nim >= 2.2.4"
requires "npeg >= 1.3.0"
requires "cligen >= 0.1.0"
requires "zippy >= 0.10.0"  # For gRPC compression support
requires "supersnappy >= 0.1.0"