#!/bin/sh
# Verify failed monitor recovery attempts are rate-limited instead of spinning.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
FUNCTION_FILE="${TMPDIR:-/tmp}/monitor-retry-backoff.$$.functions"
CALLS_FILE="${TMPDIR:-/tmp}/monitor-retry-backoff.$$.calls"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	rm -f "${FUNCTION_FILE}" "${CALLS_FILE}"
	exit 1
}

[ -f "${SCRIPT_PATH}" ] || fail "manager script not found: ${SCRIPT_PATH}"
sed -n \
	'/^agh_timestamp() {$/,/^}$/p; /^agh_log() {$/,/^}$/p; /^start_monitor() {$/,/^}$/p' \
	"${SCRIPT_PATH}" >"${FUNCTION_FILE}" || fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTION_FILE}" ] || fail 'could not extract start_monitor function'

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

ADGUARDHOME_BINARY='/bin/sh'
NAME='S99AdGuardHome'
PROCS='AdGuardHome'
MONITOR_STATE='running'
: >"${CALLS_FILE}"

adguardhome_run() {
	printf '%s\n' "adguardhome_run $1" >>"${CALLS_FILE}"
	return 1
}

check_dns_environment() {
	printf '%s\n' "check_dns_environment $1" >>"${CALLS_FILE}"
}

logger() {
	printf '%s\n' "logger $*" >>"${CALLS_FILE}"
}

pidof() {
	return 1
}

service_wait() {
	return 0
}

sleep() {
	printf '%s\n' "sleep $1" >>"${CALLS_FILE}"
	MONITOR_STATE='stop'
}

timezone() {
	:
}

set +u
start_monitor
set -u

[ "$(grep -c '^adguardhome_run start_adguardhome$' "${CALLS_FILE}")" -eq 1 ] || fail 'monitor retried startup before the recovery delay'
grep -q '^sleep 10s$' "${CALLS_FILE}" || fail 'monitor did not wait 10 seconds after failed recovery'
grep -q 'start_monitor: state=running action=check_process reason=process_missing result=dead retry=10' "${CALLS_FILE}" || fail 'monitor did not report the retry delay'
grep -q '^adguardhome_run stop_adguardhome$' "${CALLS_FILE}" || fail 'test monitor did not stop cleanly after the retry delay'

rm -f "${FUNCTION_FILE}" "${CALLS_FILE}"
printf '%s\n' 'PASS: monitor rate-limits failed recovery attempts'
