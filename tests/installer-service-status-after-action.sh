#!/bin/sh
# Verify installer service action status waits before reporting transitional states.

set -u

SCRIPT_PATH="${1:-installer}"
TEST_ROOT="${TMPDIR:-/tmp}/installer-service-status-after-action.$$"
FUNCTIONS_FILE="${TEST_ROOT}/functions"
CALLS_FILE="${TEST_ROOT}/calls"

cleanup() {
	rm -rf "${TEST_ROOT}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
mkdir -p "${TEST_ROOT}" || fail 'could not create test directory'

sed -n '/^adguard_service_status_after_action() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" ||
	fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTIONS_FILE}" ] || fail 'service status helper was not found'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

INFO='Info:'
ADGUARDHOME_WAIT_TIMEOUT=60
PROCESS_STATE='stopped'
PROCESS_COUNT='0'
SLEEP_CALLS=0

PTXT() {
	printf '%s\n' "$*" >>"${CALLS_FILE}"
}

sleep() {
	SLEEP_CALLS="$((SLEEP_CALLS + 1))"
	if [ "${START_AFTER_SLEEP:-0}" -gt 0 ] && [ "${SLEEP_CALLS}" -ge "${START_AFTER_SLEEP}" ]; then
		PROCESS_STATE='running'
		PROCESS_COUNT='1'
	fi
	if [ "${STOP_AFTER_SLEEP:-0}" -gt 0 ] && [ "${SLEEP_CALLS}" -ge "${STOP_AFTER_SLEEP}" ]; then
		PROCESS_STATE='stopped'
		PROCESS_COUNT='0'
	fi
}

agh_is_running() {
	[ "${PROCESS_STATE}" = 'running' ]
}

agh_process_count() {
	printf '%s\n' "${PROCESS_COUNT}"
}

agh_check() {
	printf '%s\n' 'check' >>"${CALLS_FILE}"
}

: >"${CALLS_FILE}"
PROCESS_STATE='stopped'
PROCESS_COUNT='0'
START_AFTER_SLEEP=2
STOP_AFTER_SLEEP=0
SLEEP_CALLS=0
adguard_service_status_after_action restart || fail 'restart helper did not wait for a delayed running process'
grep -q 'Waiting for AdGuardHome to report running state after restart' "${CALLS_FILE}" ||
	fail 'restart helper did not print the restart wait message'
[ "${SLEEP_CALLS}" -eq 2 ] || fail 'restart helper did not poll until the process became running'
grep -q '^check$' "${CALLS_FILE}" || fail 'restart helper did not print service status after settling'
! grep -q 'Restarting\.\.\.' "${CALLS_FILE}" || fail 'restart helper reported transitional state after the process settled'

: >"${CALLS_FILE}"
PROCESS_STATE='stopped'
PROCESS_COUNT='0'
START_AFTER_SLEEP=0
STOP_AFTER_SLEEP=0
SLEEP_CALLS=0
if adguard_service_status_after_action start; then
	fail 'start helper succeeded while the process never appeared'
fi
grep -q 'Waiting for AdGuardHome to report running state after start' "${CALLS_FILE}" ||
	fail 'start helper did not print the start wait message'
grep -q 'Restarting\.\.\.' "${CALLS_FILE}" || fail 'start helper did not report the transitional restart state'
[ "${SLEEP_CALLS}" -eq 5 ] || fail 'start helper did not cap the short poll at five seconds'
! grep -q '^check$' "${CALLS_FILE}" || fail 'start helper printed final status before the process settled'

: >"${CALLS_FILE}"
PROCESS_STATE='running'
PROCESS_COUNT='1'
START_AFTER_SLEEP=0
STOP_AFTER_SLEEP=3
SLEEP_CALLS=0
adguard_service_status_after_action stop || fail 'stop helper did not wait for a delayed stopped process'
grep -q 'Waiting for AdGuardHome to stop cleanly' "${CALLS_FILE}" ||
	fail 'stop helper did not print the stop wait message'
[ "${SLEEP_CALLS}" -eq 3 ] || fail 'stop helper did not poll until the process disappeared'
grep -q '^check$' "${CALLS_FILE}" || fail 'stop helper did not print service status after settling'

: >"${CALLS_FILE}"
PROCESS_STATE='running'
PROCESS_COUNT='1'
START_AFTER_SLEEP=0
STOP_AFTER_SLEEP=0
SLEEP_CALLS=0
if adguard_service_status_after_action stop; then
	fail 'stop helper succeeded while the process remained active'
fi
grep -q 'Stopping\.\.\.' "${CALLS_FILE}" || fail 'stop helper did not report the transitional stopping state'
[ "${SLEEP_CALLS}" -eq 5 ] || fail 'stop helper did not cap the short poll at five seconds'
! grep -q '^check$' "${CALLS_FILE}" || fail 'stop helper printed final status before the process stopped'

printf '%s\n' 'PASS: installer service status helper waits through transitional states'
