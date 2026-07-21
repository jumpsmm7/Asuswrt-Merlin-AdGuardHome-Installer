#!/bin/sh
# Verify WebUI port synchronization preserves valid hosts and falls back safely.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-web-port-sync.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions"

# cleanup removes the temporary test workspace and its contents.
cleanup() {
	rm -rf "${TMP_ROOT}"
}

# fail prints a failure message to standard error and exits with status 1.
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
	sed -n '/^ipv4_is_valid() {$/,/^web_port_in_use() {$/p' "${SCRIPT_PATH}" | sed '$d'
	sed -n '/^adguardhome_yaml_secure_file() {$/,/^adguardhome_yaml_remove_ipset_file() {$/p' "${SCRIPT_PATH}" | sed '$d'
	sed -n '/^setup_default_web_host() {$/,/^setup_AdGuardHome_impl() {$/p' "${SCRIPT_PATH}" | sed '$d'
	sed -n '/^yaml_nvars_insert() {$/,/^# Interactive menu helpers$/p' "${SCRIPT_PATH}" | sed '$d'
} >"${FUNCTIONS_FILE}" || fail 'could not extract WebUI port synchronization helpers'
[ -s "${FUNCTIONS_FILE}" ] || fail 'WebUI port synchronization helper extraction was empty'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

ERROR='Error:'
YAML_FILE="${TMP_ROOT}/AdGuardHome.yaml"

# PTXT prints each argument on a separate line, or concatenates arguments without trailing newlines when the first argument is `-n`.
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

# ai_have_cmd reports whether the `ip` command is available in the test environment.
ai_have_cmd() {
	[ "${IP_AVAILABLE:-0}" -eq 1 ] && [ "$1" = "ip" ]
}

# ip returns a stubbed IPv4 address for the supported br0 query and fails for other arguments.
ip() {
	case "$*" in
		'-o -4 addr list br0')
			[ -n "${IPV4_FROM_IP:-}" ] && printf '1: br0    inet %s/24 brd 192.168.50.255 scope global br0\n' "${IPV4_FROM_IP}"
			;;
		*) return 1 ;;
	esac
}

# nvram prints stubbed router values for supported NVRAM queries.
nvram() {
	case "${1:-}:${2:-}" in
		get:lan_ifname) printf '%s\n' "${LAN_IFNAME:-}" ;;
		get:lan_ipaddr) printf '%s\n' "${IPV4_FROM_NVRAM:-}" ;;
		*) return 1 ;;
	esac
}

# reset_router_state resets the simulated router state to default WAN-mode values.
reset_router_state() {
	ADGUARD_INSTALL_MODE=wan
	IP_AVAILABLE=0
	LAN_IFNAME=""
	IPV4_FROM_IP=""
	IPV4_FROM_NVRAM=""
}

# write_yaml writes each argument as a separate line to the YAML fixture file.
write_yaml() {
	: >"${YAML_FILE}" || fail 'could not reset YAML file'
	while [ "$#" -gt 0 ]; do
		printf '%s\n' "$1" >>"${YAML_FILE}" || fail 'could not write YAML fixture'
		shift
	done
}

