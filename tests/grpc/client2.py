import socket
import struct
import threading
import queue
import enum
import time
import gzip
from typing import Iterator, Dict, Any, Optional, List, Tuple
import traceback

import serializer # use `python -m grpc_tools.protoc -I. --python_out=. --grpc_python_out=. test_service.proto` to generate; checkout readme.md

# ========== gRPC Status Codes ==========
class StatusCode(enum.IntEnum):
    OK = 0
    CANCELLED = 1
    UNKNOWN = 2
    INVALID_ARGUMENT = 3
    DEADLINE_EXCEEDED = 4
    NOT_FOUND = 5
    ALREADY_EXISTS = 6
    PERMISSION_DENIED = 7
    RESOURCE_EXHAUSTED = 8
    FAILED_PRECONDITION = 9
    ABORTED = 10
    OUT_OF_RANGE = 11
    UNIMPLEMENTED = 12
    INTERNAL = 13
    UNAVAILABLE = 14
    DATA_LOSS = 15
    UNAUTHENTICATED = 16

class GRPCError(Exception):
    def __init__(self, code: StatusCode, message: str, details: bytes = b''):
        self.code = code
        self.message = message
        self.details = details
        super().__init__(f"[Status {code.name} ({code.value})] {message}")

# ========== HTTP/2 Protocol Framework ==========
class FrameType(enum.IntEnum):
    DATA = 0x0
    HEADERS = 0x1
    PRIORITY = 0x2
    RST_STREAM = 0x3
    SETTINGS = 0x4
    PUSH_PROMISE = 0x5
    PING = 0x6
    GOAWAY = 0x7
    WINDOW_UPDATE = 0x8
    CONTINUATION = 0x9

class FrameFlags(enum.IntEnum):
    END_STREAM = 0x1
    ACK = 0x1
    END_HEADERS = 0x4
    PADDED = 0x8

# ========== HTTP/2 Frame Handler ==========
class HTTP2Frame:
    @staticmethod
    def pack_frame(frame_type: int, flags: int, stream_id: int, payload: bytes = b'') -> bytes:
        length = len(payload)
        header = struct.pack('>HBBBL', 
            length >> 8,
            length & 0xFF,
            frame_type,
            flags,
            stream_id & 0x7FFFFFFF
        )
        return header + payload
    
    @staticmethod
    def unpack_header(data: bytes) -> dict:
        if len(data) < 9:
            raise ValueError("Incomplete frame header")
        hi, lo, typ, flags, sid = struct.unpack('>HBBBL', data[:9])
        return {
            'length': (hi << 8) | lo,
            'type': typ,
            'flags': flags,
            'stream_id': sid
        }

