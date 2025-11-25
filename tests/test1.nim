import unittest
import nimproto3

suite "Protobuf3 Parser Tests":
  test "Basic Syntax":
    let proto = """
syntax = "proto3";
package test;
"""
    let ast = parseProto(proto)
    check ast.kind == nkProto
    check ast.children.len == 2
    check ast.children[0].kind == nkSyntax
    check ast.children[0].value == "proto3"
    check ast.children[1].kind == nkPackage
    check ast.children[1].name == "test"

  test "Message and Fields":
    let proto = """
syntax = "proto3";
message Person {
  string name = 1;
  int32 id = 2;
  repeated string email = 3;
}
"""
    let ast = parseProto(proto)
    let msg = ast.children[1]
    check msg.kind == nkMessage
    check msg.name == "Person"
    check msg.children.len == 3
    check msg.children[0].kind == nkField
    check msg.children[0].name == "name"
    check msg.children[0].value == "string"
    check msg.children[0].number == 1
    check msg.children[2].attrs.len == 1
    check msg.children[2].attrs[0].name == "label"
    check msg.children[2].attrs[0].value == "repeated"

  test "Enum":
    let proto = """
syntax = "proto3";
enum PhoneType {
  MOBILE = 0;
  HOME = 1;
  WORK = 2;
}
"""
    let ast = parseProto(proto)
    let enm = ast.children[1]
    check enm.kind == nkEnum
    check enm.name == "PhoneType"
    check enm.children.len == 3
    check enm.children[0].kind == nkEnumField
    check enm.children[0].name == "MOBILE"
    check enm.children[0].number == 0

  test "Nested Message":
    let proto = """
syntax = "proto3";
message Outer {
  message Inner {
    int64 val = 1;
  }
  Inner inner = 1;
}
"""
    let ast = parseProto(proto)
    let outer = ast.children[1]
    check outer.kind == nkMessage
    check outer.children[0].kind == nkMessage
    check outer.children[0].name == "Inner"

  test "Imports and Options":
    let proto = """
syntax = "proto3";
import "other.proto";
option java_package = "com.example.foo";
"""
    let ast = parseProto(proto)
    check ast.children[1].kind == nkImport
    check ast.children[1].value == "other.proto"
    check ast.children[2].kind == nkOption
    check ast.children[2].name == "java_package"
    check ast.children[2].value == "com.example.foo"

  test "Oneof":
    let proto = """
syntax = "proto3";
message Test {
  oneof test_oneof {
    string name = 4;
    int32 id = 5;
  }
}
"""
    let ast = parseProto(proto)
    let msg = ast.children[1]
    check msg.children[0].kind == nkOneof
    check msg.children[0].name == "test_oneof"
    check msg.children[0].children.len == 2
    check msg.children[0].children[0].name == "name"

  test "Map Field":
    let proto = """
syntax = "proto3";
message Test {
  map<string, int32> projects = 3;
}
"""
    let ast = parseProto(proto)
    let msg = ast.children[1]
    check msg.children[0].kind == nkMapField
    check msg.children[0].name == "projects"
    check msg.children[0].value == "string,int32"

  test "Service":
    let proto = """
syntax = "proto3";
service SearchService {
  rpc Search(SearchRequest) returns (SearchResponse);
}
"""
    let ast = parseProto(proto)
    let svc = ast.children[1]
    check svc.kind == nkService
    check svc.name == "SearchService"
    check svc.children[0].kind == nkRpc
    check svc.children[0].name == "Search"

  test "Invalid Syntax":
    let proto = """
syntax = "proto3";
message {
"""
    expect ValueError:
      discard parseProto(proto)
