#!/bin/sh
# Verify LAN startup refreshes dynamic WebUI and DNS bind addresses atomically.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
TMP_ROOT="${TMPDIR:-/tmp}/adguardhome-lan-bind-refresh.$$"
FUNCTION_FILE="${TMP_ROOT}/functions"
YAML_FILE="${TMP_ROOT}/AdGuardHome.yaml"
CALLS_FILE="${TMP_ROOT}/calls"
BIN_DIR="${TMP_ROOT}/bin"
ADGUARDHOME_BINARY="${TMP_ROOT}/AdGuardHome"

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
mkdir -p "${TMP_ROOT}" "${BIN_DIR}" || fail 'could not create test directory'
sed -n '/^ipv4_is_usable_unicast() {$/,/^}$/p; /^private_ipv4_bridge_dns_options() {$/,/^}$/p; /^adguard_refresh_lan_bind_addresses() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" || fail 'could not extract refresh helper'
[ -s "${FUNCTION_FILE}" ] || fail 'refresh helper was not found'
# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

# agh_log records structured failure reasons without exposing fixture contents.
agh_log() { printf '%s\n' "$*" >>"${CALLS_FILE}"; }

cat >"${ADGUARDHOME_BINARY}" <<'EOF' || fail 'could not create validation stub'
#!/bin/sh
printf '%s\n' "$*" >>"${CALLS_FILE}"
[ "${VALIDATION_STATUS:-0}" -eq 0 ]
EOF
chmod 700 "${ADGUARDHOME_BINARY}" || fail 'could not make validation stub executable'
export ADGUARDHOME_BINARY CALLS_FILE

adguard_lan_mode() { return 0; }
have_cmd() { return 0; }
# ip returns duplicate and distinct private addresses in both router address formats.
ip() {
	if [ "${IP_OUTPUT_MODE:-fast}" = "fallback" ] && [ "${1:-}" = "-o" ]; then
		return 0
	fi
	if [ "${IP_OUTPUT_MODE:-fast}" = "fallback" ]; then
		printf '%s\n' \
			'5: br1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500' \
			'    inet 192.168.101.254/24 brd 192.168.101.255 scope global br1' \
			'    inet 192.168.102.254/24 brd 192.168.102.255 scope global secondary br1' \
			'    inet 192.168.103.254/24 brd 192.168.103.255 scope global secondary br1' \
			'    inet 192.168.101.254/24 brd 192.168.101.255 scope global br1'
	else
		printf '%s\n' \
			'5: br1    inet 192.168.101.254/24 brd 192.168.101.255 scope global br1' \
			'5: br1    inet 192.168.102.254/24 brd 192.168.102.255 scope global secondary br1' \
			'5: br1    inet 192.168.103.254/24 brd 192.168.103.255 scope global secondary br1' \
			'5: br1    inet 192.168.101.254/24 brd 192.168.101.255 scope global br1'
	fi
}
# interface_ipv4_addr prints the IPv4 address assigned to the LAN interface.
interface_ipv4_addr() { printf '%s\n' 192.168.50.27; }
# interface_ipv6_addr prints the IPv6 address assigned to the LAN interface.
interface_ipv6_addr() { printf '%s\n' 2001:db8::27; }
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

bridge_options="$(private_ipv4_bridge_dns_options)" || fail 'bridge address discovery failed'
[ "${bridge_options}" = "$(printf '%s\n' 'br1 192.168.101.254' 'br1 192.168.102.254' 'br1 192.168.103.254')" ] ||
	fail 'bridge address discovery did not preserve distinct per-interface addresses'
IP_OUTPUT_MODE=fallback
bridge_options="$(private_ipv4_bridge_dns_options)" || fail 'fallback bridge address discovery failed'
[ "${bridge_options}" = "$(printf '%s\n' 'br1 192.168.101.254' 'br1 192.168.102.254' 'br1 192.168.103.254')" ] ||
	fail 'fallback bridge address discovery did not preserve distinct per-interface addresses'
IP_OUTPUT_MODE=fast

adguard_refresh_lan_bind_addresses || fail 'dynamic LAN bind refresh failed'
grep -q '^  address: 192\.168\.50\.27:3443$' "${YAML_FILE}" || fail 'WebUI address or preserved port was not refreshed'
grep -q '^    - 192\.168\.50\.27$' "${YAML_FILE}" || fail 'LAN IPv4 DNS bind was not refreshed'
grep -q '^    - 2001:db8::27$' "${YAML_FILE}" || fail 'LAN IPv6 DNS bind was not refreshed'
grep -q '^    - 192\.168\.101\.254$' "${YAML_FILE}" || fail 'bridge DNS bind was not refreshed'
grep -q '^    - 192\.168\.102\.254$' "${YAML_FILE}" || fail 'secondary bridge DNS bind was not refreshed'
grep -q '^    - 192\.168\.103\.254$' "${YAML_FILE}" || fail 'additional bridge DNS bind was not refreshed'
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

# Restore usable LAN addresses for staged-validation and failure-path cases.
interface_ipv4_addr() { printf '%s\n' 192.168.50.27; }
interface_ipv6_addr() { printf '%s\n' 2001:db8::27; }
nvram() {
	case "$2" in
		lan_ifname) printf '%s\n' br0 ;;
		lan_ipaddr) printf '%s\n' 192.168.50.1 ;;
		ipv6_rtr_addr) printf '%s\n' 2001:db8::1 ;;
	esac
}

