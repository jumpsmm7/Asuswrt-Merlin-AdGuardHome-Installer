#!/bin/sh
# Verify v2.6.0 runtime defaults, upgrade preservation, and migration paths.

set -u

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

INSTALLER_PATH="${1:-installer}"
S99_PATH="${2:-S99AdGuardHome}"
MANAGER_PATH="${3:-AdGuardHome.sh}"
TMP_ROOT="${TMPDIR:-/tmp}/runtime-default-regression.$$"
INSTALLER_FUNCTIONS="${TMP_ROOT}/installer-functions"
S99_FUNCTIONS="${TMP_ROOT}/s99-functions"

cleanup() {
	rm -rf "${TMP_ROOT}"
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

[ -f "${INSTALLER_PATH}" ] || fail "installer script not found: ${INSTALLER_PATH}"
[ -f "${S99_PATH}" ] || fail "S99 script not found: ${S99_PATH}"
[ -f "${MANAGER_PATH}" ] || fail "manager script not found: ${MANAGER_PATH}"
mkdir -p "${TMP_ROOT}" || fail 'could not create test directory'

sed -n \
	'/^_quote() {$/,/^}$/p; /^PTXT() {$/,/^}$/p; /^ptxt_ok() {$/,/^}$/p; /^conf_value() {$/,/^}$/p; /^conf_has_key() {$/,/^}$/p; /^write_conf_if_absent() {$/,/^}$/p; /^ipv4_is_valid() {$/,/^}$/p; /^adguard_install_feature_defaults() {$/,/^}$/p; /^write_conf() {$/,/^}$/p; /^cli_write_quoted_conf() {$/,/^}$/p; /^configure_runtime_defaults() {$/,/^}$/p; /^cli_migrate_runtime_default() {$/,/^}$/p; /^cli_migrate_runtime_defaults() {$/,/^}$/p' \
	"${INSTALLER_PATH}" >"${INSTALLER_FUNCTIONS}" || fail 'could not extract installer runtime helpers'
grep -q '^adguard_install_feature_defaults() {$' "${INSTALLER_FUNCTIONS}" || fail 'install feature defaults helper missing'
grep -q '^configure_runtime_defaults() {$' "${INSTALLER_FUNCTIONS}" || fail 'configure_runtime_defaults helper missing'
grep -q '^cli_migrate_runtime_defaults() {$' "${INSTALLER_FUNCTIONS}" || fail 'runtime migration helper missing'

sed -n '/^dns_port_unknown_refusal_enabled() {$/,/^}$/p' "${S99_PATH}" >"${S99_FUNCTIONS}" ||
	fail 'could not extract S99 DNS refusal helper'
grep -q '^dns_port_unknown_refusal_enabled() {$' "${S99_FUNCTIONS}" || fail 'DNS refusal helper missing'

# shellcheck disable=SC1090
. "${INSTALLER_FUNCTIONS}"
INFO='[i]'
WARNING='[w]'
ERROR='[!]'

CONF_FILE="${TMP_ROOT}/new-wan.config"
ADGUARD_INSTALL_MODE="wan"
adguard_install_feature_defaults >"${TMP_ROOT}/feature-wan.out" || fail 'WAN install feature defaults failed'
grep -q '^ADGUARD_IPSET="YES"$' "${CONF_FILE}" || fail 'WAN feature defaults did not preserve default IPSET enablement'
grep -q '^ADGUARD_DNSMASQ_MODE="enabled"$' "${CONF_FILE}" || fail 'WAN feature defaults did not save enabled DNSMasq mode'
configure_runtime_defaults new-install wan 0 >"${TMP_ROOT}/new-wan.out" || fail 'new WAN defaults failed'
grep -q '^ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="1"$' "${CONF_FILE}" || fail 'new WAN install did not refuse unknown DNS owners'
grep -q '^ADGUARD_INSTALL_MODE="wan"$' "${CONF_FILE}" || fail 'new WAN install did not save wan install mode'
grep -q '^ADGUARD_NETCHECK_MODE="wan"$' "${CONF_FILE}" || fail 'new WAN install did not save wan netcheck mode'
grep -q '^ADGUARD_PROC_OPTIMIZE="YES"$' "${CONF_FILE}" || fail 'new WAN install did not enable balanced optimization'
grep -q '^ADGUARD_PROC_PROFILE="balanced"$' "${CONF_FILE}" || fail 'new WAN install did not save balanced profile'

CONF_FILE="${TMP_ROOT}/feature-wan-existing-no.config"
printf '%s\n' 'ADGUARD_IPSET="NO"' >"${CONF_FILE}" || fail 'could not seed WAN feature config'
ADGUARD_INSTALL_MODE="wan"
adguard_install_feature_defaults >"${TMP_ROOT}/feature-wan-existing-no.out" || fail 'WAN existing IPSET feature defaults failed'
grep -q '^ADGUARD_IPSET="NO"$' "${CONF_FILE}" || fail 'WAN feature defaults overwrote explicit IPSET disablement'
grep -q '^ADGUARD_DNSMASQ_MODE="enabled"$' "${CONF_FILE}" || fail 'WAN existing feature defaults did not save enabled DNSMasq mode'

CONF_FILE="${TMP_ROOT}/new-lan.config"
# nvram returns the configured LAN gateway address for supported queries and fails for all other queries.
nvram() {
	case "${1:-}:${2:-}" in
		get:lan_gateway) printf '%s\n' 192.168.50.1 ;;
		*) return 1 ;;
	esac
}
printf '%s\n' 'ADGUARD_IPSET="YES"' 'ADGUARD_DNSMASQ_MODE="enabled"' >"${CONF_FILE}" || fail 'could not seed LAN feature config'
ADGUARD_INSTALL_MODE="lan"
adguard_install_feature_defaults >"${TMP_ROOT}/feature-lan.out" || fail 'LAN install feature defaults failed'
grep -q '^ADGUARD_IPSET="NO"$' "${CONF_FILE}" || fail 'LAN feature defaults did not force IPSET disablement'
grep -q '^ADGUARD_DNSMASQ_MODE="auto"$' "${CONF_FILE}" || fail 'LAN feature defaults did not force auto DNSMasq mode'
grep -q '^ADGUARD_LAN_REVERSE_UPSTREAM="192.168.50.1"$' "${CONF_FILE}" || fail 'LAN feature defaults did not save detected gateway reverse upstream'

