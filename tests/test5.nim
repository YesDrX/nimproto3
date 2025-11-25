import nimproto3


let proto = """
syntax = "proto3";
package nested;

message Outer {
  message Middle1 {
    message Inner {
      int64 value = 1;
    }
    Inner inner = 1;
  }
  message Middle2 {
    message Inner {
      int64 value = 1;
    }
    Inner inner = 1;
  }
  message Middle3 {
    Middle1 msg1 = 1;
    Middle2 msg2 = 2;
  }
}
"""
# We expect the parser to auto-detect the include path from protoc
let ast = parseProto(proto)
echo ast
ast.renameSubmessageTypeNames()
echo ast.printRenamedTypes
