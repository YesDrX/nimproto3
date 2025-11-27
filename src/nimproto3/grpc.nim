import std/[asyncdispatch, asyncnet, net, strutils, tables,
    deques, options, json, sequtils, sugar]
import ./utils/huffman
import zippy # nimble install zippy
import supersnappy # nimble install supersnappy

# =============================================================================
# 1. CONSTANTS & ENUMS
# =============================================================================

type
  FrameType* = enum
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

  FrameFlags* = enum
    ACK_OR_END_STREAM = 0x1
    END_HEADERS = 0x4
    PADDED = 0x8

  StatusCode* = enum
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

  GrpcError* = object of CatchableError
    code*: StatusCode

  GrpcCompression* = enum
    CompressionIdentity = 0
    CompressionGzip = 1
    CompressionDeflate = 2
    CompressionSnappy = 3

# =============================================================================
# 2. UTILITIES & COMPRESSION
# =============================================================================

type
  AsyncQueue*[T] = ref object
    items: Deque[T]
    waiters: Deque[Future[T]]

proc newAsyncQueue*[T](): AsyncQueue[T] =
  new(result)
  result.items = initDeque[T]()
  result.waiters = initDeque[Future[T]]()

proc put*[T](q: AsyncQueue[T], item: T) =
  if q.waiters.len > 0:
    let fut = q.waiters.popFirst()
    fut.complete(item)
  else:
    q.items.addLast(item)

proc get*[T](q: AsyncQueue[T]): Future[T] =
  var fut = newFuture[T]("AsyncQueue.get")
  if q.items.len > 0:
    fut.complete(q.items.popFirst())
  else:
    q.waiters.addLast(fut)
  return fut

when defined(traceGrpc):
  proc toHex(data : seq[byte]): string =
    data.map(it => it.uint8.toHex).join("")

# --- Compression Helpers ---

proc toHeaderValue(c: GrpcCompression): string =
  case c
  of CompressionIdentity: "identity"
  of CompressionGzip: "gzip"
  of CompressionDeflate: "deflate"
  of CompressionSnappy: "snappy"

proc compressPayload(data: seq[byte], algo: GrpcCompression): seq[byte] =
  if data.len == 0: return data
  case algo
  of CompressionIdentity: return data
  of CompressionGzip: return zippy.compress(data, dataFormat = dfGzip)
  of CompressionDeflate: return zippy.compress(data, dataFormat = dfZlib)
  of CompressionSnappy: return supersnappy.compress(data)

proc decompressPayload(data: seq[byte], encoding: string): seq[byte] =
  if data.len == 0: return data
  case encoding
  of "identity": return data
  of "gzip": return zippy.uncompress(data, dataFormat = dfGzip)
  of "deflate": return zippy.uncompress(data, dataFormat = dfZlib)
  of "snappy": return supersnappy.uncompress(data)
  else:
    raise newException(GrpcError, "Unsupported compression algorithm: " & encoding)

const ACCEPT_ENCODING_VAL = "identity,gzip,deflate,snappy"

# =============================================================================
# 3. HPACK
# =============================================================================
type HpackHeader* = tuple[name: string, value: string]

const STATIC_TABLE: seq[HpackHeader] = @[
  ("", ""), (":authority", ""), (":method", "GET"), (":method", "POST"),
  (":path", "/"), (":path", "/index.html"), (":scheme", "http"),
  (":scheme", "https"), (":status", "200"), (":status", "204"),
  (":status", "304"), (":status", "400"), (":status", "404"),
  (":status", "500"), ("accept-charset", ""), ("accept-encoding",
      "gzip, deflate"),
  ("accept-language", ""), ("accept-ranges", ""), ("accept", ""),
  ("access-control-allow-origin", ""), ("age", ""), ("allow", ""),
  ("authorization", ""), ("cache-control", ""), ("content-disposition", ""),
  ("content-encoding", ""), ("content-language", ""), ("content-length", ""),
  ("content-location", ""), ("content-range", ""), ("content-type", ""),
  ("cookie", ""), ("date", ""), ("etag", ""), ("expect", ""), ("expires", ""),
  ("from", ""), ("host", ""), ("if-match", ""), ("if-modified-since", ""),
  ("if-none-match", ""), ("if-range", ""), ("if-unmodified-since", ""),
  ("last-modified", ""), ("link", ""), ("location", ""), ("max-forwards", ""),
  ("proxy-authenticate", ""), ("proxy-authorization", ""), ("range", ""),
  ("referer", ""), ("refresh", ""), ("retry-after", ""), ("server", ""),
  ("set-cookie", ""), ("strict-transport-security", ""), ("transfer-encoding", ""),
  ("user-agent", ""), ("vary", ""), ("via", ""), ("www-authenticate", ""),
  ("grpc-status", "0"), ("grpc-message", ""), ("content-type",
      "application/grpc"),
  ("te", "trailers"), ("grpc-encoding", "identity"),
  ("grpc-accept-encoding", ACCEPT_ENCODING_VAL)
]

