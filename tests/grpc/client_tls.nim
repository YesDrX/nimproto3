{.define: grpcTls.}
import ../../src/nimproto3

importProto3 currentSourcePath.parentDir & "/test_service.proto"

# =============================================================================
# MAIN CLIENT TEST
# =============================================================================

when isMainModule:
  proc runTests() {.async.} =
    echo "================================================================================"
    echo "Nim gRPC Client with TLS - Local Test"
    echo "================================================================================"

    # Create client with TLS
    let client = newGrpcClient("localhost", 50051, CompressionIdentity, sslVerify = false)
    
    echo "[Client] Connecting to server..."
    await client.connect()
    echo "[Client] Connected, waiting for settings exchange..."
    await sleepAsync(200) # Wait for settings exchange
    echo "[Client] Settings exchange complete"

    echo "\n[Test 1] SimpleTest (Unary)"
    try:
      echo "[Client] Sending SimpleTest request..."
      let reply = await client.simpleTest(
        TestRequest(message: "Hello from Nim TLS client!", counter: 42)
      )
      echo "Response: response='", reply.response, "', received=", reply.received
    except:
      echo "Error: ", getCurrentExceptionMsg()
      echo "Stack trace:"
      echo getCurrentException().getStackTrace()
    
    echo "\n[Test 2] StreamTest (stream)"
    try:
      echo "[Client] Sending StreamTest request..."
      await client.streamTest(
        @[TestRequest(message: "Hello from Nim TLS client!", counter: 37)]
      )
      let response = await client.streamTestGetResponse()
      echo "Response: response='", response
      let addition_response = await client.streamTestGetResponse()
      echo "Response: addition_response='", addition_response
    except:
      echo "Error: ", getCurrentExceptionMsg()
      echo "Stack trace:"
      echo getCurrentException().getStackTrace()

    echo "\n[Test 3] Second StreamTest (stream)"
    try:
      echo "[Client] Sending StreamTest request..."
      await client.streamTest(
        @[TestRequest(message: "Hello from Nim TLS client!", counter: 37)]
      )
      let response = await client.streamTestGetResponse()
      echo "Response: response='", response
      let additional_response = await client.streamTestGetResponse()
      echo "Response: additional_response='", additional_response
      await client.streamTestCloseStream()
    except:
      echo "Error: ", getCurrentExceptionMsg()
      echo "Stack trace:"
      echo getCurrentException().getStackTrace()

    client.close()
    echo "[Client] Connection closed"

    echo "\n================================================================================"
    echo "All tests completed successfully!"
    echo "================================================================================"
  
  waitFor runTests()