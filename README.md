# nimproto3

A Nim implementation of Protocol Buffers 3 (proto3) with support for parsing `.proto` files, generating Nim code, serializing/deserializing data in both binary (protobuf wire format) and JSON formats, and gRPC server/client.

## Features

✅ **Full Proto3 Syntax Support** - Messages, enums, nested types, maps, repeated fields, oneofs, services  
✅ **Compile-time Code Generation** - Use the `importProto3`/`proto3` macro to generate Nim types at compile time  
✅ **Runtime Code Generation** - Parse and generate code from proto files or strings at runtime  
✅ **Binary Serialization** - `toBinary`/`fromBinary` for protobuf wire format  
✅ **JSON Serialization** - `toJson`/`fromJson` for JSON representation  
✅ **Import Resolution** - Automatically resolves and processes imported `.proto` files  
✅ **CLI Tool** - `protonim` command-line tool for standalone code generation  
✅ **gRPC Support**
  - server
    - streaming RPCs
    - unary RPCs
    - Identity/Deflate/Gzip/Zlib/Snappy compression (Zstd not supported)
    - Huffman decoding for heaaders
    - TLS support
  - client
    - streaming RPCs
    - unary RPCs
    - Identity/Deflate/Gzip/Zlib/Snappy compression (Zstd not supported)
    - customized metadata in headers, such as authentication tokens
    - Huffman decoding for heaaders
    - TLS support

## Installation

```bash
nimble install nimproto3
```

**Dependencies:**
- `npeg` - PEG parser for `.proto` files
- `cligen` - CLI argument parsing for `protonim` tool
- `zippy` - Compression support for gRPC (gzip encoding)
- `supersnappy` - Snappy compression support for gRPC

## Quick Start

### 1. Using the `importProto3` Macro (Compile-Time)

The easiest way to use proto3 in your Nim projects is with the `importProto3` macro, which generates Nim types and gRPC client stubs at compile time.

**Step 1: Create a `.proto` file**

- [user_service.proto](tests/grpc_example/user_service.proto):
```protobuf
syntax = "proto3";

service UserService {
  rpc GetUser(UserRequest) returns (User) {};
  rpc ListUsers(stream UserRequest) returns (stream User) {};
}

message UserRequest {
  int32 id = 1;
}

message User {
  string name = 1;
  int32 id = 2;
  repeated string emails = 3;
  map<string, int32> scores = 4;
}
```

**Step 2: Import and use in your Nim code (server/client)**
- [server.nim](tests/grpc_example/server.nim)

