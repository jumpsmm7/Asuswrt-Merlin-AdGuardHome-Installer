#!/bin/sh
# Verify installer startup readiness retries local socket checks before failing.

set -u

INSTALLER_PATH="${1:-installer}"
TEST_ROOT="${TMPDIR:-/tmp}/installer-startup-readiness.$$"
FUNCTIONS_FILE="${TEST_ROOT}/installer-functions"
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

sed -n \
	'/^port_is_valid() {$/,/^}$/p; /^runtime_port_is_valid() {$/,/^}$/p; /^web_port_in_use() {$/,/^}$/p; /^web_port_owned_by_agh() {$/,/^}$/p; /^agh_config_valid() {$/,/^}$/p; /^agh_dns_bound() {$/,/^}$/p; /^agh_web_port() {$/,/^}$/p; /^agh_web_bound() {$/,/^}$/p; /^agh_log_start_failure() {$/,/^}$/p; /^agh_startup_check() {$/,/^}$/p; /^agh_startup_ready() {$/,/^}$/p; /^agh_complete_startup() {$/,/^}$/p; /^agh_is_running() {$/,/^}$/p' \
	"${INSTALLER_PATH}" >"${FUNCTIONS_FILE}" || fail "could not read ${INSTALLER_PATH}"
[ -s "${FUNCTIONS_FILE}" ] || fail 'installer startup functions were not found'

grep -q '^agh_startup_check() {$' "${FUNCTIONS_FILE}" || fail 'installer has no silent startup check helper'
grep -q 'agh_startup_ready()' "${FUNCTIONS_FILE}" || fail 'installer has no startup readiness helper'

PTXT() {
	printf '%s\n' "$*"
	printf '%s\n' "$*" >>"${CALLS_FILE}"
}

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

ERROR='Error:'
ADGUARDHOME_READY_TIMEOUT=5
AGH_FILE="${TEST_ROOT}/AdGuardHome"
YAML_FILE="${TEST_ROOT}/AdGuardHome.yaml"
CONF_FILE="${TEST_ROOT}/.config"
printf '%s\n' '#!/bin/sh' 'exit 0' >"${AGH_FILE}" || fail 'could not create AdGuardHome stub'
chmod 755 "${AGH_FILE}" || fail 'could not chmod AdGuardHome stub'
printf '%s\n' 'http:' '  address: 0.0.0.0:3000' >"${YAML_FILE}" || fail 'could not create YAML stub'
printf '%s\n' 'ADGUARD_WEBUI_PORT="3000"' >"${CONF_FILE}" || fail 'could not create config stub'

pidof() {
	[ "$1" = AdGuardHome ] || return 1
	[ "${PROCESS_STATE:-running}" = running ] || return 1
	printf '%s\n' 321
}

netstat() {
	case "${READINESS_STATE:-ready}" in
		dns_wait)
			printf '%s\n' 'tcp 0 0 0.0.0.0:3000 0.0.0.0:* LISTEN 321/AdGuardHome'
			;;
		web_taken)
			printf '%s\n' \
				'tcp 0 0 0.0.0.0:53 0.0.0.0:* LISTEN 321/AdGuardHome' \
				'udp 0 0 0.0.0.0:53 0.0.0.0:* 321/AdGuardHome' \
				'tcp 0 0 0.0.0.0:3000 0.0.0.0:* LISTEN 123/httpd'
			;;
		ready_low)
			printf '%s\n' \
				'tcp 0 0 0.0.0.0:53 0.0.0.0:* LISTEN 321/AdGuardHome' \
				'udp 0 0 0.0.0.0:53 0.0.0.0:* 321/AdGuardHome' \
				'tcp 0 0 0.0.0.0:80 0.0.0.0:* LISTEN 321/AdGuardHome'
			;;
		ready)
			printf '%s\n' \
				'tcp 0 0 0.0.0.0:53 0.0.0.0:* LISTEN 321/AdGuardHome' \
				'udp 0 0 0.0.0.0:53 0.0.0.0:* 321/AdGuardHome' \
				'tcp 0 0 0.0.0.0:3000 0.0.0.0:* LISTEN 321/AdGuardHome'
			;;
	esac
}

sleep() {
	SLEEP_CALLS="$((SLEEP_CALLS + 1))"
	if [ "${READY_AFTER_SLEEP:-0}" -gt 0 ] && [ "${SLEEP_CALLS}" -ge "${READY_AFTER_SLEEP}" ]; then
		READINESS_STATE=ready
	fi
	:
}

: >"${CALLS_FILE}"
PROCESS_STATE=running
READINESS_STATE=dns_wait
READY_AFTER_SLEEP=3
SLEEP_CALLS=0
agh_startup_ready || fail 'startup readiness did not retry until local sockets were ready'
[ "${SLEEP_CALLS}" -eq 3 ] || fail 'startup readiness used an unexpected retry count'
! grep -q 'startup failed' "${CALLS_FILE}" || fail 'startup readiness logged a failure before retrying to success'

