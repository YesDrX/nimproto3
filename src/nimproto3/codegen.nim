import std/[strutils, tables, sets, sequtils, os]
import ./[ast, parser]

proc capitalizeTypeName(name: string): string =
  ## Capitalize first letter of type name for Nim convention
  if name.len > 0:
    result = name[0].toUpperAscii & name[1..^1]
  else:
    result = name

# Nim keywords that need to be escaped with backticks when used as identifiers
const nimKeywords = [
  "addr", "and", "as", "asm", "bind", "block", "break", "case", "cast",
  "concept", "const", "continue", "converter", "defer", "discard", "distinct",
  "div", "do", "elif", "else", "end", "enum", "except", "export", "finally",
  "for", "from", "func", "if", "import", "in", "include", "interface",
  "is", "isnot", "iterator", "let", "macro", "method", "mixin", "mod", "nil",
  "not", "notin", "object", "of", "or", "out", "proc", "ptr", "raise", "ref",
  "return", "shl", "shr", "static", "template", "try", "tuple", "type", "using",
  "var", "when", "while", "xor", "yield"
].toHashSet

proc escapeNimKeyword(name: string): string =
  ## Escapes Nim keywords by wrapping them in backticks
  if name in nimKeywords:
    return "`" & name & "`"
  else:
    return name

proc parseTypeName(typeStr: string): string =
  # Extracts "Foo" from "Foo* = object" or "Foo* = enum"
  let parts = typeStr.split("*")
  if parts.len > 0:
    return parts[0].strip()
  return ""

proc protoTypeToNim*(typeName: string, isRepeated: bool = false,
    packagePrefix: string = ""): string =
  ## Convert a Protobuf type name to a Nim type string
  var baseType: string

  case typeName
  of "string":
    baseType = "string"
  of "int32", "sint32", "sfixed32":
    baseType = "int32"
  of "int64", "sint64", "sfixed64":
    baseType = "int64"
  of "uint32", "fixed32":
    baseType = "uint32"
  of "uint64", "fixed64":
    baseType = "uint64"
  of "bool":
    baseType = "bool"
  of "float":
    baseType = "float32"
  of "double":
    baseType = "float64"
  of "bytes":
    baseType = "seq[byte]"
  else:
    # Custom type - use the type name directly
    # Handle qualified names like "google.protobuf.Timestamp"
    if packagePrefix.len > 0 and not typeName.contains(".") and not typeName.startsWith(packagePrefix & "_"):
      baseType = capitalizeTypeName(packagePrefix & "_" & typeName)
    else:
      baseType = capitalizeTypeName(typeName.replace(".", "_"))

  if isRepeated:
    result = "seq[" & baseType & "]"
  else:
    result = baseType

proc indent(s: string, level: int = 1): string =
  let prefix = "  ".repeat(level)
  result = ""
  for line in s.split("\n"):
    if line.len > 0:
      result &= prefix & line & "\n"
    else:
      result &= "\n"

proc generateEnum*(node: ProtoNode, prefix: string = ""): string =
  ## Generate a Nim enum type from a ProtoNode enum
  assert node.kind == nkEnum

  let enumName = if prefix.len > 0:
    capitalizeTypeName(prefix & "_" & node.name)
  else:
    capitalizeTypeName(node.name)

  result = enumName & "* = enum\n"

  for i, child in node.children:
    if child.kind == nkEnumField:
      result &= "  " & child.name
      if i < node.children.len - 1:
        result &= ",\n"
      else:
        result &= "\n"

proc generateMessage*(node: ProtoNode, prefix: string = "",
    nestedTypes: var seq[string], packagePrefix: string = ""): string =
  ## Generate a Nim object type from a ProtoNode message
  assert node.kind == nkMessage

  let typeName = if prefix.len > 0:
    capitalizeTypeName(prefix & "_" & node.name)
  else:
    capitalizeTypeName(node.name)

  # First pass: collect nested type names for reference qualification
  var nestedTypeMap: seq[(string, string)] = @[] # (original name, qualified name)
  for child in node.children:
    if child.kind == nkMessage or child.kind == nkEnum:
      let originalName = child.name
      let qualifiedName = if prefix.len > 0:
        prefix & "_" & node.name & "_" & child.name
      else:
        node.name & "_" & child.name
      nestedTypeMap.add((originalName, qualifiedName))

  # Collect oneof fields to process them separately
  var oneofFields: seq[ProtoNode] = @[]
  for child in node.children:
    if child.kind == nkOneof:
      oneofFields.add(child)

  # Process nested messages and enums first (common to both branches)
  for child in node.children:
    case child.kind
    of nkMessage:
      # Nested message - generate it separately with qualified name
      let nestedPrefix = if prefix.len > 0:
        prefix & "_" & node.name
      else:
        node.name
      nestedTypes.add(generateMessage(child, nestedPrefix, nestedTypes,
          packagePrefix))

    of nkEnum:
      # Nested enum - generate it separately with qualified name
      let nestedPrefix = if prefix.len > 0:
        prefix & "_" & node.name
      else:
        node.name
      nestedTypes.add(generateEnum(child, nestedPrefix))

    else:
      discard

  # If we have oneof fields, we need to generate a variant object
  if oneofFields.len > 0:
    # Generate oneof kind enums first - but put them directly in the result, not nestedTypes
    var enumDefs = ""
    for oneofNode in oneofFields:
      # Correct naming: TypeName + OneofName + "Kind"
      let oneofKindName = typeName & capitalizeTypeName(oneofNode.name) & "Kind"
      enumDefs &= oneofKindName & "* = enum\n"
      enumDefs &= "  rkNone  # nothing set\n"
      
      for field in oneofNode.children:
        if field.kind == nkField:
          let fieldName = field.name
          enumDefs &= "  rk" & capitalizeTypeName(fieldName) & "\n"

    # Generate the enum definition before the object definition
    result = enumDefs & "\n"
    
    # Now generate the main object with oneof variant fields
    result &= typeName & "* = object\n"
    
    # First, generate regular fields (non-oneof)
    for child in node.children:
      case child.kind
      of nkField:
        # Check if field is repeated
        var isRepeated = false
        for attr in child.attrs:
          if attr.kind == nkOption and attr.name == "label" and attr.value == "repeated":
            isRepeated = true
            break

        let fieldName = child.name
        var fieldTypeName = child.value
        var typeWasRenamed = false

        # Check if this is a reference to a nested type - qualify it
        for (origName, qualName) in nestedTypeMap:
          if fieldTypeName == origName:
            fieldTypeName = qualName
            typeWasRenamed = true
            break

        if node.reanamedTypeNamesInScope.len > 0 and
            node.reanamedTypeNamesInScope.hasKey(fieldTypeName):
          fieldTypeName = node.reanamedTypeNamesInScope[fieldTypeName]
          typeWasRenamed = true

        if not typeWasRenamed:
          let root = getRoot(node)
          if root.globalTypeMap.hasKey(fieldTypeName):
            fieldTypeName = root.globalTypeMap[fieldTypeName]
            typeWasRenamed = true

        # Only pass packagePrefix if the type wasn't already qualified
        let pkgPrefix = if typeWasRenamed: "" else: packagePrefix
        let fieldType = protoTypeToNim(fieldTypeName, isRepeated, pkgPrefix)

        result &= "  " & escapeNimKeyword(fieldName) & "*: " & fieldType & "\n"

      of nkMapField:
        # map<K,V> -> Table[K, V]
        let parts = child.value.split(",")
        if parts.len == 2:
          var keyBase = parts[0].strip()
          var valBase = parts[1].strip()
          if node.reanamedTypeNamesInScope.len > 0 and
              node.reanamedTypeNamesInScope.hasKey(valBase):
            valBase = node.reanamedTypeNamesInScope[valBase]
          let keyType = protoTypeToNim(keyBase, false, packagePrefix)
          let valType = protoTypeToNim(valBase, false, packagePrefix)
          result &= "  " & escapeNimKeyword(child.name) & "*: Table[" & keyType &
              ", " & valType & "]\n"

      of nkOneof, nkMessage, nkEnum:
        # Skip these for now - handled separately
        discard

      else:
        discard

    # Add kind fields and case statements for all oneof fields
    for oneofNode in oneofFields:
      let oneofName = oneofNode.name
      let oneofKindName = typeName & capitalizeTypeName(oneofName) & "Kind"
      
      # Generate the case statement for the variant
      result &= "  case " & escapeNimKeyword(oneofName & "Kind") & "*: " & oneofKindName & "\n"
      
      # Add the none case
      result &= "  of rkNone: discard\n"
      
      # Add each field in the oneof
      for field in oneofNode.children:
        if field.kind == nkField:
          let fieldName = field.name
          var fieldTypeName = field.value
          var typeWasRenamed = false

          # Check if this is a reference to a nested type - qualify it
          for (origName, qualName) in nestedTypeMap:
            if fieldTypeName == origName:
              fieldTypeName = qualName
              typeWasRenamed = true
              break

          if node.reanamedTypeNamesInScope.len > 0 and
              node.reanamedTypeNamesInScope.hasKey(fieldTypeName):
            fieldTypeName = node.reanamedTypeNamesInScope[fieldTypeName]
            typeWasRenamed = true

          if not typeWasRenamed:
            let root = getRoot(node)
            if root.globalTypeMap.hasKey(fieldTypeName):
              fieldTypeName = root.globalTypeMap[fieldTypeName]
              typeWasRenamed = true

          # Only pass packagePrefix if the type wasn't already qualified
          let pkgPrefix = if typeWasRenamed: "" else: packagePrefix
          let fieldType = protoTypeToNim(fieldTypeName, false, pkgPrefix)
          
          result &= "  of rk" & capitalizeTypeName(fieldName) & ":\n"
          result &= "    " & escapeNimKeyword(fieldName) & "*: " & fieldType & "\n"
      
  else:
    # No oneof fields, generate normally
    result = typeName & "* = object\n"
    
    for child in node.children:
      case child.kind
      of nkField:
        # Check if field is repeated
        var isRepeated = false
        for attr in child.attrs:
          if attr.kind == nkOption and attr.name == "label" and attr.value == "repeated":
            isRepeated = true
            break

        let fieldName = child.name
        var fieldTypeName = child.value
        var typeWasRenamed = false

        # Check if this is a reference to a nested type - qualify it
        for (origName, qualName) in nestedTypeMap:
          if fieldTypeName == origName:
            fieldTypeName = qualName
            typeWasRenamed = true
            break

        if node.reanamedTypeNamesInScope.len > 0 and
            node.reanamedTypeNamesInScope.hasKey(fieldTypeName):
          fieldTypeName = node.reanamedTypeNamesInScope[fieldTypeName]
          typeWasRenamed = true

        if not typeWasRenamed:
          let root = getRoot(node)
          if root.globalTypeMap.hasKey(fieldTypeName):
            fieldTypeName = root.globalTypeMap[fieldTypeName]
            typeWasRenamed = true

        # Only pass packagePrefix if the type wasn't already qualified
        let pkgPrefix = if typeWasRenamed: "" else: packagePrefix
        let fieldType = protoTypeToNim(fieldTypeName, isRepeated, pkgPrefix)

        result &= "  " & escapeNimKeyword(fieldName) & "*: " & fieldType & "\n"

      of nkMapField:
        # map<K,V> -> Table[K, V]
        let parts = child.value.split(",")
        if parts.len == 2:
          var keyBase = parts[0].strip()
          var valBase = parts[1].strip()
          if node.reanamedTypeNamesInScope.len > 0 and
              node.reanamedTypeNamesInScope.hasKey(valBase):
            valBase = node.reanamedTypeNamesInScope[valBase]
          let keyType = protoTypeToNim(keyBase, false, packagePrefix)
          let valType = protoTypeToNim(valBase, false, packagePrefix)
          result &= "  " & escapeNimKeyword(child.name) & "*: Table[" & keyType &
              ", " & valType & "]\n"

      of nkOneof:
        # Skip oneofs - handled above
        discard

      of nkMessage, nkEnum:
        # Skip nested types - handled above
        discard

      else:
        discard

  # Nested messages and enums are already handled in the main loop above
  # No need to process them again here

