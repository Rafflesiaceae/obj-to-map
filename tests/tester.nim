import os, strformat, sequtils, sugar, strutils, osproc

proc main =
  os.setCurrentDir(os.getAppDir())


  var binExt = ""
  when defined windows: binExt = ".exe"

  let bin = absolutePath(fmt"..{os.DirSep}obj_to_map{binExt}")
  let objs = toSeq(walkDir(".")).mapIt(it.path).filter(x => x.endsWith(".obj"))

  echo fmt"Bin: {bin}"
  for obj in objs:
    let map = obj.replace(".obj", ".map")

    echo fmt"Converting {obj} to {map}"
    flushFile(stdout)
    discard execCmd(fmt"{bin} {obj} {map}")
    flushFile(stdout)

when isMainModule:
  main()
