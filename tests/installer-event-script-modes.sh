#!/bin/sh
# Verify installer event-script setup remains mode-aware for WAN and LAN paths.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_FILE="${TMPDIR:-/tmp}/installer-event-script-modes.$$"

# cleanup removes temporary extracted files created by the regression check.
cleanup() {
	rm -f "${TMP_FILE}" "${TMP_FILE}.wan" "${TMP_FILE}.lan" "${TMP_FILE}.wan-helper"
}

# fail prints a failure message to standard error and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"

awk '
	/yaml_nvars_file_action delete "#Asuswrt-Merlin AdGuardHome Installer" \/jffs\/scripts\/dnsmasq\.postconf/ {
		armed = 1
		next
	}
	!armed { next }
	/^[[:space:]]*case "\$\{ADGUARD_INSTALL_MODE:-wan\}" in[[:space:]]*$/ {
		in_case = 1
		depth = 1
	}
	in_case {
		print
		if ($0 !~ /^[[:space:]]*case "\$\{ADGUARD_INSTALL_MODE:-wan\}" in[[:space:]]*$/ &&
			$0 ~ /^[[:space:]]*case[[:space:]]/) {
			depth++
		}
		if ($0 ~ /^[[:space:]]*esac[[:space:]]*$/) {
			depth--
			if (depth == 0) exit
		}
	}
' "${SCRIPT_PATH}" >"${TMP_FILE}" ||
	fail 'could not extract event-script mode branch'
[ -s "${TMP_FILE}" ] || fail 'event-script mode branch was not found'

awk -v branch='wan)' '
	$0 ~ "^[[:space:]]*" branch "[[:space:]]*$" { in_branch = 1 }
	in_branch {
		print
		if ($0 ~ /^[[:space:]]*case[[:space:]]/) depth++
		if ($0 ~ /^[[:space:]]*esac[[:space:]]*$/) depth--
		if (depth == 0 && $0 ~ /^[[:space:]]*;;[[:space:]]*$/) exit
	}
' "${TMP_FILE}" >"${TMP_FILE}.wan" ||
	fail 'could not extract WAN event-script branch'
awk -v branch='lan)' '
	$0 ~ "^[[:space:]]*" branch "[[:space:]]*$" { in_branch = 1 }
	in_branch {
		print
		if ($0 ~ /^[[:space:]]*case[[:space:]]/) depth++
		if ($0 ~ /^[[:space:]]*esac[[:space:]]*$/) depth--
		if (depth == 0 && $0 ~ /^[[:space:]]*;;[[:space:]]*$/) exit
	}
' "${TMP_FILE}" >"${TMP_FILE}.lan" ||
	fail 'could not extract LAN event-script branch'
[ -s "${TMP_FILE}.wan" ] || fail 'WAN event-script branch was not found'
[ -s "${TMP_FILE}.lan" ] || fail 'LAN event-script branch was not found'

sed -n '/^install_wan_event_scripts() {$/,/^}$/p' "${SCRIPT_PATH}" >"${TMP_FILE}.wan-helper" ||
	fail 'could not extract WAN event-script helper'
[ -s "${TMP_FILE}.wan-helper" ] || fail 'WAN event-script helper was not found'
grep -q 'install_wan_event_scripts' "${TMP_FILE}.wan" ||
	fail 'WAN branch does not invoke the shared event-script helper'
grep -q 'write_manager_script /jffs/scripts/init-start "init-start &"' "${TMP_FILE}.wan-helper" ||
	fail 'WAN branch does not install init-start'
grep -q 'write_manager_script /jffs/scripts/services-stop "services-stop &"' "${TMP_FILE}.wan-helper" ||
	fail 'WAN branch does not install services-stop'
grep -q 'pidof dnsmasq >/dev/null 2>&1 && \[ -f /etc/dnsmasq.conf \]' "${TMP_FILE}.wan-helper" ||
	fail 'WAN branch does not require running dnsmasq and /etc/dnsmasq.conf'