type HpackContext* = ref object
  dynamicTable*: seq[HpackHeader]

proc newHpack*(): HpackContext =
  new(result)
  result.dynamicTable = @[]

proc encodeInteger(value: int, prefixBits: int): seq[byte] =
  var res: seq[byte] = @[]
  let maxPrefix = (1 shl prefixBits) - 1
  var v = value
  if v < maxPrefix:
    res.add(v.byte)
    return res
  res.add(maxPrefix.byte)
  v -= maxPrefix
  while v >= 128:
    res.add((v and 0x7F or 0x80).byte)
    v = v shr 7
  res.add(v.byte)
  return res

proc encodeHeaders*(ctx: HpackContext, headers: openArray[HpackHeader]): seq[byte] =
  var res: seq[byte] = @[]
  for h in headers:
    let (name, value) = h
    res.add(0x00.byte)
    res.add(encodeInteger(name.len, 7))
    for c in name: res.add(c.byte)
    res.add(encodeInteger(value.len, 7))
    for c in value: res.add(c.byte)
  return res

proc decodeInteger(data: seq[byte], startIdx: int, prefixBits: int): tuple[
    value: int, consumed: int] =
  if startIdx >= data.len: return (0, 0)
  let maxPrefix = (1 shl prefixBits) - 1
  let first = data[startIdx].int
  var value = first and maxPrefix
  if value < maxPrefix: return (value, 1)
  var m = 0
  var i = 1
  while (startIdx + i) < data.len:
    let b = data[startIdx + i].int
    value += (b and 0x7F) shl m
    m += 7
    i += 1
    if (b and 0x80) == 0: break
  return (value, i)

proc decodeString(data: seq[byte], startIdx: int): tuple[val: string, consumed: int] =
  if startIdx >= data.len: return ("", 0)
  let huffman = (data[startIdx] and 0x80) != 0
  let (len, consumedLen) = decodeInteger(data, startIdx, 7)
  if startIdx + consumedLen + len > data.len: return ("", data.len - startIdx)
  let strStart = startIdx + consumedLen
  let strBytes = data[strStart ..< strStart + len]
  var s: string
  if huffman:
    s = hpackHuffmanDecode(strBytes)
  else:
    s = newString(len)
    if len > 0: copyMem(addr s[0], unsafeAddr data[strStart], len)
  return (s, consumedLen + len)

proc decodeHeaders*(ctx: HpackContext, data: seq[byte]): seq[HpackHeader] =
  var res: seq[HpackHeader] = @[]
  var i = 0
  while i < data.len:
    let b = data[i].int
    if (b and 0x80) != 0:
      let (idx, consumed) = decodeInteger(data, i, 7)
      i += consumed
      if idx < STATIC_TABLE.len: res.add(STATIC_TABLE[idx])
      else:
        let dynIdx = idx - STATIC_TABLE.len
        if dynIdx < ctx.dynamicTable.len: res.add(ctx.dynamicTable[dynIdx])
    elif (b and 0x40) != 0:
      let (nameIdx, consumed) = decodeInteger(data, i, 6)
      i += consumed
      var name = ""
      if nameIdx == 0:
        let (n, c) = decodeString(data, i)
        name = n
        i += c
      elif nameIdx < STATIC_TABLE.len: name = STATIC_TABLE[nameIdx].name
      let (val, c) = decodeString(data, i)
      i += c
      res.add((name, val))
    elif (b and 0x20) != 0:
      let (size, consumed) = decodeInteger(data, i, 5)
      i += consumed
    else:
      let (nameIdx, consumed) = decodeInteger(data, i, 4)
      i += consumed
      var name = ""
      if nameIdx == 0:
        let (n, c) = decodeString(data, i)
        name = n
        i += c
      elif nameIdx < STATIC_TABLE.len: name = STATIC_TABLE[nameIdx].name
      let (val, c) = decodeString(data, i)
      i += c
      res.add((name, val))
  
  when defined(traceGrpc):
    echo "[gRPC] Decoding headers: ", data.toHex
    echo "[gRPC] Decoded headers: ", res
  return res

