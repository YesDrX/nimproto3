import nimproto3


# Generated from protobuf
type
  SampleMessageValueKind* = enum
    rkNone  # nothing set
    rkText
    rkNumber
    rkCustom_message
  SampleMessageResultKind* = enum
    rkNone  # nothing set
    rkMsg
    rkId

  SampleMessage* = object
    name*: string
    status_code*: int32
    is_valid*: bool
    tags*: seq[string]
    sub*: SampleMessage_SubMessage
    case valueKind*: SampleMessageValueKind
    of rkNone: discard
    of rkText:
      text*: string
    of rkNumber:
      number*: int32
    of rkCustom_message:
      custom_message*: bool
    case resultKind*: SampleMessageResultKind
    of rkNone: discard
    of rkMsg:
      msg*: string
    of rkId:
      id*: int32


  SampleMessage_SubMessageError_typeKind* = enum
    rkNone  # nothing set
    rkError_text
    rkError_code

  SampleMessage_SubMessage* = object
    detail*: string
    case error_typeKind*: SampleMessage_SubMessageError_typeKind
    of rkNone: discard
    of rkError_text:
      error_text*: string
    of rkError_code:
      error_code*: int32


proc toBinary*(self: SampleMessage): seq[byte]
proc fromBinary*(T: typedesc[SampleMessage], data: openArray[byte]): SampleMessage
proc toJson*(self: SampleMessage): JsonNode
proc fromJson*(T: typedesc[SampleMessage], node: JsonNode): SampleMessage

proc toBinary*(self: SampleMessage_SubMessage): seq[byte]
proc fromBinary*(T: typedesc[SampleMessage_SubMessage], data: openArray[byte]): SampleMessage_SubMessage
proc toJson*(self: SampleMessage_SubMessage): JsonNode
proc fromJson*(T: typedesc[SampleMessage_SubMessage], node: JsonNode): SampleMessage_SubMessage

# Serialization procs for SampleMessage_SubMessage
proc toBinary*(self: SampleMessage_SubMessage): seq[byte] =
  result = @[]
  case self.error_typeKind
  of rkNone:
    discard
  of rkError_text:
    # field 11, wire=2 (length-delimited)
    result.add(encodeFieldKey(11, wtLengthDelimited))
    let s = self.error_text
    result.add(encodeString(s))
  of rkError_code:
    # field 12, wire=0 (varint)
    result.add(encodeFieldKey(12, wtVarint))
    result.add(encodeInt32(self.error_code))
  result.add(encodeFieldKey(10, wtLengthDelimited))
  result.add(encodeString(self.detail))

proc fromBinary*(T: typedesc[SampleMessage_SubMessage], data: openArray[byte]): SampleMessage_SubMessage =
  var pos = 0
  while pos < data.len:
    let (fieldNum, wireType) = decodeFieldKey(data, pos)
    case fieldNum
    of 10:
      result.detail = decodeString(data, pos)
    of 11:
      assert wireType == 2
      let length = int(decodeVarint(data, pos))
      let s = cast[string](data[pos ..< pos+length])
      pos += length
      result.error_typeKind = rkError_text
      result.error_text = decodeString(s)
    of 12:
      assert wireType == 0
      let v = decodeInt32(data, pos)
      result.error_typeKind = rkError_code
      result.error_code = v
    else:
      discard

proc toJson*(self: SampleMessage_SubMessage): JsonNode =
  result = newJObject()
  case self.error_typeKind
  of rkNone:
    discard
  of rkError_text:
    result["error_text"] = %self.error_text
  of rkError_code:
    result["error_code"] = %self.error_code
  result["detail"] = %self.detail

proc fromJson*(T: typedesc[SampleMessage_SubMessage], node: JsonNode): SampleMessage_SubMessage =
  if node.hasKey("error_text"):
    result.error_typeKind = rkError_text
    result.error_text = node["error_text"].getStr
  elif node.hasKey("error_code"):
    result.error_typeKind = rkError_code
    result.error_code = int32(node["error_code"].getInt)
  else:
    result.error_typeKind = rkNone


  if node.hasKey("detail"):
    result.detail = node["detail"].getStr()


