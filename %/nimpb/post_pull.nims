import os, strutils
let clp = commandLineParams()
let vc_root = if clp.len == 0 or clp[^1].lastPathPart.endsWith(".nims"):
  getEnv("NIMP", "/u/cb/pkg/nim") else: clp[^1]
let cd = getCurrentDir()
let pd = vc_root & "/" & cd.lastPathPart
for e in listFiles("."):
  if e.endsWith(".patch"):
    exec "(cd " & pd & "; patch -p1 < " & cd & "/" & e & ")"
mvFile pd/"nimpb/json.nim", pd/"nimpb/json1.nim"
mvFile pd/"nimpb/compiler/generator.nim", pd/"nimpb/compiler/generator1.nim"
