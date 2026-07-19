#!/bin/sh
# Verify initial setup bind address selection keeps WAN DNS wildcard-bound while LAN DNS includes loopback, LAN IPv4, LAN IPv6, and bridge IPv4 binds.

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

sed -n '/^setup_resolve_lan_addresses() {$/,/^setup_AdGuardHome_impl() {$/p' "${SCRIPT_PATH}" | sed '$d' >"${FUNCTIONS_FILE}" ||
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
	case "$1" in
		ip) [ "${IP_AVAILABLE:-0}" -eq 1 ] ;;
		route) [ "${ROUTE_AVAILABLE:-0}" -eq 1 ] ;;
		*) return 1 ;;
	esac
}

ip() {
	case "$*" in
		'-o -4 addr list br0')
			[ -n "${IPV4_FROM_IP:-}" ] && printf '1: br0    inet %s/24 brd 192.168.50.255 scope global br0\n' "${IPV4_FROM_IP}"
			;;
		'-o -6 addr list br0 scope global')
			[ -n "${IPV6_FROM_IP:-}" ] && printf '1: br0    inet6 %s/64 scope global\n' "${IPV6_FROM_IP}"
			;;
		'-o -6 addr list br0')
			[ -n "${IPV6_ASSIGNED:-}" ] && printf '1: br0    inet6 %s/64 scope global\n' "${IPV6_ASSIGNED}"
			;;
		'-o -4 addr show scope global')
			[ -n "${IPV4_FROM_IP:-}" ] && printf '1: br0    inet %s/24 brd 192.168.50.255 scope global br0\n' "${IPV4_FROM_IP}"
			[ -n "${BRIDGE_ADDRS:-}" ] && printf '%s\n' "${BRIDGE_ADDRS}"
			;;
		'route show')
			[ -n "${IP_ROUTE_OUTPUT:-}" ] && printf '%s\n' "${IP_ROUTE_OUTPUT}"
			;;
		*) return 1 ;;
	esac
}

route() {
	[ -n "${ROUTE_OUTPUT:-}" ] && printf '%s\n' "${ROUTE_OUTPUT}"
}

nvram() {
	case "${1:-}:${2:-}" in
		get:lan_ifname) printf '%s\n' "${LAN_IFNAME:-}" ;;
		get:lan_ipaddr) printf '%s\n' "${IPV4_FROM_NVRAM:-}" ;;
		get:ipv6_rtr_addr) printf '%s\n' "${IPV6_FROM_NVRAM:-}" ;;
		*) return 1 ;;
	esac
}

reset_inputs() {
	ADGUARD_INSTALL_MODE=""
	IP_AVAILABLE=0
	ROUTE_AVAILABLE=0
	LAN_IFNAME=""
	IPV4_FROM_IP=""
	IPV4_FROM_NVRAM=""
	IPV6_FROM_IP=""
	IPV6_FROM_NVRAM=""
	IPV6_ASSIGNED=""
	BRIDGE_ADDRS=""
	IP_ROUTE_OUTPUT=""
	ROUTE_OUTPUT=""
	NET_ADDR=""
	NET_ADDR6=""
	SETUP_WEB_ADDRESS="preset"
	SETUP_DNS_BIND_HOST="preset"
	SETUP_DNS_BIND_HOST6=""
}

assert_bind_values() {
	case_name="$1"
	expected_web="$2"
	expected_dns4="$3"
	expected_dns6="${4-}"
	[ "${SETUP_WEB_ADDRESS:-}" = "${expected_web}" ] || fail "${case_name}: expected web ${expected_web}, got ${SETUP_WEB_ADDRESS:-empty}"
	[ "${SETUP_DNS_BIND_HOST:-}" = "${expected_dns4}" ] || fail "${case_name}: expected DNS IPv4 ${expected_dns4}, got ${SETUP_DNS_BIND_HOST:-empty}"
	[ "${SETUP_DNS_BIND_HOST6:-}" = "${expected_dns6}" ] || fail "${case_name}: expected DNS IPv6 ${expected_dns6:-empty}, got ${SETUP_DNS_BIND_HOST6:-empty}"
}

