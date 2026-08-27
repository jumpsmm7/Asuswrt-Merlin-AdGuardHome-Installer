#!/bin/sh
# Verify installer event-script setup remains mode-aware for WAN and LAN paths.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_FILE="${TMPDIR:-/tmp}/installer-event-script-modes.$$"

# cleanup removes temporary extracted files created by the regression check.
cleanup() {
	rm -rf "${TMP_FILE}" "${TMP_FILE}.wan" "${TMP_FILE}.lan" "${TMP_FILE}.wan-helper" "${TMP_FILE}.remove-helper" "${TMP_FILE}.snapshot-helper" "${TMP_FILE}.restore-helper" "${TMP_FILE}.add-helper" "${TMP_FILE}.services-helper" "${TMP_FILE}.rollback"
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
sed -n '/^remove_dnsmasq_event_scripts() {$/,/^}$/p' "${SCRIPT_PATH}" >"${TMP_FILE}.remove-helper" ||
	fail 'could not extract dnsmasq event-script removal helper'
[ -s "${TMP_FILE}.remove-helper" ] || fail 'dnsmasq event-script removal helper was not found'
sed -n '/^dnsmasq_event_scripts_snapshot() {$/,/^}$/p' "${SCRIPT_PATH}" >"${TMP_FILE}.snapshot-helper" ||
	fail 'could not extract dnsmasq event-script snapshot helper'
[ -s "${TMP_FILE}.snapshot-helper" ] || fail 'dnsmasq event-script snapshot helper was not found'
sed -n '/^dnsmasq_event_scripts_restore() {$/,/^}$/p' "${SCRIPT_PATH}" >"${TMP_FILE}.restore-helper" ||
	fail 'could not extract dnsmasq event-script restore helper'
[ -s "${TMP_FILE}.restore-helper" ] || fail 'dnsmasq event-script restore helper was not found'
sed -n '/^add_dnsmasq_event_scripts() {$/,/^}$/p' "${SCRIPT_PATH}" >"${TMP_FILE}.add-helper" ||
	fail 'could not extract dnsmasq event-script addition helper'
[ -s "${TMP_FILE}.add-helper" ] || fail 'dnsmasq event-script addition helper was not found'
for helper in \
	add_init_event_scripts remove_init_event_scripts init_event_scripts_snapshot \
	add_services_event_scripts remove_services_event_scripts services_event_scripts_snapshot \
	add_firewall_event_scripts remove_firewall_event_scripts firewall_event_scripts_snapshot; do
	grep -q "^${helper}() {$" "${SCRIPT_PATH}" || fail "event-script transaction helper was not found: ${helper}"
done
sed -n '/^add_services_event_scripts() {$/,/^}$/p' "${SCRIPT_PATH}" >"${TMP_FILE}.services-helper" ||
	fail 'could not extract services event-script addition helper'
grep -q 'write_manager_script /jffs/scripts/services-stop "services-stop &"' "${TMP_FILE}.services-helper" ||
	fail 'services transaction does not publish services-stop'
grep -q 'write_command_script /jffs/scripts/service-event-end' "${TMP_FILE}.services-helper" ||
	fail 'services transaction does not publish service-event-end'
grep -q 'services_event_scripts_restore "${SNAPSHOT_DIR}"' "${TMP_FILE}.services-helper" ||
	fail 'services transaction does not restore both hooks after publication failure'
grep -q 'install_wan_event_scripts' "${TMP_FILE}.wan" ||
	fail 'WAN branch does not invoke the shared event-script helper'
grep -q 'all_event_scripts_snapshot "${SNAPSHOT_DIR}" || return 1' "${TMP_FILE}.wan-helper" ||
	fail 'WAN branch does not snapshot all hooks before publication'
grep -q 'add_init_event_scripts || failed=1' "${TMP_FILE}.wan-helper" ||
	fail 'WAN branch does not transactionally install init-start'
grep -q 'add_services_event_scripts || failed=1' "${TMP_FILE}.wan-helper" ||
	fail 'WAN branch does not transactionally install service hooks'
grep -q 'all_event_scripts_restore "${SNAPSHOT_DIR}"' "${TMP_FILE}.wan-helper" ||
	fail 'WAN branch does not restore the aggregate hook snapshot after failure'
grep -q 'pidof dnsmasq >/dev/null 2>&1 || \[ ! -f /etc/dnsmasq.conf \]' "${TMP_FILE}.add-helper" ||
	fail 'WAN branch does not require running dnsmasq and /etc/dnsmasq.conf'
grep -q 'write_manager_script /jffs/scripts/dnsmasq.postconf dnsmasq' "${TMP_FILE}.add-helper" ||
	fail 'WAN branch does not install dnsmasq.postconf when dnsmasq is available'
grep -q 'add_firewall_event_scripts || failed=1' "${TMP_FILE}.wan-helper" ||
	fail 'WAN branch does not transactionally install firewall-start'
grep -q "write_manager_script /jffs/scripts/dnsmasq-sdn.postconf 'dnsmasq-sdn \$2'" "${TMP_FILE}.add-helper" ||
	fail 'WAN branch does not install dnsmasq-sdn.postconf when supported'
grep -q "write_conf ADGUARD_DNSMASQ_MODE '\"enabled\"'" "${TMP_FILE}.add-helper" ||
	fail 'WAN branch does not persist enabled dnsmasq mode'
grep -q 'dnsmasq_event_scripts_snapshot "${SNAPSHOT_DIR}" || {' "${TMP_FILE}.add-helper" ||
	fail 'dnsmasq hook addition does not snapshot managed state before publication'
grep -q 'dnsmasq_event_scripts_restore "${SNAPSHOT_DIR}"' "${TMP_FILE}.add-helper" ||
	fail 'dnsmasq hook addition does not restore managed state after publication failure'

grep -q 'add_init_event_scripts' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not transactionally install init-start'
grep -q 'all_event_scripts_snapshot "${EVENT_SCRIPTS_SNAPSHOT_DIR}"' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not snapshot all managed hooks before publication'
grep -q 'all_event_scripts_restore "${EVENT_SCRIPTS_SNAPSHOT_DIR}"' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not restore the aggregate hook snapshot after failure'
grep -q 'add_services_event_scripts' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not transactionally install service hooks'
grep -q 'if wan_iptables_state_active; then' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not gate firewall-start on active WAN IPTABLES state'
grep -q 'add_firewall_event_scripts' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not transactionally install firewall-start for an active WAN IPTABLES state'
grep -q 'remove_firewall_event_scripts' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not transactionally remove firewall-start without WAN IPTABLES state'
grep -q 'add_dnsmasq_event_scripts' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not use the shared dnsmasq hook addition helper'
grep -q 'remove_dnsmasq_event_scripts' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not remove only the installer-managed dnsmasq.postconf hook when dnsmasq is stopped'
grep -q '{ del_jffs_script /jffs/scripts/dnsmasq.postconf dnsmasq >/dev/null 2>&1; } || failed=1' "${TMP_FILE}.remove-helper" ||
	fail 'dnsmasq hook cleanup does not propagate primary hook removal failures'
grep -q "{ del_jffs_script /jffs/scripts/dnsmasq-sdn.postconf 'dnsmasq-sdn \$2' >/dev/null 2>&1; } || failed=1" "${TMP_FILE}.remove-helper" ||
	fail 'LAN branch does not remove the installer-managed SDN dnsmasq hook when dnsmasq is stopped'
if grep -q "nvram get rc_support.*mtlancfg" "${TMP_FILE}.remove-helper"; then
	fail 'dnsmasq hook cleanup still gates SDN hook removal on current firmware capability'
fi
if grep -q 'else' "${TMP_FILE}.add-helper"; then
	fail 'dnsmasq hook addition manages the SDN hook when current firmware lacks the capability'
fi
wan_cleanup_line="$(grep -n 'add_dnsmasq_event_scripts || failed=1' "${TMP_FILE}.wan-helper" | head -n 1 | cut -d: -f1)"
wan_publish_line="$(grep -n 'add_init_event_scripts' "${TMP_FILE}.wan-helper" | head -n 1 | cut -d: -f1)"
[ "${wan_cleanup_line}" -lt "${wan_publish_line}" ] || fail 'WAN branch publishes JFFS hooks before dnsmasq cleanup can fail'
lan_cleanup_line="$(grep -n 'if ! remove_dnsmasq_event_scripts' "${TMP_FILE}.lan" | head -n 1 | cut -d: -f1)"
lan_publish_line="$(grep -n 'add_firewall_event_scripts' "${TMP_FILE}.lan" | head -n 1 | cut -d: -f1)"
[ "${lan_cleanup_line}" -lt "${lan_publish_line}" ] || fail 'LAN branch publishes JFFS hooks before dnsmasq cleanup can fail'
grep -q 'if ! remove_firewall_event_scripts' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not abort when transactional firewall-hook removal fails'
grep -q "if ! write_conf ADGUARD_IPSET '\"NO\"'" "${TMP_FILE}.lan" ||
	fail 'LAN branch does not persist disabled IPSET state after WAN IPTABLES state is lost'
if grep -q 'Unable to remove.*continuing LAN-mode setup' "${TMP_FILE}.lan"; then
	fail 'LAN branch still downgrades required hook-removal failures to warnings'
fi
grep -q '\[ "${ADGUARD_DNSMASQ_MODE:-$(conf_value ADGUARD_DNSMASQ_MODE 2>/dev/null)}" = "disabled" \]' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not preserve disabled dnsmasq mode before checking runtime state'
disabled_line="$(grep -n '\[ "${ADGUARD_DNSMASQ_MODE:-$(conf_value ADGUARD_DNSMASQ_MODE 2>/dev/null)}" = "disabled" \]' "${TMP_FILE}.lan" | head -n 1 | cut -d: -f1)"
pid_line="$(grep -n 'pidof dnsmasq >/dev/null 2>&1' "${TMP_FILE}.lan" | head -n 1 | cut -d: -f1)"
[ "${disabled_line}" -lt "${pid_line}" ] || fail 'LAN branch checks runtime dnsmasq state before preserving disabled mode'
grep -q 'ptxt_warn "dnsmasq is not running or /etc/dnsmasq.conf is unavailable; removing AdGuardHome dnsmasq event hooks."' "${TMP_FILE}.lan" ||
	fail 'LAN branch does not report unavailable dnsmasq before removing hooks'
grep -q "write_conf ADGUARD_DNSMASQ_MODE '\"enabled\"'" "${TMP_FILE}.add-helper" ||
	fail 'shared addition helper does not persist enabled dnsmasq mode'
grep -q "write_conf ADGUARD_DNSMASQ_MODE '\"disabled\"'" "${TMP_FILE}.remove-helper" ||
	fail 'shared removal helper does not persist disabled dnsmasq mode'
(
	REMOVE_ROOT="${TMP_FILE}.remove"
	mkdir -p "${REMOVE_ROOT}/jffs/scripts" "${REMOVE_ROOT}/base"
	printf '%s\n' 'original primary hook' >"${REMOVE_ROOT}/jffs/scripts/dnsmasq.postconf"
	printf '%s\n' 'original SDN hook' >"${REMOVE_ROOT}/jffs/scripts/dnsmasq-sdn.postconf"
	printf '%s\n' 'ADGUARD_DNSMASQ_MODE="enabled"' >"${REMOVE_ROOT}/config"
	cat "${TMP_FILE}.snapshot-helper" "${TMP_FILE}.restore-helper" "${TMP_FILE}.remove-helper" |
		sed "s|/jffs/scripts|${REMOVE_ROOT}/jffs/scripts|g" >"${REMOVE_ROOT}/helpers"
	. "${REMOVE_ROOT}/helpers"
	BASE_DIR="${REMOVE_ROOT}/base"
	CONF_FILE="${REMOVE_ROOT}/config"
	remove_calls=0
	del_jffs_script() {
		remove_calls="$((remove_calls + 1))"
		if [ "${remove_calls}" -eq 1 ]; then
			printf '%s\n' 'changed primary hook' >"$1"
			return 0
		fi
		return 1
	}
	write_conf() { fail 'disabled mode was written after a hook removal failed'; }
	if remove_dnsmasq_event_scripts; then
		fail 'dnsmasq hook cleanup hides SDN hook removal failures'
	fi
	[ "${remove_calls}" -eq 2 ] || fail 'dnsmasq hook cleanup did not attempt both hook removals'
	grep -qx 'original primary hook' "${REMOVE_ROOT}/jffs/scripts/dnsmasq.postconf" ||
		fail 'dnsmasq hook cleanup did not restore the primary hook after a removal failure'
	grep -qx 'original SDN hook' "${REMOVE_ROOT}/jffs/scripts/dnsmasq-sdn.postconf" ||
		fail 'dnsmasq hook cleanup did not restore the SDN hook after a removal failure'
	grep -qx 'ADGUARD_DNSMASQ_MODE="enabled"' "${CONF_FILE}" ||
		fail 'dnsmasq hook cleanup changed the mode after a removal failure'
	del_jffs_script() { return 0; }
	write_conf() { return 1; }
	if remove_dnsmasq_event_scripts; then
		fail 'dnsmasq hook cleanup hides disabled-mode configuration write failures'
	fi
	grep -qx 'original primary hook' "${REMOVE_ROOT}/jffs/scripts/dnsmasq.postconf" ||
		fail 'dnsmasq hook cleanup did not restore the primary hook after a configuration failure'
	grep -qx 'original SDN hook' "${REMOVE_ROOT}/jffs/scripts/dnsmasq-sdn.postconf" ||
		fail 'dnsmasq hook cleanup did not restore the SDN hook after a configuration failure'
	grep -qx 'ADGUARD_DNSMASQ_MODE="enabled"' "${CONF_FILE}" ||
		fail 'dnsmasq hook cleanup did not restore the enabled mode after a configuration failure'
) || fail 'dnsmasq hook removal rollback checks failed'

(
	ROLLBACK_ROOT="${TMP_FILE}.rollback"
	mkdir -p "${ROLLBACK_ROOT}/jffs/scripts" "${ROLLBACK_ROOT}/base"
	printf '%s\n' 'original primary hook' >"${ROLLBACK_ROOT}/jffs/scripts/dnsmasq.postconf"
	printf '%s\n' 'original SDN hook' >"${ROLLBACK_ROOT}/jffs/scripts/dnsmasq-sdn.postconf"
	printf '%s\n' 'ADGUARD_DNSMASQ_MODE="disabled"' >"${ROLLBACK_ROOT}/config"
	cat "${TMP_FILE}.snapshot-helper" "${TMP_FILE}.restore-helper" "${TMP_FILE}.add-helper" |
		sed "s|/jffs/scripts|${ROLLBACK_ROOT}/jffs/scripts|g; s|/etc/dnsmasq.conf|${ROLLBACK_ROOT}/dnsmasq.conf|g" >"${ROLLBACK_ROOT}/helpers"
	. "${ROLLBACK_ROOT}/helpers"
	BASE_DIR="${ROLLBACK_ROOT}/base"
	CONF_FILE="${ROLLBACK_ROOT}/config"
	: >"${ROLLBACK_ROOT}/dnsmasq.conf"
	pidof() { return 0; }
	nvram() { printf '%s\n' 'mtlancfg'; }
	write_manager_script() {
		if [ "$1" = "${ROLLBACK_ROOT}/jffs/scripts/dnsmasq-sdn.postconf" ]; then
			return 1
		fi
		printf '%s\n' 'changed primary hook' >"$1"
	}
	write_conf() {
		printf '%s\n' 'ADGUARD_DNSMASQ_MODE="enabled"' >"${CONF_FILE}"
	}
	if add_dnsmasq_event_scripts; then
		fail 'dnsmasq hook addition hides SDN publication failure'
	fi
	grep -qx 'original primary hook' "${ROLLBACK_ROOT}/jffs/scripts/dnsmasq.postconf" ||
		fail 'dnsmasq hook addition did not restore the primary hook'
	grep -qx 'original SDN hook' "${ROLLBACK_ROOT}/jffs/scripts/dnsmasq-sdn.postconf" ||
		fail 'dnsmasq hook addition did not restore the SDN hook'
	grep -qx 'ADGUARD_DNSMASQ_MODE="disabled"' "${CONF_FILE}" ||
		fail 'dnsmasq hook addition did not restore the dnsmasq mode'
	write_manager_script() {
		printf '%s\n' 'changed managed hook' >"$1"
	}
	write_conf() {
		printf '%s\n' 'ADGUARD_DNSMASQ_MODE="enabled"' >"${CONF_FILE}"
		return 1
	}
	if add_dnsmasq_event_scripts; then
		fail 'dnsmasq hook addition hides enabled-mode configuration write failure'
	fi
	grep -qx 'original primary hook' "${ROLLBACK_ROOT}/jffs/scripts/dnsmasq.postconf" ||
		fail 'configuration write failure did not restore the primary hook'
	grep -qx 'original SDN hook' "${ROLLBACK_ROOT}/jffs/scripts/dnsmasq-sdn.postconf" ||
		fail 'configuration write failure did not restore the SDN hook'
	grep -qx 'ADGUARD_DNSMASQ_MODE="disabled"' "${CONF_FILE}" ||
		fail 'configuration write failure did not restore the dnsmasq mode'
)

(
	LAN_ROLLBACK_ROOT="${TMP_FILE}.lan-rollback"
	mkdir -p "${LAN_ROLLBACK_ROOT}/jffs/scripts" "${LAN_ROLLBACK_ROOT}/base"
	for hook in dnsmasq.postconf dnsmasq-sdn.postconf init-start services-stop service-event-end firewall-start; do
		printf '%s\n' "original ${hook}" >"${LAN_ROLLBACK_ROOT}/jffs/scripts/${hook}"
	done
	CONF_FILE="${LAN_ROLLBACK_ROOT}/config"
	printf '%s\n' 'ADGUARD_DNSMASQ_MODE="disabled"' >"${CONF_FILE}"
	sed -n '/^event_scripts_snapshot() {$/,/^init_event_scripts_snapshot() {$/p' "${SCRIPT_PATH}" |
		sed '$d' >"${LAN_ROLLBACK_ROOT}/helpers.part"
	sed "s|/jffs/scripts|${LAN_ROLLBACK_ROOT}/jffs/scripts|g" "${LAN_ROLLBACK_ROOT}/helpers.part" >"${LAN_ROLLBACK_ROOT}/helpers"
	. "${LAN_ROLLBACK_ROOT}/helpers"
	SNAPSHOT_DIR="${LAN_ROLLBACK_ROOT}/base/snapshot"
	all_event_scripts_snapshot "${SNAPSHOT_DIR}" || fail 'LAN aggregate hook snapshot failed'
	printf '%s\n' 'changed dnsmasq hook' >"${LAN_ROLLBACK_ROOT}/jffs/scripts/dnsmasq.postconf"
	printf '%s\n' 'changed firewall hook' >"${LAN_ROLLBACK_ROOT}/jffs/scripts/firewall-start"
	printf '%s\n' 'ADGUARD_DNSMASQ_MODE="enabled"' >"${CONF_FILE}"
	all_event_scripts_restore "${SNAPSHOT_DIR}" || fail 'LAN aggregate hook rollback failed'
	grep -qx 'original dnsmasq.postconf' "${LAN_ROLLBACK_ROOT}/jffs/scripts/dnsmasq.postconf" ||
		fail 'LAN rollback did not restore an earlier dnsmasq publication'
	grep -qx 'original firewall-start' "${LAN_ROLLBACK_ROOT}/jffs/scripts/firewall-start" ||
		fail 'LAN rollback did not restore the failed firewall publication'
	grep -qx 'ADGUARD_DNSMASQ_MODE="disabled"' "${CONF_FILE}" ||
		fail 'LAN rollback did not restore the dnsmasq configuration'
) || fail 'LAN aggregate hook rollback checks failed'

printf '%s\n' 'PASS: installer event-script mode regression'
