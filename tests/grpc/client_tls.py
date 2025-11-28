#!/usr/bin/env python3
"""
gRPC Client with TLS for testing
"""
import grpc
import sys
import os

# Import generated protobuf files
import test_service_pb2
import test_service_pb2_grpc

def run():
    # Read server certificate
    cert_dir = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(cert_dir, 'server.crt'), 'rb') as f:
        cert = f.read()
    
    # Create credentials
    credentials = grpc.ssl_channel_credentials(root_certificates=cert)
    
    # Create channel with TLS
    with grpc.secure_channel('localhost:50051', credentials) as channel:
        stub = test_service_pb2_grpc.TestServiceStub(channel)
        
        # Test 1: Simple unary call
        print("=" * 80)
        print("Test 1: SimpleTest (Unary)")
        print("=" * 80)
        request = test_service_pb2.TestRequest(message="Hello from Python TLS client!", counter=42)
        response = stub.SimpleTest(request)
        print(f"Response: response='{response.response}', received={response.received}")
        
        # Test 2: Bidirectional streaming
        print("\n" + "=" * 80)
        print("Test 2: StreamTest (Bidirectional)")
        print("=" * 80)
        
        def request_generator():
            for i in range(3):
                yield test_service_pb2.TestRequest(message=f"Message {i+1}", counter=i+1)
        
        responses = stub.StreamTest(request_generator())
        for i, response in enumerate(responses):
            print(f"Response {i+1}: response='{response.response}', received={response.received}")
        
        print("\n" + "=" * 80)
        print("All tests completed successfully!")
        print("=" * 80)

if __name__ == '__main__':
    run()