# Serialization procs for SampleMessage
proc toBinary*(self: SampleMessage): seq[byte] =
  result = @[]
  case self.valueKind
  of rkNone:
    discard
  of rkText:
    # field 1, wire=2 (length-delimited)
    result.add(encodeFieldKey(1, wtLengthDelimited))
    let s = self.text
    result.add(encodeString(s))
  of rkNumber:
    # field 2, wire=0 (varint)
    result.add(encodeFieldKey(2, wtVarint))
    result.add(encodeInt32(self.number))
  of rkCustom_message:
    # field 3, wire=0 (varint)
    result.add(encodeFieldKey(3, wtVarint))
    result.add(encodeBool(self.custom_message))
  case self.resultKind
  of rkNone:
    discard
  of rkMsg:
    # field 8, wire=2 (length-delimited)
    result.add(encodeFieldKey(8, wtLengthDelimited))
    let s = self.msg
    result.add(encodeString(s))
  of rkId:
    # field 9, wire=0 (varint)
    result.add(encodeFieldKey(9, wtVarint))
    result.add(encodeInt32(self.id))
  result.add(encodeFieldKey(4, wtLengthDelimited))
  result.add(encodeString(self.name))
  result.add(encodeFieldKey(5, wtVarint))
  result.add(encodeInt32(self.status_code))
  result.add(encodeFieldKey(6, wtVarint))
  result.add(encodeBool(self.is_valid))
  for item in self.tags:
    result.add(encodeFieldKey(7, wtLengthDelimited))
    result.add(encodeString(item))
  block:
    let fieldData = toBinary(self.sub)
    if fieldData.len > 0:
      result.add(encodeFieldKey(13, wtLengthDelimited))
      result.add(encodeLengthDelimited(fieldData))

proc fromBinary*(T: typedesc[SampleMessage], data: openArray[byte]): SampleMessage =
  var pos = 0
  while pos < data.len:
    let (fieldNum, wireType) = decodeFieldKey(data, pos)
    case fieldNum
    of 4:
      result.name = decodeString(data, pos)
    of 5:
      result.status_code = decodeInt32(data, pos)
    of 6:
      result.is_valid = decodeBool(data, pos)
    of 7:
      result.tags.add(decodeString(data, pos))
    of 13:
      let fieldData = decodeLengthDelimited(data, pos)
      result.sub = fromBinary(SampleMessage_SubMessage, fieldData)
    of 1:
      assert wireType == 2
      let length = int(decodeVarint(data, pos))
      let s = cast[string](data[pos ..< pos+length])
      pos += length
      result.valueKind = rkText
      result.text = decodeString(s)
    of 2:
      assert wireType == 0
      let v = decodeInt32(data, pos)
      result.valueKind = rkNumber
      result.number = v
    of 3:
      assert wireType == 0
      let v = decodeBool(data, pos)
      result.valueKind = rkCustom_message
      result.custom_message = v
    of 8:
      assert wireType == 2
      let length = int(decodeVarint(data, pos))
      let s = cast[string](data[pos ..< pos+length])
      pos += length
      result.resultKind = rkMsg
      result.msg = decodeString(s)
    of 9:
      assert wireType == 0
      let v = decodeInt32(data, pos)
      result.resultKind = rkId
      result.id = v
    else:
      discard

proc toJson*(self: SampleMessage): JsonNode =
  result = newJObject()
  case self.valueKind
  of rkNone:
    discard
  of rkText:
    result["text"] = %self.text
  of rkNumber:
    result["number"] = %self.number
  of rkCustom_message:
    result["custom_message"] = %self.custom_message
  case self.resultKind
  of rkNone:
    discard
  of rkMsg:
    result["msg"] = %self.msg
  of rkId:
    result["id"] = %self.id
  result["name"] = %self.name
  result["status_code"] = %self.status_code
  result["is_valid"] = %self.is_valid
  result["tags"] = %self.tags
  result["sub"] = %self.sub

proc fromJson*(T: typedesc[SampleMessage], node: JsonNode): SampleMessage =
  if node.hasKey("text"):
    result.valueKind = rkText
    result.text = node["text"].getStr
  elif node.hasKey("number"):
    result.valueKind = rkNumber
    result.number = int32(node["number"].getInt)
  elif node.hasKey("custom_message"):
    result.valueKind = rkCustom_message
    result.custom_message = node["custom_message"].getBool
  else:
    result.valueKind = rkNone
  if node.hasKey("msg"):
    result.resultKind = rkMsg
    result.msg = node["msg"].getStr
  elif node.hasKey("id"):
    result.resultKind = rkId
    result.id = int32(node["id"].getInt)
  else:
    result.resultKind = rkNone


  if node.hasKey("name"):
    result.name = node["name"].getStr()
  if node.hasKey("status_code"):
    result.status_code = int32(node["status_code"].getInt())
  if node.hasKey("is_valid"):
    result.is_valid = node["is_valid"].getBool()
  if node.hasKey("tags"):
    for item in node["tags"]:
      result.tags.add(item.getStr())
  if node.hasKey("sub"):
    result.sub = fromJson(SampleMessage_SubMessage, node["sub"])


