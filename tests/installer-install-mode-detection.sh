#!/bin/sh
# Verify sw_mode no longer hard-exits LAN-mode install paths.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-install-mode-detection.$$"
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
mkdir -p "${TMP_ROOT}" || fail 'could not create test directory'

sed -n '/^ipv4_is_valid() {$/,/^port_is_valid() {$/p' "${SCRIPT_PATH}" | sed '$d' >"${FUNCTIONS_FILE}" ||
	fail 'could not extract install mode helpers'
[ -s "${FUNCTIONS_FILE}" ] || fail 'install mode helper extraction was empty'

grep -q '^adguard_install_mode_detect() {$' "${SCRIPT_PATH}" ||
	fail 'install mode detection helper is missing'
grep -q 'write_conf ADGUARD_INSTALL_MODE "\\"${ADGUARD_INSTALL_MODE}\\""' "${SCRIPT_PATH}" ||
	fail 'installer must persist ADGUARD_INSTALL_MODE'
grep -q 'PREVIOUS_ADGUARD_INSTALL_MODE="$(conf_value ADGUARD_INSTALL_MODE 2>/dev/null)"' "${SCRIPT_PATH}" ||
	fail 'installer must preserve the saved install mode before detection'
awk '
	/^case "\$\{1:-\}" in$/ { in_dispatch = 1 }
	in_dispatch && /install \| update\)/ { mode_actions = 1 }
	mode_actions && /adguard_install_mode_detect \|\| exit 1/ { detected = 1 }
	mode_actions && /cli_run "\$@"/ { exit(detected ? 0 : 1) }
	END { if (!in_dispatch || !mode_actions) exit 1 }
' "${SCRIPT_PATH}" || fail 'install/update CLI dispatch does not detect install mode before cli_run'
grep -q 'adguard_migrate_detected_install_mode "${PREVIOUS_ADGUARD_INSTALL_MODE:-}"' "${SCRIPT_PATH}" ||
	fail 'install/update orchestration must migrate mode-dependent settings'
if sed -n '/^PREVIOUS_ADGUARD_INSTALL_MODE=/,/^if \[ "${ADGUARD_INSTALL_MODE}" = "wan" \]/p' "${SCRIPT_PATH}" |
	grep -q 'adguard_migrate_detected_install_mode'; then
	fail 'installer startup must not migrate mode-dependent settings before action dispatch'
fi
service_install_line="$(grep -n 'ptxt_ok "AdGuardHome service files installed\."' "${SCRIPT_PATH}" | cut -d: -f1)"
migration_line="$(grep -n 'adguard_migrate_detected_install_mode "${PREVIOUS_ADGUARD_INSTALL_MODE:-}"' "${SCRIPT_PATH}" | cut -d: -f1)"
[ -n "${service_install_line}" ] && [ -n "${migration_line}" ] && [ "${migration_line}" -gt "${service_install_line}" ] ||
	fail 'mode migration must run only after mode-aware service scripts are installed'
firewall_cleanup_line="$(awk -v after="${service_install_line}" 'NR > after && /^[[:space:]]*cleanup_legacy_firewall$/ { print NR; exit }' "${SCRIPT_PATH}")"
event_cleanup_line="$(grep -n 'yaml_nvars_delete "#Asuswrt-Merlin AdGuardHome Installer" /jffs/scripts/dnsmasq.postconf' "${SCRIPT_PATH}" | head -n 1 | cut -d: -f1)"
[ -n "${firewall_cleanup_line}" ] && [ -n "${event_cleanup_line}" ] &&
	[ "${migration_line}" -lt "${firewall_cleanup_line}" ] && [ "${migration_line}" -lt "${event_cleanup_line}" ] ||
	fail 'mode migration must finish before firewall state or event hooks are changed'
sed -n '/^adguard_migrate_detected_install_mode() {$/,/^}$/p' "${SCRIPT_PATH}" >"${TMP_ROOT}/migration" ||
	fail 'could not extract install-mode migration helper'
wan_hooks_line="$(grep -n 'install_wan_event_scripts' "${TMP_ROOT}/migration" | cut -d: -f1)"
mode_write_line="$(grep -n 'write_conf ADGUARD_INSTALL_MODE' "${TMP_ROOT}/migration" | head -n 1 | cut -d: -f1)"
[ -n "${wan_hooks_line}" ] && [ -n "${mode_write_line}" ] && [ "${wan_hooks_line}" -lt "${mode_write_line}" ] ||
	fail 'LAN-to-WAN migration must install WAN event hooks before persisting WAN mode'
