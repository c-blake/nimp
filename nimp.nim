import std/[os,osproc,json,strutils,tables,streams,parsecfg,httpclient,times]
when not declared(File): import std/syncio
if paramCount() < 1 or paramStr(1)[0] notin "gumdipU": echo """Usage:
  nimp g)et name|URI [nim c|cpp|.. opts]   clone&install name|URI & deps
  nimp u)p [baseDirName..]                 git pull listed|all repos
  nimp m)kpath                             make nim.cfg from repos
  nimp d)ump {n)ame|v)sn|r)eq|d)esc|l)ic}  print .nimble variables
  nimp i)nit [packageName]                 init a skeleton package
  nimp p)ub tag1 [tag2...]                 publish to github.com
$NIMP - root of VC hierarchy|CWD; Run dump & pub INSIDE a pkg dir."""; quit(1)
const official = "https://github.com/nim-lang/packages"
let vr  = if "NIMP".getEnv(getCurrentDir()) == ".": getCurrentDir()
          else: getEnv("NIMP", getCurrentDir()) # VC Repos
let sr  = "NIMP_SR".getEnv(vr/"%")              # scripts
let co  = "NIMP_CO".getEnv("")                  # local checkouts
let ucf = "NIMP_UCF".getEnv("UNSET") != "UNSET" # no auto-update nim.cfg
let bin = "NIMP_BIN".getEnv(vr/"bin")           # executables
putEnv("NIMP", vr)                              # propagate defaults to kids
putEnv("NIMP_SR", sr)
if co.len > 0: putEnv("NIMP_CO", co)
putEnv("NIMP_BIN", bin)
putEnv("PATH", bin & ":" & getEnv("PATH", ""))
let nimpDirs = """import os, strutils   # shared .nims header
let vcRepos  = getEnv("NIMP", ".")                  # VC hierarchy root
let checkout = getEnv("NIMP_CO", "")                # local checkout|""
let scripts  = getEnv("NIMP_SR", vcRepos / "%")     # scripts
let binDir   = getEnv("NIMP_BIN", vcRepos / "bin")  # execs
let package  = getEnv("NIMP_PKG", "")               # current package
""" # boilerplate NimScript setup for default progs

proc n(x: string): string = x.toLower.multiReplace(("_", ""))

proc run(cmd, msg: string, quiet=false) =       # command harness
  if not quiet: echo cmd                        # verb run cmd|maybe quit
  if execCmd(cmd) != 0:
    if msg.startsWith("warning: "): echo msg
    else: quit(msg, 1)

template cd(new: string, body: untyped) =       # shell (cd new; body)
  let old = getCurrentDir(); setCurrentDir(new); body; setCurrentDir(old)

proc loadFromClone(): Table[string, string] =   # pkgnm->URI
  var alt: Table[string, string]
  let repo = vr/"packages"
  if not dirExists(repo):
    run("git clone " & official & " " & repo, "cannot clone packages")
  for p in parseJson(readFile(repo/"packages.json")):
    try: result[($p["name"]).n[1..^2]] = ($p["url"])[1..^2]
    except:                                     # [1..^2] slice kills '"'s
      try: alt[($p["name"]).n[1..^2]] = ($p["alias"]).n[1..^2]
      except: stderr.write "problem with: ", p, "\n"
  for k, v in alt: result[k] = result[v]        # apply aliases
let pkgs = loadFromClone()                      # decl global early
discard existsOrCreateDir(sr)

proc nimblePath(): string =
  for k, path in ".".walkDir(true):
    if k == pcFile and path.endsWith(".nimble"): return path

proc multiSplitStrip(s: string): seq[string] =
  result = split(s, {'\r', '\n', ','})
  for i in 0 ..< result.len: result[i] = result[i].strip
  for i in countdown(result.len - 1, 0):        # empty result..
    if result[i].len < 1: result.del(i)         # => empty loop.

proc dumpIni(path: string) =
  if paramCount() != 2: echo "Use: nimp dump [nvrdl]*"; quit(1)
  var fs = newFileStream(path, fmRead)
  if fs != nil:
    var p: CfgParser
    open(p, fs, path)
    var section = ""
    while true:
      var e = p.next
      case e.kind
      of cfgEof: break
      of cfgError, cfgOption: raise newException(ValueError, "")
      of cfgSectionStart:
        if e.key.n notin ["deps", "dependencies", "package"]:
          raise newException(ValueError, "")
        else: section = e.key.n
      of cfgKeyValuePair:
        if section == "": raise newException(ValueError, "")
        if   paramStr(2).startsWith("n") and e.key.n == "name": echo e.value
        elif paramStr(2).startsWith("v") and e.key.n == "version": echo e.value
        elif paramStr(2).startsWith("r") and e.key.n == "requires":
          for v in e.value.multiSplitStrip: echo v
        elif paramStr(2).startsWith("d") and e.key.n == "description": echo e.value
        elif paramStr(2).startsWith("l") and e.key.n == "license": echo e.value
    p.close # also closes fs

