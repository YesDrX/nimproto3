import ../../src/nimproto3

importProto3 currentSourcePath.parentDir & "/user_service.proto" # full path to the proto file

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
      let reply = await client.getUser(
        UserRequest(id: 1),
        metadata = meta
      )
      echo "Reply: ", reply
    except:
      echo "Error: ", getCurrentExceptionMsg()

    client.close()

  waitFor runTests()
