#!/bin/sh
# Verify the private IPv4 bridge DNS fallback chain requires the primary LAN
# interface and threads it through every discovery tier, instead of excluding
# a hardcoded br0.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
TMP_ROOT="${TMPDIR:-/tmp}/private-ipv4-dns-fallback-chain.$$"
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
mkdir -p "${TMP_ROOT}" || fail 'could not create test directory'

sed -n '/^private_ipv4_bridge_dns_options() {$/,/^resolv_conf_is_tmp_mount() {$/p' "${SCRIPT_PATH}" | sed '$d' >"${FUNCTION_FILE}" ||
	fail 'could not extract bridge DNS fallback helpers'
[ -s "${FUNCTION_FILE}" ] || fail 'bridge DNS fallback helper extraction was empty'
# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

# agh_log discards bridge-discovery log lines; only discovery output is under test here.
agh_log() { :; }

# --- Every tier rejects a missing primary LAN interface argument ---
have_cmd() { [ "$1" = ip ] || [ "$1" = route ]; }
ip() { return 1; }
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

# --- Tier 2 (`ip route show`) excludes the actual primary LAN interface, not a hardcoded br0 ---
have_cmd() { [ "$1" = ip ]; }
ip() {
	case "$*" in
		'-o -4 addr show scope global') return 0 ;;
		'-4 addr show scope global') return 0 ;;
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

# --- An empty tier 1 result falls through to tier 2, threading the primary interface the whole way ---
fallback_options="$(private_ipv4_bridge_dns_options_with_fallbacks br5)" || fail 'fallback chain failed to reach tier 2'
[ "${fallback_options}" = 'br7 10.0.7.1' ] ||
	fail "fallback chain did not use the tier-2 route discovery result (got: ${fallback_options})"

# --- Tier 3 (legacy `route`) excludes the actual primary LAN interface, not a hardcoded br0 ---
have_cmd() { [ "$1" = route ]; } # 'ip' unavailable forces tiers 1 and 2 to fail over to tier 3.
route() {
	printf '%s\n' \
		'10.0.5.0       0.0.0.0         255.255.255.0   U     0      0        0 br5' \
		'10.0.7.0       0.0.0.0         255.255.255.0   U     0      0        0 br7'
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