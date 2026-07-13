#!/bin/sh
# Verify failed DNS prompts abort setup and restore a backed-up configuration.

set -u

SCRIPT_PATH="${1:-installer}"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"

RUNTIME_DEFAULT_FUNCTIONS="$(sed -n '/^conf_value() {$/,/^md5_is_valid() {$/p' "${SCRIPT_PATH}" | sed '$d')"
ROLLBACK_FUNCTIONS="$(sed -n '/^rollback_result_write() {$/,/^rollback_result_summary() {$/p' "${SCRIPT_PATH}" | sed '$d')"
SETUP_FUNCTIONS="$(sed -n '/^setup_AdGuardHome() {$/,/^setup_amtmupdate() {$/p' "${SCRIPT_PATH}" | sed '$d')"
[ -n "${RUNTIME_DEFAULT_FUNCTIONS}" ] || fail 'could not extract runtime default functions'
[ -n "${ROLLBACK_FUNCTIONS}" ] || fail 'could not extract rollback result functions'
[ -n "${SETUP_FUNCTIONS}" ] || fail 'could not extract setup functions'
eval "${RUNTIME_DEFAULT_FUNCTIONS}"
eval "${ROLLBACK_FUNCTIONS}"
eval "${SETUP_FUNCTIONS}"

INFO='Info:'
ERROR='Error:'
WARNING='Warning:'
TMP_ROOT="${TMPDIR:-/tmp}/installer-dns-input-failure.$$"
ROLLBACK_RESULT_FILE="${TMP_ROOT}/.rollback_result"
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

ptxt_ok() { :; }
PTXT() {
	printf '%s\n' "$@"
}
read_input_num() { CHOSEN=3; }
read_input_port() { WEB_PORT=3000; }
write_conf() {
	printf '%s\n' "$*" >>"${WRITE_LOG}"
	if [ "$1" = ADGUARD_DOMAIN ]; then
		printf '%s\n' 'ADGUARD_DOMAIN="CHANGED"' >>"${CONF_FILE}"
	fi
}
AdGuardHome_authen() {
	AUTH_TARGET="${2:-}"
}
check_AdGuardHome_yaml() { return 0; }
check_dns_filter() {
	DNS_FILTER_CALLS="$((DNS_FILTER_CALLS + 1))"
	[ "${FAIL_NESTED_DNS_PROMPT:-0}" -eq 1 ] && return 2
	return 0
}
save_dns_filter_settings() {
	mkdir -p "$1"
}
restore_dns_filter_settings() {
	rm -rf "$1"
}
check_dns_local() {
	LOCAL_CACHE_CALLS="$((LOCAL_CACHE_CALLS + 1))"
	[ "${FAIL_LOCAL_CACHE_SAVE:-0}" -eq 0 ]
}
check_ipset() { :; }
read_yesno() {
	CONFIRM_PROMPTS="$((CONFIRM_PROMPTS + 1))"
	[ "${CONFIRM_PROMPTS}" -eq "${FAIL_CONFIRM_PROMPT:-0}" ] && return 2
	return 1
}
nvram() {
	case "$1:${2:-}" in
		get:dns_local_cache) printf '%s\n' '0' ;;
	esac
}

DNS_PROMPTS=0
LOCAL_CACHE_CALLS=0
read_input_dns() {
	DNS_PROMPTS="$((DNS_PROMPTS + 1))"
	[ "${DNS_PROMPTS}" -eq "${FAIL_PROMPT}" ] && return 1
	BOOTSTRAP1=9.9.9.9
	BOOTSTRAP2=8.8.8.8
	return 0
}

: >"${CONF_FILE}"
for FAIL_CONFIRM_PROMPT in 1 2 3; do
	CONFIRM_PROMPTS=0
	DNS_FILTER_CALLS=0
	printf '%s\n' 'working configuration' >"${YAML_FILE}"
	printf '%s\n' 'original template' >"${YAML_ORI}"
	: >"${WRITE_LOG}"

	if setup_AdGuardHome_impl reconfig reconfig; then
		fail "setup accepted failed confirmation prompt ${FAIL_CONFIRM_PROMPT}"
	fi
	[ "${CONFIRM_PROMPTS}" -eq "${FAIL_CONFIRM_PROMPT}" ] || fail "setup did not stop at confirmation prompt ${FAIL_CONFIRM_PROMPT}"
	[ "${DNS_FILTER_CALLS}" -eq 0 ] || fail "setup changed DNSFilter before confirmation prompt ${FAIL_CONFIRM_PROMPT} completed"
	! grep -q '^ADGUARD_WEBUI_PORT ' "${WRITE_LOG}" || fail "setup saved the WebUI port before confirmation prompt ${FAIL_CONFIRM_PROMPT} completed"
	[ "$(cat "${YAML_FILE}")" = 'working configuration' ] || fail "setup did not restore YAML after confirmation prompt ${FAIL_CONFIRM_PROMPT}"
	[ ! -e "${YAML_BAK}" ] || fail "setup left the YAML backup after confirmation prompt ${FAIL_CONFIRM_PROMPT}"
