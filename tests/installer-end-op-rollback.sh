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
ERROR='Error:'
REAPER_RELEASE_ATTEMPTS="0"
# nvram_transaction_lock_reaper_release_active records an attempt to release the active NVRAM transaction reaper.
nvram_transaction_lock_reaper_release_active() {
	REAPER_RELEASE_ATTEMPTS=$((REAPER_RELEASE_ATTEMPTS + 1))
	return 0
}

end_op_message 1 update >/dev/null 2>&1 && fail 'CLI failure unexpectedly returned success'
[ "${REAPER_RELEASE_ATTEMPTS}" -eq 1 ] || fail 'CLI failure did not release the active reaper before returning'
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

cat >"${ROLLBACK_RESULT_FILE}" <<'RESULT'
time=2026-07-12 00:00:00
context=binary-replace
result=rollback complete
detail=previous binary restored successfully
RESULT
CLI_MODE="1"
ADGUARD_DEFER_END_OP="0"
ROLLBACK_RESULT_UPDATED="0"
REAPER_RELEASE_ATTEMPTS_SAVED="${REAPER_RELEASE_ATTEMPTS}"

end_op_message 1 update >/dev/null 2>&1 && fail 'CLI failure with a benign prior result unexpectedly returned success'
grep -q '^result=no rollback attempted$' "${ROLLBACK_RESULT_FILE}" || fail 'CLI failure did not overwrite a rollback result that did not need attention'
grep -q '^detail=operation aborted before rollback was needed$' "${ROLLBACK_RESULT_FILE}" || fail 'CLI failure did not overwrite the detail of a rollback result that did not need attention'
REAPER_RELEASE_ATTEMPTS="${REAPER_RELEASE_ATTEMPTS_SAVED}"

rm -f "${ROLLBACK_RESULT_FILE}" || fail 'could not reset rollback result'
CLI_MODE="0"
ADGUARD_DEFER_END_OP="1"
ROLLBACK_RESULT_UPDATED="0"

end_op_message 2 >/dev/null 2>&1 && fail 'deferred interruption unexpectedly returned success'
[ "${REAPER_RELEASE_ATTEMPTS}" -eq 3 ] || fail 'deferred interruption did not release the active reaper before returning'
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

for signal_mode in cli deferred; do
	CLI_MODE="0"
	ADGUARD_DEFER_END_OP="0"
	[ "${signal_mode}" != "cli" ] || CLI_MODE="1"
	[ "${signal_mode}" != "deferred" ] || ADGUARD_DEFER_END_OP="1"
	# nvram_transaction_lock_reaper_release_active reports that the active NVRAM transaction reaper was released.
	nvram_transaction_lock_reaper_release_active() { return 0; }
	rm -f "${TEST_ROOT}/unexpected-signal-return"
	(
		END_OP_SIGNAL="1"
		end_op_message 2 >/dev/null 2>&1
		printf '%s\n' returned >"${TEST_ROOT}/unexpected-signal-return"
	)
	status=$?
	[ "${status}" -eq 2 ] || fail "${signal_mode} signal cleanup exited with status ${status} instead of 2"
	[ ! -e "${TEST_ROOT}/unexpected-signal-return" ] || fail "${signal_mode} signal cleanup returned to the interrupted operation"

	# nvram_transaction_lock_reaper_release_active simulates failure to release the active NVRAM transaction reaper.
	nvram_transaction_lock_reaper_release_active() { return 1; }
	rm -f "${TEST_ROOT}/unexpected-signal-return"
	(
		END_OP_SIGNAL="1"
		end_op_message 2 >"${TEST_ROOT}/${signal_mode}-signal-release-output" 2>&1
		printf '%s\n' returned >"${TEST_ROOT}/unexpected-signal-return"
	)
	status=$?
	[ "${status}" -eq 1 ] || fail "${signal_mode} signal cleanup failure exited with status ${status} instead of 1"
	[ ! -e "${TEST_ROOT}/unexpected-signal-return" ] || fail "${signal_mode} signal cleanup failure returned to the interrupted operation"
	grep -q 'Unable to release the installer NVRAM transaction reaper' "${TEST_ROOT}/${signal_mode}-signal-release-output" || fail "${signal_mode} signal cleanup failure was not reported"
done

