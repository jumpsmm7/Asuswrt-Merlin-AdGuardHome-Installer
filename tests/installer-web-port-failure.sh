#!/bin/sh
# Verify setup does not persist an unverified WebUI port when port selection fails.

set -u

SCRIPT_PATH="${1:-installer}"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"

RUNTIME_DEFAULT_FUNCTIONS="$(sed -n '/^conf_value() {$/,/^md5_is_valid() {$/p' "${SCRIPT_PATH}" | sed '$d')"
SETUP_FUNCTIONS="$(sed -n '/^setup_AdGuardHome() {$/,/^setup_amtmupdate() {$/p' "${SCRIPT_PATH}" | sed '$d')"
[ -n "${RUNTIME_DEFAULT_FUNCTIONS}" ] || fail 'could not extract runtime default functions'
[ -n "${SETUP_FUNCTIONS}" ] || fail 'could not extract setup functions'
eval "${RUNTIME_DEFAULT_FUNCTIONS}"
eval "${SETUP_FUNCTIONS}"

# port_is_valid determines whether a value is a numeric port in the range 3000 through 65535.
port_is_valid() {
	case "$1" in
		"" | *[!0123456789]*) return 1 ;;
	esac
	[ "$1" -ge 3000 ] 2>/dev/null && [ "$1" -le 65535 ] 2>/dev/null
}

# runtime_port_is_valid validates whether a WebUI port is within the supported range.
runtime_port_is_valid() {
	port_is_valid "$@"
}

# rollback_result_write records the result of a rollback operation.
rollback_result_write() { :; }
rollback_result_notice() { :; }

INFO='Info:'
ERROR='Error:'
WARNING='Warning:'
TMP_ROOT="${TMPDIR:-/tmp}/installer-web-port-failure.$$"
BASE_DIR="${TMP_ROOT}/base"
TARG_DIR="${TMP_ROOT}/target"
AGH_FILE="${TARG_DIR}/AdGuardHome"
YAML_FILE="${TMP_ROOT}/AdGuardHome.yaml"
YAML_ORI="${TMP_ROOT}/AdGuardHome.yaml.original"
YAML_BAK="${TMP_ROOT}/AdGuardHome.yaml.backup"
YAML_ERR="${TMP_ROOT}/AdGuardHome.yaml.error"
CONF_FILE="${TMP_ROOT}/.config"
WRITE_LOG="${TMP_ROOT}/writes"
mkdir -p "${TARG_DIR}" || fail 'could not create test directory'
cat >"${AGH_FILE}" <<'SCRIPT'
#!/bin/sh
printf '%s\n' 'AdGuard Home, version test Schema version: 27'
SCRIPT
chmod 755 "${AGH_FILE}"

cleanup() {
	rm -rf "${TMP_ROOT}"
}
trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

