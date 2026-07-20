#!/bin/sh
# Verify LAN-mode IPSET enforcement clears inline mappings and ipset_file safely.

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

# cleanup removes the temporary test workspace.
cleanup() {
	rm -rf "${TMP_ROOT}"
}

# fail prints a failure message to standard error and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

# mode_string extracts the file type and permission bits for the specified path.
mode_string() {
	ls -ld "$1" | awk 'NR == 1 { print substr($1, 1, 10) }'
}

# extract_function appends the named function definition from the installer script to the functions file.
extract_function() {
	_function_name="$1"
	awk -v name="${_function_name}" '
		$0 == name "() {" { copying = 1 }
		copying {
			print
			line = $0
			opens = gsub(/\{/, "", line)
			line = $0
			closes = gsub(/\}/, "", line)
			depth += opens - closes
			if (depth == 0) exit
		}
	' "${SCRIPT_PATH}" >>"${FUNCTIONS_FILE}" || return 1
}

# write_conf updates a configuration key atomically, replacing its existing assignment or appending it when absent.
write_conf() {
	_key="$1"
	_value="$2"
	[ "${FAIL_WRITE_KEY:-}" != "${_key}" ] || return 1
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

# assert_no_ipset_file verifies that the YAML file does not contain an `ipset_file` entry.
assert_no_ipset_file() {
	if grep -q 'ipset_file' "${YAML_FILE}"; then
		fail "$1: ipset_file was not removed"
	fi
}

# assert_ipset_disabled verifies that inline IPSET mappings are cleared from the YAML configuration.
assert_ipset_disabled() {
	assert_no_ipset_file "$1"
	grep -q '^[[:space:]]*ipset: \[\]$' "${YAML_FILE}" || fail "$1: inline ipset mappings were not cleared"
	if grep -q 'example\.com/router\|example\.net/vpn' "${YAML_FILE}"; then
		fail "$1: inline ipset mapping entries were retained"
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
extract_function runtime_port_is_valid || fail 'could not extract runtime port validation helper'
extract_function setup_sync_mode_dependent_yaml || fail 'could not extract mode-dependent YAML sync helper'
extract_function setup_sync_restored_yaml_for_wan || fail 'could not extract WAN restore YAML sync helper'
extract_function setup_sync_mode_dependent_yaml_and_snapshot || fail 'could not extract mode-dependent YAML snapshot sync helper'
extract_function setup_sync_restored_yaml_and_snapshot_for_wan || fail 'could not extract WAN restore YAML snapshot sync helper'
extract_function restore_mode_migration_yaml || fail 'could not extract mode migration YAML rollback helper'
extract_function rollback_pending_mode_migration || fail 'could not extract pending mode migration rollback helper'
extract_function adguard_migrate_detected_install_mode || fail 'could not extract detected-mode migration helper'
[ -s "${FUNCTIONS_FILE}" ] || fail 'helper extraction was empty'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

cat >"${STUB_DIR}/chown" <<'EOF_CHOWN' || fail 'could not write chown stub'
#!/bin/sh
printf '%s %s\n' "$1" "$2" >>"${CHOWN_LOG}"
EOF_CHOWN
chmod 755 "${STUB_DIR}/chown" || fail 'could not chmod chown stub'

ERROR='Error:'
INFO='Info:'
ADDON_DIR="${TMP_ROOT}/addon"
# PTXT prints its arguments as text, one per line, ignoring an optional `-n` argument.
PTXT() {
	if [ "${1:-}" = "-n" ]; then
		shift
	fi
	printf '%s\n' "$@"
}

# backup_mode_migration_wan_hooks creates a test-local marker for retained hook rollback state.
backup_mode_migration_wan_hooks() {
	mkdir -p "$1"
}

# restore_mode_migration_wan_hooks removes the test-local hook rollback state unless retention is requested.
restore_mode_migration_wan_hooks() {
	[ "${2:-0}" = "1" ] || rm -rf "$1"
}

# install_wan_event_scripts simulates successful WAN hook synchronization.
install_wan_event_scripts() {
	return 0
}

# save_installer_config copies the installer configuration file to the specified backup path while preserving its metadata.
save_installer_config() {
	_backup="$1"
	cp -p "${CONF_FILE}" "${_backup}"
}

# restore_installer_config restores an installer configuration file from the specified source path.
restore_installer_config() {
	mv -f "$1" "${CONF_FILE}"
}

# discard_installer_config_backup removes the installer configuration backup and its absence marker.
discard_installer_config_backup() {
	rm -f "$1" "$1.absent"
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
ADGUARD_WEBUI_PORT="invalid"
ADGUARD_NETCHECK_MODE="wan"
EOF_CONF
cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write restored YAML ipset_file'
http:
  address: 0.0.0.0:8080
dns:
  bind_hosts:
    - 0.0.0.0
  ipset:
    - example.com/router
    - example.net/vpn
  ipset_file: restored-custom.conf
  local_ptr_upstreams:
    - '[::]:553'
EOF_YAML
cp -f "${YAML_FILE}" "${YAML_ORI}" || fail 'could not write restored original WAN YAML snapshot'
# setup_resolve_bind_addresses sets the Web UI address and DNS bind hosts for LAN mode.
setup_resolve_bind_addresses() {
	SETUP_WEB_ADDRESS="192.168.50.2:${WEB_PORT}"
	SETUP_DNS_BIND_HOST='192.168.50.2'
	SETUP_DNS_BIND_HOST6='fd00::2'
}
# setup_reverse_upstream_target sets the reverse DNS upstream target to `192.168.50.1:53`.
setup_reverse_upstream_target() {
	SETUP_REVERSE_UPSTREAM='192.168.50.1:53'
}
# setup_private_ipv4_bridge_dns_binds configures private IPv4 bridge DNS bind addresses.
setup_private_ipv4_bridge_dns_binds() {
	return 0
}
ADGUARD_INSTALL_MODE='lan'
adguard_enforce_lan_ipset_disabled || fail 'LAN enforcement failed for detected LAN/restored WAN config'
[ "$(conf_value ADGUARD_INSTALL_MODE)" = 'lan' ] || fail 'LAN enforcement did not persist detected LAN mode'
[ "$(conf_value ADGUARD_IPSET)" = 'NO' ] || fail 'LAN enforcement did not disable ADGUARD_IPSET'
[ "$(conf_value ADGUARD_NETCHECK_MODE)" = 'lan' ] || fail 'LAN enforcement did not reset restored WAN netcheck mode'
assert_ipset_disabled detected-lan
[ "${ADGUARD_FORCE_SETUP_YAML:-0}" = '1' ] || fail 'LAN detection did not request YAML rebuild over restored WAN mode'
setup_sync_mode_dependent_yaml_and_snapshot || fail 'could not synchronize restored WAN YAML for LAN mode'
for restored_yaml in "${YAML_FILE}" "${YAML_ORI}"; do
	grep -q '^  address: 192\.168\.50\.2:8080$' "${restored_yaml}" || fail 'LAN restore sync did not preserve the YAML WebUI port'
	grep -Fq '    - 192.168.50.2' "${restored_yaml}" || fail 'LAN restore sync did not add the LAN DNS bind'
	! grep -Fq -- '- 0.0.0.0' "${restored_yaml}" || fail 'LAN restore sync retained the WAN wildcard DNS bind'
	grep -Fq -- "- '192.168.50.1:53'" "${restored_yaml}" || fail 'LAN restore sync did not replace the WAN reverse target'
	grep -q '^[[:space:]]*ipset: \[\]$' "${restored_yaml}" || fail 'LAN restore sync did not retain disabled inline IPSET state'
	! grep -q 'example\.com/router\|example\.net/vpn' "${restored_yaml}" || fail 'LAN restore sync retained inline IPSET mappings'
done
ADGUARD_FORCE_SETUP_YAML=0

cat >"${CONF_FILE}" <<'EOF_CONF' || fail 'could not write legacy restored config without install mode'
ADGUARD_IPSET="YES"
ADGUARD_WEBUI_PORT="8080"
ADGUARD_NETCHECK_MODE="wan"
EOF_CONF
cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write legacy restored WAN YAML'
http:
  address: 0.0.0.0:8080
dns:
  bind_hosts:
    - 0.0.0.0
  local_ptr_upstreams:
    - '[::]:553'
EOF_YAML
cp -f "${YAML_FILE}" "${YAML_ORI}" || fail 'could not write legacy restored WAN YAML snapshot'
ADGUARD_INSTALL_MODE='lan'
adguard_enforce_lan_ipset_disabled || fail 'LAN enforcement failed for legacy restored WAN config'
[ "$(conf_value ADGUARD_INSTALL_MODE)" = 'lan' ] || fail 'legacy restore did not persist detected LAN mode'
[ "$(conf_value ADGUARD_NETCHECK_MODE)" = 'lan' ] || fail 'legacy restore did not select LAN netcheck mode'
[ "${ADGUARD_FORCE_SETUP_YAML:-0}" = '1' ] || fail 'legacy restore did not request WAN YAML synchronization'
setup_sync_mode_dependent_yaml_and_snapshot || fail 'could not synchronize legacy restored WAN YAML'
for restored_yaml in "${YAML_FILE}" "${YAML_ORI}"; do
	grep -q '^  address: 192\.168\.50\.2:8080$' "${restored_yaml}" || fail 'legacy restore did not scope the WebUI address'
	grep -Fq '    - 192.168.50.2' "${restored_yaml}" || fail 'legacy restore did not add the LAN DNS bind'
	! grep -Fq -- '- 0.0.0.0' "${restored_yaml}" || fail 'legacy restore retained the WAN wildcard DNS bind'
	grep -Fq -- "- '192.168.50.1:53'" "${restored_yaml}" || fail 'legacy restore did not replace the WAN reverse target'
done
ADGUARD_FORCE_SETUP_YAML=0

cat >"${CONF_FILE}" <<'EOF_CONF' || fail 'could not write legacy config without install mode'
ADGUARD_IPSET="YES"
ADGUARD_WEBUI_PORT="3000"
ADGUARD_NETCHECK_MODE="legacy"
EOF_CONF
cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write legacy LAN working YAML'
http:
  address: 0.0.0.0:3000
dns:
  bind_hosts:
    - 0.0.0.0
  ipset:
    - example.com/router
  ipset_file: legacy-ipset.conf
  local_ptr_upstreams:
    - '[::]:553'
EOF_YAML
cp -f "${YAML_FILE}" "${YAML_ORI}" || fail 'could not write legacy LAN original YAML snapshot'
# adguard_install_feature_defaults sets default IPSET and DNSMASQ feature configuration values.
adguard_install_feature_defaults() {
	write_conf ADGUARD_IPSET '"NO"' || return 1
	write_conf ADGUARD_DNSMASQ_MODE '"auto"'
}
ADGUARD_INSTALL_MODE='lan'
adguard_migrate_detected_install_mode '' || fail 'legacy install without a saved mode was not migrated to LAN mode'
[ "$(conf_value ADGUARD_INSTALL_MODE)" = 'lan' ] || fail 'legacy LAN migration did not persist detected mode'
[ "$(conf_value ADGUARD_IPSET)" = 'NO' ] || fail 'legacy LAN migration did not disable IPSET'
[ "$(conf_value ADGUARD_DNSMASQ_MODE)" = 'auto' ] || fail 'legacy LAN migration did not apply LAN feature defaults'
[ "$(conf_value ADGUARD_NETCHECK_MODE)" = 'lan' ] || fail 'legacy LAN migration did not update netcheck mode'
for legacy_yaml in "${YAML_FILE}" "${YAML_ORI}"; do
	grep -q '^  address: 192\.168\.50\.2:3000$' "${legacy_yaml}" || fail 'legacy LAN migration did not scope the WebUI address'
	grep -Fq '    - 192.168.50.2' "${legacy_yaml}" || fail 'legacy LAN migration did not add the LAN DNS bind'
	! grep -Fq -- '- 0.0.0.0' "${legacy_yaml}" || fail 'legacy LAN migration retained the WAN wildcard DNS bind'
	grep -Fq -- "- '192.168.50.1:53'" "${legacy_yaml}" || fail 'legacy LAN migration did not replace the WAN reverse target'
	grep -q '^[[:space:]]*ipset: \[\]$' "${legacy_yaml}" || fail 'legacy LAN migration did not disable inline IPSET mappings'
	! grep -q 'ipset_file\|example\.com/router' "${legacy_yaml}" || fail 'legacy LAN migration retained an IPSET pathway'
done

for failed_key in ADGUARD_INSTALL_MODE ADGUARD_IPSET ADGUARD_DNSMASQ_MODE ADGUARD_NETCHECK_MODE; do
	cat >"${CONF_FILE}" <<'EOF_CONF' || fail "could not reset config for ${failed_key} rollback"
ADGUARD_WEBUI_PORT="3000"
ADGUARD_INSTALL_MODE="wan"
ADGUARD_IPSET="YES"
ADGUARD_DNSMASQ_MODE="enabled"
ADGUARD_NETCHECK_MODE="wan"
EOF_CONF
	cat >"${YAML_FILE}" <<'EOF_YAML' || fail "could not reset working YAML for ${failed_key} rollback"
http:
  address: 0.0.0.0:3000
dns:
  bind_hosts:
    - 0.0.0.0
  ipset_file: rollback-ipset.conf
EOF_YAML
	cp -p "${YAML_FILE}" "${YAML_ORI}" || fail "could not reset original YAML for ${failed_key} rollback"
	cp -p "${CONF_FILE}" "${TMP_ROOT}/config.before-${failed_key}" || fail "could not preserve config for ${failed_key} rollback"
	cp -p "${YAML_FILE}" "${TMP_ROOT}/working.before-${failed_key}" || fail "could not preserve working YAML for ${failed_key} rollback"
	cp -p "${YAML_ORI}" "${TMP_ROOT}/original.before-${failed_key}" || fail "could not preserve original YAML for ${failed_key} rollback"
	FAIL_WRITE_KEY="${failed_key}"
	if adguard_migrate_detected_install_mode wan; then
		fail "mode migration ignored ${failed_key} persistence failure"
	fi
	FAIL_WRITE_KEY=''
	cmp -s "${TMP_ROOT}/config.before-${failed_key}" "${CONF_FILE}" || fail "${failed_key} failure did not restore installer config"
	cmp -s "${TMP_ROOT}/working.before-${failed_key}" "${YAML_FILE}" || fail "${failed_key} failure did not restore working YAML"
	cmp -s "${TMP_ROOT}/original.before-${failed_key}" "${YAML_ORI}" || fail "${failed_key} failure did not restore original YAML"
	[ ! -e "${YAML_FILE}.mode-migration.rollback.$$" ] || fail "${failed_key} failure left a working YAML rollback file"
	[ ! -e "${YAML_ORI}.mode-migration.rollback.$$" ] || fail "${failed_key} failure left an original YAML rollback file"
	[ ! -e "${CONF_FILE}.mode-migration.rollback.$$" ] || fail "${failed_key} failure left a config rollback file"
done

cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write rollback working YAML'
http:
  address: 0.0.0.0:3000
dns:
  bind_hosts:
    - 0.0.0.0
EOF_YAML
cp -f "${YAML_FILE}" "${TMP_ROOT}/working-yaml.before-sync" || fail 'could not preserve rollback working YAML'
cat >"${YAML_ORI}" <<'EOF_YAML' || fail 'could not write malformed original YAML snapshot'
dns: []
EOF_YAML
cp -f "${YAML_ORI}" "${TMP_ROOT}/original-yaml.before-sync" || fail 'could not preserve malformed original YAML snapshot'
if setup_sync_mode_dependent_yaml_and_snapshot; then
	fail 'mode-dependent synchronization accepted a malformed original YAML snapshot'
fi
cmp -s "${TMP_ROOT}/working-yaml.before-sync" "${YAML_FILE}" || fail 'failed snapshot synchronization changed the working YAML'
cmp -s "${TMP_ROOT}/original-yaml.before-sync" "${YAML_ORI}" || fail 'failed snapshot synchronization changed the original YAML snapshot'
[ ! -e "${YAML_FILE}.mode-sync.$$" ] || fail 'failed snapshot synchronization left a working YAML stage'
[ ! -e "${YAML_ORI}.mode-sync.$$" ] || fail 'failed snapshot synchronization left an original YAML stage'
[ ! -e "${YAML_FILE}.mode-sync.rollback.$$" ] || fail 'failed snapshot synchronization left a working YAML rollback file'

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
ADGUARD_WEBUI_PORT="invalid"
ADGUARD_LAN_REVERSE_UPSTREAM="192.168.50.1"
EOF_CONF
cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write restored LAN YAML'
"http": &http_settings # restored web settings
    "address": "192.168.50.1:3443" # restored WebUI: HTTPS
    session_ttl: 720h
users:
  - name: restored-user
    password: restored-password-hash
tls:
  enabled: true
  server_name: dns.example.test
"dns": &dns_settings # resolver settings
  'bind_hosts':
    - 127.0.0.1
  # Keep scanning bind hosts across comments at the key indentation.

    - 192.168.50.1
    - fd00::1
  'upstream_dns': # restored resolvers
    - '[/router.asus.com/]192.168.50.1:53'
    - '192.168.50.1:53'
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
grep -Fq '"http": &http_settings # restored web settings' "${YAML_FILE}" || fail 'WAN YAML sync changed an anchored HTTP header'
grep -q '^    "address": 0.0.0.0:3443$' "${YAML_FILE}" || fail 'WAN YAML sync did not rewrite a quoted WebUI address key'
grep -q '^    session_ttl: 720h$' "${YAML_FILE}" || fail 'WAN YAML sync changed an HTTP sibling indentation'
[ "$(grep -c '^    - 0.0.0.0$' "${YAML_FILE}")" -eq 1 ] || fail 'WAN YAML sync did not replace DNS bind hosts'
grep -Fq '"dns": &dns_settings # resolver settings' "${YAML_FILE}" || fail 'WAN YAML sync changed an anchored DNS header'
! grep -q '^    - 192\.168\.50\.1$' "${YAML_FILE}" || fail 'WAN YAML sync retained a bind host after a comment and blank line'
! grep -q '^    - fd00::1$' "${YAML_FILE}" || fail 'WAN YAML sync retained a trailing bind host after a comment and blank line'
grep -Fq "[/router.asus.com/][::]:553" "${YAML_FILE}" || fail 'WAN YAML sync did not update reverse upstream'
grep -Fq -- "- '[::]:553'" "${YAML_FILE}" || fail 'WAN YAML sync did not update local PTR upstream'
grep -Fq -- "- '192.168.50.1:53'" "${YAML_FILE}" || fail 'WAN YAML sync changed a plain general upstream matching the reverse target'
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

cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write restored indentationless bind hosts'
dns:
  bind_hosts:
  - 127.0.0.1
  # Keep scanning indentationless bind hosts across comments.

  - 192.168.50.1
  - fd00::1
  upstream_dns:
  - https://dns.example/dns-query
EOF_YAML
setup_sync_restored_yaml_for_wan || fail 'could not synchronize indentationless bind hosts for WAN mode'
[ "$(grep -c '^    - 0.0.0.0$' "${YAML_FILE}")" -eq 1 ] || fail 'WAN YAML sync did not add a wildcard for indentationless bind hosts'
! grep -Eq '^  - (127\.0\.0\.1|192\.168\.50\.1|fd00::1)$' "${YAML_FILE}" || fail 'WAN YAML sync retained an indentationless bind host'
grep -Fq '  - https://dns.example/dns-query' "${YAML_FILE}" || fail 'WAN YAML sync removed a sibling indentationless upstream'

for flow_yaml in \
	'http: {address: 192.168.50.1:3443}' \
	'dns: {bind_hosts: [192.168.50.1]}' \
	'dns:\n  upstream_dns: [192.168.50.1:53]' \
	'dns:\n  local_ptr_upstreams: [192.168.50.1:53]'; do
	printf '%b\n' "${flow_yaml}" >"${YAML_FILE}" || fail 'could not write restored flow-style YAML'
	cp -f "${YAML_FILE}" "${YAML_FILE}.before" || fail 'could not preserve restored flow-style YAML'
	! setup_sync_restored_yaml_for_wan || fail 'WAN YAML sync silently accepted an unsupported flow-style mapping or collection'
	cmp -s "${YAML_FILE}" "${YAML_FILE}.before" || fail 'WAN YAML sync changed YAML after rejecting unsupported flow style'
done
rm -f "${YAML_FILE}.before"

cat >"${CONF_FILE}" <<'EOF_CONF' || fail 'could not write WAN-to-LAN sync preferences'
ADGUARD_WEBUI_PORT=""
ADGUARD_LAN_REVERSE_UPSTREAM="192.168.50.254"
EOF_CONF
cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write WAN YAML for LAN-mode migration'
http:
  address: 0.0.0.0:443
dns:
  bind_hosts:
    - 0.0.0.0
  upstream_dns:
    - '[/router.asus.com/][::]:553'
    - '[::]:553'
  local_ptr_upstreams:
    - '[::]:553'
EOF_YAML
rm -f "${YAML_ORI}"
# setup_resolve_bind_addresses sets the web address and IPv4 and IPv6 DNS bind hosts used for LAN-mode configuration.
setup_resolve_bind_addresses() {
	SETUP_WEB_ADDRESS="192.168.50.2:${WEB_PORT}"
	SETUP_DNS_BIND_HOST='192.168.50.2'
	SETUP_DNS_BIND_HOST6='fd00::2'
}
# setup_reverse_upstream_target sets the reverse DNS upstream target to 192.168.50.254:53.
setup_reverse_upstream_target() {
	SETUP_REVERSE_UPSTREAM='192.168.50.254:53'
}
# setup_private_ipv4_bridge_dns_binds outputs the private IPv4 bridge DNS bind address.
setup_private_ipv4_bridge_dns_binds() {
	printf '%s\n' '192.168.60.1'
}
ADGUARD_INSTALL_MODE='lan'
setup_sync_mode_dependent_yaml_and_snapshot || fail 'could not migrate WAN YAML to detected LAN mode'
grep -q '^  address: 192\.168\.50\.2:443$' "${YAML_FILE}" || fail 'LAN mode migration did not preserve the low WebUI port'
for bind_host in 127.0.0.1 192.168.50.2 fd00::2 192.168.60.1; do
	grep -Fq "    - ${bind_host}" "${YAML_FILE}" || fail "LAN mode migration omitted DNS bind ${bind_host}"
done
! grep -Fq -- '- 0.0.0.0' "${YAML_FILE}" || fail 'LAN mode migration retained the WAN wildcard DNS bind'
grep -Fq '[/router.asus.com/]192.168.50.254:53' "${YAML_FILE}" || fail 'LAN mode migration did not update the reverse upstream'
grep -Fq -- "- '[::]:553'" "${YAML_FILE}" || fail 'LAN mode migration changed a plain general upstream matching the reverse target'
grep -Fq -- "- '192.168.50.254:53'" "${YAML_FILE}" || fail 'LAN mode migration did not update the local PTR upstream'

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
