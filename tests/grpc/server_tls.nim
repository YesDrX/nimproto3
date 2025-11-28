{.define: ssl.}

import ../../src/nimproto3
importProto3 currentSourcePath.parentDir & "/test_service.proto"

# Service handlers
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
  import std/asyncdispatch
  
  proc runServer() {.async.} =
    echo "================================================================================"
    echo "Nim gRPC Server with TLS - Local Test"
    echo "================================================================================"
    
    # Create server with TLS support
    let server = newGrpcServer(
        50051,
        CompressionIdentity,
        certFile = currentSourcePath.parentDir() / "server.crt",
        keyFile = currentSourcePath.parentDir() / "server.key"
    )

    server.registerHandler("/TestService/SimpleTest", handleSimpleTest)
    server.registerHandler("/TestService/StreamTest", handleStreamTest)
    
    echo "[Server] Starting TLS server on port 50051..."
    echo "[Server] Waiting for connections..."
    await server.serve()
  
  waitFor runServer()