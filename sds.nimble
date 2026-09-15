mode = ScriptMode.Verbose

import strutils, os

# Package
version = "0.1.0"
author = "Waku Team"
description = "E2E Reliability Protocol API"
license = "MIT"
srcDir = "src"
# Keep the repo layout in installed copies: a nimble store copy installs srcDir
# only, which would drop library/ (the FFI wrapper the libsds tasks compile).
installDirs = @["library", "src"]

# Dependencies. (This branch — nimble-v0.3.3 — is v0.3.3 made consumable as a
# nimble dependency: one manifest at the root (reliability.nimble removed),
# the FFI wrapper kept in installed copies, NIMFLAGS forwarding, and the
# reproducible/localized static archives from PR #85. The library ABI is
# untouched.)
requires "nim >= 2.2.4",
  "chronicles", "chronos", "stew", "stint", "metrics", "results",
  # library/ (the FFI wrapper) uses taskpools' SPSC channel; the release/v0.3
  # tree got it from a vendored submodule, a nimble consumer needs it declared.
  "taskpools"
# src/ uses libp2p for minprotobuf + varint only. Pinned to the release the
# status-desktop graph verified against (libp2p 2.0.0 / websock 0.4.0 /
# lsquic 0.5.4); newer libp2p releases pull json_serialization >= 0.4.4,
# protobuf_serialization >= 0.6.0 and libplum into a consumer's graph.
requires "libp2p == 2.0.0"

proc envNimFlags(): string =
  ## Extra Nim flags injected by the invoking environment via the NIMFLAGS
  ## env var. Lets embedders (a consumer workspace building libsds from its
  ## own dependency resolution) pass e.g. --skipParentCfg and --path flags.
  ## Appended after the task's own flags so the environment wins.
  let flags = getEnv("NIMFLAGS")
  if flags.len > 0: " " & flags else: ""

proc buildLibrary(
    outLibNameAndExt: string,
    name: string,
    srcDir = "./",
    params = "",
    `type` = "static",
) =
  if not dirExists "build":
    mkDir "build"
  # allow something like "nim nimbus --verbosity:0 --hints:off nimbus.nims"
  var extra_params = params
  for i in 2 ..< paramCount():
    extra_params &= " " & paramStr(i)
  if `type` == "static":
    exec "nim c" & " --out:build/" & outLibNameAndExt &
      " --threads:on --app:staticlib --opt:size --noMain --mm:refc --header --nimMainPrefix:libsds --skipParentCfg:on " &
      extra_params & envNimFlags() & " " & srcDir & name & ".nim"
  else:
    when defined(windows):
      exec "nim c" & " --out:build/" & outLibNameAndExt &
        " --threads:on --app:lib --opt:size --noMain --mm:refc --header --nimMainPrefix:libsds --skipParentCfg:off " &
        extra_params & envNimFlags() & " " & srcDir & name & ".nim"
    else:
      exec "nim c" & " --out:build/" & outLibNameAndExt &
        " --threads:on --app:lib --opt:size --noMain --mm:refc --header --nimMainPrefix:libsds --skipParentCfg:on " &
        extra_params & envNimFlags() & " " & srcDir & name & ".nim"

proc getArch(): string =
  let arch = getEnv("ARCH")
  if arch != "": return $arch
  let (archFromUname, _) = gorgeEx("uname -m")
  return $archFromUname

# Tasks
task test, "Run the test suite":
  exec "nim c -r tests/test_bloom.nim"
  exec "nim c -r tests/test_reliability.nim"
  exec "nim c -r tests/test_wire_compat.nim"

task libsdsDynamicWindows, "Generate bindings":
  let outLibNameAndExt = "libsds.dll"
  let name = "libsds"
  buildLibrary outLibNameAndExt,
    name, "library/",
    """-d:chronicles_line_numbers --warning:Deprecated:off --warning:UnusedImport:on -d:chronicles_log_level=TRACE """,
    "dynamic"

task libsdsDynamicLinux, "Generate bindings":
  let outLibNameAndExt = "libsds.so"
  let name = "libsds"
  buildLibrary outLibNameAndExt,
    name, "library/",
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
    name, "library/",
    archFlags & " -d:chronicles_line_numbers --warning:Deprecated:off --warning:UnusedImport:on -d:chronicles_log_level=TRACE",
    "dynamic"

