#!/bin/sh
# Verify LAN mode gates service IPSET paths before locks, rewrites, or restarts.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
FUNCTION_FILE="${TMPDIR:-/tmp}/ipset-lan-functions.$$"
CALLS_FILE="${TMPDIR:-/tmp}/ipset-lan-calls.$$"

cleanup() {
	rm -f "${FUNCTION_FILE}" "${CALLS_FILE}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

sed -n '/^agh_timestamp() {$/,/^}$/p; /^agh_log() {$/,/^}$/p; /^IPSet_Migrate() {$/,/^}$/p; /^IPSet_Enabled() {$/,/^}$/p; /^IPSet_Refresh() {$/,/^}$/p; /^IPSet_Setup_For_Start() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" || fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTION_FILE}" ] || fail 'LAN IPSET functions were not found'

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

adguard_lan_mode() {
	[ "${INSTALL_MODE:-wan}" = "lan" ]
}

adguard_ipset_allowed() {
	! adguard_lan_mode
}

agh_log() {
	printf '%s\n' "log $1 $2 $3" >>"${CALLS_FILE}"
}

conf_value() {
	printf '%s\n' "${IPSET_CONFIG:-YES}"
}

IPSet_Disable_Managed() {
	printf '%s\n' IPSet_Disable_Managed >>"${CALLS_FILE}"
	return "${DISABLE_STATUS:-0}"
}

IPSet_Lock() {
	printf '%s\n' IPSet_Lock >>"${CALLS_FILE}"
	return 1
}

IPSet_Supported() {
	printf '%s\n' IPSet_Supported >>"${CALLS_FILE}"
	return 0
}

lower_script() {
	printf '%s\n' "lower_script $1" >>"${CALLS_FILE}"
	return 0
}

pidof() {
	printf '%s\n' 1234
	return 0
}

IPSET_FILE=/tmp/ipset.conf
IPSET_USER_FILE=/tmp/ipset.user
YAML_FILE=/tmp/AdGuardHome.yaml
PROCS=AdGuardHome
NAME=AdGuardHome

INSTALL_MODE=lan
DISABLE_STATUS=0
: >"${CALLS_FILE}"
if IPSet_Enabled; then
	fail 'IPSet_Enabled returned true in LAN mode'
fi
[ ! -s "${CALLS_FILE}" ] || fail 'IPSet_Enabled caused side effects in LAN mode'

IPSet_Refresh || fail 'LAN refresh did not return success'
ACTUAL="$(cat "${CALLS_FILE}")"
case "${ACTUAL}" in
	*IPSet_Lock* | *IPSet_Supported* | *lower_script*) fail "LAN refresh touched managed path: ${ACTUAL}" ;;
esac
case "${ACTUAL}" in
	*'reason=lan_mode'*) : ;;
	*) fail 'LAN refresh did not log skip reason' ;;
esac

: >"${CALLS_FILE}"
IPSet_Migrate || fail 'LAN migration did not return success'
[ "$(cat "${CALLS_FILE}")" = 'IPSet_Disable_Managed' ] || fail 'LAN migration did not attempt managed cleanup'

DISABLE_STATUS=1
: >"${CALLS_FILE}"
IPSet_Migrate || fail 'LAN migration treated failed cleanup as fatal'
ACTUAL="$(cat "${CALLS_FILE}")"
case "${ACTUAL}" in
	*IPSet_Disable_Managed*'reason=lan_mode_remove_failed'*) : ;;
	*) fail "LAN migration did not log non-fatal cleanup failure: ${ACTUAL}" ;;
esac

: >"${CALLS_FILE}"
IPSet_Setup_For_Start || fail 'LAN startup setup treated failed cleanup as fatal'
ACTUAL="$(cat "${CALLS_FILE}")"
case "${ACTUAL}" in
	*IPSet_Disable_Managed*'reason=lan_mode_remove_failed'*) : ;;
	*) fail "LAN startup setup did not log non-fatal cleanup failure: ${ACTUAL}" ;;
esac
case "${ACTUAL}" in
	*IPSet_Lock* | *IPSet_Supported*) fail "LAN startup setup touched lock/support path: ${ACTUAL}" ;;
esac

printf '%s\n' 'PASS: LAN mode skips IPSET locks, rewrites, and restarts while cleanup remains non-fatal'
