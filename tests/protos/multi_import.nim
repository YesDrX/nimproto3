# Generated from protobuf
type
  Multiple_import_common_CommonType* = object
    id*: int32
    name*: string


  Multiple_import_1_TypeMultipleImport1* = object
    common*: Multiple_import_common_CommonType
    enumMultipleImport1*: Multiple_import_1_TypeMultipleImport1_EnumMultipleImport1


  Multiple_import_2_TypeMultipleImport2* = object
    common*: Multiple_import_common_CommonType


  MultipleImport* = object
    fldFromMultipleImport1*: Multiple_import_1_TypeMultipleImport1
    fldFromMultipleImport2*: Multiple_import_2_TypeMultipleImport2


  Multiple_import_1_TypeMultipleImport1_EnumMultipleImport1* = enum
    VALUE_1,
    VALUE_2


proc toBinary*(self: Multiple_import_common_CommonType): seq[byte]
proc fromBinary*(T: typedesc[Multiple_import_common_CommonType], data: openArray[byte]): Multiple_import_common_CommonType
proc toJson*(self: Multiple_import_common_CommonType): JsonNode
proc fromJson*(T: typedesc[Multiple_import_common_CommonType], node: JsonNode): Multiple_import_common_CommonType

proc toBinary*(self: Multiple_import_1_TypeMultipleImport1): seq[byte]
proc fromBinary*(T: typedesc[Multiple_import_1_TypeMultipleImport1], data: openArray[byte]): Multiple_import_1_TypeMultipleImport1
proc toJson*(self: Multiple_import_1_TypeMultipleImport1): JsonNode
proc fromJson*(T: typedesc[Multiple_import_1_TypeMultipleImport1], node: JsonNode): Multiple_import_1_TypeMultipleImport1

proc toBinary*(self: Multiple_import_2_TypeMultipleImport2): seq[byte]
proc fromBinary*(T: typedesc[Multiple_import_2_TypeMultipleImport2], data: openArray[byte]): Multiple_import_2_TypeMultipleImport2
proc toJson*(self: Multiple_import_2_TypeMultipleImport2): JsonNode
proc fromJson*(T: typedesc[Multiple_import_2_TypeMultipleImport2], node: JsonNode): Multiple_import_2_TypeMultipleImport2

proc toBinary*(self: MultipleImport): seq[byte]
proc fromBinary*(T: typedesc[MultipleImport], data: openArray[byte]): MultipleImport
proc toJson*(self: MultipleImport): JsonNode
proc fromJson*(T: typedesc[MultipleImport], node: JsonNode): MultipleImport

# Serialization procs for Multiple_import_common_CommonType
proc toBinary*(self: Multiple_import_common_CommonType): seq[byte] =
  result = @[]
  result.add(encodeFieldKey(1, wtVarint))
  result.add(encodeInt32(self.id))
  result.add(encodeFieldKey(2, wtLengthDelimited))
  result.add(encodeString(self.name))

proc fromBinary*(T: typedesc[Multiple_import_common_CommonType], data: openArray[byte]): Multiple_import_common_CommonType =
  var pos = 0
  while pos < data.len:
    let (fieldNum, wireType) = decodeFieldKey(data, pos)
    case fieldNum
    of 1:
      result.id = decodeInt32(data, pos)
    of 2:
      result.name = decodeString(data, pos)
    else:
      discard

proc toJson*(self: Multiple_import_common_CommonType): JsonNode =
  result = newJObject()
  result["id"] = %self.id
  result["name"] = %self.name

proc fromJson*(T: typedesc[Multiple_import_common_CommonType], node: JsonNode): Multiple_import_common_CommonType =
  discard
  if node.hasKey("id"):
    result.id = int32(node["id"].getInt())
  if node.hasKey("name"):
    result.name = node["name"].getStr()


proc toBinary*(self: Multiple_import_1_TypeMultipleImport1_EnumMultipleImport1): seq[byte] =
  result = encodeInt32(int32(self))

proc fromBinary*(T: typedesc[Multiple_import_1_TypeMultipleImport1_EnumMultipleImport1], data: openArray[byte]): Multiple_import_1_TypeMultipleImport1_EnumMultipleImport1 =
  var pos = 0
  result = Multiple_import_1_TypeMultipleImport1_EnumMultipleImport1(decodeInt32(data, pos))

proc toJson*(self: Multiple_import_1_TypeMultipleImport1_EnumMultipleImport1): JsonNode =
  result = %int(self)

proc fromJson*(T: typedesc[Multiple_import_1_TypeMultipleImport1_EnumMultipleImport1], node: JsonNode): Multiple_import_1_TypeMultipleImport1_EnumMultipleImport1 =
  result = Multiple_import_1_TypeMultipleImport1_EnumMultipleImport1(node.getInt())

