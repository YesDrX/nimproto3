import ../../src/nimproto3

importProto3 currentSourcePath.parentDir & "/test_service.proto"

# =============================================================================
# MAIN CLIENT TEST
# =============================================================================

when isMainModule:
  proc runTests() {.async.} =
    echo "================================================================================"
    echo "Nim gRPC Client (Stream Architecture)"
    echo "================================================================================"

    # Example 1: Identity + Custom Metadata
    let client = newGrpcClient("localhost", 50051, CompressionIdentity)
    await client.connect()
    await sleepAsync(200) # Wait for settings exchange

    echo "\n[TEST 1] Unary Call with Metadata"
    try:
      # Pass custom authorization header
      let meta = @[("authorization", "Bearer my-secret-token")]
      let reply = await client.simpleTest(
        TestRequest(message: "Hello Metadata", counter: 101),
        metadata = meta
      )
      echo "Reply: ", reply.response
    except:
      echo "Error: ", getCurrentExceptionMsg()

    client.close()

    # Example 2: Gzip Compression
    echo "\n--------------------------------------------------------------------------------"
    echo "Switching to Gzip Compression..."
    let clientGzip = newGrpcClient("localhost", 50051, CompressionGzip)
    await clientGzip.connect()
    await sleepAsync(200)

    echo "\n[TEST 2] Unary Call (Gzip)"
    try:
      let reply = await clientGzip.simpleTest(TestRequest(message: "Hello Gzip", counter: 202))
      echo "Reply: ", reply.response
    except:
      echo "Error: ", getCurrentExceptionMsg()

    clientGzip.close()

    # Example 3: Streaming
    echo "\n--------------------------------------------------------------------------------"
    echo "Streaming Test..."
    let clientStream = newGrpcClient("localhost", 50051, CompressionIdentity)
    await clientStream.connect()
    await sleepAsync(200)

    echo "\n[TEST 3] Bidirectional Stream Echo"
    try:
      let reqs = @[
        TestRequest(message: "Ping 1", counter: 1),
        TestRequest(message: "Ping 2", counter: 2)
      ]
      let replies = await clientStream.streamTest(reqs)
      for r in replies:
        echo "Stream Reply: ", r.response
    except:
      echo "Error: ", getCurrentExceptionMsg()

    clientStream.close()

  waitFor runTests()
