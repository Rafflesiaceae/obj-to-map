import strutils, lexbase, streams, unicode
import std/private/decode_helpers
import parseutils
import glm
import strformat

const
  WordChars* = {'a'..'z', 'A'..'Z', '0'..'9', '_', '-', '/', '.', '(', ')'}
  FaceEntrychars* = {'0'..'9', '/'}

type
  TokKind* = enum
    # @TODO cleanup
    tkError,
    tkEof,
    tkString,
    tkInt,
    tkFloat,
    tkTrue,
    tkFalse,
    tkNull,
    tkCurlyLe,
    tkCurlyRi,
    tkBracketLe,
    tkBracketRi,
    tkColon,
    tkComma,

    tkComment,
    tkFace,
    tkVertex,

  WavefrontObjEventKind* = enum
    wfobjUnknown,
    wfobjEof,
    wfobjFace,
    wfobjVertex,
    wfobjVertexNormal,
    wfobjObject,

  WavefrontObjFaceEntry* = object
    vertexIndex*: uint
    textureIndex*: uint
    normalIndex*: uint

  WavefrontObjFace* = seq[WavefrontObjFaceEntry] # @TODO optimize, seq → array ?

  WavefrontObjVertex* = object
    x*: float64
    y*: float64
    z*: float64

  WavefrontObjObject* = ref object
    id*: string
    faces*: seq[WavefrontObjFace]

  WavefrontObj* = ref object
    objects*: seq[WavefrontObjObject]
    vertices*: seq[WavefrontObjVertex]
    vertexNormals*: seq[WavefrontObjVertex]

  WavefrontObjEvent* = object of RootObj
    case kind*: WavefrontObjEventKind
    of wfobjUnknown, wfobjObject:
      id*: string
    of wfobjEof: nil
    of wfobjFace:
      face*: WavefrontObjFace
    of wfobjVertex, wfobjVertexNormal:
      vertex*: WavefrontObjVertex

  WavefrontObjParser* = object of BaseLexer ## the parser object.
    a*: string
    tok*: TokKind
    # kind: JsonEventKind
    # err: JsonError
    # state: seq[ParserState]
    filename: string
    # rawStringLiterals: bool

# @XXX this is a bit of a hack, this can collide with a legit vertex, but the
# chance of that seems extremely unlikely
const emptyVertex* = WavefrontObjVertex(
  x: high(float64),
  y: high(float64),
  z: high(float64),
)

proc newWavefrontObj*(): WavefrontObj =
  new(result)
  result.vertices.add(emptyVertex)
  result.vertexNormals.add(emptyVertex)

proc open*(my: var WavefrontObjParser, input: Stream, filename: string) =
  lexbase.open(my, input)
  my.filename = filename
  # my.state = @[stateStart]
  # my.kind = jsonError
  # my.a = ""
  # my.rawStringLiterals = rawStringLiterals

proc close*(my: var WavefrontObjParser) {.inline.} =
  lexbase.close(my)

proc parseEscapedUTF16*(buf: cstring, pos: var int): int =
  result = 0
  #UTF-16 escape is always 4 bytes.
  for _ in 0..3:
    # if char in '0' .. '9', 'a' .. 'f', 'A' .. 'F'
    if handleHexChar(buf[pos], result):
      inc(pos)
    else:
      return -1

proc skip(my: var WavefrontObjParser) =
  var pos = my.bufpos
  while true:
    case my.buf[pos]
    of '/':
      if my.buf[pos+1] == '/':
        # skip line comment:
        inc(pos, 2)
        while true:
          case my.buf[pos]
          of '\0':
            break
          of '\c':
            pos = lexbase.handleCR(my, pos)
            break
          of '\L':
            pos = lexbase.handleLF(my, pos)
            break
          else:
            inc(pos)
      elif my.buf[pos+1] == '*':
        # skip long comment:
        inc(pos, 2)
        while true:
          case my.buf[pos]
          of '\0':
            raise newException(Exception, "errEOC_Expected")
            break
          of '\c':
            pos = lexbase.handleCR(my, pos)
          of '\L':
            pos = lexbase.handleLF(my, pos)
          of '*':
            inc(pos)
            if my.buf[pos] == '/':
              inc(pos)
              break
          else:
            inc(pos)
      else:
        break
    of ' ', '\t':
      inc(pos)
    of '\c':
      pos = lexbase.handleCR(my, pos)
    of '\L':
      pos = lexbase.handleLF(my, pos)
    else:
      break
  my.bufpos = pos