done
unset FAIL_CONFIRM_PROMPT

FAIL_NESTED_DNS_PROMPT=1
CONFIRM_PROMPTS=0
DNS_FILTER_CALLS=0
FAIL_PROMPT=0
printf '%s\n' 'ADGUARD_DOMAIN="OLD"' >"${CONF_FILE}"
printf '%s\n' 'working configuration' >"${YAML_FILE}"
printf '%s\n' 'original template' >"${YAML_ORI}"
: >"${WRITE_LOG}"

if setup_AdGuardHome_impl reconfig reconfig; then
	fail 'setup accepted failed nested DNS confirmation prompt'
fi
[ "${AUTH_TARGET}" = "${YAML_ORI}.new.$$" ] || fail 'setup did not write credentials to the staged YAML snapshot'
[ "$(cat "${YAML_FILE}")" = 'working configuration' ] || fail 'setup did not restore YAML after nested DNS confirmation failure'
! grep -q '^ADGUARD_WEBUI_PORT ' "${WRITE_LOG}" || fail 'setup saved the WebUI port before nested DNS confirmation completed'
[ ! -e "${YAML_BAK}" ] || fail 'setup left the YAML backup after nested DNS confirmation failure'
[ "$(cat "${YAML_ORI}")" = 'original template' ] || fail 'setup replaced the original snapshot after nested DNS confirmation failure'
[ ! -e "${YAML_ORI}.new.$$" ] || fail 'setup left an aborted replacement snapshot after nested DNS confirmation failure'
[ "$(cat "${CONF_FILE}")" = 'ADGUARD_DOMAIN="OLD"' ] || fail 'setup did not restore installer preferences after nested DNS confirmation failure'
unset FAIL_NESTED_DNS_PROMPT
unset FAIL_PROMPT

FAIL_LOCAL_CACHE_SAVE=1
CONFIRM_PROMPTS=0
DNS_FILTER_CALLS=0
LOCAL_CACHE_CALLS=0
DNS_PROMPTS=0
FAIL_PROMPT=0
printf '%s\n' 'working configuration' >"${YAML_FILE}"
printf '%s\n' 'original template' >"${YAML_ORI}"
: >"${WRITE_LOG}"

if setup_AdGuardHome_impl reconfig reconfig; then
	fail 'setup accepted a failed local-cache preference save'
fi
[ "${LOCAL_CACHE_CALLS}" -eq 1 ] || fail 'setup did not attempt to save the local-cache preference'
[ "$(cat "${YAML_FILE}")" = 'working configuration' ] || fail 'setup did not restore YAML after local-cache persistence failed'
! grep -q '^ADGUARD_WEBUI_PORT ' "${WRITE_LOG}" || fail 'setup saved the WebUI port after local-cache persistence failed'
[ ! -e "${YAML_BAK}" ] || fail 'setup left the YAML backup after local-cache persistence failed'
[ "$(cat "${YAML_ORI}")" = 'original template' ] || fail 'setup replaced the original snapshot after local-cache persistence failed'
[ ! -e "${YAML_ORI}.new.$$" ] || fail 'setup left an aborted replacement snapshot after local-cache persistence failed'
unset FAIL_LOCAL_CACHE_SAVE
unset FAIL_PROMPT

for FAIL_PROMPT in 1 2; do
	CONFIRM_PROMPTS=0
	DNS_PROMPTS=0
	DNS_FILTER_CALLS=0
	printf '%s\n' 'working configuration' >"${YAML_FILE}"
	printf '%s\n' 'original template' >"${YAML_ORI}"
	: >"${WRITE_LOG}"

	if setup_AdGuardHome_impl reconfig reconfig; then
		fail "setup accepted failed DNS prompt ${FAIL_PROMPT}"
	fi
	[ "${DNS_PROMPTS}" -eq "${FAIL_PROMPT}" ] || fail "setup did not stop at DNS prompt ${FAIL_PROMPT}"
	[ "${DNS_FILTER_CALLS}" -eq 0 ] || fail "setup changed DNSFilter before DNS prompt ${FAIL_PROMPT} completed"
	! grep -q '^ADGUARD_WEBUI_PORT ' "${WRITE_LOG}" || fail "setup saved the WebUI port before DNS prompt ${FAIL_PROMPT} completed"
	[ "$(cat "${YAML_FILE}")" = 'working configuration' ] || fail "setup did not restore YAML after DNS prompt ${FAIL_PROMPT}"
	[ ! -e "${YAML_BAK}" ] || fail "setup left the YAML backup after DNS prompt ${FAIL_PROMPT}"
	[ "$(cat "${YAML_ORI}")" = 'original template' ] || fail "setup replaced the original snapshot after DNS prompt ${FAIL_PROMPT}"
	[ ! -e "${YAML_ORI}.new.$$" ] || fail "setup left a partial replacement snapshot after DNS prompt ${FAIL_PROMPT}"
done

printf '%s\n' 'PASS: failed DNS input aborts setup and restores the previous configuration'
