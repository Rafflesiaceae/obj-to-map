import streams, strformat
import ./obj_parser.nim
import glm
import sugar

type
  MapPlane* = array[3, WavefrontObjVertex]
  MapBrush* = object
    id*: string
    planes*: seq[MapPlane]

converter toVec3(v: WavefrontObjVertex): Vec3[float64] = vec3(v.x, v.y, v.z)
converter toWavefrontObjVertex(v: Vec3[float64]): WavefrontObjVertex = WavefrontObjVertex(x: v[0], y: v[1], z: v[2])

proc wavefrontObjToMapBrushes*(
    wobj: WavefrontObj,
    sizeFactor: float = 100.0): seq[MapBrush] =

  return collect:
    let vertices = wobj.vertices
    let vertexNormals = wobj.vertexNormals

    for obj in wobj.objects:
      let faces = obj.faces
      let planes = collect:
        for face in faces:
          assert face.len == 3

          # @TODO :/
          let v1 = vertices[face[1].vertexIndex]
          let v2 = vertices[face[0].vertexIndex]
          let v3 = vertices[face[2].vertexIndex]

          let vn1 = vertexNormals[face[1].normalIndex]
          let vn2 = vertexNormals[face[0].normalIndex]
          let vn3 = vertexNormals[face[2].normalIndex]

          # var v1x = (v1.x * sizeFactor)
          # var v1y = (v1.y * sizeFactor)
          # var v1z = (v1.z * sizeFactor)
          # var v2x = (v2.x * sizeFactor)
          # var v2y = (v2.y * sizeFactor)
          # var v2z = (v2.z * sizeFactor)
          # var v3x = (v3.x * sizeFactor)
          # var v3y = (v3.y * sizeFactor)
          # var v3z = (v3.z * sizeFactor)

          # block checkWeirdInvariants:
          proc length(v: Vec3[float64]): float64 {.inline.} =
            return sqrt((v[0] * v[0]) + (v[1] * v[1]) + (v[2] * v[2]))

          proc calcNorm(p1,p2,p3: Vec3[float64]): Vec3[float64] {.inline.} =
            let c = cross( (p3-p1), (p2-p1) )
            # let length = sqrt((c[0] * c[0]) + (c[1] * c[1]) + (c[2] * c[2]))
            let clen = c.length()
            let norm = c / clen
            return norm

          var
            # p1 = v1.toVec3 * sizeFactor
            # p2 = v2.toVec3 * sizeFactor
            # p3 = v3.toVec3 * sizeFactor
            p1 = v1.toVec3
            p2 = v2.toVec3
            p3 = v3.toVec3
            # p1 = vec3(v1x, v1y, v1z)
            # p2 = vec3(v2x, v2y, v2z)
            # p3 = vec3(v3x, v3y, v3z)
            # c = cross( (p3-p1), (p2-p1) )

            # length = sqrt((c[0] * c[0]) + (c[1] * c[1]) + (c[2] * c[2]))
            # norm = c / length

          p1 = p1 * sizeFactor
          p2 = p2 * sizeFactor
          p3 = p3 * sizeFactor

          let calcedNorm = calcNorm(p1, p2, p3)
          let objVertexNorm = vn1.toVec3

          # if ((objVertexNorm-calcedNorm).len > 0.000001) != calcedNorm:
          let difflen = (calcedNorm-objVertexNorm).length()
          if (difflen > 0.01):
            echo ""
            echo "MISMATCHING NORMS"
            echo "DIFL: " & $difflen
            echo "VEC:  " & $p1
            echo "CALC: " & $calcedNorm
            # echo "CALC: " & $(calcNorm(p2, p1, p3))
            # echo "CALC: " & $(calcNorm(p2, p3, p1))
            echo "GIVN: " & $objVertexNorm

          [
            p1.toWavefrontObjVertex,
            p2.toWavefrontObjVertex,
            p3.toWavefrontObjVertex,
          ]

      MapBrush(
        id: obj.id,
        planes: planes,
      )

proc writeMap*(brushes: seq[MapBrush], outf: string, sizeFactor: float = 100.0) =
  #[ to like this ↓
  // brush 0
  {
  ( 112 120 120 ) ( 112 -88 120 ) ( -168 120 120 ) radiant/notex 16 0 0 0.5 0.5 0 0 0
  ( 120 120 64 ) ( -160 120 64 ) ( 120 120 -64 ) radiant/notex 0 0 0 0.5 0.5 0 0 0
  ( 120 120 64 ) ( 120 120 -64 ) ( 120 -88 64 ) radiant/notex -0 0 0 0.5 0.5 0 0 0
  ( -160 -88 -64 ) ( -160 -88 64 ) ( 120 -88 -64 ) radiant/notex 0 0 0 0.5 0.5 0 0 0
  ( -160 -88 -64 ) ( -160 120 -64 ) ( -160 -88 64 ) radiant/notex -0 0 0 0.5 0.5 0 0 0
  ( -168 120 112 ) ( 112 -88 112 ) ( 112 120 112 ) sky/indigosky 0 0 0 0.5 0.5 0 0 0
  }
  ]#

  var i = 0

  proc outputBrush(strm: Stream, brush: MapBrush) =
    strm.write(&"// brush {i} - {brush.id}\n{{\n")
    for plane in brush.planes:
      let v1x = (plane[0].x).int
      let v1y = (plane[0].y).int
      let v1z = (plane[0].z).int
      let v2x = (plane[1].x).int
      let v2y = (plane[1].y).int
      let v2z = (plane[1].z).int
      let v3x = (plane[2].x).int
      let v3y = (plane[2].y).int
      let v3z = (plane[2].z).int



      # e.g.: "( -168 120 112 ) ( 112 -88 112 ) ( 112 120 112 ) sky/indigosky 0 0 0 0.5 0.5 0 0 0"
      strm.writeLine(&"( {v1x} {v1y} {v1z} ) ( {v2x} {v2y} {v2z} ) ( {v3x} {v3y} {v3z} ) sky/indigosky 0 0 0 0.5 0.5 0 0 0")
    strm.write("}\n")
    inc(i)

  var strm = newFileStream(outf, fmWrite)
  defer: strm.close()

  # write stanza
  strm.write("""// entity 0
{
"classname" "worldspawn"
""")

  for brush in brushes:
    outputBrush(strm, brush)

  strm.write("}\n")

