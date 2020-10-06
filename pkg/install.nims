import os, strutils   # shared .nims header
let vcRepos  = getEnv("NIMP", ".")                  # VC hierarchy root
let checkout = getEnv("NIMP_CO", "")                # local checkout|""
let scripts  = getEnv("NIMP_SR", vcRepos / "%")     # scripts
let binDir   = getEnv("NIMP_BIN", vcRepos / "bin")  # execs
let package  = getEnv("NIMP_PKG", "")               # current package

let clp = commandLineParams()     # compile command from args tail
proc findP*[T](s: openArray[T], pred: proc(x: T): bool): int =
  for i, x in s: (if pred(s[i]): return i) # XXX grow `sequtils.find` PR
let i = clp.findP(proc(x: string): bool = x.endsWith("install.nims"))
let nim = if i+1 < clp.len: clp[i+1 .. ^1] else: @["nim", "c"]

for e in ["nimp"]:
  exec nim.join(" ") & " -o:" & binDir/e & " " & e
