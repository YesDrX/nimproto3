import ../../src/nimproto3

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

proc handleGetUser(stream: GrpcStream) {.async.} =
  # 1. Read Request (Unary = Read 1 message)
  let msgOpt = await stream.recvMsg()

  if msgOpt.isNone:
    # Client closed without sending data?
    echo "[Service] Client closed without sending data"
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
  let server = newGrpcServer(50051, CompressionGzip)

  # Register routes
  server.registerHandler("/UserService/GetUser", handleGetUser)
  server.registerHandler("/UserService/ListUsers", handleListUsers)

  echo "Starting gRPC Server (Stream Architecture)..."
  waitFor server.serve()