```nim
import nimproto3

# Import the proto file - generates types and gRPC stubs at compile time
importProto3 currentSourcePath.parentDir & "/user_service.proto" # full path to the proto file

# importProto3/proto3 macro generates the following types and procs:
# Types:
#   - User = object
#   - UserRequest = object
# Serialization procs:
#   - proc toBinary*(self: User): seq[byte]
#   - proc fromBinary*(T: typedesc[User], data: openArray[byte]): User
#   - proc toJson*(self: User): JsonNode
#   - proc fromJson*(T: typedesc[User], node: JsonNode): User
# gRPC client stubs:
#   - proc getUser*(c: GrpcChannel, req: UserRequest, metadata: seq[HpackHeader] = @[]): Future[User]
#   - proc listUsers*(c: GrpcChannel, reqs: seq[UserRequest]): Future[seq[User]]
#   - proc getUserJson*(c: GrpcChannel, req: UserRequest, metadata: seq[HpackHeader] = @[]): Future[JsonNode] # a memory efficient version of getUser for sparse data
#   - proc listUsersJson*(c: GrpcChannel, reqs: seq[UserRequest]): Future[seq[JsonNode]] # a memory efficient version of listUsers for sparse data

proc handleGetUser(stream: GrpcStream) {.async.} =
  # 1. Read Request (Unary = Read 1 message)
  let msgOpt = await stream.recvMsg()

  if msgOpt.isNone:
    # Client closed without sending data?
    return

  let input = msgOpt.get()
  let req = UserRequest.fromBinary(input)

  # Demonstrate reading Metadata (Headers)
  let auth = stream.headers.getOrDefault("authorization", "none")
  echo "[Service] Received: ", req, " | Auth: ", auth

  # 2. Logic
  let reply = User(
    name: "Alice",
    id: 42,
    emails: @["alice@example.com", "alice@work.com"],
    scores: {"math": 95.int32, "science": 88.int32}.toTable
  )

  # 3. Send Response (Unary = Send 1 message)
  await stream.sendMsg(reply.toBinary())

  # When this async proc finishes, the server automatically closes the stream
  # and sends the Trailing Headers (Status: OK).

# Example of a Server Streaming handler (returning multiple items)
proc handleListUsers(stream: GrpcStream) {.async.} =
  # Read incoming requests loop (Bidirectional or Client Stream)
  while true:
    let msgOpt = await stream.recvMsg()
    if msgOpt.isNone: break # End of Stream

    let req = fromBinary(UserRequest, msgOpt.get())
    echo "[Service] Stream item: ", req

    # Send a reply immediately (Echo)
    let reply = User(
      name: "Alice",
      id: 42,
      emails: @["alice@example.com", "alice@work.com"],
      scores: {"math": 95.int32, "science": 88.int32}.toTable
    )
    await stream.sendMsg(reply.toBinary())

# =============================================================================
# MAIN SERVER
# =============================================================================

when isMainModule:
  # Enable server-side compression preference (e.g., Gzip)
  let server = newGrpcServer(50051, CompressionGzip) # if -d:ssl, you can specify certFile and keyFile

  # Register routes
  server.registerHandler("/UserService/GetUser", handleGetUser) # "/package_name.UserService/GetUser" if package_name is defined in the .proto file
  server.registerHandler("/UserService/ListUsers", handleListUsers) # "/package_name.UserService/ListUsers" if package_name is defined in the .proto file

  echo "Starting gRPC Server (Stream Architecture)..."
  waitFor server.serve()

```

- [client.nim](tests/grpc_example/client.nim)
```nim
import nimproto3
importProto3 currentSourcePath.parentDir & "/user_service.proto" # full path to the proto file

when isMainModule:
  proc runTests() {.async.} =
    echo "================================================================================"
    echo "Nim gRPC Client (Stream Architecture)"
    echo "================================================================================"

    # Example 1: Identity + Custom Metadata
    let client = newGrpcClient("localhost", 50051, CompressionIdentity) #if -d:ssl, you can disable ssl certificate verification by setting sslVerify = false
    await client.connect()
    await sleepAsync(200) # Wait for settings exchange

    echo "\n[TEST 1] Unary Call with Metadata"
    try:
      # Pass custom authorization header
      let meta = @[("authorization", "Bearer my-secret-token")]
      let reply = await client.getUser(
        UserRequest(id: 1),
        metadata = meta
      )
      echo "Reply: ", reply
    except:
      echo "Error: ", getCurrentExceptionMsg()

    client.close()

  waitFor runTests()
```

- Run
```bash
nim r -d:showGeneratedProto3Code ./tests/grpc_example/server.nim # -d:showGeneratedProto3Code will show generated code during compile time; # -d:traceGrpc will print out the gRPC network traffic
nim r -d:showGeneratedProto3Code ./tests/grpc_example/client.nim

# use -d:ssl to enable TLS support on server/client
```
- Other examples
  - [server.nim](tests/grpc/server.nim)
  - [client.nim](tests/grpc/client.nim)
  - [test_service.proto](tests/grpc/test_service.proto)
  - to cross validate using python library (grpcio)
    - [server.py](tests/grpc/server.py)
    - [client1.py](tests/grpc/client1.py)
    - [client2.py](tests/grpc/client2.py)
    - [client3.py](tests/grpc/client3.py)
  - to test against grpcbin.bin server:
    - [test9.nim](tests/test9.nim) # grpcbin DummyClientStream is buggy
  - TLS tests:
    - [server_tls.py](tests/grpc/server_tls.py)
    - [server_tls.nim](tests/grpc/server_tls.nim)
    - [client_tls.nim](tests/grpc/client_tls.nim)
    - [client_tls.py](tests/grpc/client_tls.py)
    - [test8.nim](tests/test8.nim) # grpcbin DummyClientStream is buggy