proc dumpScript(path: string, prog = "pkg"/"dump.nims") =
  const s = "--skipUserCfg:on --skipParentCfg:on --skipProjCfg:on" &
            " --hints:off -w:off --path=. --path=src"
  if not prog.fileExists:                       # Allow pkg author override
    discard existsOrCreateDir("pkg")
    let dotNimble = path.readFile
    writeFile(prog, """import strformat, strutils, tables, os
var name, url, description, license: string
proc getPkgDir(): string = getCurrentDir()
proc thisDir(): string = getPkgDir()
template before(action: untyped, body: untyped): untyped = discard
template after(action: untyped, body: untyped): untyped = discard
""" & dotNimble & "\n" & """
let pc = paramCount()
if pc < 3: echo "Use: nim e dump.nims (n|r|u|d|l)*"; quit(1)
if   paramStr(pc).startsWith("n"): echo name
elif paramStr(pc).startsWith("v"): echo version
elif paramStr(pc).startsWith("r"): #Eg. `ndf` puts multiple in ""
  for d in requiresData: (for dd in d.split(","): echo dd.strip)
elif paramStr(pc).startsWith("d"): echo description
elif paramStr(pc).startsWith("l"): echo license""" & "\n")
  run("nim e " & s & " " & prog & " " & paramStr(2), "bad " & prog, true)

proc maybeRun(pknm, dir, name: string; args: seq[string] = @[]) =
  if not dir.dirExists: return
  let args = if args.len > 0: " " & args.join(" ") else: ""
  cd dir: # foo.nims is *~nim.cfg* for foo.nim => try .nim first
    putEnv("NIMP_PKG", pknm)
    if fileExists(name & ".nim"):
      run("nim r " & name & ".nim" & args, name & ".nim failed")
    elif fileExists(name & ".nims"):            # run nims if no nim
      run("nim e " & name & ".nims" & args, name & ".nims failed")

proc maybeWrite(path, contents: string) =       # non clobbering writeFile
  if not path.fileExists: writeFile(path, contents)

iterator subdirs(root: string): string =        # specific | all pkg
  if paramCount() > 1:
    for i in 2..paramCount(): yield paramStr(i)
  else:
    for k, nm in vr.walkDir(true):
      if k == pcDir and dirExists(vr/nm/".git"): yield nm

proc hasNim(dir: string): bool =                # dir has a Nim module
  for nm in dir.walkDirRec(relative = true):
    if nm.endsWith(".nim"): return true

proc padd(p: var string, d = "", pfx = "path=\"", sfx = "\"\n") =
  if d.dirExists and d.hasNim: p.add pfx & d & sfx

proc makePath(): string =                       # write to $NIMP_CO/nim.cfg
  result.add "path=\"" & vr & "\"\n"            # pkg.qual. debate:
  for k, pknm in vr.walkDir(true):              # deep/unqualified?
    result.padd(vr/pknm)                        # only 1 .nim ck? Etc.
    result.padd(vr/pknm/"src")
    result.padd(vr/pknm/pknm)
    result.padd(vr/pknm/pknm/"pkg")

proc exes(dotNimble: string): seq[string] =
  const delim = Whitespace + {'"', ',', '@', '=', '[', ']'}
  for ln in dotNimble.splitLines:               # only neverwinter.nim..
    if ln.startsWith("bin "):                   # ..needs more than this!
      for word in ln[4..^1].split(delim):       # only for back/cross-
        if word.len > 0: result.add word        # ..nimble compatiblity!
                                               
proc postCheckout(pknm: string) =               # duktape(litestore) breaks
  maybeRun(pknm, sr/pknm, "post_checkout")      #..and libgit2(but unused)
  if "src".dirExists and not pknm.dirExists:    # cross/back compat with..
    when defined(windows):                      # ..VERY BAD nimble src/ idea
      run("mklink /d " & pknm & " src", "warning: src/ incompatible")
    else: # Araq hates symlink. Could also cp, but src/ ditch best of all
      run("ln -s src " & pknm, "warning: src/ incompatible")

