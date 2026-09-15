mode = ScriptMode.Verbose

import strutils, os

# Package
version = "0.1.0"
author = "Waku Team"
description = "E2E Reliability Protocol API"
license = "MIT"
srcDir = "src"
# nimble installs srcDir only, so library/ — the FFI wrapper the libsds tasks
# compile, plus its task entry point — has to be listed here as well.
installDirs = @["library", "src"]

# Dependencies
requires "nim >= 2.2.4",
  "chronicles", "chronos", "stew", "stint", "metrics", "results",
  # library/ (the FFI wrapper) uses taskpools' SPSC channel
  # (taskpools/channels_spsc_single), which taskpools 0.2.0 removed.
  "taskpools < 0.2.0"
# src/ uses libp2p for minprotobuf + varint only. libp2p 2.0.0: newer releases
# pull json_serialization >= 0.4.4, protobuf_serialization >= 0.6.0 and libplum
# into a consumer's graph.
requires "libp2p == 2.0.0"

proc envNimFlags(): string =
  ## Nim flags from the NIMFLAGS env var, appended after the task's own flags so
  ## the environment wins. This is how an embedder passes its own dependency
  ## resolution in: --path entries, and --skipParentCfg so that a nim.cfg above
  ## the build directory does not leak into the compile.
  ## In the make and nix flows nimbus-build-system already folds NIMFLAGS into
  ## NIM_PARAMS, which reaches the tasks on the command line as well, so those
  ## flags arrive twice.
  let flags = getEnv("NIMFLAGS")
  if flags.len > 0: " " & flags else: ""

proc sdsOutDir(): string =
  ## Every artifact of a build task goes here: nimcache, objects, archives, the
  ## library. A package resolved through nimble is built from a read-only store
  ## copy, so no task may write under the source tree; such a consumer passes an
  ## absolute path in SDS_OUT_DIR. Unset, it is `build` under the working
  ## directory, which is what the Makefile flow uses.
  result = getEnv("SDS_OUT_DIR")
  if result.len == 0:
    result = "build"

proc nimcacheDirOf(outDir, target: string): string =
  ## One nimcache per build target, under the out dir. The macOS and mobile
  ## tasks compile every .c file they find there, so the location must be
  ## pinned and must hold that target's generated sources only.
  outDir / "nimcache" / target

proc sdsRootDir(): string =
  ## This package's root. `currentSourcePath()` is this manifest whichever
  ## entry script included it, while `thisDir()` is the entry script's own
  ## directory — the root in a checkout, library/ in an installed copy.
  parentDir(currentSourcePath())

proc libraryDir(): string =
  ## The FFI wrapper's sources (libsds.nim, and libsds.h, the header contract
  ## embedders compile against). Resolved from this package rather than from the
  ## working directory: a consumer runs the tasks from its own build directory.
  sdsRootDir() / "library"

proc buildLibrary(
    outLibNameAndExt: string,
    name: string,
    srcDir: string,
    params = "",
    `type` = "static",
) =
  let outDir = sdsOutDir()
  mkDir outDir
  # forward any extra flags given on the nim command line after the task name
  var extra_params = params
  for i in 2 ..< paramCount():
    extra_params &= " " & paramStr(i)
  let outFlags = " --nimcache:" & quoteShell(nimcacheDirOf(outDir, outLibNameAndExt)) &
    " --out:" & quoteShell(outDir / outLibNameAndExt)
  if `type` == "static":
    exec "nim c" & outFlags &
      " --threads:on --app:staticlib --opt:size --noMain --mm:refc --header --nimMainPrefix:libsds --skipParentCfg:on " &
      extra_params & envNimFlags() & " " & quoteShell(srcDir / (name & ".nim"))
  else:
    when defined(windows):
      exec "nim c" & outFlags &
        " --threads:on --app:lib --opt:size --noMain --mm:refc --header --nimMainPrefix:libsds --skipParentCfg:off " &
        extra_params & envNimFlags() & " " & quoteShell(srcDir / (name & ".nim"))
    else:
      exec "nim c" & outFlags &
        " --threads:on --app:lib --opt:size --noMain --mm:refc --header --nimMainPrefix:libsds --skipParentCfg:on " &
        extra_params & envNimFlags() & " " & quoteShell(srcDir / (name & ".nim"))