# =============================================================================
# 4. HTTP/2 FRAMING
# =============================================================================
type Http2Frame* = object
  length*: uint32
  frameType*: FrameType
  flags*: uint8
  streamId*: uint32
  payload*: seq[byte]

proc packFrame*(ft: FrameType, flags: uint8, streamId: uint32,
    payload: openArray[byte]): seq[byte] =
  let length = payload.len.uint32
  result = newSeq[byte](9 + length)
  result[0] = ((length shr 16) and 0xFF).byte
  result[1] = ((length shr 8) and 0xFF).byte
  result[2] = (length and 0xFF).byte
  result[3] = ft.ord.byte
  result[4] = flags
  result[5] = ((streamId shr 24) and 0x7F).byte
  result[6] = ((streamId shr 16) and 0xFF).byte
  result[7] = ((streamId shr 8) and 0xFF).byte
  result[8] = (streamId and 0xFF).byte
  if length > 0:
    for i in 0 ..< length: result[9+i] = payload[i]

proc parseFrameHeader*(data: seq[byte]): Http2Frame =
  let len = (data[0].uint32 shl 16) or (data[1].uint32 shl 8) or data[2].uint32
  let ft = data[3].FrameType
  let fl = data[4]
  let sid = ((data[5].uint32 and 0x7F) shl 24) or (data[6].uint32 shl 16) or (
      data[7].uint32 shl 8) or data[8].uint32
  result = Http2Frame(length: len, frameType: ft, flags: fl, streamId: sid)

# =============================================================================
# 5. CONNECTION & STREAMS
# =============================================================================

type
  StreamEventKind* = enum
    SE_HEADERS, SE_DATA, SE_TRAILERS, SE_RST

  StreamEvent* = object
    kind*: StreamEventKind
    data*: seq[byte]
    headers*: seq[HpackHeader]
    endStream*: bool

  Http2Stream* = ref object
    id*: uint32
    eventQueue*: AsyncQueue[StreamEvent]
    headers*: Table[string, string]
    trailers*: Table[string, string]
    closed*: bool
    connection*: Http2Connection

  OnNewStreamCallback = proc(s: Http2Stream) {.async.}

  Http2Connection* = ref object
    socket*: AsyncSocket
    host*: string
    port*: Port
    nextStreamId*: uint32
    streams*: TableRef[uint32, Http2Stream]
    hpack*: HpackContext
    windowSize*: int
    connected*: bool
    loopFuture*: Future[void]
    isServer*: bool
    onNewStream*: OnNewStreamCallback

proc newHttp2Connection*(host: string, port: int,
    isServer: bool = false): Http2Connection =
  new(result)
  result.socket = newAsyncSocket()
  result.host = host
  result.port = port.Port
  result.nextStreamId = if isServer: 2 else: 1
  result.streams = newTable[uint32, Http2Stream]()
  result.hpack = newHpack()
  result.windowSize = 65535
  result.isServer = isServer

proc sendFrame*(conn: Http2Connection, frame: seq[byte]) {.async.} =
  if conn.connected:
    try:
      when defined(traceGrpc):
        echo "[gRPC] sending frame: ", frame.toHex
      await conn.socket.send(cast[string](frame))
      when defined(traceGrpc):
        echo "[gRPC] frame sent"
    except:
      conn.connected = false

proc createStream*(conn: Http2Connection, id: uint32 = 0): Http2Stream =
  new(result)
  if id == 0:
    result.id = conn.nextStreamId
    conn.nextStreamId += 2
  else:
    result.id = id

  result.eventQueue = newAsyncQueue[StreamEvent]()
  result.headers = initTable[string, string]()
  result.trailers = initTable[string, string]()
  result.connection = conn
  conn.streams[result.id] = result

