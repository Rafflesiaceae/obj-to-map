import
  strutils, strformat, sugar

import ./obj_parser.nim

proc dumpWavefrontObj*(wfObj: WavefrontObj, path: string) =
  let f = open(path, fmWrite)
  defer: f.close()

  for v in wfObj.vertices[1..^1]:
    f.writeLine(fmt"v {v.x} {v.y} {v.z}")

  for vn in wfObj.vertexNormals[1..^1]:
    f.writeLine(fmt"vn {vn.x} {vn.y} {vn.z}")

  for o in wfObj.objects:
    f.writeLine(fmt"o {o.id}")
    for fa in o.faces:
      let liny = collect:
        for d in fa:
          join([d.vertexIndex, d.textureIndex, d.normalIndex], "/")
      let fStr = join(liny, " ")

      f.writeLine(fmt"f {fStr}")
