import unittest, os, strutils
import nimproto3

suite "Standard Import Verification":
  test "Verify Google Protobuf Import":
    let proto = """
syntax = "proto3";
package standard;

import "google/protobuf/timestamp.proto";

message TimeMessage {
  google.protobuf.Timestamp timestamp = 1;
}
"""
    echo "Parsing standard import test..."
    # We expect the parser to auto-detect the include path from protoc
    let ast = parseProto(proto)
    echo "AST for standard import test:"
    echo ast

    check ast.kind == nkProto

    # Check if import is resolved
    var foundImport = false
    for child in ast.children:
      if child.kind == nkImport and child.value == "google/protobuf/timestamp.proto":
        foundImport = true
        if child.children.len > 0:
          echo "Standard import resolved with ", child.children.len, " children."
          check child.children[0].kind == nkProto
          check child.children[0].children.len > 0
        else:
          echo "Standard import has NO children."
          fail()

    check foundImport
