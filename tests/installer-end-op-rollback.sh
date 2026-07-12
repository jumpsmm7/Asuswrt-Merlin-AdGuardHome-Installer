#!/bin/sh
# Verify CLI/deferred end_op_message failures still record default rollback results.

set -u

fail() {
	printf '%s\n' "FAIL: $1" >&2
	exit 1
}

INSTALLER_PATH="${1:-installer}"
TEST_ROOT="${TMPDIR:-/tmp}/installer-end-op-rollback.$$"
FUNCTIONS_FILE="${TEST_ROOT}/installer-end-op-functions"
mkdir -p "${TEST_ROOT}/target" || fail 'could not create test directory'
trap 'rm -rf "${TEST_ROOT}"' EXIT HUP INT TERM

sed -n \
	'/^PTXT() {$/,/^}$/p; /^rollback_result_write() {$/,/^}$/p; /^rollback_result_summary() {$/,/^}$/p; /^end_op_message() {$/,/^}$/p' \
	"${INSTALLER_PATH}" >"${FUNCTIONS_FILE}" || fail "could not read ${INSTALLER_PATH}"
[ -s "${FUNCTIONS_FILE}" ] || fail 'end_op_message functions were not found'
grep -q '^end_op_message() {$' "${FUNCTIONS_FILE}" || fail 'installer has no end_op_message helper'

. "${FUNCTIONS_FILE}"

TARG_DIR="${TEST_ROOT}/target"
ROLLBACK_RESULT_FILE="${TARG_DIR}/.rollback_result"
CLI_MODE="1"
ROLLBACK_RESULT_UPDATED="0"

end_op_message 1 update >/dev/null 2>&1 && fail 'CLI failure unexpectedly returned success'
[ -f "${ROLLBACK_RESULT_FILE}" ] || fail 'CLI failure did not write rollback result'
grep -q '^result=no rollback attempted$' "${ROLLBACK_RESULT_FILE}" || fail 'CLI failure wrote wrong rollback result'
grep -q '^detail=operation aborted before rollback was needed$' "${ROLLBACK_RESULT_FILE}" || fail 'CLI failure wrote wrong rollback detail'

rm -f "${ROLLBACK_RESULT_FILE}" || fail 'could not reset rollback result'
CLI_MODE="0"
ADGUARD_DEFER_END_OP="1"
ROLLBACK_RESULT_UPDATED="0"

end_op_message 2 >/dev/null 2>&1 && fail 'deferred interruption unexpectedly returned success'
[ -f "${ROLLBACK_RESULT_FILE}" ] || fail 'deferred interruption did not write rollback result'
grep -q '^result=interrupted: no rollback attempted$' "${ROLLBACK_RESULT_FILE}" || fail 'deferred interruption wrote wrong rollback result'

printf '%s\n' 'PASS: end_op_message records default rollback before early returns'