# assert_rejected_unchanged verifies structural failures never replace the active YAML.
assert_rejected_unchanged() {
	case_name="$1"
	cp "${YAML_FILE}" "${YAML_FILE}.before" || fail "${case_name}: could not preserve fixture"
	if adguard_refresh_lan_bind_addresses; then
		fail "${case_name}: invalid YAML was accepted"
	fi
	cmp -s "${YAML_FILE}" "${YAML_FILE}.before" || fail "${case_name}: active YAML changed"
}

cat >"${YAML_FILE}" <<'EOF'
defaults: &web
  address: 192.168.50.1:3443
http: *web
dns:
  bind_hosts: &hosts [127.0.0.1, 192.168.50.1, 2001:db8::1]
copy: *hosts
EOF
assert_rejected_unchanged aliases

cat >"${YAML_FILE}" <<'EOF'
http:
  address: 192.168.50.1:3443
http:
  address: 192.168.50.1:3444
dns:
  bind_hosts: [127.0.0.1, 192.168.50.1]
dns:
  bind_hosts:
    - 192.168.50.1
EOF
assert_rejected_unchanged duplicate-mappings

cat >"${YAML_FILE}" <<'EOF'
http:
  # address intentionally missing
dns:
  # bind_hosts intentionally missing
  port: 53
EOF
assert_rejected_unchanged missing-comment-only-keys

cat >"${YAML_FILE}" <<'EOF'
"http":
  "address": "192.168.50.1:3443"
'dns':
  'bind_hosts': [127.0.0.1, 192.168.50.1, "2001:db8::1"] # inline list
EOF
adguard_refresh_lan_bind_addresses || fail 'quoted inline bind list was not refreshed'
grep -q '^    - 2001:db8::27$' "${YAML_FILE}" || fail 'inline list was not normalized with the current IPv6 address'
[ "${LAN_BIND_ADDRESSES_CHANGED}" -eq 1 ] || fail 'changed inline list was not reported as changed'
cp "${YAML_FILE}" "${YAML_FILE}.before" || fail 'could not preserve no-op fixture'
adguard_refresh_lan_bind_addresses || fail 'no-op refresh failed validation'
[ "${LAN_BIND_ADDRESSES_CHANGED}" -eq 0 ] || fail 'no-op refresh requested a restart'
cmp -s "${YAML_FILE}" "${YAML_FILE}.before" || fail 'no-op refresh replaced content'

VALIDATION_STATUS=1
export VALIDATION_STATUS
assert_rejected_unchanged binary-validation-failure
unset VALIDATION_STATUS
grep -q 'reason=adguard_config_validation_failed' "${CALLS_FILE}" || fail 'validation failure reason was not logged'
! grep -q '192\.168\.' "${CALLS_FILE}" || fail 'validation log exposed YAML address content'

ln -s "${YAML_FILE}" "${TMP_ROOT}/linked.yaml" || fail 'could not create symlink fixture'
ACTIVE_YAML_FILE="${YAML_FILE}"
YAML_FILE="${TMP_ROOT}/linked.yaml"
if adguard_refresh_lan_bind_addresses; then fail 'symlink active YAML was accepted'; fi
YAML_FILE="${ACTIVE_YAML_FILE}"

# Command wrappers deterministically exercise failures that are otherwise filesystem-dependent as root.
for command_name in cp chmod chown cmp mv; do
	cat >"${BIN_DIR}/${command_name}" <<EOF
#!/bin/sh
case " \${FAIL_COMMAND:-} \$* " in
  *" ${command_name} "*.AdGuardHome.yaml.lan-bind.*)
    if [ "${command_name}" != mv ]; then exit \${FAIL_STATUS:-1}; fi
    case "\$*" in */AdGuardHome.yaml) exit \${FAIL_STATUS:-1} ;; esac
    ;;
esac
exec /usr/bin/${command_name} "\$@"
EOF
	chmod 700 "${BIN_DIR}/${command_name}" || fail "could not create ${command_name} failure wrapper"
done
PATH="${BIN_DIR}:${PATH}"
export PATH
for failure_case in 'cp:stage_copy_failed:1' 'chmod:stage_chmod_failed:1' 'chown:stage_chown_failed:1' 'cmp:stage_compare_failed:2' 'mv:atomic_replace_failed:1'; do
	sed 's/192\.168\.50\.27:3443/192.168.50.1:3443/' "${YAML_FILE}" >"${YAML_FILE}.reset" || fail 'could not prepare command-failure fixture'
	/usr/bin/mv "${YAML_FILE}.reset" "${YAML_FILE}" || fail 'could not activate command-failure fixture'
	FAIL_COMMAND="${failure_case%%:*}"
	remainder="${failure_case#*:}"
	expected_reason="${remainder%%:*}"
	FAIL_STATUS="${failure_case##*:}"
	export FAIL_COMMAND FAIL_STATUS
	: >"${CALLS_FILE}"
	assert_rejected_unchanged "failed-${FAIL_COMMAND}"
	grep -q "reason=${expected_reason}" "${CALLS_FILE}" || fail "failed-${FAIL_COMMAND}: reason was not logged"
done
unset FAIL_COMMAND FAIL_STATUS

# A read-only-filesystem-style staging failure follows the same preservation path as a failed copy.
sed 's/192\.168\.50\.27:3443/192.168.50.1:3443/' "${YAML_FILE}" >"${YAML_FILE}.reset" || fail 'could not prepare read-only fixture'
/usr/bin/mv "${YAML_FILE}.reset" "${YAML_FILE}" || fail 'could not activate read-only fixture'
FAIL_COMMAND=cp
export FAIL_COMMAND
assert_rejected_unchanged read-only-staging-directory
unset FAIL_COMMAND

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
