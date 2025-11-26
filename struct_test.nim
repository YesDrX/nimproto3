import nimproto3


# Generated from protobuf
type
  Google_protobuf_Struct* = object
    fields*: Table[string, Google_protobuf_google_protobuf_Value]


  Google_protobuf_ValueKindKind* = enum
    rkNone  # nothing set
    rkNull_value
    rkNumber_value
    rkString_value
    rkBool_value
    rkStruct_value
    rkList_value

  Google_protobuf_Value* = object
    case kindKind*: Google_protobuf_ValueKindKind
    of rkNone: discard
    of rkNull_value:
      null_value*: Google_protobuf_NullValue
    of rkNumber_value:
      number_value*: float64
    of rkString_value:
      string_value*: string
    of rkBool_value:
      bool_value*: bool
    of rkStruct_value:
      struct_value*: Google_protobuf_Struct
    of rkList_value:
      list_value*: Google_protobuf_ListValue


  Google_protobuf_NullValue* = enum
    NULL_VALUE


  Google_protobuf_ListValue* = object
    values*: seq[Google_protobuf_Value]


  StructMessage* = object
    config*: Google_protobuf_Struct
    value*: Google_protobuf_Value
    list*: Google_protobuf_ListValue


proc toBinary*(self: Google_protobuf_Struct): seq[byte]
proc fromBinary*(T: typedesc[Google_protobuf_Struct], data: openArray[byte]): Google_protobuf_Struct
proc toJson*(self: Google_protobuf_Struct): JsonNode
proc fromJson*(T: typedesc[Google_protobuf_Struct], node: JsonNode): Google_protobuf_Struct

proc toBinary*(self: Google_protobuf_Value): seq[byte]
proc fromBinary*(T: typedesc[Google_protobuf_Value], data: openArray[byte]): Google_protobuf_Value
proc toJson*(self: Google_protobuf_Value): JsonNode
proc fromJson*(T: typedesc[Google_protobuf_Value], node: JsonNode): Google_protobuf_Value

proc toBinary*(self: Google_protobuf_ListValue): seq[byte]
proc fromBinary*(T: typedesc[Google_protobuf_ListValue], data: openArray[byte]): Google_protobuf_ListValue
proc toJson*(self: Google_protobuf_ListValue): JsonNode
proc fromJson*(T: typedesc[Google_protobuf_ListValue], node: JsonNode): Google_protobuf_ListValue

proc toBinary*(self: StructMessage): seq[byte]
proc fromBinary*(T: typedesc[StructMessage], data: openArray[byte]): StructMessage
proc toJson*(self: StructMessage): JsonNode
proc fromJson*(T: typedesc[StructMessage], node: JsonNode): StructMessage

# Serialization procs for Google_protobuf_Struct
proc toBinary*(self: Google_protobuf_Struct): seq[byte] =
  result = @[]
  for key, val in self.fields:
    var entry = newSeq[byte]()
    entry.add(encodeFieldKey(1, wtLengthDelimited))
    entry.add(encodeString(key))
    entry.add(encodeFieldKey(2, wtLengthDelimited))
    let valData = toBinary(val)
    entry.add(encodeLengthDelimited(valData))
    result.add(encodeFieldKey(1, wtLengthDelimited))
    result.add(encodeLengthDelimited(entry))

proc fromBinary*(T: typedesc[Google_protobuf_Struct], data: openArray[byte]): Google_protobuf_Struct =
  var pos = 0
  while pos < data.len:
    let (fieldNum, wireType) = decodeFieldKey(data, pos)
    case fieldNum
    of 1:
      let entryData = decodeLengthDelimited(data, pos)
      var entryPos = 0
      var key: string
      var val: Google_protobuf_google_protobuf_Value
      while entryPos < entryData.len:
        let (fNum, wType) = decodeFieldKey(entryData, entryPos)
        case fNum
        of 1:
          key = decodeString(entryData, entryPos)
        of 2:
          let valData = decodeLengthDelimited(entryData, entryPos)
          val = fromBinary(Google_protobuf_google_protobuf_Value, valData)
        else: discard
      result.fields[key] = val
    else:
      discard

proc toJson*(self: Google_protobuf_Struct): JsonNode =
  result = newJObject()
  var fieldsJson = newJObject()
  for key, val in self.fields:
    fieldsJson[$key] = %val
  result["fields"] = fieldsJson

