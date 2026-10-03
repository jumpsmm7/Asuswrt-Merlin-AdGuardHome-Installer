#!/bin/sh
# Verify primary LAN address selection rejects unstable addresses during renumbering.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
umask 077
TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/lan-primary-address-selection.XXXXXX")" || {
	printf '%s\n' 'FAIL: could not create secure temporary file' >&2
	exit 1
}

# fail prints a failure message to standard error and exits with status 1.
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

# have_cmd reports whether the requested command is `ip`.
have_cmd() { [ "$1" = ip ]; }

# ip simulates address-listing output for the test interfaces.
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
				'1: br0 inet6 2001:db8::96/64 scope global dadfailed' \
				'1: br0 inet6 2001:db8::61/64 scope global mngtmpaddr' \
				'1: br0 inet6 2001:db8::60/64 scope global'
			;;
		'-o -4 addr list br1 scope global')
			printf '%s\n' \
				'1: br1 inet 192.168.70.1/24 scope global tentative br1' \
				'1: br1 inet 192.168.70.2/24 scope global deprecated br1'
			;;
		'-o -6 addr list br1 scope global')
			printf '%s\n' \
				'1: br1 inet6 2001:db8:1::1/64 scope global tentative' \
				'1: br1 inet6 2001:db8:1::2/64 scope global deprecated dynamic'
			;;
		*) return 1 ;;
	esac
}

[ "$(interface_ipv4_addr br0)" = '192.168.60.1' ] || fail 'renumbering retained a deprecated IPv4 address'
[ "$(interface_ipv6_addr br0)" = '2001:db8::61' ] || fail 'IPv6 selection rejected a stable mngtmpaddr template address'

# When every candidate address is unstable, neither helper falls back to a filtered-out address.
[ -z "$(interface_ipv4_addr br1)" ] || fail 'IPv4 selection returned an address although every candidate was unstable'
[ -z "$(interface_ipv6_addr br1)" ] || fail 'IPv6 selection returned an address although every candidate was unstable'

# Both helpers require a non-empty interface argument.
if interface_ipv4_addr ''; then fail 'interface_ipv4_addr accepted an empty interface argument'; fi
if interface_ipv6_addr ''; then fail 'interface_ipv6_addr accepted an empty interface argument'; fi

# have_cmd simulates an unavailable command for tests.
have_cmd() { return 1; }
[ -z "$(interface_ipv4_addr br0)" ] || fail 'IPv4 selection returned an address without the ip command available'
[ -z "$(interface_ipv6_addr br0)" ] || fail 'IPv6 selection returned an address without the ip command available'

printf '%s\n' 'PASS: primary LAN address selection rejects unstable addresses during renumbering'
