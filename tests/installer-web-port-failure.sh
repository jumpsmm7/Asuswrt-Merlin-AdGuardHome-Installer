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
# PTXT outputs no text.
PTXT() { :; }
# rm removes files and simulates cleanup failures for configured LAN-domain or DNS-filter snapshot markers.
rm() {
	if { [ "${FAIL_LAN_DOMAIN_SNAPSHOT_CLEANUP:-0}" -eq 1 ] || [ "${FAIL_DNS_FILTER_SNAPSHOT_CLEANUP:-0}" -eq 1 ]; } &&
		[ "$*" = "-rf ${BASE_DIR}/.AdGuardHome.nvram/lan-domain ${BASE_DIR}/.AdGuardHome.nvram/dnsfilter ${BASE_DIR}/.AdGuardHome.nvram/setup-files" ]; then
		return 1
	fi
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
# read_input_port sets WEB_PORT to SELECTED_WEB_PORT or 3000 and returns READ_INPUT_PORT_STATUS, defaulting to 1.
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
SETUP_FILES_BEGIN_COUNT=0
SETUP_FILES_RESTORE_COUNT=0
SETUP_FILES_FINALIZE_COUNT=0
SETUP_FILE_JOURNALS=0
# save_dns_filter_settings creates directories for DNS filter rollback state.
save_dns_filter_settings() {
	mkdir -p "$1"
	mkdir -p "${BASE_DIR}/.AdGuardHome.nvram/dnsfilter"
}
# installer_lan_domain_set records the current LAN domain and persists a replacement value, failing when persistence is configured to fail.
installer_lan_domain_set() {
	[ "${FAIL_LAN_DOMAIN_SET:-0}" -eq 0 ] || return 1
	TEST_LAN_DOMAIN_ROLLBACK="${LAN_DOMAIN:-}"
	mkdir -p "${BASE_DIR}/.AdGuardHome.nvram/lan-domain"
	: >"${BASE_DIR}/.AdGuardHome.nvram/lan-domain/dirty"
	nvram set "lan_domain=$1"
}
# installer_lan_domain_restore restores the prior LAN domain, records the restoration, and removes its transaction state.
installer_lan_domain_restore() {
	LAN_DOMAIN_RESTORES="$((LAN_DOMAIN_RESTORES + 1))"
	LAN_DOMAIN="${TEST_LAN_DOMAIN_ROLLBACK:-}"
	rm -rf "${BASE_DIR}/.AdGuardHome.nvram/lan-domain"
}
# restore_dns_filter_settings removes the temporary restore directory and DNS filter snapshot, then clears the change marker.
restore_dns_filter_settings() {
	[ -d "${BASE_DIR}/.AdGuardHome.nvram/dnsfilter" ] || return 0
	DNS_FILTER_RESTORES="$((DNS_FILTER_RESTORES + 1))"
	rm -rf "$1" || return 1
	rm -rf "${BASE_DIR}/.AdGuardHome.nvram/dnsfilter" || return 1
	DNS_FILTER_CHANGED=0
}
# nvram_transaction_finalize_setup_pair publishes the setup commit marker and removes transaction snapshots; it fails if marker publication fails and retains snapshots when cleanup is configured to fail.
nvram_transaction_finalize_setup_pair() {
	SETUP_FILES_FINALIZE_COUNT="$((SETUP_FILES_FINALIZE_COUNT + 1))"
	[ "${FAIL_SETUP_COMMIT_MARKER:-0}" -eq 0 ] || return 1
	: >"${BASE_DIR}/.AdGuardHome.nvram/setup-committed"
	if rm -rf "${BASE_DIR}/.AdGuardHome.nvram/lan-domain" "${BASE_DIR}/.AdGuardHome.nvram/dnsfilter" "${BASE_DIR}/.AdGuardHome.nvram/setup-files"; then
		rm -f "${BASE_DIR}/.AdGuardHome.nvram/setup-committed"
	fi
	return 0
}
# nvram_transaction_setup_committed reports whether the setup commit marker exists.
nvram_transaction_setup_committed() { [ -f "${BASE_DIR}/.AdGuardHome.nvram/setup-committed" ]; }
# nvram_transaction_setup_files_begin creates a rollback journal containing snapshots of the YAML and configuration files, and records markers for files that are absent.
nvram_transaction_setup_files_begin() {
	local journal_root source target
	journal_root="${BASE_DIR}/.AdGuardHome.nvram/setup-files"
	[ ! -e "${journal_root}" ] || return 1
	SETUP_FILES_BEGIN_COUNT="$((SETUP_FILES_BEGIN_COUNT + 1))"
	SETUP_FILE_JOURNALS="$((SETUP_FILE_JOURNALS + 1))"
	mkdir -p "${journal_root}" || return 1
	for source in yaml-file yaml-original config; do
		case "${source}" in
			yaml-file) target="${YAML_FILE}" ;;
			yaml-original) target="${YAML_ORI}" ;;
			config) target="${CONF_FILE}" ;;
		esac
		if [ "${source}" = "yaml-file" ] && [ "${YAML_BACKED_UP:-0}" -eq 1 ] && [ -f "${YAML_BAK}" ]; then
			cp -p "${YAML_BAK}" "${journal_root}/${source}" || return 1
		elif [ -f "${target}" ]; then
			cp -p "${target}" "${journal_root}/${source}" || return 1
		else
			: >"${journal_root}/${source}.absent" || return 1
		fi
	done
}
# nvram_transaction_setup_files_restore restores journaled setup files and removes the journal only after all restorations succeed.
nvram_transaction_setup_files_restore() {
	local journal_root source target stage_file
	journal_root="${BASE_DIR}/.AdGuardHome.nvram/setup-files"
	[ -d "${journal_root}" ] || return 0
	SETUP_FILES_RESTORE_COUNT="$((SETUP_FILES_RESTORE_COUNT + 1))"
	for source in yaml-file yaml-original config; do
		case "${source}" in
			yaml-file) target="${YAML_FILE}" ;;
			yaml-original) target="${YAML_ORI}" ;;
			config) target="${CONF_FILE}" ;;
		esac
		stage_file="${target}.setup-restore.$$"
		if [ -f "${journal_root}/${source}" ]; then
			cp -p "${journal_root}/${source}" "${stage_file}" || {
				rm -f "${stage_file}"
				return 1
			}
			if [ "${FAIL_SETUP_FILES_RESTORE:-0}" -eq 1 ]; then
				rm -f "${stage_file}"
				return 1
			fi
			mv -f "${stage_file}" "${target}" || {
				rm -f "${stage_file}"
				return 1
			}
		elif [ -f "${journal_root}/${source}.absent" ]; then
			if [ "${FAIL_SETUP_FILES_RESTORE:-0}" -eq 1 ]; then
				return 1
			fi
			rm -f "${target}" || return 1
		else
			return 1
		fi
	done
	rm -rf "${journal_root}"
}
# check_dns_filter marks DNS-filter settings as changed, records setup-journal availability, and reports a simulated update failure when configured.
check_dns_filter() {
	[ ! -d "${BASE_DIR}/.AdGuardHome.nvram/setup-files" ] || DNS_FILTER_SAW_SETUP_JOURNAL=1
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
# check_ipset records an IP set configuration change and marks an existing setup journal as observed.
check_ipset() {
	[ ! -d "${BASE_DIR}/.AdGuardHome.nvram/setup-files" ] || IPSET_SAW_SETUP_JOURNAL=1
	printf '%s\n' 'ADGUARD_IPSET="CHANGED"' >>"${CONF_FILE}"
}
# read_yesno always indicates a negative response.
read_yesno() { return 1; }
# AdGuardHome_authen authenticates with AdGuard Home.
AdGuardHome_authen() { :; }
# read_input_dns sets the first or second bootstrap DNS server based on whether the first server is already configured.
read_input_dns() {
	if [ -z "${BOOTSTRAP1:-}" ]; then
		BOOTSTRAP1=9.9.9.9
	else
		BOOTSTRAP2=8.8.8.8
	fi
}
# ai_have_cmd reports that the requested command is unavailable.
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
SETUP_FILES_FINALIZE_COUNT=0
# read_yesno simulates an affirmative user response by returning success.
read_yesno() { return 0; }
if ! setup_AdGuardHome_impl ''; then
	fail 'existing-config setup failed while updating a LAN-bound WebUI port'
fi
grep -q '^ADGUARD_WEBUI_PORT "4000"$' "${WRITE_LOG}" || fail 'existing-config setup did not persist the selected LAN WebUI port'
grep -q 'address: 192.168.50.1:3000' "${WRITE_LOG}" || fail 'existing-config setup did not match the current LAN WebUI bind address when changing ports'
grep -q 'address: 192.168.50.1:4000' "${WRITE_LOG}" || fail 'existing-config setup did not preserve the LAN WebUI bind address when changing ports'
! grep -q '0\.0\.0\.0:3000' "${WRITE_LOG}" || fail 'existing-config setup used the old wildcard WebUI replacement pattern for a LAN bind'
[ "${YAML_CHECKS}" -eq 1 ] || fail 'existing-config setup did not validate the rewritten LAN-bound YAML once'
[ "${SETUP_FILES_FINALIZE_COUNT}" -eq 1 ] || fail 'existing-config WebUI update did not finalize its setup-file journal'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/setup-files" ] || fail 'existing-config WebUI update retained its completed setup-file journal'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/setup-committed" ] || fail 'existing-config WebUI update retained its completed setup commit marker'