: >"${CALLS_FILE}"
READINESS_STATE=dns_wait
READY_AFTER_SLEEP=0
ADGUARDHOME_READY_TIMEOUT=2
SLEEP_CALLS=0
if agh_startup_ready; then
	fail 'startup readiness succeeded while DNS remained unbound'
fi
[ "${SLEEP_CALLS}" -eq 2 ] || fail 'startup readiness did not honor the bounded retry timeout'
[ "$(grep -c 'DNS is not bound' "${CALLS_FILE}")" -eq 1 ] || fail 'startup readiness did not log one final DNS failure'

: >"${CALLS_FILE}"
READINESS_STATE=web_taken
READY_AFTER_SLEEP=0
ADGUARDHOME_READY_TIMEOUT=1
SLEEP_CALLS=0
if agh_startup_ready; then
	fail 'startup readiness succeeded while another process owned the WebUI port'
fi
[ "${SLEEP_CALLS}" -eq 1 ] || fail 'startup readiness did not retry the WebUI ownership check'
[ "$(grep -c 'WebUI port is unavailable' "${CALLS_FILE}")" -eq 1 ] || fail 'startup readiness did not log one final WebUI ownership failure'

: >"${CALLS_FILE}"
PROCESS_STATE=stopped
READINESS_STATE=dns_wait
READY_AFTER_SLEEP=0
ADGUARDHOME_READY_TIMEOUT=5
SLEEP_CALLS=0
if agh_startup_ready; then
	fail 'startup readiness succeeded after AdGuardHome exited'
fi
[ "${SLEEP_CALLS}" -eq 0 ] || fail 'startup readiness kept retrying after AdGuardHome exited'
[ "$(grep -c 'process is not running' "${CALLS_FILE}")" -eq 1 ] || fail 'startup readiness did not log one final stopped-process failure'
PROCESS_STATE=running

printf '%s\n' 'http:' '  address: 0.0.0.0:80' >"${YAML_FILE}" || fail 'could not update YAML stub'
: >"${CALLS_FILE}"
READINESS_STATE=ready_low
READY_AFTER_SLEEP=0
ADGUARDHOME_READY_TIMEOUT=1
SLEEP_CALLS=0
agh_startup_ready || fail 'startup readiness rejected a valid low YAML WebUI port'
[ "${SLEEP_CALLS}" -eq 0 ] || fail 'startup readiness retried despite low YAML WebUI port being ready'

# Complete startup must never start over an unconfirmed stop, and a failed
# initial start must not proceed into the restart validation phase.
STARTUP_SEQUENCE_FILE="${TEST_ROOT}/startup-sequence"
ptxt_phase() { :; }
ptxt_step() { :; }
ptxt_ok() { :; }
ptxt_fail() { printf '%s\n' "$*" >>"${STARTUP_SEQUENCE_FILE}"; }
agh_stop() { printf '%s\n' stop >>"${STARTUP_SEQUENCE_FILE}"; return "${STOP_STATUS:-0}"; }
agh_start() { printf '%s\n' start >>"${STARTUP_SEQUENCE_FILE}"; return "${START_STATUS:-0}"; }
agh_restart() { printf '%s\n' restart >>"${STARTUP_SEQUENCE_FILE}"; return "${RESTART_STATUS:-0}"; }
agh_start_error() { printf '%s\n' start-error >>"${STARTUP_SEQUENCE_FILE}"; }

: >"${STARTUP_SEQUENCE_FILE}"
STOP_STATUS=1
START_STATUS=0
RESTART_STATUS=0
if agh_complete_startup; then
	fail 'complete startup ignored an unconfirmed stopped state'
fi
[ "$(sed -n '1p' "${STARTUP_SEQUENCE_FILE}")" = stop ] || fail 'complete startup did not attempt its initial stop'
[ "$(wc -l <"${STARTUP_SEQUENCE_FILE}")" -eq 2 ] || fail 'complete startup continued after the initial stop failed'

: >"${STARTUP_SEQUENCE_FILE}"
STOP_STATUS=0
START_STATUS=1
if agh_complete_startup; then
	fail 'complete startup ignored initial start failure'
fi
[ "$(grep -c '^restart$' "${STARTUP_SEQUENCE_FILE}")" -eq 0 ] || fail 'complete startup restarted after the initial start failed'

: >"${STARTUP_SEQUENCE_FILE}"
START_STATUS=0
RESTART_STATUS=0
agh_complete_startup || fail 'complete startup rejected a successful stop/start/restart lifecycle'
[ "$(cat "${STARTUP_SEQUENCE_FILE}")" = "$(printf '%s\n' stop start restart)" ] ||
	fail 'complete startup did not preserve the stop/start/restart lifecycle order'

printf '%s\n' 'PASS: installer startup readiness and lifecycle checks are fail-closed'