CONF_FILE="${TMP_ROOT}/new-lan-disabled.config"
printf '%s\n' 'ADGUARD_DNSMASQ_MODE="disabled"' >"${CONF_FILE}" || fail 'could not seed disabled LAN dnsmasq mode'
ADGUARD_INSTALL_MODE="lan"
adguard_install_feature_defaults >"${TMP_ROOT}/feature-lan-disabled.out" || fail 'disabled LAN dnsmasq defaults failed'
grep -q '^ADGUARD_DNSMASQ_MODE="disabled"$' "${CONF_FILE}" || fail 'LAN feature defaults overwrote explicit disabled dnsmasq mode'

CONF_FILE="${TMP_ROOT}/new-lan-existing-reverse.config"
printf '%s\n' 'ADGUARD_LAN_REVERSE_UPSTREAM="192.168.60.1"' >"${CONF_FILE}" || fail 'could not seed LAN reverse upstream config'
ADGUARD_INSTALL_MODE="lan"
adguard_install_feature_defaults >"${TMP_ROOT}/feature-lan-existing-reverse.out" || fail 'LAN existing reverse upstream feature defaults failed'
grep -q '^ADGUARD_LAN_REVERSE_UPSTREAM="192.168.60.1"$' "${CONF_FILE}" || fail 'LAN feature defaults overwrote explicit reverse upstream'