grep -q 'write_manager_script /jffs/scripts/dnsmasq.postconf dnsmasq' "${TMP_FILE}.wan-helper" ||
	fail 'WAN branch does not install dnsmasq.postconf when dnsmasq is available'
grep -q "write_manager_script /jffs/scripts/firewall-start 'firewall \"\$1\"'" "${TMP_FILE}.wan-helper" ||
	fail 'WAN branch does not install firewall-start'
grep -q "write_manager_script /jffs/scripts/dnsmasq-sdn.postconf 'dnsmasq-sdn \$2'" "${TMP_FILE}.wan-helper" ||
	fail 'WAN branch does not install dnsmasq-sdn.postconf when supported'
grep -q "write_conf ADGUARD_DNSMASQ_MODE '\"enabled\"'" "${TMP_FILE}.wan-helper" ||
	fail 'WAN branch does not persist enabled dnsmasq mode'

grep -q 'write_manager_script /jffs/scripts/init-start "init-start &"' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not install init-start'
grep -q 'write_manager_script /jffs/scripts/services-stop "services-stop &"' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not install services-stop'
grep -q 'if wan_iptables_state_active; then' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not gate firewall-start on active WAN IPTABLES state'
grep -q 'write_manager_script /jffs/scripts/firewall-start' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not install firewall-start for an active WAN IPTABLES state'
grep -q 'del_jffs_script /jffs/scripts/firewall-start' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not remove the installer-managed firewall-start hook without WAN IPTABLES state'
grep -q 'pidof dnsmasq >/dev/null 2>&1 && \[ -f /etc/dnsmasq.conf \]' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not require running dnsmasq and /etc/dnsmasq.conf'
grep -q 'write_manager_script /jffs/scripts/dnsmasq.postconf dnsmasq' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not install dnsmasq.postconf when dnsmasq is running'
grep -q "write_manager_script /jffs/scripts/dnsmasq-sdn.postconf 'dnsmasq-sdn \$2'" "${TMP_FILE}.lan" ||
	fail 'LAN branch does not install dnsmasq-sdn.postconf when needed and supported'
grep -q 'del_jffs_script /jffs/scripts/dnsmasq.postconf dnsmasq' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not remove only the installer-managed dnsmasq.postconf hook when dnsmasq is stopped'
grep -q 'del_jffs_script /jffs/scripts/dnsmasq-sdn.postconf' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not remove the installer-managed SDN dnsmasq hook when dnsmasq is stopped'
grep -q '\[ "${ADGUARD_DNSMASQ_MODE:-$(conf_value ADGUARD_DNSMASQ_MODE 2>/dev/null)}" = "disabled" \]' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not preserve disabled dnsmasq mode before checking runtime state'
disabled_line="$(grep -n '\[ "${ADGUARD_DNSMASQ_MODE:-$(conf_value ADGUARD_DNSMASQ_MODE 2>/dev/null)}" = "disabled" \]' "${TMP_FILE}.lan" | head -n 1 | cut -d: -f1)"
pid_line="$(grep -n 'pidof dnsmasq >/dev/null 2>&1' "${TMP_FILE}.lan" | head -n 1 | cut -d: -f1)"
[ "${disabled_line}" -lt "${pid_line}" ] || fail 'LAN branch checks runtime dnsmasq state before preserving disabled mode'
grep -q 'ptxt_warn "dnsmasq is not running or /etc/dnsmasq.conf is unavailable; removing AdGuardHome dnsmasq event hooks."' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not report unavailable dnsmasq before removing hooks'
grep -q 'write_conf ADGUARD_DNSMASQ_MODE "\\"enabled\\""' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not persist enabled dnsmasq mode'
grep -q 'write_conf ADGUARD_DNSMASQ_MODE "\\"disabled\\""' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not persist disabled dnsmasq mode'

printf '%s\n' 'PASS: installer event-script mode regression'
