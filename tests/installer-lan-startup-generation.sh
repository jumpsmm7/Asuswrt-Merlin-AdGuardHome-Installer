#!/bin/sh
# Verify LAN-mode startup defaults and initial YAML generation for non-router sw_mode.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-lan-startup-generation.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions"

cleanup() {
	rm -rf "${TMP_ROOT}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"
mkdir -p "${TMP_ROOT}/target" || fail 'could not create test directory'

sed -n \
	'/^_quote() {$/,/^}$/p; /^conf_value() {$/,/^md5_is_valid() {$/p; /^write_conf() {$/,/^}$/p; /^ipv4_is_valid() {$/,/^port_is_valid() {$/p; /^setup_AdGuardHome() {$/,/^setup_amtmupdate() {$/p' \
	"${SCRIPT_PATH}" | sed '/^md5_is_valid() {$/d; /^port_is_valid() {$/d; /^setup_amtmupdate() {$/d' >"${FUNCTIONS_FILE}" ||
	fail 'could not extract installer helpers'
[ -s "${FUNCTIONS_FILE}" ] || fail 'installer helper extraction was empty'

grep -q '^adguard_install_mode_detect() {$' "${FUNCTIONS_FILE}" || fail 'install mode detection helper is missing'
grep -q '^configure_runtime_defaults() {$' "${FUNCTIONS_FILE}" || fail 'runtime defaults helper is missing'
grep -q '^setup_AdGuardHome_impl() {$' "${FUNCTIONS_FILE}" || fail 'setup helper is missing'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

INFO='Info:'
ERROR='Error:'
WARNING='Warning:'
TARG_DIR="${TMP_ROOT}/target"
AGH_FILE="${TARG_DIR}/AdGuardHome"
YAML_FILE="${TMP_ROOT}/AdGuardHome.yaml"
YAML_ORI="${TMP_ROOT}/AdGuardHome.yaml.original"
YAML_BAK="${TMP_ROOT}/AdGuardHome.yaml.backup"
YAML_ERR="${TMP_ROOT}/AdGuardHome.yaml.error"
CONF_FILE="${TMP_ROOT}/.config"

cat >"${AGH_FILE}" <<'SCRIPT'
#!/bin/sh
printf '%s\n' 'AdGuard Home, version test Schema version: 27'
SCRIPT
chmod 755 "${AGH_FILE}" || fail 'could not create AdGuardHome executable'
: >"${CONF_FILE}"

PTXT() {
	printf '%s\n' "$@"
}
create_dir() {
	mkdir -p "$1"
}
ptxt_ok() { :; }
read_input_port() { WEB_PORT=3000; }
read_input_dns() {
	if [ -z "${BOOTSTRAP1:-}" ]; then
		BOOTSTRAP1=9.9.9.9
	else
		BOOTSTRAP2=8.8.8.8
	fi
}
read_yesno() { return 1; }
AdGuardHome_authen() {
	printf '%s\n' 'users:' '- name: admin' '  password: hash' >>"$2"
}
check_AdGuardHome_yaml() { :; }
save_dns_filter_settings() { mkdir -p "$1"; }
restore_dns_filter_settings() { rm -rf "$1"; }
check_dns_filter() { :; }
check_dns_local() { :; }
check_ipset() { :; }
ai_have_cmd() { return 1; }
nvram() {
	case "${1:-}:${2:-}" in
		get:sw_mode) printf '%s\n' "${TEST_SW_MODE}" ;;
		get:lan_ipaddr) printf '%s\n' "${TEST_LAN_IPADDR}" ;;
		get:lan_ifname) printf '%s\n' '' ;;
		get:dns_local_cache) printf '%s\n' '1' ;;
		get:ipv6_rtr_addr) printf '%s\n' '' ;;
		get:lan_domain) printf '%s\n' 'lan' ;;
		get:lan_gateway) printf '%s\n' '192.168.1.1' ;;
		set:*) : ;;
		commit:) : ;;
		*) return 1 ;;
	esac
}

run_startup_case() {
	case_name="$1"
	TEST_SW_MODE="$2"
	TEST_LAN_IPADDR="$3"
	expected_mode="$4"
	expected_web="$5"

	rm -f "${CONF_FILE}" "${YAML_FILE}" "${YAML_ORI}" "${YAML_BAK}" "${YAML_ERR}"
	: >"${CONF_FILE}"
	BOOTSTRAP1=
	BOOTSTRAP2=
	ADGUARD_INSTALL_MODE=

	adguard_install_mode_detect || fail "${case_name}: install mode detection failed"
	[ "${ADGUARD_INSTALL_MODE}" = "${expected_mode}" ] || fail "${case_name}: expected mode ${expected_mode}, got ${ADGUARD_INSTALL_MODE}"
	configure_runtime_defaults new-install "${ADGUARD_INSTALL_MODE}" 0 >/dev/null || fail "${case_name}: runtime defaults failed"
	setup_AdGuardHome_impl '' install >/dev/null || fail "${case_name}: initial setup failed"

	grep -q "^ADGUARD_INSTALL_MODE=\"${expected_mode}\"$" "${CONF_FILE}" || fail "${case_name}: install mode was not persisted"
	grep -q "^ADGUARD_NETCHECK_MODE=\"${expected_mode}\"$" "${CONF_FILE}" || fail "${case_name}: netcheck mode was not persisted"
	grep -q "^  address: ${expected_web}\$" "${YAML_FILE}" || fail "${case_name}: WebUI bind address was not generated"
	grep -q '^  bind_hosts:$' "${YAML_FILE}" || fail "${case_name}: DNS bind_hosts section was not generated"
	case "${expected_mode}" in
		wan)
			grep -q '^    - 0\.0\.0\.0$' "${YAML_FILE}" || fail "${case_name}: wildcard DNS bind host was not generated"
			;;
		lan)
			awk -v expected="    - ${TEST_LAN_IPADDR}" '$0 == expected { found = 1 } END { exit(found ? 0 : 1) }' "${YAML_FILE}" ||
				fail "${case_name}: LAN DNS bind host was not generated"
			;;
	esac
}

run_startup_failure_case() {
	case_name="$1"
	TEST_SW_MODE="$2"
	TEST_LAN_IPADDR="$3"

	rm -f "${CONF_FILE}" "${YAML_FILE}" "${YAML_ORI}" "${YAML_BAK}" "${YAML_ERR}"
	: >"${CONF_FILE}"
	ADGUARD_INSTALL_MODE=

	if adguard_install_mode_detect >/dev/null 2>&1; then
		fail "${case_name}: install mode detection succeeded without a usable LAN IPv4 address"
	fi
	[ -z "${ADGUARD_INSTALL_MODE:-}" ] || fail "${case_name}: install mode was set after failed detection"
	[ ! -e "${YAML_FILE}" ] || fail "${case_name}: YAML was generated after failed detection"
	[ ! -s "${CONF_FILE}" ] || fail "${case_name}: config was written after failed detection"
}

run_startup_case repeater-lan 2 192.168.1.2 lan 192.168.1.2:3000
run_startup_case ap-lan 3 192.168.1.2 lan 192.168.1.2:3000
run_startup_case missing-sw-mode-lan '' 192.168.1.2 lan 192.168.1.2:3000
run_startup_case router-wan 1 192.168.1.1 wan 0.0.0.0:3000
run_startup_failure_case repeater-missing-lan-ip 2 ''
run_startup_failure_case ap-invalid-lan-ip 3 999.168.1.2
run_startup_failure_case missing-sw-mode-missing-lan-ip '' ''

printf '%s\n' 'PASS: installer startup persists mode defaults and generates LAN/WAN YAML bindings'
