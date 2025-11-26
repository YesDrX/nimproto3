
import strutils, tables


type
  ProtoNodeKind* = enum
    nkProto, nkSyntax, nkEdition, nkPackage, nkImport, nkOption,
    nkMessage, nkEnum, nkService, nkField, nkMapField, nkOneof,
    nkEnumField, nkRpc, nkStream, nkComment, nkReserved, nkExtensions,
    nkGroup

  ProtoNode* {.acyclic.} = ref object
    kind*: ProtoNodeKind
    name*: string
    value*: string         # For literals, types, etc.
    number*: int           # For field numbers
    children*: seq[ProtoNode]
    attrs*: seq[ProtoNode] # For options, etc.
    parent*: ProtoNode
    reanamedTypeNamesInScope*: Table[string, string]
    globalTypeMap*: Table[string, string]

proc copyTable[K, V](input: Table[K, V]): Table[K, V] =
  for k, v in input.pairs:
    result[k] = v

proc newProtoNode*(kind: ProtoNodeKind, name: string = "", value: string = "",
    number: int = 0): ProtoNode =
  ProtoNode(kind: kind, name: name, value: value, number: number)

proc getFullTypeName*(node: ProtoNode): string =
  if node.kind != nkMessage and node.kind != nkEnum:
    raise newException(ValueError, "getFullTypeName called on non-message or non-enum node")
  result = node.name
  var parent = node.parent
  while parent != nil:
    if parent.kind == nkMessage:
      result = parent.name & "_" & result
    parent = parent.parent

proc getRoot*(node: ProtoNode): ProtoNode =
  result = node
  while result.parent != nil:
    result = result.parent

proc renameSubmessageTypeNames*(node: ProtoNode) =
  if node.parent != nil:
    node.reanamedTypeNamesInScope = node.parent.reanamedTypeNamesInScope.copyTable()

  # First, process imports to add imported types to scope
  for child in node.children:
    child.parent = node
    if child.kind == nkImport:
      # Process imported proto files
      for importedChild in child.children:
        if importedChild.kind == nkProto:
          # Get the package name from the imported proto
          var packagePrefix = ""
          for importedNode in importedChild.children:
            if importedNode.kind == nkPackage:
              packagePrefix = importedNode.name.replace(".", "_")
              break

          # Add all types from the imported file to the current scope and global map
          for importedNode in importedChild.children:
            if importedNode.kind == nkMessage or importedNode.kind == nkEnum:
              let qualifiedName = if packagePrefix.len > 0:
                packagePrefix & "_" & importedNode.name
              else:
                importedNode.name
              node.reanamedTypeNamesInScope[importedNode.name] = qualifiedName

              # Add to global map on root
              var root = getRoot(node)
              root.globalTypeMap[importedNode.name] = qualifiedName

  # Then process nested types
  for child in node.children:
    if child.kind == nkMessage or child.kind == nkEnum:
      let fullName = getFullTypeName(child)
      if fullName != child.name:
        node.reanamedTypeNamesInScope[child.name] = fullName

  # Recursively process children
  for child in node.children:
    if child.kind == nkMessage or child.kind == nkImport or child.kind == nkProto:
      renameSubmessageTypeNames(child)

proc add*(parent: ProtoNode, child: ProtoNode) =
  parent.children.add(child)

proc `$`*(node: ProtoNode): string =
  result = $node.kind
  if node.name.len > 0: result.add " name=" & node.name
  if node.value.len > 0: result.add " value=" & node.value
  if node.number != 0: result.add " number=" & $node.number
  if node.attrs.len > 0:
    result.add " attrs=["
    for i, attr in node.attrs:
      if i > 0: result.add ", "
      result.add $attr
    result.add "]"
  if node.children.len > 0:
    result.add " {\n"
    for child in node.children:
      for line in ($child).splitLines:
        result.add "  " & line & "\n"
    result.add "}"

proc printRenamedTypes*(node: ProtoNode): string =
  result = $node.kind
  if node.name.len > 0: result.add " name=" & node.name
  if node.reanamedTypeNamesInScope.len > 0:
    result.add " renamedTypes=["
    for oldName, newName in node.reanamedTypeNamesInScope.pairs:
      result.add " " & oldName & "->" & newName & ", "
    result.add " ]"
  if node.children.len > 0:
    result.add " {\n"
    for child in node.children:
      for line in (printRenamedTypes(child)).splitLines:
        result.add "  " & line & "\n"
    result.add "}"