proc skipLine(my: var WavefrontObjParser) =
  var pos = my.bufpos
  var hitLine = false
  while true:
    case my.buf[pos]
    of '\c':
      pos = lexbase.handleCR(my, pos)
      hitLine = true
    of '\L':
      pos = lexbase.handleLF(my, pos)
      hitLine = true
    else:
      if hitLine:
        break
      inc(pos)

  my.bufpos = pos

proc parseNumber(my: var WavefrontObjParser) =
  var pos = my.bufpos
  if my.buf[pos] == '-':
    add(my.a, '-')
    inc(pos)
  if my.buf[pos] == '.':
    add(my.a, "0.")
    inc(pos)
  else:
    while my.buf[pos] in Digits:
      add(my.a, my.buf[pos])
      inc(pos)
    if my.buf[pos] == '.':
      add(my.a, '.')
      inc(pos)
  # digits after the dot:
  while my.buf[pos] in Digits:
    add(my.a, my.buf[pos])
    inc(pos)
  if my.buf[pos] in {'E', 'e'}:
    add(my.a, my.buf[pos])
    inc(pos)
    if my.buf[pos] in {'+', '-'}:
      add(my.a, my.buf[pos])
      inc(pos)
    while my.buf[pos] in Digits:
      add(my.a, my.buf[pos])
      inc(pos)
  my.bufpos = pos

proc parseString(my: var WavefrontObjParser): TokKind =
  result = tkString
  var pos = my.bufpos + 1
  # if my.rawStringLiterals:
  #   add(my.a, '"')
  while true:
    case my.buf[pos]
    of '\0':
      raise newException(Exception, "errQuoteExpected")
      # result = tkError
      break
    of '"':
      # if my.rawStringLiterals:
      #   add(my.a, '"')
      inc(pos)
      break
    of '\\':
      # if my.rawStringLiterals:
      #   add(my.a, '\\')
      case my.buf[pos+1]
      of '\\', '"', '\'', '/':
        add(my.a, my.buf[pos+1])
        inc(pos, 2)
      of 'b':
        add(my.a, '\b')
        inc(pos, 2)
      of 'f':
        add(my.a, '\f')
        inc(pos, 2)
      of 'n':
        add(my.a, '\L')
        inc(pos, 2)
      of 'r':
        add(my.a, '\C')
        inc(pos, 2)
      of 't':
        add(my.a, '\t')
        inc(pos, 2)
      of 'v':
        add(my.a, '\v')
        inc(pos, 2)
      of 'u':
        # if my.rawStringLiterals:
        #   add(my.a, 'u')
        inc(pos, 2)
        var pos2 = pos
        var r = parseEscapedUTF16(my.buf, pos)
        if r < 0:
          raise newException(Exception, "errInvalidToken")
          break
        # Deal with surrogates
        if (r and 0xfc00) == 0xd800:
          if my.buf[pos] != '\\' or my.buf[pos+1] != 'u':
            raise newException(Exception, "errInvalidToken")
            break
          inc(pos, 2)
          var s = parseEscapedUTF16(my.buf, pos)
          if (s and 0xfc00) == 0xdc00 and s > 0:
            r = 0x10000 + (((r - 0xd800) shl 10) or (s - 0xdc00))
          else:
            raise newException(Exception, "errInvalidToken")
            break
        # if my.rawStringLiterals:
        #   let length = pos - pos2
        #   for i in 1 .. length:
        #     if my.buf[pos2] in {'0'..'9', 'A'..'F', 'a'..'f'}:
        #       add(my.a, my.buf[pos2])
        #       inc pos2
        #     else:
        #       break
        else:
          add(my.a, toUTF8(Rune(r)))
      else:
        # don't bother with the error
        add(my.a, my.buf[pos])
        inc(pos)
    of '\c':
      pos = lexbase.handleCR(my, pos)
      add(my.a, '\c')
    of '\L':
      pos = lexbase.handleLF(my, pos)
      add(my.a, '\L')
    else:
      add(my.a, my.buf[pos])
      inc(pos)
  my.bufpos = pos # store back

proc parseName(my: var WavefrontObjParser) =
  var pos = my.bufpos
  if my.buf[pos] in IdentStartChars:
    while my.buf[pos] in IdentChars:
      add(my.a, my.buf[pos])
      inc(pos)
  my.bufpos = pos

proc parseWord(my: var WavefrontObjParser) =
  setLen(my.a, 0)
  var pos = my.bufpos
  if my.buf[pos] in WordChars:
    while my.buf[pos] in WordChars:
      add(my.a, my.buf[pos])
      inc(pos)
  my.bufpos = pos