# ptxt_ok is a no-op text helper used by the test harness.
ptxt_ok() { :; }
# PTXT is a no-op text output helper.
PTXT() { :; }
# rm removes files normally and simulates configured cleanup failures for LAN-domain or DNS-filter snapshot markers.
rm() {
	if [ "${FAIL_LAN_DOMAIN_SNAPSHOT_CLEANUP:-0}" -eq 1 ] &&
		[ "$*" = "-f ${BASE_DIR}/.AdGuardHome.nvram/lan-domain/dirty" ]; then
		return 1
	fi
	if [ "${FAIL_DNS_FILTER_SNAPSHOT_CLEANUP:-0}" -eq 1 ] &&
		[ "$*" = "-f ${BASE_DIR}/.AdGuardHome.nvram/dnsfilter/dirty" ]; then
		return 1
	fi
	command rm "$@"
}
# read_input_port sets WEB_PORT to the selected WebUI port and returns the configured input status.
read_input_port() {
	WEB_PORT="${SELECTED_WEB_PORT:-3000}"
	return "${READ_INPUT_PORT_STATUS:-1}"
}
# write_conf records a configuration write and optionally fails WebUI port persistence.
write_conf() {
	printf '%s\n' "$*" >>"${WRITE_LOG}"
	[ "${FAIL_WRITE_CONF:-0}" -eq 0 ] || [ "$1" != ADGUARD_WEBUI_PORT ]
}
# save_installer_config saves the installer configuration file to the specified backup path.
save_installer_config() {
	cp -p "${CONF_FILE}" "$1"
}
# restore_installer_config restores the installer configuration from the specified backup file and removes its absent-state marker.
restore_installer_config() {
	mv -f "$1" "${CONF_FILE}"
	rm -f "$1.absent"
}
# discard_installer_config_backup removes an installer configuration backup and its absent-state marker.
discard_installer_config_backup() {
	rm -f "$1" "$1.absent"
}
# yaml_nvars_replace records YAML variable replacement arguments in the write log.
yaml_nvars_replace() {
	printf '%s\n' "$*" >>"${WRITE_LOG}"
}
YAML_CHECKS=0
# check_AdGuardHome_yaml increments the YAML validation check counter.
check_AdGuardHome_yaml() {
	YAML_CHECKS="$((YAML_CHECKS + 1))"
}
DNS_FILTER_CHANGED=0
DNS_FILTER_RESTORES=0
LAN_DOMAIN_RESTORES=0
# save_dns_filter_settings saves DNS filter settings to the specified directory and creates a DNS filter snapshot for rollback.
save_dns_filter_settings() {
	mkdir -p "$1"
	mkdir -p "${BASE_DIR}/.AdGuardHome.nvram/dnsfilter"
}
# installer_lan_domain_set records the current LAN domain and sets it to the specified value, returning failure when persistence is configured to fail.
installer_lan_domain_set() {
	[ "${FAIL_LAN_DOMAIN_SET:-0}" -eq 0 ] || return 1
	TEST_LAN_DOMAIN_ROLLBACK="${LAN_DOMAIN:-}"
	mkdir -p "${BASE_DIR}/.AdGuardHome.nvram/lan-domain"
	: >"${BASE_DIR}/.AdGuardHome.nvram/lan-domain/dirty"
	nvram set "lan_domain=$1"
}
# installer_lan_domain_restore restores the prior LAN domain and records the restoration.
installer_lan_domain_restore() {
	LAN_DOMAIN_RESTORES="$((LAN_DOMAIN_RESTORES + 1))"
	LAN_DOMAIN="${TEST_LAN_DOMAIN_ROLLBACK:-}"
	rm -rf "${BASE_DIR}/.AdGuardHome.nvram/lan-domain"
}
# restore_dns_filter_settings restores DNS filter settings, clears the change marker, and removes the temporary and snapshot directories.
restore_dns_filter_settings() {
	[ -d "${BASE_DIR}/.AdGuardHome.nvram/dnsfilter" ] || return 0
	DNS_FILTER_RESTORES="$((DNS_FILTER_RESTORES + 1))"
	DNS_FILTER_CHANGED=0
	rm -rf "$1"
	rm -rf "${BASE_DIR}/.AdGuardHome.nvram/dnsfilter"
}
# check_dns_filter marks the DNS filter settings as changed and fails when configured to simulate an update failure.
check_dns_filter() {
	DNS_FILTER_CHANGED=1
	if [ "${FAIL_CHECK_DNS_FILTER:-0}" -eq 1 ]; then
		: >"${BASE_DIR}/.AdGuardHome.nvram/dnsfilter/dirty"
		return 1
	fi
}
# check_dns_local appends a changed local DNS setting to the installer configuration.
check_dns_local() {
	printf '%s\n' 'ADGUARD_LOCAL="CHANGED"' >>"${CONF_FILE}"
}
check_ipset() {
	printf '%s\n' 'ADGUARD_IPSET="CHANGED"' >>"${CONF_FILE}"
}
read_yesno() { return 1; }
AdGuardHome_authen() { :; }
# read_input_dns sets the first or second bootstrap DNS server based on whether the first server is already configured.
read_input_dns() {
	if [ -z "${BOOTSTRAP1:-}" ]; then
		BOOTSTRAP1=9.9.9.9
	else
		BOOTSTRAP2=8.8.8.8
	fi
}
# ai_have_cmd indicates that the requested command is unavailable.
ai_have_cmd() { return 1; }
# nvram mocks NVRAM reads and writes used by installer tests.
nvram() {
	case "$1:${2:-}" in
		get:dns_local_cache) printf '%s\n' '1' ;;
		get:lan_ipaddr) printf '%s\n' '192.168.1.1' ;;
		get:lan_domain) printf '%s\n' "${LAN_DOMAIN:-}" ;;
		set:*)
			LAN_DOMAIN="${2#lan_domain=}"
			;;
	esac
}