rm -rf "${BASE_DIR}/.AdGuardHome.nvram"
rm -f "${YAML_ORI}" "${YAML_BAK}"
printf '%s\n' 'http:' '  address: 192.168.50.1:3000' 'schema_version: 27' >"${YAML_FILE}"
: >"${CONF_FILE}"
: >"${WRITE_LOG}"
SETUP_FILES_BEGIN_COUNT=0
SETUP_FILES_FINALIZE_COUNT=0
# read_yesno indicates that a yes-or-no response was not accepted.
read_yesno() {
	return 1
}
# read_input_num sets the chosen input number to 3.
read_input_num() {
	CHOSEN=3
}
if ! setup_AdGuardHome_impl ''; then
	fail 'recursive existing-config setup did not reuse its active setup-file journal'
fi
[ "${SETUP_FILES_BEGIN_COUNT}" -eq 1 ] || fail 'recursive existing-config setup initialized its setup-file journal more than once'
[ "${SETUP_FILES_FINALIZE_COUNT}" -eq 1 ] || fail 'recursive existing-config setup did not finalize its inherited setup-file journal'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/setup-files" ] || fail 'recursive existing-config setup retained its completed setup-file journal'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/setup-committed" ] || fail 'recursive existing-config setup retained its completed setup commit marker'