# proc parseFloat64(my: var WavefrontObjParser): float64 =
#   discard

proc parseVertex(my: var WavefrontObjParser, kind = wfobjVertex): WavefrontObjEvent =
  my.skip()

  template parseFloat(res: var float64) =
    my.parseWord()
    assert parseBiggestFloat(my.a, res) != 0
    my.skip()

  var x: float64
  var y: float64
  var z: float64

  parseFloat(x)
  parseFloat(y)
  parseFloat(z)

  case kind
  of wfobjVertex, wfobjVertexNormal:
    return WavefrontObjEvent(kind: kind, vertex: WavefrontObjVertex(x: x, y: y, z: z))
  else:
    raise newException(Exception, "unknown case")


proc parseFaceEntry(my: var WavefrontObjParser): WavefrontObjFaceEntry =
  setLen(my.a, 0)
  var pos = my.bufpos
  var slashCount = 0

  result = WavefrontObjFaceEntry()

  template assignVal =
    # echo my.a
    var res: uint
    # some indicies (like textureIndex) can be missing (``) which will will make
    # the call below return 0, which is fine as legit indexes start at 1 anyway
    discard parseUInt(my.a, res)
    setLen(my.a, 0)

    case slashCount
    of 0:
      result.vertexIndex = res
    of 1:
      result.textureIndex = res
    of 2:
      result.normalIndex = res
    else: raise newException(Exception, "got more than 3 parts")

  while true:
    case my.buf[pos]
    of '/':
      assignVal()
      inc(slashCount)
      inc(pos)
    of '0'..'9':
      add(my.a, my.buf[pos])
      inc(pos)
    else:
      break
  my.bufpos = pos

  assignVal()

  # if my.buf[pos] in FaceEntrychars:
  #   while my.buf[pos] in FaceEntrychars:
  #     add(my.a, my.buf[pos])
  #     inc(pos)

  # return WavefrontObjFaceEntry()

proc parseFace(my: var WavefrontObjParser): WavefrontObjEvent =
  # template parseFaceEntry(res: var float64) =
  #   my.parseWord()
  #   assert parseBiggestFloat(my.a, res) != 0
  #   my.skip()


  # var x: float64
  # var y: float64
  # var z: float64

  # parseFloat(x)
  # parseFloat(y)
  # parseFloat(z)

  result = WavefrontObjEvent(
    kind: wfobjFace,
    face: newSeq[WavefrontObjFaceEntry](),
  )

  var pos = my.bufpos
  while true:
    case my.buf[pos]
    of ' ', '\t':
      inc(pos)
    of '\c':
      pos = lexbase.handleCR(my, pos)
      break
    of '\L':
      pos = lexbase.handleLF(my, pos)
      break
    else:
      # parse int/tuple @TODO unroll / get rid of the my.bufpos assignments
      my.bufpos = pos
      result.face.add(my.parseFaceEntry())
      pos = my.bufpos
  my.bufpos = pos

proc next*(my: var WavefrontObjParser): WavefrontObjEvent =
  # var tk = getTok(my)
  # echo repr tk
  my.skip()
  case my.buf[my.bufpos]
  # of '-', '.', '0'..'9':
  #   parseNumber(my)
  #   if {'.', 'e', 'E'} in my.a:
  #     result = tkFloat
  #   else:
  #     result = tkInt
  of '#':
    my.skipLine()
    return next(my)
  of lexbase.EndOfFile:
    return WavefrontObjEvent(kind: wfobjEof)
  else:
    parseWord(my)
    let op = my.a
    case op
    of "f":
      inc(my.bufpos)
      # return "face!"
      # return WavefrontObjEvent(kind: wfobjFace)
      return my.parseFace()
    of "v":
      return my.parseVertex()
    of "vn":
      return my.parseVertex(wfobjVertexNormal)
    of "o":
      my.skip()
      my.parseWord()
      var id = my.a
      return WavefrontObjEvent(kind: wfobjObject, id: id)
    else:
      var id = my.a
      return WavefrontObjEvent(kind: wfobjUnknown, id: id)

iterator parseWavefrontObj*(s: Stream, filename = ""): WavefrontObjEvent =
  var parser: WavefrontObjParser
  try:
    parser.open(s, filename)
    defer: parser.close()

    while true:
      var e = parser.next()
      case e.kind
      of wfobjEof: break
      else:
        yield e
  except:
    writeLine(stderr, fmt"↓ parser: {parser}")
    flushFile(stderr)
    raise