CLI_MODE="0"
ADGUARD_DEFER_END_OP="0"
ROLLBACK_RESULT_UPDATED="1"
INFO='Info:'
ERROR='Error:'
BRANCH='testing'
SCRIPT_LOC="${TEST_ROOT}/missing-installer"
HOME="${TEST_ROOT}/home"
mkdir -p "${HOME}" || fail 'could not create test home directory'
cat >"${TARG_DIR}/installer" <<EOF_INSTALLER
#!/bin/sh
printf '%s\n' restarted >"${TEST_ROOT}/unexpected-restart"
EOF_INSTALLER
chmod 755 "${TARG_DIR}/installer" || fail 'could not make restart target executable'
# nvram_transaction_lock_release always fails to release the NVRAM transaction lock.
nvram_transaction_lock_release() { return 1; }
# nvram_transaction_lock_reaper_release_active reports that the active NVRAM transaction reaper was released.
nvram_transaction_lock_reaper_release_active() { return 0; }
# sleep overrides the delay command with a no-op for testing.
sleep() { :; }
# clear_screen clears the terminal display.
clear_screen() { :; }

(
	end_op_message 0 '' >"${TEST_ROOT}/interactive-output" 2>&1
	printf '%s\n' returned >"${TEST_ROOT}/unexpected-return"
)
status=$?
[ "${status}" -eq 1 ] || fail "interactive lock-release failure exited with status ${status} instead of 1"
[ ! -e "${TEST_ROOT}/unexpected-return" ] || fail 'interactive lock-release failure returned to its caller'
[ ! -e "${TEST_ROOT}/unexpected-restart" ] || fail 'interactive lock-release failure restarted without releasing the lock'
grep -q 'Unable to release the installer NVRAM transaction lock' "${TEST_ROOT}/interactive-output" || fail 'interactive lock-release failure was not reported'

CLI_MODE="1"
ADGUARD_DEFER_END_OP="0"
# nvram_transaction_lock_release succeeds so only reaper release is under test below.
nvram_transaction_lock_release() { return 0; }
# nvram_transaction_lock_reaper_release_active simulates failure to release the active NVRAM transaction reaper.
nvram_transaction_lock_reaper_release_active() { return 1; }
if end_op_message 0 >"${TEST_ROOT}/cli-reaper-output" 2>&1; then
	fail 'CLI reaper-release failure unexpectedly returned success'
else
	status=$?
fi
[ "${status}" -eq 1 ] || fail "CLI reaper-release failure returned status ${status} instead of 1"
grep -q 'Unable to release the installer NVRAM transaction reaper' "${TEST_ROOT}/cli-reaper-output" || fail 'CLI reaper-release failure was not reported'

CLI_MODE="0"
ADGUARD_DEFER_END_OP="1"
if end_op_message 2 >"${TEST_ROOT}/deferred-reaper-output" 2>&1; then
	fail 'deferred reaper-release failure unexpectedly returned success'
else
	status=$?
fi
[ "${status}" -eq 1 ] || fail "deferred reaper-release failure returned status ${status} instead of 1"
grep -q 'Unable to release the installer NVRAM transaction reaper' "${TEST_ROOT}/deferred-reaper-output" || fail 'deferred reaper-release failure was not reported'

CLI_MODE="0"
ADGUARD_DEFER_END_OP="0"
for end_status in 0 1 2; do
	rm -f "${TEST_ROOT}/unexpected-interactive-return"
	(
		end_op_message "${end_status}" >"${TEST_ROOT}/interactive-reaper-output.${end_status}" 2>&1
		printf '%s\n' returned >"${TEST_ROOT}/unexpected-interactive-return"
	)
	status=$?
	[ "${status}" -eq 1 ] || fail "interactive reaper-release failure for status ${end_status} exited with status ${status} instead of 1"
	[ ! -e "${TEST_ROOT}/unexpected-interactive-return" ] || fail "interactive reaper-release failure for status ${end_status} returned to its caller"
	grep -q 'Unable to release the installer NVRAM transaction reaper' "${TEST_ROOT}/interactive-reaper-output.${end_status}" || fail "interactive reaper-release failure for status ${end_status} was not reported"
done

printf '%s\n' 'PASS: end_op_message preserves rollback results and releases reapers before every return'
