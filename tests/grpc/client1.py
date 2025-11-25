import grpc

import serializer # use `python -m grpc_tools.protoc -I. --python_out=. --grpc_python_out=. test_service.proto` to generate; checkout readme.md

# serializer defined in serializer.so
# serializer has the following functions:
# requestToBytes(data: JsonNode): seq[byte]
# responseToBytes(data: JsonNode): seq[byte]
# requestFromBytes(data: seq[byte]): JsonNode
# responseFromBytes(data: seq[byte]): JsonNode

class TestClient:
    def __init__(self, host='localhost:50051'):
        self.channel = grpc.insecure_channel(host)
        self.stub = self.channel.unary_unary(
            '/TestService/SimpleTest',
            request_serializer=lambda x: x,
            response_deserializer=lambda x: x
        )
        self.stream_stub = self.channel.stream_stream(
            '/TestService/StreamTest', 
            request_serializer=lambda x: x,
            response_deserializer=lambda x: x
        )
    
    def simple_test(self, message, counter=1):
        # Use your module's serialization function
        request_bytes = serializer.requestToBytes({
            "message": message, 
            "counter": counter
        })
        
        # Send raw bytes
        response_bytes = self.stub(request_bytes)
        print("sent bytes: " , request_bytes)
        print("response bytes: " , response_bytes)
        
        # Use your module's deserialization function
        return serializer.responseFromBytes(response_bytes)
    
    def stream_test(self, messages_with_counters):
        # Serialize all requests using your module
        request_bytes_list = [
            serializer.requestToBytes({
                "message": msg, 
                "counter": counter
            }) 
            for msg, counter in messages_with_counters
        ]
        
        # Send stream and get responses
        response_bytes_list = self.stream_stub(iter(request_bytes_list))
        
        # Deserialize all responses using your module
        return [
            serializer.responseFromBytes(response_bytes) 
            for response_bytes in response_bytes_list
        ]
    
    def close(self):
        self.channel.close()

# Usage:
client = TestClient()
result = client.simple_test("hello", 123)
print(result)  # {'response': 'Processed: hello', 'received': True}
client.close()