CONF_FILE="${TMP_ROOT}/new-lan.config"
configure_runtime_defaults new-install lan 1 >"${TMP_ROOT}/new-lan.out" || fail 'new LAN defaults failed'
grep -q '^ADGUARD_INSTALL_MODE="lan"$' "${CONF_FILE}" || fail 'new LAN install did not save lan install mode'
grep -q '^ADGUARD_NETCHECK_MODE="lan"$' "${CONF_FILE}" || fail 'new LAN install did not save lan netcheck mode'
grep -q '^ADGUARD_PROC_PROFILE="balanced"$' "${CONF_FILE}" || fail 'new LAN install did not save balanced profile'

# nvram returns `1` for `sw_mode` requests and fails for all other requests.
nvram() {
	case "${1:-}:${2:-}" in
		get:sw_mode) printf '%s\n' 1 ;;
		*) return 1 ;;
	esac
}
CONF_FILE="${TMP_ROOT}/new-invalid-router.config"
configure_runtime_defaults new-install invalid 0 >"${TMP_ROOT}/new-invalid-router.out" || fail 'invalid-mode router fallback defaults failed'
grep -q '^ADGUARD_INSTALL_MODE="wan"$' "${CONF_FILE}" || fail 'invalid-mode router fallback did not save wan install mode'
grep -q '^ADGUARD_NETCHECK_MODE="wan"$' "${CONF_FILE}" || fail 'invalid-mode router fallback did not save wan netcheck mode'

# nvram returns `2` for `get:sw_mode` requests and fails for all other requests.
nvram() {
	case "${1:-}:${2:-}" in
		get:sw_mode) printf '%s\n' 2 ;;
		*) return 1 ;;
	esac
}
CONF_FILE="${TMP_ROOT}/new-invalid-lan.config"
configure_runtime_defaults new-install invalid 1 >"${TMP_ROOT}/new-invalid-lan.out" || fail 'invalid-mode LAN fallback defaults failed'
grep -q '^ADGUARD_INSTALL_MODE="lan"$' "${CONF_FILE}" || fail 'invalid-mode LAN fallback did not save lan install mode'
grep -q '^ADGUARD_NETCHECK_MODE="lan"$' "${CONF_FILE}" || fail 'invalid-mode LAN fallback did not save lan netcheck mode'

# nvram returns a failure status for all queries.
nvram() {
	return 1
}
CONF_FILE="${TMP_ROOT}/new-invalid-missing-sw-mode.config"
configure_runtime_defaults new-install invalid 0 >"${TMP_ROOT}/new-invalid-missing-sw-mode.out" || fail 'invalid-mode missing sw_mode fallback defaults failed'
grep -q '^ADGUARD_INSTALL_MODE="lan"$' "${CONF_FILE}" || fail 'invalid-mode missing sw_mode fallback did not save lan install mode'
grep -q '^ADGUARD_NETCHECK_MODE="lan"$' "${CONF_FILE}" || fail 'invalid-mode missing sw_mode fallback did not save lan netcheck mode'

CONF_FILE="${TMP_ROOT}/new-existing-netcheck.config"
cat >"${CONF_FILE}" <<'CONFIG'
ADGUARD_NETCHECK_MODE="legacy"
CONFIG
configure_runtime_defaults new-install wan 0 >"${TMP_ROOT}/new-existing-netcheck.out" || fail 'new install existing netcheck preservation failed'
grep -q '^ADGUARD_INSTALL_MODE="wan"$' "${CONF_FILE}" || fail 'new install existing netcheck did not save wan install mode'
grep -q '^ADGUARD_NETCHECK_MODE="legacy"$' "${CONF_FILE}" || fail 'new install overwrote existing netcheck mode'

CONF_FILE="${TMP_ROOT}/upgrade-existing.config"
cat >"${CONF_FILE}" <<'CONFIG'
ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="1"
ADGUARD_NETCHECK_MODE="lan"
ADGUARD_PROC_OPTIMIZE="NO"
ADGUARD_PROC_PROFILE="safe"
CONFIG
before="$(cat "${CONF_FILE}")"
configure_runtime_defaults upgrade >"${TMP_ROOT}/upgrade-existing.out" || fail 'upgrade preservation failed'
[ "$(cat "${CONF_FILE}")" = "${before}" ] || fail 'upgrade overwrote existing runtime defaults'
grep -q 'Existing runtime defaults were retained for compatibility' "${TMP_ROOT}/upgrade-existing.out" ||
	fail 'upgrade did not print retention guidance'