proc getArch(): string =
  let arch = getEnv("ARCH")
  if arch != "": return $arch
  let (archFromUname, _) = gorgeEx("uname -m")
  return $archFromUname

# Tasks
task test, "Run the test suite":
  # tests/ is not in installDirs, so this task runs in a checkout only.
  let outDir = sdsOutDir()
  mkDir outDir
  for t in ["test_bloom", "test_reliability", "test_wire_compat"]:
    exec "nim c -r --nimcache:" & quoteShell(nimcacheDirOf(outDir, t)) &
      " --out:" & quoteShell(outDir / t) & envNimFlags() &
      " " & quoteShell(sdsRootDir() / "tests" / (t & ".nim"))

task libsdsDynamicWindows, "Generate bindings":
  let outLibNameAndExt = "libsds.dll"
  let name = "libsds"
  buildLibrary outLibNameAndExt,
    name, libraryDir(),
    """-d:chronicles_line_numbers --warning:Deprecated:off --warning:UnusedImport:on -d:chronicles_log_level=TRACE """,
    "dynamic"

task libsdsDynamicLinux, "Generate bindings":
  let outLibNameAndExt = "libsds.so"
  let name = "libsds"
  buildLibrary outLibNameAndExt,
    name, libraryDir(),
    """-d:chronicles_line_numbers --warning:Deprecated:off --warning:UnusedImport:on -d:chronicles_log_level=TRACE """,
    "dynamic"

task libsdsDynamicMac, "Generate bindings":
  let outLibNameAndExt = "libsds.dylib"
  let name = "libsds"

  let arch = getArch()
  let sdkPath = staticExec("xcrun --show-sdk-path").strip()
  let archFlags = (if arch == "arm64": "--cpu:arm64 --passC:\"-arch arm64\" --passL:\"-arch arm64\" --passC:\"-isysroot " & sdkPath & "\" --passL:\"-isysroot " & sdkPath & "\""
                   else: "--cpu:amd64 --passC:\"-arch x86_64\" --passL:\"-arch x86_64\" --passC:\"-isysroot " & sdkPath & "\" --passL:\"-isysroot " & sdkPath & "\"")
  buildLibrary outLibNameAndExt,
    name, libraryDir(),
    archFlags & " -d:chronicles_line_numbers --warning:Deprecated:off --warning:UnusedImport:on -d:chronicles_log_level=TRACE",
    "dynamic"

task libsdsStaticWindows, "Generate bindings":
  let outLibNameAndExt = "libsds.lib"
  let name = "libsds"
  buildLibrary outLibNameAndExt,
    name, libraryDir(),
    """-d:chronicles_line_numbers --warning:Deprecated:off --warning:UnusedImport:on -d:chronicles_log_level=TRACE """,
    "static"

task libsdsStaticLinux, "Generate bindings":
  let outLibNameAndExt = "libsds.a"
  let name = "libsds"
  buildLibrary outLibNameAndExt,
    name, libraryDir(),
    """-d:chronicles_line_numbers --warning:Deprecated:off --warning:UnusedImport:on -d:chronicles_log_level=TRACE """,
    "static"

proc nimLibDir(): string =
  ## lib/ of the nim on PATH, where nimbase.h lives. The macOS and iOS tasks
  ## compile the generated C by hand and pass this to clang as an include dir.
  let nimBin = findExe("nim")
  if nimBin.len == 0:
    quit "Error: nim not found on PATH"
  result = parentDir(parentDir(nimBin)) / "lib"
  if not fileExists(result / "nimbase.h"):
    quit "Error: nimbase.h not found in " & result

task libsdsStaticMac, "Generate bindings":
  let outLibNameAndExt = "libsds.a"
  let name = "libsds"

  let arch = getArch()
  let sdkPath = staticExec("xcrun --show-sdk-path").strip()
  let archFlags = (if arch == "arm64": "--cpu:arm64 --passC:\"-arch arm64\" --passL:\"-arch arm64\" --passC:\"-isysroot " & sdkPath & "\" --passL:\"-isysroot " & sdkPath & "\""
                   else: "--cpu:amd64 --passC:\"-arch x86_64\" --passL:\"-arch x86_64\" --passC:\"-isysroot " & sdkPath & "\" --passL:\"-isysroot " & sdkPath & "\"")
  buildLibrary outLibNameAndExt,
    name, libraryDir(),
    archFlags & " -d:chronicles_line_numbers --warning:Deprecated:off --warning:UnusedImport:on -d:chronicles_log_level=TRACE",
    "static"

