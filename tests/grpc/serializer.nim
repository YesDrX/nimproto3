import ../../src/nimproto3
import nimpy

importProto3 currentSourcePath.parentDir & "/test_service.proto"

proc requestFromBytes(data: seq[byte]): JsonNode {.exportpy.} =
    return %*(TestRequest.fromBinary(data))

proc responseFromBytes(data: seq[byte]): JsonNode {.exportpy.} =
    return %*(TestReply.fromBinary(data))

proc requestToBytes(data: JsonNode): seq[byte] {.exportpy.} =
    echo "[Serializer]: ", data.pretty
    return TestRequest.fromJSON(data).toBinary()

proc responseToBytes(data: JsonNode): seq[byte] {.exportpy.} =
    echo "[Serializer]: ", data.pretty
    return TestReply.fromJSON(data).toBinary()
