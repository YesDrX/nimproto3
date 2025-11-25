import grpc
from concurrent import futures
import test_service_pb2 as pb2
import test_service_pb2_grpc as pb2_grpc

class TestServicer(pb2_grpc.TestServiceServicer):
    def SimpleTest(self, request, context):
        print(f"Received: {request.message}, {request.counter}")
        return pb2.TestReply(
            response=f"Processed: {request.message}", 
            received=True
        )
    
    def StreamTest(self, request_iterator, context):
        for request in request_iterator:
            print(f"Stream received: {request.message}, {request.counter}")
            yield pb2.TestReply(
                response=f"Stream processed: {request.message}", 
                received=True
            )

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    pb2_grpc.add_TestServiceServicer_to_server(TestServicer(), server)
    server.add_insecure_port('0.0.0.0:50051')
    server.start()
    print("Server running on port 50051")
    server.wait_for_termination()

if __name__ == '__main__':
    serve()