proc processFrame*(conn: Http2Connection, frame: Http2Frame, payload: seq[byte]) =
  let isEndStream = (frame.flags and FrameFlags.ACK_OR_END_STREAM.ord.uint8) != 0

  case frame.frameType
  of SETTINGS:
    if (frame.flags and FrameFlags.ACK_OR_END_STREAM.ord.uint8) == 0:
      let ack = packFrame(SETTINGS, FrameFlags.ACK_OR_END_STREAM.ord.uint8, 0, [])
      asyncCheck conn.sendFrame(ack)
  of PING:
    if (frame.flags and FrameFlags.ACK_OR_END_STREAM.ord.uint8) == 0:
      let ack = packFrame(PING, FrameFlags.ACK_OR_END_STREAM.ord.uint8, 0, payload)
      asyncCheck conn.sendFrame(ack)
  of HEADERS:
    var stream: Http2Stream
    var isNew = false
    if conn.streams.hasKey(frame.streamId):
      stream = conn.streams[frame.streamId]
    elif conn.isServer and (frame.streamId mod 2 == 1):
      stream = conn.createStream(frame.streamId)
      isNew = true

    if stream != nil:
      let decoded = decodeHeaders(conn.hpack, payload)
      # Heuristic for Trailers-Only or Trailers
      var isTrailers = stream.headers.len > 0 and isEndStream
      if stream.headers.len == 0 and isEndStream: isTrailers = true

      if isTrailers:
        for h in decoded: stream.trailers[h.name] = h.value
        stream.eventQueue.put(StreamEvent(kind: SE_TRAILERS, headers: decoded,
            endStream: true))
        stream.closed = true
      else:
        for h in decoded: stream.headers[h.name] = h.value
        stream.eventQueue.put(StreamEvent(kind: SE_HEADERS, headers: decoded,
            endStream: isEndStream))
        if isEndStream: stream.closed = true

      if isNew and conn.onNewStream != nil:
        asyncCheck conn.onNewStream(stream)
  of DATA:
    if conn.streams.hasKey(frame.streamId):
      let stream = conn.streams[frame.streamId]
      stream.eventQueue.put(StreamEvent(kind: SE_DATA, data: payload,
          endStream: isEndStream))
      if isEndStream: stream.closed = true
  of RST_STREAM:
    if conn.streams.hasKey(frame.streamId):
      let stream = conn.streams[frame.streamId]
      stream.closed = true
      stream.eventQueue.put(StreamEvent(kind: SE_RST, endStream: true))
  else:
    discard

proc readLoop*(conn: Http2Connection) {.async.} =
  var headerBuf = newString(9)
  try:
    while conn.connected:
      let nRead = await conn.socket.recvInto(addr headerBuf[0], 9)
      if nRead != 9: break
      let rawHeader = cast[seq[byte]](headerBuf)
      let frameHeader = parseFrameHeader(rawHeader)
      var payload: seq[byte] = @[]
      if frameHeader.length > 0:
        let payloadStr = await conn.socket.recv(frameHeader.length.int)
        if payloadStr.len != frameHeader.length.int: break
        payload = cast[seq[byte]](payloadStr)
      conn.processFrame(frameHeader, payload)
  except:
    if conn.connected: discard # echo "Connection error: " & getCurrentExceptionMsg()
    conn.connected = false

proc connect*(conn: Http2Connection) {.async.} =
  await conn.socket.connect(conn.host, conn.port)
  conn.connected = true
  await conn.socket.send("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")
  let settingsPayload: seq[byte] = @[0x00.byte, 0x03.byte, 0x00.byte, 0x00.byte,
      0x00.byte, 0x64.byte]
  await conn.sendFrame(packFrame(SETTINGS, 0, 0, settingsPayload))
  conn.loopFuture = readLoop(conn)

proc acceptHttp2*(conn: Http2Connection) {.async.} =
  conn.connected = true
  let prefaceExpected = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
  let prefaceReceived = await conn.socket.recv(prefaceExpected.len)
  if prefaceReceived != prefaceExpected:
    conn.socket.close()
    conn.connected = false
    raise newException(IOError, "Invalid HTTP/2 Preface : `" & prefaceReceived.toSeq.map(it => it.uint8.toHex).join("") & "` but expect : `" & prefaceExpected.toSeq.map(it => it.uint8.toHex).join("") & "`")
  let settingsPayload: seq[byte] = @[0x00.byte, 0x03.byte, 0x00.byte, 0x00.byte,
      0x00.byte, 0x64.byte]
  await conn.sendFrame(packFrame(SETTINGS, 0, 0, settingsPayload))
  conn.loopFuture = readLoop(conn)

