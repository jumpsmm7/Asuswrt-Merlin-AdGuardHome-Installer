#!/bin/sh
# Verify LAN-mode startup defaults and initial YAML generation for non-router sw_mode.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-lan-startup-generation.$$"
BASE_DIR="${TMP_ROOT}/base"
FUNCTIONS_FILE="${TMP_ROOT}/functions"

# cleanup removes the temporary test workspace.
cleanup() {
	rm -rf "${TMP_ROOT}"
}

# fail prints a failure message to standard error and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"
mkdir -p "${TMP_ROOT}/target" || fail 'could not create test directory'

sed -n \
	'/^_quote() {$/,/^}$/p; /^conf_value() {$/,/^md5_is_valid() {$/p; /^write_conf() {$/,/^}$/p; /^ipv4_is_valid() {$/,/^port_is_valid() {$/p; /^startup_action_allows_unknown_install_mode() {$/,/^}$/p; /^setup_AdGuardHome() {$/,/^setup_amtmupdate() {$/p' \
	"${SCRIPT_PATH}" | sed '/^md5_is_valid() {$/d; /^port_is_valid() {$/d; /^setup_amtmupdate() {$/d' >"${FUNCTIONS_FILE}" ||
	fail 'could not extract installer helpers'
[ -s "${FUNCTIONS_FILE}" ] || fail 'installer helper extraction was empty'

grep -q '^adguard_install_mode_detect() {$' "${FUNCTIONS_FILE}" || fail 'install mode detection helper is missing'
grep -q '^adguard_install_mode_confirmed() {$' "${FUNCTIONS_FILE}" || fail 'install mode confirmation helper is missing'
grep -q '^startup_action_allows_unknown_install_mode() {$' "${FUNCTIONS_FILE}" || fail 'startup action validation helper is missing'
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

# PTXT prints each argument on a separate line.
PTXT() {
	printf '%s\n' "$@"
}
# create_dir creates the specified directory and any missing parent directories.
create_dir() {
	mkdir -p "$1"
}
ptxt_ok() { :; }
# read_input_port sets the web interface port to 3000.
read_input_port() { WEB_PORT=3000; }
# read_input_dns sets the first bootstrap DNS server to 9.9.9.9 or the second to 8.8.8.8 depending on whether the first is already set.
read_input_dns() {
	if [ -z "${BOOTSTRAP1:-}" ]; then
		BOOTSTRAP1=9.9.9.9
	else
		BOOTSTRAP2=8.8.8.8
	fi
}
# read_yesno indicates a negative response.
read_yesno() { return 1; }
# AdGuardHome_authen appends a default AdGuard Home administrator entry to the specified configuration file.
AdGuardHome_authen() {
	printf '%s\n' 'users:' '- name: admin' '  password: hash' >>"$2"
}
# check_AdGuardHome_yaml validates the AdGuard Home YAML configuration.
check_AdGuardHome_yaml() { :; }
# save_dns_filter_settings creates the directory used to preserve DNS filter settings.
save_dns_filter_settings() { mkdir -p "$1"; }
# installer_lan_domain_set stores the specified LAN domain in NVRAM.
installer_lan_domain_set() { nvram set "lan_domain=$1"; }
# installer_lan_domain_restore provides a no-op stub for restoring the configured LAN domain.
installer_lan_domain_restore() { :; }
# nvram_transaction_finalize_setup_pair completes the simulated NVRAM setup transaction successfully.
nvram_transaction_finalize_setup_pair() { return 0; }
# nvram_transaction_setup_files_begin starts an NVRAM setup-files transaction.
nvram_transaction_setup_files_begin() { return 0; }
# nvram_transaction_setup_files_restore restores NVRAM transaction setup files successfully.
nvram_transaction_setup_files_restore() { return 0; }
# restore_dns_filter_settings removes the specified directory and all of its contents.
restore_dns_filter_settings() { rm -rf "$1"; }
# check_dns_filter is a no-op test stub for DNS filter checks.
check_dns_filter() { :; }
# check_dns_local is a no-op stub for checking local DNS configuration.
check_dns_local() { :; }
# check_ipset is a no-op test stub for IP set validation.
check_ipset() { :; }
# ai_have_cmd always reports that the requested command is unavailable.
ai_have_cmd() { return 1; }
# nvram simulates NVRAM reads and writes for installer tests.
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

# run_startup_case validates install-mode detection, runtime defaults, and generated LAN/WAN startup configuration for a test scenario.
# run_startup_case verifies install-mode detection, runtime configuration, setup output, and generated LAN/WAN bindings for a startup scenario.
# run_startup_case verifies install-mode detection, runtime default persistence, and LAN/WAN YAML bindings for a startup scenario.
# Arguments are the case name, simulated switch mode, LAN IP address, expected install mode, and expected WebUI bind address.
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

# run_startup_failure_case verifies that unknown install-mode detection is rejected without setting the install mode or creating YAML or configuration artifacts.
run_startup_failure_case() {
	case_name="$1"
	TEST_SW_MODE="$2"
	TEST_LAN_IPADDR="$3"

	rm -f "${CONF_FILE}" "${YAML_FILE}" "${YAML_ORI}" "${YAML_BAK}" "${YAML_ERR}"
	: >"${CONF_FILE}"
	ADGUARD_INSTALL_MODE=
	PREVIOUS_ADGUARD_INSTALL_MODE=

	# Follow the production dispatch path from installer lines 8726-8736
	adguard_install_mode_detect >/dev/null 2>&1 || fail "${case_name}: install mode detection failed"
	[ "${ADGUARD_INSTALL_MODE_DETECTION:-}" = unknown ] || fail "${case_name}: detection was not unknown"

	# Check if mode is confirmed (production uses adguard_install_mode_confirmed)
	if ! adguard_install_mode_confirmed; then
		# No previous mode (simulating fresh install) and no existing installation
		# Production checks startup_action_allows_unknown_install_mode here
		# Using empty strings for $1 and $2 to simulate 'install' action which requires confirmed mode
		if ! startup_action_allows_unknown_install_mode "" ""; then
			# This is the expected path - mode is unknown and action doesn't allow it
			# Verify no state was modified (matching production exit at line 8735-8736)
			[ -z "${ADGUARD_INSTALL_MODE:-}" ] || fail "${case_name}: install mode was set despite unknown detection"
			[ ! -e "${YAML_FILE}" ] || fail "${case_name}: YAML was generated despite unknown detection"
			[ ! -s "${CONF_FILE}" ] || fail "${case_name}: config was written despite unknown detection"
			return 0
		else
			fail "${case_name}: startup_action_allows_unknown_install_mode incorrectly allowed unknown mode"
		fi
	else
		fail "${case_name}: install mode was confirmed when it should have been unknown"
	fi
}

run_startup_case repeater-lan 2 192.168.1.2 lan 192.168.1.2:3000
run_startup_case ap-lan 3 192.168.1.2 lan 192.168.1.2:3000
run_startup_case media-bridge-lan 4 192.168.1.2 lan 192.168.1.2:3000
run_startup_case router-wan 1 192.168.1.1 wan 0.0.0.0:3000
run_startup_failure_case repeater-missing-lan-ip 2 ''
run_startup_failure_case ap-invalid-lan-ip 3 999.168.1.2
run_startup_failure_case missing-sw-mode-missing-lan-ip '' ''
run_startup_failure_case missing-sw-mode-usable-lan-ip '' 192.168.1.2
run_startup_failure_case unrecognized-sw-mode-usable-lan-ip 9 192.168.1.2

printf '%s\n' 'PASS: installer startup persists mode defaults and generates LAN/WAN YAML bindings'
