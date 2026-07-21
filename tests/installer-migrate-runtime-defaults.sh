#!/bin/sh
# Verify runtime default migration reports legacy values and only writes with --yes.

set -u

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-migrate-runtime-defaults.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions"

cleanup() {
	rm -rf "${TMP_ROOT}"
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
mkdir -p "${TMP_ROOT}" || fail 'could not create test directory'

sed -n \
	'/^_quote() {$/,/^}$/p; /^PTXT() {$/,/^}$/p; /^ptxt_ok() {$/,/^}$/p; /^conf_value() {$/,/^}$/p; /^write_conf() {$/,/^}$/p; /^adguardhome_yaml_ipset_file() {$/,/^}$/p; /^adguardhome_yaml_secure_file() {$/,/^}$/p; /^adguardhome_yaml_remove_ipset_file() {$/,/^}$/p; /^branch_is_safe() {$/,/^}$/p; /^cli_bool_value() {$/,/^}$/p; /^cli_adguard_branch_is_valid() {$/,/^}$/p; /^cli_simple_value_is_safe() {$/,/^}$/p; /^cli_host_list_is_safe() {$/,/^}$/p; /^cli_write_quoted_conf() {$/,/^}$/p; /^cli_netcheck_config_values() {$/,/^}$/p; /^cli_dns_port_policy() {$/,/^}$/p; /^cli_migrate_runtime_default() {$/,/^}$/p; /^cli_migrate_runtime_defaults() {$/,/^}$/p; /^cli_installer_branch_from_args() {$/,/^}$/p; /^cli_write_adguard_branch() {$/,/^}$/p; /^cli_run() {$/,/^}$/p; /^cli_pre_runtime_defaults_preview() {$/,/^}$/p' \
	"${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" || fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTIONS_FILE}" ] || fail 'runtime migration helper extraction was empty'
grep -q '^cli_migrate_runtime_defaults() {$' "${FUNCTIONS_FILE}" || fail 'migration helper missing'
grep -q '^cli_pre_runtime_defaults_preview() {$' "${FUNCTIONS_FILE}" || fail 'migration preview short-circuit missing'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

INFO='[i]'
WARNING='[w]'
ERROR='[!]'
CONF_FILE="${TMP_ROOT}/.config"
YAML_FILE="${TMP_ROOT}/AdGuardHome.yaml"
TARG_DIR="${TMP_ROOT}"

# cli_require_yes is a no-op that succeeds without requiring confirmation.
cli_require_yes() {
	return 0
}

cli_enable_assume_yes() {
	return 0
}

menu() {
	fail "menu should not be called by migrate-runtime-defaults CLI"
}

cat >"${CONF_FILE}" <<'CONFIG'
ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="0"
ADGUARD_NETCHECK_MODE="legacy"
ADGUARD_PROC_OPTIMIZE="YES"
ADGUARD_PROC_PROFILE="aggressive"
CONFIG

before="$(cat "${CONF_FILE}")"
cli_migrate_runtime_defaults >"${TMP_ROOT}/report" || fail 'report-only migration failed'
[ "$(cat "${CONF_FILE}")" = "${before}" ] || fail 'report-only migration changed .config'
grep -q 'Legacy runtime default: ADGUARD_NETCHECK_MODE="legacy"' "${TMP_ROOT}/report" || fail 'legacy netcheck value was not reported'
grep -q 'No changes made. Re-run with --yes' "${TMP_ROOT}/report" || fail 'report-only migration did not explain --yes'

cli_migrate_runtime_defaults --dry-run >"${TMP_ROOT}/dry-run" || fail 'dry-run migration failed'
[ "$(cat "${CONF_FILE}")" = "${before}" ] || fail 'dry-run migration changed .config'
grep -q 'Dry-run: would write v2.6.0 safer runtime defaults' "${TMP_ROOT}/dry-run" || fail 'dry-run did not report planned writes'

cli_pre_runtime_defaults_preview migrate-runtime-defaults >"${TMP_ROOT}/preview-report" ||
	fail 'preview short-circuit did not run report-only migration'
[ "$(cat "${CONF_FILE}")" = "${before}" ] || fail 'preview report changed .config before startup'
cli_pre_runtime_defaults_preview migrate-runtime-defaults --dry-run >"${TMP_ROOT}/preview-dry-run" ||
	fail 'preview short-circuit did not run dry-run migration'