### 2. Using the `proto3` Macro (Inline Schemas)

You can also define proto3 schemas inline without a separate `.proto` file. `proto3` is essentially the same as `importProto3`, but it doesn't require a separate file.

```nim
import nimproto3
import std/tables

# Define schema inline
proto3 """
syntax = "proto3";

message Config {
  map<string, string> settings = 1;
  int32 version = 2;
}
"""

# Use the generated types
let config = Config(
  settings: {"timeout": "30", "retries": "3"}.toTable,
  version: 1.int32
)

echo config.toBinary()
echo config.toJson()
```

### 3. Using the CLI Tool (`protonim`)

Generate Nim code from `.proto` files using the command-line tool:
* You need add proper imports to make the generated code actually work.

```bash
# Generate code to stdout
protonim -i input.proto

# Generate code to a file
protonim -i input.proto -o output.nim

# With search directories for imports
protonim -i input.proto -o output.nim -s ./protos -s ./vendor/protos

```

### 4. Runtime Code Generation

Parse proto files and generate code at runtime:

```nim
import nimproto3

# Generate from a file
let nimCode = genCodeFromProtoFile("path/to/schema.proto")
writeFile("generated.nim", nimCode) # you need add your "import tables/json" like imports

# Generate from a string
let protoSchema = """
syntax = "proto3";

message Person {
  string name = 1;
  int32 age = 2;
}
"""

let code = genCodeFromProtoString(protoSchema)
echo code
```

### 5. Parsing Proto Files (AST)

Parse proto files into an Abstract Syntax Tree (AST) for analysis or custom processing:

```nim
import nimproto3

# Parse from string
let ast = parseProto("""
syntax = "proto3";
message Test {
  string field = 1;
}
""")

# Inspect the AST
echo ast.kind  # nkProto
echo ast.children[0].kind  # nkSyntax
echo ast.children[1].kind  # nkMessage

# Parse from file with import resolution
let astFromFile = parseProto(
  readFile("schema.proto"),
  searchDirs = @["proto_dir1", "proto_dir2"]
)
```

## Supported Features

### Message Types

```protobuf
syntax = "proto3";

message Person {
  string name = 1;
  int32 id = 2;
  repeated string emails = 3;
  map<string, int32> scores = 4;
}
```

Generated Nim code includes:
- Type definitions (`Person = object`)
- Binary serialization (`toBinary`, `fromBinary`)
- JSON serialization (`toJson`, `fromJson`)

### Enums

```protobuf
enum PhoneType {
  MOBILE = 0;
  HOME = 1;
  WORK = 2;
}

message Contact {
  PhoneType type = 1;
}
```

### Nested Messages

```protobuf
message Outer {
  message Inner {
    int32 value = 1;
  }
  Inner inner = 1;
}
```

Generated as `Outer` and `Outer_Inner` types.

### Map Fields

```protobuf
message Config {
  map<string, int32> settings = 1;
  map<int32, string> lookup = 2;
}
```

Maps are generated as `Table[K, V]` from Nim's `std/tables`.

### Imports

```protobuf
syntax = "proto3";
import "common.proto";

message User {
  Common common = 1;
}
```

The `importProto3` macro automatically resolves and processes imported files.

### Oneofs

```protobuf
message RpcCall {
  string function_name = 1;
  repeated Argument args = 2;
  int32 call_id = 3;
}

message Argument {
  oneof value {
    int32 int_val = 1;
    bool bool_val = 2;
    string string_val = 3;
    bytes data_val = 4;
  }
}
```
Onefs are generated as object variant (need -d:nimOldCaseObjects for runtime behavior):
```nim
type
  RpcCall* = object
    function_name*: string
    args*: seq[Argument]
    call_id*: int32


  ArgumentValueKind* {.size: 4.} = enum
    rkNone # nothing set
    rkInt_val
    rkBool_val
    rkString_val
    rkData_val

  Argument* = object
    case valueKind*: ArgumentValueKind
    of rkNone: discard
    of rkInt_val:
      int_val*: int32
    of rkBool_val:
      bool_val*: bool
    of rkString_val:
      string_val*: string
    of rkData_val:
      data_val*: seq[byte]
```

