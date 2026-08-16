#!/bin/sh
# Verify the private IPv4 bridge DNS fallback chain requires the primary LAN
# interface and threads it through every discovery tier, instead of excluding
# a hardcoded br0.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
umask 077
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/private-ipv4-dns-fallback-chain.XXXXXX")" || {
	printf '%s\n' 'FAIL: could not create secure test directory' >&2
	exit 1
}
FUNCTION_FILE="${TMP_ROOT}/functions"

# cleanup removes the temporary test directory and its contents.
cleanup() {
	rm -rf "${TMP_ROOT}"
}

# fail reports a failure message to standard error and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

sed -n '/^private_ipv4_bridge_dns_options() {$/,/^resolv_conf_is_tmp_mount() {$/p' "${SCRIPT_PATH}" | sed '$d' >"${FUNCTION_FILE}" ||
	fail 'could not extract bridge DNS fallback helpers'
[ -s "${FUNCTION_FILE}" ] || fail 'bridge DNS fallback helper extraction was empty'
# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

# agh_log discards bridge-discovery log lines; only discovery output is under test here.
agh_log() { :; }

# have_cmd reports whether the requested command is available for the test.
have_cmd() { [ "$1" = ip ] || [ "$1" = route ]; }
ip() { return 1; }
# route simulates an unavailable legacy route command by returning failure.
route() { return 1; }

if private_ipv4_bridge_dns_options; then
	fail 'private_ipv4_bridge_dns_options accepted a missing LAN interface argument'
fi
if private_ipv4_bridge_dns_options_with_fallbacks; then
	fail 'private_ipv4_bridge_dns_options_with_fallbacks accepted a missing LAN interface argument'
fi
if private_ipv4_route_dns_options; then
	fail 'private_ipv4_route_dns_options accepted a missing LAN interface argument'
fi
if private_ipv4_legacy_route_dns_options; then
	fail 'private_ipv4_legacy_route_dns_options accepted a missing LAN interface argument'
fi

# have_cmd reports whether the requested command is available for the test.
have_cmd() { [ "$1" = ip ]; }
# ip simulates the mocked network command used to provide route discovery output for bridge interfaces.
ip() {
	case "$*" in
		'-o -4 addr show scope global'|'-4 addr show scope global') return 1 ;;
		'-o -4 addr show dev br5 scope global') printf '%s\n' '1: br5 inet 10.0.5.1/24 scope global br5' ;;
		'-o -4 addr show dev br7 scope global') printf '%s\n' '2: br7 inet 10.0.7.1/24 scope global br7' ;;
		'route show')
			printf '%s\n' \
				'10.0.5.0/24 dev br5 proto kernel scope link src 10.0.5.1' \
				'10.0.7.0/24 dev br7 proto kernel scope link src 10.0.7.1'
			;;
		*) return 1 ;;
	esac
}

route_options="$(private_ipv4_route_dns_options br5)" || fail 'tier-2 route discovery failed for a non-br0 primary interface'
[ "${route_options}" = 'br7 10.0.7.1' ] ||
	fail "tier-2 route discovery did not exclude the actual primary interface br5 (got: ${route_options})"

route_options="$(private_ipv4_route_dns_options br7)" || fail 'tier-2 route discovery failed when br7 was the primary interface'
[ "${route_options}" = 'br5 10.0.5.1' ] ||
	fail "tier-2 route discovery did not switch exclusion when the primary interface changed (got: ${route_options})"

route_options="$(private_ipv4_route_dns_options br0)" || fail 'tier-2 route discovery failed when br0 was a secondary bridge'
[ "${route_options}" = "$(printf '%s\n' 'br5 10.0.5.1' 'br7 10.0.7.1')" ] ||
	fail "tier-2 route discovery incorrectly excluded br0 when it was not the primary interface (got: ${route_options})"

# --- An unavailable tier 1 falls through to tier 2, threading the primary interface the whole way ---
fallback_options="$(private_ipv4_bridge_dns_options_with_fallbacks br5)" || fail 'fallback chain failed to reach tier 2'
[ "${fallback_options}" = 'br7 10.0.7.1' ] ||
	fail "fallback chain did not use the tier-2 route discovery result (got: ${fallback_options})"

# --- A successful scan with only rejected addresses never derives an unassigned route address ---
ip() {
	case "$*" in
		'-o -4 addr show scope global') printf '%s\n' '2: br7 inet 10.0.7.2/24 scope global deprecated br7' ;;
		'route show') printf '%s\n' '10.0.7.0/24 dev br7 proto kernel scope link src 10.0.7.1' ;;
		*) return 1 ;;
	esac
}
fallback_options="$(private_ipv4_bridge_dns_options_with_fallbacks br5)" || fail 'rejected-address scan failed'
[ -z "${fallback_options}" ] || fail 'route fallback advertised an unassigned address after a successful empty scan'

# have_cmd reports whether the requested command is the legacy `route` command.
have_cmd() { [ "$1" = route ] || [ "$1" = ifconfig ]; } # route and ifconfig emit mocked legacy bridge state.
route() {
	printf '%s\n' \
		'10.0.5.0       0.0.0.0         255.255.255.0   U     0      0        0 br5' \
		'10.0.7.0       0.0.0.0         255.255.255.0   U     0      0        0 br7'
}
ifconfig() {
	case "$1" in
		br5) printf '%s\n' 'inet addr:10.0.5.1  Bcast:10.0.5.255  Mask:255.255.255.0' ;;
		br7) printf '%s\n' 'inet addr:10.0.7.1  Bcast:10.0.7.255  Mask:255.255.255.0' ;;
		*) return 1 ;;
	esac
}

legacy_options="$(private_ipv4_legacy_route_dns_options br5)" || fail 'tier-3 legacy route discovery failed'
[ "${legacy_options}" = 'br7 10.0.7.1' ] ||
	fail "tier-3 legacy route discovery did not exclude the actual primary interface br5 (got: ${legacy_options})"

fallback_options="$(private_ipv4_bridge_dns_options_with_fallbacks br5)" || fail 'fallback chain failed to reach tier 3'
[ "${fallback_options}" = 'br7 10.0.7.1' ] ||
	fail "fallback chain did not use the tier-3 legacy route discovery result (got: ${fallback_options})"

# --- When no discovery command is available, the fallback chain produces no options ---
have_cmd() { return 1; }
fallback_options="$(private_ipv4_bridge_dns_options_with_fallbacks br5)"
[ -z "${fallback_options}" ] || fail 'fallback chain produced output with no available discovery commands'

printf '%s\n' 'PASS: private IPv4 bridge DNS fallback chain requires and threads the primary LAN interface through every tier'