: >"${CONF_FILE}"
: >"${WRITE_LOG}"
READ_INPUT_PORT_STATUS=1
SELECTED_WEB_PORT=3000
printf '%s\n' 'http:' '  address: 0.0.0.0:3000' 'schema_version: 27' >"${YAML_FILE}"
if setup_AdGuardHome_impl ''; then
	fail 'existing-config setup accepted a WebUI port that could not be verified'
fi
[ ! -s "${WRITE_LOG}" ] || fail 'existing-config setup persisted an unverified WebUI port'
[ "${YAML_CHECKS}" -eq 0 ] || fail 'existing-config setup continued after WebUI port selection failed'
grep -q 'address: 0.0.0.0:3000' "${YAML_FILE}" || fail 'existing YAML was changed after port selection failed'

rm -f "${YAML_ORI}" "${YAML_BAK}"
printf '%s\n' 'http:' '  address: 192.168.50.1:3000' 'schema_version: 27' >"${YAML_FILE}"
: >"${CONF_FILE}"
: >"${WRITE_LOG}"
YAML_CHECKS=0
READ_INPUT_PORT_STATUS=0
SELECTED_WEB_PORT=4000
# read_yesno returns success to simulate affirmative user input.
read_yesno() { return 0; }
if ! setup_AdGuardHome_impl ''; then
	fail 'existing-config setup failed while updating a LAN-bound WebUI port'
fi
grep -q '^ADGUARD_WEBUI_PORT "4000"$' "${WRITE_LOG}" || fail 'existing-config setup did not persist the selected LAN WebUI port'
grep -q 'address: 192.168.50.1:3000' "${WRITE_LOG}" || fail 'existing-config setup did not match the current LAN WebUI bind address when changing ports'
grep -q 'address: 192.168.50.1:4000' "${WRITE_LOG}" || fail 'existing-config setup did not preserve the LAN WebUI bind address when changing ports'
! grep -q '0\.0\.0\.0:3000' "${WRITE_LOG}" || fail 'existing-config setup used the old wildcard WebUI replacement pattern for a LAN bind'
[ "${YAML_CHECKS}" -eq 1 ] || fail 'existing-config setup did not validate the rewritten LAN-bound YAML once'
# read_yesno always indicates a negative response.
read_yesno() { return 1; }
READ_INPUT_PORT_STATUS=1
SELECTED_WEB_PORT=3000

rm -f "${YAML_ORI}" "${YAML_BAK}"
printf '%s\n' 'filters:' '  - url: http://example.invalid/filter.txt' 'schema_version: 27' >"${YAML_FILE}"
printf '%s\n' 'ADGUARD_DOMAIN="router.local"' >"${CONF_FILE}"
: >"${WRITE_LOG}"
YAML_CHECKS=0
READ_INPUT_PORT_STATUS=0
SELECTED_WEB_PORT=4000
if setup_AdGuardHome_impl ''; then
	fail 'existing-config setup accepted a WebUI port that could not be synced to YAML'
fi
grep -q '^ADGUARD_WEBUI_PORT "4000"$' "${WRITE_LOG}" || fail 'existing-config setup did not attempt to persist the selected WebUI port before sync failure'
[ "$(cat "${CONF_FILE}")" = 'ADGUARD_DOMAIN="router.local"' ] || fail 'existing-config setup did not restore installer preferences after WebUI sync failure'
[ "${YAML_CHECKS}" -eq 0 ] || fail 'existing-config setup continued after WebUI sync failure'
! grep -q 'address:' "${YAML_FILE}" || fail 'existing-config setup wrote a WebUI address outside a top-level http section'
READ_INPUT_PORT_STATUS=1
SELECTED_WEB_PORT=3000

