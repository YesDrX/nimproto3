## Protobuf to Nim Code Generator
## 
## Usage: protonim -i input.proto -o output.nim
##
## If output file is not specified, prints to stdout

import strutils
import ../nimproto3/[codegen]

proc main(input: string, output: string = "", searchDirs: seq[string] = @[]) =
  let nimCode = genCodeFromProtoFile(input, searchDirs)

  # Output
  if output.len > 0:
    writeFile(output, nimCode)
  else:
    echo nimCode

when isMainModule:
  import cligen
  cligen.dispatch(main, short = {"input": 'i', "output": 'o'})