rm -rf "${BASE_DIR}/.AdGuardHome.nvram"
printf '%s\n' 'http:' '  address: 192.168.50.1:4000' 'schema_version: 26' >"${YAML_FILE}"
printf '%s\n' 'ADGUARD_WEBUI_PORT="4000"' >"${CONF_FILE}"
: >"${WRITE_LOG}"
SETUP_FILES_FINALIZE_COUNT=0
if ! setup_AdGuardHome_impl ''; then
	fail 'existing-config setup failed while updating the schema version'
fi
grep -q '^schema_version: 26 schema_version: 27 ' "${WRITE_LOG}" || fail 'existing-config setup did not attempt the schema version update'
[ "${SETUP_FILES_FINALIZE_COUNT}" -eq 1 ] || fail 'existing-config schema update did not finalize its setup-file journal'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/setup-files" ] || fail 'existing-config schema update retained its completed setup-file journal'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/setup-committed" ] || fail 'existing-config schema update retained its completed setup commit marker'

rm -rf "${BASE_DIR}/.AdGuardHome.nvram"
printf '%s\n' 'http:' '  address: 192.168.50.1:4000' 'schema_version: 26' >"${YAML_FILE}"
printf '%s\n' 'ADGUARD_WEBUI_PORT="4000"' >"${CONF_FILE}"
: >"${WRITE_LOG}"
FAIL_SETUP_COMMIT_MARKER=1
SETUP_FILES_FINALIZE_COUNT=0
SETUP_FILES_RESTORE_COUNT=0
if setup_AdGuardHome_impl ''; then
	fail 'existing-config schema update ignored setup commit marker publication failure'
fi
[ "${SETUP_FILES_FINALIZE_COUNT}" -eq 1 ] || fail 'existing-config schema update did not attempt journal finalization'
[ "${SETUP_FILES_RESTORE_COUNT}" -eq 1 ] || fail 'existing-config schema finalization failure did not restore the setup-file journal'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/setup-files" ] || fail 'existing-config schema finalization failure retained a restored setup-file journal'
FAIL_SETUP_COMMIT_MARKER=0
# read_yesno always indicates a negative response.
read_yesno() { return 1; }
READ_INPUT_PORT_STATUS=1
SELECTED_WEB_PORT=3000