### Services

```protobuf
service UserService {
  rpc GetUser(UserId) returns (User);
  rpc ListUsers(Filter) returns (stream User);
}
```

## API Reference

### Compile-Time Macros

#### `importProto3(filename: string, searchDirs: seq[string] = @[])`
Imports a `.proto` file and generates Nim types at compile time.

**Parameters:**
- `filename`: Path to `.proto` file
- `searchDirs`: Optional directories to search for imported files; default @[]
- `extraImportPackages`: Optional list of additional imports to resolve; default @[]

```nim
importProto3 "schema.proto"
# With search directories
importProto3("schema.proto", @["./protos", "./vendor"])
importProto3("schema.proto", searchDirs = @["./protos", "./vendor"], extraImportPackages = @["google/protobuf/any.proto"]) # Additional imports
```

#### `proto3(schemaString: string, searchDirs: seq[string] = @[])`
Define proto3 schemas inline without a separate file.

**Parameters:**
- `schemaString`: Proto3 schema as a string
- `searchDirs`: Optional directories to search for imported files
- `extraImportPackages`: Optional list of additional imports to resolve

```nim
proto3 """
syntax = "proto3";
message Test {
  string name = 1;
}
""", @[]
```

### Runtime Functions

#### `proc parseProto(content: string, searchDirs: seq[string] = @[]): ProtoNode`
Parse a proto3 string into an AST.

**Parameters:**
- `content`: Proto3 schema as a string
- `searchDirs`: Directories to search for imported files

**Returns:** `ProtoNode` representing the root of the AST

#### `proc genCodeFromProtoString*(protoString: string, searchDirs: seq[string] = @[], extraImportPackages: seq[string] = @[]): string`
Generate Nim code from a proto3 string.

**Parameters:**
- `protoString`: Proto3 schema as a string
- `searchDirs`: Optional directories to search for imported files; default @[]
- `extraImportPackages`: Optional list of additional imports to resolve; default @[]

**Returns:** Generated Nim code as string

#### `proc genCodeFromProtoFile*(filePath: string, searchDirs: seq[string] = @[], extraImportPackages: seq[string] = @[]): string`
Generate Nim code from a proto3 file.

**Parameters:**
- `protoFile`: Path to `.proto` file
- `searchDirs`: Directories to search for imported files
- `extraImportPackages`: Optional list of additional imports to resolve

**Returns:** Generated Nim code as string

### Generated API

For each message type, the following procedures are generated:

```nim
# Binary serialization
proc toBinary*(self: MessageType): seq[byte]
proc fromBinary*(T: typedesc[MessageType], data: openArray[byte]): MessageType

# JSON serialization
proc toJson*(self: MessageType): JsonNode
proc fromJson*(T: typedesc[MessageType], node: JsonNode): MessageType
```

For each service definition, gRPC client stubs are generated:

```nim
# Example service:
# service UserService {
#   rpc GetUser(UserRequest) returns (User) {};
#   rpc CreateUser(User) returns (User) {};
#   rpc ListUsers(stream UserRequest) returns (stream User) {};
# }

# Generated async stubs:
proc getUser*(c: GrpcChannel, req: UserRequest, metadata: seq[HpackHeader] = @[]): Future[User]
proc createUser*(c: GrpcChannel, req: User, metadata: seq[HpackHeader] = @[]): Future[User]
proc listUsers*(c: GrpcChannel, reqs: seq[UserRequest]): Future[seq[User]]
```

**RPC signature mapping:**
- Unary: `rpc Method(Req) returns (Resp)` → `proc method(c: GrpcChannel, req: Req, metadata: seq[HpackHeader] = @[]): Future[Resp]`
  - also `proc methodJson(c: GrpcChannel, req: Req, metadata: seq[HpackHeader] = @[]): Future[JsonNode]`, which is useful when data is sparse as fields with default values are skipped in output json node and we parse bytes deirectly into JsonNode rather than bytes->object->json.
