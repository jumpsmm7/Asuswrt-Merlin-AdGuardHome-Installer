#!/bin/sh
# Verify RESTORE does not run the interactive feature-selection path.

set -u

SCRIPT_PATH="${1:-installer}"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"

selection_case="$(awk '
	/case "\$\{2:-reconfig\}" in/ { copying = 1 }
	copying { print }
	copying && /^[[:space:]]*"RESTORE"\)/ { found_restore = 1 }
	copying && found_restore && /^[[:space:]]*;;[[:space:]]*$/ { exit }
' "${SCRIPT_PATH}")"

[ -n "${selection_case}" ] || fail 'could not find setup feature-selection case'
printf '%s\n' "${selection_case}" | grep -q '"install" | "reconfig")' ||
	fail 'install/reconfig feature-selection branch is missing'
if printf '%s\n' "${selection_case}" | grep -q '"install" | "reconfig" | "RESTORE")'; then
	fail 'RESTORE still shares the interactive feature-selection branch'
fi
printf '%s\n' "${selection_case}" | grep -q '^[[:space:]]*"RESTORE")' ||
	fail 'RESTORE does not have an explicit feature-preservation branch'

printf '%s\n' 'PASS: RESTORE preserves restored feature selections'
