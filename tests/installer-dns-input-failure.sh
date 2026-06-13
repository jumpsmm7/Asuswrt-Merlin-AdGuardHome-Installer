#!/bin/sh
# Verify failed DNS prompts abort setup and restore a backed-up configuration.

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
TMP_ROOT="${TMPDIR:-/tmp}/installer-dns-input-failure.$$"
TARG_DIR="${TMP_ROOT}/target"
AGH_FILE="${TARG_DIR}/AdGuardHome"
YAML_FILE="${TMP_ROOT}/AdGuardHome.yaml"
YAML_ORI="${TMP_ROOT}/AdGuardHome.yaml.original"
YAML_BAK="${TMP_ROOT}/AdGuardHome.yaml.backup"
YAML_ERR="${TMP_ROOT}/AdGuardHome.yaml.error"
CONF_FILE="${TMP_ROOT}/.config"
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

PTXT() {
	if [ "${1:-}" = "http:" ]; then
		printf '%s\n' "$@" >"${YAML_ORI}"
	fi
}
read_input_num() { CHOSEN=3; }
read_input_port() { WEB_PORT=3000; }
write_conf() { :; }
AdGuardHome_authen() { :; }
check_AdGuardHome_yaml() { return 0; }
check_dns_filter() { :; }
check_dns_local() { :; }
check_ipset() { :; }
read_yesno() { return 1; }
nvram() {
	case "$1:${2:-}" in
		get:dns_local_cache) printf '%s\n' '1' ;;
	esac
}

DNS_PROMPTS=0
read_input_dns() {
	DNS_PROMPTS="$((DNS_PROMPTS + 1))"
	[ "${DNS_PROMPTS}" -eq "${FAIL_PROMPT}" ] && return 1
	BOOTSTRAP1=9.9.9.9
	return 0
}

: >"${CONF_FILE}"
for FAIL_PROMPT in 1 2; do
	DNS_PROMPTS=0
	printf '%s\n' 'working configuration' >"${YAML_FILE}"
	printf '%s\n' 'original template' >"${YAML_ORI}"

	if setup_AdGuardHome_impl reconfig reconfig; then
		fail "setup accepted failed DNS prompt ${FAIL_PROMPT}"
	fi
	[ "${DNS_PROMPTS}" -eq "${FAIL_PROMPT}" ] || fail "setup did not stop at DNS prompt ${FAIL_PROMPT}"
	[ "$(cat "${YAML_FILE}")" = 'working configuration' ] || fail "setup did not restore YAML after DNS prompt ${FAIL_PROMPT}"
	[ ! -e "${YAML_BAK}" ] || fail "setup left the YAML backup after DNS prompt ${FAIL_PROMPT}"
	[ ! -e "${YAML_ORI}" ] || fail "setup left partial YAML after DNS prompt ${FAIL_PROMPT}"
done

printf '%s\n' 'PASS: failed DNS input aborts setup and restores the previous configuration'