grep -q 'if \[ "${previous_mode}" = "lan" \] && ! install_wan_event_scripts; then' "${TMP_ROOT}/migration" ||
	fail 'LAN-to-WAN migration does not require WAN event-script synchronization'
grep -q 'Unable to install the required WAN-mode event scripts' "${TMP_ROOT}/migration" ||
	fail 'LAN-to-WAN migration does not abort when WAN event-script synchronization fails'
grep -q 'wan:lan | lan:wan | :lan)' "${SCRIPT_PATH}" ||
	fail 'installer must migrate legacy installs without a saved mode when LAN mode is detected'
grep -q 'if \[ "${ADGUARD_INSTALL_MODE}" = "wan" \] && \[ -n "${NAT_ENV}" \]' "${SCRIPT_PATH}" ||
	fail 'double-NAT warning must be gated by WAN install mode'
grep -q 'if \[ "${ADGUARD_INSTALL_MODE}" = "wan" \]; then' "${SCRIPT_PATH}" ||
	fail 'DNS environment preparation must be gated by WAN install mode'
grep -q 'if \[ "${ADGUARD_INSTALL_MODE:-wan}" = "wan" \] && \[ -n "${DNS_FILTER_SELECTION:-}" \]; then' "${SCRIPT_PATH}" ||
	fail 'DNSFilter mutation must be gated by WAN install mode'
grep -q 'if { \[ "${ADGUARD_INSTALL_MODE:-wan}" = "lan" \] || \[ -n "${DNS_FILTER_SELECTION:-}" \]; } &&' "${SCRIPT_PATH}" ||
	fail 'LAN runtime defaults must not depend on DNSFilter selection'
grep -q 'if \[ "${ADGUARD_INSTALL_MODE:-wan}" = "wan" \] && \[ ! -f "${AGH_FILE}" \]; then' "${SCRIPT_PATH}" ||
	fail 'DNS environment restore must be gated by WAN install mode'
grep -q 'configure_runtime_defaults new-install "${ADGUARD_INSTALL_MODE:-wan}" "${LOCAL_CACHE_SELECTION:-0}"' "${SCRIPT_PATH}" ||
	fail 'runtime defaults must receive install mode before local cache selection'
if grep -q '\[ "$(nvram get sw_mode)" != "1" \].*exit 1' "${SCRIPT_PATH}"; then
	fail 'installer must not hard-exit on non-router sw_mode'
fi

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

ERROR='Error:'

# PTXT prints its arguments as a single line.
PTXT() {
	printf '%s\n' "$*"
}

# run_case executes an install-mode detection test case and fails if the result does not match the expected status or mode.
run_case() {
	case_name="$1"
	sw_value="$2"
	lan_value="$3"
	expected_status="$4"
	expected_mode="$5"

	ADGUARD_INSTALL_MODE=""
	nvram() {
		case "${1:-}:${2:-}" in
			get:sw_mode) printf '%s\n' "${sw_value}" ;;
			get:lan_ipaddr) printf '%s\n' "${lan_value}" ;;
			*) return 1 ;;
		esac
	}

	if adguard_install_mode_detect >/dev/null 2>&1; then
		actual_status="0"
	else
		actual_status="1"
	fi

	if [ "${actual_status}" != "${expected_status}" ]; then
		fail "${case_name}: expected status ${expected_status}, got ${actual_status}"
	fi
	if [ "${ADGUARD_INSTALL_MODE:-}" != "${expected_mode}" ]; then
		fail "${case_name}: expected mode ${expected_mode}, got ${ADGUARD_INSTALL_MODE:-empty}"
	fi
}

run_case router-wan 1 192.168.50.1 0 wan
run_case repeater-lan 2 192.168.50.1 0 lan
run_case ap-lan 3 192.168.50.1 0 lan
run_case media-bridge-lan 4 192.168.50.1 0 lan
run_case unknown-non-router-lan 9 192.168.50.1 0 lan
run_case repeater-without-lan-ip 2 "" 1 ""
run_case ap-with-invalid-lan-ip 3 999.168.50.1 1 ""
run_case ap-with-wildcard-lan-ip 3 0.0.0.0 1 ""
run_case ap-with-loopback-lan-ip 3 127.0.0.1 1 ""
run_case ap-with-multicast-lan-ip 3 224.0.0.1 1 ""
run_case missing-sw-mode-with-lan-ip "" 192.168.50.1 0 lan
run_case missing-sw-mode-without-lan-ip "" "" 1 ""
run_case missing-sw-mode-with-invalid-lan-ip "" 999.168.50.1 1 ""

printf '%s\n' 'PASS: installer install-mode detection accepts LAN pathways'
