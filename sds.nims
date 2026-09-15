# Entry point for `nim <task> sds.nims` (nim only runs tasks out of a .nims
# file, and this package's tasks live in sds.nimble so nimble can parse the
# manifest). This used to be a symlink the Makefile created on demand — which
# a consumer building a READ-ONLY copy of this package (a nimble store copy)
# cannot do, and which made every such build write into the source tree. It is
# committed instead, and declared in installFiles so installed copies keep it.
#
# Nim only auto-loads a `<project>.nims` as a config for a `<project>.nim` in
# the same directory; there is no sds.nim next to this file (the module lives
# at src/sds.nim), so nothing picks this up implicitly.
include "sds.nimble"
