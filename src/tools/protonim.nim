## Protobuf to Nim Code Generator
##
## This tool generates Nim code from Protobuf files (.proto).
## It supports generating Nim types, serialization/deserialization procedures (binary and JSON),
## and gRPC client/server stubs.
##
## Usage:
##   protonim [options] -i <input.proto>
##
## Options:
##   -i, --input <file>       Input .proto file (required)
##   -o, --output <file>      Output .nim file (optional, defaults to stdout)
##   -s, --searchDirs <dir>   Search directories for imported .proto files (can be used multiple times)
##   -p, --extraImportPackages <pkg>
##                            Extra Nim packages to import in the generated code (can be used multiple times)
##   -r, --replaceCode <old:new>
##                            Replace code in the generated Nim code (can be used multiple times)
##                            Format: "old_string:new_string"
##
## Examples:
##   # Generate code to stdout
##   protonim -i my_proto.proto
##
##   # Generate code to a file
##   protonim -i my_proto.proto -o my_proto.nim
##
##   # With search directories and extra imports
##   protonim -i my_proto.proto -s ./protos -p my_utils
##
##   # Replace a type name in the generated code
##   protonim -i my_proto.proto -r "OldType:NewType"

import strutils
import ../nimproto3/[codegen]

proc main(input: string, output: string = "", searchDirs: seq[string] = @[],
    extraImportPackages: seq[string] = @[], replaceCode: seq[string] = @[]) =

  var replaceCodeTuples: seq[tuple[oldStr: string, newStr: string]]
  for i in 0 ..< replaceCode.len:
    let replaceCodeParts = replaceCode[i].split(":")
    if replaceCodeParts.len != 2:
      raise newException(ValueError, "Invalid replace code: " & replaceCode[i])
    let (oldStr, newStr) = (replaceCodeParts[0], replaceCodeParts[1])
    replaceCodeTuples.add((oldStr, newStr))

  let nimCode = genCodeFromProtoFile(input, searchDirs, extraImportPackages, replaceCodeTuples)

  # Output
  if output.len > 0:
    writeFile(output, nimCode)
  else:
    echo nimCode

when isMainModule:
  import cligen
  cligen.dispatch(main, short = {"input": 'i', "output": 'o',
      "extraImportPackages": 'p'}, help = {
      "extraImportPackages": "Extra import packages to add to the generated code. For example: -p google.protobuf.any -p google.protobuf.duration",
      "replaceCode": "Replace code in the generated Nim code. For example: -r old_code:new_code -r another_old_code:another_new_code",
      "searchDirs": "Search directories for imported proto files. For example: -s /path/to/protos -s /path/to/other/protos",
      "output": "Output file. If not specified, prints to stdout"})
