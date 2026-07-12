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

grep -q '\[ -z "${2:-}" \] && single_arg_menu_action "${1:-}"' "${SCRIPT_PATH}" ||
	fail 'main argument parser does not guard unset action parameters before one-argument dispatch'
grep -q 'set -- "${BRANCH}" "${CHOSEN}"' "${SCRIPT_PATH}" ||
	fail 'single-argument compatibility path does not rewrite branch/action parameters'
default_line="$(grep -n 'write_conf BLOCKLIST_ANALYZER_SHA256' "${SCRIPT_PATH}" | cut -d: -f1)" ||
	fail 'could not find blocklist analyzer checksum default write'
preview_line="$(grep -n '^cli_pre_runtime_defaults_preview "\$@"' "${SCRIPT_PATH}" | cut -d: -f1)" ||
	fail 'could not find runtime migration preview short-circuit'
amtm_check_line="$(grep -n '^amtm_update_check "\$@"' "${SCRIPT_PATH}" | cut -d: -f1)" ||
	fail 'could not find amtmupdate check before dependency validation'
dependency_line="$(grep -n '^installer_dependencies_available || exit 1' "${SCRIPT_PATH}" | cut -d: -f1)" ||
	fail 'could not find dependency validation'
dispatch_line="$(grep -n '\[ -z "${2:-}" \] && single_arg_menu_action "${1:-}"' "${SCRIPT_PATH}" | cut -d: -f1)" ||
	fail 'could not find one-argument dispatch guard'
if [ -z "${default_line}" ] || [ -z "${preview_line}" ] || [ -z "${amtm_check_line}" ] || [ -z "${dependency_line}" ] || [ -z "${dispatch_line}" ]; then
	fail 'could not compare amtmupdate check, dependency validation, checksum defaulting, and one-argument dispatch ordering'
fi
if [ "${preview_line}" -ge "${amtm_check_line}" ]; then
	fail 'runtime migration previews must run before startup checks that can write .config'
fi
if [ "${amtm_check_line}" -ge "${dependency_line}" ]; then
	fail 'amtmupdate check handling must happen before dependency validation'
fi
if [ "${dependency_line}" -ge "${default_line}" ]; then
	fail 'base dependency validation must happen before blocklist analyzer checksum default write'
fi
if [ "${default_line}" -ge "${dispatch_line}" ]; then
	fail 'blocklist analyzer checksum defaulting must happen before one-argument dispatch'
fi

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	TARG_DIR="${TMP_ROOT}/target"
	AGH_FILE="${TARG_DIR}/AdGuardHome"
	BASE_DIR="${TMP_ROOT}/base"
	BACKUP_FILE="${BASE_DIR}/backup_AdGuardHome.tar.gz"
	mkdir -p "${BASE_DIR}" || exit 1

	assert_allowed() {
		local action
		for action in "$@"; do
			if ! single_arg_menu_action "${action}"; then
				printf '%s\n' "missing action: ${action}" >&2
				exit 1
			fi
		done
	}

	assert_disallowed() {
		local action
		for action in "$@"; do
			if single_arg_menu_action "${action}"; then
				printf '%s\n' "unexpected action: ${action}" >&2
				exit 1
			fi
		done
	}

	BLOCKLIST_ANALYZER_SHA256=""
	assert_allowed 1 2 install update uninstall d D doctor status
	assert_disallowed 3 4 5 6 7 8 changepw reconfigure setamtmupdate setlocalcache switchbranch setipset m M migrate-runtime-defaults b B backup r R restore 9 blocklists unusedblocklists

	touch "${BACKUP_FILE}" || exit 1
	assert_allowed r R restore
	assert_disallowed 3 4 5 6 7 8 changepw reconfigure setamtmupdate setlocalcache switchbranch setipset m M migrate-runtime-defaults b B backup 9 blocklists unusedblocklists

	mkdir -p "${TARG_DIR}" || exit 1
	touch "${AGH_FILE}" || exit 1
	assert_allowed 1 2 3 4 5 6 7 8 install update uninstall changepw reconfigure setamtmupdate setlocalcache switchbranch setipset m M b B backup r R restore
	assert_disallowed migrate-runtime-defaults 9 blocklists unusedblocklists

	BLOCKLIST_ANALYZER_SHA256="configured-sha256"
	assert_allowed 9 blocklists unusedblocklists
	assert_disallowed master dev release beta edge amtmupdate
) || fail 'single-argument action helper returned an unexpected result'

printf '%s\n' 'PASS: regular menu actions support one-argument dispatch with checksum-gated blocklist aliases'
