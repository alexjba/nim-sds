# Entry point for `nim <task> <package>/library/sds_tasks.nims` — the one a
# CONSUMER uses. It lives under library/ because that is an installDirs entry,
# so it survives `nimble install` into the package store; a root-level .nims
# does not (nimble 0.22.3 ignores installFiles — see sds.nimble).
#
# It is the same include as the root sds.nims. sdsRootDir() in the manifest
# normalizes thisDir(), which follows whichever of the two is the entry script.
include "../sds.nimble"