grep -q 'migrate-runtime-defaults --yes' "${TMP_ROOT}/upgrade-existing.out" ||
	fail 'upgrade did not print migration command'

CONF_FILE="${TMP_ROOT}/upgrade-missing.config"
: >"${CONF_FILE}"
ADGUARD_INSTALL_MODE="wan"
configure_runtime_defaults upgrade >"${TMP_ROOT}/upgrade-missing.out" || fail 'upgrade missing-default pin failed'
grep -q '^ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="0"$' "${CONF_FILE}" || fail 'upgrade missing policy did not pin legacy DNS cleanup'
grep -q '^ADGUARD_NETCHECK_MODE="legacy"$' "${CONF_FILE}" || fail 'upgrade missing netcheck did not pin legacy mode'
grep -q '^ADGUARD_PROC_OPTIMIZE="YES"$' "${CONF_FILE}" || fail 'upgrade missing optimize did not pin legacy enablement'
grep -q '^ADGUARD_PROC_PROFILE="aggressive"$' "${CONF_FILE}" || fail 'upgrade missing profile did not pin aggressive compatibility'
cli_migrate_runtime_defaults --dry-run >"${TMP_ROOT}/upgrade-missing-migrate-dry-run.out" ||
	fail 'upgrade migration dry-run failed'
grep -q '^ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="0"$' "${CONF_FILE}" || fail 'upgrade migration dry-run rewrote legacy DNS cleanup'
grep -q '^ADGUARD_NETCHECK_MODE="legacy"$' "${CONF_FILE}" || fail 'upgrade migration dry-run rewrote legacy netcheck mode'
grep -q 'Dry-run: would write v2.6.0 safer runtime defaults' "${TMP_ROOT}/upgrade-missing-migrate-dry-run.out" ||
	fail 'upgrade migration dry-run did not report planned safer defaults'
cli_migrate_runtime_defaults --yes >"${TMP_ROOT}/upgrade-missing-migrate.out" ||
	fail 'upgrade migration apply failed'
grep -q '^ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="1"$' "${CONF_FILE}" || fail 'upgrade migration did not enable DNS owner refusal'
grep -q '^ADGUARD_NETCHECK_MODE="wan"$' "${CONF_FILE}" || fail 'upgrade migration did not save wan netcheck mode'
grep -q '^ADGUARD_PROC_OPTIMIZE="YES"$' "${CONF_FILE}" || fail 'upgrade migration did not preserve optimization enablement'
grep -q '^ADGUARD_PROC_PROFILE="balanced"$' "${CONF_FILE}" || fail 'upgrade migration did not save balanced profile'

# shellcheck disable=SC1090
. "${S99_FUNCTIONS}"
WORK_DIR="${TMP_ROOT}/s99-empty"
mkdir -p "${WORK_DIR}" || fail 'could not create S99 work dir'
unset ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL
if ! dns_port_unknown_refusal_enabled; then
	fail 'S99 no-config fallback did not refuse unknown DNS owners'
fi
printf '%s\n' 'ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="0"' >"${WORK_DIR}/.config" || fail 'could not create S99 config'
if dns_port_unknown_refusal_enabled; then
	fail 'S99 saved legacy DNS policy was not preserved'
fi
ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL='1'
if ! dns_port_unknown_refusal_enabled; then
	fail 'S99 environment DNS refusal override did not take precedence'
fi

manager_default="$(sed -n 's/^DEFAULT_ADGUARD_PROC_OPTIMIZE="\([^"]*\)"$/\1/p' "${MANAGER_PATH}" | sed -n '1p')"
[ "${manager_default}" = 'NO' ] || fail 'manager no-config proc optimization fallback is not disabled'

printf '%s\n' 'PASS: runtime defaults preserve upgrades, migrate legacy pins, and apply safer new-install fallbacks'
