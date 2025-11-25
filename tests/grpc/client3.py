import grpc
import time
import test_service_pb2 as pb2
import test_service_pb2_grpc as pb2_grpc

def generate_messages():
    """Helper to generate a stream of requests."""
    messages = [
        ("First chunk", 1),
        ("Second chunk", 2),
        ("Third chunk", 3),
        ("Fourth chunk", 4),
    ]
    for msg, count in messages:
        print(f"Client Sending: {msg}, {count}")
        yield pb2.TestRequest(message=msg, counter=count)
        time.sleep(0.5) # Simulate network delay

def run():
    # connect to the server on localhost:50051
    with grpc.insecure_channel('localhost:50051') as channel:
        stub = pb2_grpc.TestServiceStub(channel)

        print("-------------- Unary Call (SimpleTest) --------------")
        # Create a single request object
        # Based on your server: request.message, request.counter
        unary_request = pb2.TestRequest(message="Hello Server", counter=100)
        
        try:
            unary_response = stub.SimpleTest(unary_request)
            print(f"Server Responded: {unary_response.response}")
            print(f"Received Flag: {unary_response.received}")
        except grpc.RpcError as e:
            print(f"RPC failed: {e}")

        print("\n-------------- Streaming Call (StreamTest) --------------")
        # For bidirectional streaming, we pass an iterator (generator) to the stub
        try:
            # We pass the generator function call
            response_iterator = stub.StreamTest(generate_messages())
            
            # We iterate over the responses as they arrive
            for response in response_iterator:
                print(f"Server Streamed Reply: {response.response}")
                
        except grpc.RpcError as e:
            print(f"Stream RPC failed: {e}")

if __name__ == '__main__':
    run()