# Serialization procs for Multiple_import_1_TypeMultipleImport1
proc toBinary*(self: Multiple_import_1_TypeMultipleImport1): seq[byte] =
  result = @[]
  block:
    let fieldData = toBinary(self.common)
    if fieldData.len > 0:
      result.add(encodeFieldKey(1, wtLengthDelimited))
      result.add(encodeLengthDelimited(fieldData))
  block:
    let fieldData = toBinary(self.enumMultipleImport1)
    if fieldData.len > 0:
      result.add(encodeFieldKey(2, wtLengthDelimited))
      result.add(encodeLengthDelimited(fieldData))

proc fromBinary*(T: typedesc[Multiple_import_1_TypeMultipleImport1], data: openArray[byte]): Multiple_import_1_TypeMultipleImport1 =
  var pos = 0
  while pos < data.len:
    let (fieldNum, wireType) = decodeFieldKey(data, pos)
    case fieldNum
    of 1:
      let fieldData = decodeLengthDelimited(data, pos)
      result.common = fromBinary(Multiple_import_common_CommonType, fieldData)
    of 2:
      let fieldData = decodeLengthDelimited(data, pos)
      result.enumMultipleImport1 = fromBinary(Multiple_import_1_TypeMultipleImport1_EnumMultipleImport1, fieldData)
    else:
      discard

proc toJson*(self: Multiple_import_1_TypeMultipleImport1): JsonNode =
  result = newJObject()
  result["common"] = %self.common
  result["enumMultipleImport1"] = %self.enumMultipleImport1

proc fromJson*(T: typedesc[Multiple_import_1_TypeMultipleImport1], node: JsonNode): Multiple_import_1_TypeMultipleImport1 =
  discard
  if node.hasKey("common"):
    result.common = fromJson(Multiple_import_common_CommonType, node["common"])
  if node.hasKey("enumMultipleImport1"):
    result.enumMultipleImport1 = fromJson(Multiple_import_1_TypeMultipleImport1_EnumMultipleImport1, node["enumMultipleImport1"])


# Serialization procs for Multiple_import_2_TypeMultipleImport2
proc toBinary*(self: Multiple_import_2_TypeMultipleImport2): seq[byte] =
  result = @[]
  block:
    let fieldData = toBinary(self.common)
    if fieldData.len > 0:
      result.add(encodeFieldKey(1, wtLengthDelimited))
      result.add(encodeLengthDelimited(fieldData))

proc fromBinary*(T: typedesc[Multiple_import_2_TypeMultipleImport2], data: openArray[byte]): Multiple_import_2_TypeMultipleImport2 =
  var pos = 0
  while pos < data.len:
    let (fieldNum, wireType) = decodeFieldKey(data, pos)
    case fieldNum
    of 1:
      let fieldData = decodeLengthDelimited(data, pos)
      result.common = fromBinary(Multiple_import_common_CommonType, fieldData)
    else:
      discard

proc toJson*(self: Multiple_import_2_TypeMultipleImport2): JsonNode =
  result = newJObject()
  result["common"] = %self.common

proc fromJson*(T: typedesc[Multiple_import_2_TypeMultipleImport2], node: JsonNode): Multiple_import_2_TypeMultipleImport2 =
  discard
  if node.hasKey("common"):
    result.common = fromJson(Multiple_import_common_CommonType, node["common"])


# Serialization procs for MultipleImport
proc toBinary*(self: MultipleImport): seq[byte] =
  result = @[]
  block:
    let fieldData = toBinary(self.fldFromMultipleImport1)
    if fieldData.len > 0:
      result.add(encodeFieldKey(1, wtLengthDelimited))
      result.add(encodeLengthDelimited(fieldData))
  block:
    let fieldData = toBinary(self.fldFromMultipleImport2)
    if fieldData.len > 0:
      result.add(encodeFieldKey(2, wtLengthDelimited))
      result.add(encodeLengthDelimited(fieldData))

proc fromBinary*(T: typedesc[MultipleImport], data: openArray[byte]): MultipleImport =
  var pos = 0
  while pos < data.len:
    let (fieldNum, wireType) = decodeFieldKey(data, pos)
    case fieldNum
    of 1:
      let fieldData = decodeLengthDelimited(data, pos)
      result.fldFromMultipleImport1 = fromBinary(Multiple_import_1_TypeMultipleImport1, fieldData)
    of 2:
      let fieldData = decodeLengthDelimited(data, pos)
      result.fldFromMultipleImport2 = fromBinary(Multiple_import_2_TypeMultipleImport2, fieldData)
    else:
      discard

proc toJson*(self: MultipleImport): JsonNode =
  result = newJObject()
  result["fldFromMultipleImport1"] = %self.fldFromMultipleImport1
  result["fldFromMultipleImport2"] = %self.fldFromMultipleImport2

proc fromJson*(T: typedesc[MultipleImport], node: JsonNode): MultipleImport =
  discard
  if node.hasKey("fldFromMultipleImport1"):
    result.fldFromMultipleImport1 = fromJson(Multiple_import_1_TypeMultipleImport1, node["fldFromMultipleImport1"])
  if node.hasKey("fldFromMultipleImport2"):
    result.fldFromMultipleImport2 = fromJson(Multiple_import_2_TypeMultipleImport2, node["fldFromMultipleImport2"])


