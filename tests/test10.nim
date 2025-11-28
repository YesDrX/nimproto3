import nimproto3

# check the testing server at : https://grpcb.in/

importProto3 currentSourcePath().parentDir() & "/protos/grpcbin.proto"

proc runTests() {.async.} =
    echo "================================================================================"
    echo "Nim gRPC Client"
    echo "================================================================================"

    # Example 1: Identity + Custom Metadata
    let client = newGrpcClient("grpcb.in", 9000, CompressionIdentity)
    # let client = newGrpcClient("grpcb.in", 9001, CompressionIdentity) # -d:ssl

    await client.connect()
    await sleepAsync(200) # Wait for settings exchange
    defer: client.close()
    echo "Response:\n", (await client.indexJson(EmptyMessage()))
    echo "Response:\n", (await client.emptyJson(EmptyMessage()))
    echo "Response:\n", (await client.dummyBidirectionalStreamStreamJson(@[DummyMessage(f_string  : "Hello from Nim")]))

waitFor runTests()