rm -rf "${BASE_DIR}/.AdGuardHome.nvram"
printf '%s\n' 'http:' '  address: 192.168.50.1:4000' 'schema_version: 26' >"${YAML_FILE}"
printf '%s\n' 'ADGUARD_WEBUI_PORT="4000"' >"${CONF_FILE}"
SETUP_FILES_RESTORE_COUNT=0
# read_yesno reports that no yes/no response was provided.
read_yesno() { return 2; }
if setup_AdGuardHome_impl ''; then
	fail 'existing-config setup accepted an interrupted confirmation prompt'
fi
[ "${SETUP_FILES_RESTORE_COUNT}" -eq 1 ] || fail 'interrupted existing-config confirmation did not restore the active setup-file journal'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/setup-files" ] || fail 'interrupted existing-config confirmation retained the restored setup-file journal'

rm -rf "${BASE_DIR}/.AdGuardHome.nvram"
printf '%s\n' 'working configuration' >"${YAML_FILE}"
printf '%s\n' 'original configuration' >"${YAML_ORI}"
printf '%s\n' 'ADGUARD_LOCAL="OLD"' >"${CONF_FILE}"
SETUP_FILES_RESTORE_COUNT=0
nvram_transaction_setup_files_begin || fail 'could not initialize inherited setup-file journal fixture'
# read_input_num simulates a failed numeric input read.
read_input_num() { return 1; }
if setup_AdGuardHome_impl reconfig reconfig 1; then
	fail 'reconfiguration accepted an interrupted mode-selection prompt'
fi
[ "${SETUP_FILES_RESTORE_COUNT}" -eq 1 ] || fail 'interrupted reconfiguration selection did not restore the inherited setup-file journal'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/setup-files" ] || fail 'interrupted reconfiguration selection retained the restored setup-file journal'

# read_yesno always indicates a negative response.
read_yesno() { return 1; }

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

rm -rf "${BASE_DIR}/.AdGuardHome.nvram"
printf '%s\n' 'working configuration' >"${YAML_FILE}"
printf '%s\n' 'original configuration' >"${YAML_ORI}"
printf '%s\n' 'ADGUARD_LOCAL="OLD"' 'ADGUARD_IPSET="OLD"' 'ADGUARD_DOMAIN="OLD"' >"${CONF_FILE}"
SETUP_FILE_JOURNALS=0
DNS_FILTER_SAW_SETUP_JOURNAL=0
DNS_FILTER_CHANGED=0
# read_input_num sets the chosen input number to 1.
read_input_num() {
	CHOSEN=1
}
if ! setup_AdGuardHome_impl reconfig reconfig; then
	fail 'existing-YAML DNSFilter reconfiguration failed'
fi
[ "${SETUP_FILE_JOURNALS}" -eq 1 ] || fail 'existing-YAML DNSFilter reconfiguration did not initialize the setup file journal'
[ "${DNS_FILTER_SAW_SETUP_JOURNAL}" -eq 1 ] || fail 'existing-YAML DNSFilter reconfiguration applied NVRAM before initializing the setup file journal'
# read_input_num sets the chosen input number to 3.
read_input_num() {
	CHOSEN=3
}

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

rm -rf "${BASE_DIR}/.AdGuardHome.nvram"
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
if ! setup_AdGuardHome_impl reconfig reconfig; then
	fail 'reconfiguration failed after best-effort DNSFilter snapshot cleanup failed'
fi
[ "${DNS_FILTER_RESTORES}" -eq 0 ] || fail 'DNSFilter snapshot cleanup failure rolled back committed DNSFilter settings'
[ "${LAN_DOMAIN_RESTORES}" -eq 0 ] || fail 'DNSFilter snapshot cleanup failure rolled back the committed LAN domain'
[ "${DNS_FILTER_CHANGED}" -eq 1 ] || fail 'DNSFilter snapshot cleanup failure did not retain committed DNSFilter settings'
[ -f "${BASE_DIR}/.AdGuardHome.nvram/setup-committed" ] || fail 'DNSFilter snapshot cleanup failure did not publish the setup commit marker'
[ -d "${BASE_DIR}/.AdGuardHome.nvram/lan-domain" ] || fail 'DNSFilter snapshot cleanup failure did not preserve the LAN-domain snapshot directory'
[ -d "${BASE_DIR}/.AdGuardHome.nvram/dnsfilter" ] || fail 'DNSFilter snapshot cleanup failure did not preserve the DNSFilter snapshot directory'