# ========== HPACK Encoder/Decoder ==========
class HPACK:
    # RFC 7541 Static Table
    STATIC_TABLE = [
        (None, None),              # 0 - unused
        (':authority', ''),        # 1
        (':method', 'GET'),        # 2
        (':method', 'POST'),       # 3
        (':path', '/'),            # 4
        (':path', '/index.html'),  # 5
        (':scheme', 'http'),       # 6
        (':scheme', 'https'),      # 7
        (':status', '200'),        # 8
        (':status', '204'),        # 9
        (':status', '304'),        # 10
        (':status', '400'),        # 11
        (':status', '404'),        # 12
        (':status', '500'),        # 13
        ('accept-encoding', ''),   # 14
        ('content-type', 'application/grpc'),  # 15
        ('te', 'trailers'),        # 16
    ]
    
    def __init__(self):
        self.dynamic_table = []
        self.max_table_size = 4096
    
    @staticmethod
    def encode_integer(value: int, prefix_bits: int) -> bytes:
        max_prefix = (1 << prefix_bits) - 1
        if value < max_prefix:
            return bytes([value])
        result = [max_prefix]
        value -= max_prefix
        while value >= 128:
            result.append((value & 0x7F) | 0x80)
            value >>= 7
        result.append(value)
        return bytes(result)
    
    def encode(self, headers: Dict[str, str]) -> bytes:
        result = b''
        for name, value in headers.items():
            result += b'\x00'  # Literal without indexing
            result += self.encode_integer(len(name), 7) + name.encode('utf-8')
            result += self.encode_integer(len(value), 7) + value.encode('utf-8')
        return result
    
    @staticmethod
    def decode_integer(data: bytes, prefix_bits: int) -> Tuple[int, int]:
        if not data:
            return 0, 0
        max_prefix = (1 << prefix_bits) - 1
        first = data[0]
        if first < max_prefix:
            return first, 1
        value = max_prefix
        m = 0
        i = 1
        while i < len(data):
            byte = data[i]
            value += (byte & 0x7F) << m
            m += 7
            i += 1
            if not (byte & 0x80):
                break
        return value, i
    
    def decode(self, data: bytes) -> Dict[str, str]:
        headers = {}
        i = 0
        while i < len(data):
            byte = data[i]
            
            if byte & 0x80:  # Indexed header (0b1xxxxxxx)
                index = byte & 0x7F
                i += 1
                
                if index == 0:
                    # Extended index
                    index, consumed = self.decode_integer(data[i:], 7)
                    i += consumed
                
                if index < len(self.STATIC_TABLE):
                    name, value = self.STATIC_TABLE[index]
                    if name is not None:
                        headers[name] = value
            
            elif byte & 0x40:  # Literal with incremental indexing (0b01xxxxxx)
                i += 1
                name_len, consumed = self.decode_integer(data[i:], 6)
                i += consumed
                name = data[i:i+name_len].decode('utf-8')
                i += name_len
                value_len, consumed = self.decode_integer(data[i:], 7)
                i += consumed
                value = data[i:i+value_len].decode('utf-8')
                i += name_len
                headers[name] = value
            
            elif byte & 0x20:  # Dynamic table size update (0b001xxxxx)
                i += 1  # Skip size update
            
            else:  # Literal without indexing (0b0000xxxx or 0b0001xxxx)
                prefix_bits = 4 if (byte & 0xF0) == 0 else 6
                name_index = byte & 0x0F if prefix_bits == 4 else byte & 0x3F
                
                if name_index == 0:
                    # New name
                    i += 1
                    name_len, consumed = self.decode_integer(data[i:], 7)
                    i += consumed
                    name = data[i:i+name_len].decode('utf-8')
                    i += name_len
                else:
                    # Name from static table
                    i += 1
                    if name_index < len(self.STATIC_TABLE):
                        name, _ = self.STATIC_TABLE[name_index]
                    else:
                        name = f":unknown-{name_index}"
                
                # Decode value
                value_len, consumed = self.decode_integer(data[i:], 7)
                i += consumed
                value = data[i:i+value_len].decode('utf-8')
                i += value_len
                headers[name] = value
        
        return headers

# ========== Flow Control ==========
class FlowControl:
    def __init__(self, initial_window: int = 65535):
        self.window_size = initial_window
        self.lock = threading.Lock()
    
    def consume(self, size: int) -> bool:
        with self.lock:
            if self.window_size >= size:
                self.window_size -= size
                return True
            return False
    
    def update(self, increment: int):
        with self.lock:
            self.window_size += increment

# ========== HTTP/2 Stream State Machine ==========
class StreamState(enum.Enum):
    IDLE = 1
    RESERVED_LOCAL = 2
    RESERVED_REMOTE = 3
    OPEN = 4
    HALF_CLOSED_LOCAL = 5
    HALF_CLOSED_REMOTE = 6
    CLOSED = 7