# =============================================================================
# 6. GRPC STREAM ABSTRACTION
# =============================================================================

type GrpcStream* = ref object
  httpStream*: Http2Stream
  isServer*: bool
  sendCompression: GrpcCompression
  recvEncoding: string
  readBuffer: seq[byte]
  # Headers available after call starts (Client) or request received (Server)
  headers*: Table[string, string]
  trailers*: Table[string, string]

proc newGrpcStream(httpStream: Http2Stream, isServer: bool,
    sendComp: GrpcCompression): GrpcStream =
  new(result)
  result.httpStream = httpStream
  result.isServer = isServer
  result.sendCompression = sendComp
  result.recvEncoding = "identity"
  result.readBuffer = @[]
  # Copy headers immediately if available (mostly for server side)
  result.headers = httpStream.headers
  result.trailers = httpStream.trailers

# --- Send Message ---
proc sendMsg*(stream: GrpcStream, data: seq[byte]) {.async.} =
  var finalPayload = compressPayload(data, stream.sendCompression)
  var compFlag: byte = if stream.sendCompression !=
      CompressionIdentity: 1 else: 0

  when defined(traceGrpc):
    echo "[gRPC] sending data: ", data.toHex
  
  var frameData = newSeq[byte]()
  frameData.add(compFlag)
  let length = finalPayload.len.uint32
  frameData.add(((length shr 24) and 0xFF).byte)
  frameData.add(((length shr 16) and 0xFF).byte)
  frameData.add(((length shr 8) and 0xFF).byte)
  frameData.add((length and 0xFF).byte)
  frameData.add(finalPayload)

  await stream.httpStream.connection.sendFrame(packFrame(DATA, 0,
      stream.httpStream.id, frameData))

# --- Send Close (Half Close) ---
proc closeSend*(stream: GrpcStream) {.async.} =
  # Sends an empty DATA frame with END_STREAM set
  await stream.httpStream.connection.sendFrame(packFrame(DATA,
      FrameFlags.ACK_OR_END_STREAM.ord.uint8, stream.httpStream.id, []))

proc recvMsg*(stream: GrpcStream): Future[Option[seq[byte]]] {.async.} =
  while true:
    # 1. Check if we have a complete message in the buffer
    if stream.readBuffer.len >= 5:
      let msgLen = (stream.readBuffer[1].uint32 shl 24) or (stream.readBuffer[2].uint32 shl 16) or
                   (stream.readBuffer[3].uint32 shl 8) or stream.readBuffer[4].uint32
      let totalFrame = 5 + msgLen.int

      if stream.readBuffer.len >= totalFrame:
        let isCompressed = stream.readBuffer[0] == 1
        let payload = stream.readBuffer[5 ..< totalFrame]

        # Remove from buffer
        if stream.readBuffer.len == totalFrame: stream.readBuffer = @[]
        else: stream.readBuffer = stream.readBuffer[totalFrame .. ^1]

        # Decompress and return
        if isCompressed:
          when defined(traceGrpc):
            echo "[gRPC] receiving compressed frame: ", payload.toHex
          return some(decompressPayload(payload, stream.recvEncoding))
        else:
          when defined(traceGrpc):
            echo "[gRPC] receiving uncompressed frame: ", payload.toHex
          return some(payload)

    # 2. Check if the stream is truly finished.
    # We only return EOF if:
    #   a. The stream is marked closed (END_STREAM received).
    #   b. We don't have enough data in the buffer for a frame.
    #   c. AND the event queue is empty. (Pending SE_DATA might still be there!)
    if stream.httpStream.closed and
       stream.readBuffer.len < 5 and
       stream.httpStream.eventQueue.items.len == 0:

      # Check for error trailers
      if stream.httpStream.trailers.hasKey("grpc-status"):
        let status = parseInt(stream.httpStream.trailers["grpc-status"])
        if status != 0:
          let msg = stream.httpStream.trailers.getOrDefault("grpc-message", "Unknown error")
          raise newException(GrpcError, "gRPC Error " & $status & ": " & msg)
      when defined(traceGrpc):
        echo "[gRPC] returning EOF"
      return none(seq[byte])

    # 3. Read more events
    # If the queue has items, this will return immediately.
    let evt = await stream.httpStream.eventQueue.get()

    case evt.kind
    of SE_HEADERS:
      for h in evt.headers:
        stream.headers[h.name] = h.value
        if h.name == "grpc-encoding": stream.recvEncoding = h.value
    of SE_DATA:
      stream.readBuffer.add(evt.data)
    of SE_TRAILERS:
      for h in evt.headers: stream.trailers[h.name] = h.value
    of SE_RST:
      raise newException(IOError, "Stream reset by peer")


