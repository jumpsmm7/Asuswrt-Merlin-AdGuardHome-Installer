#!/bin/sh
# Verify a malformed monitor stop snapshot forces dnsmasq restoration semantics.

set -u

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/AdGuardHome.sh"
TEST_ROOT="${TMPDIR:-/tmp}/agh-monitor-stop-config.$$"
FUNCTIONS_FILE="${TEST_ROOT}/functions.sh"
READY_FILE="${TEST_ROOT}/ready"
MODE_FILE="${TEST_ROOT}/mode"
MONITOR_TEST_PID=""

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

cleanup() {
	if [ -n "${MONITOR_TEST_PID:-}" ] && kill -0 "${MONITOR_TEST_PID}" 2>/dev/null; then
		kill -KILL "${MONITOR_TEST_PID}" 2>/dev/null || true
		wait "${MONITOR_TEST_PID}" 2>/dev/null || true
	fi
	rm -rf "${TEST_ROOT}"
}

wait_for_file() {
	_file="$1"
	_attempts=0
	while [ ! -f "${_file}" ] && [ "${_attempts}" -lt 10 ]; do
		command sleep 1
		_attempts="$((_attempts + 1))"
	done
	[ -f "${_file}" ]
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
umask 077
mkdir "${TEST_ROOT}" || fail 'could not create test workspace'

sed -n '/^set_operation_config_defaults() {$/,/^}$/p; /^start_monitor() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" ||
	fail 'could not extract monitor configuration helpers'
[ -s "${FUNCTIONS_FILE}" ] || fail 'monitor configuration helper extraction was empty'
[ "$(grep -c 'CONFIG_DNSMASQ_MODE="enabled"' "${FUNCTIONS_FILE}")" -eq 2 ] ||
	fail 'both monitor stop fallback paths must force managed dnsmasq restoration'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

DEFAULT_ADGUARD_NETCHECK_HOSTS='google.com github.com snbforums.com'
DEFAULT_ADGUARD_NETCHECK_DNS='127.0.0.1'
DEFAULT_ADGUARD_NETCHECK_REQUIRE_HTTP='NO'
DEFAULT_ADGUARD_NETCHECK_TIMEOUT='300'
DEFAULT_ADGUARD_NETCHECK_MODE='wan'
DEFAULT_ADGUARD_PROC_OPTIMIZE='NO'
DEFAULT_ADGUARD_PROC_PROFILE='aggressive'
ADGUARDHOME_BINARY=/bin/sh
PROCS=AdGuardHome

agh_log() {
	[ "${2:-}" != start_monitor ] || : >"${READY_FILE}"
}
service_wait() { return 0; }
check_dns_environment() { :; }
load_operation_config() {
	[ "${1:-}" != stop ] || return 1
	return 0
}
adguardhome_run() {
	case "${1:-}" in
		stop_adguardhome)
			printf '%s\n' "${CONFIG_DNSMASQ_MODE:-unset}" >"${MODE_FILE}"
			;;
	esac
	return 0
}
pidof() {
	[ "${1:-}" = "${PROCS}" ] || return 1
	printf '%s\n' 123
}
timezone() { :; }
adguard_lan_mode() { return 1; }
adguard_refresh_lan_bind_addresses() { return 0; }
netcheck_config() { printf '%s\n' wan; }
sleep() { command sleep 1; }

set +u
start_monitor &
MONITOR_TEST_PID="$!"
set -u
wait_for_file "${READY_FILE}" || fail 'monitor did not reach its running state'
kill -USR1 "${MONITOR_TEST_PID}" || fail 'could not request monitor stop'
wait_for_file "${MODE_FILE}" || fail 'monitor did not execute its stop path'
wait "${MONITOR_TEST_PID}" || fail 'monitor stop path returned failure'
MONITOR_TEST_PID=""

[ "$(cat "${MODE_FILE}")" = enabled ] ||
	fail 'malformed monitor stop configuration did not force dnsmasq restoration'

printf '%s\n' 'PASS: malformed monitor stop configuration forces dnsmasq restoration'
