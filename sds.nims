# Entry point for `nim <task> sds.nims` in a CHECKOUT (nim only runs tasks out
# of a .nims file, and this package's tasks live in sds.nimble so nimble can
# parse the manifest). This used to be a symlink the Makefile created on
# demand, which made every build write into the source tree.
#
# An INSTALLED copy does not get this file: nimble 0.22.3 strips every root
# file that installDirs does not cover, and installFiles does not rescue it
# (see sds.nimble). Consumers use library/sds_tasks.nims, which is identical
# apart from the include path.
#
# Nim only auto-loads a `<project>.nims` as a config for a `<project>.nim` in
# the same directory; there is no sds.nim next to this file (the module lives
# at src/sds.nim), so nothing picks this up implicitly.
include "sds.nimble"