proc mkInstall(pknm: string, exes: openArray[string]) =
  maybeWrite("pkg"/"install.nims", nimpDirs & "\n" & """
let clp = commandLineParams()     # compile command from args tail
proc findP*[T](s: openArray[T], pred: proc(x: T): bool): int =
  for i, x in s: (if pred(s[i]): return i) # XXX grow `sequtils.findP` PR
let i = clp.findP(proc(x: string): bool = x.endsWith("install.nims"))
let nim = if i+1 < clp.len: clp[i+1 .. ^1] else: @["nim", "c"]

for e in """ & $exes & """:
  let t = "src" / (e & ".nim") # source
  let s = if t.fileExists: t else: e & ".nim"
  let x = "-o:" & binDir/e.lastPathPart & " " & s
  exec nim.join(" ") & " " & x""" & '\n')

proc pkGet(pk: string, nim: seq[string]) =      # Unpublished => pknm=basenm
  const no = ["no", "nim", "nimrod"]            # 29 pks still use "nimrod"
  let pknm = if "://" in pk: pk.lastPathPart.n else: pk.n
  let repo = if "://" in pk: pk else: pkgs[pk.n]
  if not existsOrCreateDir(vr/pknm):
    var dir = vr/pknm
    cd dir: # Hg? ALL pkgs were bitbucket & are gone
      run("git clone --recursive " & repo & " .", "clone failure")
#   if co.len > 0: # XXX above could do --no-checkout
#     dir = co/pknm # XXX below could get any specific vsn
#     run("git worktree add " & dir, "cannot add worktree")
      postCheckout(pknm) # hack up pkg to be bkwd compat.
#   cd dir:
      for ln in execProcess("nimp dump req").splitLines:
        let pv = ln.n.split(Whitespace + {'#','<','>','='})
        if pv[0] notin no and pv[0].len > 0: pkGet(pv[0], nim)
      maybeRun(pknm, sr/pknm, "pre_install")
      let path = nimblePath()
      let nb = if path.len > 0: path.readFile else: ""
      if "\nbin " in nb or "\nbin=" in nb :     # ~15% pkgs have exes
        discard existsOrCreateDir("pkg")
        let pfx = vr/pknm/"pkg"/"install.nim"
        if not pfx.fileExists and not fileExists(pfx & "s"):
          if nb.exes.len>0: mkInstall(pknm, nb.exes) # long-term -> pkgAuth
      writeFile(vr/"nim.cfg", makePath())       # deps update
      maybeRun(pknm, vr/pknm, "pkg"/"install", nim)
  else: echo vr/pknm," exists.  Done.  You may want `nimp update`."

if paramStr(1).startsWith("g"):                 # GET REPOS INSTALLING ALL DEPS
  pkGet(paramStr(2), commandLineParams()[2..^1])
elif paramStr(1).startsWith("U"):               # UPDATE 1 REPO VIA git pull
  if paramCount() != 2: quit(1)                 # This is really just for non-||
  let pknm = paramStr(2)                        # update of the `packages` pkg.
  cd vr/pknm:
    maybeRun(pknm, sr/pknm, "pre_pull")
    if execCmd("git pull") != 0: quit("cannot pull", 1)
    maybeRun(pknm, sr/pknm, "post_pull")
elif paramStr(1).startsWith("u"):               # UPDATE listed|all REPOS
  const opts = {poUsePath, poStdErrToStdOut}
  var nms, cmds: seq[string]                    # Parallel for network..
  var doPkgs = false                            # ..more than CPU.
  for pknm in subdirs(vr):
    if pknm == "packages": doPkgs = true
    else: nms.add pknm; cmds.add "nimp U " & pknm
  template a() {.dirty.} =
    let (lines, exCode) = p.readLines
    if lines.len > 1 or exCode != 0:
      echo "\e[7m", nms[i], ":(exCode=", exCode, ")\e[m"
      for ln in lines: echo "  ", ln
    p.close
  if doPkgs: # no JSON parse during => no pull packages in||
    var nms = ["packages"]; var cmds = ["nimp U packages"]
    discard execProcesses(cmds, opts, afterRunEvent =
      proc(i: int, p: Process) = a)
  let x = execProcesses(cmds, opts, n = 32, afterRunEvent =
    proc(i: int, p: Process) = a)
  if ucf: writeFile vr/"nim.cfg", makePath()
  quit x
elif paramStr(1).startsWith("m"):               # MAKE PATH IN nim.cfg
  writeFile(vr/"nim.cfg", makePath())
elif paramStr(1).startsWith("d"):               # DUMP (not so end-user useful)
  let path = nimblePath()
  if path.len > 0:
    try: dumpIni(path)                          # Archaic ini file fmt
    except: dumpScript(path)                    # New style NimScript fmt
  else: stderr.write "No .nimble in CWD\n"; quit(1)
