#!/bin/sh
# Verify JFFS NVRAM failures abort both installer entry pathways.

set -u

INSTALLER_PATH="${1:-installer}"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

[ -f "${INSTALLER_PATH}" ] || fail "installer script not found: ${INSTALLER_PATH}"

cli_install_body="$(sed -n '/^[[:space:]]*install)$/,/^[[:space:]]*;;$/p' "${INSTALLER_PATH}")" ||
	fail 'could not inspect the CLI install pathway'
printf '%s\n' "${cli_install_body}" | grep -q 'check_jffs_enabled || return 1' ||
	fail 'CLI install must abort when JFFS setup fails'

interactive_body="$(sed -n '/^case "$2" in$/,/^[[:space:]]*check_version$/p' "${INSTALLER_PATH}")" ||
	fail 'could not inspect the interactive install pathway'
printf '%s\n' "${interactive_body}" | grep -q 'check_jffs_enabled || exit 1' ||
	fail 'interactive install must abort when JFFS setup fails'

call_count="$(grep -c '^[[:space:]]*check_jffs_enabled || \(return\|exit\) 1$' "${INSTALLER_PATH}")" ||
	fail 'could not count guarded JFFS setup calls'
[ "${call_count}" -eq 2 ] || fail 'every JFFS setup call must propagate failure'

printf '%s\n' 'PASS: JFFS setup failures abort CLI and interactive installs'