rm -f "${YAML_FILE}" "${YAML_ORI}" "${YAML_BAK}"
: >"${WRITE_LOG}"
YAML_CHECKS=0
if setup_AdGuardHome_impl '' install; then
	fail 'initial setup accepted a WebUI port that could not be verified'
fi
[ ! -s "${WRITE_LOG}" ] || fail 'initial setup persisted an unverified WebUI port'
[ "${YAML_CHECKS}" -eq 0 ] || fail 'initial setup continued after WebUI port selection failed'
[ ! -e "${YAML_ORI}" ] || fail 'initial setup created YAML with an unverified WebUI port'

printf '%s\n' 'working configuration' >"${YAML_FILE}"
YAML_CHECKS=0
printf '%s\n' 'original configuration' >"${YAML_ORI}"
: >"${WRITE_LOG}"
read_input_num() {
	CHOSEN=3
}
if setup_AdGuardHome_impl reconfig reconfig; then
	fail 'reconfiguration accepted a WebUI port that could not be verified'
fi
[ ! -s "${WRITE_LOG}" ] || fail 'reconfiguration persisted an unverified WebUI port'
[ "${YAML_CHECKS}" -eq 1 ] || fail 'reconfiguration continued after WebUI port selection failed'
[ "$(cat "${YAML_FILE}")" = 'working configuration' ] || fail 'reconfiguration did not restore the previous YAML after port selection failed'
[ ! -e "${YAML_BAK}" ] || fail 'reconfiguration left the YAML backup behind after port selection failed'

printf '%s\n' 'working configuration' >"${YAML_FILE}"
printf '%s\n' 'original configuration' >"${YAML_ORI}"
printf '%s\n' 'ADGUARD_LOCAL="OLD"' 'ADGUARD_IPSET="OLD"' 'ADGUARD_DOMAIN="OLD"' >"${CONF_FILE}"
LAN_DOMAIN='before-web-port-failure.test'
: >"${WRITE_LOG}"
YAML_CHECKS=0
FAIL_WRITE_CONF=1
DNS_FILTER_CHANGED=0
DNS_FILTER_RESTORES=0
LAN_DOMAIN_RESTORES=0
# read_input_port sets the selected WebUI port to 3000 and succeeds.
read_input_port() {
	WEB_PORT=3000
	return 0
}
if setup_AdGuardHome_impl reconfig reconfig; then
	fail 'reconfiguration accepted a WebUI port that could not be persisted'
fi
grep -q '^ADGUARD_WEBUI_PORT ' "${WRITE_LOG}" || fail 'reconfiguration did not attempt to persist the selected WebUI port'
[ "${YAML_CHECKS}" -eq 3 ] || fail 'reconfiguration did not validate the generated YAML before persisting the WebUI port'
[ "$(cat "${YAML_FILE}")" = 'working configuration' ] || fail 'reconfiguration did not restore the previous YAML after WebUI port persistence failed'
[ ! -e "${YAML_BAK}" ] || fail 'reconfiguration left the YAML backup behind after WebUI port persistence failed'
[ "${DNS_FILTER_CHANGED}" -eq 0 ] || fail 'reconfiguration left changed DNSFilter settings after WebUI port persistence failed'
[ "${DNS_FILTER_RESTORES}" -eq 1 ] || fail 'reconfiguration did not restore DNSFilter settings after WebUI port persistence failed'
[ "${LAN_DOMAIN_RESTORES}" -eq 1 ] || fail 'reconfiguration did not restore LAN domain after WebUI port persistence failed'
[ "$(cat "${CONF_FILE}")" = "$(printf '%s\n' 'ADGUARD_LOCAL="OLD"' 'ADGUARD_IPSET="OLD"' 'ADGUARD_DOMAIN="OLD"')" ] || fail 'reconfiguration did not restore installer preferences after WebUI port persistence failed'
[ "${LAN_DOMAIN}" = 'before-web-port-failure.test' ] || fail 'reconfiguration did not restore the prior router LAN domain after WebUI port persistence failed'