task libsdsStaticWindows, "Generate bindings":
  let outLibNameAndExt = "libsds.lib"
  let name = "libsds"
  buildLibrary outLibNameAndExt,
    name, "library/",
    """-d:chronicles_line_numbers --warning:Deprecated:off --warning:UnusedImport:on -d:chronicles_log_level=TRACE """,
    "static"

task libsdsStaticLinux, "Generate bindings":
  let outLibNameAndExt = "libsds.a"
  let name = "libsds"
  buildLibrary outLibNameAndExt,
    name, "library/",
    """-d:chronicles_line_numbers --warning:Deprecated:off --warning:UnusedImport:on -d:chronicles_log_level=TRACE """,
    "static"

proc nimLibDir(): string =
  ## The lib/ of the nim that runs this task (nimbase.h): the compiler's own
  ## install (nimble store, tarball) or a choosenim toolchain. The release/v0.3
  ## tree pointed at a vendored nimbus-build-system copy, which a nimble
  ## consumer does not have.
  let (nimBin, _) = gorgeEx("which nim")
  let nimLibFromBin = parentDir(parentDir(nimBin.strip())) / "lib"
  let nimLibChoosenim = getHomeDir() / ".choosenim/toolchains/nim-" & NimVersion & "/lib"
  if fileExists(nimLibFromBin / "nimbase.h"): nimLibFromBin
  else: nimLibChoosenim

task libsdsStaticMac, "Generate bindings":
  # Same symbol localization as the iOS build: the archive exports only the
  # _Sds* API, so libsds's embedded Nim runtime cannot clash with the Nim
  # runtime of a consumer executable that links the archive (PR #85).
  let srcDir = "./library"
  let outDir = "build"
  let nimcacheDir = outDir & "/nimcache"
  if dirExists nimcacheDir:
    rmDir nimcacheDir
  if not dirExists outDir:
    mkDir outDir

  let aFile = outDir & "/libsds.a"
  let cpu = if getArch() == "arm64": "arm64" else: "amd64"
  let clangArch = if cpu == "amd64": "x86_64" else: cpu
  let sdkPath = staticExec("xcrun --show-sdk-path").strip()

  # 1) Generate C sources from Nim (no linking)
  exec "nim c" & " --nimcache:" & nimcacheDir & " --cpu:" & cpu &
    " --compileOnly:on" & " --noMain --mm:refc" & " --threads:on --opt:size --header" &
    " --nimMainPrefix:libsds --skipParentCfg:on" & " --cc:clang" & " -d:useMalloc" &
    " -d:chronicles_line_numbers --warning:Deprecated:off --warning:UnusedImport:on" &
    " -d:chronicles_log_level=TRACE" & envNimFlags() &
    " " & srcDir & "/libsds.nim"

  # 2) Compile the generated C files with hidden visibility. -fno-common:
  # tentative definitions (uninitialized globals) become regular data symbols;
  # otherwise they stay "common" symbols, which the ld -r -exported_symbol pass
  # below cannot localize, leaking ~550 Nim-runtime globals past the
  # _Sds*-only export surface.
  let clangFlags =
    "-arch " & clangArch & " -isysroot " & sdkPath & " -I" & nimLibDir() &
    " -O2 -fvisibility=hidden -fno-common"

  var objectFiles: seq[string] = @[]
  for cFile in listFiles(nimcacheDir):
    if cFile.endsWith(".c"):
      let oFile = cFile.changeFileExt("o")
      exec "clang " & clangFlags & " -c " & cFile & " -o " & oFile
      objectFiles.add(oFile)

  # 3) Merge into one object exporting only the _Sds* API
  let objListFile = outDir & "/objects.txt"
  writeFile(objListFile, objectFiles.join("\n"))
  let mergedObj = outDir & "/libsds_merged.o"
  exec "xcrun ld -r -arch " & clangArch & " -exported_symbol '_Sds*' -o " & mergedObj &
    " -filelist " & objListFile
  # ZERO_AR_DATE: zero the ar header mtimes so an unchanged rebuild yields a
  # byte-identical archive (embedders gate copies/relinks on content compares).
  exec "ZERO_AR_DATE=1 ar rcs " & aFile & " " & mergedObj
  exec "rm -f " & mergedObj & " " & objListFile

  echo "✔ macOS static library created: " & aFile

