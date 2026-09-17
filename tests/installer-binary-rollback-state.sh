#!/bin/sh
# Verify binary rollback and service-restart state survives failed recovery attempts.

set -u

SCRIPT_PATH="${1:-installer}"
TEST_ROOT="${TMPDIR:-/tmp}/installer-binary-rollback-state.$$"

# fail reports a regression failure and exits the test.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

# cleanup removes the rollback-state fixture.
cleanup() {
	rm -rf "${TEST_ROOT}"
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
mkdir -p "${TEST_ROOT}" || fail 'could not create rollback-state fixture'
sed -n \
	-e '/^on_installer_exit() {$/,/^}/p' \
	-e '/^adguard_restart_after_failed_replace() {$/,/^}/p' \
	-e '/^adguard_restart_after_install_abort() {$/,/^}/p' \
	-e '/^adguard_install_signal_traps_disable() {$/,/^}/p' \
	-e '/^adguard_install_abort_trap_disable() {$/,/^}/p' \
	-e '/^adguard_install_abort_trap_disable_preserve_defer() {$/,/^}/p' \
	-e '/^adguard_install_abort_on_signal() {$/,/^}/p' \
	-e '/^adguard_restore_after_failed_replace() {$/,/^}/p' \
	-e '/^adguard_committed_binary_cleanup_finalize() {$/,/^}/p' \
	"${SCRIPT_PATH}" >"${TEST_ROOT}/helpers" || fail 'could not extract binary rollback helpers'
[ -s "${TEST_ROOT}/helpers" ] || fail 'binary rollback helper extraction was empty'
# shellcheck disable=SC1090
. "${TEST_ROOT}/helpers"

ERROR='Error:'
INFO='Info:'
WARNING='Warning:'
BASE_DIR="${TEST_ROOT}"
TARG_DIR="${TEST_ROOT}/AdGuardHome"
AGH_FILE="${TARG_DIR}/AdGuardHome"
ROLLBACK_RESULT_FILE="${TEST_ROOT}/rollback-result"
CALLS_FILE="${TEST_ROOT}/calls"
mkdir -p "${TARG_DIR}" || fail 'could not create rollback target'

# PTXT records installer messages for later assertions.
PTXT() { printf '%s\n' "$*" >>"${CALLS_FILE}"; }
# rollback_result_write records rollback outcomes for later assertions.
rollback_result_write() { printf '%s\n' "rollback:$*" >>"${CALLS_FILE}"; }
# rollback_result_notice suppresses fixture-only user notifications.
rollback_result_notice() { :; }
# nvram_transaction_lock_owned reports that the fixture holds no NVRAM lock.
nvram_transaction_lock_owned() { return 1; }
# nvram_transaction_lock_release accepts the fixture's no-lock cleanup.
nvram_transaction_lock_release() { return 0; }
# cleanup_api_files suppresses unrelated API-file cleanup in the fixture.
cleanup_api_files() { :; }
# installer_cleanup_tmp_file suppresses unrelated temporary-file cleanup.
installer_cleanup_tmp_file() { :; }
# adguard_committed_binary_cleanup_retry reports no pending committed backup.
adguard_committed_binary_cleanup_retry() { return 0; }
# all_event_scripts_transaction_rollback suppresses unrelated hook rollback.
all_event_scripts_transaction_rollback() { :; }
# clear_screen suppresses terminal output in the fixture.
clear_screen() { :; }
# end_op_message suppresses terminal completion output in the fixture.
end_op_message() { :; }
# agh_is_running reports that no AdGuardHome process is running.
agh_is_running() { return 1; }
MODE_MIGRATION_YAML_FILE_BACKUP=""
EVENT_SCRIPTS_ACTIVE_SNAPSHOT=""
ADGUARD_RESTORE_ACTIVE=0
ADGUARD_DEFER_END_OP=0

printf '%s\n' new >"${AGH_FILE}"
OLD_BINARY="${TARG_DIR}/.AdGuardHome.previous.101"
printf '%s\n' old >"${OLD_BINARY}"
ADGUARD_INSTALL_REPLACE_ACTIVE=1
ADGUARD_INSTALL_OLD_BINARY="${OLD_BINARY}"
ADGUARD_INSTALL_STAGE_DIR=""
ADGUARD_INSTALL_WAS_RUNNING=1
ADGUARD_INSTALL_RESTART_PENDING=0
START_CALLS=0
STOP_CALLS=0
MOVE_CALLS=0
# agh_process_count reports that the initial replacement process is stopped.
agh_process_count() { printf '%s\n' 0; }
# agh_stop records attempts to stop the initial replacement process.
agh_stop() { STOP_CALLS="$((STOP_CALLS + 1))"; }
# agh_start fails once before accepting the exit-cleanup retry.
agh_start() {
	START_CALLS="$((START_CALLS + 1))"
	[ "${START_CALLS}" -gt 1 ]
}
# mv records binary restoration before delegating to the system command.
mv() {
	MOVE_CALLS="$((MOVE_CALLS + 1))"
	/bin/mv "$@"
}
if adguard_restore_after_failed_replace "${OLD_BINARY}" 1; then
	fail 'initial rollback restart failure was reported as success'
fi
[ "$(cat "${AGH_FILE}")" = old ] || fail 'initial rollback did not restore the old binary'
[ "${ADGUARD_INSTALL_REPLACE_ACTIVE}" = 0 ] || fail 'restored binary remained eligible for a second rollback'
[ "${ADGUARD_INSTALL_RESTART_PENDING}" = 1 ] || fail 'failed restart did not retain pending service recovery state'
[ "${MOVE_CALLS}" -eq 1 ] || fail 'initial rollback did not move the old binary exactly once'
on_installer_exit || fail 'EXIT cleanup did not recover the pending service restart'
[ "${START_CALLS}" -eq 2 ] || fail 'EXIT cleanup did not retry the service restart'
[ "${MOVE_CALLS}" -eq 1 ] || fail 'EXIT cleanup moved the restored binary again'
[ "${ADGUARD_INSTALL_RESTART_PENDING}" = 0 ] || fail 'successful restart retry retained pending state'

printf '%s\n' failed-fresh >"${AGH_FILE}"
OLD_BINARY="${TARG_DIR}/.AdGuardHome.previous.202"
ADGUARD_INSTALL_REPLACE_ACTIVE=1
ADGUARD_INSTALL_OLD_BINARY="${OLD_BINARY}"
ADGUARD_INSTALL_WAS_RUNNING=0
ADGUARD_INSTALL_RESTART_PENDING=0
START_CALLS=0
# agh_start records any unexpected restart of an initially stopped service.
agh_start() { START_CALLS="$((START_CALLS + 1))"; }
adguard_restore_after_failed_replace "${OLD_BINARY}" 0 || fail 'stopped-service rollback failed'
[ "${START_CALLS}" -eq 0 ] || fail 'rollback of a stopped service attempted a restart'
[ "${ADGUARD_INSTALL_RESTART_PENDING}" = 0 ] || fail 'stopped-service rollback retained restart state'

printf '%s\n' new >"${AGH_FILE}"
OLD_BINARY="${TARG_DIR}/.AdGuardHome.previous.303"
printf '%s\n' old >"${OLD_BINARY}"
ADGUARD_INSTALL_REPLACE_ACTIVE=1
ADGUARD_INSTALL_OLD_BINARY="${OLD_BINARY}"
ADGUARD_INSTALL_WAS_RUNNING=1
# agh_process_count reports a replacement process for the stop-failure case.
agh_process_count() { printf '%s\n' 1; }
# agh_stop injects a persistent process-stop failure.
agh_stop() {
	STOP_CALLS="$((STOP_CALLS + 1))"
	return 1
}
if adguard_restore_after_failed_replace "${OLD_BINARY}" 1; then
	fail 'monitor stop failure was reported as successful rollback'
fi
[ "$(cat "${AGH_FILE}")" = new ] || fail 'monitor stop failure altered the replacement binary'
[ -f "${OLD_BINARY}" ] || fail 'monitor stop failure removed the old binary backup'
[ "${ADGUARD_INSTALL_REPLACE_ACTIVE}" = 1 ] || fail 'monitor stop failure cleared rollback state'

STOP_CALLS=0
# agh_stop fails once before accepting the exit-cleanup retry.
agh_stop() {
	STOP_CALLS="$((STOP_CALLS + 1))"
	[ "${STOP_CALLS}" -gt 1 ]
}
# agh_start accepts the restart after the delayed binary restoration.
agh_start() { return 0; }
adguard_install_abort_on_signal
[ "${ADGUARD_INSTALL_REPLACE_ACTIVE}" = 1 ] || fail 'signal stop failure cleared binary rollback state'
[ "${ADGUARD_INSTALL_OLD_BINARY}" = "${OLD_BINARY}" ] || fail 'signal stop failure lost the old binary path'
on_installer_exit || fail 'EXIT cleanup did not retry signal-driven binary rollback'
[ "$(cat "${AGH_FILE}")" = old ] || fail 'EXIT cleanup did not restore the binary after signal stop failure'
[ "${ADGUARD_INSTALL_REPLACE_ACTIVE}" = 0 ] || fail 'successful EXIT rollback retained replacement state'

printf '%s\n' committed-new >"${AGH_FILE}"
OLD_BINARY="${TARG_DIR}/.AdGuardHome.previous.404"
printf '%s\n' committed-old >"${OLD_BINARY}"
ADGUARD_INSTALL_REPLACE_ACTIVE=1
ADGUARD_INSTALL_OLD_BINARY="${OLD_BINARY}"
ADGUARD_INSTALL_COMMIT_PENDING=1
ADGUARD_COMMITTED_BINARY_CLEANUP_PENDING=""
ADGUARD_INSTALL_WAS_RUNNING=1
EVENT_SCRIPTS_ACTIVE_SNAPSHOT=""
MOVE_CALLS=0
# adguard_committed_binary_cleanup_record_write verifies signal recovery publishes the cleanup path before writing its record.
adguard_committed_binary_cleanup_record_write() {
	[ "${ADGUARD_COMMITTED_BINARY_CLEANUP_PENDING}" = "${OLD_BINARY}" ] ||
		fail 'signal recovery did not publish committed cleanup state before writing its record'
	printf '%s\n' "$1" >"${BASE_DIR}/.AdGuardHome.binary-cleanup"
}
# adguard_committed_binary_cleanup_retry simulates deletion remaining pending after the signal.
adguard_committed_binary_cleanup_retry() { return 1; }
# agh_is_running keeps signal recovery from restarting the committed service fixture.
agh_is_running() { return 0; }
# This state models a signal after the commit marker is set but before the pending cleanup path is assigned.
adguard_install_abort_on_signal
[ "$(cat "${AGH_FILE}")" = committed-new ] || fail 'post-commit signal restored the previous binary'
[ "${MOVE_CALLS}" -eq 0 ] || fail 'post-commit signal invoked binary rollback'
[ "${ADGUARD_INSTALL_REPLACE_ACTIVE}" = 0 ] || fail 'post-commit signal retained rollback eligibility'
[ -f "${BASE_DIR}/.AdGuardHome.binary-cleanup" ] || fail 'post-commit signal failed to retain durable cleanup state'
[ -f "${OLD_BINARY}" ] || fail 'post-commit signal lost the retained cleanup backup'

printf '%s\n' 'PASS: binary rollback state survives stop and restart failures'