proc fromJson*(T: typedesc[Google_protobuf_Struct], node: JsonNode): Google_protobuf_Struct =
  discard
  if node.hasKey("fields"):
    for keyStr, valNode in node["fields"]:
      let key = keyStr
      result.fields[key] = fromJson(Google_protobuf_google_protobuf_Value, valNode)


  if node.hasKey("fields"):
    for keyStr, valNode in node["fields"]:
      let key = keyStr
      result.fields[key] = fromJson(Google_protobuf_google_protobuf_Value, valNode)


# Serialization procs for Google_protobuf_Value
proc toBinary*(self: Google_protobuf_Value): seq[byte] =
  result = @[]
  case self.kindKind
  of rkNone:
    discard
  of rkNull_value:
    # field 1, wire=0 (varint)
    result.add(encodeFieldKey(1, wtVarint))
    result.add(encodeVarint(uint64(int(self.null_value))))
  of rkNumber_value:
    # field 2, wire=0 (varint)
    result.add(encodeFieldKey(2, wtVarint))
    result.add(encodeFloat64(self.number_value))
  of rkString_value:
    # field 3, wire=2 (length-delimited)
    result.add(encodeFieldKey(3, wtLengthDelimited))
    let s = self.string_value
    result.add(encodeString(s))
  of rkBool_value:
    # field 4, wire=0 (varint)
    result.add(encodeFieldKey(4, wtVarint))
    result.add(encodeBool(self.bool_value))
  of rkStruct_value:
    # field 5, wire=2 (length-delimited)
    result.add(encodeFieldKey(5, wtLengthDelimited))
    let msgData = toBinary(self.struct_value)
    result.add(encodeVarint(uint64(msgData.len)))
    result.add(msgData)
  of rkList_value:
    # field 6, wire=2 (length-delimited)
    result.add(encodeFieldKey(6, wtLengthDelimited))
    let msgData = toBinary(self.list_value)
    result.add(encodeVarint(uint64(msgData.len)))
    result.add(msgData)

proc fromBinary*(T: typedesc[Google_protobuf_Value], data: openArray[byte]): Google_protobuf_Value =
  var pos = 0
  while pos < data.len:
    let (fieldNum, wireType) = decodeFieldKey(data, pos)
    case fieldNum
    of 1:
      assert wireType == 0
      let v = Google_protobuf_NullValue(int32(decodeVarint(data, pos)))
      result.kindKind = rkNull_value
      result.null_value = v
    of 2:
      assert wireType == 0
      let v = decodeFloat64(data, pos)
      result.kindKind = rkNumber_value
      result.number_value = v
    of 3:
      assert wireType == 2
      let length = int(decodeVarint(data, pos))
      let s = cast[string](data[pos ..< pos+length])
      pos += length
      result.kindKind = rkString_value
      result.string_value = decodeString(s)
    of 4:
      assert wireType == 0
      let v = decodeBool(data, pos)
      result.kindKind = rkBool_value
      result.bool_value = v
    of 5:
      assert wireType == 2
      let length = int(decodeVarint(data, pos))
      let msgData = data[pos ..< pos+length]
      pos += length
      result.kindKind = rkStruct_value
      result.struct_value = fromBinary(Google_protobuf_Struct, msgData)
    of 6:
      assert wireType == 2
      let length = int(decodeVarint(data, pos))
      let msgData = data[pos ..< pos+length]
      pos += length
      result.kindKind = rkList_value
      result.list_value = fromBinary(Google_protobuf_ListValue, msgData)
    else:
      discard

proc toJson*(self: Google_protobuf_Value): JsonNode =
  result = newJObject()
  case self.kindKind
  of rkNone:
    discard
  of rkNull_value:
    result["null_value"] = %self.null_value
  of rkNumber_value:
    result["number_value"] = %self.number_value
  of rkString_value:
    result["string_value"] = %self.string_value
  of rkBool_value:
    result["bool_value"] = %self.bool_value
  of rkStruct_value:
    result["struct_value"] = %self.struct_value
  of rkList_value:
    result["list_value"] = %self.list_value

proc fromJson*(T: typedesc[Google_protobuf_Value], node: JsonNode): Google_protobuf_Value =
  if node.hasKey("null_value"):
    result.kindKind = rkNull_value
    result.null_value = fromJson(Google_protobuf_NullValue, node["null_value"])
  elif node.hasKey("number_value"):
    result.kindKind = rkNumber_value
    result.number_value = float64(node["number_value"].getFloat)
  elif node.hasKey("string_value"):
    result.kindKind = rkString_value
    result.string_value = node["string_value"].getStr
  elif node.hasKey("bool_value"):
    result.kindKind = rkBool_value
    result.bool_value = node["bool_value"].getBool
  elif node.hasKey("struct_value"):
    result.kindKind = rkStruct_value
    result.struct_value = fromJson(Google_protobuf_Struct, node["struct_value"])
  elif node.hasKey("list_value"):
    result.kindKind = rkList_value
    result.list_value = fromJson(Google_protobuf_ListValue, node["list_value"])
  else:
    result.kindKind = rkNone




