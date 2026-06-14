#!/bin/sh
# Verify setup does not persist an unverified WebUI port when port selection fails.

set -u

SCRIPT_PATH="${1:-installer}"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"

SETUP_FUNCTIONS="$(sed -n '/^setup_AdGuardHome() {$/,/^setup_amtmupdate() {$/p' "${SCRIPT_PATH}" | sed '$d')"
[ -n "${SETUP_FUNCTIONS}" ] || fail 'could not extract setup functions'
eval "${SETUP_FUNCTIONS}"

INFO='Info:'
ERROR='Error:'
WARNING='Warning:'
TMP_ROOT="${TMPDIR:-/tmp}/installer-web-port-failure.$$"
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

PTXT() { :; }
read_input_port() {
	WEB_PORT=3000
	return 1
}
write_conf() {
	printf '%s\n' "$*" >>"${WRITE_LOG}"
	[ "${FAIL_WRITE_CONF:-0}" -eq 0 ]
}
yaml_nvars_replace() {
	printf '%s\n' "$*" >>"${WRITE_LOG}"
}
YAML_CHECKS=0
check_AdGuardHome_yaml() {
	YAML_CHECKS="$((YAML_CHECKS + 1))"
}
DNS_FILTER_CHANGED=0
DNS_FILTER_RESTORES=0
save_dns_filter_settings() {
	mkdir -p "$1"
}
restore_dns_filter_settings() {
	DNS_FILTER_RESTORES="$((DNS_FILTER_RESTORES + 1))"
	DNS_FILTER_CHANGED=0
	rm -rf "$1"
}
check_dns_filter() {
	DNS_FILTER_CHANGED=1
}
check_dns_local() { :; }
check_ipset() { :; }
read_yesno() { return 1; }
AdGuardHome_authen() { :; }
read_input_dns() {
	if [ -z "${BOOTSTRAP1:-}" ]; then
		BOOTSTRAP1=9.9.9.9
	else
		BOOTSTRAP2=8.8.8.8
	fi
}
ai_have_cmd() { return 1; }
nvram() {
	case "$1:${2:-}" in
		get:dns_local_cache) printf '%s\n' '1' ;;
		get:lan_ipaddr) printf '%s\n' '192.168.1.1' ;;
	esac
}

: >"${CONF_FILE}"
: >"${WRITE_LOG}"
printf '%s\n' 'http:' '  address: 0.0.0.0:3000' 'schema_version: 27' >"${YAML_FILE}"
if setup_AdGuardHome_impl ''; then
	fail 'existing-config setup accepted a WebUI port that could not be verified'
fi
[ ! -s "${WRITE_LOG}" ] || fail 'existing-config setup persisted an unverified WebUI port'
[ "${YAML_CHECKS}" -eq 0 ] || fail 'existing-config setup continued after WebUI port selection failed'
grep -q 'address: 0.0.0.0:3000' "${YAML_FILE}" || fail 'existing YAML was changed after port selection failed'

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
: >"${WRITE_LOG}"
YAML_CHECKS=0
FAIL_WRITE_CONF=1
DNS_FILTER_CHANGED=0
DNS_FILTER_RESTORES=0
read_input_port() {
	WEB_PORT=3000
	return 0
}
if setup_AdGuardHome_impl reconfig reconfig; then
	fail 'reconfiguration accepted a WebUI port that could not be persisted'
fi
grep -q '^ADGUARD_WEBUI_PORT ' "${WRITE_LOG}" || fail 'reconfiguration did not attempt to persist the selected WebUI port'
[ "${YAML_CHECKS}" -eq 2 ] || fail 'reconfiguration did not validate the generated YAML before persisting the WebUI port'
[ "$(cat "${YAML_FILE}")" = 'working configuration' ] || fail 'reconfiguration did not restore the previous YAML after WebUI port persistence failed'
[ ! -e "${YAML_BAK}" ] || fail 'reconfiguration left the YAML backup behind after WebUI port persistence failed'
[ "${DNS_FILTER_CHANGED}" -eq 0 ] || fail 'reconfiguration left changed DNSFilter settings after WebUI port persistence failed'
[ "${DNS_FILTER_RESTORES}" -eq 1 ] || fail 'reconfiguration did not restore DNSFilter settings after WebUI port persistence failed'

printf '%s\n' 'PASS: failed WebUI port verification or persistence aborts setup safely'
