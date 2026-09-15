# nim-e2e-reliability
Nim implementation of the e2e reliability protocol

## Building

### Nix

```bash
nix build --print-out-paths '.?submodules=1#libsds'
nix build --print-out-paths '.?submodules=1#libsds-android-arm64'
```

### Windows, Linux or MacOS

```code
make libsds
```

### Android

Download the latest Android NDK. For example, on Ubuntu with Intel:

```code
cd ~
wget https://dl.google.com/android/repository/android-ndk-r27c-linux.zip
```
```code
unzip android-ndk-r27c-linux.zip
```

Then, add the following to your ~/.bashrc file:
```code
export ANDROID_NDK_ROOT=$HOME/android-ndk-r27c
export PATH=$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH
```

Then, use one of the following commands, according to the current architecture:

| Architecture | command |
| ------------ | ------- |
| arm64 | `make libsds-android ARCH=arm64` |
| amd64 | `make libsds-android ARCH=amd64` |
| x86 | `make libsds-android ARCH=x86` |

At the end of the process, the library will be created in build/libsds.so

### Build outputs, and building from a read-only copy

Every build task writes exclusively under one directory, `build` by default.
Set `SDS_OUT_DIR` (absolute path) to put the nimcache, the object files and the
library somewhere else — nothing is written into the source tree, so a consumer
that resolves this package through nimble can build the read-only store copy in
place:

```code
SDS_OUT_DIR=/path/to/out nim libsdsDynamicLinux /path/to/nim-sds/sds.nims
```

From a copy installed by nimble, use `library/sds_tasks.nims` instead of
`sds.nims`: nimble 0.22.3 strips root files that `installDirs` does not cover,
so that is the entry point that survives installation. It is the same include.

`NIMFLAGS` is appended to every compile, which is how such a consumer passes its
own dependency resolution (`--path:` entries) in. The header contract stays
`library/libsds.h` in the source tree.




