import nimproto3

# check the testing server at : https://grpcb.in/

importProto3 currentSourcePath().parentDir() & "/protos/grpcbin.proto"

proc runTests() {.async.} =
    echo "================================================================================"
    echo "Nim gRPC Client"
    echo "================================================================================"

    # Example 1: Identity + Custom Metadata
    let client = newGrpcClient("grpcb.in", 9000, CompressionIdentity)
    await client.connect()
    await sleepAsync(200) # Wait for settings exchange
    defer: client.close()
    # echo "Response:\n", (await client.index(EmptyMessage())).repr
    # echo "Response:\n", (await client.empty(EmptyMessage())).repr
    echo "Response:\n", (await client.dummyBidirectionalStreamStream(@[DummyMessage()])).repr

waitFor runTests()
