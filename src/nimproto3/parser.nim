# parser.nim
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

proc resolvePath(filename: string, searchDirs: seq[string]): string =
  if fileExists(filename): return filename
  for dir in searchDirs:
    let path = dir / filename
    if fileExists(path): return path
  return ""

# Helper to parse Proto integer formats (Hex, Octal, Decimal)
proc parseProtoNumber(s: string): int =
  try:
    if s.len > 1 and (s.startsWith("0x") or s.startsWith("0X")):
      result = parseHexInt(s)
    elif s.len > 1 and s.startsWith("0"):
      result = parseOctInt(s)
    else:
      result = parseInt(s)
  except ValueError:
    result = 0 

# Forward declaration
proc parseProto*(content: string, searchDirs: seq[string] = @[],
    cache: ref Table[string, ProtoNode] = nil, extraImportPackages: seq[
        string] = @[]): ProtoNode

let parser* = peg("proto", s: ParserState):
  # Basic tokens
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
  
  identifierHyphen <- identStart * *(identChar | '-')
  packageFullIdentifier <- identifierHyphen * *('.' * identifierHyphen)

  fullIdentifier <- identifier * *('.' * identifier)

  # Integer Literals
  hexInt <- >("0x" * +Xdigit)
  octInt <- >("0" * +{'0'..'7'})
  decInt <- > +Digit
  
  intLit <- hexInt | octInt | decInt

  floatLit <- > *Digit * '.' * +Digit * ?(i"e" * ?{'+', '-'} * +Digit)
  boolLit <- >("true" | "false")

  # String Literals
  # Define content logic: match escaped char OR non-quote char
  dqContent <- "\\\"" | 1 - {'"'}
  sqContent <- "\\'" | 1 - {'\''}
  
  # Capturing versions (for normal values)
  dqStr <- '"' * > *dqContent * '"'
  sqStr <- '\'' * > *sqContent * '\''
  strLit <- dqStr | sqStr

  # Non-capturing versions (for aggregate skipping to avoid capture pollution)
  dqStrSkip <- '"' * *dqContent * '"'
  sqStrSkip <- '\'' * *sqContent * '\''
  strLitSkip <- dqStrSkip | sqStrSkip

  # Aggregate / Message Literal
  # Safely consumes content inside {} including nesting and strings
  # Use strLitSkip to avoid adding captures to the stack which confuses fieldOption
  aggregate <- "{" * *( strLitSkip | comment | aggregate | 1 - {'{', '}'} ) * "}"

  constant <- >fullIdentifier | floatLit | intLit | boolLit | strLit | >aggregate

  # Syntax
  syntax <- "syntax" * S * tkEq * S * strLit * S * tkSemi * S:
    s.root = newProtoNode(nkProto)
    s.stack.add(s.root)
    var node = newProtoNode(nkSyntax, value = $1)
    s.push(node)
    s.pop()

  # Edition
  edition <- "edition" * S * tkEq * S * strLit * S * tkSemi * S:
    if s.root.isNil:
      s.root = newProtoNode(nkProto)
      s.stack.add(s.root)
    var node = newProtoNode(nkEdition, value = $1)
    s.push(node)
    s.pop()

  # Package
  package <- "package" * S * >packageFullIdentifier * S * tkSemi * S:
    var node = newProtoNode(nkPackage, name = $1)
    s.push(node)
    s.pop()

  # Import
  importStmt <- "import" * S * ?("public" * S | "weak" * S) * strLit * S *
      tkSemi * S:
    var node = newProtoNode(nkImport, value = $1)
    let filename = $1
    let path = resolvePath(filename, s.searchDirs)
    if path != "":
      if not s.cache.hasKey(path):
        try:
          let content = readFile(path)
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
  fieldOption <- >optionName * S * tkEq * S * constant:
    # Captures: $1 = optionName, $2 = constant
    var node = newProtoNode(nkOption, name = $1, value = $2)
    s.push(node)
    s.pop()

  fieldOptions <- tkLBracket * S * fieldOption * *(S * tkComma * S *
      fieldOption) * S * tkRBracket

  # Field
  label <- "repeated" | "optional" | "required"
  type_name <- fullIdentifier
  fieldNumber <- intLit

  fieldStart <- ?( > label * S) * >type_name * S * >identifier * S * tkEq * S *
      fieldNumber * S:
    var name, val, numStr, lbl: string
    if capture.len == 5:
      lbl = capture[1].s
      val = capture[2].s
      name = capture[3].s
      numStr = capture[4].s
    else:
      val = capture[1].s
      name = capture[2].s
      numStr = capture[3].s

    var node = newProtoNode(nkField, name = name, value = val,
        number = parseProtoNumber(numStr))
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
        number = parseProtoNumber($4))
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

  oneofFieldStart <- >type_name * S * >identifier * S * tkEq * S * fieldNumber * S:
    var node = newProtoNode(nkField, name = $2, value = $1, number = parseProtoNumber($3))
    s.push(node)

  oneofFieldEnd <- tkSemi * S:
    s.pop()

  oneofField <- oneofFieldStart * ?fieldOptions * S * oneofFieldEnd

  oneof <- oneofStart * *oneofField * S * oneofEnd

  # Reserved
  rangeVal <- intLit
  range <- >rangeVal * S * "to" * S * >rangeVal | >rangeVal
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

  enumFieldStart <- >identifier * S * tkEq * S * intLit * S:
    var node = newProtoNode(nkEnumField, name = $1, number = parseProtoNumber($2))
    s.push(node)

  enumFieldEnd <- tkSemi * S:
    s.pop()

  enumField <- enumFieldStart * ?fieldOptions * S * enumFieldEnd

  enumDef <- enumStart * *(option | enumField | reserved) * enumEnd

  # Extend
  extendStart <- "extend" * S * >type_name * S * tkLBrace * S:
    var node = newProtoNode(nkExtend, value = $1)
    s.push(node)

  extendEnd <- tkRBrace * S:
    s.pop()

  extendDef <- extendStart * *(field | option) * extendEnd

  # Extensions
  extensionRangeVal <- "max" | intLit
  extensionRange <- >extensionRangeVal * S * "to" * S * >extensionRangeVal | >extensionRangeVal
  
  extensions <- "extensions" * S * extensionRange * *(S * tkComma * S * extensionRange) * ?fieldOptions * S * tkSemi * S:
    var node = newProtoNode(nkExtensions)
    s.push(node)
    s.pop()

  # Message
  messageStart <- "message" * S * >identifier * S * tkLBrace * S:
    var node = newProtoNode(nkMessage, name = $1)
    s.push(node)

  messageEnd <- tkRBrace * S:
    s.pop()

  messageBody <- *(field | mapField | oneof | option | reserved | extensions | enumDef |
      messageDef | extendDef)

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
      service | extendDef)
  proto <- S * topLevel * !1