- Client streaming: `rpc Method(stream Req) returns (Resp)` → `proc method(c: GrpcChannel, reqs: seq[Req]): Future[Resp]`
  - also `proc methodJson(c: GrpcChannel, reqs: seq[Req]): Future[JsonNode]`
- Server streaming: `rpc Method(Req) returns (stream Resp)` → `proc method(c: GrpcChannel, req: Req): Future[seq[Resp]]`
  - also `proc methodJson(c: GrpcChannel, req: Req): Future[seq[JsonNode]]`
- Bidirectional: `rpc Method(stream Req) returns (stream Resp)` → `proc method(c: GrpcChannel, reqs: seq[Req]): Future[seq[Resp]]`
  - also `proc methodJson(c: GrpcChannel, reqs: seq[Req]): Future[seq[JsonNode]]`

**RPC service endpoints:**
- `test_service.proto:TestService.SimpleTest` → `/TestService/SimpleTest`, or `/package_name.TestService/SimpleTest` if package_name is defined in the .proto file
- `test_service.proto:TestService.StreamTest` → `/TestService/StreamTest`
- `user_service.proto:UserService.GetUser` → `/UserService/GetUser`
- `user_service.proto:UserService.ListUsers` → `/UserService/ListUsers`

## Known Limitations

1. **Multiple imports in one file:** Importing multiple `.proto` files in a single Nim file may cause redefinition errors if they share transitive dependencies. The recommended approach is to import proto files in separate Nim modules.

2. **extensions:** The following proto code won't be parsed:
```proto
  extensions 1000 to 9994 [
    declaration = {
      number: 1000,
      full_name: ".pb.cpp",
      type: ".pb.CppFeatures"
    },
    declaration = {
      number: 1001,
      full_name: ".pb.java",
      type: ".pb.JavaFeatures"
    },
    declaration = { number: 1002, full_name: ".pb.go", type: ".pb.GoFeatures" },
    declaration = {
      number: 9990,
      full_name: ".pb.proto1",
      type: ".pb.Proto1Features"
    }
  ];
```

3. **Need -d:nimOldCaseObjects for oneof fields:**:
- When there is oneof fields in the proto file, you need to add -d:nimOldCaseObjects to the Nim compiler flags, otherwise you will get a compile error: 
```nim
Error: unhandled exception: assignment to discriminant changes object branch; compile with -d:nimOldCaseObjects for a transition period [FieldDefect]
```

## Development

### Running Tests

```bash
# Run all tests
nimble test

# Test individual proto files
nim c -r tests/test6.nim
```

### Debugging Generated Code

Enable `-d:showGeneratedProto3Code` to print the generated Nim code during compile-time macro expansion.

- Prints the command used to generate code and the resulting Nim source.
- Helps diagnose parsing and codegen issues without writing files.

Enable `-d:traceGrpc` to print the network traffic for gRPC calls. This can be helpful for debugging and understanding the communication between the client and server.
- Prints the gRPC method being called and the request/response messages.
- Can be combined with `-d:showGeneratedProto3Code` for more detailed tracing.

Example:

```bash
nim c -r -d:showGeneratedProto3Code tests/test5.nim
```

### Project Structure

```
nimproto3/
├── src/
│   └── nimproto3/
│       ├── ast.nim           # Proto AST definitions
│       ├── parser.nim        # Proto3 parser (npeg-based)
│       ├── codegen.nim       # Code generation
│       ├── codegen_macro.nim # Compile-time macros
│       ├── grpc.nim          # gRPC support
│       └── wire_format.nim   # Binary encoding/decoding
├── tools/
│   └── protonim.nim          # CLI tool
└── tests/
    ├── protos/               # Test proto files
    ├── grpc/                 # gRPC test files: nim/python scripts to cross validate
    ├── grpc_example/         # gRPC example files
    └── test*.nim             # Test suites
```

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues for bugs and feature requests.

## Credits

Built with [npeg](https://github.com/zevv/npeg) parser combinator library.