# =============================================================================
# 7. GRPC CLIENT
# =============================================================================
type GrpcChannel* = ref object
  conn*: Http2Connection
  compression*: GrpcCompression

proc newGrpcChannel*(host: string, port: int,
    compression: GrpcCompression = CompressionIdentity): GrpcChannel =
  new(result)
  result.conn = newHttp2Connection(host, port, false)
  result.compression = compression

proc newGrpcClient*(host: string, port: int,
    compression: GrpcCompression = CompressionIdentity): GrpcChannel =
  newGrpcChannel(host, port, compression)

proc connect*(chan: GrpcChannel) {.async.} =
  await chan.conn.connect()

proc close*(chan: GrpcChannel) =
  chan.conn.connected = false
  chan.conn.socket.close()

# Start a call and return a Stream object for reading/writing
proc startRpc*(chan: GrpcChannel, methodPath: string, metadata: seq[
    HpackHeader] = @[]): Future[GrpcStream] {.async.} =
  let stream = chan.conn.createStream()

  var headers: seq[HpackHeader] = @[
    (":method", "POST"),
    (":scheme", "http"),
    (":path", methodPath),
    (":authority", chan.conn.host & ":" & $chan.conn.port),
    ("content-type", "application/grpc"),
    ("te", "trailers"),
    ("grpc-accept-encoding", ACCEPT_ENCODING_VAL)
  ]

  if chan.compression != CompressionIdentity:
    headers.add(("grpc-encoding", toHeaderValue(chan.compression)))

  # Add Custom Metadata
  for m in metadata:
    headers.add(m)

  let headerPayload = encodeHeaders(chan.conn.hpack, headers)
  await chan.conn.sendFrame(packFrame(HEADERS, FrameFlags.END_HEADERS.ord.uint8,
      stream.id, headerPayload))

  return newGrpcStream(stream, false, chan.compression)

# Helper for Unary calls that wraps startRpc
proc grpcInvoke*(chan: GrpcChannel, methodPath: string, requests: seq[seq[
    byte]], metadata: seq[HpackHeader] = @[]): Future[seq[seq[
    byte]]] {.async.} =
  let stream = await chan.startRpc(methodPath, metadata)

  # Send all requests
  for req in requests:
    await stream.sendMsg(req)

  await stream.closeSend()

  var responses: seq[seq[byte]] = @[]
  while true:
    let msgOpt = await stream.recvMsg()
    if msgOpt.isNone: break
    responses.add(msgOpt.get())

  return responses

# =============================================================================
# 8. GRPC SERVER
# =============================================================================

# Server Handler now takes the Stream, not bytes
type RpcHandler* = proc(stream: GrpcStream): Future[void] {.gcsafe, async.}

type GrpcServer* = ref object
  socket: AsyncSocket
  port: int
  handlers: Table[string, RpcHandler]
  preferredResponseCompression: GrpcCompression

proc newGrpcServer*(port: int, preferredCompression: GrpcCompression = CompressionIdentity): GrpcServer =
  new(result)
  result.socket = newAsyncSocket()
  result.socket.setSockOpt(OptReuseAddr, true)
  result.port = port
  result.handlers = initTable[string, RpcHandler]()
  result.preferredResponseCompression = preferredCompression

proc registerHandler*(server: GrpcServer, path: string, handler: RpcHandler) =
  server.handlers[path] = handler

