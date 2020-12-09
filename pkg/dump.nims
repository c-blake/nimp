import strformat, strutils, tables, os
var name, url, description, license: string
proc getPkgDir(): string = getCurrentDir()
proc thisDir(): string = getPkgDir()
template before(action: untyped, body: untyped): untyped = discard
template after(action: untyped, body: untyped): untyped = discard
# Package
version     = "0.1.0"
author      = "Charles Blake"
description = "A package manager that delegates to package authors"
license     = "MIT/ISC"

# Dependencies
requires "nim >= 1.3.7"

let pc = paramCount()
if pc < 3: echo "Use: nim e dump.nims (n|r|u|d|l)*"; quit(1)
if   paramStr(pc).startsWith("n"): echo name
elif paramStr(pc).startsWith("v"): echo version
elif paramStr(pc).startsWith("r"): #Eg. `ndf` puts multiple in ""
  for d in requiresData: (for dd in d.split(","): echo dd.strip)
elif paramStr(pc).startsWith("d"): echo description
elif paramStr(pc).startsWith("l"): echo license
