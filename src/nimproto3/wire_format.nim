## Protobuf wire format encoder/decoder
## Implements the basic protobuf binary format with varint encoding

import streams, strutils

type
  WireType* = enum
    wtVarint = 0          # int32, int64, uint32, uint64, sint32, sint64, bool, enum
    wt64Bit = 1           # fixed64, sfixed64, double
    wtLengthDelimited = 2 # string, bytes, embedded messages, packed repeated
    wt32Bit = 5           # fixed32, sfixed32, float

proc encodeVarint*(value: uint64): seq[byte] =
  ## Encode an unsigned integer as a varint
  var val = value
  result = @[]
  while val >= 0x80'u64:
    result.add(byte((val and 0x7F) or 0x80))
    val = val shr 7
  result.add(byte(val))

proc encodeZigZag*(value: int64): uint64 =
  ## ZigZag encoding for signed integers
  if value >= 0:
    result = uint64(value * 2)
  else:
    result = uint64(value * -2 - 1)

proc decodeVarint*(data: openArray[byte], pos: var int): uint64 =
  ## Decode a varint from byte array, updating pos
  result = 0
  var shift = 0
  while pos < data.len:
    let b = data[pos]
    inc pos
    result = result or (uint64(b and 0x7F) shl shift)
    if (b and 0x80) == 0:
      return
    shift += 7
  raise newException(ValueError, "Invalid varint encoding")

proc decodeZigZag*(value: uint64): int64 =
  ## ZigZag decoding for signed integers
  if (value and 1) == 0:
    result = int64(value shr 1)
  else:
    result = -int64((value + 1) shr 1)

proc encodeFieldKey*(fieldNumber: int, wireType: WireType): seq[byte] =
  ## Encode field number and wire type into a field key
  let key = uint64((fieldNumber shl 3) or int(wireType))
  result = encodeVarint(key)

proc decodeFieldKey*(data: openArray[byte], pos: var int): tuple[
    fieldNumber: int, wireType: WireType] =
  ## Decode field key into field number and wire type
  let key = decodeVarint(data, pos)
  result.fieldNumber = int(key shr 3)
  result.wireType = WireType(key and 0x7)

proc encodeLengthDelimited*(data: openArray[byte]): seq[byte] =
  ## Encode length-delimited data (length prefix + data)
  result = encodeVarint(uint64(data.len))
  for b in data:
    result.add(b)

proc decodeLengthDelimited*(data: openArray[byte], pos: var int): seq[byte] =
  ## Decode length-delimited data
  let length = int(decodeVarint(data, pos))
  result = newSeq[byte](length)
  for i in 0..<length:
    if pos >= data.len:
      raise newException(ValueError, "Unexpected end of data")
    result[i] = data[pos]
    inc pos

# Encoding helpers for specific types
proc encodeInt32*(value: int32): seq[byte] = encodeVarint(uint64(value))
proc encodeInt64*(value: int64): seq[byte] = encodeVarint(uint64(value))
proc encodeUInt32*(value: uint32): seq[byte] = encodeVarint(uint64(value))
proc encodeUInt64*(value: uint64): seq[byte] = encodeVarint(value)
proc encodeSInt32*(value: int32): seq[byte] = encodeVarint(encodeZigZag(value))
proc encodeSInt64*(value: int64): seq[byte] = encodeVarint(encodeZigZag(value))
proc encodeBool*(value: bool): seq[byte] = encodeVarint(
    if value: 1'u64 else: 0'u64)

proc encodeString*(value: string): seq[byte] =
  result = encodeVarint(uint64(value.len))
  for c in value:
    result.add(byte(c))

proc encodeFloat32*(value: float32): seq[byte] =
  result = newSeq[byte](4)
  copyMem(addr result[0], unsafeAddr value, 4)

proc encodeFloat64*(value: float64): seq[byte] =
  result = newSeq[byte](8)
  copyMem(addr result[0], unsafeAddr value, 8)

# Decoding helpers
proc decodeInt32*(data: openArray[byte], pos: var int): int32 =
  int32(decodeVarint(data, pos))

proc decodeInt64*(data: openArray[byte], pos: var int): int64 =
  int64(decodeVarint(data, pos))

proc decodeUInt32*(data: openArray[byte], pos: var int): uint32 =
  uint32(decodeVarint(data, pos))

proc decodeUInt64*(data: openArray[byte], pos: var int): uint64 =
  decodeVarint(data, pos)

proc decodeSInt32*(data: openArray[byte], pos: var int): int32 =
  int32(decodeZigZag(decodeVarint(data, pos)))

proc decodeSInt64*(data: openArray[byte], pos: var int): int64 =
  decodeZigZag(decodeVarint(data, pos))

proc decodeBool*(data: openArray[byte], pos: var int): bool =
  decodeVarint(data, pos) != 0

proc decodeString*(data: openArray[byte], pos: var int): string =
  let bytes = decodeLengthDelimited(data, pos)
  result = newString(bytes.len)
  for i, b in bytes:
    result[i] = char(b)

proc decodeFloat32*(data: openArray[byte], pos: var int): float32 =
  if pos + 4 > data.len:
    raise newException(ValueError, "Unexpected end of data")
  copyMem(addr result, unsafeAddr data[pos], 4)
  pos += 4

proc decodeFloat64*(data: openArray[byte], pos: var int): float64 =
  if pos + 8 > data.len:
    raise newException(ValueError, "Unexpected end of data")
  copyMem(addr result, unsafeAddr data[pos], 8)
  pos += 8