[ "$(cat "${CONF_FILE}")" = "${before}" ] || fail 'preview dry-run changed .config before startup'
grep -q 'Dry-run: would write v2.6.0 safer runtime defaults' "${TMP_ROOT}/preview-dry-run" ||
	fail 'preview dry-run did not report planned writes'
if cli_pre_runtime_defaults_preview migrate-runtime-defaults --yes >/dev/null; then
	fail 'preview short-circuit should not apply migrations before startup'
fi

cli_run migrate-runtime-defaults --dry-run >"${TMP_ROOT}/cli-dry-run" || fail 'CLI dry-run migration failed'
[ "$(cat "${CONF_FILE}")" = "${before}" ] || fail 'CLI dry-run migration changed .config'
grep -q 'Dry-run: would write v2.6.0 safer runtime defaults' "${TMP_ROOT}/cli-dry-run" ||
	fail 'CLI dry-run did not report planned writes'

cli_run migrate-runtime-defaults --yes >"${TMP_ROOT}/apply" || fail 'CLI apply migration failed'
grep -q '^ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="1"$' "${CONF_FILE}" || fail 'DNS port policy was not migrated'
grep -q '^ADGUARD_NETCHECK_MODE="wan"$' "${CONF_FILE}" || fail 'netcheck mode was not migrated'
grep -q '^ADGUARD_PROC_OPTIMIZE="YES"$' "${CONF_FILE}" || fail 'process optimization was not preserved'
grep -q '^ADGUARD_PROC_PROFILE="balanced"$' "${CONF_FILE}" || fail 'process profile was not migrated'

cat >"${CONF_FILE}" <<'CONFIG'
ADGUARD_INSTALL_MODE="lan"
ADGUARD_IPSET="YES"
ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="1"
ADGUARD_NETCHECK_MODE="legacy"
ADGUARD_PROC_OPTIMIZE="YES"
ADGUARD_PROC_PROFILE="balanced"
CONFIG

cat >"${YAML_FILE}" <<'YAML'
dns:
  bind_hosts:
  - 0.0.0.0
  ipset:
  - example.com/router
  ipset_file: ipset.conf
  port: 53
YAML
# Startup detection may leave the shell variable at its newly detected value,
# but migration must follow the install mode already persisted for this install.
ADGUARD_INSTALL_MODE="wan"
cli_run migrate-runtime-defaults --yes >"${TMP_ROOT}/lan-apply" || fail 'LAN-mode apply migration failed'
grep -q '^ADGUARD_INSTALL_MODE="lan"$' "${CONF_FILE}" || fail 'LAN install mode was not preserved'
grep -q '^ADGUARD_IPSET="NO"$' "${CONF_FILE}" || fail 'LAN-mode IPSET was not disabled during migration'
grep -q '^ADGUARD_NETCHECK_MODE="lan"$' "${CONF_FILE}" || fail 'LAN-mode netcheck was not migrated to lan'
if grep -q 'ipset_file' "${YAML_FILE}"; then
	fail 'LAN-mode migration did not remove dns.ipset_file from YAML'
fi
grep -q '^[[:space:]]*ipset: \[\]$' "${YAML_FILE}" || fail 'LAN-mode migration did not clear inline dns.ipset mappings'
if grep -q 'example\.com/router' "${YAML_FILE}"; then
	fail 'LAN-mode migration retained an inline dns.ipset mapping'
fi
if grep -q '^ADGUARD_NETCHECK_MODE="wan"$' "${CONF_FILE}"; then
	fail 'LAN-mode migration regressed to WAN netcheck mode'
fi

cat >"${CONF_FILE}" <<'CONFIG'
ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="0"
ADGUARD_NETCHECK_MODE="lan"
ADGUARD_PROC_OPTIMIZE="NO"
ADGUARD_PROC_PROFILE="balanced"
CONFIG

cli_migrate_runtime_defaults --yes >"${TMP_ROOT}/mixed-apply" || fail 'mixed custom apply migration failed'
grep -q '^ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="1"$' "${CONF_FILE}" || fail 'mixed DNS port policy was not migrated'
grep -q '^ADGUARD_NETCHECK_MODE="lan"$' "${CONF_FILE}" || fail 'custom netcheck mode was overwritten'
grep -q '^ADGUARD_PROC_OPTIMIZE="NO"$' "${CONF_FILE}" || fail 'custom process optimization was overwritten'
grep -q '^ADGUARD_PROC_PROFILE="balanced"$' "${CONF_FILE}" || fail 'custom process profile was overwritten'

printf '%s\n' 'PASS: runtime defaults migration reports and applies expected values'