# Serialization helpers
proc getWireType(protoType: string): string =
  case protoType
  of "int32", "int64", "uint32", "uint64", "sint32", "sint64", "bool":
    "wtVarint"
  of "fixed64", "sfixed64", "double":
    "wt64Bit"
  of "string", "bytes":
    "wtLengthDelimited"
  of "fixed32", "sfixed32", "float":
    "wt32Bit"
  else:
    "wtLengthDelimited" # Message types

proc getEncodeProc(protoType: string): string =
  case protoType
  of "int32": "encodeInt32"
  of "int64": "encodeInt64"
  of "uint32": "encodeUInt32"
  of "uint64": "encodeUInt64"
  of "sint32": "encodeSInt32"
  of "sint64": "encodeSInt64"
  of "bool": "encodeBool"
  of "string": "encodeString"
  of "float": "encodeFloat32"
  of "double": "encodeFloat64"
  of "bytes": "encodeLengthDelimited"
  else: ""

proc getDecodeProc(protoType: string): string =
  case protoType
  of "int32": "decodeInt32"
  of "int64": "decodeInt64"
  of "uint32": "decodeUInt32"
  of "uint64": "decodeUInt64"
  of "sint32": "decodeSInt32"
  of "sint64": "decodeSInt64"
  of "bool": "decodeBool"
  of "string": "decodeString"
  of "float": "decodeFloat32"
  of "double": "decodeFloat64"
  of "bytes": "decodeLengthDelimited"
  else: ""

