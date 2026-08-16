#!/bin/sh
# Verify primary LAN address selection rejects unstable addresses during renumbering.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
TMP_FILE="${TMPDIR:-/tmp}/lan-primary-address-selection.$$"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap 'rm -f "${TMP_FILE}"' 0
trap 'rm -f "${TMP_FILE}"; exit 1' HUP INT TERM

sed -n '/^interface_ipv4_addr() {$/,/^}$/p; /^interface_ipv6_addr() {$/,/^}$/p' "${SCRIPT_PATH}" >"${TMP_FILE}" ||
	fail 'could not extract primary address helpers'
# shellcheck disable=SC1090
. "${TMP_FILE}"

have_cmd() { [ "$1" = ip ]; }

ip() {
	case "$*" in
		'-o -4 addr list br0 scope global')
			printf '%s\n' \
				'1: br0 inet 192.168.50.1/24 scope global deprecated br0' \
				'1: br0 inet 192.168.60.1/24 scope global br0' \
				'1: br0 inet 192.168.60.1/24 scope global secondary br0'
			;;
		'-o -6 addr list br0 scope global')
			printf '%s\n' \
				'1: br0 inet6 2001:db8::99/64 scope global temporary dynamic' \
				'1: br0 inet6 2001:db8::98/64 scope global tentative' \
				'1: br0 inet6 2001:db8::97/64 scope global deprecated' \
				'1: br0 inet6 2001:db8::60/64 scope global' \
				'1: br0 inet6 2001:db8::60/64 scope global'
			;;
		*) return 1 ;;
	esac
}

[ "$(interface_ipv4_addr br0)" = '192.168.60.1' ] || fail 'renumbering retained a deprecated IPv4 address'
[ "$(interface_ipv6_addr br0)" = '2001:db8::60' ] || fail 'IPv6 selection retained an unstable address'
[ -z "$(interface_ipv4_addr br-vpn)" ] || fail 'VPN bridge supplied the primary LAN address'
[ -z "$(interface_ipv6_addr br-guest)" ] || fail 'guest bridge supplied the primary LAN address'

printf '%s\n' 'PASS: primary LAN address selection rejects unstable and non-primary interface addresses'
