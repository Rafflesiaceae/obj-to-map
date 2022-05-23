# Package
author      = "Rafflesiaceae"
backend     = "c"
bin         = @["obj_to_map"]
description = "Convert Wavefront .obj (consisting of only convex-hulls) to idtech3 .map"
license     = "GPL-2.0-or-later"
srcDir      = "src"
version     = "0.0.0"


# Dependencies
requires "nim == 1.6.4"
requires "https://github.com/stavenko/nim-glm.git#47d5f8681f3c462b37e37ebc5e7067fa5cba4d16"

# Tasks
before test:
  exec "nimble build"

task test, "Runs the test suite":
  exec "nim c -r tests/tester"