proc getProtocIncludePath(): string =
  # Try to find protoc in PATH
  let protocPath = findExe("protoc")
  if protocPath.len > 0:
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

  let envPath = getEnv("PROTO_PATH")
  if envPath.len > 0:
    s.searchDirs.add(envPath.split(PathSep))

  let stdPath = getProtocIncludePath()
  if stdPath.len > 0:
    s.searchDirs.add(stdPath)

  s.searchDirs.add(searchDirs)

  if cache != nil:
    s.cache = cache
  else:
    s.cache = newTable[string, ProtoNode]()

  if extraImportPackages.len > 0:
    var protoContent = content.splitLines()
    var modifiedProtoContent: seq[string]
    var idx = -1
    for line in protoContent:
      idx += 1
      if line.strip().startswith("syntax") or line.strip().startswith(
          "package") or line.strip().startswith("//"):
        continue
      else:
        break
    modifiedProtoContent = protoContent[0 ..< idx]
    for pkg in extraImportPackages:
      modifiedProtoContent.add("import \"" & pkg & "\";\n")
    modifiedProtoContent.add(protoContent[idx ..< protoContent.len])
    let res = parser.match(modifiedProtoContent.join("\n"), s)
    if not res.ok: raise newException(ValueError,
        "Failed to parse proto file at index " & $res.matchMax & " : " & modifiedProtoContent.join("\n")[max(0, res.matchMax-1) ..< min(res.matchMax + 100, modifiedProtoContent.join("\n").len)])
    result = s.root
  else:
    let res = parser.match(content, s)
    if not res.ok: raise newException(ValueError,
        "Failed to parse proto file at index " & $res.matchMax & " : " & content[max(0, res.matchMax-1) ..< min(res.matchMax + 100, content.len)])
    result = s.root