class HTTP2Stream:
    def __init__(self, stream_id: int, connection: 'HTTP2Connection'):
        self.stream_id = stream_id
        self.connection = connection
        self.state = StreamState.IDLE
        self.response_queue = queue.Queue()
        self.flow_control = FlowControl(connection.settings.get(0x4, 65535))
        self.headers = {}
        self.trailers = {}
        self.data = b''
        self.end_stream_received = False
    
    def send_headers(self, headers: Dict[str, str], end_stream: bool = False):
        flags = FrameFlags.END_HEADERS
        if end_stream:
            flags |= FrameFlags.END_STREAM
            self.state = StreamState.HALF_CLOSED_LOCAL
        elif self.state == StreamState.IDLE:
            self.state = StreamState.OPEN
        
        payload = self.connection.hpack.encode(headers)
        frame = HTTP2Frame.pack_frame(FrameType.HEADERS, flags, self.stream_id, payload)
        self.connection.send_frame(frame)
        
        print(f"   [HEADERS] stream={self.stream_id}, flags={flags}")
        for k, v in headers.items():
            print(f"     {k}: {v}")
    
    def send_data(self, data: bytes, end_stream: bool = False):
        frame_size = min(len(data), self.connection.max_frame_size)
        
        while not self.flow_control.consume(frame_size):
            time.sleep(0.001)
        
        flags = FrameFlags.END_STREAM if end_stream else 0
        frame = HTTP2Frame.pack_frame(FrameType.DATA, flags, self.stream_id, data[:frame_size])
        self.connection.send_frame(frame)
        
        compression_flag = data[0] if data else 0
        msg_len = struct.unpack('>I', data[1:5])[0] if len(data) >= 5 else 0
        print(f"   [DATA] stream={self.stream_id}, flags={flags}, compression={compression_flag}, msg_len={msg_len}")
        
        if end_stream:
            self.state = StreamState.HALF_CLOSED_LOCAL
        
        if len(data) > frame_size:
            self.send_data(data[frame_size:], end_stream)

