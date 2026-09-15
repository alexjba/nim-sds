# Task entry point for a consumer: `nim <task> <package>/library/sds_tasks.nims`.
# It sits under library/ because installDirs covers that directory; a .nims at
# the package root does not survive `nimble install` (nimble 0.22.3 ignores
# installFiles).
include "../sds.nimble"