proc handleServerStream(server: GrpcServer, httpStream: Http2Stream) {.async.} =
  # 1. Wait for initial headers to know the Path and Encoding
  var methodPath = ""
  var clientEncoding = "identity"

  # We peek or wait? The httpStream logic populates headers on SE_HEADERS.
  # We must wait until headers are received.
  while httpStream.headers.len == 0:
    let evt = await httpStream.eventQueue.get()
    case evt.kind
    of SE_HEADERS:
      for h in evt.headers: httpStream.headers[h.name] = h.value
    else:
      # Push back data events if they arrive before headers (rare but possible in H2)
      httpStream.eventQueue.items.addFirst(evt) # Re-inject at front
      break

  methodPath = httpStream.headers.getOrDefault(":path", "")
  clientEncoding = httpStream.headers.getOrDefault("grpc-encoding", "identity")

  when defined(traceGrpc):
    echo "[gRPC] Received headers: ", httpStream.headers
    echo "[gRPC] Client Encoding: ", clientEncoding
    echo "[gRPC] Method Path: ", methodPath

  if methodPath == "" or not server.handlers.hasKey(methodPath):
    # Method not found
    let trailers: seq[HpackHeader] = @[
      (":status", "200"),
      ("content-type", "application/grpc"),
      ("grpc-status", "12"),
      ("grpc-message", "Method not implemented")
    ]
    let payload = encodeHeaders(httpStream.connection.hpack, trailers)
    let flags = (FrameFlags.END_HEADERS.ord or
        FrameFlags.ACK_OR_END_STREAM.ord).uint8
    await httpStream.connection.sendFrame(packFrame(HEADERS, flags,
        httpStream.id, payload))
    return

  # 2. Negotiate Response Compression
  var sendAlgo = CompressionIdentity
  if server.preferredResponseCompression != CompressionIdentity:
    let accept = httpStream.headers.getOrDefault("grpc-accept-encoding", "")
    if toHeaderValue(server.preferredResponseCompression) in accept:
      sendAlgo = server.preferredResponseCompression

  # 3. Create GrpcStream
  let grpcStream = newGrpcStream(httpStream, true, sendAlgo)
  grpcStream.recvEncoding = clientEncoding

  # 4. Send Initial Headers (Response)
  var respHeaders: seq[HpackHeader] = @[
    (":status", "200"),
    ("content-type", "application/grpc")
  ]
  if sendAlgo != CompressionIdentity:
    respHeaders.add(("grpc-encoding", toHeaderValue(sendAlgo)))

  await httpStream.connection.sendFrame(packFrame(HEADERS,
      FrameFlags.END_HEADERS.ord.uint8, httpStream.id, encodeHeaders(
      httpStream.connection.hpack, respHeaders)))

  # 5. Call Handler
  try:
    await server.handlers[methodPath](grpcStream)
    # 6. Send Trailers (OK) if handler finishes without error
    let trailers: seq[HpackHeader] = @[("grpc-status", "0"), ("grpc-message", "")]
    let flags = (FrameFlags.END_HEADERS.ord or
        FrameFlags.ACK_OR_END_STREAM.ord).uint8
    await httpStream.connection.sendFrame(packFrame(HEADERS, flags,
        httpStream.id, encodeHeaders(httpStream.connection.hpack, trailers)))
  except:
    # Handler crashed
    echo "[Server] Error in handler: ", getCurrentExceptionMsg()
    let trailers: seq[HpackHeader] = @[("grpc-status", "2"), ("grpc-message",
        "Internal Server Error")]
    let flags = (FrameFlags.END_HEADERS.ord or
        FrameFlags.ACK_OR_END_STREAM.ord).uint8
    await httpStream.connection.sendFrame(packFrame(HEADERS, flags,
        httpStream.id, encodeHeaders(httpStream.connection.hpack, trailers)))

proc processClient(server: GrpcServer, socket: AsyncSocket) {.async.} =
  let conn = newHttp2Connection("", 0, isServer = true)
  conn.socket = socket
  conn.onNewStream = proc(s: Http2Stream) {.async.} =
    await server.handleServerStream(s)
  try:
    await conn.acceptHttp2()
  except:
    echo "[Server] Connection error: ", getCurrentExceptionMsg()

proc serve*(server: GrpcServer, ip: string = "0.0.0.0") {.async.} =
  server.socket.bindAddr(server.port.Port, address = ip)
  server.socket.listen()
  echo "[Server] Listening on ", ip, ":", server.port
  while true:
    let clientSock = await server.socket.accept()
    asyncCheck server.processClient(clientSock)