# ========== HTTP/2 Connection ==========
class HTTP2Connection:
    def __init__(self, host: str, port: int):
        self.host = host
        self.port = port
        self.socket = None
        self.hpack = HPACK()
        self.next_stream_id = 1
        self.streams: Dict[int, HTTP2Stream] = {}
        
        self.settings = {
            0x1: 4096,    # HEADER_TABLE_SIZE
            0x2: 0,       # ENABLE_PUSH
            0x3: 100,     # MAX_CONCURRENT_STREAMS
            0x4: 65535,   # INITIAL_WINDOW_SIZE
            0x5: 16384,   # MAX_FRAME_SIZE
            0x6: 8192,    # MAX_HEADER_LIST_SIZE
        }
        self.max_frame_size = 16384
        self.conn_flow_control = FlowControl()
        self._lock = threading.RLock()
        self._running = False
        self._recv_thread = None
        self._ping_response = threading.Event()
        self._last_ping_data = b''
    
    def connect(self):
        print("\n" + "="*80)
        print("[=== ESTABLISHING HTTP/2 CONNECTION ===]")
        print("="*80)
        
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.socket.connect((self.host, self.port))
        
        preface = b'PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n'
        self.socket.sendall(preface)
        print(f"\n→ Connection Preface (24 bytes):")
        print(f"   ASCII:   PRI * HTTP/2.0\\r\\n\\r\\nSM\\r\\n\\r\\n")
        print(f"   Hex:     {preface.hex()}")
        
        settings_payload = b''.join([
            struct.pack('>HI', k, v) for k, v in self.settings.items()
        ])
        settings_frame = HTTP2Frame.pack_frame(FrameType.SETTINGS, 0, 0, settings_payload)
        self.send_frame(settings_frame)
        print(f"\n→ SETTINGS Frame ({len(settings_frame)} bytes):")
        print(f"   Hex:     {settings_frame.hex()}")
        print(f"   Payload: {len(self.settings)} settings")
        
        self._running = True
        self._recv_thread = threading.Thread(target=self._recv_loop, daemon=True)
        self._recv_thread.start()
        
        time.sleep(0.2)
    
    def send_frame(self, frame: bytes):
        with self._lock:
            self.socket.sendall(frame)
            print(f"\n→ OUTBOUND FRAME ({len(frame)} bytes):")
            print(f"   Hex: {frame.hex()}")
    
    def _recv_loop(self):
        buffer = b''
        while self._running:
            try:
                data = self.socket.recv(4096)
                if not data:
                    break
                buffer += data
                print(f"\n← INBOUND DATA ({len(data)} bytes):")
                print(f"   Hex: {data.hex()}")
                
                while len(buffer) >= 9:
                    header = HTTP2Frame.unpack_header(buffer)
                    frame_size = 9 + header['length']
                    
                    if len(buffer) < frame_size:
                        break
                    
                    frame = buffer[:frame_size]
                    buffer = buffer[frame_size:]
                    self._process_frame(header, frame[9:])
                    
            except Exception as e:
                print(f"\n[ERROR] {e}")
                traceback.print_exc()
                break
    
    def _process_frame(self, header: dict, payload: bytes):
        print(f"\n   [FRAME PARSED]")
        print(f"   Type: {FrameType(header['type']).name} ({header['type']})")
        print(f"   Stream ID: {header['stream_id']}")
        print(f"   Flags: {header['flags']} (0x{header['flags']:02x})")
        print(f"   Payload Length: {header['length']} bytes")
        
        frame_type = header['type']
        stream_id = header['stream_id']
        flags = header['flags']
        is_end = bool(flags & FrameFlags.END_STREAM)
        
        if frame_type == FrameType.SETTINGS:
            if not (flags & FrameFlags.ACK):
                for i in range(0, len(payload), 6):
                    if i + 6 <= len(payload):
                        id_val, value = struct.unpack('>HI', payload[i:i+6])
                        self.settings[id_val] = value
                        print(f"   → Setting: id=0x{id_val:04x}, value={value}")
                
                ack_frame = HTTP2Frame.pack_frame(FrameType.SETTINGS, FrameFlags.ACK, 0, b'')
                self.send_frame(ack_frame)
            else:
                print("   ← Received SETTINGS ACK")
        
        elif frame_type == FrameType.PING:
            ping_data = payload[:8] if len(payload) >= 8 else payload
            if flags & FrameFlags.ACK:
                self._last_ping_data = ping_data
                self._ping_response.set()
                print(f"   ← PING ACK: {ping_data.hex()}")
            else:
                ack_frame = HTTP2Frame.pack_frame(FrameType.PING, FrameFlags.ACK, 0, ping_data)
                self.send_frame(ack_frame)
                print(f"   → PING ACK response: {ping_data.hex()}")
        
        elif frame_type == FrameType.WINDOW_UPDATE:
            if len(payload) >= 4:
                increment = struct.unpack('>I', payload[:4])[0] & 0x7FFFFFFF
                print(f"   ← WINDOW_UPDATE: increment={increment}")
                if stream_id == 0:
                    self.conn_flow_control.update(increment)
                else:
                    with self._lock:
                        if stream_id in self.streams:
                            self.streams[stream_id].flow_control.update(increment)
        
        elif frame_type == FrameType.GOAWAY:
            if len(payload) >= 8:
                last_stream_id = struct.unpack('>I', payload[:4])[0] & 0x7FFFFFFF
                error_code = struct.unpack('>I', payload[4:8])[0]
                debug_data = payload[8:].decode('utf-8', errors='ignore')
                print(f"   ← GOAWAY: last_stream={last_stream_id}, error={error_code} ({debug_data})")
                self._running = False
        
        elif frame_type == FrameType.RST_STREAM:
            if len(payload) >= 4:
                error_code = struct.unpack('>I', payload[:4])[0]
                print(f"   ← RST_STREAM: error_code={error_code}")
                # RST_STREAM with error_code=0 is normal cleanup, not an error
                if error_code != 0 and stream_id in self.streams:
                    self.streams[stream_id].response_queue.put((None, None, True))
        
        elif frame_type in (FrameType.HEADERS, FrameType.DATA):
            with self._lock:
                if stream_id not in self.streams:
                    if stream_id % 2 == 0:
                        self.streams[stream_id] = HTTP2Stream(stream_id, self)
            
            stream = self.streams[stream_id]
            
            if frame_type == FrameType.HEADERS:
                decoded_headers = self.hpack.decode(payload)
                
                # **ULTIMATE FIX**: Check END_STREAM flag to detect trailers-only
                if is_end and not stream.data:
                    # Trailers-only response (immediate error/success)
                    stream.trailers.update(decoded_headers)
                    stream.end_stream_received = True
                else:
                    # Normal headers or trailers after data
                    if not stream.headers:
                        stream.headers.update(decoded_headers)
                    else:
                        stream.trailers.update(decoded_headers)
                
                print(f"   ← HEADERS: {len(decoded_headers)} headers")
                for k, v in decoded_headers.items():
                    print(f"      {k}: {v}")
                
                if is_end:
                    stream.end_stream_received = True
            
            elif frame_type == FrameType.DATA:
                self.conn_flow_control.consume(len(payload))
                stream.flow_control.consume(len(payload))
                stream.data += payload
                
                if len(payload) >= 5:
                    compression = payload[0]
                    msg_len = struct.unpack('>I', payload[1:5])[0]
                    print(f"   ← DATA: compression={compression}, msg_len={msg_len}")
                
                if is_end:
                    stream.end_stream_received = True
            
            stream.response_queue.put((frame_type, payload, is_end))
    
    def create_stream(self) -> HTTP2Stream:
        with self._lock:
            stream_id = self.next_stream_id
            self.next_stream_id += 2
            stream = HTTP2Stream(stream_id, self)
            self.streams[stream_id] = stream
            return stream
    
    def send_ping(self, data: bytes = b'\x00' * 8) -> bool:
        self._ping_response.clear()
        ping_frame = HTTP2Frame.pack_frame(FrameType.PING, 0, 0, data)
        self.send_frame(ping_frame)
        print(f"\n→ PING: {data.hex()}")
        return self._ping_response.wait(timeout=5)
    
    def close(self):
        print("\n" + "="*80)
        print("[=== GRACEFUL SHUTDOWN ===]")
        print("="*80)
        
        with self._lock:
            self._running = False
            goaway_payload = struct.pack('>I', self.next_stream_id - 2) + b'Normal shutdown'
            goaway_frame = HTTP2Frame.pack_frame(FrameType.GOAWAY, 0, 0, goaway_payload)
            self.send_frame(goaway_frame)
            
            self.socket.close()
            print("✓ Connection closed")

