#!/bin/sh
# Verify LAN-mode IPSET enforcement removes YAML ipset_file safely.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-lan-ipset-yaml-cleanup.$$"
STUB_DIR="${TMP_ROOT}/bin"
CHOWN_LOG="${TMP_ROOT}/chown.log"
FUNCTIONS_FILE="${TMP_ROOT}/functions"
CONF_FILE="${TMP_ROOT}/.config"
TARG_DIR="${TMP_ROOT}/AdGuardHome"
YAML_FILE="${TARG_DIR}/AdGuardHome.yaml"
YAML_ORI="${TARG_DIR}/.AdGuardHome.yaml.ori"

cleanup() {
	rm -rf "${TMP_ROOT}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

mode_string() {
	ls -ld "$1" | awk 'NR == 1 { print substr($1, 1, 10) }'
}

extract_function() {
	_function_name="$1"
	awk -v name="${_function_name}" '
		$0 == name "() {" { copying = 1 }
		copying { print }
		copying && $0 == "}" { exit }
	' "${SCRIPT_PATH}" >>"${FUNCTIONS_FILE}" || return 1
}

write_conf() {
	_key="$1"
	_value="$2"
	_tmp_file="${CONF_FILE}.tmp.$$"
	awk -v KEY="${_key}" -v VALUE="${_value}" '
		BEGIN { replaced = 0 }
		index($0, KEY "=") == 1 {
			print KEY "=" VALUE
			replaced = 1
			next
		}
		{ print }
		END {
			if (!replaced) print KEY "=" VALUE
		}
	' "${CONF_FILE}" >"${_tmp_file}" && mv -f "${_tmp_file}" "${CONF_FILE}" || {
		rm -f "${_tmp_file}"
		return 1
	}
}