assert_yaml_bind_hosts() {
	case_name="$1"
	expected_count="$2"
	yaml_file="${TMP_ROOT}/${case_name}.yaml"
	rm -f "${yaml_file}"
	setup_write_dns_bind_hosts "${yaml_file}" || fail "${case_name}: failed to write DNS bind hosts"
	grep -q '^dns:$' "${yaml_file}" || fail "${case_name}: DNS section was not written"
	grep -q '^  bind_hosts:$' "${yaml_file}" || fail "${case_name}: bind_hosts section was not written"
	awk -v expected="    - ${SETUP_DNS_BIND_HOST}" '$0 == expected { found = 1 } END { exit(found ? 0 : 1) }' "${yaml_file}" ||
		fail "${case_name}: DNS bind host was not written"
	[ "$(grep -c '^    - ' "${yaml_file}")" -eq "${expected_count}" ] || fail "${case_name}: expected ${expected_count} DNS bind host item(s)"
	! grep -q '^    - ::$' "${yaml_file}" || fail "${case_name}: generated YAML appended an IPv6 wildcard bind host"
}

reset_inputs
ADGUARD_INSTALL_MODE=wan
setup_resolve_bind_addresses >/dev/null || fail 'WAN bind resolution failed'
assert_bind_values wan '0.0.0.0:3000' '0.0.0.0'
assert_yaml_bind_hosts wan 1
grep -q '^    - 0\.0\.0\.0$' "${TMP_ROOT}/wan.yaml" || fail 'WAN DNS bind host was not wildcard-bound'

reset_inputs
ADGUARD_INSTALL_MODE=lan
IP_AVAILABLE=1
LAN_IFNAME=br0
IPV4_FROM_IP=192.168.50.1
IPV6_FROM_IP=2001:db8::1
IPV4_FROM_NVRAM=192.168.1.1
IPV6_FROM_NVRAM=2001:db8::2
BRIDGE_ADDRS='2: br1    inet 192.168.101.1/24 brd 192.168.101.255 scope global br1
3: br52    inet 10.52.0.1/24 brd 10.52.0.255 scope global br52'
SETUP_DNS_BIND_HOST6='::'
setup_resolve_lan_addresses
[ "${NET_ADDR:-}" = "${IPV4_FROM_IP}" ] || fail 'initial YAML LAN IPv4 resolution did not prefer ip output'
[ "${NET_ADDR6:-}" = "${IPV6_FROM_IP}" ] || fail 'initial YAML LAN IPv6 resolution did not prefer ip output'
setup_resolve_bind_addresses >/dev/null || fail 'LAN bind resolution from ip failed'
assert_bind_values lan-ip '192.168.50.1:3000' "${IPV4_FROM_IP}" "${IPV6_FROM_IP}"
assert_yaml_bind_hosts lan-ip 5
grep -q '^    - 127\.0\.0\.1$' "${TMP_ROOT}/lan-ip.yaml" || fail 'LAN DNS loopback bind host was not written'
grep -q '^    - 192\.168\.50\.1$' "${TMP_ROOT}/lan-ip.yaml" || fail 'LAN DNS bind host from ip was not written'
grep -q '^    - 2001:db8::1$' "${TMP_ROOT}/lan-ip.yaml" || fail 'LAN DNS IPv6 bind host from ip was not written'
grep -q '^    - 192\.168\.101\.1$' "${TMP_ROOT}/lan-ip.yaml" || fail 'LAN DNS bind host for guest bridge was not written'
grep -q '^    - 10\.52\.0\.1$' "${TMP_ROOT}/lan-ip.yaml" || fail 'LAN DNS bind host for SDN bridge was not written'

reset_inputs
ADGUARD_INSTALL_MODE=lan
IP_AVAILABLE=1
LAN_IFNAME=br0
IPV4_FROM_NVRAM=192.168.1.1
IPV6_FROM_NVRAM=2001:db8::2
IPV6_ASSIGNED="${IPV6_FROM_NVRAM}"
SETUP_DNS_BIND_HOST6='::'
setup_resolve_lan_addresses
[ "${NET_ADDR:-}" = "${IPV4_FROM_NVRAM}" ] || fail 'initial YAML LAN IPv4 resolution did not fall back to nvram'
[ "${NET_ADDR6:-}" = "${IPV6_FROM_NVRAM}" ] || fail 'initial YAML LAN IPv6 resolution did not fall back to nvram'
setup_resolve_bind_addresses >/dev/null || fail 'LAN bind resolution from nvram fallback failed'
assert_bind_values lan-nvram '192.168.1.1:3000' "${IPV4_FROM_NVRAM}" "${IPV6_FROM_NVRAM}"
assert_yaml_bind_hosts lan-nvram 3
grep -q '^    - 127\.0\.0\.1$' "${TMP_ROOT}/lan-nvram.yaml" || fail 'LAN DNS loopback bind host from nvram fallback was not written'
grep -q '^    - 192\.168\.1\.1$' "${TMP_ROOT}/lan-nvram.yaml" || fail 'LAN DNS bind host from nvram was not written'
grep -q '^    - 2001:db8::2$' "${TMP_ROOT}/lan-nvram.yaml" || fail 'LAN DNS IPv6 bind host from nvram was not written'