# ========== gRPC Channel (ULTIMATE FIX) ==========
class gRPCChannel:
    def __init__(self, host: str, port: int):
        self.conn = HTTP2Connection(host, port)
        self.conn.connect()
    
    def _invoke(self, method: str, requests: Iterator[bytes], 
                timeout: Optional[float] = None, 
                metadata: Optional[Dict[str, str]] = None) -> Tuple[Dict[str, str], Iterator[bytes]]:
        
        stream = self.conn.create_stream()
        
        # Prepare headers
        headers = {
            ':method': 'POST',
            ':path': method,
            ':scheme': 'http',
            ':authority': f'{self.conn.host}:{self.conn.port}',
            'content-type': 'application/grpc',
            'te': 'trailers',
            'grpc-accept-encoding': 'gzip,identity',
        }
        
        if timeout:
            headers['grpc-timeout'] = f'{int(timeout * 1000)}m'
        
        if metadata:
            headers.update(metadata)
        
        # Send HEADERS
        stream.send_headers(headers)
        
        # Send requests with gRPC prefix
        for req in requests:
            grpc_prefix = b'\x00' + struct.pack('>I', len(req))
            stream.send_data(grpc_prefix + req, end_stream=False)
        
        # Half-close stream
        stream.send_data(b'', end_stream=True)
        
        # Receive responses
        def response_iterator():
            response_data = b''
            headers_received = False
            
            while not stream.end_stream_received:
                try:
                    frame_type, payload, is_end = stream.response_queue.get(timeout=timeout)
                    
                    if frame_type == FrameType.HEADERS:
                        decoded_headers = self.conn.hpack.decode(payload)
                        
                        if not headers_received:
                            # **ULTIMATE FIX**: Check if this is trailers-only response
                            if is_end:
                                # Trailers-only response (immediate error/success)
                                headers_received = True
                                stream.trailers.update(decoded_headers)
                                
                                # Check for gRPC status
                                grpc_status = stream.trailers.get('grpc-status')
                                if grpc_status is not None:
                                    status = int(grpc_status)
                                    if status != 0:
                                        raise GRPCError(StatusCode(status), 
                                                      stream.trailers.get('grpc-message', ''))
                                    # status=0 means success but no data (rare)
                                    break
                                else:
                                    # No grpc-status, assume success but no data
                                    break
                            else:
                                # Normal initial headers
                                headers_received = True
                                stream.headers.update(decoded_headers)
                                print(f"\n   ← Initial Response HEADERS:")
                                for k, v in stream.headers.items():
                                    print(f"      {k}: {v}")
                        else:
                            # TRAILING HEADERS (after DATA)
                            stream.trailers.update(decoded_headers)
                            print(f"\n   ← Trailers:")
                            for k, v in stream.trailers.items():
                                print(f"      {k}: {v}")
                            
                            if is_end:
                                status = int(stream.trailers.get('grpc-status', '0'))
                                if status != 0:
                                    raise GRPCError(StatusCode(status), 
                                                  stream.trailers.get('grpc-message', ''))
                                break
                    
                    elif frame_type == FrameType.DATA:
                        if len(payload) >= 5:
                            encoding = stream.headers.get('grpc-encoding', 'identity')
                            msg = self._decompress(payload, encoding)
                            yield msg
                    
                except queue.Empty:
                    raise GRPCError(StatusCode.DEADLINE_EXCEEDED, "Deadline exceeded")
        
        return stream.headers, response_iterator()
    
    def _decompress(self, payload: bytes, encoding: str) -> bytes:
        if len(payload) < 5:
            return b''
        
        compression = payload[0]
        msg_len = struct.unpack('>I', payload[1:5])[0]
        msg = payload[5:5+msg_len]
        
        if encoding == 'gzip':
            return gzip.decompress(msg)
        return msg
    
    # All four gRPC method types
    def unary_unary(self, method: str, request: bytes, **kwargs) -> bytes:
        _, responses = self._invoke(method, iter([request]), **kwargs)
        try:
            return next(responses)
        except StopIteration:
            raise GRPCError(StatusCode.UNKNOWN, 
                          "Server closed stream without response (method not found or no data)")
    
    def unary_stream(self, method: str, request: bytes, **kwargs) -> Iterator[bytes]:
        _, responses = self._invoke(method, iter([request]), **kwargs)
        return responses
    
    def stream_unary(self, method: str, requests: Iterator[bytes], **kwargs) -> bytes:
        _, responses = self._invoke(method, requests, **kwargs)
        try:
            return next(responses)
        except StopIteration:
            raise GRPCError(StatusCode.UNKNOWN, 
                          "Server closed stream without response (method not found or no data)")
    
    def stream_stream(self, method: str, requests: Iterator[bytes], **kwargs) -> Iterator[bytes]:
        _, responses = self._invoke(method, requests, **kwargs)
        return responses
    
    def close(self):
        self.conn.close()
    
    def ping(self) -> float:
        start = time.time()
        if self.conn.send_ping():
            return time.time() - start
        raise GRPCError(StatusCode.UNAVAILABLE, "Ping timeout")