proc generateSerializationProcs(node: ProtoNode, typeName: string,
    nestedTypeMap: seq[(string, string)], enumNames: HashSet[string],
        packagePrefix: string = "", checkDefined: bool = false): string =
  ## Generate toBinary, fromBinary, toJson, and fromJson procs
  result = ""
  if checkDefined:
    result &= "when declared(Defined_" & typeName & "):\n"

  let indentStr = if checkDefined: "  " else: ""

  result &= indentStr & "# Serialization procs for " & typeName & "\n"

  # Check if this message has oneof fields
  var oneofFields: seq[ProtoNode] = @[]
  for child in node.children:
    if child.kind == nkOneof:
      oneofFields.add(child)
      
  let hasOneof = oneofFields.len > 0

  # toBinary proc
  result &= indentStr & "proc toBinary*(self: " & typeName & "): seq[byte] =\n"
  result &= indentStr & "  result = @[]\n"

  # Handle oneof fields first (if any)
  if hasOneof:
    # Handle each oneof field - we need separate case statements for each oneof
    for oneofNode in oneofFields:
      let oneofName = oneofNode.name
      let oneofKindName = typeName & capitalizeTypeName(oneofName) & "Kind"
      
      # For oneof fields, we generate a case statement
      result &= indentStr & "  case self." & escapeNimKeyword(oneofName & "Kind") & "\n"
      
      # Handle the none case
      result &= indentStr & "  of rkNone:\n"
      result &= indentStr & "    discard\n"
      
      # Handle each field in this oneof
      for oneofField in oneofNode.children:
        if oneofField.kind == nkField:
          let fieldNum = oneofField.number
          let fieldName = oneofField.name
          var protoType = oneofField.value
          
          var typeWasRenamed = false
          # Qualify nested types
          for (origName, qualName) in nestedTypeMap:
            if protoType == origName:
              protoType = qualName
              typeWasRenamed = true
          if node.reanamedTypeNamesInScope.len > 0 and
              node.reanamedTypeNamesInScope.hasKey(protoType):
            protoType = node.reanamedTypeNamesInScope[protoType]
            typeWasRenamed = true
          else:
            let root = getRoot(node)
            if root.globalTypeMap.hasKey(protoType):
              protoType = root.globalTypeMap[protoType]
              typeWasRenamed = true

          let encodeProc = getEncodeProc(protoType)
          let pkgPrefix = if typeWasRenamed: "" else: packagePrefix
          let nimType = protoTypeToNim(protoType, false, pkgPrefix)
          let isEnum = enumNames.contains(protoType)
          let wireType = if isEnum: "wtVarint" else: getWireType(protoType)
          
          result &= indentStr & "  of rk" & capitalizeTypeName(fieldName) & ":\n"
          
          if wireType == "wtLengthDelimited":
            # Length-delimited fields (strings, bytes, messages)
            result &= indentStr & "    # field " & $fieldNum & ", wire=2 (length-delimited)\n"
            result &= indentStr & "    result.add(encodeFieldKey(" & $fieldNum & ", wtLengthDelimited))\n"
            if encodeProc.len > 0:
              result &= indentStr & "    let s = self." & escapeNimKeyword(fieldName) & "\n"
              result &= indentStr & "    result.add(encodeString(s))\n"
            else:
              # Message type
              result &= indentStr & "    let msgData = toBinary(self." & escapeNimKeyword(fieldName) & ")\n"
              result &= indentStr & "    result.add(encodeVarint(uint64(msgData.len)))\n"
              result &= indentStr & "    result.add(msgData)\n"
          else:
            # Varint fields (integers, booleans, enums)
            result &= indentStr & "    # field " & $fieldNum & ", wire=0 (varint)\n"
            result &= indentStr & "    result.add(encodeFieldKey(" & $fieldNum & ", wtVarint))\n"
            if encodeProc.len > 0:
              result &= indentStr & "    result.add(" & encodeProc & "(self." & 
                  escapeNimKeyword(fieldName) & "))\n"
            elif isEnum:
              result &= indentStr & "    result.add(encodeVarint(uint64(int(self." & 
                  escapeNimKeyword(fieldName) & "))))\n"
            else:
              # Boolean
              result &= indentStr & "    result.add(encodeVarint(uint64(self." & 
                  escapeNimKeyword(fieldName) & ".int)))\n"

  # Handle regular fields (both with and without oneof fields)
  # First, collect all oneof field names to exclude them from regular field processing
  var oneofFieldNames: seq[string] = @[]
  if hasOneof:
    for oneofNode in oneofFields:
      for oneofField in oneofNode.children:
        if oneofField.kind == nkField:
          oneofFieldNames.add(oneofField.name)
  
  # Now process regular fields, excluding oneof fields
  for child in node.children:
    case child.kind
    of nkField:
      # Skip oneof fields as they're handled above
      if child.name in oneofFieldNames:
        continue
      
      let fieldNum = child.number
      let fieldName = child.name
      var protoType = child.value
      var isRepeated = false

      # Check if repeated
      for attr in child.attrs:
        if attr.kind == nkOption and attr.name == "label" and attr.value == "repeated":
          isRepeated = true

      var typeWasRenamed = false
      # Qualify nested types
      for (origName, qualName) in nestedTypeMap:
        if protoType == origName:
          protoType = qualName
          typeWasRenamed = true
      if node.reanamedTypeNamesInScope.len > 0 and
          node.reanamedTypeNamesInScope.hasKey(protoType):
        protoType = node.reanamedTypeNamesInScope[protoType]
        typeWasRenamed = true
      else:
        let root = getRoot(node)
        if root.globalTypeMap.hasKey(protoType):
          protoType = root.globalTypeMap[protoType]
          typeWasRenamed = true

      let wireType = if enumNames.contains(
          protoType): "wtVarint" else: getWireType(protoType)
      let encodeProc = getEncodeProc(protoType)

      let pkgPrefix = if typeWasRenamed: "" else: packagePrefix
      let nimType = protoTypeToNim(protoType, false, pkgPrefix)

      if isRepeated:
        result &= indentStr & "  for item in self." & escapeNimKeyword(
            fieldName) & ":\n"
        result &= indentStr & "    result.add(encodeFieldKey(" & $fieldNum &
            ", " & wireType & "))\n"
        if encodeProc.len > 0:
          result &= indentStr & "    result.add(" & encodeProc & "(item))\n"
        else:
          result &= indentStr & "    let itemData = toBinary(item)\n"
          result &= indentStr & "    result.add(encodeLengthDelimited(itemData))\n"
      else:
        # Regular field
        if encodeProc.len > 0:
          result &= indentStr & "  result.add(encodeFieldKey(" & $fieldNum &
              ", " & wireType & "))\n"
          result &= indentStr & "  result.add(" & encodeProc & "(self." &
              escapeNimKeyword(fieldName) & "))\n"
        elif enumNames.contains(protoType):
          result &= indentStr & "  result.add(encodeInt32(int32(self." &
              escapeNimKeyword(fieldName) &
              ")))\n"
        else:
          result &= indentStr & "  block:\n"
          result &= indentStr & "    let fieldData = toBinary(self." &
              escapeNimKeyword(fieldName) & ")\n"
          result &= indentStr & "    if fieldData.len > 0:\n"
          result &= indentStr & "      result.add(encodeFieldKey(" & $fieldNum &
              ", " & wireType & "))\n"
          result &= indentStr & "      result.add(encodeLengthDelimited(fieldData))\n"
          
    of nkMapField:
      let fieldNum = child.number
      let fieldName = child.name
      let parts = child.value.split(",")
      var keyType = parts[0].strip()
      var valType = parts[1].strip()
      if node.reanamedTypeNamesInScope.len > 0 and
          node.reanamedTypeNamesInScope.hasKey(valType):
        valType = node.reanamedTypeNamesInScope[valType]

      let keyWireType = getWireType(keyType)
      let valWireType = getWireType(valType)

      let keyEncode = getEncodeProc(keyType)
      let valEncode = getEncodeProc(valType)

      result &= indentStr & "  for key, val in self." & escapeNimKeyword(
          fieldName) & ":\n"
      result &= indentStr & "    var entry = newSeq[byte]()\n"

      # Encode Key (field 1)
      result &= indentStr & "    entry.add(encodeFieldKey(1, " & keyWireType & "))\n"
      if keyEncode.len > 0:
        result &= indentStr & "    entry.add(" & keyEncode & "(key))\n"
      else:
        # Keys can only be scalar types, so this should be covered, but for safety:
        result &= indentStr & "    entry.add(toBinary(key))\n"

      # Encode Value (field 2)
      result &= indentStr & "    entry.add(encodeFieldKey(2, " & valWireType & "))\n"
      if valEncode.len > 0:
        result &= indentStr & "    entry.add(" & valEncode & "(val))\n"
      else:
        # Value can be message
        result &= indentStr & "    let valData = toBinary(val)\n"
        result &= indentStr & "    entry.add(encodeLengthDelimited(valData))\n"

      # Add entry to result (field N)
      result &= indentStr & "    result.add(encodeFieldKey(" & $fieldNum & ", wtLengthDelimited))\n"
      result &= indentStr & "    result.add(encodeLengthDelimited(entry))\n"
    of nkOneof:
      # Oneof fields are handled separately
      discard
    of nkProto, nkSyntax, nkEdition, nkPackage, nkImport, nkOption, nkMessage, nkEnum, nkService, nkEnumField, nkRpc, nkStream, nkComment, nkReserved, nkExtensions, nkGroup:
      # These node kinds are not processed in this context
      discard

  result &= "\n"

  # fromBinary proc
  result &= indentStr & "proc fromBinary*(T: typedesc[" & typeName &
      "], data: openArray[byte]): " & typeName & " =\n"
  result &= indentStr & "  var pos = 0\n"
  result &= indentStr & "  while pos < data.len:\n"
  result &= indentStr & "    let (fieldNum, wireType {.used.}) = decodeFieldKey(data, pos)\n"
  result &= indentStr & "    case fieldNum\n"

  # Handle regular fields first
  for child in node.children:
    case child.kind
    of nkField:
      let fieldNum = child.number
      let fieldName = child.name
      let isRepeated = child.attrs.anyIt(it.name == "label" and it.value == "repeated")
      var protoType = child.value
      var typeWasRenamed = false
      # Check if this is a nested type reference
      for (origName, qualName) in nestedTypeMap:
        if protoType == origName:
          protoType = qualName
          typeWasRenamed = true
          break
      if node.reanamedTypeNamesInScope.len > 0 and
          node.reanamedTypeNamesInScope.hasKey(protoType):
        protoType = node.reanamedTypeNamesInScope[protoType]
        typeWasRenamed = true
      else:
        let root = getRoot(node)
        if root.globalTypeMap.hasKey(protoType):
          protoType = root.globalTypeMap[protoType]
          typeWasRenamed = true

      let decodeProc = getDecodeProc(child.value)
      let pkgPrefix = if typeWasRenamed: "" else: packagePrefix
      let nimType = protoTypeToNim(protoType, false, pkgPrefix)
      let isEnum = enumNames.contains(protoType)
      result &= indentStr & "    of " & $fieldNum & ":\n"
      
      if isRepeated:
        if decodeProc.len > 0:
          result &= indentStr & "      result." & escapeNimKeyword(fieldName) &
              ".add(" & decodeProc &
              "(data, pos))\n"
        else:
          result &= indentStr & "      let fieldData = decodeLengthDelimited(data, pos)\n"
          result &= indentStr & "      result." & escapeNimKeyword(fieldName) &
              ".add(fromBinary(" & nimType & ", fieldData))\n"
      else:
        if decodeProc.len > 0:
          result &= indentStr & "      result." & escapeNimKeyword(fieldName) &
              " = " & decodeProc & "(data, pos)\n"
        elif isEnum:
          result &= indentStr & "      result." & escapeNimKeyword(fieldName) &
              " = " & nimType &
              "(decodeInt32(data, pos))\n"
        else:
          result &= indentStr & "      let fieldData = decodeLengthDelimited(data, pos)\n"
          result &= indentStr & "      result." & escapeNimKeyword(fieldName) &
              " = fromBinary(" & nimType & ", fieldData)\n"

    of nkMapField:
      let fieldNum = child.number
      let fieldName = child.name
      let parts = child.value.split(",")
      var keyType = parts[0].strip()
      var valType = parts[1].strip()
      if node.reanamedTypeNamesInScope.len > 0 and
          node.reanamedTypeNamesInScope.hasKey(valType):
        valType = node.reanamedTypeNamesInScope[valType]

      let keyDecode = getDecodeProc(keyType)
      let valDecode = getDecodeProc(valType)
      let keyNimType = protoTypeToNim(keyType, false, packagePrefix)
      let valNimType = protoTypeToNim(valType, false, packagePrefix)

      result &= indentStr & "    of " & $fieldNum & ":\n"
      result &= indentStr & "      let entryData = decodeLengthDelimited(data, pos)\n"
      result &= indentStr & "      var entryPos = 0\n"
      result &= indentStr & "      var key: " & keyNimType & "\n"
      result &= indentStr & "      var val: " & valNimType & "\n"
      result &= indentStr & "      while entryPos < entryData.len:\n"
      result &= indentStr & "        let (fNum, wType) = decodeFieldKey(entryData, entryPos)\n"
      result &= indentStr & "        case fNum\n"
      result &= indentStr & "        of 1:\n"
      if keyDecode.len > 0:
        result &= indentStr & "          key = " & keyDecode & "(entryData, entryPos)\n"
      else:
        result &= indentStr & "          key = fromBinary(" & keyNimType &
            ", decodeLengthDelimited(entryData, entryPos))\n"
      result &= indentStr & "        of 2:\n"
      if valDecode.len > 0:
        result &= indentStr & "          val = " & valDecode & "(entryData, entryPos)\n"
      else:
        result &= indentStr & "          let valData = decodeLengthDelimited(entryData, entryPos)\n"
        result &= indentStr & "          val = fromBinary(" & valNimType &
            ", valData)\n"
      result &= indentStr & "        else: discard\n"
      result &= indentStr & "      result." & escapeNimKeyword(fieldName) & "[key] = val\n"

    of nkOneof:
      # Oneof fields are handled separately below
      discard

    else:
      discard
  
  # Handle oneof fields
  for oneofNode in oneofFields:
    let oneofName = oneofNode.name
    for oneofField in oneofNode.children:
      if oneofField.kind == nkField:
        let fieldNum = oneofField.number
        let fieldName = oneofField.name
        var protoType = oneofField.value
        
        var typeWasRenamed = false
        # Check if this is a nested type reference
        for (origName, qualName) in nestedTypeMap:
          if protoType == origName:
            protoType = qualName
            typeWasRenamed = true
            break
        if node.reanamedTypeNamesInScope.len > 0 and
            node.reanamedTypeNamesInScope.hasKey(protoType):
          protoType = node.reanamedTypeNamesInScope[protoType]
          typeWasRenamed = true
        else:
          let root = getRoot(node)
          if root.globalTypeMap.hasKey(protoType):
            protoType = root.globalTypeMap[protoType]
            typeWasRenamed = true

        let decodeProc = getDecodeProc(oneofField.value)
        let pkgPrefix = if typeWasRenamed: "" else: packagePrefix
        let nimType = protoTypeToNim(protoType, false, pkgPrefix)
        let isEnum = enumNames.contains(protoType)
        let wireType = if isEnum: "wtVarint" else: getWireType(oneofField.value)
        
        result &= indentStr & "    of " & $fieldNum & ":\n"
        
        if wireType == "wtLengthDelimited":
          # Length-delimited fields
          result &= indentStr & "      assert wireType.int == 2\n"
          result &= indentStr & "      let length = int(decodeVarint(data, pos))\n"
          if decodeProc.len > 0:
            result &= indentStr & "      result." & escapeNimKeyword(oneofName & "Kind") & " = rk" & capitalizeTypeName(fieldName) & "\n"
            result &= indentStr & "      result." & escapeNimKeyword(fieldName) & " = " & decodeProc & "(data, pos)\n"
          else:
            # Message type
            result &= indentStr & "      let msgData = data[pos ..< pos+length]\n"
            result &= indentStr & "      pos += length\n"
            result &= indentStr & "      result." & escapeNimKeyword(oneofName & "Kind") & " = rk" & capitalizeTypeName(fieldName) & "\n"
            result &= indentStr & "      result." & escapeNimKeyword(fieldName) & " = fromBinary(" & nimType & ", msgData)\n"
        else:
          # Varint fields
          result &= indentStr & "      assert wireType.int == 0\n"
          if decodeProc.len > 0:
            result &= indentStr & "      let v = " & decodeProc & "(data, pos)\n"
            result &= indentStr & "      result." & escapeNimKeyword(oneofName & "Kind") & " = rk" & capitalizeTypeName(fieldName) & "\n"
            result &= indentStr & "      result." & escapeNimKeyword(fieldName) & " = v\n"
          elif isEnum:
            result &= indentStr & "      let v = " & nimType & "(int32(decodeVarint(data, pos)))\n"
            result &= indentStr & "      result." & escapeNimKeyword(oneofName & "Kind") & " = rk" & capitalizeTypeName(fieldName) & "\n"
            result &= indentStr & "      result." & escapeNimKeyword(fieldName) & " = v\n"
          else:
            # Boolean
            result &= indentStr & "      let b = decodeVarint(data, pos) != 0\n"
            result &= indentStr & "      result." & escapeNimKeyword(oneofName & "Kind") & " = rk" & capitalizeTypeName(fieldName) & "\n"
            result &= indentStr & "      result." & escapeNimKeyword(fieldName) & " = b\n"

  result &= indentStr & "    else:\n"
  result &= indentStr & "      discard\n\n"

  # toJson proc
  result &= indentStr & "proc toJson*(self: " & typeName & "): JsonNode =\n"
  result &= indentStr & "  result = newJObject()\n"
  
  if hasOneof:
    # For oneof fields, we generate a case statement for each oneof
    for oneofNode in oneofFields:
      let oneofName = oneofNode.name
      result &= indentStr & "  case self." & escapeNimKeyword(oneofName & "Kind") & "\n"
      
      # Handle the none case
      result &= indentStr & "  of rkNone:\n"
      result &= indentStr & "    discard\n"
      
      # Handle each field in this oneof
      for oneofField in oneofNode.children:
        if oneofField.kind == nkField:
          let fieldName = oneofField.name
          result &= indentStr & "  of rk" & capitalizeTypeName(fieldName) & ":\n"
          result &= indentStr & "    result[\"" & fieldName & "\"] = %self." &
              escapeNimKeyword(fieldName) & "\n"
  
  # Handle regular fields (both with and without oneof fields)
  for child in node.children:
    case child.kind
    of nkField:
      # Skip oneof fields as they're handled above
      var isOneofField = false
      for oneofNode in oneofFields:
        for oneofField in oneofNode.children:
          if oneofField.kind == nkField and oneofField.name == child.name:
            isOneofField = true
            break
        if isOneofField: break
      
      if isOneofField: continue
      
      let fieldName = child.name
      result &= indentStr & "  result[\"" & fieldName & "\"] = %self." &
          escapeNimKeyword(fieldName) & "\n"
    of nkMapField:
      let fieldName = child.name
      result &= indentStr & "  var " & fieldName & "Json = newJObject()\n"
      result &= indentStr & "  for key, val in self." & escapeNimKeyword(
          fieldName) & ":\n"
      result &= indentStr & "    " & fieldName & "Json[$key] = %val\n"
      result &= indentStr & "  result[\"" & fieldName & "\"] = " & fieldName & "Json\n"
    else:
      discard

  result &= "\n"

  # fromJson proc
  result &= indentStr & "proc fromJson*(T: typedesc[" & typeName &
      "], node: JsonNode): " & typeName & " =\n"
  
  if hasOneof:
    # For oneof fields, check each oneof group independently
    for oneofNode in oneofFields:
      let oneofName = oneofNode.name
      var firstField = true
      
      # Generate if-elif chain for each field in this oneof group
      for oneofField in oneofNode.children:
        if oneofField.kind == nkField:
          let fieldName = oneofField.name
          var protoType = oneofField.value
          
          var typeWasRenamed = false
          # Qualify nested types
          for (origName, qualName) in nestedTypeMap:
            if protoType == origName:
              protoType = qualName
              typeWasRenamed = true
          # Apply renamed type names from scope
          if node.reanamedTypeNamesInScope.len > 0 and
              node.reanamedTypeNamesInScope.hasKey(protoType):
            protoType = node.reanamedTypeNamesInScope[protoType]
            typeWasRenamed = true
          else:
            let root = getRoot(node)
            if root.globalTypeMap.hasKey(protoType):
              protoType = root.globalTypeMap[protoType]
              typeWasRenamed = true

          let pkgPrefix = if typeWasRenamed: "" else: packagePrefix
          
          let condition = "node.hasKey(\"" & fieldName & "\")"
          let keyword = if firstField: "  if " else: "  elif "
          firstField = false
          
          result &= indentStr & keyword & condition & ":\n"
          
          case oneofField.value
          of "string":
            result &= indentStr & "    result." & escapeNimKeyword(oneofName & "Kind") & " = rk" & capitalizeTypeName(fieldName) & "\n"
            result &= indentStr & "    result." & escapeNimKeyword(fieldName) & " = node[\"" & fieldName & "\"].getStr\n"
          of "int32", "int64":
            result &= indentStr & "    result." & escapeNimKeyword(oneofName & "Kind") & " = rk" & capitalizeTypeName(fieldName) & "\n"
            result &= indentStr & "    result." & escapeNimKeyword(fieldName) & " = " & 
                protoTypeToNim(oneofField.value, false, packagePrefix) & 
                "(node[\"" & fieldName & "\"].getInt)\n"
          of "uint32", "uint64":
            result &= indentStr & "    result." & escapeNimKeyword(oneofName & "Kind") & " = rk" & capitalizeTypeName(fieldName) & "\n"
            result &= indentStr & "    result." & escapeNimKeyword(fieldName) & " = " & 
                protoTypeToNim(oneofField.value, false, packagePrefix) & 
                "(node[\"" & fieldName & "\"].getInt)\n"
          of "bool":
            result &= indentStr & "    result." & escapeNimKeyword(oneofName & "Kind") & " = rk" & capitalizeTypeName(fieldName) & "\n"
            result &= indentStr & "    result." & escapeNimKeyword(fieldName) & " = node[\"" & fieldName & "\"].getBool\n"
          of "float", "double":
            result &= indentStr & "    result." & escapeNimKeyword(oneofName & "Kind") & " = rk" & capitalizeTypeName(fieldName) & "\n"
            result &= indentStr & "    result." & escapeNimKeyword(fieldName) & " = " & 
                protoTypeToNim(oneofField.value, false, packagePrefix) & 
                "(node[\"" & fieldName & "\"].getFloat)\n"
          else:
            # Message type
            let nimType = protoTypeToNim(protoType, false, pkgPrefix)
            result &= indentStr & "    result." & escapeNimKeyword(oneofName & "Kind") & " = rk" & capitalizeTypeName(fieldName) & "\n"
            result &= indentStr & "    result." & escapeNimKeyword(fieldName) & " = fromJson(" & nimType & 
                ", node[\"" & fieldName & "\"])\n"
      
      # Add else clause for this oneof group if no fields were set
      if not firstField:  # Only add if we had fields in this oneof
        result &= indentStr & "  else:\n"
        result &= indentStr & "    result." & escapeNimKeyword(oneofName & "Kind") & " = rkNone\n"
  else:
    result &= indentStr & "  discard\n"
    # Handle regular fields
    for child in node.children:
      if child.kind == nkField:
        let fieldName = child.name
        var protoType = child.value
        let isRepeated = child.attrs.anyIt(it.name == "label" and it.value == "repeated")

        var typeWasRenamed = false
        # Qualify nested types
        for (origName, qualName) in nestedTypeMap:
          if protoType == origName:
            protoType = qualName
            typeWasRenamed = true
        # Apply renamed type names from scope
        if node.reanamedTypeNamesInScope.len > 0 and
            node.reanamedTypeNamesInScope.hasKey(protoType):
          protoType = node.reanamedTypeNamesInScope[protoType]
          typeWasRenamed = true
        else:
          let root = getRoot(node)
          if root.globalTypeMap.hasKey(protoType):
            protoType = root.globalTypeMap[protoType]
            typeWasRenamed = true

        let pkgPrefix = if typeWasRenamed: "" else: packagePrefix

        result &= indentStr & "  if node.hasKey(\"" & fieldName & "\"):\n"

        if isRepeated:
          result &= indentStr & "    for item in node[\"" & fieldName & "\"]:\n"
          case child.value
          of "string":
            result &= indentStr & "      result." & escapeNimKeyword(fieldName) & ".add(item.getStr())\n"
          of "int32", "int64":
            result &= indentStr & "      result." & escapeNimKeyword(fieldName) &
                ".add(" & protoTypeToNim(child.value, false, packagePrefix) & "(item.getInt()))\n"
          of "uint32", "uint64":
            result &= indentStr & "      result." & escapeNimKeyword(fieldName) &
                ".add(" & protoTypeToNim(child.value, false, packagePrefix) & "(item.getInt()))\n"
          of "bool":
            result &= indentStr & "      result." & escapeNimKeyword(fieldName) & ".add(item.getBool())\n"
          of "float", "double":
            result &= indentStr & "      result." & escapeNimKeyword(fieldName) &
                ".add(" & protoTypeToNim(child.value, false, packagePrefix) & "(item.getFloat()))\n"
          else:
            # Message type
            let nimType = protoTypeToNim(protoType, false, pkgPrefix)
            result &= indentStr & "      result." & escapeNimKeyword(fieldName) &
                ".add(fromJson(" & nimType & ", item))\n"
        else:
          case child.value
          of "string":
            result &= indentStr & "    result." & escapeNimKeyword(fieldName) &
                " = node[\"" & fieldName & "\"].getStr()\n"
          of "int32", "int64":
            result &= indentStr & "    result." & escapeNimKeyword(fieldName) &
                " = " & protoTypeToNim(child.value, false, packagePrefix) &
                    "(node[\"" & fieldName &
                "\"].getInt())\n"
          of "uint32", "uint64":
            result &= indentStr & "    result." & escapeNimKeyword(fieldName) &
                " = " & protoTypeToNim(child.value, false, packagePrefix) &
                    "(node[\"" & fieldName &
                "\"].getInt())\n"
          of "bool":
            result &= indentStr & "    result." & escapeNimKeyword(fieldName) &
                " = node[\"" & fieldName & "\"].getBool()\n"
          of "float", "double":
            result &= indentStr & "    result." & escapeNimKeyword(fieldName) &
                " = " & protoTypeToNim(child.value, false, packagePrefix) &
                    "(node[\"" & fieldName &
                "\"].getFloat())\n"
          else:
            # Message type
            let nimType = protoTypeToNim(protoType, false, pkgPrefix)
            result &= indentStr & "    result." & escapeNimKeyword(fieldName) &
                " = fromJson(" & nimType & ", node[\"" & fieldName & "\"])\n"

      elif child.kind == nkMapField:
        let fieldName = child.name
        let parts = child.value.split(",")
        var keyType = parts[0].strip()
        var valType = parts[1].strip()
        if node.reanamedTypeNamesInScope.len > 0 and
            node.reanamedTypeNamesInScope.hasKey(valType):
          valType = node.reanamedTypeNamesInScope[valType]
        let keyNimType = protoTypeToNim(keyType, false, packagePrefix)
        let valNimType = protoTypeToNim(valType, false, packagePrefix)

        result &= indentStr & "  if node.hasKey(\"" & fieldName & "\"):\n"
        result &= indentStr & "    for keyStr, valNode in node[\"" & fieldName & "\"]:\n"

        # Parse Key
        var keyParser = ""
        case keyType
        of "string": keyParser = "keyStr"
        of "int32", "int64", "uint32", "uint64", "sint32", "sint64", "fixed32",
            "fixed64", "sfixed32", "sfixed64":
          keyParser = keyNimType & "(parseInt(keyStr))"
        of "bool": keyParser = "parseBool(keyStr)"
        else: keyParser = "keyStr" # Should not happen for map keys

        result &= indentStr & "      let key = " & keyParser & "\n"

        # Parse Value
        var valParser = ""
        case valType
        of "string": valParser = "valNode.getStr()"
        of "int32", "int64", "uint32", "uint64", "sint32", "sint64", "fixed32",
            "fixed64", "sfixed32", "sfixed64":
          valParser = valNimType & "(valNode.getInt())"
        of "bool": valParser = "valNode.getBool()"
        of "float", "double": valParser = valNimType & "(valNode.getFloat())"
        else:
          # Message type
          valParser = "fromJson(" & valNimType & ", valNode)"

        result &= indentStr & "      result." & escapeNimKeyword(fieldName) &
            "[key] = " & valParser & "\n"

  result &= "\n\n"

  for child in node.children:
    if child.kind == nkField:
      let fieldName = child.name
      var protoType = child.value
      let isRepeated = child.attrs.anyIt(it.name == "label" and it.value == "repeated")

      var typeWasRenamed = false
      # Qualify nested types
      for (origName, qualName) in nestedTypeMap:
        if protoType == origName:
          protoType = qualName
          typeWasRenamed = true
      # Apply renamed type names from scope
      if node.reanamedTypeNamesInScope.len > 0 and
          node.reanamedTypeNamesInScope.hasKey(protoType):
        protoType = node.reanamedTypeNamesInScope[protoType]
        typeWasRenamed = true
      else:
        let root = getRoot(node)
        if root.globalTypeMap.hasKey(protoType):
          protoType = root.globalTypeMap[protoType]
          typeWasRenamed = true

      let pkgPrefix = if typeWasRenamed: "" else: packagePrefix

      result &= indentStr & "  if node.hasKey(\"" & fieldName & "\"):\n"

      if isRepeated:
        result &= indentStr & "    for item in node[\"" & fieldName & "\"]:\n"
        case child.value
        of "string":
          result &= indentStr & "      result." & escapeNimKeyword(fieldName) & ".add(item.getStr())\n"
        of "int32", "int64":
          result &= indentStr & "      result." & escapeNimKeyword(fieldName) &
              ".add(" & protoTypeToNim(child.value, false, packagePrefix) & "(item.getInt()))\n"
        of "uint32", "uint64":
          result &= indentStr & "      result." & escapeNimKeyword(fieldName) &
              ".add(" & protoTypeToNim(child.value, false, packagePrefix) & "(item.getInt()))\n"
        of "bool":
          result &= indentStr & "      result." & escapeNimKeyword(fieldName) & ".add(item.getBool())\n"
        of "float", "double":
          result &= indentStr & "      result." & escapeNimKeyword(fieldName) &
              ".add(" & protoTypeToNim(child.value, false, packagePrefix) & "(item.getFloat()))\n"
        else:
          # Message type
          let nimType = protoTypeToNim(protoType, false, pkgPrefix)
          result &= indentStr & "      result." & escapeNimKeyword(fieldName) &
              ".add(fromJson(" & nimType & ", item))\n"
      else:
        case child.value
        of "string":
          result &= indentStr & "    result." & escapeNimKeyword(fieldName) &
              " = node[\"" & fieldName & "\"].getStr()\n"
        of "int32", "int64":
          result &= indentStr & "    result." & escapeNimKeyword(fieldName) &
              " = " & protoTypeToNim(child.value, false, packagePrefix) &
                  "(node[\"" & fieldName &
              "\"].getInt())\n"
        of "uint32", "uint64":
          result &= indentStr & "    result." & escapeNimKeyword(fieldName) &
              " = " & protoTypeToNim(child.value, false, packagePrefix) &
                  "(node[\"" & fieldName &
              "\"].getInt())\n"
        of "bool":
          result &= indentStr & "    result." & escapeNimKeyword(fieldName) &
              " = node[\"" & fieldName & "\"].getBool()\n"
        of "float", "double":
          result &= indentStr & "    result." & escapeNimKeyword(fieldName) &
              " = " & protoTypeToNim(child.value, false, packagePrefix) &
                  "(node[\"" & fieldName &
              "\"].getFloat())\n"
        else:
          # Message type
          let nimType = protoTypeToNim(protoType, false, pkgPrefix)
          result &= indentStr & "    result." & escapeNimKeyword(fieldName) &
              " = fromJson(" & nimType & ", node[\"" & fieldName & "\"])\n"

    elif child.kind == nkMapField:
      let fieldName = child.name
      let parts = child.value.split(",")
      var keyType = parts[0].strip()
      var valType = parts[1].strip()
      if node.reanamedTypeNamesInScope.len > 0 and
          node.reanamedTypeNamesInScope.hasKey(valType):
        valType = node.reanamedTypeNamesInScope[valType]
      let keyNimType = protoTypeToNim(keyType, false, packagePrefix)
      let valNimType = protoTypeToNim(valType, false, packagePrefix)

      result &= indentStr & "  if node.hasKey(\"" & fieldName & "\"):\n"
      result &= indentStr & "    for keyStr, valNode in node[\"" & fieldName & "\"]:\n"

      # Parse Key
      var keyParser = ""
      case keyType
      of "string": keyParser = "keyStr"
      of "int32", "int64", "uint32", "uint64", "sint32", "sint64", "fixed32",
          "fixed64", "sfixed32", "sfixed64":
        keyParser = keyNimType & "(parseInt(keyStr))"
      of "bool": keyParser = "parseBool(keyStr)"
      else: keyParser = "keyStr" # Should not happen for map keys

      result &= indentStr & "      let key = " & keyParser & "\n"

      # Parse Value
      var valParser = ""
      case valType
      of "string": valParser = "valNode.getStr()"
      of "int32", "int64", "uint32", "uint64", "sint32", "sint64", "fixed32",
          "fixed64", "sfixed32", "sfixed64":
        valParser = valNimType & "(valNode.getInt())"
      of "bool": valParser = "valNode.getBool()"
      of "float", "double": valParser = valNimType & "(valNode.getFloat())"
      else:
        # Message type
        valParser = "fromJson(" & valNimType & ", valNode)"

      result &= indentStr & "      result." & escapeNimKeyword(fieldName) &
          "[key] = " & valParser & "\n"

  result &= "\n"

  result &= "\n"