printf '%s\n' 'working configuration' >"${YAML_FILE}"
printf '%s\n' 'original configuration' >"${YAML_ORI}"
printf '%s\n' 'ADGUARD_LOCAL="OLD"' 'ADGUARD_IPSET="OLD"' 'ADGUARD_DOMAIN="OLD"' >"${CONF_FILE}"
LAN_DOMAIN='before-persistence-failure.test'
: >"${WRITE_LOG}"
YAML_CHECKS=0
FAIL_WRITE_CONF=0
FAIL_LAN_DOMAIN_SET=1
DNS_FILTER_CHANGED=0
if setup_AdGuardHome_impl reconfig reconfig; then
	fail 'reconfiguration continued after LAN domain persistence failed'
fi
[ "$(cat "${YAML_FILE}")" = 'working configuration' ] || fail 'reconfiguration did not restore the previous YAML after LAN domain persistence failed'
[ ! -e "${YAML_BAK}" ] || fail 'reconfiguration left the YAML backup behind after LAN domain persistence failed'
[ ! -e "${YAML_ORI}.new.$$" ] || fail 'reconfiguration left staged YAML behind after LAN domain persistence failed'
[ "${DNS_FILTER_CHANGED}" -eq 0 ] || fail 'reconfiguration changed DNSFilter settings after LAN domain persistence failed'
[ "$(cat "${CONF_FILE}")" = "$(printf '%s\n' 'ADGUARD_LOCAL="OLD"' 'ADGUARD_IPSET="OLD"' 'ADGUARD_DOMAIN="OLD"')" ] || fail 'reconfiguration did not restore installer preferences after LAN domain persistence failed'
[ "${LAN_DOMAIN}" = 'before-persistence-failure.test' ] || fail 'reconfiguration changed the prior router LAN domain after LAN domain persistence failed'

printf '%s\n' 'working configuration' >"${YAML_FILE}"
printf '%s\n' 'original configuration' >"${YAML_ORI}"
printf '%s\n' 'ADGUARD_LOCAL="OLD"' 'ADGUARD_IPSET="OLD"' 'ADGUARD_DOMAIN="OLD"' >"${CONF_FILE}"
LAN_DOMAIN='before-dnsfilter-cleanup-failure.test'
: >"${WRITE_LOG}"
FAIL_LAN_DOMAIN_SET=0
FAIL_DNS_FILTER_SNAPSHOT_CLEANUP=1
DNS_FILTER_CHANGED=0
DNS_FILTER_RESTORES=0
LAN_DOMAIN_RESTORES=0
if setup_AdGuardHome_impl reconfig reconfig; then
	fail 'reconfiguration ignored DNSFilter snapshot cleanup failure'
fi
[ "${DNS_FILTER_RESTORES}" -eq 1 ] || fail 'DNSFilter snapshot cleanup failure did not restore DNSFilter settings'
[ "${LAN_DOMAIN_RESTORES}" -eq 1 ] || fail 'DNSFilter snapshot cleanup failure did not restore the LAN domain'
[ "${DNS_FILTER_CHANGED}" -eq 0 ] || fail 'DNSFilter snapshot cleanup failure left changed DNSFilter settings'
[ "$(cat "${YAML_FILE}")" = 'working configuration' ] || fail 'DNSFilter snapshot cleanup failure did not restore the previous YAML'
[ "$(cat "${CONF_FILE}")" = "$(printf '%s\n' 'ADGUARD_LOCAL="OLD"' 'ADGUARD_IPSET="OLD"' 'ADGUARD_DOMAIN="OLD"')" ] || fail 'DNSFilter snapshot cleanup failure did not restore installer preferences'
[ "${LAN_DOMAIN}" = 'before-dnsfilter-cleanup-failure.test' ] || fail 'DNSFilter snapshot cleanup failure did not restore the prior router LAN domain'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/lan-domain" ] || fail 'DNSFilter snapshot cleanup rollback retained the LAN-domain transaction directory'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/dnsfilter" ] || fail 'DNSFilter snapshot cleanup rollback retained the DNSFilter transaction directory'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/lan-domain/dirty" ] || fail 'DNSFilter snapshot cleanup rollback retained the LAN-domain dirty marker'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/dnsfilter/dirty" ] || fail 'DNSFilter snapshot cleanup rollback retained the DNSFilter dirty marker'

