#!/bin/sh
# Verify LAN startup refreshes dynamic WebUI and DNS bind addresses atomically.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
TMP_ROOT="${TMPDIR:-/tmp}/adguardhome-lan-bind-refresh.$$"
FUNCTION_FILE="${TMP_ROOT}/functions"
YAML_FILE="${TMP_ROOT}/AdGuardHome.yaml"

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
sed -n '/^ipv4_is_usable_unicast() {$/,/^}$/p; /^adguard_refresh_lan_bind_addresses() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" || fail 'could not extract refresh helper'
[ -s "${FUNCTION_FILE}" ] || fail 'refresh helper was not found'
# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

adguard_lan_mode() { return 0; }
have_cmd() { return 0; }
# interface_ipv4_addr prints the IPv4 address assigned to the LAN interface.
interface_ipv4_addr() { printf '%s\n' 192.168.50.27; }
# interface_ipv6_addr prints the IPv6 address assigned to the LAN interface.
interface_ipv6_addr() { printf '%s\n' 2001:db8::27; }
# private_ipv4_bridge_dns_options outputs a bridge interface address confirmed as locally assigned.
private_ipv4_bridge_dns_options() { printf '%s\n' 'br1 192.168.101.254' 'br1 192.168.102.254'; }
# nvram returns fixed test values for the requested NVRAM variable.
nvram() {
	case "$2" in
		lan_ifname) printf '%s\n' br0 ;;
		lan_ipaddr) printf '%s\n' 192.168.50.1 ;;
		ipv6_rtr_addr) printf '%s\n' 2001:db8::1 ;;
	esac
}

cat >"${YAML_FILE}" <<'EOF' || fail 'could not write fixture'
http:
  address: 192.168.50.1:3443
dns:
  bind_hosts:
    - 127.0.0.1
    - 192.168.50.1
    - 2001:db8::1
  port: 53
EOF

adguard_refresh_lan_bind_addresses || fail 'dynamic LAN bind refresh failed'
grep -q '^  address: 192\.168\.50\.27:3443$' "${YAML_FILE}" || fail 'WebUI address or preserved port was not refreshed'
grep -q '^    - 192\.168\.50\.27$' "${YAML_FILE}" || fail 'LAN IPv4 DNS bind was not refreshed'
grep -q '^    - 2001:db8::27$' "${YAML_FILE}" || fail 'LAN IPv6 DNS bind was not refreshed'
grep -q '^    - 192\.168\.101\.254$' "${YAML_FILE}" || fail 'bridge DNS bind was not refreshed'
grep -q '^    - 192\.168\.102\.254$' "${YAML_FILE}" || fail 'secondary bridge DNS bind was not refreshed'
! grep -q '192\.168\.50\.1' "${YAML_FILE}" || fail 'stale LAN bind address remained in YAML'

cat >"${YAML_FILE}" <<'EOF' || fail 'could not write quoted-key fixture'
"http": &http_settings # restored web settings
  "address": "192.168.50.1:7443"
  session_ttl: 720h
'dns': &dns_settings # restored resolver settings
  'bind_hosts':
    - 192.168.50.1
  port: 53
EOF

adguard_refresh_lan_bind_addresses || fail 'dynamic LAN bind refresh rejected quoted keys or anchored headers'
grep -Fq '"http": &http_settings # restored web settings' "${YAML_FILE}" || fail 'HTTP mapping header was not preserved'
grep -q '^  "address": 192\.168\.50\.27:7443$' "${YAML_FILE}" || fail 'quoted WebUI key or port was not refreshed'
grep -Fq "'dns': &dns_settings # restored resolver settings" "${YAML_FILE}" || fail 'DNS mapping header was not preserved'
grep -q "^  'bind_hosts':$" "${YAML_FILE}" || fail 'quoted bind-host key was not preserved'
grep -q '^    - 2001:db8::27$' "${YAML_FILE}" || fail 'quoted-key fixture did not receive refreshed binds'

cp "${YAML_FILE}" "${YAML_FILE}.before" || fail 'could not preserve refreshed fixture'
sed -i '/address/d' "${YAML_FILE}" || fail 'could not make malformed fixture'
cp "${YAML_FILE}" "${YAML_FILE}.malformed" || fail 'could not preserve malformed fixture'
if adguard_refresh_lan_bind_addresses; then
	fail 'refresh accepted YAML without a WebUI address'
fi
cmp -s "${YAML_FILE}" "${YAML_FILE}.malformed" || fail 'failed refresh modified YAML'

# interface_ipv4_addr prints the IPv4 address assigned to the interface.
interface_ipv4_addr() { printf '%s\n' 0.0.0.0; }
# nvram returns fixture values for the requested LAN-related NVRAM key.
nvram() {
	case "$2" in
		lan_ifname) printf '%s\n' br0 ;;
		lan_ipaddr) printf '%s\n' 0.0.0.0 ;;
		ipv6_rtr_addr) printf '%s\n' 2001:db8::1 ;;
	esac
}
cat >"${YAML_FILE}" <<'EOF' || fail 'could not write wildcard fallback fixture'
http:
  address: 192.168.50.27:3443
dns:
  bind_hosts:
    - 127.0.0.1
    - 192.168.50.27
  port: 53
EOF
cp "${YAML_FILE}" "${YAML_FILE}.wildcard" || fail 'could not preserve wildcard fallback fixture'
if adguard_refresh_lan_bind_addresses; then
	fail 'refresh accepted a wildcard LAN IPv4 address'
fi
cmp -s "${YAML_FILE}" "${YAML_FILE}.wildcard" || fail 'wildcard LAN IPv4 failure modified YAML'

ipv4_is_usable_unicast '192.168.50.27' || fail 'ipv4_is_usable_unicast rejected a normal unicast address'
ipv4_is_usable_unicast '223.255.255.255' || fail 'ipv4_is_usable_unicast rejected the address just below the multicast range'
! ipv4_is_usable_unicast '224.0.0.1' || fail 'ipv4_is_usable_unicast accepted a multicast address'
! ipv4_is_usable_unicast '127.0.0.1' || fail 'ipv4_is_usable_unicast accepted a loopback address'
! ipv4_is_usable_unicast '0.1.2.3' || fail 'ipv4_is_usable_unicast accepted an address in the 0.0.0.0/8 range'
! ipv4_is_usable_unicast '0.0.0.0' || fail 'ipv4_is_usable_unicast accepted the wildcard address'
! ipv4_is_usable_unicast '256.1.1.1' || fail 'ipv4_is_usable_unicast accepted an out-of-range octet'
! ipv4_is_usable_unicast '192.168.1' || fail 'ipv4_is_usable_unicast accepted an address with too few octets'
! ipv4_is_usable_unicast '192.168.1.2.3' || fail 'ipv4_is_usable_unicast accepted an address with too many octets'
! ipv4_is_usable_unicast '192.168.1.abc' || fail 'ipv4_is_usable_unicast accepted a non-numeric octet'
! ipv4_is_usable_unicast '' || fail 'ipv4_is_usable_unicast accepted an empty address'

printf '%s\n' 'PASS: LAN startup refreshes dynamic WebUI and DNS bind addresses without partial YAML writes'