for invalid_ipv6 in :: 2001:db8::dead; do
	reset_inputs
	ADGUARD_INSTALL_MODE=lan
	IP_AVAILABLE=1
	LAN_IFNAME=br0
	IPV4_FROM_NVRAM=192.168.1.1
	IPV6_FROM_NVRAM="${invalid_ipv6}"
	IPV6_ASSIGNED=2001:db8::2
	setup_resolve_lan_addresses
	[ -z "${NET_ADDR6:-}" ] || fail "LAN IPv6 fallback accepted unusable nvram address ${invalid_ipv6}"
	setup_resolve_bind_addresses >/dev/null || fail 'LAN bind resolution without a usable IPv6 fallback failed'
	assert_bind_values lan-invalid-ipv6 '192.168.1.1:3000' "${IPV4_FROM_NVRAM}"
	assert_yaml_bind_hosts lan-invalid-ipv6 2
done

reset_inputs
ADGUARD_INSTALL_MODE=lan
IP_AVAILABLE=1
ROUTE_AVAILABLE=1
LAN_IFNAME=br0
IPV4_FROM_IP=192.168.50.1
IP_ROUTE_OUTPUT='192.168.102.0/24 dev br102 proto kernel scope link'
setup_resolve_bind_addresses >/dev/null || fail 'LAN bind resolution for route fallback failed'
assert_bind_values lan-route '192.168.50.1:3000' "${IPV4_FROM_IP}"
assert_yaml_bind_hosts lan-route 3
grep -q '^    - 127\.0\.0\.1$' "${TMP_ROOT}/lan-route.yaml" || fail 'LAN DNS loopback bind host from route fallback was not written'
grep -q '^    - 192\.168\.50\.1$' "${TMP_ROOT}/lan-route.yaml" || fail 'LAN DNS bind host from route fallback was not written'
grep -q '^    - 192\.168\.102\.1$' "${TMP_ROOT}/lan-route.yaml" || fail 'LAN DNS route fallback bridge bind host was not written'

reset_inputs
ADGUARD_INSTALL_MODE=lan
ROUTE_AVAILABLE=1
LAN_IFNAME=br0
IPV4_FROM_NVRAM=192.168.1.1
ROUTE_OUTPUT='192.168.103.0     *               255.255.255.0   U     0      0        0 br103'
setup_resolve_bind_addresses >/dev/null || fail 'LAN bind resolution for legacy route fallback failed'
assert_bind_values lan-legacy-route '192.168.1.1:3000' "${IPV4_FROM_NVRAM}"
assert_yaml_bind_hosts lan-legacy-route 3
grep -q '^    - 127\.0\.0\.1$' "${TMP_ROOT}/lan-legacy-route.yaml" || fail 'LAN DNS loopback bind host from legacy route fallback was not written'
grep -q '^    - 192\.168\.1\.1$' "${TMP_ROOT}/lan-legacy-route.yaml" || fail 'LAN DNS bind host from legacy route fallback was not written'
grep -q '^    - 192\.168\.103\.1$' "${TMP_ROOT}/lan-legacy-route.yaml" || fail 'LAN DNS legacy route fallback bridge bind host was not written'

reset_inputs
ADGUARD_INSTALL_MODE=lan
IP_AVAILABLE=1
LAN_IFNAME=br0
setup_resolve_lan_addresses
[ -z "${NET_ADDR:-}" ] || fail 'initial YAML LAN IPv4 resolution unexpectedly found an address'
if setup_resolve_bind_addresses >/dev/null 2>&1; then
	fail 'LAN bind resolution succeeded without IPv4 address'
fi

printf '%s\n' 'PASS: installer bind address resolution keeps WAN DNS wildcard-bound while LAN DNS includes loopback, LAN IPv4, LAN IPv6, and bridge IPv4 binds'
