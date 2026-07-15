#!/bin/sh
# Verify initial setup bind address selection keeps LAN DNS wildcard-bound while resolving the WebUI address.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-bind-addresses.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions"

cleanup() {
	rm -rf "${TMP_ROOT}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"
mkdir -p "${TMP_ROOT}" || fail 'could not create test directory'

sed -n '/^setup_resolve_bind_addresses() {$/,/^setup_AdGuardHome_impl() {$/p' "${SCRIPT_PATH}" | sed '$d' >"${FUNCTIONS_FILE}" ||
	fail 'could not extract bind address helper'
[ -s "${FUNCTIONS_FILE}" ] || fail 'bind address helper extraction was empty'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

ERROR='Error:'
WEB_PORT=3000

PTXT() {
	printf '%s\n' "$@"
}

ai_have_cmd() {
	[ "${IP_AVAILABLE:-0}" -eq 1 ] && [ "$1" = "ip" ]
}

ip() {
	case "$*" in
		'-o -4 addr list br0')
			[ -n "${IPV4_FROM_IP:-}" ] && printf '1: br0    inet %s/24 brd 192.168.50.255 scope global br0\n' "${IPV4_FROM_IP}"
			;;
		*) return 1 ;;
	esac
}

nvram() {
	case "${1:-}:${2:-}" in
		get:lan_ifname) printf '%s\n' "${LAN_IFNAME:-}" ;;
		get:lan_ipaddr) printf '%s\n' "${IPV4_FROM_NVRAM:-}" ;;
		*) return 1 ;;
	esac
}

reset_inputs() {
	ADGUARD_INSTALL_MODE=""
	IP_AVAILABLE=0
	LAN_IFNAME=""
	IPV4_FROM_IP=""
	IPV4_FROM_NVRAM=""
	SETUP_WEB_ADDRESS="preset"
	SETUP_DNS_BIND_HOST="preset"
}

assert_bind_values() {
	case_name="$1"
	expected_web="$2"
	expected_dns4="$3"
	[ "${SETUP_WEB_ADDRESS:-}" = "${expected_web}" ] || fail "${case_name}: expected web ${expected_web}, got ${SETUP_WEB_ADDRESS:-empty}"
	[ "${SETUP_DNS_BIND_HOST:-}" = "${expected_dns4}" ] || fail "${case_name}: expected DNS IPv4 ${expected_dns4}, got ${SETUP_DNS_BIND_HOST:-empty}"
}

reset_inputs
ADGUARD_INSTALL_MODE=wan
setup_resolve_bind_addresses >/dev/null || fail 'WAN bind resolution failed'
assert_bind_values wan '0.0.0.0:3000' '0.0.0.0'

reset_inputs
ADGUARD_INSTALL_MODE=lan
IP_AVAILABLE=1
LAN_IFNAME=br0
IPV4_FROM_IP=192.168.50.1
IPV4_FROM_NVRAM=192.168.1.1
setup_resolve_bind_addresses >/dev/null || fail 'LAN bind resolution from ip failed'
assert_bind_values lan-ip '192.168.50.1:3000' '0.0.0.0'
[ "${SETUP_DNS_BIND_HOST:-}" != "${IPV4_FROM_IP}" ] || fail 'LAN DNS bind was pinned to the primary LAN IPv4 address instead of remaining wildcard-bound'

reset_inputs
ADGUARD_INSTALL_MODE=lan
IP_AVAILABLE=1
LAN_IFNAME=br0
IPV4_FROM_NVRAM=192.168.1.1
setup_resolve_bind_addresses >/dev/null || fail 'LAN bind resolution from nvram fallback failed'
assert_bind_values lan-nvram '192.168.1.1:3000' '0.0.0.0'
[ "${SETUP_DNS_BIND_HOST:-}" != "${IPV4_FROM_NVRAM}" ] || fail 'LAN DNS bind was pinned to the nvram LAN IPv4 address instead of remaining wildcard-bound'

reset_inputs
ADGUARD_INSTALL_MODE=lan
IP_AVAILABLE=1
LAN_IFNAME=br0
if setup_resolve_bind_addresses >/dev/null 2>&1; then
	fail 'LAN bind resolution succeeded without IPv4 address'
fi

printf '%s\n' 'PASS: installer bind address resolution keeps LAN DNS wildcard-bound while resolving the WebUI address'
