#!/bin/sh
# Verify optional-file nvars actions dispatch only for existing files.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-yaml-nvars-file-action.$$"
FUNCTION_FILE="${TMP_ROOT}/function"
TARGET_FILE="${TMP_ROOT}/target"
CALLS_FILE="${TMP_ROOT}/calls"

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
sed -n '/^yaml_nvars_file_action() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" ||
	fail 'could not extract guarded nvars file action'
[ -s "${FUNCTION_FILE}" ] || fail 'guarded nvars file action extraction was empty'

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

yaml_nvars_append() { printf '%s\n' "append:$*" >>"${CALLS_FILE}"; }
yaml_nvars_delete() { printf '%s\n' "delete:$*" >>"${CALLS_FILE}"; }
yaml_nvars_insert() { printf '%s\n' "insert:$*" >>"${CALLS_FILE}"; }
yaml_nvars_replace() { printf '%s\n' "replace:$*" >>"${CALLS_FILE}"; }

: >"${TARGET_FILE}"
: >"${CALLS_FILE}"
yaml_nvars_file_action append content "${TARGET_FILE}" || fail 'append action failed'
yaml_nvars_file_action delete pattern "${TARGET_FILE}" || fail 'delete action failed'
yaml_nvars_file_action insert pattern content "${TARGET_FILE}" || fail 'insert action failed'
yaml_nvars_file_action replace pattern content "${TARGET_FILE}" || fail 'replace action failed'
[ "$(wc -l <"${CALLS_FILE}")" -eq 4 ] || fail 'existing-file actions were not all dispatched'

rm -f "${TARGET_FILE}"
yaml_nvars_file_action delete pattern "${TARGET_FILE}" || fail 'missing optional file was not tolerated'
[ "$(wc -l <"${CALLS_FILE}")" -eq 4 ] || fail 'missing-file action was dispatched'
if yaml_nvars_file_action invalid pattern "${TARGET_FILE}"; then
	fail 'unsupported nvars action was accepted'
fi
if yaml_nvars_file_action delete; then
	fail 'nvars action without a file was accepted'
fi

printf '%s\n' 'PASS: guarded nvars actions dispatch only for existing files'
