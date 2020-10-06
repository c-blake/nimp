import os, strutils
for e in listFiles("tests"):
  if e.endsWith(".nim"): exec "nim r " & e
