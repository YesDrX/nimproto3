import unittest, os, strutils
import nimproto3

suite "Protobuf3 File Tests":
  const protosDir = "tests/protos"

  for kind, path in walkDir(protosDir):
    if kind == pcFile and path.endsWith(".proto"):
      test "Parse " & path:
        echo "Parsing ", path
        let content = readFile(path)
        let ast = parseProto(content, searchDirs = @[protosDir])
        check ast.kind == nkProto
        echo "AST for ", path, ":"
        echo ast
        echo "Successfully parsed ", path