# ========== Complete gRPC Stub ==========
class TestStub:
    def __init__(self, channel: gRPCChannel):
        self.channel = channel
    
    def simple_test(self, message: str, counter: int, **kwargs):
        """
        Unary-Unary RPC: /TestService/SimpleTest
        """
        request = serializer.requestToBytes({"message": message, "counter": counter})
        response = self.channel.unary_unary('/TestService/SimpleTest', request, **kwargs)
        return serializer.responseFromBytes(response)
        
    def stream_test(self, messages: List[Tuple[str, int]], **kwargs):
        """
        Stream-Stream RPC: Bidirectional streaming
        """
        requests = (serializer.requestToBytes({"message": msg, "counter": c}) for msg, c in messages)
        responses = self.channel.stream_stream('/TestService/StreamTest', requests, **kwargs)
        return [serializer.responseFromBytes(r) for r in responses]

# ========== Complete Test Client ==========
class TestClient:
    def __init__(self, host='localhost', port=50051):
        self.channel = gRPCChannel(host, port)
        self.stub = TestStub(self.channel)
    
    def simple_test(self, message, counter=1, timeout=None):
        return self.stub.simple_test(message, counter, timeout=timeout)
    
    def stream_test(self, messages, timeout=None):
        return self.stub.stream_test(messages, timeout=timeout)
    
    def ping(self):
        return self.channel.ping()
    
    def close(self):
        self.channel.close()

