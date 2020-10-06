import os, strutils
let clp = commandLineParams()
let vc_root = if clp.len == 0 or clp[^1].lastPathPart.endsWith(".nims"):
  getEnv("NIMP", "/u/cb/pkg/nim") else: clp[^1]

let pd = vc_root & "/" & getCurrentDir().lastPathPart

proc run(s: string): int = # gorgeEx cd's to dir of nims
  let (output, code) = gorgeEx("cd " & pd & "; " & s)
  echo output
  result = code

let (tag, xtag) = gorgeEx("cd " & pd & "; git describe --tags")
if xtag == 0 and tag.len > 2:
  if run("git checkout -b Nimp " & tag[0..^2]) == 0:
    if run("git branch -u origin/master") != 0:
      quit(run("git branch -u origin/devel"))
else:
  echo "No tagged version: output: ", tag.repr, " exitcode: ", xtag
