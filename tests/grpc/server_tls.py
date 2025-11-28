#!/usr/bin/env python3
"""
gRPC Server with TLS for testing Nim gRPC client
"""
import grpc
from concurrent import futures
import sys
import os

# Import generated protobuf files
import test_service_pb2
import test_service_pb2_grpc

class TestServiceServicer(test_service_pb2_grpc.TestServiceServicer):
    def SimpleTest(self, request, context):
        print(f"[Server] Received SimpleTest: message='{request.message}', counter={request.counter}")
        return test_service_pb2.TestReply(
            response=f"Echo: {request.message}",
            received=True
        )
    
    def StreamTest(self, request_iterator, context):
        print(f"[Server] Received StreamTest (bidirectional)")
        for request in request_iterator:
            print(f"[Server] Got message: '{request.message}', counter={request.counter}")
            yield test_service_pb2.TestReply(
                response=f"Echo: {request.message}",
                received=True
            )

def serve():
    # Read certificate and key
    cert_dir = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(cert_dir, 'server.crt'), 'rb') as f:
        cert = f.read()
    with open(os.path.join(cert_dir, 'server.key'), 'rb') as f:
        key = f.read()
    
    # Create server credentials
    server_credentials = grpc.ssl_server_credentials([(key, cert)])
    
    # Create server
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    test_service_pb2_grpc.add_TestServiceServicer_to_server(TestServiceServicer(), server)
    
    # Start server with TLS
    port = 50051
    server.add_secure_port(f'[::]:{port}', server_credentials)
    server.start()
    
    print(f"[Server] gRPC Server with TLS started on port {port}")
    print(f"[Server] Using cert: server.crt, key: server.key")
    
    try:
        server.wait_for_termination()
    except KeyboardInterrupt:
        print("\n[Server] Shutting down...")
        server.stop(0)

if __name__ == '__main__':
    serve()
