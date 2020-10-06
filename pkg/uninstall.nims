import os, strutils   # shared .nims header
let vcRepos  = getEnv("NIMP", ".")                  # VC hierarchy root
let checkout = getEnv("NIMP_CO", "")                # local checkout|""
let scripts  = getEnv("NIMP_SR", vcRepos / "%")     # scripts
let binDir   = getEnv("NIMP_BIN", vcRepos / "bin")  # execs
let package  = getEnv("NIMP_PKG", "")               # current package

rmFile binDir/"nimp"
rmDir vcRepos/"nimp"