proc collectEnums(node: ProtoNode, prefix: string = "", results: var HashSet[string]) =
  for child in node.children:
    case child.kind
    of nkEnum:
      let name = if prefix.len > 0: prefix & "_" & child.name else: child.name
      results.incl(name)
    of nkMessage:
      let name = if prefix.len > 0: prefix & "_" & child.name else: child.name
      collectEnums(child, name, results)
    of nkImport:
      for importedChild in child.children:
        if importedChild.kind == nkProto:
          var packagePrefix = ""
          for importedNode in importedChild.children:
            if importedNode.kind == nkPackage:
              packagePrefix = importedNode.name.replace(".", "_")
              break
          collectEnums(importedChild, packagePrefix, results)
    of nkProto:
      # Handle nested proto nodes (e.g. inside import)
      # But here we are recursing into import children which ARE nkProto
      # So we need to handle children of nkProto
      collectEnums(child, prefix, results)
    else:
      discard

proc generateEnumSerializationProcs*(enumName: string): string =
  ## Generate serialization procs for an enum type
  result = ""

  # toBinary proc - encode enum as int32
  result &= "proc toBinary*(self: " & enumName & "): seq[byte] =\n"
  result &= "  result = encodeInt32(int32(self))\n\n"

  # fromBinary proc - decode int32 to enum
  result &= "proc fromBinary*(T: typedesc[" & enumName &
      "], data: openArray[byte]): " & enumName & " =\n"
  result &= "  var pos = 0\n"
  result &= "  result = " & enumName & "(decodeInt32(data, pos))\n\n"

  # toJson proc - convert enum to JSON number
  result &= "proc toJson*(self: " & enumName & "): JsonNode =\n"
  result &= "  result = %int(self)\n\n"

  # fromJson proc - parse JSON number to enum
  result &= "proc fromJson*(T: typedesc[" & enumName & "], node: JsonNode): " &
      enumName & " =\n"
  result &= "  result = " & enumName & "(node.getInt())\n\n"

