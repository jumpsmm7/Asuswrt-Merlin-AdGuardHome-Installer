#!/bin/sh
# Verify all regular menu actions are eligible for one-argument dispatch.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-single-arg-actions.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions"

cleanup() {
	rm -rf "${TMP_ROOT}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"
mkdir -p "${TMP_ROOT}" || fail 'could not create test directory'

sed -n '/^single_arg_menu_action() {$/,/^}/p' "${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" ||
	fail 'could not extract single-argument action helper'
[ -s "${FUNCTIONS_FILE}" ] || fail 'single-argument action helper extraction was empty'

grep -q '\[ -z "${2:-}" \] && single_arg_menu_action "${1}"' "${SCRIPT_PATH}" ||
	fail 'main argument parser does not guard unset action parameters before one-argument dispatch'
grep -q 'set -- "${BRANCH}" "${CHOSEN}"' "${SCRIPT_PATH}" ||
	fail 'single-argument action path does not rewrite branch/action parameters'

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	for action in 1 2 3 4 5 6 7 8 9 install update uninstall changepw reconfigure setamtmupdate setlocalcache switchbranch setipset blocklists unusedblocklists b B backup r R restore; do
		if ! single_arg_menu_action "${action}"; then
			printf '%s\n' "missing action: ${action}" >&2
			exit 1
		fi
	done
	for branch in master dev release beta edge amtmupdate; do
		if single_arg_menu_action "${branch}"; then
			printf '%s\n' "branch/action ambiguity: ${branch}" >&2
			exit 1
		fi
	done
) || fail 'single-argument action helper returned an unexpected result'

printf '%s\n' 'PASS: regular menu actions support one-argument dispatch without matching branch names'
