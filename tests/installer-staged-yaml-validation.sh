#!/bin/sh
# Verify initial setup validates the staged YAML only after it is complete.

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

INFO='Info:'
ERROR='Error:'
WARNING='Warning:'
TMP_ROOT="${TMPDIR:-/tmp}/installer-staged-yaml-validation.$$"
TARG_DIR="${TMP_ROOT}/target"
AGH_FILE="${TARG_DIR}/AdGuardHome"
YAML_FILE="${TMP_ROOT}/AdGuardHome.yaml"
YAML_ORI="${TMP_ROOT}/AdGuardHome.yaml.original"
YAML_BAK="${TMP_ROOT}/AdGuardHome.yaml.backup"
YAML_ERR="${TMP_ROOT}/AdGuardHome.yaml.error"
CONF_FILE="${TMP_ROOT}/.config"
CHECK_LOG="${TMP_ROOT}/checks"
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
read_yesno() { return 1; }
write_conf() { :; }
save_dns_filter_settings() { mkdir -p "$1"; }
restore_dns_filter_settings() { rm -rf "$1"; }
check_dns_filter() { :; }
check_dns_local() { :; }
check_ipset() { :; }
ipv4_is_valid() {
	case "$1" in
		192.168.1.1 | 192.168.50.1) return 0 ;;
		*) return 1 ;;
	esac
}
ai_have_cmd() { return 1; }
nvram() {
	case "$1:${2:-}" in
		get:dns_local_cache) printf '%s\n' '1' ;;
		get:lan_ipaddr) printf '%s\n' '192.168.1.1' ;;
		get:ipv6_rtr_addr) printf '%s\n' '' ;;
		get:lan_domain) printf '%s\n' '' ;;
		set) : ;;
	esac
}
read_input_dns() {
	if [ -z "${BOOTSTRAP1:-}" ]; then
		BOOTSTRAP1=9.9.9.9
	else
		BOOTSTRAP2=8.8.8.8
	fi
}
AdGuardHome_authen() {
	printf '%s\n' 'users:' '- name: admin' '  password: hash' >>"$2"
}
check_AdGuardHome_yaml() {
	target="${1:-${YAML_FILE}}"
	printf '%s\n' "${target}" >>"${CHECK_LOG}"
	if [ "${target}" = "${YAML_ORI}.new.$$" ]; then
		grep -q '^dns:$' "${target}" || fail 'staged YAML was validated before dns was appended'
		grep -q '^schema_version: 27$' "${target}" || fail 'staged YAML was validated before schema_version was appended'
		if [ "${FAIL_STAGED_CHECK:-0}" -eq 1 ]; then
			mv "${target}" "${target}.err"
			return 1
		fi
	fi
	return 0
}

: >"${CONF_FILE}"
: >"${CHECK_LOG}"

if ! setup_AdGuardHome_impl '' install; then
	fail 'initial setup failed'
fi

first_check="$(sed -n '1p' "${CHECK_LOG}")"
second_check="$(sed -n '2p' "${CHECK_LOG}")"
[ "${first_check}" = "${YAML_ORI}.new.$$" ] || fail 'first validation did not target the complete staged YAML'
[ "${second_check}" = "${YAML_FILE}" ] || fail 'published YAML was not validated after copy'
grep -q '^dns:$' "${YAML_FILE}" || fail 'published YAML is missing dns section'
grep -q '^schema_version: 27$' "${YAML_FILE}" || fail 'published YAML is missing schema_version'
grep -q "^  - '\[/router.asus.com/\]\[::\]:553'" "${YAML_FILE}" || fail 'WAN router upstream did not use wildcard reverse target'
grep -q "^  - '\[::\]:553'" "${YAML_FILE}" || fail 'WAN local PTR upstream did not use wildcard reverse target'
grep -q "^  - '\[/10.in-addr.arpa/\]\[::\]:553'" "${YAML_FILE}" || fail 'WAN private PTR upstream did not use wildcard reverse target'
[ "$(cat "${YAML_ORI}")" = "$(cat "${YAML_FILE}")" ] || fail 'original snapshot does not match published YAML'

rm -f "${YAML_FILE}" "${YAML_ORI}" "${CHECK_LOG}"
BOOTSTRAP1=
BOOTSTRAP2=
ADGUARD_INSTALL_MODE=lan
ADGUARD_LAN_REVERSE_UPSTREAM=192.168.50.1
: >"${CHECK_LOG}"
if ! setup_AdGuardHome_impl '' install; then
	fail 'LAN initial setup failed'
fi
grep -q "^http:$" "${YAML_FILE}" || fail 'LAN published YAML is missing http section'
grep -q "^  address: 192.168.1.1:3000$" "${YAML_FILE}" || fail 'LAN web bind address did not use LAN IPv4'
grep -q "^  - '\[/router.asus.com/\]192.168.50.1:53'" "${YAML_FILE}" || fail 'LAN router upstream did not use LAN reverse target'
grep -q "^  - '192.168.50.1:53'" "${YAML_FILE}" || fail 'LAN local PTR upstream did not use LAN reverse target'
grep -q "^  - '\[/10.in-addr.arpa/\]192.168.50.1:53'" "${YAML_FILE}" || fail 'LAN private PTR upstream did not use LAN reverse target'

rm -f "${YAML_FILE}" "${YAML_ORI}" "${CHECK_LOG}"
BOOTSTRAP1=
BOOTSTRAP2=
ADGUARD_INSTALL_MODE=wan
ADGUARD_LAN_REVERSE_UPSTREAM=
FAIL_STAGED_CHECK=1
: >"${CHECK_LOG}"
if setup_AdGuardHome_impl '' install; then
	fail 'initial setup continued after staged YAML validation failed'
fi
[ ! -e "${YAML_FILE}" ] || fail 'failed staged validation published YAML_FILE'
[ ! -e "${YAML_ORI}" ] || fail 'failed staged validation published YAML_ORI'
[ -e "${YAML_ORI}.new.$$.err" ] || fail 'failed staged validation did not preserve the invalid staged YAML'
[ "$(wc -l <"${CHECK_LOG}")" -eq 1 ] || fail 'setup continued validating after staged YAML validation failed'

printf '%s\n' 'PASS: staged YAML validation runs after initial setup YAML is complete and aborts on failure'
