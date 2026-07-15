#!/bin/sh
# Verify WebUI port synchronization preserves valid hosts and falls back safely.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-web-port-sync.$$"
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

{
	sed -n '/^_quote() {$/,/^PTXT() {$/p' "${SCRIPT_PATH}" | sed '$d'
	sed -n '/^ipv4_is_valid() {$/,/^runtime_port_is_valid() {$/p' "${SCRIPT_PATH}" | sed '$d'
	sed -n '/^setup_default_web_host() {$/,/^setup_AdGuardHome_impl() {$/p' "${SCRIPT_PATH}" | sed '$d'
	sed -n '/^yaml_nvars_insert() {$/,/^# Interactive menu helpers$/p' "${SCRIPT_PATH}" | sed '$d'
} >"${FUNCTIONS_FILE}" || fail 'could not extract WebUI port synchronization helpers'
[ -s "${FUNCTIONS_FILE}" ] || fail 'WebUI port synchronization helper extraction was empty'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

ERROR='Error:'
YAML_FILE="${TMP_ROOT}/AdGuardHome.yaml"

PTXT() {
	case "${1:-}" in
		-n)
			shift
			while [ "$#" -gt 0 ]; do
				printf '%s' "$1"
				shift
			done
			;;
		*)
			while [ "$#" -gt 0 ]; do
				printf '%s\n' "$1"
				shift
			done
			;;
	esac
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

reset_router_state() {
	ADGUARD_INSTALL_MODE=wan
	IP_AVAILABLE=0
	LAN_IFNAME=""
	IPV4_FROM_IP=""
	IPV4_FROM_NVRAM=""
}

write_yaml() {
	: >"${YAML_FILE}" || fail 'could not reset YAML file'
	while [ "$#" -gt 0 ]; do
		printf '%s\n' "$1" >>"${YAML_FILE}" || fail 'could not write YAML fixture'
		shift
	done
}

assert_address() {
	case_name="$1"
	expected="$2"
	actual="$(awk '
		/^http:[[:space:]]*$/ { in_http = 1; next }
		in_http && /^[^[:space:]]/ { exit }
		in_http && /^[[:space:]]*address:[[:space:]]*/ {
			sub(/^[[:space:]]*address:[[:space:]]*/, "")
			print
			exit
		}
	' "${YAML_FILE}")"
	[ "${actual}" = "${expected}" ] || fail "${case_name}: expected address ${expected}, got ${actual:-empty}"
}

reset_router_state
write_yaml \
	'http:' \
	'  address: 192.168.50.1:3000' \
	'dns:' \
	'  bind_hosts:' \
	'    - 0.0.0.0'
setup_sync_webui_port 4000 || fail 'valid LAN-bound address synchronization failed'
assert_address preserve-ipv4-host '192.168.50.1:4000'
grep -q '^    - 0\.0\.0\.0$' "${YAML_FILE}" || fail 'synchronization changed non-http YAML content'

reset_router_state
write_yaml \
	'http:' \
	'  address: custom-router.lan:3000'
setup_sync_webui_port 4444 || fail 'valid hostname-bound address synchronization failed'
assert_address preserve-hostname 'custom-router.lan:4444'

reset_router_state
write_yaml \
	'http:' \
	'  address:'
setup_sync_webui_port 5555 || fail 'empty WAN address fallback synchronization failed'
assert_address wan-empty-fallback '0.0.0.0:5555'

reset_router_state
ADGUARD_INSTALL_MODE=lan
IP_AVAILABLE=1
LAN_IFNAME=br0
IPV4_FROM_IP=192.168.50.1
IPV4_FROM_NVRAM=192.168.1.1
write_yaml \
	'http:' \
	'  address: malformed-address'
setup_sync_webui_port 6000 || fail 'malformed LAN address fallback synchronization failed'
assert_address lan-malformed-fallback '192.168.50.1:6000'

reset_router_state
ADGUARD_INSTALL_MODE=lan
LAN_IFNAME=br0
IPV4_FROM_NVRAM=192.168.1.1
write_yaml \
	'http:' \
	'dns:' \
	'  bind_hosts:' \
	'    - 0.0.0.0'
setup_sync_webui_port 6001 || fail 'missing address insertion failed'
assert_address lan-missing-address-insert '192.168.1.1:6001'

reset_router_state
write_yaml \
	'http:' \
	'  address: 192.168.50.1:3000'
if setup_sync_webui_port 2999 >/dev/null 2>&1; then
	fail 'invalid new WebUI port was accepted'
fi
assert_address invalid-new-port-unchanged '192.168.50.1:3000'

printf '%s\n' 'PASS: installer WebUI port synchronization preserves hosts and falls back safely'
