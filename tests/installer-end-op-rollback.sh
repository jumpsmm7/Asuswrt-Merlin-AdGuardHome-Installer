#!/bin/sh
# Verify CLI/deferred end_op_message failures record default rollback results
# without replacing rollback records that still need attention.

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
	'/^PTXT() {$/,/^}$/p; /^rollback_result_write() {$/,/^}$/p; /^rollback_result_summary() {$/,/^}$/p; /^rollback_result_needs_attention() {$/,/^}$/p; /^end_op_message() {$/,/^}$/p' \
	"${INSTALLER_PATH}" >"${FUNCTIONS_FILE}" || fail "could not read ${INSTALLER_PATH}"
[ -s "${FUNCTIONS_FILE}" ] || fail 'end_op_message functions were not found'
grep -q '^rollback_result_needs_attention() {$' "${FUNCTIONS_FILE}" || fail 'rollback attention helper was not found'
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

cat >"${ROLLBACK_RESULT_FILE}" <<'RESULT'
time=2026-07-12 00:00:00
context=binary-replace
result=rollback partial
detail=previous binary restored but service restart failed
RESULT
CLI_MODE="1"
ADGUARD_DEFER_END_OP="0"
ROLLBACK_RESULT_UPDATED="0"

end_op_message 1 update >/dev/null 2>&1 && fail 'CLI failure with attention record unexpectedly returned success'
grep -q '^result=rollback partial$' "${ROLLBACK_RESULT_FILE}" || fail 'CLI failure replaced rollback attention result'
grep -q '^detail=previous binary restored but service restart failed$' "${ROLLBACK_RESULT_FILE}" || fail 'CLI failure replaced rollback attention detail'

rm -f "${ROLLBACK_RESULT_FILE}" || fail 'could not reset rollback result'
CLI_MODE="0"
ADGUARD_DEFER_END_OP="1"
ROLLBACK_RESULT_UPDATED="0"

end_op_message 2 >/dev/null 2>&1 && fail 'deferred interruption unexpectedly returned success'
[ -f "${ROLLBACK_RESULT_FILE}" ] || fail 'deferred interruption did not write rollback result'
grep -q '^result=interrupted: no rollback attempted$' "${ROLLBACK_RESULT_FILE}" || fail 'deferred interruption wrote wrong rollback result'

cat >"${ROLLBACK_RESULT_FILE}" <<'RESULT'
time=2026-07-12 00:00:00
context=directory-restore
result=restore-failed
detail=previous installation remains at backup path
RESULT
CLI_MODE="0"
ADGUARD_DEFER_END_OP="1"
ROLLBACK_RESULT_UPDATED="0"

end_op_message 2 >/dev/null 2>&1 && fail 'deferred interruption with attention record unexpectedly returned success'
grep -q '^result=restore-failed$' "${ROLLBACK_RESULT_FILE}" || fail 'deferred interruption replaced rollback attention result'
grep -q '^detail=previous installation remains at backup path$' "${ROLLBACK_RESULT_FILE}" || fail 'deferred interruption replaced rollback attention detail'

printf '%s\n' 'PASS: end_op_message records default rollback results without replacing attention records'
