import nimproto3

# check the testing server at : https://grpcb.in/

importProto3 currentSourcePath().parentDir() & "/protos/grpcbin.proto"

proc runTests() {.async.} =
    echo "================================================================================"
    echo "Nim gRPC Client"
    echo "================================================================================"

    # Example 1: Identity + Custom Metadata
    let client = newGrpcClient("grpcb.in", 9000, CompressionIdentity)
    # let client = newGrpcClient("grpcb.in", 9001, CompressionIdentity) # -d:grpcTls

    await client.connect()
    await sleepAsync(200) # Wait for settings exchange
    defer: client.close()
    echo "Response:\n", (await client.index(EmptyMessage()))
    echo "Response:\n", (await client.emptyJson(EmptyMessage()))
    await client.dummyBidirectionalStreamStream(@[DummyMessage(f_string  : "Hello from Nim")])
    echo "Response:\n", (await client.dummyBidirectionalStreamStreamGetResponse())

waitFor runTests()
