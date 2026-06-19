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
	'/^port_is_valid() {$/,/^}$/p; /^web_port_in_use() {$/,/^}$/p; /^agh_config_valid() {$/,/^}$/p; /^agh_dns_bound() {$/,/^}$/p; /^agh_web_port() {$/,/^}$/p; /^agh_web_bound() {$/,/^}$/p; /^agh_log_start_failure() {$/,/^}$/p; /^agh_startup_check() {$/,/^}$/p; /^agh_startup_ready() {$/,/^}$/p; /^agh_is_running() {$/,/^}$/p' \
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