# Build Mobile iOS
proc buildMobileIOS(srcDir = ".", sdkPath = "") =
  echo "Building iOS libsds library"

  let outDir = "build"
  let nimcacheDir = outDir & "/nimcache"
  if not dirExists outDir:
    mkDir outDir

  if sdkPath.len == 0:
    quit "Error: Xcode/iOS SDK not found"

  let aFile = outDir & "/libsds.a"
  let aFileTmp = outDir & "/libsds_tmp.a"
  let arch = getArch()

  # 1) Generate C sources from Nim (no linking)
  # Use unique symbol prefix to avoid conflicts with other Nim libraries
  exec "nim c" &
      " --nimcache:" & nimcacheDir & " --os:ios --cpu:" & arch &
      " --compileOnly:on" &
      " --noMain --mm:orc" &
      " --threads:on --opt:size --header" &
      " --nimMainPrefix:libsds --skipParentCfg:on" &
      " --cc:clang" &
      " -d:useMalloc" & envNimFlags() &
      " " & srcDir & "/libsds.nim"

  # 2) Compile all generated C files to object files with hidden visibility
  # This prevents symbol conflicts with other Nim libraries (e.g., libnim_status_client)
  # -fno-common: see libsdsStaticMac (common symbols escape localization).
  let clangFlags = "-arch " & arch & " -isysroot " & sdkPath &
      " -I" & nimLibDir() &
      " -fembed-bitcode -miphoneos-version-min=16.0 -O2" &
      " -fvisibility=hidden -fno-common"

  var objectFiles: seq[string] = @[]
  for cFile in listFiles(nimcacheDir):
    if cFile.endsWith(".c"):
      let oFile = cFile.changeFileExt("o")
      exec "clang " & clangFlags & " -c " & cFile & " -o " & oFile
      objectFiles.add(oFile)

  # 3) Create static library from all object files. ZERO_AR_DATE: zero the ar
  # header mtimes so an unchanged rebuild yields a byte-identical archive
  # (embedders gate copies/relinks on content compares).
  exec "ZERO_AR_DATE=1 ar rcs " & aFileTmp & " " & objectFiles.join(" ")

  # 4) Use libtool to localize all non-public symbols
  # Keep only Sds* functions as global, hide everything else to prevent conflicts
  # with nim runtime symbols from libnim_status_client
  let keepSymbols = "_Sds*:_libsdsNimMain:_libsdsDatInit*:_libsdsInit*:_NimMainModule__libsds*"
  exec "xcrun libtool -static -o " & aFile & " " & aFileTmp &
       " -exported_symbols_list /dev/stdin <<< '" & keepSymbols & "' 2>/dev/null || cp " & aFileTmp & " " & aFile

  echo "✔ iOS library created: " & aFile

task libsdsIOS, "Build the mobile bindings for iOS":
  let srcDir = "./library"
  let sdkPath = getEnv("IOS_SDK_PATH")
  buildMobileIOS srcDir, sdkPath

### Mobile Android
proc buildMobileAndroid(srcDir = ".", params = "") =
  let cpu = getArch()

  let outDir = "build/"
  if not dirExists outDir:
    mkDir outDir

  var extra_params = params
  for i in 2 ..< paramCount():
    extra_params &= " " & paramStr(i)

  exec "nim c" & " --out:" & outDir &
    "/libsds.so --threads:on --app:lib --opt:size --noMain --mm:refc --nimMainPrefix:libsds " &
    "-d:chronicles_sinks=textlines[dynamic] --header --passL:-L" & outdir &
    " --passL:-llog --cpu:" & cpu & " --os:android -d:androidNDK " & extra_params &
    envNimFlags() & " " & srcDir & "/libsds.nim"

task libsdsAndroid, "Build the mobile bindings for Android":
  let srcDir = "./library"
  let extraParams = "-d:chronicles_log_level=ERROR"
  buildMobileAndroid srcDir, extraParams
