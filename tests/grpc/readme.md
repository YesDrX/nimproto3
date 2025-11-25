# Generate python module to be imported by client1.py and client2.py
    - need `nimpy` installed for nim

```bash
nim c -d:showGeneratedProto3Code --app:lib -o:./tests/grpc/serializer.so ./tests/grpc/serializer.nim
```

# Generate pb2 and grpc modules using protoc
    - need `grpcio` and `grpcio-tools` installed for python

```bash
cd tests/grpc
python -m grpc_tools.protoc -I. --python_out=. --grpc_python_out=. test_service.proto
cd ../..
```

# Run Tests
```
python tests/grpc/server.py # start server; or `nim r ./tests/grpc/server.nim`
python tests/grpc/client1.py # client2.py/client3.py; or `nim r ./tests/grpc/client.nim`
```