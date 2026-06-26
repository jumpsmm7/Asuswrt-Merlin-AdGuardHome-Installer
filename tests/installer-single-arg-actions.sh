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

sed -n '/^menu_action_allowed() {$/,/^single_arg_menu_action() {$/p' "${SCRIPT_PATH}" | sed '$d' >"${FUNCTIONS_FILE}" ||
	fail 'could not extract menu action helpers'
sed -n '/^single_arg_menu_action() {$/,/^}/p' "${SCRIPT_PATH}" >>"${FUNCTIONS_FILE}" ||
	fail 'could not extract single-argument action helper'
[ -s "${FUNCTIONS_FILE}" ] || fail 'single-argument action helper extraction was empty'

grep -q '\[ -z "${2:-}" \] && single_arg_menu_action "${1}"' "${SCRIPT_PATH}" ||
	fail 'main argument parser does not guard unset action parameters before one-argument dispatch'
grep -q 'set -- "${BRANCH}" "${CHOSEN}"' "${SCRIPT_PATH}" ||
	fail 'single-argument action path does not rewrite branch/action parameters'
default_line="$(grep -n 'write_conf BLOCKLIST_ANALYZER_SHA256' "${SCRIPT_PATH}" | cut -d: -f1)" ||
	fail 'could not find blocklist analyzer checksum default write'
dispatch_line="$(grep -n '\[ -z "${2:-}" \] && single_arg_menu_action "${1}"' "${SCRIPT_PATH}" | cut -d: -f1)" ||
	fail 'could not find one-argument dispatch guard'
if [ -z "${default_line}" ] || [ -z "${dispatch_line}" ]; then
	fail 'could not compare checksum defaulting and one-argument dispatch ordering'
fi
if [ "${default_line}" -ge "${dispatch_line}" ]; then
	fail 'blocklist analyzer checksum defaulting must happen before one-argument dispatch'
fi

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	BLOCKLIST_ANALYZER_SHA256=""
	for action in 1 2 3 4 5 6 7 8 install update uninstall changepw reconfigure setamtmupdate setlocalcache switchbranch setipset b B backup r R restore; do
		if ! single_arg_menu_action "${action}"; then
			printf '%s\n' "missing action: ${action}" >&2
			exit 1
		fi
	done
	for action in 9 blocklists unusedblocklists; do
		if single_arg_menu_action "${action}"; then
			printf '%s\n' "unexpected blocklist action without checksum: ${action}" >&2
			exit 1
		fi
	done
	BLOCKLIST_ANALYZER_SHA256="configured-sha256"
	for action in 9 blocklists unusedblocklists; do
		if ! single_arg_menu_action "${action}"; then
			printf '%s\n' "missing blocklist action with checksum: ${action}" >&2
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

printf '%s\n' 'PASS: regular menu actions support one-argument dispatch with checksum-gated blocklist aliases'