proc buildMobileIOS(srcDir = libraryDir(), sdkPath = "") =
  echo "Building iOS libsds library"

  let outDir = sdsOutDir()
  let nimcacheDir = nimcacheDirOf(outDir, "libsdsIOS")
  if dirExists nimcacheDir:
    rmDir nimcacheDir
  mkDir outDir

  if sdkPath.len == 0:
    quit "Error: Xcode/iOS SDK not found"

  let aFile = outDir / "libsds.a"
  let aFileTmp = outDir / "libsds_tmp.a"
  let arch = getArch()

  # 1) Generate C sources from Nim (no linking)
  exec "nim c" &
      " --nimcache:" & quoteShell(nimcacheDir) & " --os:ios --cpu:" & arch &
      " --compileOnly:on" &
      " --noMain --mm:orc" &
      " --threads:on --opt:size --header" &
      " --nimMainPrefix:libsds --skipParentCfg:on" &
      " --cc:clang" &
      " -d:useMalloc" & envNimFlags() &
      " " & quoteShell(srcDir / "libsds.nim")

  # 2) Compile to objects with hidden visibility, so the Nim runtime symbols
  # stay private to this archive.
  let clangFlags = "-arch " & arch & " -isysroot " & quoteShell(sdkPath) &
      " -I" & quoteShell(nimLibDir()) &
      " -fembed-bitcode -miphoneos-version-min=16.0 -O2" &
      " -fvisibility=hidden"

  var objectFiles: seq[string] = @[]
  for cFile in listFiles(nimcacheDir):
    if cFile.endsWith(".c"):
      let oFile = cFile.changeFileExt("o")
      exec "clang " & clangFlags & " -c " & quoteShell(cFile) &
        " -o " & quoteShell(oFile)
      objectFiles.add(oFile)

  # 3) Create the static library from all object files
  exec "ar rcs " & quoteShell(aFileTmp) & " " & quoteShellCommand(objectFiles)

  # 4) Localize every symbol outside the public API; the listed ones stay
  # global, so the embedded Nim runtime stays private to this archive.
  let keepSymbols = "_Sds*:_libsdsNimMain:_libsdsDatInit*:_libsdsInit*:_NimMainModule__libsds*"
  exec "xcrun libtool -static -o " & quoteShell(aFile) & " " & quoteShell(aFileTmp) &
       " -exported_symbols_list /dev/stdin <<< '" & keepSymbols &
       "' 2>/dev/null || cp " & quoteShell(aFileTmp) & " " & quoteShell(aFile)

  echo "✔ iOS library created: " & aFile

task libsdsIOS, "Build the mobile bindings for iOS":
  let sdkPath = getEnv("IOS_SDK_PATH")
  buildMobileIOS libraryDir(), sdkPath

### Mobile Android
proc buildMobileAndroid(srcDir = libraryDir(), params = "") =
  let cpu = getArch()

  let outDir = sdsOutDir()
  mkDir outDir

  var extra_params = params
  for i in 2 ..< paramCount():
    extra_params &= " " & paramStr(i)

  exec "nim c" & " --nimcache:" & quoteShell(nimcacheDirOf(outDir, "libsdsAndroid-" & cpu)) &
    " --out:" & quoteShell(outDir / "libsds.so") &
    " --threads:on --app:lib --opt:size --noMain --mm:refc --nimMainPrefix:libsds " &
    "-d:chronicles_sinks=textlines[dynamic] --header --passL:-L" & quoteShell(outDir) &
    " --passL:-llog --cpu:" & cpu & " --os:android -d:androidNDK " & extra_params &
    envNimFlags() & " " & quoteShell(srcDir / "libsds.nim")

task libsdsAndroid, "Build the mobile bindings for Android":
  let extraParams = "-d:chronicles_log_level=ERROR"
  buildMobileAndroid libraryDir(), extraParams