elif paramStr(1).startsWith("i"):               # INIT A .nimble FILE
  var pknm = getCurrentDir().lastPathPart.n
  if paramCount() >= 2:
    discard existsOrCreateDir(paramStr(2)); setCurrentDir(paramStr(2))
    pknm = getCurrentDir().lastPathPart.n
  if nimblePath().len == 0:
    writeFile(pknm & ".nimble", """# Package
version     = "0.1.0"
#author      = "Me"
#description = "WhatIam"
#license     = "MIT" # Apache-2.0 GPL-3.0 ISC BSD-3-Clause

# Dependencies
requires "nim >= """ & NimVersion & "\"\n")
  discard existsOrCreateDir("pkg")
  discard existsOrCreateDir("tests")
  maybeWrite("pkg"/"test.nims", """import os, strutils
for e in listFiles("tests"):
  if e.endsWith(".nim"): exec "nim r " & e""" & '\n')
  mkInstall(pknm, [pknm])
  maybeWrite("pkg"/"uninstall.nims", nimpDirs & "\n" &
             "rmFile binDir/\"" & pknm & "\"\n" &
             "rmDir vcRepos/\"" & pknm & "\"\n")
  maybeWrite(pknm & ".nim", "# New nim package\n")
elif paramStr(1).startsWith("p"):               # PUBLISH A PACKAGE
  let nimble = nimblePath().lastPathPart
  if nimble.len < 8: quit("Need .nimble file in CWD", 1)
  let pknm = nimble[0..^(".nimble".len+1)]
  let url = execProcess("git ls-remote --get-url").strip
  if url.startsWith("ssh://"): quit("Need https URL", 1)
  let tags = if paramCount() > 1: commandLineParams()[1..^1] else: @[]
  if tags.len < 1: quit("no tags specified on command line", 1)
  let desc = execProcess("nimp dump desc").strip
  if desc.len < 9: quit("description too short", 1)
  let license = execProcess("nimp dump license").strip
  if license.len < 1: quit("no license", 1)
  const ghc = "github.com/"; const gh = "https://" & ghc
  const api = "https://api." & ghc
  const pk = "packages"; const nlp = "nim-lang/" & pk
  let token = getEnv("NIMP_AUTH", readFile(vr/".auth")) # get auth token | die
  if token.len == 0: quit("Get token@ " & gh & "settings/tokens/new\n" &
                          "Set NIMP_AUTH=That & try again", 1)
  let prx = getEnv("http_proxy", getEnv("https_proxy",
            getEnv("HTTP_PROXY", getEnv("HTTPS_PROXY", ""))))
  let proxy = if prx.len > 0: newProxy(prx) else: nil
  let web = newHttpClient(proxy = proxy, headers = newHttpHeaders({
    "Authorization": "token $1" % token, "Accept": "*/*",
    "Content-Type": "application/x-www-form-urlencoded"}))
  let user = web.getContent(api & "user").parseJson{"login"}.getStr
  let auth = "https://" & token & "@" & ghc & user & "/" & pk
  proc haveFork(): bool =
    try:
      let j = web.getContent(api & "repos/" & user & "/" & pk).parseJson
      if j{"fork"}.getBool(): result = j{"parent"}{"full_name"}.getStr == nlp
    except JsonParsingError, IOError: discard
  let ext = getTime().utc.format("-MMdd-HHmm")  # day of year+min of day
  var dir = getTempDir() / (user & "-" & pk & ext)
  createDir(dir); setCurrentDir(dir)            # rest runs in `dir`
  run("git init", "cannot git init")
  if not haveFork():
    try: echo "FORK.."; discard web.postContent(api & "repos/" & nlp & "/forks")
    except: quit("could not fork on github", 1)
    echo "10s wait"; sleep(10000)               # git pull w/exp.backoff?
  run("git pull " & gh & user & "/" & pk, "cannot fork-pull")
  run("git pull " & gh & nlp & ".git master", "cannot master-pull")
  let b = "add-" & pknm & ext
  run("git checkout -B " & b, "cannot make branch")
  var contents = parseFile("packages.json")
  contents.add(%*{"name": pknm, "url": url, "method": "git", "tags": tags,
                  "description": desc, "license": license, "web": url})
  writeFile("packages.json", contents.pretty & "\n")
  run("git commit packages.json -m \"Add " & pknm & "\"", "cannot commit")
  run("git push " & auth & " " & b, "cannot push to fork")
  try:
    let j = web.postContent(api & "repos/" & nlp & "/pulls", """{"title":
"Add $1", "head": "$2:$3", "base": "master"}""" % [pknm, user, b])
    echo "Made pull request.  See " & j.parseJson{"html_url"}.getStr
  except: echo "cannot make pull request"
