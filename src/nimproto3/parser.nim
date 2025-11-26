import npeg, strutils, tables, os
import ./ast

type
  ParserState = object
    root: ProtoNode
    stack: seq[ProtoNode]
    searchDirs: seq[string]
    cache: ref Table[string, ProtoNode]

proc push(s: var ParserState, node: ProtoNode) =
  if s.stack.len > 0:
    s.stack[^1].add(node)
  else:
    s.root = node
  s.stack.add(node)

proc pop(s: var ParserState) =
  discard s.stack.pop()

proc peek(s: var ParserState): ProtoNode {.used.} =
  if s.stack.len > 0: result = s.stack[^1]

proc resolvePath(filename: string, searchDirs: seq[
    string]): string =
  if fileExists(filename): return filename
  for dir in searchDirs:
    let path = dir / filename
    if fileExists(path): return path
  return ""

# Forward declaration
proc parseProto*(content: string, searchDirs: seq[string] = @[],
    cache: ref Table[string, ProtoNode] = nil): ProtoNode

let parser* = peg("proto", s: ParserState):
  # Basic tokens
  tkDoubleQuote <- "\""
  tkSingleQuote <- "'"
  tkSemi <- ";"
  tkEq <- "="
  tkLBrace <- "{"
  tkRBrace <- "}"
  tkLBracket <- "["
  tkRBracket <- "]"
  tkLParen <- "("
  tkRParen <- ")"
  tkComma <- ","
  tkDot <- "."
  tkLess <- "<"
  tkGreater <- ">"

  # Whitespace and comments
  space <- {' ', '\t', '\r', '\n'}
  comment <- "//" * *(1 - '\n') * ?'\n' | "/*" * *(1 - "*/") * "*/"
  S <- *(space | comment)

  # Identifiers and literals
  identStart <- {'a'..'z', 'A'..'Z', '_'}
  identChar <- identStart | {'0'..'9'}
  identifier <- identStart * *identChar
  # Package identifier segments may contain '-'
  identifierHyphen <- identStart * *(identChar | '-')
  packageFullIdentifier <- identifierHyphen * *('.' * identifierHyphen)

  fullIdentifier <- identifier * *('.' * identifier)

  decInt <- > +Digit
  hexInt <- "0x" * > +Xdigit
  octInt <- "0" * > +{'0'..'7'}
  floatLit <- > *Digit * '.' * +Digit * ?(i"e" * ?{'+', '-'} * +Digit)
  boolLit <- >("true" | "false")

  strLit <- tkDoubleQuote * > *(1 - tkDoubleQuote) * tkDoubleQuote |
            tkSingleQuote * > *(1 - tkSingleQuote) * tkSingleQuote

  constant <- >fullIdentifier | floatLit | decInt | hexInt | octInt | boolLit | strLit

  # Syntax
  syntax <- "syntax" * S * tkEq * S * strLit * S * tkSemi * S:
    s.root = newProtoNode(nkProto)
    s.stack.add(s.root)
    var node = newProtoNode(nkSyntax, value = $1)
    s.push(node)
    s.pop()

  # Edition (proto3.21+)
  edition <- "edition" * S * tkEq * S * strLit * S * tkSemi * S:
    if s.root.isNil:
      s.root = newProtoNode(nkProto)
      s.stack.add(s.root)
    var node = newProtoNode(nkEdition, value = $1)
    s.push(node)
    s.pop()

  # Package (allow hyphen in segments)
  package <- "package" * S * >packageFullIdentifier * S * tkSemi * S:
    var node = newProtoNode(nkPackage, name = $1)
    s.push(node)
    s.pop()

  # Import
  importStmt <- "import" * S * ?("public" * S | "weak" * S) * strLit * S *
      tkSemi * S:
    var node = newProtoNode(nkImport, value = $1)

    # Resolve and parse import
    let filename = $1
    let path = resolvePath(filename, s.searchDirs)
    if path != "":
      if not s.cache.hasKey(path):
        # Prevent infinite recursion by adding a placeholder or checking stack?
        # For now, simple cache check.
        try:
          let content = readFile(path)
          # Recursive call
          let importedAst = parseProto(content, s.searchDirs, s.cache)
          s.cache[path] = importedAst
          node.children.add(importedAst)
        except:
          echo "Warning: Failed to parse imported file: ", path
      else:
        node.children.add(s.cache[path])
    else:
      echo "Warning: Import not found: ", filename

    s.push(node)
    s.pop()

  # Option
  optionName <- (tkLParen * fullIdentifier * tkRParen | fullIdentifier) * *(
      '.' * fullIdentifier)
  option <- "option" * S * >optionName * S * tkEq * S * constant * S * tkSemi * S:
    var node = newProtoNode(nkOption, name = $1, value = $2)
    s.push(node)
    s.pop()

  # Field Options
  # We need to capture options and add them to the field node.
  # Since field node is created at the end of field rule (currently), we can't add options easily.
  # But field is a leaf node in terms of structure (it doesn't contain other fields).
  # So we can keep the current approach for field, BUT we need to handle fieldOptions.
  # For now, let's just parse fieldOptions but not attach them to AST to avoid complexity,
  # OR we can use a temporary storage.
  # Better: Create field node EARLY.

  fieldOption <- >optionName * S * tkEq * S * constant:
    # This runs after option matches.
    # We need to add this option to the current field node.
    # This requires the field node to be on the stack!
    var node = newProtoNode(nkOption, name = $1, value = $2)
    s.push(node)
    s.pop()

  fieldOptions <- tkLBracket * S * fieldOption * *(S * tkComma * S *
      fieldOption) * S * tkRBracket

  # Field
  label <- "repeated" | "optional" | "required"
  type_name <- fullIdentifier
  fieldNumber <- decInt | hexInt | octInt

  # We split field into Start and End to allow fieldOptions to add to it.
  fieldStart <- ?( > label * S) * >type_name * S * >identifier * S * tkEq * S *
      fieldNumber * S:
    var name, val, num, lbl: string
    # capture[0] is the whole match
    if capture.len == 5:
      lbl = capture[1].s
      val = capture[2].s
      name = capture[3].s
      num = capture[4].s
    else:
      val = capture[1].s
      name = capture[2].s
      num = capture[3].s

    var node = newProtoNode(nkField, name = name, value = val,
        number = parseInt(num))
    if lbl != "":
      node.attrs.add(newProtoNode(nkOption, name = "label", value = lbl))
    s.push(node)

  fieldEnd <- tkSemi * S:
    s.pop()

  field <- fieldStart * ?fieldOptions * S * fieldEnd

  # Map Field
  mapFieldStart <- "map" * S * tkLess * S * >type_name * S * tkComma * S *
      > type_name * S * tkGreater * S * >identifier * S * tkEq * S *
      fieldNumber * S:
    var node = newProtoNode(nkMapField, name = $3, value = $1 & "," & $2,
        number = parseInt($4))
    s.push(node)

  mapFieldEnd <- tkSemi * S:
    s.pop()

  mapField <- mapFieldStart * ?fieldOptions * S * mapFieldEnd

  # Oneof
  oneofStart <- "oneof" * S * >identifier * S * tkLBrace * S:
    var node = newProtoNode(nkOneof, name = $1)
    s.push(node)

  oneofEnd <- tkRBrace * S:
    s.pop()

  # OneofField needs to be adapted too if we want options
  oneofFieldStart <- >type_name * S * >identifier * S * tkEq * S * fieldNumber * S:
    var node = newProtoNode(nkField, name = $2, value = $1, number = parseInt($3))
    s.push(node)

  oneofFieldEnd <- tkSemi * S:
    s.pop()

  oneofField <- oneofFieldStart * ?fieldOptions * S * oneofFieldEnd

  oneof <- oneofStart * *oneofField * S * oneofEnd

  # Reserved
  range <- >decInt * S * "to" * S * >decInt | >decInt
  reserved <- "reserved" * S * (range * *(S * tkComma * S * range) | strLit * *(
      S * tkComma * S * strLit)) * S * tkSemi * S:
    var node = newProtoNode(nkReserved)
    s.push(node)
    s.pop()

  # Enum
  enumStart <- "enum" * S * >identifier * S * tkLBrace * S:
    var node = newProtoNode(nkEnum, name = $1)
    s.push(node)

  enumEnd <- tkRBrace * S:
    s.pop()

  enumFieldStart <- >identifier * S * tkEq * S * >decInt * S:
    var node = newProtoNode(nkEnumField, name = $1, number = parseInt($2))
    s.push(node)

  enumFieldEnd <- tkSemi * S:
    s.pop()

  enumField <- enumFieldStart * ?fieldOptions * S * enumFieldEnd

  enumDef <- enumStart * *(option | enumField | reserved) * enumEnd

  # Message
  messageStart <- "message" * S * >identifier * S * tkLBrace * S:
    var node = newProtoNode(nkMessage, name = $1)
    s.push(node)

  messageEnd <- tkRBrace * S:
    s.pop()

  messageBody <- *(field | mapField | oneof | option | reserved | enumDef |
      messageDef)

  messageDef <- messageStart * messageBody * messageEnd

  # Service
  serviceStart <- "service" * S * >identifier * S * tkLBrace * S:
    var node = newProtoNode(nkService, name = $1)
    s.push(node)

  serviceEnd <- tkRBrace * S:
    s.pop()

  rpcStart <- "rpc" * S * >identifier * S * tkLParen * S * >?("stream" * S) *
      > type_name * S * tkRParen * S * "returns" * S * tkLParen * S * >?(
      "stream" * S) * >type_name * S * tkRParen * S:
    var node = newProtoNode(nkRpc, name = $1)

    # Request info
    let clientStream = $2
    let reqType = $3
    node.attrs.add(newProtoNode(nkOption, name = "request_type",
        value = reqType))
    if clientStream.strip() == "stream":
      node.attrs.add(newProtoNode(nkOption, name = "client_streaming",
          value = "true"))

    # Response info
    let serverStream = $4
    let respType = $5
    node.attrs.add(newProtoNode(nkOption, name = "response_type",
        value = respType))
    if serverStream.strip() == "stream":
      node.attrs.add(newProtoNode(nkOption, name = "server_streaming",
          value = "true"))

    s.push(node)

  rpcEnd <- ((tkLBrace * S * *(option) * tkRBrace * ?(S * tkSemi)) | tkSemi) * S:
    s.pop()

  rpc <- rpcStart * rpcEnd

  service <- serviceStart * *(option | rpc) * serviceEnd

  # Top level
  topLevel <- (syntax | edition) * *(importStmt | package | option |
      messageDef | enumDef |
      service)
  proto <- S * topLevel * !1

