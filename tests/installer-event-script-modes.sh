#!/bin/sh
# Verify installer event-script setup remains mode-aware for WAN and LAN paths.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_FILE="${TMPDIR:-/tmp}/installer-event-script-modes.$$"

cleanup() {
	rm -f "${TMP_FILE}" "${TMP_FILE}.wan" "${TMP_FILE}.lan"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"

sed -n '/case "${ADGUARD_INSTALL_MODE:-wan}" in/,/^[[:space:]]*esac$/p' "${SCRIPT_PATH}" >"${TMP_FILE}" ||
	fail 'could not extract event-script mode branch'
[ -s "${TMP_FILE}" ] || fail 'event-script mode branch was not found'

awk '
	/^[[:space:]]*wan\)/ { in_branch = 1; indent = $0; sub(/wan\).*/, "", indent) }
	in_branch { print; if ($0 ~ "^" indent ";;[[:space:]]*$") exit }
' "${TMP_FILE}" >"${TMP_FILE}.wan" ||
	fail 'could not extract WAN event-script branch'
awk '
	/^[[:space:]]*lan\)/ { in_branch = 1; indent = $0; sub(/lan\).*/, "", indent) }
	in_branch { print; if ($0 ~ "^" indent ";;[[:space:]]*$") exit }
' "${TMP_FILE}" >"${TMP_FILE}.lan" ||
	fail 'could not extract LAN event-script branch'
[ -s "${TMP_FILE}.wan" ] || fail 'WAN event-script branch was not found'
[ -s "${TMP_FILE}.lan" ] || fail 'LAN event-script branch was not found'

grep -q 'write_manager_script /jffs/scripts/init-start "init-start &"' "${TMP_FILE}.wan" ||
	fail 'WAN branch does not install init-start'
grep -q 'write_manager_script /jffs/scripts/services-stop "services-stop &"' "${TMP_FILE}.wan" ||
	fail 'WAN branch does not install services-stop'
grep -q 'write_manager_script /jffs/scripts/dnsmasq.postconf dnsmasq' "${TMP_FILE}.wan" ||
	fail 'WAN branch does not install dnsmasq.postconf'
grep -q "write_manager_script /jffs/scripts/firewall-start 'firewall \"\$1\"'" "${TMP_FILE}.wan" ||
	fail 'WAN branch does not install firewall-start'
grep -q "write_manager_script /jffs/scripts/dnsmasq-sdn.postconf 'dnsmasq-sdn \$2'" "${TMP_FILE}.wan" ||
	fail 'WAN branch does not install dnsmasq-sdn.postconf when supported'
grep -q 'write_conf ADGUARD_DNSMASQ_MODE "\\"enabled\\""' "${TMP_FILE}.wan" ||
	fail 'WAN branch does not persist enabled dnsmasq mode'

grep -q 'write_manager_script /jffs/scripts/init-start "init-start &"' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not install init-start'
grep -q 'write_manager_script /jffs/scripts/services-stop "services-stop &"' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not install services-stop'
if grep -q 'write_manager_script /jffs/scripts/firewall-start' "${TMP_FILE}.lan"; then
	fail 'LAN branch installs firewall-start'
fi
grep -q 'pidof dnsmasq >/dev/null 2>&1' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not check whether dnsmasq is running'
grep -q 'write_manager_script /jffs/scripts/dnsmasq.postconf dnsmasq' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not install dnsmasq.postconf when dnsmasq is running'
grep -q "write_manager_script /jffs/scripts/dnsmasq-sdn.postconf 'dnsmasq-sdn \$2'" "${TMP_FILE}.lan" ||
	fail 'LAN branch does not install dnsmasq-sdn.postconf when needed and supported'
grep -q 'del_jffs_script /jffs/scripts/dnsmasq.postconf dnsmasq' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not remove only the installer-managed dnsmasq.postconf hook when dnsmasq is stopped'
grep -q 'del_jffs_script /jffs/scripts/dnsmasq-sdn.postconf' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not remove the installer-managed SDN dnsmasq hook when dnsmasq is stopped'
grep -q 'case "${ADGUARD_DNSMASQ_MODE:-$(conf_value ADGUARD_DNSMASQ_MODE 2>/dev/null)}" in' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not read persisted dnsmasq mode before handling stopped dnsmasq'
grep -q 'ptxt_warn "dnsmasq is not running; preserving dnsmasq event hooks for LAN-mode startup."' "${TMP_FILE}.lan" ||
	fail 'LAN branch extraction does not include transient stopped-dnsmasq path'
grep -q 'write_conf ADGUARD_DNSMASQ_MODE "\\"enabled\\""' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not persist enabled dnsmasq mode'
grep -q 'write_conf ADGUARD_DNSMASQ_MODE "\\"disabled\\""' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not persist disabled dnsmasq mode'

printf '%s\n' 'PASS: installer event-script mode regression'
