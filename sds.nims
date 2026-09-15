# Task entry point for a checkout: `nim <task> sds.nims`. Nim runs tasks only
# from a .nims file, while the tasks themselves live in sds.nimble so that
# nimble can still parse the manifest.
#
# An installed copy does not have this file — nimble 0.22.3 keeps only what
# installDirs covers — so a consumer uses library/sds_tasks.nims instead.
include "sds.nimble"