printf '%s\n' 'working configuration' >"${YAML_FILE}"
printf '%s\n' 'original configuration' >"${YAML_ORI}"
printf '%s\n' 'ADGUARD_LOCAL="OLD"' 'ADGUARD_IPSET="OLD"' 'ADGUARD_DOMAIN="OLD"' >"${CONF_FILE}"
LAN_DOMAIN='before-lan-cleanup-failure.test'
: >"${WRITE_LOG}"
FAIL_DNS_FILTER_SNAPSHOT_CLEANUP=0
FAIL_LAN_DOMAIN_SNAPSHOT_CLEANUP=1
DNS_FILTER_CHANGED=0
DNS_FILTER_RESTORES=0
LAN_DOMAIN_RESTORES=0
if setup_AdGuardHome_impl reconfig reconfig; then
	fail 'reconfiguration ignored LAN domain snapshot cleanup failure'
fi
[ "${DNS_FILTER_RESTORES}" -eq 1 ] || fail 'LAN domain snapshot cleanup failure did not restore DNSFilter settings'
[ "${LAN_DOMAIN_RESTORES}" -eq 1 ] || fail 'LAN domain snapshot cleanup failure did not restore the LAN domain'
[ "${DNS_FILTER_CHANGED}" -eq 0 ] || fail 'LAN domain snapshot cleanup failure left changed DNSFilter settings'
[ "$(cat "${YAML_FILE}")" = 'working configuration' ] || fail 'LAN domain snapshot cleanup failure did not restore the previous YAML'
[ "$(cat "${CONF_FILE}")" = "$(printf '%s\n' 'ADGUARD_LOCAL="OLD"' 'ADGUARD_IPSET="OLD"' 'ADGUARD_DOMAIN="OLD"')" ] || fail 'LAN domain snapshot cleanup failure did not restore installer preferences'
[ "${LAN_DOMAIN}" = 'before-lan-cleanup-failure.test' ] || fail 'LAN domain snapshot cleanup failure did not restore the prior router LAN domain'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/lan-domain" ] || fail 'LAN-domain snapshot cleanup rollback retained the LAN-domain transaction directory'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/dnsfilter" ] || fail 'LAN-domain snapshot cleanup rollback retained the DNSFilter transaction directory'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/lan-domain/dirty" ] || fail 'LAN-domain snapshot cleanup rollback retained the LAN-domain dirty marker'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/dnsfilter/dirty" ] || fail 'LAN-domain snapshot cleanup rollback retained the DNSFilter dirty marker'

printf '%s\n' 'working configuration' >"${YAML_FILE}"
printf '%s\n' 'original configuration' >"${YAML_ORI}"
printf '%s\n' 'ADGUARD_LOCAL="OLD"' 'ADGUARD_IPSET="OLD"' 'ADGUARD_DOMAIN="OLD"' >"${CONF_FILE}"
LAN_DOMAIN='before-dnsfilter-apply-failure.test'
: >"${WRITE_LOG}"
FAIL_LAN_DOMAIN_SNAPSHOT_CLEANUP=0
FAIL_CHECK_DNS_FILTER=1
DNS_FILTER_CHANGED=0
DNS_FILTER_RESTORES=0
LAN_DOMAIN_RESTORES=0
if setup_AdGuardHome_impl reconfig reconfig; then
	fail 'reconfiguration ignored DNSFilter transaction failure'
fi
[ "${DNS_FILTER_RESTORES}" -eq 1 ] || fail 'DNSFilter transaction failure did not restore its snapshot'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/dnsfilter" ] || fail 'DNSFilter transaction failure retained a successfully restored snapshot'
[ "${LAN_DOMAIN_RESTORES}" -eq 1 ] || fail 'DNSFilter transaction failure did not restore the LAN domain'
[ "${LAN_DOMAIN}" = 'before-dnsfilter-apply-failure.test' ] || fail 'DNSFilter transaction failure did not restore the prior router LAN domain'

printf '%s\n' 'PASS: failed WebUI port verification or persistence aborts setup safely'
