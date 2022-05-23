import streams
import os

import ./obj_parser.nim
import ./map_output.nim

proc main =
  let args = commandLineParams()

  assert args.len == 2
  let inputf = args[0]
  let outputf = args[1]

  var wfObj = WavefrontObj()

  var obj: WavefrontObjObject

  proc newBrush(id: string) =
    obj = WavefrontObjObject()
    obj.id = id

    wfObj.objects.add(obj)

  block parseObj:
    for e in parseWavefrontObj(newFileStream(inputf), inputf):
      case e.kind
      of wfobjEof: discard
      of wfobjUnknown: discard
      of wfobjVertex: wfObj.vertices.add(e.vertex)
      of wfobjVertexNormal: wfObj.vertexNormals.add(e.vertex)
      of wfobjFace: obj.faces.add(e.face)
      of wfobjObject: newBrush(e.id)

  block writeMap:
    var mapBrushes = wavefrontObjToMapBrushes(wfObj)
    mapBrushes.writeMap(outputf)

when isMainModule:
  main()