proc toBinary*(self: Google_protobuf_NullValue): seq[byte] =
  result = encodeInt32(int32(self))

proc fromBinary*(T: typedesc[Google_protobuf_NullValue], data: openArray[byte]): Google_protobuf_NullValue =
  var pos = 0
  result = Google_protobuf_NullValue(decodeInt32(data, pos))

proc toJson*(self: Google_protobuf_NullValue): JsonNode =
  result = %int(self)

proc fromJson*(T: typedesc[Google_protobuf_NullValue], node: JsonNode): Google_protobuf_NullValue =
  result = Google_protobuf_NullValue(node.getInt())

# Serialization procs for Google_protobuf_ListValue
proc toBinary*(self: Google_protobuf_ListValue): seq[byte] =
  result = @[]
  for item in self.values:
    result.add(encodeFieldKey(1, wtLengthDelimited))
    let itemData = toBinary(item)
    result.add(encodeLengthDelimited(itemData))

proc fromBinary*(T: typedesc[Google_protobuf_ListValue], data: openArray[byte]): Google_protobuf_ListValue =
  var pos = 0
  while pos < data.len:
    let (fieldNum, wireType) = decodeFieldKey(data, pos)
    case fieldNum
    of 1:
      let fieldData = decodeLengthDelimited(data, pos)
      result.values.add(fromBinary(Google_protobuf_Value, fieldData))
    else:
      discard

proc toJson*(self: Google_protobuf_ListValue): JsonNode =
  result = newJObject()
  result["values"] = %self.values

proc fromJson*(T: typedesc[Google_protobuf_ListValue], node: JsonNode): Google_protobuf_ListValue =
  discard
  if node.hasKey("values"):
    for item in node["values"]:
      result.values.add(fromJson(Google_protobuf_Value, item))


  if node.hasKey("values"):
    for item in node["values"]:
      result.values.add(fromJson(Google_protobuf_Value, item))


# Serialization procs for StructMessage
proc toBinary*(self: StructMessage): seq[byte] =
  result = @[]
  block:
    let fieldData = toBinary(self.config)
    if fieldData.len > 0:
      result.add(encodeFieldKey(1, wtLengthDelimited))
      result.add(encodeLengthDelimited(fieldData))
  block:
    let fieldData = toBinary(self.value)
    if fieldData.len > 0:
      result.add(encodeFieldKey(2, wtLengthDelimited))
      result.add(encodeLengthDelimited(fieldData))
  block:
    let fieldData = toBinary(self.list)
    if fieldData.len > 0:
      result.add(encodeFieldKey(3, wtLengthDelimited))
      result.add(encodeLengthDelimited(fieldData))

proc fromBinary*(T: typedesc[StructMessage], data: openArray[byte]): StructMessage =
  var pos = 0
  while pos < data.len:
    let (fieldNum, wireType) = decodeFieldKey(data, pos)
    case fieldNum
    of 1:
      let fieldData = decodeLengthDelimited(data, pos)
      result.config = fromBinary(Google_protobuf_Struct, fieldData)
    of 2:
      let fieldData = decodeLengthDelimited(data, pos)
      result.value = fromBinary(Google_protobuf_Value, fieldData)
    of 3:
      let fieldData = decodeLengthDelimited(data, pos)
      result.list = fromBinary(Google_protobuf_ListValue, fieldData)
    else:
      discard

proc toJson*(self: StructMessage): JsonNode =
  result = newJObject()
  result["config"] = %self.config
  result["value"] = %self.value
  result["list"] = %self.list

proc fromJson*(T: typedesc[StructMessage], node: JsonNode): StructMessage =
  discard
  if node.hasKey("config"):
    result.config = fromJson(Google_protobuf_Struct, node["config"])
  if node.hasKey("value"):
    result.value = fromJson(Google_protobuf_Value, node["value"])
  if node.hasKey("list"):
    result.list = fromJson(Google_protobuf_ListValue, node["list"])


  if node.hasKey("config"):
    result.config = fromJson(Google_protobuf_Struct, node["config"])
  if node.hasKey("value"):
    result.value = fromJson(Google_protobuf_Value, node["value"])
  if node.hasKey("list"):
    result.list = fromJson(Google_protobuf_ListValue, node["list"])