proc generateAllSerializationProcs(node: ProtoNode, prefix: string = "",
    enumNames: HashSet[string], packagePrefix: string = "",
        checkDefined: bool = false): string =
  result = ""

  let typeName = if prefix.len > 0:
    capitalizeTypeName(prefix & "_" & node.name)
  else:
    capitalizeTypeName(node.name)

  # Build nested type map for this message
  var nestedTypeMap: seq[(string, string)] = @[]
  for subchild in node.children:
    if subchild.kind == nkMessage or subchild.kind == nkEnum:
      nestedTypeMap.add((subchild.name, typeName & "_" & subchild.name))

  # Recursively generate for nested messages and enums
  for child in node.children:
    case child.kind
    of nkMessage:
      # Nested message name construction needs to match what generateMessage does
      let childPrefix = if prefix.len > 0: prefix & "_" &
          node.name else: node.name
      # Don't pass checkDefined to nested - they're always defined when parent is
      result &= generateAllSerializationProcs(child, childPrefix, enumNames,
          packagePrefix, false)
    of nkEnum:
      # Generate serialization for nested enum
      let enumName = typeName & "_" & capitalizeTypeName(child.name)
      result &= generateEnumSerializationProcs(enumName)
    else:
      discard

  # Generate for current message
  result &= generateSerializationProcs(node, typeName, nestedTypeMap, enumNames,
      packagePrefix, checkDefined)

