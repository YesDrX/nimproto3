import std/[macros, strutils, json, tables, strformat, os]
import ./[wire_format]

export wire_format, json, tables, strutils, strformat

proc importProtoImpl(file: string, searchDirs: seq[string],
        extraImportPackages: seq[string], replaceCode: seq[tuple[oldStr: string,
                newStr: string]] = @[]): NimNode =
    # var cmdPath = staticExec("which protonim")
    # if cmdPath.len == 0:
    when defined(windows):
        const protonimPath = currentSourcePath().parentDir() / "\\..\\tools\\protonim.nim"
    else:
        const protonimPath = currentSourcePath().parentDir() & "/../tools/protonim.nim"

    var cmdPath = "nim r " & protonimPath
    var cmd = cmdPath & " -i " & file
    for dirname in searchDirs:
        cmd &= " -s " & dirname
    for extraImport in extraImportPackages:
        cmd &= " -p " & extraImport
    for replaceRule in replaceCode:
        cmd &= " -r " & replaceRule.oldStr & ":" & replaceRule.newStr
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
    ## Import a protobuf file and generate Nim code for it.
    ##
    ## Arguments:
    ## - `file`: The path to the .proto file to import.
    ##
    ## Example:
    ## ```nim
    ## importProto3 "my_proto.proto"
    ## ```
    result = importProtoImpl(file, @[], @[], @[])

macro importProto3*(file: static[string], searchDirs: static[seq[
        string]]): untyped =
    ## Import a protobuf file with search directories.
    ##
    ## Arguments:
    ## - `file`: The path to the .proto file to import.
    ## - `searchDirs`: A list of directories to search for imported .proto files.
    ##
    ## Example:
    ## ```nim
    ## importProto3 "my_proto.proto", @["protos/common"]
    ## ```
    result = importProtoImpl(file, searchDirs, @[], @[])

macro importProto3*(file: static[string], searchDirs: static[seq[
        string]], extraImportPackages: static[seq[string]]): untyped =
    ## Import a protobuf file with search directories and extra import packages.
    ##
    ## Arguments:
    ## - `file`: The path to the .proto file to import.
    ## - `searchDirs`: A list of directories to search for imported .proto files.
    ## - `extraImportPackages`: A list of extra Nim packages to import in the generated code.
    ##
    ## Example:
    ## ```nim
    ## importProto3 "my_proto.proto", @["protos/common"], @["my_utils"]
    ## ```
    result = importProtoImpl(file, searchDirs, extraImportPackages, @[])

macro importProto3*(file: static[string], searchDirs: static[seq[
        string]], extraImportPackages: static[seq[string]], replaceCode: static[
                seq[tuple[oldStr: string, newStr: string]]]): untyped =
    ## Import a protobuf file with full options including code replacement.
    ##
    ## Arguments:
    ## - `file`: The path to the .proto file to import.
    ## - `searchDirs`: A list of directories to search for imported .proto files.
    ## - `extraImportPackages`: A list of extra Nim packages to import in the generated code.
    ## - `replaceCode`: A list of string replacement rules to apply to the generated code.
    ##
    ## Example:
    ## ```nim
    ## importProto3 "my_proto.proto", @[], @[], @[("OldType", "NewType")]
    ## ```
    result = importProtoImpl(file, searchDirs, extraImportPackages, replaceCode)

proc proto3Impl(proto_code: NimNode, searchDirs: seq[
        string], extraImportPackages: seq[string], replaceCode: seq[tuple[
                oldStr: string, newStr: string]]): NimNode {.compileTime.} =
    var success = false

    when defined(windows):
        let filename = currentSourcePath().parentDir() & "\\tmp_proto3Impl.proto"
    else:
        let filename = "/tmp/tmp_proto3Impl.proto"

    writeFile(filename, proto_code.strVal)

    try:
        result = importProtoImpl(filename, searchDirs, extraImportPackages)
        success = true
    except Exception as e:
        echo "Failed to generate code from proto code: \n" & proto_code.strVal &
                "\n" & e.msg
    finally:
        when defined(windows):
            let cmd = "powershell.exe -NoProfile -Command Remove-Item -Force \"" &
                    filename & "\""
        else:
            let cmd = "rm \"" & filename & "\""
        echo "[nimproto3] Running command: " & cmd
        echo staticExec(cmd)

    if not success:
        raise newException(ValueError, "Failed to generate code from proto code: \n" &
                proto_code.strVal)

macro proto3*(proto_code: untyped): untyped =
    ## Generate Nim code from an inline protobuf string.
    ##
    ## Arguments:
    ## - `proto_code`: The protobuf code as a string literal.
    ##
    ## Example:
    ## ```nim
    ## proto3 """
    ## syntax = "proto3";
    ## message MyMsg { int32 id = 1; }
    ## """
    ## ```
    result = proto3Impl(proto_code, @[], @[], @[])

macro proto3*(proto_code: untyped, searchDirs: static[seq[
        string]]): untyped =
    ## Generate Nim code from an inline protobuf string with search directories.
    ##
    ## Arguments:
    ## - `proto_code`: The protobuf code as a string literal.
    ## - `searchDirs`: A list of directories to search for imported .proto files.
    result = proto3Impl(proto_code, searchDirs, @[], @[])

macro proto3*(proto_code: untyped, searchDirs: static[seq[
        string]], extraImportPackages: static[seq[string]]): untyped =
    ## Generate Nim code from an inline protobuf string with search directories and extra imports.
    ##
    ## Arguments:
    ## - `proto_code`: The protobuf code as a string literal.
    ## - `searchDirs`: A list of directories to search for imported .proto files.
    ## - `extraImportPackages`: A list of extra Nim packages to import in the generated code.
    result = proto3Impl(proto_code, searchDirs, extraImportPackages, @[])

macro proto3*(proto_code: untyped, searchDirs: static[seq[
        string]], extraImportPackages: static[seq[string]], replaceCode: static[
                seq[tuple[oldStr: string, newStr: string]]]): untyped =
    ## Generate Nim code from an inline protobuf string with full options.
    ##
    ## Arguments:
    ## - `proto_code`: The protobuf code as a string literal.
    ## - `searchDirs`: A list of directories to search for imported .proto files.
    ## - `extraImportPackages`: A list of extra Nim packages to import in the generated code.
    ## - `replaceCode`: A list of string replacement rules to apply to the generated code.
    result = proto3Impl(proto_code, searchDirs, extraImportPackages, replaceCode)

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