proc getProtocIncludePath(): string =
  # Try to find protoc in PATH
  let protocPath = findExe("protoc")
  if protocPath.len > 0:
    # Assuming standard layout: bin/protoc -> include/google/protobuf
    # So we want the parent of bin, then include.
    let binDir = parentDir(protocPath)
    let prefix = parentDir(binDir)
    let includeDir = prefix / "include"
    if dirExists(includeDir):
      return includeDir
  return ""

proc parseProto*(content: string, searchDirs: seq[string] = @[],
    cache: ref Table[string, ProtoNode] = nil, extraImportPackages: seq[
        string] = @[]): ProtoNode =
  var s: ParserState

  # Initialize search dirs with env var
  let envPath = getEnv("PROTO_PATH")
  if envPath.len > 0:
    s.searchDirs.add(envPath.split(PathSep))

  # Add auto-detected protoc include path
  let stdPath = getProtocIncludePath()
  if stdPath.len > 0:
    s.searchDirs.add(stdPath)

  s.searchDirs.add(searchDirs)

  # Initialize cache
  if cache != nil:
    s.cache = cache
  else:
    s.cache = newTable[string, ProtoNode]()

  let res = parser.match(content, s)
  if not res.ok:
    raise newException(ValueError, "Failed to parse proto file at index " & $res.matchMax)
  result = s.root