FAIL_DNS_FILTER_SNAPSHOT_CLEANUP=0
rm -rf "${BASE_DIR}/.AdGuardHome.nvram"
printf '%s\n' 'working configuration' >"${YAML_FILE}"
printf '%s\n' 'original configuration' >"${YAML_ORI}"
printf '%s\n' 'ADGUARD_LOCAL="OLD"' 'ADGUARD_IPSET="OLD"' 'ADGUARD_DOMAIN="OLD"' >"${CONF_FILE}"
LAN_DOMAIN='before-lan-cleanup-failure.test'
: >"${WRITE_LOG}"
FAIL_LAN_DOMAIN_SNAPSHOT_CLEANUP=1
DNS_FILTER_CHANGED=0
DNS_FILTER_RESTORES=0
LAN_DOMAIN_RESTORES=0
if ! setup_AdGuardHome_impl reconfig reconfig; then
	fail 'reconfiguration failed after best-effort LAN-domain snapshot cleanup failed'
fi
[ "${DNS_FILTER_RESTORES}" -eq 0 ] || fail 'LAN-domain snapshot cleanup failure rolled back committed DNSFilter settings'
[ "${LAN_DOMAIN_RESTORES}" -eq 0 ] || fail 'LAN-domain snapshot cleanup failure rolled back the committed LAN domain'
[ "${DNS_FILTER_CHANGED}" -eq 1 ] || fail 'LAN-domain snapshot cleanup failure did not retain committed DNSFilter settings'
[ -f "${BASE_DIR}/.AdGuardHome.nvram/setup-committed" ] || fail 'LAN-domain snapshot cleanup failure did not publish the setup commit marker'
[ -d "${BASE_DIR}/.AdGuardHome.nvram/lan-domain" ] || fail 'LAN-domain snapshot cleanup failure did not preserve the LAN-domain snapshot directory'
[ -d "${BASE_DIR}/.AdGuardHome.nvram/dnsfilter" ] || fail 'LAN-domain snapshot cleanup failure did not preserve the DNSFilter snapshot directory'

rm -rf "${BASE_DIR}/.AdGuardHome.nvram"
printf '%s\n' 'working configuration' >"${YAML_FILE}"
printf '%s\n' 'original configuration' >"${YAML_ORI}"
printf '%s\n' 'ADGUARD_LOCAL="OLD"' 'ADGUARD_IPSET="OLD"' 'ADGUARD_DOMAIN="OLD"' >"${CONF_FILE}"
LAN_DOMAIN='before-marker-failure.test'
: >"${WRITE_LOG}"
FAIL_LAN_DOMAIN_SNAPSHOT_CLEANUP=0
FAIL_SETUP_COMMIT_MARKER=1
FAIL_SETUP_FILES_RESTORE=0
DNS_FILTER_CHANGED=0
DNS_FILTER_RESTORES=0
LAN_DOMAIN_RESTORES=0
SETUP_FILES_RESTORE_COUNT=0
if setup_AdGuardHome_impl reconfig reconfig; then
	fail 'reconfiguration ignored setup commit marker publication failure'
fi
[ "${SETUP_FILES_RESTORE_COUNT}" -eq 1 ] || fail 'setup commit marker failure did not invoke setup-file journal restoration'
[ "${DNS_FILTER_RESTORES}" -eq 1 ] || fail 'setup commit marker failure did not restore DNSFilter settings'
[ "${LAN_DOMAIN_RESTORES}" -eq 1 ] || fail 'setup commit marker failure did not restore the LAN domain'
[ "${DNS_FILTER_CHANGED}" -eq 0 ] || fail 'setup commit marker failure left changed DNSFilter settings'
[ "$(cat "${YAML_FILE}")" = 'working configuration' ] || fail 'setup commit marker failure did not restore the previous YAML'
[ "$(cat "${CONF_FILE}")" = "$(printf '%s\n' 'ADGUARD_LOCAL="OLD"' 'ADGUARD_IPSET="OLD"' 'ADGUARD_DOMAIN="OLD"')" ] || fail 'setup commit marker failure did not restore installer preferences'
[ "${LAN_DOMAIN}" = 'before-marker-failure.test' ] || fail 'setup commit marker failure did not restore the prior router LAN domain'
[ "$(cat "${YAML_ORI}")" = 'original configuration' ] || fail 'setup commit marker failure did not restore the previous original YAML snapshot'
[ ! -e "${YAML_ORI}.rollback.$$" ] || fail 'setup commit marker failure retained the original YAML rollback artifact'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/setup-committed" ] || fail 'setup commit marker failure published the completion marker'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/setup-files" ] || fail 'setup commit marker failure retained the restored setup-file journal'

