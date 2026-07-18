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
YESNO_LOG="${TMP_ROOT}/yesno"
IPSET_LOG="${TMP_ROOT}/ipset"
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
read_yesno() {
	printf '%s\n' "$1" >>"${YESNO_LOG}"
	case "$1" in
		*IPSET*) return "${IPSET_YESNO_STATUS:-1}" ;;
	esac
	return 1
}
write_conf() {
	key="$1"
	value="$2"
	tmp_file="${CONF_FILE}.$$"
	if [ -f "${CONF_FILE}" ]; then
		grep -v "^${key}=" "${CONF_FILE}" >"${tmp_file}" || :
	else
		: >"${tmp_file}"
	fi
	printf '%s=%s\n' "${key}" "${value}" >>"${tmp_file}"
	mv -f "${tmp_file}" "${CONF_FILE}"
}
save_dns_filter_settings() { mkdir -p "$1"; }
restore_dns_filter_settings() { rm -rf "$1"; }
check_dns_filter() { :; }
check_dns_local() { :; }
check_ipset() {
	printf '%s\n' "$1" >>"${IPSET_LOG}"
	case "$1" in
		1) write_conf ADGUARD_IPSET '"YES"' ;;
		*) write_conf ADGUARD_IPSET '"NO"' ;;
	esac
}
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
		get:lan_gateway) printf '%s\n' "${TEST_LAN_GATEWAY:-}" ;;
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

reset_setup_logs() {
	rm -f "${YAML_FILE}" "${YAML_ORI}" "${CHECK_LOG}" "${YESNO_LOG}" "${IPSET_LOG}"
	BOOTSTRAP1=
	BOOTSTRAP2=
	: >"${CHECK_LOG}"
	: >"${YESNO_LOG}"
	: >"${IPSET_LOG}"
	IPSET_YESNO_STATUS=0
}

assert_lan_yaml_reverse_upstreams() {
	expected_target="$1"
	case_label="$2"

	grep -q "^http:$" "${YAML_FILE}" || fail "${case_label}: LAN published YAML is missing http section"
	grep -q "^  address: 192.168.1.1:3000$" "${YAML_FILE}" || fail "${case_label}: LAN web bind address did not use LAN IPv4"
	grep -q "^  - '\[/router.asus.com/\]${expected_target}'" "${YAML_FILE}" || fail "${case_label}: LAN router upstream did not use LAN reverse target"
	grep -q "^  - '\[//\]${expected_target}'" "${YAML_FILE}" || fail "${case_label}: LAN local domain upstream did not use LAN reverse target"
	grep -q "^  - '${expected_target}'" "${YAML_FILE}" || fail "${case_label}: LAN local PTR upstream did not use LAN reverse target"
	grep -q "^  - '\[/10.in-addr.arpa/\]${expected_target}'" "${YAML_FILE}" || fail "${case_label}: LAN private PTR upstream did not use LAN reverse target"
	if grep -q '\[::\]:553' "${YAML_FILE}"; then
		fail "${case_label}: LAN setup emitted WAN wildcard reverse target"
	fi
	if grep -q 'IPSET integration' "${YESNO_LOG}"; then
		fail "${case_label}: LAN setup showed the IPSET prompt"
	fi
	grep -q '^0$' "${IPSET_LOG}" || fail "${case_label}: LAN setup did not force IPSET disabled selection"
	grep -q '^ADGUARD_IPSET="NO"$' "${CONF_FILE}" || fail "${case_label}: LAN setup did not persist ADGUARD_IPSET=NO"
}

: >"${CONF_FILE}"
: >"${CHECK_LOG}"
: >"${YESNO_LOG}"
: >"${IPSET_LOG}"
IPSET_YESNO_STATUS=0

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
grep -q "^  - '\[//\]\[::\]:553'" "${YAML_FILE}" || fail 'WAN local domain upstream did not use wildcard reverse target'
grep -q "^  - '\[::\]:553'" "${YAML_FILE}" || fail 'WAN local PTR upstream did not use wildcard reverse target'
grep -q "^  - '\[/10.in-addr.arpa/\]\[::\]:553'" "${YAML_FILE}" || fail 'WAN private PTR upstream did not use wildcard reverse target'
grep -q 'IPSET integration' "${YESNO_LOG}" || fail 'WAN setup did not show the IPSET prompt'
grep -q '^1$' "${IPSET_LOG}" || fail 'WAN setup did not accept IPSET enablement'
grep -q '^ADGUARD_IPSET="YES"$' "${CONF_FILE}" || fail 'WAN setup did not persist ADGUARD_IPSET=YES'
[ "$(cat "${YAML_ORI}")" = "$(cat "${YAML_FILE}")" ] || fail 'original snapshot does not match published YAML'

reset_setup_logs
ADGUARD_INSTALL_MODE=lan
ADGUARD_LAN_REVERSE_UPSTREAM=192.168.1.1
TEST_LAN_GATEWAY=
if ! setup_AdGuardHome_impl '' install; then
	fail 'LAN explicit reverse upstream setup failed'
fi
assert_lan_yaml_reverse_upstreams '192.168.1.1:53' 'LAN explicit reverse upstream'

reset_setup_logs
ADGUARD_INSTALL_MODE=lan
ADGUARD_LAN_REVERSE_UPSTREAM=
TEST_LAN_GATEWAY=
write_conf ADGUARD_LAN_REVERSE_UPSTREAM '"192.168.50.1"'
if ! setup_AdGuardHome_impl '' install; then
	fail 'LAN persisted reverse upstream setup failed'
fi
assert_lan_yaml_reverse_upstreams '192.168.50.1:53' 'LAN persisted reverse upstream'

reset_setup_logs
ADGUARD_INSTALL_MODE=lan
ADGUARD_LAN_REVERSE_UPSTREAM=
TEST_LAN_GATEWAY=192.168.1.1
write_conf ADGUARD_LAN_REVERSE_UPSTREAM '""'
if ! setup_AdGuardHome_impl '' install; then
	fail 'LAN gateway reverse upstream setup failed'
fi
assert_lan_yaml_reverse_upstreams '192.168.1.1:53' 'LAN gateway reverse upstream'

reset_setup_logs
ADGUARD_INSTALL_MODE=lan
ADGUARD_LAN_REVERSE_UPSTREAM=
TEST_LAN_GATEWAY=
write_conf ADGUARD_LAN_REVERSE_UPSTREAM '""'
if setup_AdGuardHome_impl '' install; then
	fail 'LAN setup continued with a missing main router reverse upstream'
fi
[ ! -e "${YAML_FILE}" ] || fail 'LAN missing router IP wrote published YAML'
[ ! -e "${YAML_ORI}.new.$$" ] || fail 'LAN missing router IP wrote staged YAML'

rm -f "${YAML_FILE}" "${YAML_ORI}" "${CHECK_LOG}" "${YESNO_LOG}" "${IPSET_LOG}"
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