proc generateService*(node: ProtoNode, packagePrefix: string = ""): string =
  ## Generate gRPC client stub procedures from a service definition
  assert node.kind == nkService

  result = "# gRPC client stubs for " & node.name & "\n"

  for child in node.children:
    if child.kind == nkRpc:
      let rpcName = child.name
      var reqType = ""
      var respType = ""
      var clientStreaming = false
      var serverStreaming = false

      # Extract RPC metadata from attrs
      for attr in child.attrs:
        if attr.kind == nkOption:
          case attr.name
          of "request_type":
            reqType = attr.value
          of "response_type":
            respType = attr.value
          of "client_streaming":
            clientStreaming = (attr.value == "true")
          of "server_streaming":
            serverStreaming = (attr.value == "true")

      # Convert proto types to Nim types
      let reqNimType = capitalizeTypeName(reqType.replace(".", "_"))
      let respNimType = capitalizeTypeName(respType.replace(".", "_"))

      # Generate procedure name (camelCase)
      let procName = if rpcName.len > 0:
        rpcName[0].toLowerAscii & rpcName[1..^1]
      else:
        rpcName

      # Determine signature based on streaming type
      if not clientStreaming and not serverStreaming:
        # Unary: single request -> single response
        result &= "proc " & procName & "*(c: GrpcChannel, req: " & reqNimType &
            ", metadata: seq[HpackHeader] = @[]): Future[" & respNimType & "] {.async.} =\n"
        result &= "  let binReq = req.toBinary()\n"
        result &= "  let rawResps = await c.grpcInvoke(\"/" & node.name & "/" &
            rpcName & "\", @[binReq], metadata)\n"
        result &= "  if rawResps.len == 0:\n"
        result &= "    raise newException(ValueError, \"No response received\")\n"
        result &= "  return " & respNimType & ".fromBinary(rawResps[0])\n\n"

      elif clientStreaming and not serverStreaming:
        # Client streaming: seq[request] -> single response
        result &= "proc " & procName & "*(c: GrpcChannel, reqs: seq[" &
            reqNimType & "]): Future[" & respNimType & "] {.async.} =\n"
        result &= "  var binReqs: seq[seq[byte]] = @[]\n"
        result &= "  for req in reqs:\n"
        result &= "    binReqs.add(req.toBinary())\n"
        result &= "  let rawResps = await c.grpcInvoke(\"/" & node.name & "/" &
            rpcName & "\", binReqs)\n"
        result &= "  if rawResps.len == 0:\n"
        result &= "    raise newException(ValueError, \"No response received\")\n"
        result &= "  return " & respNimType & ".fromBinary(rawResps[0])\n\n"

      elif not clientStreaming and serverStreaming:
        # Server streaming: single request -> seq[response]
        result &= "proc " & procName & "*(c: GrpcChannel, req: " & reqNimType &
            "): Future[seq[" & respNimType & "]] {.async.} =\n"
        result &= "  let binReq = req.toBinary()\n"
        result &= "  let rawResps = await c.grpcInvoke(\"/" & node.name & "/" &
            rpcName & "\", @[binReq])\n"
        result &= "  result = @[]\n"
        result &= "  for r in rawResps:\n"
        result &= "    result.add(" & respNimType & ".fromBinary(r))\n\n"

      else:
        # Bidirectional streaming: seq[request] -> seq[response]
        result &= "proc " & procName & "*(c: GrpcChannel, reqs: seq[" &
            reqNimType & "]): Future[seq[" & respNimType & "]] {.async.} =\n"
        result &= "  var binReqs: seq[seq[byte]] = @[]\n"
        result &= "  for req in reqs:\n"
        result &= "    binReqs.add(req.toBinary())\n"
        result &= "  let rawResps = await c.grpcInvoke(\"/" & node.name & "/" &
            rpcName & "\", binReqs)\n"
        result &= "  result = @[]\n"
        result &= "  for r in rawResps:\n"
        result &= "    result.add(" & respNimType & ".fromBinary(r))\n\n"

