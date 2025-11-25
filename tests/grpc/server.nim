import ../../src/nimproto3

importProto3 currentSourcePath.parentDir & "/test_service.proto"
# importProto3 macro will generate the following types and functions
# TestRequest = object
# TestReply = object
# fromBinary*(T: typedesc[TestRequest], data: openArray[byte]): TestRequest
# fromBinary*(T: typedesc[TestReply], data: openArray[byte]): TestReply
# toBinary*(self: TestRequest): seq[byte]
# toBinary*(self: TestReply): seq[byte]
# fromJson*(T: typedesc[TestRequest], node: JsonNode): TestRequest
# fromJson*(T: typedesc[TestReply], node: JsonNode): TestReply
# toJson*(self: TestRequest): JsonNode
# toJson*(self: TestReply): JsonNode
# getUser*(c: GrpcChannel, req: UserRequest, metadata: seq[HpackHeader] = @[]): Future[User]
# listUsers*(c: GrpcChannel, reqs: seq[UserRequest]): Future[seq[User]]

# Handler Signature: proc(stream: GrpcStream): Future[void]
proc handleSimpleTest(stream: GrpcStream) {.async.} =
  # 1. Read Request (Unary = Read 1 message)
  let msgOpt = await stream.recvMsg()

  if msgOpt.isNone:
    echo "[Service] Client closed without sending data?"
    return

  let input = msgOpt.get()
  let req = fromBinary(TestRequest, input)

  # Demonstrate reading Metadata (Headers)
  let auth = stream.headers.getOrDefault("authorization", "none")
  echo "[Service] Received: ", req.message, " (Counter: ", req.counter,
      ") | Auth: ", auth

  # 2. Logic
  let reply = TestReply(
    response: "Server says: " & req.message.toUpperAscii(),
    received: true
  )

  # 3. Send Response (Unary = Send 1 message)
  await stream.sendMsg(toBinary(reply))

  # When this async proc finishes, the server automatically closes the stream
  # and sends the Trailing Headers (Status: OK).

# Example of a Server Streaming handler (returning multiple items)
proc handleStreamTest(stream: GrpcStream) {.async.} =
  # Read incoming requests loop (Bidirectional or Client Stream)
  while true:
    let msgOpt = await stream.recvMsg()
    if msgOpt.isNone: break # End of Stream

    let req = fromBinary(TestRequest, msgOpt.get())
    echo "[Service] Stream item: ", req.message

    # Send a reply immediately (Echo)
    let reply = TestReply(response: "Echo: " & req.message, received: true)
    await stream.sendMsg(toBinary(reply))

# =============================================================================
# MAIN SERVER
# =============================================================================

when isMainModule:
  # Enable server-side compression preference (e.g., Gzip)
  let server = newGrpcServer(50051, CompressionIdentity)

  # Register routes
  server.registerHandler("/TestService/SimpleTest", handleSimpleTest)
  server.registerHandler("/TestService/StreamTest", handleStreamTest)

  echo "Starting gRPC Server (Stream Architecture)..."
  waitFor server.serve()