# assert_address checks that the quoted or unquoted top-level http.address value in the YAML fixture matches the expected value for a test case.
assert_address() {
	case_name="$1"
	expected="$2"
	actual="$(awk '
		function yaml_key_is(line, expected, text, separator, key) {
			text = line
			sub(/^[[:space:]]*/, "", text)
			separator = index(text, ":")
			if (!separator) return 0
			key = substr(text, 1, separator - 1)
			sub(/[[:space:]]*$/, "", key)
			return key == expected || key == "\"" expected "\"" || key == sprintf("%c%s%c", 39, expected, 39)
		}
		/^[^[:space:]]/ && yaml_key_is($0, "http") { in_http = 1; next }
		in_http && /^[^[:space:]#]/ { exit }
		in_http && yaml_key_is($0, "address") {
			sub(/^[[:space:]]*["'"'"']?address["'"'"']?[[:space:]]*:[[:space:]]*/, "")
			print
			exit
		}
	' "${YAML_FILE}")"
	[ "${actual}" = "${expected}" ] || fail "${case_name}: expected address ${expected}, got ${actual:-empty}"
}

# assert_single_address_key verifies synchronization leaves exactly one quoted or unquoted address key.
assert_single_address_key() {
	case_name="$1"
	count="$(awk '
		{
			line = $0
			sub(/^[[:space:]]*/, "", line)
			if (line ~ /^address[[:space:]]*:/ || line ~ /^"address"[[:space:]]*:/ || line ~ /^'"'"'address'"'"'[[:space:]]*:/) count++
		}
		END { print count + 0 }
	' "${YAML_FILE}")"
	[ "${count}" -eq 1 ] || fail "${case_name}: expected one address key, found ${count}"
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
	'  address: "192.168.50.2:3000"'
setup_sync_webui_port 4545 || fail 'quoted LAN-bound address synchronization failed'
assert_address preserve-quoted-ipv4-host '192.168.50.2:4545'

reset_router_state
write_yaml \
	'http:' \
	'  address: "[::1]:3000"'
setup_sync_webui_port 4555 || fail 'quoted IPv6 WebUI address synchronization failed'
assert_address preserve-quoted-ipv6-host '"[::1]:4555"'

reset_router_state
write_yaml \
	'http:' \
	'  address: 192.168.50.2:80'
setup_sync_webui_port 4646 || fail 'runtime WebUI port synchronization failed'
assert_address preserve-runtime-port-host '192.168.50.2:4646'

reset_router_state
write_yaml \
	'http:' \
	'  address: 127.0.0.1:3000 # local only'
setup_sync_webui_port 4747 || fail 'inline-commented WebUI address synchronization failed'
assert_address preserve-inline-comment-host '127.0.0.1:4747'

reset_router_state
write_yaml \
	'"http":' \
	'  "address": 127.0.0.1:3000'
setup_sync_webui_port 4848 || fail 'quoted HTTP keys synchronization failed'
grep -q '^  address: 127\.0\.0\.1:4848$' "${YAML_FILE}" || fail 'quoted HTTP keys did not preserve the WebUI host'
assert_single_address_key quoted-http-keys

reset_router_state
write_yaml \
	"'http': # WebUI settings" \
	"  'address': 127.0.0.1:3000"
setup_sync_webui_port 4898 || fail 'single-quoted HTTP keys synchronization failed'
assert_address single-quoted-http-keys '127.0.0.1:4898'
assert_single_address_key single-quoted-http-keys

reset_router_state
write_yaml \
	'http:' \
	'  "address" : "192.168.50.3:3000"'
setup_sync_webui_port 4949 || fail 'spaced quoted address key synchronization failed'
grep -q '^  address: 192\.168\.50\.3:4949$' "${YAML_FILE}" || fail 'spaced quoted address key did not preserve the WebUI host'
assert_single_address_key spaced-quoted-address-key

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
	'filters:' \
	'  - url: http://example.invalid/filter.txt' \
	'http:' \
	'dns:' \
	'  bind_hosts:' \
	'    - 0.0.0.0'
setup_sync_webui_port 6001 || fail 'missing address insertion failed'
assert_address lan-missing-address-insert '192.168.1.1:6001'
[ "$(ls -l "${YAML_FILE}" | cut -c 1-10)" = "-rw-------" ] || fail 'missing address insertion did not preserve private YAML permissions'
if awk '
	/^filters:[[:space:]]*$/ { in_filters = 1; next }
	in_filters && /^[^[:space:]]/ { exit }
	in_filters && /^[[:space:]]*address:[[:space:]]*/ { found = 1 }
	END { exit(found ? 0 : 1) }
' "${YAML_FILE}"; then
	fail 'missing address insertion wrote into filters section'
fi

reset_router_state
write_yaml \
	'filters:' \
	'  - url: http://example.invalid/filter.txt' \
	'dns:' \
	'  bind_hosts:' \
	'    - 0.0.0.0'
if setup_sync_webui_port 6002 >/dev/null 2>&1; then
	fail 'missing top-level http section was accepted'
fi
if grep -q '^[[:space:]]*address:[[:space:]]*' "${YAML_FILE}"; then
	fail 'missing top-level http section wrote an address line'
fi

reset_router_state
write_yaml \
	'"http":' \
	'  "address": "127.0.0.1:3000"' \
	'dns:' \
	'  bind_hosts:' \
	'    - 0.0.0.0'
setup_sync_webui_port 6003 || fail 'block-style quoted http mapping control failed'
grep -q '^  address: 127\.0\.0\.1:6003$' "${YAML_FILE}" ||
	fail 'block-style quoted http mapping control did not update its address'
assert_single_address_key block-style-quoted-http

reset_router_state
write_yaml \
	'"http": {address: "127.0.0.1:3000"}' \
	'dns:' \
	'  bind_hosts:' \
	'    - 0.0.0.0'
if setup_sync_webui_port 6004 >/dev/null 2>&1; then
	fail 'flow-style http mapping was accepted as a block mapping'
fi
grep -q '^"http": {address: "127\.0\.0\.1:3000"}$' "${YAML_FILE}" ||
	fail 'flow-style http mapping was rewritten'
if grep -q '^[[:space:]][[:space:]]*address:' "${YAML_FILE}"; then
	fail 'flow-style http mapping received an invalid block address'
fi

reset_router_state
write_yaml \
	'http: {' \
	'  address: "127.0.0.1:3000"' \
	'}' \
	'dns:' \
	'  bind_hosts:' \
	'    - 0.0.0.0'
if setup_sync_webui_port 6005 >/dev/null 2>&1; then
	fail 'multiline flow-style http mapping was accepted as a block mapping'
fi
grep -q '^  address: "127\.0\.0\.1:3000"$' "${YAML_FILE}" ||
	fail 'multiline flow-style http mapping was rewritten'
grep -q '^http: {$' "${YAML_FILE}" || fail 'multiline flow-style http mapping header was rewritten'
grep -q '^}$' "${YAML_FILE}" || fail 'multiline flow-style http mapping terminator was rewritten'

reset_router_state
write_yaml \
	'http:' \
	'# bind settings' \
	'  address: "127.0.0.1:3000"' \
	'dns:' \
	'  bind_hosts:' \
	'    - 0.0.0.0'
setup_sync_webui_port 6006 || fail 'http address after an unindented comment was not synchronized'
assert_address http-unindented-comment '127.0.0.1:6006'
[ "$(grep -c '^[[:space:]]*address:' "${YAML_FILE}")" -eq 1 ] ||
	fail 'http address after an unindented comment was duplicated'

reset_router_state
write_yaml \
	'"http": # Web UI settings' \
	'  "address" : "127.0.0.1:3000"' \
	'dns:' \
	'  bind_hosts:' \
	'    - 0.0.0.0'
setup_sync_webui_port 6007 || fail 'quoted http mapping with an inline comment was not synchronized'
grep -q '^  address: 127\.0\.0\.1:6007$' "${YAML_FILE}" ||
	fail 'quoted http mapping with an inline comment did not update its address'
assert_single_address_key quoted-http-inline-comment

reset_router_state
write_yaml \
	'http: # Web UI settings' \
	'dns:' \
	'  bind_hosts:' \
	'    - 0.0.0.0'
setup_sync_webui_port 6008 || fail 'http mapping with an inline comment did not receive an address'
grep -q '^  address: 0\.0\.0\.0:6008$' "${YAML_FILE}" ||
	fail 'http mapping with an inline comment received the wrong address'
assert_single_address_key http-inline-comment-insertion

reset_router_state
write_yaml \
	'http:' \
	'  address: 192.168.50.1:3000'
if setup_sync_webui_port 2999 >/dev/null 2>&1; then
	fail 'invalid new WebUI port was accepted'
fi
assert_address invalid-new-port-unchanged '192.168.50.1:3000'

printf '%s\n' 'PASS: installer WebUI port synchronization preserves hosts and falls back safely'
