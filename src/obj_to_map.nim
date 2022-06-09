import streams
import os
import strutils, strformat
import re
import sugar
import sequtils

import ./obj_parser.nim
import ./obj_dumper.nim
import ./map_output.nim

type
  Command* {.pure.} = enum
    none = "none"
    convert = "convert"
    filter = "filter"
    listObjects = "list-objects"

var
  currentCmd: Command = none

proc usage(errormsg="", retcode=0) =
  const usage = """
  """

  var rRetcode = retcode
  var rErrormsg = errormsg
  if errormsg != "":
    rRetcode=1
    rErrormsg="ERROR: "&errormsg&"\n\n"

  ## prints usage message
  var specificUsageMsg: string

  case currentCmd
  of Command.none:
    specificUsageMsg = """Usage: obj-to-map [globalopts] COMMAND [cmdopts] ...

Commands:
  convert      from to               Convert .obj to .map (idtech3)
  filter       from to <regexps>...  Filter objects from an .obj
  list-objects path                  List all objects from an .obj"""
  of Command.convert:
    specificUsageMsg = """Usage: obj-to-map [globalopts] convert <from> <to>

Parameters:
  from    Input path to an .obj file
  to      Output path to a .map file"""
  of Command.filter:
    specificUsageMsg = """Usage: obj-to-map [globalopts] filter <from> <to> <regexps>...

Parameters:
  from          Input path to an .obj file
  to            Output path to an .obj file
  rules...      List of filter rules (regexps), preceded either by + for inclusion or ! for exclusion, ** is automatically transformed to .*"""
  of Command.listObjects:
    specificUsageMsg = """Usage: obj-to-map [globalopts] list-objects <path>

Parameters:
  path          Input path to an .obj file"""

  # - - - -

  echo fmt"""{rErrormsg}{specificUsageMsg}

Global Options:
  -h, --help          Print this message
  -v, --version       Print version information"""

  quit(rRetcode)

proc loadWfObj*(inputf: string): WavefrontObj =
  var wfObj = newWavefrontObj()

  var obj: WavefrontObjObject

  proc newBrush(id: string) =
    obj = WavefrontObjObject()
    obj.id = id

    wfObj.objects.add(obj)

  block parseObj:
    for e in parseWavefrontObj(newFileStream(inputf), inputf):
      case e.kind
      of wfobjEof          : discard
      of wfobjUnknown      : discard
      of wfobjVertex       : wfObj.vertices.add(e.vertex)
      of wfobjVertexNormal : wfObj.vertexNormals.add(e.vertex)
      of wfobjFace         : obj.faces.add(e.face)
      of wfobjObject       : newBrush(e.id)

    return wfObj

proc convert(args: seq[string]) =
  if args.len != 2: usage()

  let inputf = args[0]
  let outputf = args[1]

  var wfObj = newWavefrontObj()

  var obj: WavefrontObjObject

  proc newBrush(id: string) =
    obj = WavefrontObjObject()
    obj.id = id

    wfObj.objects.add(obj)

  block parseObj:
    for e in parseWavefrontObj(newFileStream(inputf), inputf):
      case e.kind
      of wfobjEof          : discard
      of wfobjUnknown      : discard
      of wfobjVertex       : wfObj.vertices.add(e.vertex)
      of wfobjVertexNormal : wfObj.vertexNormals.add(e.vertex)
      of wfobjFace         : obj.faces.add(e.face)
      of wfobjObject       : newBrush(e.id)

  block writeMap:
    var mapBrushes = wavefrontObjToMapBrushes(wfObj)
    mapBrushes.writeMap(outputf)

proc filter(args: seq[string]) =
  if args.len < 3: usage()
  let fromPath = args[0]
  let toPath = args[1]

  var
    excludeRegexes: seq[Regex]
    includeRegexes: seq[Regex]

  for arg in args[2..^1]:
    let regex = re("^" & arg[1..^1].replace("**", ".*") & "$")
    let op = arg[0]
    case op
    of '+':
      includeRegexes.add(regex)
    of '!':
      excludeRegexes.add(regex)
    else:
      # raise newException(Exception, )
      usage(&"unsupported op: {op}\n  allowed ops: + (inclusion), ! (exclusion)")

  # if we only have includes but no excludes, assume we exclude everything
  # (effectively allowlist)
  if includeRegexes.len > 0 and excludeRegexes.len == 0:
    excludeRegexes.add(re(".*"))

  let wfObj = loadWfObj(fromPath)

  # mark for deletion
  var markedForDeletion: seq[int]
  for i, obj in wfObj.objects:
    if (
      any(excludeRegexes, (r: Regex) => re.match(obj.id, r)) and not
      any(includeRegexes, (r: Regex) => re.match(obj.id, r))
    ):
      markedForDeletion.add(i)

  # recollect
  wfObj.objects = collect:
    for i, obj in wfObj.objects:
      if i notin markedForDeletion:
        obj

  # print matched objects
  for i, obj in wfObj.objects:
    echo(obj.id)

  # dump obj
  dumpWavefrontObj(wfObj, toPath)

proc listObjects(args: seq[string]) =
  if args.len != 1: usage()
  let fromPath = args[0]

  let wfObj = loadWfObj(fromPath)

  for i, obj in wfObj.objects:
    echo(obj.id)
    discard

proc main =
  let args = commandLineParams()

  if args.len < 1: usage()

  var remainingArgs: seq[string] = @[]
  var arg = ""
  for i in 0..<args.len:
    arg = args[i]

    # parse command options
    case currentCmd
    of Command.none:
      discard
    of Command.convert:
      discard
    of Command.filter:
      discard
    of Command.listObjects:
      discard

    # parse global options
    case arg
    of "--help", "-h":
      usage()
    of "--version", "-v":
      echo("0.0.1")
      quit(0)
    of "--":
      for j in i+1..<args.len:
        remainingArgs.add args[j]
      break
    # check if we know the option
    elif arg.startsWith("--") or ( arg != "-" and arg.startsWith("-") ):
      usage(fmt"unknown option: {arg}")
    # the first non-option gets assigned as the command
    elif currentCmd == Command.none:
      # assign a command
      let argCmd = parseEnum[Command](arg)
      case argCmd
      of Command.none:
        usage("none command not callable")
      else:
        currentCmd = argCmd
    else:
      remainingArgs.add arg

  # run command
  case currentCmd
  of Command.none:
    usage()
  of Command.convert:
    convert(remainingArgs)
  of Command.filter:
    filter(remainingArgs)
  of Command.listObjects:
    listObjects(remainingArgs)

when isMainModule:
  main()