assert_no_ipset_file() {
	if grep -q 'ipset_file' "${YAML_FILE}"; then
		fail "$1: ipset_file was not removed"
	fi
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"
mkdir -p "${TMP_ROOT}" "${TARG_DIR}" "${STUB_DIR}" || fail 'could not create test directory'
: >"${FUNCTIONS_FILE}"
extract_function conf_value || fail 'could not extract conf_value'
extract_function adguardhome_yaml_ipset_file || fail 'could not extract YAML parser'
extract_function adguardhome_yaml_secure_file || fail 'could not extract YAML security helper'
extract_function adguardhome_yaml_remove_ipset_file || fail 'could not extract YAML cleanup helper'
extract_function adguard_enforce_lan_ipset_disabled || fail 'could not extract LAN enforcement helper'
extract_function port_is_valid || fail 'could not extract port validation helper'
extract_function setup_sync_restored_yaml_for_wan || fail 'could not extract WAN restore YAML sync helper'
extract_function setup_sync_restored_yaml_and_snapshot_for_wan || fail 'could not extract WAN restore YAML snapshot sync helper'
[ -s "${FUNCTIONS_FILE}" ] || fail 'helper extraction was empty'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

cat >"${STUB_DIR}/chown" <<'EOF_CHOWN' || fail 'could not write chown stub'
#!/bin/sh
printf '%s %s\n' "$1" "$2" >>"${CHOWN_LOG}"
EOF_CHOWN
chmod 755 "${STUB_DIR}/chown" || fail 'could not chmod chown stub'

INFO='Info:'
PTXT() {
	if [ "${1:-}" = "-n" ]; then
		shift
	fi
	printf '%s\n' "$@"
}

cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write custom YAML ipset_file'
dns:
  bind_hosts:
    - 0.0.0.0
  ipset_file: custom-ipset.conf
  bootstrap_dns:
    - 1.1.1.1
EOF_YAML
chmod 600 "${YAML_FILE}" || fail 'could not set YAML mode'
adguardhome_yaml_remove_ipset_file || fail 'custom YAML ipset_file cleanup failed'
assert_no_ipset_file custom-path
[ "$(mode_string "${YAML_FILE}")" = '-rw-------' ] || fail 'YAML mode was not preserved after cleanup'
grep -q 'bootstrap_dns:' "${YAML_FILE}" || fail 'cleanup removed following dns child key'

cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write quoted-key YAML ipset_file'
"dns":
  'ipset_file': custom-quoted-ipset.conf
  bootstrap_dns:
    - 1.0.0.1
EOF_YAML
chmod 644 "${YAML_FILE}" || fail 'could not set world-readable YAML mode'
adguardhome_yaml_remove_ipset_file || fail 'quoted-key YAML ipset_file cleanup failed'
assert_no_ipset_file quoted-key
[ "$(mode_string "${YAML_FILE}")" = '-rw-------' ] || fail 'YAML mode was not tightened after quoted-key cleanup'
grep -q 'bootstrap_dns:' "${YAML_FILE}" || fail 'quoted-key cleanup removed following dns child key'

cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write block scalar YAML ipset_file'
dns:
  ipset_file: |
    custom-ipset.conf
    stale-continuation.conf
  bootstrap_dns:
    - 9.9.9.9
filtering:
  protection_enabled: true
EOF_YAML
chmod 600 "${YAML_FILE}" || fail 'could not reset YAML mode'
adguardhome_yaml_remove_ipset_file || fail 'block-scalar YAML ipset_file cleanup failed'
assert_no_ipset_file block-scalar
if grep -q 'custom-ipset.conf\|stale-continuation.conf' "${YAML_FILE}"; then
	fail 'block-scalar continuation was not removed'
fi
grep -q 'bootstrap_dns:' "${YAML_FILE}" || fail 'block cleanup removed following dns key'
grep -q 'filtering:' "${YAML_FILE}" || fail 'block cleanup removed following top-level key'
[ "$(mode_string "${YAML_FILE}")" = '-rw-------' ] || fail 'YAML mode was not preserved after block cleanup'

cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write explicit-indent block YAML ipset_file'
dns:
  ipset_file: |2
    explicit-indent-ipset.conf
    explicit-indent-continuation.conf
  bootstrap_dns:
    - 1.0.0.1
filtering:
  protection_enabled: true
EOF_YAML
chmod 600 "${YAML_FILE}" || fail 'could not reset explicit-indent YAML mode'
adguardhome_yaml_remove_ipset_file || fail 'explicit-indent block YAML ipset_file cleanup failed'
assert_no_ipset_file explicit-indent-block
if grep -q 'explicit-indent-ipset.conf\|explicit-indent-continuation.conf' "${YAML_FILE}"; then
	fail 'explicit-indent block continuation was not removed'
fi
grep -q 'bootstrap_dns:' "${YAML_FILE}" || fail 'explicit-indent cleanup removed following dns key'
grep -q 'filtering:' "${YAML_FILE}" || fail 'explicit-indent cleanup removed following top-level key'

cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write folded block YAML ipset_file'
'dns':
  "ipset_file": >-
    folded-ipset.conf
    folded-continuation.conf
  bootstrap_dns:
    - 8.8.8.8
EOF_YAML
chmod 600 "${YAML_FILE}" || fail 'could not reset folded YAML mode'
adguardhome_yaml_remove_ipset_file || fail 'folded block YAML ipset_file cleanup failed'
assert_no_ipset_file folded-block
if grep -q 'folded-ipset.conf\|folded-continuation.conf' "${YAML_FILE}"; then
	fail 'folded block continuation was not removed'
fi
grep -q 'bootstrap_dns:' "${YAML_FILE}" || fail 'folded cleanup removed following dns key'

cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write YAML without ipset_file'
dns:
  bootstrap_dns:
    - 4.4.4.4
EOF_YAML
chmod 644 "${YAML_FILE}" || fail 'could not set no-op YAML mode'
adguardhome_yaml_remove_ipset_file || fail 'no-op YAML cleanup failed'
[ "$(mode_string "${YAML_FILE}")" = '-rw-r--r--' ] || fail 'no-op cleanup rewrote YAML permissions unexpectedly'
grep -q 'bootstrap_dns:' "${YAML_FILE}" || fail 'no-op cleanup changed YAML content'

cat >"${CONF_FILE}" <<'EOF_CONF' || fail 'could not write restored WAN config'
ADGUARD_INSTALL_MODE="wan"
ADGUARD_IPSET="YES"
EOF_CONF
cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write restored YAML ipset_file'
dns:
  ipset_file: restored-custom.conf
EOF_YAML
ADGUARD_INSTALL_MODE='lan'
adguard_enforce_lan_ipset_disabled || fail 'LAN enforcement failed for detected LAN/restored WAN config'
[ "$(conf_value ADGUARD_INSTALL_MODE)" = 'lan' ] || fail 'LAN enforcement did not persist detected LAN mode'
[ "$(conf_value ADGUARD_IPSET)" = 'NO' ] || fail 'LAN enforcement did not disable ADGUARD_IPSET'
assert_no_ipset_file detected-lan

cat >"${CONF_FILE}" <<'EOF_CONF' || fail 'could not write restored LAN config for detected WAN'
ADGUARD_INSTALL_MODE="lan"
ADGUARD_IPSET="NO"
ADGUARD_NETCHECK_MODE="lan"
EOF_CONF
cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write restored LAN YAML ipset_file for detected WAN'
dns:
  ipset_file: restored-lan-on-wan.conf
EOF_YAML
ADGUARD_INSTALL_MODE='wan'
adguard_enforce_lan_ipset_disabled || fail 'WAN detection did not override restored LAN config'
[ "$(conf_value ADGUARD_INSTALL_MODE)" = 'wan' ] || fail 'WAN detection was not persisted over restored LAN mode'
[ "$(conf_value ADGUARD_IPSET)" = 'NO' ] || fail 'WAN detection did not preserve restored ADGUARD_IPSET opt-out for WAN mode'
[ "$(conf_value ADGUARD_NETCHECK_MODE)" = 'wan' ] || fail 'WAN detection did not restore ADGUARD_NETCHECK_MODE for WAN mode'
[ "${ADGUARD_FORCE_SETUP_YAML:-0}" = '1' ] || fail 'WAN detection did not request YAML rebuild over restored LAN mode'
grep -q 'ipset_file: restored-lan-on-wan.conf' "${YAML_FILE}" || fail 'WAN detection unexpectedly removed restored ipset_file before setup rebuild'
ADGUARD_FORCE_SETUP_YAML=0

cat >"${CONF_FILE}" <<'EOF_CONF' || fail 'could not write stale LAN netcheck config for detected WAN'
ADGUARD_INSTALL_MODE="wan"
ADGUARD_IPSET="NO"
ADGUARD_NETCHECK_MODE="lan"
EOF_CONF
ADGUARD_INSTALL_MODE='wan'
adguard_enforce_lan_ipset_disabled || fail 'WAN detection did not correct stale LAN netcheck config'
[ "$(conf_value ADGUARD_IPSET)" = 'NO' ] || fail 'WAN detection did not preserve explicit ADGUARD_IPSET setting'
[ "$(conf_value ADGUARD_NETCHECK_MODE)" = 'lan' ] || fail 'WAN detection did not preserve explicit ADGUARD_NETCHECK_MODE setting'
[ "${ADGUARD_FORCE_SETUP_YAML:-0}" = '0' ] || fail 'WAN detection requested YAML rebuild without restored LAN install mode'
ADGUARD_FORCE_SETUP_YAML=0

cat >>"${CONF_FILE}" <<'EOF_CONF' || fail 'could not write WAN YAML sync preferences'
ADGUARD_WEBUI_PORT="3443"
ADGUARD_LAN_REVERSE_UPSTREAM="192.168.50.1"
EOF_CONF
cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write restored LAN YAML'
"http": # restored web settings
    "address": 192.168.50.1:3443
    session_ttl: 720h
users:
  - name: restored-user
    password: restored-password-hash
tls:
  enabled: true
  server_name: dns.example.test
"dns": # resolver settings
  'bind_hosts':
    - 127.0.0.1
  # Keep scanning bind hosts across comments at the key indentation.

    - 192.168.50.1
    - fd00::1
  'upstream_dns': # restored resolvers
    - '[/router.asus.com/]192.168.50.1:53'
    - tls://192.168.50.1:5353
    - https://dns.example/dns-query
  bootstrap_dns:
    - 192.168.50.1:53
    - 1.1.1.1
    - 1.0.0.1
  "local_ptr_upstreams": # restored PTR resolvers
    - '192.168.50.1:53'
filters:
  - enabled: true
    url: https://example.test/filter.txt
filtering:
  rewrites:
    - domain: printer.example.test
      answer: 192.168.50.20
access:
  allowed_clients:
    - 192.168.50.0/24
EOF_YAML
sed -e 's/restored-user/original-user/' \
	-e 's#https://dns.example/dns-query#https://original.example/dns-query#' \
	"${YAML_FILE}" >"${YAML_ORI}" || fail 'could not write distinct restored original YAML snapshot'
setup_sync_restored_yaml_and_snapshot_for_wan || fail 'could not synchronize restored LAN YAML for WAN mode'
grep -q '^    "address": 0.0.0.0:3443$' "${YAML_FILE}" || fail 'WAN YAML sync did not rewrite a quoted WebUI address key'
grep -q '^    session_ttl: 720h$' "${YAML_FILE}" || fail 'WAN YAML sync changed an HTTP sibling indentation'
[ "$(grep -c '^    - 0.0.0.0$' "${YAML_FILE}")" -eq 1 ] || fail 'WAN YAML sync did not replace DNS bind hosts'
! grep -q '^    - 192\.168\.50\.1$' "${YAML_FILE}" || fail 'WAN YAML sync retained a bind host after a comment and blank line'
! grep -q '^    - fd00::1$' "${YAML_FILE}" || fail 'WAN YAML sync retained a trailing bind host after a comment and blank line'
grep -Fq "[/router.asus.com/][::]:553" "${YAML_FILE}" || fail 'WAN YAML sync did not update reverse upstream'
grep -Fq -- "- '[::]:553'" "${YAML_FILE}" || fail 'WAN YAML sync did not update local PTR upstream'
grep -Fq "  'upstream_dns': # restored resolvers" "${YAML_FILE}" || fail 'WAN YAML sync changed a quoted, commented upstream header'
grep -Fq '  "local_ptr_upstreams": # restored PTR resolvers' "${YAML_FILE}" || fail 'WAN YAML sync changed a quoted, commented PTR header'
grep -Fq -- '- tls://192.168.50.1:5353' "${YAML_FILE}" || fail 'WAN YAML sync changed a partial reverse endpoint match'
grep -Fq -- '- 192.168.50.1:53' "${YAML_FILE}" || fail 'WAN YAML sync changed an endpoint outside reverse-upstream fields'
grep -q 'name: restored-user' "${YAML_FILE}" || fail 'WAN YAML sync removed restored credentials'
grep -q 'https://dns.example/dns-query' "${YAML_FILE}" || fail 'WAN YAML sync removed restored upstreams'
grep -q 'https://example.test/filter.txt' "${YAML_FILE}" || fail 'WAN YAML sync removed restored filters'
grep -q 'server_name: dns.example.test' "${YAML_FILE}" || fail 'WAN YAML sync removed restored TLS settings'
grep -q 'domain: printer.example.test' "${YAML_FILE}" || fail 'WAN YAML sync removed restored rewrites'
grep -q '192.168.50.0/24' "${YAML_FILE}" || fail 'WAN YAML sync removed restored access settings'
grep -q '^    "address": 0.0.0.0:3443$' "${YAML_ORI}" || fail 'WAN YAML sync left the quoted original WebUI snapshot in LAN mode'
grep -Fq -- "- '[/router.asus.com/][::]:553'" "${YAML_ORI}" || fail 'WAN YAML sync left the original reverse upstream snapshot in LAN mode'
grep -q 'name: original-user' "${YAML_ORI}" || fail 'WAN YAML sync replaced original snapshot credentials with working settings'
grep -q 'https://original.example/dns-query' "${YAML_ORI}" || fail 'WAN YAML sync replaced original snapshot upstreams with working settings'
! cmp -s "${YAML_FILE}" "${YAML_ORI}" || fail 'WAN YAML sync replaced the distinct original snapshot with the working YAML'

rm -f "${YAML_FILE}"
setup_sync_restored_yaml_and_snapshot_for_wan || fail 'could not synchronize restored original YAML without a working YAML'
cp -f "${YAML_ORI}" "${YAML_FILE}" || fail 'could not restore synchronized original YAML snapshot'
grep -q '^    "address": 0.0.0.0:3443$' "${YAML_FILE}" || fail 'original-only restore copied a quoted LAN WebUI address'
grep -Fq -- "- '[/router.asus.com/][::]:553'" "${YAML_FILE}" || fail 'original-only restore copied a LAN reverse upstream'

cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write restored inline bind hosts'
dns:
  "bind_hosts": [192.168.50.1, fd00::1] # restored LAN binds
  upstream_dns:
    - https://dns.example/dns-query
EOF_YAML
setup_sync_restored_yaml_for_wan || fail 'could not synchronize inline bind hosts for WAN mode'
grep -Fq '  "bind_hosts": [0.0.0.0] # restored LAN binds' "${YAML_FILE}" || fail 'WAN YAML sync did not normalize quoted inline bind hosts'
! grep -Fq '192.168.50.1, fd00::1' "${YAML_FILE}" || fail 'WAN YAML sync retained restored inline bind hosts'

cat >"${CONF_FILE}" <<'EOF_CONF' || fail 'could not write restored LAN config'
ADGUARD_INSTALL_MODE="lan"
ADGUARD_IPSET="YES"
EOF_CONF
cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write restored LAN YAML ipset_file'
dns:
  ipset_file: restored-lan.conf
EOF_YAML
ADGUARD_INSTALL_MODE=''
adguard_enforce_lan_ipset_disabled || fail 'LAN enforcement failed for restored LAN config'
[ "$(conf_value ADGUARD_INSTALL_MODE)" = 'lan' ] || fail 'LAN enforcement did not keep restored LAN mode'
[ "$(conf_value ADGUARD_IPSET)" = 'NO' ] || fail 'LAN enforcement did not disable restored ADGUARD_IPSET'
assert_no_ipset_file restored-lan

cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write YAML for nvram username ownership test'
dns:
  ipset_file: owner-ipset.conf
EOF_YAML
cat >"${STUB_DIR}/nvram" <<'EOF_NVRAM' || fail 'could not write nvram username stub'
#!/bin/sh
[ "$1" = "get" ] && [ "$2" = "http_username" ] && printf '%s\n' admin
EOF_NVRAM
chmod 755 "${STUB_DIR}/nvram" || fail 'could not chmod nvram username stub'
: >"${CHOWN_LOG}"
PATH="${STUB_DIR}:${PATH}" CHOWN_LOG="${CHOWN_LOG}" adguardhome_yaml_remove_ipset_file || fail 'nvram username YAML ownership cleanup failed'
grep -q "admin:root ${YAML_FILE}" "${CHOWN_LOG}" || fail 'YAML ownership did not use nvram http_username'
[ "$(mode_string "${YAML_FILE}")" = '-rw-------' ] || fail 'YAML mode was not secured with nvram username present'
assert_no_ipset_file nvram-owner

cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write YAML for failing ownership test'
dns:
  ipset_file: chown-fails.conf
EOF_YAML
chmod 644 "${YAML_FILE}" || fail 'could not set failing ownership YAML mode'
cat >"${STUB_DIR}/chown" <<'EOF_CHOWN_FAIL' || fail 'could not write failing chown stub'
#!/bin/sh
exit 1
EOF_CHOWN_FAIL
chmod 755 "${STUB_DIR}/chown" || fail 'could not chmod failing chown stub'
if PATH="${STUB_DIR}:${PATH}" adguardhome_yaml_remove_ipset_file; then
	fail 'cleanup succeeded despite failing YAML chown'
fi
[ "$(mode_string "${YAML_FILE}")" = '-rw-------' ] || fail 'YAML mode was not tightened before failing chown'
grep -q 'ipset_file: chown-fails.conf' "${YAML_FILE}" || fail 'failing chown path replaced YAML before securing metadata'
cat >"${STUB_DIR}/chown" <<'EOF_CHOWN' || fail 'could not restore chown stub'
#!/bin/sh
printf '%s %s\n' "$1" "$2" >>"${CHOWN_LOG}"
EOF_CHOWN
chmod 755 "${STUB_DIR}/chown" || fail 'could not chmod restored chown stub'

cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write YAML for empty nvram ownership test'
dns:
  ipset_file: root-ipset.conf
EOF_YAML
cat >"${STUB_DIR}/nvram" <<'EOF_NVRAM' || fail 'could not write empty nvram stub'
#!/bin/sh
exit 0
EOF_NVRAM
chmod 755 "${STUB_DIR}/nvram" || fail 'could not chmod empty nvram stub'
: >"${CHOWN_LOG}"
PATH="${STUB_DIR}:${PATH}" CHOWN_LOG="${CHOWN_LOG}" adguardhome_yaml_remove_ipset_file || fail 'empty nvram YAML ownership cleanup failed'
grep -q "root:root ${YAML_FILE}" "${CHOWN_LOG}" || fail 'YAML ownership did not fall back to root for empty nvram username'
[ "$(mode_string "${YAML_FILE}")" = '-rw-------' ] || fail 'YAML mode was not secured with empty nvram username'
assert_no_ipset_file nvram-empty-owner

printf '%s\n' 'PASS: LAN IPSET YAML cleanup covers simple, quoted, block, no-op, and restore paths'
