import std/[macros, strutils, json, tables, strformat, os]
import ./[wire_format]

export wire_format, json, tables, strutils

proc importProtoImpl(file: string, searchDirs: seq[string]): NimNode =
    # var cmdPath = staticExec("which protonim")
    # if cmdPath.len == 0:
    const protonimPath = currentSourcePath().parentDir() / "../tools/protonim.nim"
    var cmdPath = "nim r " & protonimPath
    var cmd = cmdPath & " -i " & file
    if searchDirs.len > 0:
        for dirname in searchDirs:
            cmd &= " -s " & dirname
    when defined(showGeneratedProto3Code):
        echo "Running command to generate nim code: " & cmd
    var generatedCode = staticExec(cmd)
    if not generatedCode.contains("# Generated from protobuf"):
        raise newException(ValueError, "Failed to parse proto file: " & file &
                "\n" & generatedCode)
    generatedCode = generatedCode[generatedCode.find(
            "# Generated from protobuf") .. ^1]
    when defined(showGeneratedProto3Code):
        echo generatedCode
    result = generatedCode.parseStmt

macro importProto3*(file: static[string]): untyped =
    result = importProtoImpl(file, @[])

macro importProto3*(file: static[string], searchDirs: static[seq[
        string]]): untyped =
    result = importProtoImpl(file, searchDirs)

proc proto3Impl(proto_code: string, searchDirs: seq[string]): NimNode =
    var success = false
    try:
        discard staticExec("rm -f ./tmp.proto")
        for line in proto_code.splitLines:
            discard staticExec(fmt"""echo '{line}' >> ./tmp.proto""")
        result = importProtoImpl("./tmp.proto", searchDirs)
        success = true
    except Exception as e:
        echo "Failed to generate code from proto code: \n" & proto_code & "\n" & e.msg
    finally:
        discard staticExec("rm -f ./tmp.proto")

    if not success:
        raise newException(ValueError, "Failed to generate code from proto code: \n" & proto_code)

macro proto3*(proto_code: static[string]): untyped =
    result = proto3Impl(proto_code, @[])

macro proto3*(proto_code: static[string], searchDirs: static[seq[
        string]]): untyped =
    result = proto3Impl(proto_code, searchDirs)

# importProto3 "../../tests/protos/maps.proto", @["../../tests/protos"]

# proto3 """
# syntax = "proto3";
# package maps;

# message Dictionary {
#   map<string, string> pairs = 1;
#   map<int32, bool> flags = 2;
# }
# """

# let msg = Dictionary(pairs: {"a": "b", "c": "d"}.toTable, flags: {1.int32: true,
#         2.int32: false}.toTable)
# echo msg.toBinary()
# echo fromBinary(Dictionary, msg.toBinary())