proc generateForwardDeclarations(node: ProtoNode, prefix: string = "",
    packagePrefix: string = "", checkDefined: bool = false): string =
  result = ""
  let typeName = if prefix.len > 0:
    capitalizeTypeName(prefix & "_" & node.name)
  else:
    capitalizeTypeName(node.name)

  if checkDefined:
    result &= "when declared(Defined_" & typeName & "):\n"

  let indentStr = if checkDefined: "  " else: ""

  result &= indentStr & "proc toBinary*(self: " & typeName & "): seq[byte]\n"
  result &= indentStr & "proc fromBinary*(T: typedesc[" & typeName &
      "], data: openArray[byte]): " & typeName & "\n"
  result &= indentStr & "proc toJson*(self: " & typeName & "): JsonNode\n"
  result &= indentStr & "proc fromJson*(T: typedesc[" & typeName &
      "], node: JsonNode): " & typeName & "\n"
  result &= "\n"

  # Recursively generate for nested messages
  for child in node.children:
    if child.kind == nkMessage:
      let childPrefix = if prefix.len > 0: prefix & "_" &
          node.name else: node.name
      # Don't pass checkDefined to nested - they're always defined when parent is
      result &= generateForwardDeclarations(child, childPrefix, packagePrefix, false)

proc generateTypes*(ast: ProtoNode): string =
  ## Generate all type definitions from a Proto AST
  ## Returns Nim code as a string
  ##
  ast.renameSubmessageTypeNames() # get child-parent links, renamedTypeNamesInCurrentScope

  result = "import nimproto3\n\n\n# Generated from protobuf\n"
  # result &= "type\n"

  var nestedTypes: seq[string] = @[]
  var mainTypes: seq[string] = @[]
  var enumNames = initHashSet[string]()

  collectEnums(ast, "", enumNames)

  var processedImports = initHashSet[string]()

  # Helper proc to recursively process imports
  proc processImports(node: ProtoNode, mainTypes: var seq[string],
      nestedTypes: var seq[string]) =
    for child in node.children:
      if child.kind == nkImport:
        let importFile = child.value
        if processedImports.contains(importFile): continue
        processedImports.incl(importFile)

        # Process the imported AST
        for importedChild in child.children:
          if importedChild.kind == nkProto:
            # First, recursively process imports of this imported file
            processImports(importedChild, mainTypes, nestedTypes)

            # Get the package name from the imported proto to use as prefix
            var packagePrefix = ""
            for importedNode in importedChild.children:
              if importedNode.kind == nkPackage:
                packagePrefix = importedNode.name.replace(".", "_")
                break

            # Generate types from the imported proto with package prefix
            for importedNode in importedChild.children:
              case importedNode.kind
              of nkMessage:
                mainTypes.add(generateMessage(importedNode, packagePrefix,
                    nestedTypes, packagePrefix))
              of nkEnum:
                mainTypes.add(generateEnum(importedNode, packagePrefix))
              else:
                discard

  # First, process all imports (including transitive imports)
  processImports(ast, mainTypes, nestedTypes)

  # Then process the main file's types
  for child in ast.children:
    case child.kind
    of nkMessage:
      mainTypes.add(generateMessage(child, "", nestedTypes))
    of nkEnum:
      mainTypes.add(generateEnum(child))
    else:
      discard

  # Add all types
  if mainTypes.len > 0 or nestedTypes.len > 0:
    result &= "type\n"
    for i, typeStr in mainTypes:
      result &= indent(typeStr, 1)
      if i < mainTypes.len - 1 or nestedTypes.len > 0:
        result &= "\n"

    for i, typeStr in nestedTypes:
      result &= indent(typeStr, 1)
      if i < nestedTypes.len - 1:
        result &= "\n"

  result &= "\n"

  # Forward declarations for imported messages
  var processedImportsFwd = initHashSet[string]()

  proc processImportsFwd(node: ProtoNode): string =
    result = ""
    for child in node.children:
      if child.kind == nkImport:
        let importFile = child.value
        if processedImportsFwd.contains(importFile):
          continue
        processedImportsFwd.incl(importFile)

        for importedChild in child.children:
          if importedChild.kind == nkProto:
            # Recursively process imports of this imported file
            result &= processImportsFwd(importedChild)

            var packagePrefix = ""
            for importedNode in importedChild.children:
              if importedNode.kind == nkPackage:
                packagePrefix = importedNode.name.replace(".", "_")
                break

            for importedNode in importedChild.children:
              if importedNode.kind == nkMessage:
                result &= generateForwardDeclarations(importedNode,
                    packagePrefix, packagePrefix, false)

  result &= processImportsFwd(ast)

  # Forward declarations for main messages
  for child in ast.children:
    if child.kind == nkMessage:
      result &= generateForwardDeclarations(child, "", "", false)

  # Implementations for imported messages and enums
  var processedImportsImpl = initHashSet[string]()

  proc processImportsImpl(node: ProtoNode): string =
    result = ""
    for child in node.children:
      if child.kind == nkImport:
        let importFile = child.value
        if processedImportsImpl.contains(importFile):
          continue
        processedImportsImpl.incl(importFile)

        for importedChild in child.children:
          if importedChild.kind == nkProto:
            # Recursively process imports of this imported file
            result &= processImportsImpl(importedChild)

            var packagePrefix = ""
            for importedNode in importedChild.children:
              if importedNode.kind == nkPackage:
                packagePrefix = importedNode.name.replace(".", "_")
                break

            for importedNode in importedChild.children:
              case importedNode.kind
              of nkMessage:
                result &= generateAllSerializationProcs(importedNode,
                    packagePrefix, enumNames, packagePrefix, false)
              of nkEnum:
                let enumName = if packagePrefix.len > 0:
                  capitalizeTypeName(packagePrefix & "_" & importedNode.name)
                else:
                  capitalizeTypeName(importedNode.name)
                result &= generateEnumSerializationProcs(enumName)
              else:
                discard

  result &= processImportsImpl(ast)

  # Generate serialization procs for main messages and enums
  for child in ast.children:
    case child.kind
    of nkMessage:
      result &= generateAllSerializationProcs(child, "", enumNames, "", false)
    of nkEnum:
      let enumName = capitalizeTypeName(child.name)
      result &= generateEnumSerializationProcs(enumName)
    else:
      discard

  # Generate gRPC service stubs
  for child in ast.children:
    if child.kind == nkService:
      result &= generateService(child, "")

proc genCodeFromProtoString*(protoString: string, searchDirs: seq[string] = @[],
    extraImportPackages: seq[string] = @[]): string =
  let ast = parseProto(protoString, searchDirs,
      extraImportPackages = extraImportPackages)
  return generateTypes(ast)

proc genCodeFromProtoFile*(filePath: string, searchDirs: seq[string] = @[],
    extraImportPackages: seq[string] = @[]): string =
  if not fileExists(filePath):
    raise newException(ValueError, "File does not exist: " & filePath)

  var fullSearchDirs = searchDirs
  fullSearchDirs.add(parentDir(filePath))
  let ast = parseProto(readFile(filePath), fullSearchDirs,
      extraImportPackages = extraImportPackages)
  return generateTypes(ast)