# ========== Usage Examples with Detailed Byte Analysis ==========
if __name__ == '__main__':
    client = TestClient()
    
    print("\n" + "="*80)
    print("📡 TEST 1: UNARY-UNARY RPC")
    print("="*80)
    print("Client sends single request, receives single response")
    print("Flow: HEADERS → DATA(END_STREAM) → HEADERS → DATA → HEADERS(trailers)")
    
    result = client.simple_test("hello world", 42)
    print(f"\n✓ Result: {result}")
    
    print("\n" + "="*80)
    print("📡 TEST 2: SERVER STREAMING (Unary-Stream)")
    print("="*80)
    print("Client sends one request, server streams multiple responses")
    
    print("\n" + "="*80)
    print("📡 TEST 3: CLIENT STREAMING (Stream-Unary)")
    print("="*80)
    print("Client streams multiple requests, server returns single response")
       
    print("\n" + "="*80)
    print("📡 TEST 4: BIDIRECTIONAL STREAMING")
    print("="*80)
    print("Both client and server stream messages concurrently")
    
    stream_results = client.stream_test([("ping", 1), ("pong", 2), ("final", 3)])
    print(f"\n✓ Stream Results: {stream_results}")
    
    print("\n" + "="*80)
    print("📡 TEST 5: CONNECTION HEALTH CHECK (PING)")
    print("="*80)
    print("HTTP/2 PING frame: 9-byte header + 8-byte payload")
    
    try:
        rtt = client.ping()
        print(f"\n✓ Round-trip time: {rtt*1000:.2f}ms")
    except GRPCError as e:
        print(f"\n✗ Ping failed: {e}")
    
    print("\n" + "="*80)
    print("📡 TEST 6: TIMEOUT HANDLING")
    print("="*80)
    print("Sets grpc-timeout header, server should respect it")
    
    try:
        client.simple_test("slow", 1, timeout=0.001)
    except GRPCError as e:
        print(f"\n✓ Expected timeout error: {e}")
    
    print("\n" + "="*80)
    print("📡 TEST 7: CUSTOM METADATA")
    print("="*80)
    print("Sends custom headers in HPACK format")
    
    metadata = {'custom-header': 'test-value', 'x-request-id': '12345'}
    result = client.stub.simple_test("with metadata", 999, metadata=metadata)
    print(f"\n✓ Result: {result}")
    
    client.close()