printf '%s\n' 'working configuration' >"${YAML_FILE}"
printf '%s\n' 'original configuration' >"${YAML_ORI}"
printf '%s\n' 'ADGUARD_LOCAL="OLD"' 'ADGUARD_IPSET="OLD"' 'ADGUARD_DOMAIN="OLD"' >"${CONF_FILE}"
LAN_DOMAIN='before-dnsfilter-apply-failure.test'
: >"${WRITE_LOG}"
FAIL_LAN_DOMAIN_SNAPSHOT_CLEANUP=0
FAIL_SETUP_COMMIT_MARKER=0
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

rm -rf "${BASE_DIR}/.AdGuardHome.nvram"
printf '%s\n' 'journal YAML' >"${YAML_FILE}"
printf '%s\n' 'journal original YAML' >"${YAML_ORI}"
printf '%s\n' 'ADGUARD_LOCAL="JOURNAL"' 'ADGUARD_IPSET="JOURNAL"' 'ADGUARD_DOMAIN="JOURNAL"' >"${CONF_FILE}"
: >"${WRITE_LOG}"
FAIL_CHECK_DNS_FILTER=1
FAIL_SETUP_FILES_RESTORE=1
SETUP_FILES_RESTORE_COUNT=0
if setup_AdGuardHome_impl reconfig reconfig; then
	fail 'reconfiguration ignored DNSFilter failure while setup-file journal restoration was unavailable'
fi
[ "${SETUP_FILES_RESTORE_COUNT}" -eq 1 ] || fail 'setup-file journal restore failure pathway did not invoke restoration'
[ -d "${BASE_DIR}/.AdGuardHome.nvram/setup-files" ] || fail 'setup-file journal restore failure did not preserve recovery state'
[ "$(cat "${BASE_DIR}/.AdGuardHome.nvram/setup-files/yaml-file")" = 'journal YAML' ] || fail 'preserved setup-file journal lost the YAML snapshot'
[ "$(cat "${BASE_DIR}/.AdGuardHome.nvram/setup-files/yaml-original")" = 'journal original YAML' ] || fail 'preserved setup-file journal lost the original YAML snapshot'
[ "$(cat "${BASE_DIR}/.AdGuardHome.nvram/setup-files/config")" = "$(printf '%s\n' 'ADGUARD_LOCAL="JOURNAL"' 'ADGUARD_IPSET="JOURNAL"' 'ADGUARD_DOMAIN="JOURNAL"')" ] || fail 'preserved setup-file journal lost the installer configuration snapshot'
[ ! -e "${YAML_FILE}.setup-restore.$$" ] || fail 'setup-file journal restore failure left YAML stage file behind'
[ ! -e "${YAML_ORI}.setup-restore.$$" ] || fail 'setup-file journal restore failure left original YAML stage file behind'
[ ! -e "${CONF_FILE}.setup-restore.$$" ] || fail 'setup-file journal restore failure left config stage file behind'

rm -rf "${BASE_DIR}/.AdGuardHome.nvram"
printf '%s\n' 'working configuration' >"${YAML_FILE}"
printf '%s\n' 'original configuration' >"${YAML_ORI}"
printf '%s\n' 'ADGUARD_LOCAL="OLD"' 'ADGUARD_IPSET="OLD"' 'ADGUARD_DOMAIN="OLD"' >"${CONF_FILE}"
: >"${WRITE_LOG}"
FAIL_CHECK_DNS_FILTER=0
FAIL_SETUP_FILES_RESTORE=0
SETUP_FILES_BEGIN_COUNT=0
DNS_FILTER_SAW_SETUP_JOURNAL=0
# read_input_num sets the chosen input number to 1.
read_input_num() {
	CHOSEN=1
}
if ! setup_AdGuardHome_impl reconfig reconfig; then
	fail 'existing-YAML DNSFilter reconfiguration failed'
