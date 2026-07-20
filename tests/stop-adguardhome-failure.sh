#!/bin/sh
# Verify runtime stop failures are returned after DNS recovery is attempted.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
TEST_ROOT="${TMPDIR:-/tmp}/stop-adguardhome-failure.$$"
FUNCTION_FILE="${TEST_ROOT}/function"
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
mkdir -p "${TEST_ROOT}" || fail "could not create test directory"

sed -n '/^agh_timestamp() {$/,/^}$/p; /^agh_log() {$/,/^}$/p; /^adguard_restart_dnsmasq_if_managed() {$/,/^}$/p; /^stop_adguardhome() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" ||
	fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTION_FILE}" ] || fail "stop_adguardhome function was not found"

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

# adguard_dnsmasq_managed reports that DNSmasq is managed by AdGuard Home.
adguard_dnsmasq_managed() {
	return 0
}

PROCS="AdGuardHome"
NAME="AdGuardHome-test"
WORK_DIR="${TEST_ROOT}/work"
RUNNING="1"
LOWER_STOP_STATUS="0"
LOWER_KILL_STATUS="0"
SERVICE_STATUS="0"

canonical_path() {
	return 1
}

logger() {
	printf '%s\n' "logger $*" >>"${CALLS_FILE}"
}

lower_script() {
	printf '%s\n' "lower_script $1" >>"${CALLS_FILE}"
	case "$1" in
		stop) return "${LOWER_STOP_STATUS}" ;;
		kill) return "${LOWER_KILL_STATUS}" ;;
	esac
	return 0
}

pidof() {
	[ "${RUNNING}" -eq 1 ] && printf '%s\n' 123
	return 0
}

service() {
	printf '%s\n' "service $*" >>"${CALLS_FILE}"
	return "${SERVICE_STATUS}"
}

service_wait() {
	return 0
}

: >"${CALLS_FILE}"
if stop_adguardhome; then
	fail "stop_adguardhome reported success while AdGuardHome remained active"
fi
grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" ||
	fail "stop failure did not attempt to restore dnsmasq"
grep -q 'reason=process_still_active' "${CALLS_FILE}" ||
	fail "persistent process failure was not logged"

: >"${CALLS_FILE}"
RUNNING="0"
SERVICE_STATUS="1"
if stop_adguardhome; then
	fail "stop_adguardhome hid a failed dnsmasq restart"
fi
grep -q 'reason=service_restart_failed' "${CALLS_FILE}" ||
	fail "dnsmasq restart failure was not logged"

: >"${CALLS_FILE}"
SERVICE_STATUS="0"
stop_adguardhome || fail "clean stopped-state handling returned failure"

printf '%s\n' "PASS: runtime stop failures propagate after DNS recovery"