fi
[ "${SETUP_FILES_BEGIN_COUNT}" -eq 1 ] || fail 'existing-YAML DNSFilter reconfiguration was not journaled exactly once'
[ "${DNS_FILTER_SAW_SETUP_JOURNAL}" -eq 1 ] || fail 'existing-YAML DNSFilter reconfiguration did not observe setup journal before check_dns_filter'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/setup-files" ] || fail 'existing-YAML DNSFilter reconfiguration retained its completed file journal'

rm -rf "${BASE_DIR}/.AdGuardHome.nvram"
printf '%s\n' 'pre-commit YAML' >"${YAML_FILE}"
printf '%s\n' 'pre-commit original YAML' >"${YAML_ORI}"
printf '%s\n' 'ADGUARD_LOCAL="PRE-COMMIT"' >"${CONF_FILE}"
SETUP_FILES_JOURNALED=1
SETUP_FILES_RESTORE_COUNT=0
nvram_transaction_setup_files_begin || fail 'could not create setup-file journal for committed cleanup regression'
printf '%s\n' 'committed YAML' >"${YAML_FILE}"
printf '%s\n' 'committed original YAML' >"${YAML_ORI}"
printf '%s\n' 'ADGUARD_LOCAL="COMMITTED"' >"${CONF_FILE}"
: >"${BASE_DIR}/.AdGuardHome.nvram/setup-committed"
setup_restore_nvram_journal || fail 'committed setup-file journal guard returned failure'
[ "${SETUP_FILES_RESTORE_COUNT}" -eq 0 ] || fail 'committed setup-file journal was restored after the setup commit point'
[ "$(cat "${YAML_FILE}")" = 'committed YAML' ] || fail 'committed setup-file journal guard rolled back the active YAML'
[ "$(cat "${YAML_ORI}")" = 'committed original YAML' ] || fail 'committed setup-file journal guard rolled back the original YAML snapshot'
[ "$(cat "${CONF_FILE}")" = 'ADGUARD_LOCAL="COMMITTED"' ] || fail 'committed setup-file journal guard rolled back installer preferences'
[ -d "${BASE_DIR}/.AdGuardHome.nvram/setup-files" ] || fail 'committed setup-file journal guard removed deferred recovery state'
[ -f "${BASE_DIR}/.AdGuardHome.nvram/setup-committed" ] || fail 'committed setup-file journal guard removed the setup commit marker'

rm -rf "${BASE_DIR}/.AdGuardHome.nvram"
printf '%s\n' 'working configuration' >"${YAML_FILE}"
printf '%s\n' 'original configuration' >"${YAML_ORI}"
printf '%s\n' 'ADGUARD_IPSET="OLD"' >"${CONF_FILE}"
ADGUARD_INSTALL_MODE=lan
IPSET_SAW_SETUP_JOURNAL=0
SETUP_FILES_BEGIN_COUNT=0
SETUP_FILES_RESTORE_COUNT=0
# read_input_num sets the chosen input number to 1.
read_input_num() {
	CHOSEN=1
}
# configure_runtime_defaults configures runtime defaults and reports failure.
configure_runtime_defaults() {
	return 1
}
if setup_AdGuardHome_impl reconfig reconfig; then
	fail 'LAN existing-YAML reconfiguration ignored runtime-default failure after IPSET update'
fi
[ "${SETUP_FILES_BEGIN_COUNT}" -eq 1 ] || fail 'LAN existing-YAML reconfiguration did not initialize the setup-file journal exactly once'
[ "${IPSET_SAW_SETUP_JOURNAL}" -eq 1 ] || fail 'LAN existing-YAML reconfiguration changed IPSET before initializing the setup-file journal'
[ "${SETUP_FILES_RESTORE_COUNT}" -eq 1 ] || fail 'LAN runtime-default failure did not restore the setup-file journal'
[ "$(cat "${CONF_FILE}")" = 'ADGUARD_IPSET="OLD"' ] || fail 'LAN runtime-default failure retained the reconfigured IPSET preference'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/setup-files" ] || fail 'LAN runtime-default failure retained the restored setup-file journal'

printf '%s\n' 'PASS: failed WebUI port verification or persistence aborts setup safely'
