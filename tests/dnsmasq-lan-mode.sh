#!/bin/sh
# Verify dnsmasq postconf LAN-mode gating preserves handoff and topology-aware IPSET refreshes.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dnsmasq-lan-mode.XXXXXX")" || {
	printf '%s\n' 'FAIL: could not create exclusive test directory' >&2
	exit 1
}
IPSET_TEST_LOCK_DIR="${TEST_ROOT}/ipset-transaction-lock"
FUNCTIONS_FILE="${TEST_ROOT}/functions"
LOG_FILE="${TEST_ROOT}/log"
IPSET_CALLS_FILE="${TEST_ROOT}/ipset-calls"
MANAGED_IPSET_FILE="${TEST_ROOT}/managed-ipset"
YAML_FILE="${TEST_ROOT}/AdGuardHome.yaml"
UMOUNT_CALLS_FILE="${TEST_ROOT}/umount-calls"
DNSMASQ_CONF_FILE="${TEST_ROOT}/dnsmasq.conf"
DNSMASQ_SDN_CONF_FILE="${TEST_ROOT}/dnsmasq-1.conf"
BRIDGE_FALLBACK_CALLS_FILE="${TEST_ROOT}/bridge-fallback-calls"
MOUNT_CALLS_FILE="${TEST_ROOT}/mount-calls"
first_pid=""
second_pid=""

# cleanup stops background workers before removing the test sandbox.
cleanup() {
	for worker_pid in "${first_pid:-}" "${second_pid:-}"; do
		[ -n "${worker_pid}" ] || continue
		if kill -0 "${worker_pid}" 2>/dev/null; then
			kill "${worker_pid}" 2>/dev/null || true
		fi
		wait "${worker_pid}" 2>/dev/null || true
	done
	rm -rf "${TEST_ROOT}"
}

# fail prints a failure message to standard error and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

[ -f "${SCRIPT_PATH}" ] || fail "script not found: ${SCRIPT_PATH}"

sed -n '/^dnsmasq_delete_matching() {$/,/^interface_ipv4_addr() {$/p' "${SCRIPT_PATH}" | sed '$d' >"${FUNCTIONS_FILE}" ||
	fail 'could not extract dnsmasq helpers'
[ -s "${FUNCTIONS_FILE}" ] || fail 'dnsmasq helper extraction was empty'
# Keep the extracted postconf helper inside the test sandbox instead of touching router paths.
sed -i \
	-e 's|CONFIG="/etc/dnsmasq.conf"|CONFIG="${DNSMASQ_CONF_FILE}"|' \
	-e 's|CONFIG="/etc/dnsmasq-${1}.conf"|CONFIG="${DNSMASQ_SDN_CONF_FILE}"|' \
	"${FUNCTIONS_FILE}" || fail 'could not sandbox dnsmasq config paths'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

PROCS='AdGuardHome'
DNS_HANDOFF_ACTIVE='0'
ADGUARD_INSTALL_MODE='wan'
DNSMASQ_RUNNING='0'
ADGUARD_RUNNING='1'
ADGUARD_DNSMASQ_MODE='auto'
CONFIG_DNSMASQ_MODE="${ADGUARD_DNSMASQ_MODE}"
WORK_DIR="${TEST_ROOT}"
IPSET_FILE="${MANAGED_IPSET_FILE}"
RESOLV_CONF_USES_ROM='1'
RESOLV_CONF_TMP_MOUNT='0'

# pidof reports fixture process state without relying on PATH interception.
# pidof reports fixture process IDs for dnsmasq and AdGuardHome based on their running-state flags.
pidof() {
	case "$1" in
		dnsmasq)
			[ "${DNSMASQ_RUNNING:-0}" = "1" ] && printf '%s\n' 111
			;;
		AdGuardHome)
			[ "${ADGUARD_RUNNING:-0}" = "1" ] && printf '%s\n' 222
			;;
	esac
}

# agh_log appends a colon-delimited log entry with a tag, timestamp, and message to the test log file.
agh_log() {
	printf '%s:%s:%s\n' "$1" "$2" "$3" >>"${LOG_FILE}"
}

# adguard_lan_mode reports whether AdGuard Home is configured in LAN mode.
adguard_lan_mode() {
	[ "${ADGUARD_INSTALL_MODE}" = 'lan' ]
}

# adguard_dnsmasq_running determines whether the dnsmasq process is running.
adguard_dnsmasq_running() {
	pidof dnsmasq >/dev/null 2>&1
}

# adguard_dnsmasq_managed determines whether dnsmasq is managed by AdGuard Home or currently running.
adguard_dnsmasq_managed() {
	case "$(conf_value ADGUARD_DNSMASQ_MODE 2>/dev/null)" in
		disabled) return 1 ;;
		enabled) return 0 ;;
	esac
	adguard_dnsmasq_running
}

# resolv_conf_uses_rom determines whether resolv.conf uses the ROM configuration.
resolv_conf_uses_rom() {
	[ "${RESOLV_CONF_USES_ROM}" = '1' ]
}

# resolv_conf_is_tmp_mount determines whether resolv.conf is mounted from a temporary filesystem.
resolv_conf_is_tmp_mount() {
	[ "${RESOLV_CONF_TMP_MOUNT}" = '1' ]
}

# umount records cleanup requests without relying on PATH interception. BusyBox
# umount records the path requested for unmounting.
umount() {
	printf '%s\n' "$1" >>"${UMOUNT_CALLS_FILE}"
}

# mount records a resolver bind request and reports whether the simulated mount succeeds.
mount() {
	printf '%s\n' "$*" >>"${MOUNT_CALLS_FILE}"
	[ "${MOUNT_FAIL:-0}" != "1" ]
}

# dns_handoff_is_active determines whether DNS handoff is active.
dns_handoff_is_active() {
	[ "${DNS_HANDOFF_ACTIVE}" = '1' ]
}

# conf_value prints the configured value for a supported configuration key and fails for unknown keys.
conf_value() {
	case "$1" in
		ADGUARD_LOCAL) printf '%s\n' 'NO' ;;
		ADGUARD_DNSMASQ_MODE) printf '%s\n' "${ADGUARD_DNSMASQ_MODE}" ;;
		*) return 1 ;;
	esac
}

# nvram returns the mocked value for a supported key when called with the `get` operation.
nvram() {
	[ "$1" = 'get' ] || return 1
	case "$2" in
		rc_support) printf '%s\n' "${NVRAM_RC_SUPPORT:-mtlancfg}" ;;
		lan_ifname) printf '%s\n' "${NVRAM_LAN_IFNAME:-br0}" ;;
		lan_ipaddr) printf '%s\n' '192.168.50.1' ;;
		ipv6_rtr_addr) printf '%s\n' 'fd00::1' ;;
		*) return 1 ;;
	esac
}

# interface_ipv4_addr prints the IPv4 address assigned to a supported bridge interface.
interface_ipv4_addr() {
	case "$1" in
		br0) printf '%s\n' '192.168.50.1' ;;
		br1) printf '%s\n' '192.168.101.1' ;;
		*) return 1 ;;
	esac
}

# interface_ipv6_addr prints the IPv6 address assigned to a supported bridge interface.
interface_ipv6_addr() {
	case "$1" in
		br0) printf '%s\n' 'fd00::1' ;;
		br1) printf '%s\n' 'fd00:101::1' ;;
		*) return 1 ;;
	esac
}

# ipv4_reverse_zone prints the IPv4 reverse DNS zone for 192.168.50.0/24.
ipv4_reverse_zone() {
	printf '%s\n' "50.168.192.in-addr.arpa"
}

# ipv6_reverse_zone prints the IPv6 reverse DNS lookup zone.
ipv6_reverse_zone() {
	printf '%s\n' "1.0.0.0.ip6.arpa"
}

# sdn_bridge_for_index prints the bridge name associated with a supported SDN index.
# sdn_bridge_for_index returns the bridge associated with SDN index 1 and fails for other indexes.
sdn_bridge_for_index() {
	[ "$1" = '1' ] || return 1
	printf '%s\n' 'br1'
}

# IPSet_Refresh records a refresh request, updates refresh state, and removes managed IPSET state when the topology does not support it.
IPSet_Refresh() {
	[ "${IPSET_LOCK_ACTIVE:-0}" = "1" ] || fail 'IPSET refresh ran outside the transaction lock'
	[ -d "${IPSET_SNAPSHOT_DIR:-}" ] || fail 'IPSET refresh ran before the transaction snapshot'
	printf '%s\n' "$1" >>"${IPSET_CALLS_FILE}"
	if [ "${IPSET_REFRESH_FAIL:-0}" = "1" ]; then
		printf '%s\n' refreshed >"${IPSET_FILE}"
		printf '%s\n' refreshed >"${YAML_FILE}"
		return 1
	fi
	if [ "${IPSET_REFRESH_CHANGE:-0}" = "1" ]; then
		printf '%s\n' refreshed >"${IPSET_FILE}"
		printf '%s\n' refreshed >"${YAML_FILE}"
	fi
	case "${ADGUARD_INSTALL_MODE:-}" in
		wan) ;;
		lan | ap | bridge)
			if [ "${WAN_NAT_ACTIVE:-0}" != "1" ]; then
				rm -f "${MANAGED_IPSET_FILE}"
				return 0
			fi
			;;
		*)
			rm -f "${MANAGED_IPSET_FILE}"
			return 0
			;;
	esac
	return 0
}

# IPSet_Lock serializes callback execution with a filesystem lock and returns the callback status or cleanup failure status.
IPSet_Lock() {
	local cleanup_status exit_trap_active lock_attempts status
	if [ "${IPSET_LOCK_ACTIVE:-0}" = "1" ]; then
		"$@"
		return "$?"
	fi
	lock_attempts="0"
	while ! mkdir "${IPSET_TEST_LOCK_DIR}" 2>/dev/null; do
		[ -z "${IPSET_LOCK_WAIT_MARKER:-}" ] || : >"${IPSET_LOCK_WAIT_MARKER}" || return 1
		lock_attempts="$((lock_attempts + 1))"
		if [ "${lock_attempts}" -ge 10 ]; then
			printf '%s\n' 'FAIL: fixture transaction lock was not released' >&2
			return 1
		fi
		sleep 1
	done
	exit_trap_active=$(trap | sed -n '/ EXIT$/p')
	trap 'rmdir "${IPSET_TEST_LOCK_DIR}" 2>/dev/null' EXIT
	IPSET_LOCK_ACTIVE="1"
	"$@"
	status="$?"
	IPSET_LOCK_ACTIVE="0"
	cleanup_status="0"
	rmdir "${IPSET_TEST_LOCK_DIR}" || cleanup_status="1"
	trap - EXIT
	[ -z "${exit_trap_active}" ] || eval "${exit_trap_active}"
	[ "${status}" -eq 0 ] || return "${status}"
	[ "${cleanup_status}" -eq 0 ] || return "${cleanup_status}"
	return "${status}"
}

# lower_script records successful service reloads required after IPSET snapshot restoration.
lower_script() { printf '%s\n' "$*" >>"${IPSET_CALLS_FILE}"; }

# IPSet_Lock_Interrupt_Propagate invokes the registered outer transaction callback when nested lock cleanup is interrupted.
IPSet_Lock_Interrupt_Propagate() {
	[ -n "${IPSET_LOCK_INTERRUPT_CALLBACK:-}" ] || return 0
	"${IPSET_LOCK_INTERRUPT_CALLBACK}"
}

# mv enforces transaction and restoration ordering checks, injects configured move failures, and delegates other moves to the system command.
mv() {
	if [ "${TRANSACTION_ACTIVE:-0}" = "1" ]; then
		[ "${IPSET_LOCK_ACTIVE:-0}" = "1" ] || fail 'dnsmasq publication or compensation ran outside the transaction lock'
	fi
	if [ "${RESTORE_REQUIRE_YAML_STAGE:-0}" = "1" ]; then
		case "${1:-}" in
			"${IPSET_FILE}.dnsmasq-restore."*)
				[ -f "${YAML_FILE}.dnsmasq-restore.$$" ] || fail 'IPSET restoration was published before YAML restoration was staged'
				;;
		esac
	fi
	if [ "${RESTORE_FAIL:-0}" = "1" ]; then
		case "${1:-}" in
			"${IPSET_FILE}.dnsmasq-restore."*) return 1 ;;
		esac
	fi
	if [ "${RESTORE_YAML_FAIL:-0}" = "1" ]; then
		case "${1:-}" in
			"${YAML_FILE}.dnsmasq-restore."*) return 1 ;;
		esac
	fi
	if [ "${RESTORE_COMPENSATE_FAIL:-0}" = "1" ] && [ "${2:-}" = "${IPSET_FILE}" ]; then
		case "${1:-}" in
			"${IPSET_FILE}.dnsmasq-current."*) return 1 ;;
		esac
	fi
	if [ "${MV_PUBLISH_FAIL:-0}" = "1" ] && [ "${2:-}" = "${DNSMASQ_CONF_FILE}" ]; then
		case "${1:-}" in
			"${DNSMASQ_CONF_FILE}.adguard."*) return 1 ;;
		esac
	fi
	if [ "${BACKUP_RESTORE_FAIL:-0}" = "1" ] && [ "${2:-}" = "${DNSMASQ_CONF_FILE}" ]; then
		case "${1:-}" in
			"${DNSMASQ_CONF_FILE}.adguard-restore."*) return 1 ;;
		esac
	fi
	if [ "${ASSOCIATION_CREATE_FAIL:-0}" = "1" ] && [ "${2:-}" = "${IPSET_SNAPSHOT_DIR:-}/config.pending" ]; then
		case "${1:-}" in
			"${IPSET_SNAPSHOT_DIR}/config.pending."*) return 1 ;;
		esac
	fi
	if [ "${MARK_CLEANUP_FAIL:-0}" = "1" ] && [ "${1:-}" = "${MARK_CLEANUP_FAIL_SNAPSHOT:-}/restore.pending" ]; then
		return 1
	fi
	command mv "$@"
}

# rm injects snapshot-finalization cleanup failures and delegates all other removals to the system command.
rm() {
	if [ "${FINALIZE_REMOVE_FAIL:-0}" = "1" ] && [ "${1:-}" = -rf ] && [ "${2:-}" = "${FINALIZE_FAIL_SNAPSHOT:-}" ]; then
		return 1
	fi
	command rm "$@"
}

# private_ipv4_bridge_dns_options_with_fallbacks records the LAN interface and emits configured bridge DNS options, failing when fallback generation is unavailable.
private_ipv4_bridge_dns_options_with_fallbacks() {
	printf '%s\n' "$1" >>"${BRIDGE_FALLBACK_CALLS_FILE}"
	[ "${BRIDGE_DNS_FAIL:-0}" != "1" ] || return 1
	[ -z "${BRIDGE_DNS_OPTIONS}" ] || printf '%s\n' "${BRIDGE_DNS_OPTIONS}"
}

# reset_case resets test logs, recorded calls, sandboxed dnsmasq configurations, and scenario state to default values.
reset_case() {
	: >"${LOG_FILE}"
	: >"${IPSET_CALLS_FILE}"
	: >"${UMOUNT_CALLS_FILE}"
	: >"${MOUNT_CALLS_FILE}"
	: >"${BRIDGE_FALLBACK_CALLS_FILE}"
	rm -f "${MANAGED_IPSET_FILE}"
	find "${TEST_ROOT}" -type d -name '.AdGuardHome.dnsmasq-ipset.*' -prune -exec /bin/rm -rf {} \; || fail 'could not remove leaked IPSET recovery snapshots'
	printf '%s\n' 'original yaml' >"${YAML_FILE}" || fail 'could not reset YAML fixture'
	printf '%s\n' '# base config' >"${DNSMASQ_CONF_FILE}" || fail 'could not reset base dnsmasq config'
	printf '%s\n' '# sdn config' >"${DNSMASQ_SDN_CONF_FILE}" || fail 'could not reset sdn dnsmasq config'
	DNS_HANDOFF_ACTIVE='0'
	ADGUARD_INSTALL_MODE='wan'
	WAN_NAT_ACTIVE='0'
	BRIDGE_DNS_FAIL='0'
	DNSMASQ_RUNNING='0'
	ADGUARD_RUNNING='1'
	ADGUARD_DNSMASQ_MODE='auto'
	CONFIG_DNSMASQ_MODE="${ADGUARD_DNSMASQ_MODE}"
	RESOLV_CONF_USES_ROM='1'
	RESOLV_CONF_TMP_MOUNT='0'
	unset NVRAM_RC_SUPPORT
	NVRAM_LAN_IFNAME='br0'
	BRIDGE_DNS_OPTIONS=''
	IPSET_REFRESH_FAIL='0'
	IPSET_REFRESH_CHANGE='0'
	MV_PUBLISH_FAIL='0'
	BACKUP_RESTORE_FAIL='0'
	ASSOCIATION_CREATE_FAIL='0'
	RESTORE_FAIL='0'
	RESTORE_REQUIRE_YAML_STAGE='0'
	RESTORE_YAML_FAIL='0'
	RESTORE_COMPENSATE_FAIL='0'
	FINALIZE_REMOVE_FAIL='0'
	FINALIZE_FAIL_SNAPSHOT=''
	MARK_CLEANUP_FAIL='0'
	MARK_CLEANUP_FAIL_SNAPSHOT=''
	MOUNT_FAIL='0'
	CONFIG_LOCAL='NO'
	[ -z "${SECOND_STARTED:-}" ] || rm -f "${SECOND_STARTED}"
	[ -z "${SECOND_WAITING:-}" ] || rm -f "${SECOND_WAITING}"
}

# assert_no_ipset_refresh verifies that no IPSET refresh calls were recorded for the test case.
assert_no_ipset_refresh() {
	[ ! -s "${IPSET_CALLS_FILE}" ] || fail "$1: IPSET refresh should not run"
}

# wait_for_file waits up to 10 seconds for the specified marker file to appear and reports whether it exists.
wait_for_file() {
	marker="$1"
	count=0
	while [ ! -f "${marker}" ] && [ "${count}" -lt 10 ]; do
		sleep 1
		count="$((count + 1))"
	done
	[ -f "${marker}" ]
}

# wait_for_release waits up to 10 seconds for the specified release marker file and returns whether it exists.
wait_for_release() {
	release_marker="$1"
	release_count=0
	while [ ! -f "${release_marker}" ] && [ "${release_count}" -lt 10 ]; do
		sleep 1
		release_count="$((release_count + 1))"
	done
	[ -f "${release_marker}" ]
}

# assert_dnsmasq_postconf_written verifies that dnsmasq handoff settings were written to the specified configuration file.
assert_dnsmasq_postconf_written() {
	config_file="$1"
	case_name="$2"
	grep -q '^port=553$' "${config_file}" || fail "${case_name}: dnsmasq handoff port was not written"
	grep -q '^add-mac$' "${config_file}" || fail "${case_name}: dnsmasq add-mac was not written"
}

# assert_dnsmasq_postconf_not_written verifies that dnsmasq handoff settings were not written to the specified configuration file.
assert_dnsmasq_postconf_not_written() {
	config_file="$1"
	case_name="$2"
	! grep -q '^port=553$' "${config_file}" || fail "${case_name}: dnsmasq handoff port was written"
	! grep -q '^add-mac$' "${config_file}" || fail "${case_name}: dnsmasq add-mac was written"
}

# assert_resolv_conf_unmounted verifies that /tmp/resolv.conf was unmounted for a test case.
assert_resolv_conf_unmounted() {
	case_name="$1"
	grep -q '^/tmp/resolv.conf$' "${UMOUNT_CALLS_FILE}" || fail "${case_name}: /tmp/resolv.conf was not unmounted"
}

# assert_resolv_conf_not_unmounted verifies that no resolv.conf unmount was recorded for the specified test case.
assert_resolv_conf_not_unmounted() {
	case_name="$1"
	[ ! -s "${UMOUNT_CALLS_FILE}" ] || fail "${case_name}: /tmp/resolv.conf was unmounted"
}

reset_case
ADGUARD_INSTALL_MODE='lan'
DNSMASQ_RUNNING='0'
ADGUARD_DNSMASQ_MODE='auto'
CONFIG_DNSMASQ_MODE="${ADGUARD_DNSMASQ_MODE}"
RESOLV_CONF_USES_ROM='0'
RESOLV_CONF_TMP_MOUNT='1'
dnsmasq_action_handler || fail 'LAN stopped dnsmasq path failed'
grep -q 'state=skip reason=lan_mode_dnsmasq_not_running' "${LOG_FILE}" ||
	fail 'LAN stopped dnsmasq path did not log stopped dnsmasq skip reason'
assert_dnsmasq_postconf_not_written "${DNSMASQ_CONF_FILE}" 'LAN stopped dnsmasq path'
assert_resolv_conf_unmounted 'LAN stopped dnsmasq path'
assert_no_ipset_refresh 'LAN stopped dnsmasq path'

reset_case
ADGUARD_INSTALL_MODE='lan'
DNSMASQ_RUNNING='0'
ADGUARD_RUNNING='0'
ADGUARD_DNSMASQ_MODE='auto'
CONFIG_DNSMASQ_MODE="${ADGUARD_DNSMASQ_MODE}"
dnsmasq_action_handler || fail 'LAN stopped AdGuardHome path failed'
grep -q 'state=skip reason=lan_mode_dnsmasq_not_running' "${LOG_FILE}" ||
	fail 'LAN stopped AdGuardHome path did not log stopped dnsmasq skip reason'
assert_dnsmasq_postconf_not_written "${DNSMASQ_CONF_FILE}" 'LAN stopped AdGuardHome path'
assert_no_ipset_refresh 'LAN stopped AdGuardHome path'

reset_case
ADGUARD_INSTALL_MODE='lan'
DNSMASQ_RUNNING='0'
ADGUARD_DNSMASQ_MODE='disabled'
CONFIG_DNSMASQ_MODE="${ADGUARD_DNSMASQ_MODE}"
dnsmasq_action_handler || fail 'LAN disabled dnsmasq path failed'
grep -q 'state=skip reason=lan_mode_dnsmasq_not_running' "${LOG_FILE}" ||
	fail 'LAN disabled dnsmasq path did not log stopped dnsmasq skip reason'
assert_dnsmasq_postconf_not_written "${DNSMASQ_CONF_FILE}" 'LAN disabled dnsmasq path'
assert_no_ipset_refresh 'LAN disabled dnsmasq path'

reset_case
ADGUARD_INSTALL_MODE='lan'
DNSMASQ_RUNNING='0'
ADGUARD_RUNNING='0'
ADGUARD_DNSMASQ_MODE='disabled'
CONFIG_DNSMASQ_MODE="${ADGUARD_DNSMASQ_MODE}"
DNS_HANDOFF_ACTIVE='1'
touch "${MANAGED_IPSET_FILE}" || fail 'could not create disabled-handoff managed IPSET fixture'
dnsmasq_action_handler || fail 'LAN disabled handoff path failed'
! grep -q 'state=skip reason=lan_mode_dnsmasq_not_running' "${LOG_FILE}" ||
	fail 'LAN disabled handoff path logged stopped dnsmasq skip reason'
assert_dnsmasq_postconf_not_written "${DNSMASQ_CONF_FILE}" 'LAN disabled handoff path'
assert_no_ipset_refresh 'LAN disabled handoff path'
[ -e "${MANAGED_IPSET_FILE}" ] || fail 'stopped dnsmasq path unexpectedly changed managed IPSET state'

reset_case
ADGUARD_INSTALL_MODE='lan'
DNSMASQ_RUNNING='1'
WAN_NAT_ACTIVE='1'
ADGUARD_DNSMASQ_MODE='auto'
CONFIG_DNSMASQ_MODE="${ADGUARD_DNSMASQ_MODE}"
dnsmasq_action_handler || fail 'LAN running dnsmasq base path failed'
assert_dnsmasq_postconf_written "${DNSMASQ_CONF_FILE}" 'LAN running dnsmasq base path'
assert_resolv_conf_not_unmounted 'LAN running dnsmasq base path'
grep -q "${DNSMASQ_CONF_FILE}" "${IPSET_CALLS_FILE}" || fail 'LAN double-NAT dnsmasq path did not refresh IPSET'

reset_case
ADGUARD_INSTALL_MODE='lan'
DNSMASQ_RUNNING='1'
WAN_NAT_ACTIVE='0'
touch "${MANAGED_IPSET_FILE}" || fail 'could not create managed IPSET state fixture'
dnsmasq_action_handler || fail 'LAN rejected-topology dnsmasq path failed'
assert_dnsmasq_postconf_written "${DNSMASQ_CONF_FILE}" 'LAN rejected-topology dnsmasq path'
grep -q "${DNSMASQ_CONF_FILE}" "${IPSET_CALLS_FILE}" ||
	fail 'LAN rejected topology did not invoke IPSET refresh cleanup'
[ ! -e "${MANAGED_IPSET_FILE}" ] || fail 'LAN rejected topology did not disable managed IPSET state'

reset_case
ADGUARD_INSTALL_MODE='wan'
DNSMASQ_RUNNING='1'
IPSET_REFRESH_FAIL='1'
printf '%s\n' 'original ipset' >"${IPSET_FILE}" || fail 'could not create IPSET rollback fixture'
ORIGINAL_CONFIG="$(cat "${DNSMASQ_CONF_FILE}")"
if dnsmasq_action_handler; then
	fail 'failed IPSET refresh unexpectedly published dnsmasq configuration'
fi
[ "$(cat "${DNSMASQ_CONF_FILE}")" = "${ORIGINAL_CONFIG}" ] ||
	fail 'failed IPSET refresh changed the live dnsmasq configuration'
grep -qx 'original ipset' "${IPSET_FILE}" || fail 'failed IPSET refresh did not restore IPSET state'
grep -qx 'original yaml' "${YAML_FILE}" || fail 'failed IPSET refresh did not restore YAML state'
if find "${TEST_ROOT}" -name 'dnsmasq.conf.adguard.*' -print | grep -q .; then
	fail 'failed IPSET refresh left a staged dnsmasq configuration'
fi

reset_case
ADGUARD_INSTALL_MODE='wan'
DNSMASQ_RUNNING='1'
IPSET_REFRESH_CHANGE='1'
MV_PUBLISH_FAIL='1'
printf '%s\n' 'original ipset' >"${IPSET_FILE}" || fail 'could not create publication rollback fixture'
ORIGINAL_CONFIG="$(cat "${DNSMASQ_CONF_FILE}")"
if dnsmasq_action_handler; then
	fail 'failed dnsmasq publication unexpectedly succeeded'
fi
[ "$(cat "${DNSMASQ_CONF_FILE}")" = "${ORIGINAL_CONFIG}" ] ||
	fail 'failed dnsmasq publication changed the live configuration'
grep -qx 'original ipset' "${IPSET_FILE}" || fail 'failed dnsmasq publication did not restore IPSET state'
grep -qx 'original yaml' "${YAML_FILE}" || fail 'failed dnsmasq publication did not restore YAML state'
if find "${TEST_ROOT}" -name '.AdGuardHome.dnsmasq-ipset.*' -print | grep -q .; then
	fail 'successful publication compensation retained an IPSET recovery snapshot'
fi

reset_case
ADGUARD_INSTALL_MODE='wan'
DNSMASQ_RUNNING='1'
IPSET_REFRESH_FAIL='1'
RESTORE_FAIL='1'
printf '%s\n' 'original ipset' >"${IPSET_FILE}" || fail 'could not create retained recovery fixture'
if dnsmasq_action_handler; then
	fail 'failed IPSET compensation unexpectedly succeeded'
fi
RECOVERY_SNAPSHOT="$(find "${TEST_ROOT}" -type d -name '.AdGuardHome.dnsmasq-ipset.*' -print | head -n 1)"
[ -n "${RECOVERY_SNAPSHOT}" ] || fail 'failed IPSET compensation discarded its recovery snapshot'
grep -qx 'original ipset' "${RECOVERY_SNAPSHOT}/ipset" ||
	fail 'retained IPSET recovery snapshot did not preserve the original state'
grep -q "result=failed snapshot=${RECOVERY_SNAPSHOT}" "${LOG_FILE}" ||
	fail 'failed IPSET compensation did not report its recovery snapshot'
rm -rf "${RECOVERY_SNAPSHOT}" || fail 'could not clear verified IPSET recovery snapshot'

reset_case
ADGUARD_INSTALL_MODE='wan'
DNSMASQ_RUNNING='1'
IPSET_REFRESH_FAIL='1'
RESTORE_REQUIRE_YAML_STAGE='1'
RESTORE_YAML_FAIL='1'
printf '%s\n' 'original ipset' >"${IPSET_FILE}" || fail 'could not create YAML restoration failure fixture'
if dnsmasq_action_handler; then
	fail 'failed YAML restoration unexpectedly succeeded'
fi
grep -qx refreshed "${IPSET_FILE}" || fail 'failed YAML restoration left partial IPSET state'
grep -qx refreshed "${YAML_FILE}" || fail 'failed YAML restoration changed the current YAML state'
RECOVERY_SNAPSHOT="$(find "${TEST_ROOT}" -type d -name '.AdGuardHome.dnsmasq-ipset.*' -print | head -n 1)"
[ -n "${RECOVERY_SNAPSHOT}" ] || fail 'failed YAML restoration discarded its recovery snapshot'
grep -qx 'original ipset' "${RECOVERY_SNAPSHOT}/ipset" ||
	fail 'retained YAML failure snapshot did not preserve the original IPSET state'
grep -qx 'original yaml' "${RECOVERY_SNAPSHOT}/yaml" ||
	fail 'retained YAML failure snapshot did not preserve the original YAML state'
if find "${TEST_ROOT}" -name '*.dnsmasq-current.*' -o -name '*.dnsmasq-restore.*' | grep -q .; then
	fail 'failed YAML restoration left staged artifacts after recovering current state'
fi
rm -rf "${RECOVERY_SNAPSHOT}" || fail 'could not clear YAML failure recovery snapshot'

reset_case
ADGUARD_INSTALL_MODE='lan'
DNSMASQ_RUNNING='1'
WAN_NAT_ACTIVE='1'
ADGUARD_DNSMASQ_MODE='auto'
CONFIG_DNSMASQ_MODE="${ADGUARD_DNSMASQ_MODE}"
dnsmasq_action_handler 1 || fail 'LAN running dnsmasq SDN path failed'
assert_dnsmasq_postconf_written "${DNSMASQ_SDN_CONF_FILE}" 'LAN running dnsmasq SDN path'
grep -q "${DNSMASQ_SDN_CONF_FILE}" "${IPSET_CALLS_FILE}" || fail 'LAN double-NAT dnsmasq SDN path did not refresh IPSET'

reset_case
ADGUARD_INSTALL_MODE='lan'
DNSMASQ_RUNNING='0'
ADGUARD_DNSMASQ_MODE='auto'
CONFIG_DNSMASQ_MODE="${ADGUARD_DNSMASQ_MODE}"
dnsmasq_action_handler 1 || fail 'LAN stopped dnsmasq SDN path failed'
grep -q 'state=skip reason=lan_mode_dnsmasq_not_running' "${LOG_FILE}" ||
	fail 'LAN stopped dnsmasq SDN path did not log stopped dnsmasq skip reason'
assert_dnsmasq_postconf_not_written "${DNSMASQ_SDN_CONF_FILE}" 'LAN stopped dnsmasq SDN path'
assert_no_ipset_refresh 'LAN stopped dnsmasq SDN path'

reset_case
ADGUARD_INSTALL_MODE='wan'
DNSMASQ_RUNNING='0'
ADGUARD_DNSMASQ_MODE='auto'
CONFIG_DNSMASQ_MODE="${ADGUARD_DNSMASQ_MODE}"
dnsmasq_action_handler || fail 'WAN stopped dnsmasq path failed'
assert_dnsmasq_postconf_not_written "${DNSMASQ_CONF_FILE}" 'WAN stopped dnsmasq path'
assert_no_ipset_refresh 'WAN stopped dnsmasq path'

reset_case
ADGUARD_INSTALL_MODE='wan'
DNSMASQ_RUNNING='1'
rm -f "${DNSMASQ_CONF_FILE}"
dnsmasq_action_handler || fail 'missing dnsmasq configuration path failed'
[ ! -e "${DNSMASQ_CONF_FILE}" ] || fail 'missing dnsmasq configuration was unexpectedly published'
assert_no_ipset_refresh 'missing dnsmasq configuration path'

reset_case
ADGUARD_INSTALL_MODE='wan'
DNSMASQ_RUNNING='0'
ADGUARD_RUNNING='0'
ADGUARD_DNSMASQ_MODE='auto'
CONFIG_DNSMASQ_MODE="${ADGUARD_DNSMASQ_MODE}"
dnsmasq_action_handler || fail 'WAN stopped AdGuardHome path failed'
assert_dnsmasq_postconf_not_written "${DNSMASQ_CONF_FILE}" 'WAN stopped AdGuardHome path'
assert_no_ipset_refresh 'WAN stopped AdGuardHome path'

reset_case
ADGUARD_INSTALL_MODE='lan'
DNSMASQ_RUNNING='0'
ADGUARD_DNSMASQ_MODE='enabled'
CONFIG_DNSMASQ_MODE="${ADGUARD_DNSMASQ_MODE}"
dnsmasq_action_handler || fail 'LAN managed stopped dnsmasq startup path failed'
! grep -q 'state=skip reason=lan_mode_dnsmasq_not_running' "${LOG_FILE}" ||
	fail 'LAN managed stopped dnsmasq startup path logged stopped dnsmasq skip reason'
assert_dnsmasq_postconf_not_written "${DNSMASQ_CONF_FILE}" 'LAN managed stopped dnsmasq startup path'
assert_no_ipset_refresh 'LAN managed stopped dnsmasq startup path'

reset_case
ADGUARD_INSTALL_MODE='lan'
DNSMASQ_RUNNING='0'
ADGUARD_DNSMASQ_MODE='auto'
CONFIG_DNSMASQ_MODE="${ADGUARD_DNSMASQ_MODE}"
DNS_HANDOFF_ACTIVE='1'
ADGUARD_RUNNING='0'
dnsmasq_action_handler || fail 'LAN stopped dnsmasq handoff path failed'
! grep -q 'state=skip reason=lan_mode_dnsmasq_not_running' "${LOG_FILE}" ||
	fail 'LAN stopped dnsmasq handoff path logged stopped dnsmasq skip reason'
assert_dnsmasq_postconf_not_written "${DNSMASQ_CONF_FILE}" 'LAN stopped dnsmasq handoff path'
assert_no_ipset_refresh 'LAN stopped dnsmasq handoff path'

# Base-config generation threads the resolved primary LAN interface into the
# bridge DNS fallback helper and writes a dhcp-option line per discovered pair.
reset_case
ADGUARD_INSTALL_MODE='wan'
DNSMASQ_RUNNING='1'
ADGUARD_RUNNING='1'
ADGUARD_DNSMASQ_MODE='auto'
CONFIG_DNSMASQ_MODE="${ADGUARD_DNSMASQ_MODE}"
NVRAM_LAN_IFNAME='br0'
NVRAM_RC_SUPPORT='some_other_feature'
BRIDGE_DNS_OPTIONS="$(printf '%s\n' 'br1 192.168.101.254' 'br2 192.168.102.1')"
dnsmasq_action_handler || fail 'bridge DNS dhcp-option base config path failed'
[ "$(cat "${BRIDGE_FALLBACK_CALLS_FILE}")" = 'br0' ] ||
	fail 'bridge DNS fallback helper was not invoked with the resolved primary LAN interface'
grep -q '^dhcp-option=br1,6,192\.168\.101\.254$' "${DNSMASQ_CONF_FILE}" ||
	fail 'bridge DNS dhcp-option for the first discovered bridge was not written'
grep -q '^dhcp-option=br2,6,192\.168\.102\.1$' "${DNSMASQ_CONF_FILE}" ||
	fail 'bridge DNS dhcp-option for the second discovered bridge was not written'

# A different resolved LAN interface is threaded through unchanged.
reset_case
ADGUARD_INSTALL_MODE='wan'
DNSMASQ_RUNNING='1'
ADGUARD_RUNNING='1'
ADGUARD_DNSMASQ_MODE='auto'
CONFIG_DNSMASQ_MODE="${ADGUARD_DNSMASQ_MODE}"
NVRAM_LAN_IFNAME='br9'
NVRAM_RC_SUPPORT='other_feature'
BRIDGE_DNS_OPTIONS="$(printf '%s\n' 'br0 192.168.50.254')"
dnsmasq_action_handler || fail 'bridge DNS dhcp-option path failed for a non-br0 primary interface'
[ "$(cat "${BRIDGE_FALLBACK_CALLS_FILE}")" = 'br9' ] ||
	fail 'bridge DNS fallback helper did not receive the non-br0 primary LAN interface'
grep -q '^dhcp-option=br0,6,192\.168\.50\.254$' "${DNSMASQ_CONF_FILE}" ||
	fail 'bridge DNS dhcp-option for a secondary br0 bridge was not written'

# Incomplete interface/address pairs from the fallback helper are skipped without writing malformed options.
reset_case
ADGUARD_INSTALL_MODE='wan'
DNSMASQ_RUNNING='1'
ADGUARD_RUNNING='1'
ADGUARD_DNSMASQ_MODE='auto'
CONFIG_DNSMASQ_MODE="${ADGUARD_DNSMASQ_MODE}"
NVRAM_LAN_IFNAME='br0'
NVRAM_RC_SUPPORT='other_feature'
BRIDGE_DNS_OPTIONS="$(printf '%s\n' 'br1 192.168.101.254' 'br2' '' 'br3 192.168.103.1')"
dnsmasq_action_handler || fail 'bridge DNS dhcp-option path failed with an incomplete discovery pair'
grep -q '^dhcp-option=br1,6,192\.168\.101\.254$' "${DNSMASQ_CONF_FILE}" ||
	fail 'bridge DNS dhcp-option before the incomplete pair was not written'
grep -q '^dhcp-option=br3,6,192\.168\.103\.1$' "${DNSMASQ_CONF_FILE}" ||
	fail 'bridge DNS dhcp-option after the incomplete pair was not written'
! grep -q '^dhcp-option=br2,6,$' "${DNSMASQ_CONF_FILE}" ||
	fail 'bridge DNS dhcp-option was written for an interface without an address'

# A bridge discovery failure must discard staged edits and preserve the live dnsmasq file.
reset_case
ADGUARD_INSTALL_MODE='wan'
DNSMASQ_RUNNING='1'
ADGUARD_RUNNING='1'
ADGUARD_DNSMASQ_MODE='auto'
CONFIG_DNSMASQ_MODE="${ADGUARD_DNSMASQ_MODE}"
NVRAM_LAN_IFNAME='br0'
NVRAM_RC_SUPPORT='other_feature'
BRIDGE_DNS_FAIL='1'
if dnsmasq_action_handler; then
	fail 'bridge DNS discovery failure was hidden'
fi
grep -qx '# base config' "${DNSMASQ_CONF_FILE}" ||
	fail 'bridge DNS discovery failure modified the live dnsmasq configuration'
if find "${TEST_ROOT}" -name '*.bridge-options' -o -name '*.adguard.*' | grep -q .; then
	fail 'bridge DNS discovery failure left staged artifacts'
fi

# The mtlancfg rc_support flag skips bridge DNS discovery entirely for the base config.
reset_case
ADGUARD_INSTALL_MODE='wan'
DNSMASQ_RUNNING='1'
ADGUARD_RUNNING='1'
ADGUARD_DNSMASQ_MODE='auto'
CONFIG_DNSMASQ_MODE="${ADGUARD_DNSMASQ_MODE}"
NVRAM_LAN_IFNAME='br0'
NVRAM_RC_SUPPORT='mtlancfg'
BRIDGE_DNS_OPTIONS="$(printf '%s\n' 'br1 192.168.101.254')"
dnsmasq_action_handler || fail 'mtlancfg bridge DNS skip path failed'
[ ! -s "${BRIDGE_FALLBACK_CALLS_FILE}" ] ||
	fail 'mtlancfg rc_support unexpectedly invoked the bridge DNS fallback helper'
! grep -q '^dhcp-option=br1,6,192\.168\.101\.254$' "${DNSMASQ_CONF_FILE}" ||
	fail 'mtlancfg rc_support unexpectedly wrote a secondary bridge dhcp-option'

# A failed post-publication resolver bind is reported without changing the
# successful dnsmasq/IPSET transaction result.
reset_case
ADGUARD_INSTALL_MODE='wan'
DNSMASQ_RUNNING='1'
CONFIG_LOCAL='YES'
RESOLV_CONF_USES_ROM='0'
MOUNT_FAIL='1'
dnsmasq_action_handler || fail 'committed dnsmasq state was reported as failed after resolver bind failure'
grep -q 'action=bind_resolver result=failed' "${LOG_FILE}" || fail 'resolver bind failure was not reported'
grep -q -- '-o bind /rom/etc/resolv.conf /tmp/resolv.conf' "${MOUNT_CALLS_FILE}" || fail 'resolver bind was not attempted'

# Restoration must reload a process that appears after the captured stopped
# state so it consumes the rolled-back files.
reset_case
STOPPED_SNAPSHOT="${TEST_ROOT}/stopped-service-snapshot"
mkdir -m 700 "${STOPPED_SNAPSHOT}" || fail 'could not create stopped-service snapshot'
printf '%s\n' 'snapshot ipset' >"${STOPPED_SNAPSHOT}/ipset"
printf '%s\n' 'snapshot yaml' >"${STOPPED_SNAPSHOT}/yaml"
printf '%s\n' changed >"${IPSET_FILE}"
printf '%s\n' changed >"${YAML_FILE}"
ADGUARD_RUNNING='1'
dnsmasq_ipset_state_restore "${STOPPED_SNAPSHOT}" 0 || fail 'stopped-service state restoration failed'
grep -q '^restart$' "${IPSET_CALLS_FILE}" || fail 'stopped-service rollback did not reload a newly appearing process'
rm -rf "${STOPPED_SNAPSHOT}" || fail 'could not clear stopped-service snapshot'

# A pending restore journal left between IPSET and YAML publication is recovered
# idempotently under the shared transaction lock before another transaction.
reset_case
RECOVERY_SNAPSHOT="${TEST_ROOT}/.AdGuardHome.dnsmasq-ipset.recovery"
printf '%s\n' 'snapshot ipset' >"${IPSET_FILE}" || fail 'could not create recovery IPSET fixture'
printf '%s\n' 'snapshot yaml' >"${YAML_FILE}" || fail 'could not create recovery YAML fixture'
dnsmasq_ipset_state_snapshot "${RECOVERY_SNAPSHOT}" || fail 'could not create pending recovery snapshot'
[ -f "${RECOVERY_SNAPSHOT}/restore.pending" ] || fail 'pending recovery snapshot lacks its durable marker'
printf '%s\n' 'snapshot ipset' >"${IPSET_FILE}" || fail 'could not simulate partial IPSET restoration'
printf '%s\n' 'current yaml' >"${YAML_FILE}" || fail 'could not simulate interrupted YAML restoration'
IPSet_Lock dnsmasq_ipset_state_recover_pending || fail 'pending recovery did not complete'
grep -qx 'snapshot ipset' "${IPSET_FILE}" || fail 'pending recovery did not restore IPSET state'
grep -qx 'snapshot yaml' "${YAML_FILE}" || fail 'pending recovery did not restore YAML state'
[ ! -e "${RECOVERY_SNAPSHOT}" ] || fail 'completed recovery retained its snapshot'
IPSet_Lock dnsmasq_ipset_state_recover_pending || fail 'repeated recovery was not idempotent'

# A committed snapshot whose recursive cleanup fails is marked cleanup-only,
# then removed by the next lock holder without rolling back published state.
reset_case
FINALIZE_SNAPSHOT="${TEST_ROOT}/.AdGuardHome.dnsmasq-ipset.finalize-retry"
FINALIZE_STAGE="${DNSMASQ_CONF_FILE}.adguard.finalize-retry"
printf '%s\n' '# committed config' >"${FINALIZE_STAGE}" || fail 'could not stage cleanup-retry dnsmasq fixture'
printf '%s\n' 'committed ipset' >"${IPSET_FILE}" || fail 'could not create cleanup-retry IPSET fixture'
printf '%s\n' 'committed yaml' >"${YAML_FILE}" || fail 'could not create cleanup-retry YAML fixture'
FINALIZE_FAIL_SNAPSHOT="${FINALIZE_SNAPSHOT}"
FINALIZE_REMOVE_FAIL='1'
dnsmasq_publish_staged_config "${DNSMASQ_CONF_FILE}" "${FINALIZE_STAGE}" "${FINALIZE_SNAPSHOT}" || fail 'published transaction failed when only snapshot cleanup failed'
[ -f "${FINALIZE_SNAPSHOT}/cleanup.pending" ] || fail 'failed snapshot cleanup did not retain its cleanup-only marker'
[ ! -e "${FINALIZE_SNAPSHOT}/restore.pending" ] || fail 'committed snapshot remained eligible for rollback after cleanup failure'
if IPSet_Lock dnsmasq_ipset_state_recover_pending; then
	fail 'cleanup retry unexpectedly succeeded while snapshot removal was failing'
fi
grep -q "state=recovery action=cleanup_snapshot result=failed snapshot=${FINALIZE_SNAPSHOT}" "${LOG_FILE}" ||
	fail 'failed cleanup retry did not identify the retained snapshot'
FINALIZE_REMOVE_FAIL='0'
IPSet_Lock dnsmasq_ipset_state_recover_pending || fail 'next transaction did not retry committed snapshot cleanup'
[ ! -e "${FINALIZE_SNAPSHOT}" ] || fail 'retried committed snapshot cleanup retained its directory'
grep -qx 'committed ipset' "${IPSET_FILE}" || fail 'cleanup retry rolled back committed IPSET state'
grep -qx 'committed yaml' "${YAML_FILE}" || fail 'cleanup retry rolled back committed YAML state'

# A failed restore-to-cleanup marker transition makes publication unsafe and
# rolls the dnsmasq, IPSet, and YAML state back while propagating failure.
reset_case
MARK_FAIL_SNAPSHOT="${TEST_ROOT}/.AdGuardHome.dnsmasq-ipset.mark-failure"
MARK_FAIL_STAGE="${DNSMASQ_CONF_FILE}.adguard.mark-failure"
printf '%s\n' '# unsafe publication' >"${MARK_FAIL_STAGE}" || fail 'could not stage marker-failure fixture'
printf '%s\n' 'previous ipset' >"${IPSET_FILE}" || fail 'could not initialize marker-failure IPSET fixture'
printf '%s\n' 'previous yaml' >"${YAML_FILE}" || fail 'could not initialize marker-failure YAML fixture'
MARK_CLEANUP_FAIL='1'
MARK_CLEANUP_FAIL_SNAPSHOT="${MARK_FAIL_SNAPSHOT}"
if dnsmasq_publish_staged_config "${DNSMASQ_CONF_FILE}" "${MARK_FAIL_STAGE}" "${MARK_FAIL_SNAPSHOT}"; then
	fail 'cleanup-marker transition failure reported a successful publication'
fi
grep -qx '# base config' "${DNSMASQ_CONF_FILE}" || fail 'cleanup-marker transition failure did not restore dnsmasq'
grep -qx 'previous ipset' "${IPSET_FILE}" || fail 'cleanup-marker transition failure did not restore IPSET state'
grep -qx 'previous yaml' "${YAML_FILE}" || fail 'cleanup-marker transition failure did not restore YAML state'
[ -f "${MARK_FAIL_SNAPSHOT}/restore.pending" ] || fail 'cleanup-marker transition failure lost its retryable restore marker'
MARK_CLEANUP_FAIL='0'
IPSet_Lock dnsmasq_ipset_state_recover_pending || fail 'marker-failure rollback cleanup was not retryable'
[ ! -e "${MARK_FAIL_SNAPSHOT}" ] || fail 'marker-failure cleanup retry retained its snapshot'

# Association creation must complete before IPSet refresh or dnsmasq publication.
reset_case
ASSOCIATION_FAIL_SNAPSHOT="${TEST_ROOT}/.AdGuardHome.dnsmasq-ipset.association-failure"
ASSOCIATION_FAIL_STAGE="${DNSMASQ_CONF_FILE}.adguard.association-failure"
printf '%s\n' '# association failure' >"${ASSOCIATION_FAIL_STAGE}" || fail 'could not stage association-failure fixture'
ASSOCIATION_CREATE_FAIL='1'
if dnsmasq_publish_staged_config "${DNSMASQ_CONF_FILE}" "${ASSOCIATION_FAIL_STAGE}" "${ASSOCIATION_FAIL_SNAPSHOT}"; then
	fail 'config association creation failure reported success'
fi
[ ! -s "${IPSET_CALLS_FILE}" ] || fail 'config association creation failure allowed IPSet refresh'
grep -qx '# base config' "${DNSMASQ_CONF_FILE}" || fail 'config association creation failure published dnsmasq configuration'
[ ! -e "${ASSOCIATION_FAIL_STAGE}" ] || fail 'config association creation failure retained its staged configuration'
[ ! -e "${ASSOCIATION_FAIL_STAGE}.previous" ] || fail 'config association creation failure retained its backup'
[ ! -e "${ASSOCIATION_FAIL_SNAPSHOT}" ] || fail 'config association creation failure retained its snapshot'

# A failed dnsmasq backup restore must retain the coupled backup and snapshot
# without restoring IPSet or YAML over the still-published configuration.
reset_case
BACKUP_FAIL_SNAPSHOT="${TEST_ROOT}/.AdGuardHome.dnsmasq-ipset.backup-failure"
BACKUP_FAIL_STAGE="${DNSMASQ_CONF_FILE}.adguard.backup-failure"
BACKUP_FAIL_FILE="${BACKUP_FAIL_STAGE}.previous"
printf '%s\n' '# published after failed rollback' >"${BACKUP_FAIL_STAGE}" || fail 'could not stage backup-restore-failure fixture'
printf '%s\n' 'previous ipset' >"${IPSET_FILE}" || fail 'could not initialize backup-restore-failure IPSET fixture'
printf '%s\n' 'previous yaml' >"${YAML_FILE}" || fail 'could not initialize backup-restore-failure YAML fixture'
IPSET_REFRESH_CHANGE='1'
MARK_CLEANUP_FAIL='1'
MARK_CLEANUP_FAIL_SNAPSHOT="${BACKUP_FAIL_SNAPSHOT}"
BACKUP_RESTORE_FAIL='1'
if dnsmasq_publish_staged_config "${DNSMASQ_CONF_FILE}" "${BACKUP_FAIL_STAGE}" "${BACKUP_FAIL_SNAPSHOT}"; then
	fail 'failed dnsmasq backup restore reported a successful publication'
fi
grep -qx '# published after failed rollback' "${DNSMASQ_CONF_FILE}" || fail 'failed dnsmasq backup restore changed the published configuration'
grep -qx refreshed "${IPSET_FILE}" || fail 'failed dnsmasq backup restore changed published IPSet state'
grep -qx refreshed "${YAML_FILE}" || fail 'failed dnsmasq backup restore changed published YAML state'
[ -f "${BACKUP_FAIL_FILE}" ] || fail 'failed dnsmasq backup restore discarded the configuration backup'
[ -f "${BACKUP_FAIL_SNAPSHOT}/restore.pending" ] || fail 'failed dnsmasq backup restore discarded the coupled snapshot'
[ -f "${BACKUP_FAIL_SNAPSHOT}/config.pending" ] || fail 'failed dnsmasq backup restore discarded its backup association'
BACKUP_RESTORE_FAIL='0'
MARK_CLEANUP_FAIL='0'
BACKUP_RECOVERY_STAGE="${DNSMASQ_CONF_FILE}.adguard.backup-recovery"
printf '%s\n' '# later transaction' >"${BACKUP_RECOVERY_STAGE}" || fail 'could not stage the later recovery transaction'
IPSET_REFRESH_FAIL='1'
if dnsmasq_publish_staged_config "${DNSMASQ_CONF_FILE}" "${BACKUP_RECOVERY_STAGE}" "${TEST_ROOT}/.AdGuardHome.dnsmasq-ipset.backup-recovery"; then
	fail 'later recovery transaction ignored its injected refresh failure'
fi
grep -qx '# base config' "${DNSMASQ_CONF_FILE}" || fail 'retained dnsmasq backup did not restore the previous configuration'
grep -qx 'previous ipset' "${IPSET_FILE}" || fail 'retained coupled snapshot did not restore IPSet state'
grep -qx 'previous yaml' "${YAML_FILE}" || fail 'retained coupled snapshot did not restore YAML state'
[ ! -e "${BACKUP_FAIL_SNAPSHOT}" ] || fail 'coupled recovery retained its snapshot'

# Unsafe or incomplete pending snapshots are rejected without changing live state.
UNSAFE_SNAPSHOT="${TEST_ROOT}/.AdGuardHome.dnsmasq-ipset.incomplete"
mkdir -m 700 "${UNSAFE_SNAPSHOT}" || fail 'could not create incomplete recovery snapshot'
: >"${UNSAFE_SNAPSHOT}/restore.pending" || fail 'could not mark incomplete recovery snapshot'
printf '%s\n' 'live ipset' >"${IPSET_FILE}" || fail 'could not create incomplete-recovery IPSET fixture'
printf '%s\n' 'live yaml' >"${YAML_FILE}" || fail 'could not create incomplete-recovery YAML fixture'
if IPSet_Lock dnsmasq_ipset_state_recover_pending; then
	fail 'incomplete pending recovery snapshot was accepted'
fi
grep -qx 'live ipset' "${IPSET_FILE}" || fail 'incomplete recovery changed IPSET state'
grep -qx 'live yaml' "${YAML_FILE}" || fail 'incomplete recovery changed YAML state'
rm -rf "${UNSAFE_SNAPSHOT}" || fail 'could not clear incomplete recovery snapshot'

# A YAML publication failure with failed IPSET compensation retains the durable
# recovery journal instead of reporting a successful rollback.
COMPENSATION_SNAPSHOT="${TEST_ROOT}/.AdGuardHome.dnsmasq-ipset.compensation"
printf '%s\n' 'snapshot ipset' >"${IPSET_FILE}" || fail 'could not create compensation IPSET fixture'
printf '%s\n' 'snapshot yaml' >"${YAML_FILE}" || fail 'could not create compensation YAML fixture'
dnsmasq_ipset_state_snapshot "${COMPENSATION_SNAPSHOT}" || fail 'could not create compensation snapshot'
printf '%s\n' 'current ipset' >"${IPSET_FILE}" || fail 'could not change compensation IPSET fixture'
printf '%s\n' 'current yaml' >"${YAML_FILE}" || fail 'could not change compensation YAML fixture'
RESTORE_YAML_FAIL='1'
RESTORE_COMPENSATE_FAIL='1'
if dnsmasq_ipset_state_restore "${COMPENSATION_SNAPSHOT}" 0; then
	fail 'failed YAML restore and IPSET compensation reported success'
fi
[ -f "${COMPENSATION_SNAPSHOT}/restore.pending" ] || fail 'failed compensation discarded the pending marker'
[ -d "${COMPENSATION_SNAPSHOT}" ] || fail 'failed compensation discarded its recovery snapshot'
RESTORE_YAML_FAIL='0'
RESTORE_COMPENSATE_FAIL='0'
IPSet_Lock dnsmasq_ipset_state_recover_pending || fail 'retained compensation snapshot could not recover'
grep -qx 'snapshot ipset' "${IPSET_FILE}" || fail 'retained compensation recovery did not restore IPSET state'
grep -qx 'snapshot yaml' "${YAML_FILE}" || fail 'retained compensation recovery did not restore YAML state'

# Overlapping base and SDN callbacks must serialize snapshot, refresh,
# publication, and compensation as one transaction.
reset_case
FIRST_MARKER="${TEST_ROOT}/first-refresh-active"
FIRST_RELEASE="${TEST_ROOT}/first-refresh-release"
SECOND_MARKER="${TEST_ROOT}/second-refresh-active"
SECOND_STARTED="${TEST_ROOT}/second-transaction-started"
SECOND_WAITING="${TEST_ROOT}/second-transaction-waiting"
FIRST_STAGE="${DNSMASQ_CONF_FILE}.adguard.first"
SECOND_STAGE="${DNSMASQ_SDN_CONF_FILE}.adguard.second"
FIRST_SNAPSHOT="${TEST_ROOT}/.AdGuardHome.dnsmasq-ipset.first"
SECOND_SNAPSHOT="${TEST_ROOT}/.AdGuardHome.dnsmasq-ipset.second"
printf '%s\n' '# first staged config' >"${FIRST_STAGE}" || fail 'could not create first concurrent stage'
printf '%s\n' '# second staged config' >"${SECOND_STAGE}" || fail 'could not create second concurrent stage'
printf '%s\n' 'original ipset' >"${IPSET_FILE}" || fail 'could not create concurrent IPSET fixture'
(
	IPSet_Refresh() {
		printf '%s\n' first >"${IPSET_FILE}"
		printf '%s\n' first >"${YAML_FILE}"
		: >"${FIRST_MARKER}"
		wait_for_release "${FIRST_RELEASE}"
	}
	MV_PUBLISH_FAIL='1'
	dnsmasq_publish_staged_config "${DNSMASQ_CONF_FILE}" "${FIRST_STAGE}" "${FIRST_SNAPSHOT}"
) &
first_pid="$!"
wait_for_file "${FIRST_MARKER}" || fail 'first concurrent transaction did not enter refresh'
(
	IPSet_Refresh() {
		: >"${SECOND_MARKER}"
		printf '%s\n' second >"${IPSET_FILE}"
		printf '%s\n' second >"${YAML_FILE}"
	}
	MV_PUBLISH_FAIL='0'
	IPSET_LOCK_WAIT_MARKER="${SECOND_WAITING}"
	: >"${SECOND_STARTED}"
	dnsmasq_publish_staged_config "${DNSMASQ_SDN_CONF_FILE}" "${SECOND_STAGE}" "${SECOND_SNAPSHOT}"
) &
second_pid="$!"
wait_for_file "${SECOND_STARTED}" || fail 'second concurrent transaction did not start'
wait_for_file "${SECOND_WAITING}" || fail 'second concurrent transaction did not wait for the first lock holder'
[ ! -e "${SECOND_MARKER}" ] || fail 'second callback refreshed state before the first transaction completed'
: >"${FIRST_RELEASE}" || fail 'could not release first concurrent transaction'
first_status=0
wait "${first_pid}" || first_status="$?"
first_pid=""
if [ "${first_status}" -eq 0 ]; then
	fail 'first concurrent publication failure unexpectedly succeeded'
fi
second_status=0
wait "${second_pid}" || second_status="$?"
second_pid=""
[ "${second_status}" -eq 0 ] || fail 'second concurrent transaction failed after waiting for the lock'
grep -qx second "${IPSET_FILE}" || fail 'first compensation overwrote the second callback IPSET state'
grep -qx second "${YAML_FILE}" || fail 'first compensation overwrote the second callback YAML state'
grep -qx '# second staged config' "${DNSMASQ_SDN_CONF_FILE}" || fail 'second callback did not publish its dnsmasq state'

# A nested IPSET lock signal handler must propagate to the outer dnsmasq
# transaction so partially refreshed state is restored.
reset_case
NESTED_MARKER="${TEST_ROOT}/nested-refresh-active"
NESTED_RELEASE="${TEST_ROOT}/nested-refresh-release"
CONFIG_STAGE="${DNSMASQ_CONF_FILE}.signal-nested"
IPSET_SNAPSHOT_DIR="${TEST_ROOT}/.AdGuardHome.dnsmasq-ipset.signal-nested"
printf '%s\n' '# staged config' >"${CONFIG_STAGE}" || fail 'could not create nested signal stage'
printf '%s\n' 'original ipset' >"${IPSET_FILE}" || fail 'could not create nested signal IPSET fixture'
(
	# IPSet_Refresh marks IPSET and YAML state as changed and waits for the nested transaction lock to be released.
	IPSet_Refresh() {
		printf '%s\n' changed >"${IPSET_FILE}"
		printf '%s\n' changed >"${YAML_FILE}"
		trap 'IPSet_Lock_Interrupt_Propagate; exit 1' TERM
		read -r transaction_pid _ </proc/self/stat
		printf '%s\n' "${transaction_pid}" >"${NESTED_MARKER}"
		wait_for_release "${NESTED_RELEASE}" || return 1
	}
	dnsmasq_publish_staged_config "${DNSMASQ_CONF_FILE}" "${CONFIG_STAGE}" "${IPSET_SNAPSHOT_DIR}"
) &
transaction_pid="$!"
wait_for_file "${NESTED_MARKER}" || fail 'nested signal fixture did not enter IPSET refresh'
kill -TERM "$(cat "${NESTED_MARKER}")" || fail 'could not interrupt nested IPSET refresh'
: >"${NESTED_RELEASE}" || fail 'could not release nested IPSET refresh fixture'
if wait "${transaction_pid}"; then
	fail 'nested IPSET refresh interruption unexpectedly succeeded'
fi
grep -qx 'original ipset' "${IPSET_FILE}" || fail 'nested lock signal did not restore IPSET state'
grep -qx 'original yaml' "${YAML_FILE}" || fail 'nested lock signal did not restore YAML state'
[ ! -e "${CONFIG_STAGE}" ] || fail 'nested lock signal retained staged dnsmasq state'
rm -rf "${IPSET_SNAPSHOT_DIR}" || fail 'could not clear nested signal snapshot'

# A signal rollback failure must retain and report its recovery snapshot.
reset_case
SIGNAL_FAIL_MARKER="${TEST_ROOT}/signal-restore-fail-active"
SIGNAL_FAIL_RELEASE="${TEST_ROOT}/signal-restore-fail-release"
CONFIG_STAGE="${DNSMASQ_CONF_FILE}.signal-restore-fail"
IPSET_SNAPSHOT_DIR="${TEST_ROOT}/.AdGuardHome.dnsmasq-ipset.signal-restore-fail"
RESTORE_FAIL='1'
printf '%s\n' '# staged config' >"${CONFIG_STAGE}" || fail 'could not create failed signal restoration stage'
printf '%s\n' 'original ipset' >"${IPSET_FILE}" || fail 'could not create failed signal restoration IPSET fixture'
(
	# IPSet_Refresh marks IPSET and YAML state as changed and waits for the refresh transaction to be released.
	IPSet_Refresh() {
		printf '%s\n' changed >"${IPSET_FILE}"
		printf '%s\n' changed >"${YAML_FILE}"
		read -r transaction_pid _ </proc/self/stat
		printf '%s\n' "${transaction_pid}" >"${SIGNAL_FAIL_MARKER}"
		wait_for_release "${SIGNAL_FAIL_RELEASE}" || return 1
	}
	dnsmasq_publish_staged_config "${DNSMASQ_CONF_FILE}" "${CONFIG_STAGE}" "${IPSET_SNAPSHOT_DIR}"
) &
transaction_pid="$!"
wait_for_file "${SIGNAL_FAIL_MARKER}" || fail 'failed signal restoration fixture did not enter refresh'
kill -TERM "$(cat "${SIGNAL_FAIL_MARKER}")" || fail 'could not interrupt failed signal restoration fixture'
: >"${SIGNAL_FAIL_RELEASE}" || fail 'could not release failed signal restoration fixture'
if wait "${transaction_pid}"; then
	fail 'failed signal restoration unexpectedly succeeded'
fi
[ -d "${IPSET_SNAPSHOT_DIR}" ] || fail 'failed signal restoration discarded its recovery snapshot'
grep -q "state=signal action=restore_ipset result=failed snapshot=${IPSET_SNAPSHOT_DIR}" "${LOG_FILE}" ||
	fail 'failed signal restoration did not report its retained snapshot'
[ ! -e "${CONFIG_STAGE}" ] || fail 'failed signal restoration retained staged dnsmasq state'
rm -rf "${IPSET_SNAPSHOT_DIR}" || fail 'could not clear failed signal restoration snapshot'

# A signal delivered during rollback must not re-enter IPSET restoration.
reset_case
RESTORE_MARKER="${TEST_ROOT}/restore-active"
RESTORE_RELEASE="${TEST_ROOT}/restore-release"
RESTORE_CALLS="${TEST_ROOT}/restore-calls"
CONFIG_STAGE="${DNSMASQ_CONF_FILE}.signal-restore"
IPSET_SNAPSHOT_DIR="${TEST_ROOT}/.AdGuardHome.dnsmasq-ipset.signal-restore"
printf '%s\n' '# staged config' >"${CONFIG_STAGE}" || fail 'could not create signal restoration stage'
(
	# IPSet_Refresh refreshes IPSET state and returns a status indicating whether the operation succeeded.
	IPSet_Refresh() { return 1; }
	# dnsmasq_ipset_state_restore records an IPSET state restoration request and waits for the restoration release signal.
	dnsmasq_ipset_state_restore() {
		printf '%s\n' restore >>"${RESTORE_CALLS}"
		read -r transaction_pid _ </proc/self/stat
		printf '%s\n' "${transaction_pid}" >"${RESTORE_MARKER}"
		wait_for_release "${RESTORE_RELEASE}" || return 1
	}
	dnsmasq_publish_staged_config "${DNSMASQ_CONF_FILE}" "${CONFIG_STAGE}" "${IPSET_SNAPSHOT_DIR}"
) &
transaction_pid="$!"
wait_for_file "${RESTORE_MARKER}" || fail 'signal restoration fixture did not enter rollback'
kill -TERM "$(cat "${RESTORE_MARKER}")" || fail 'could not interrupt active IPSET restoration'
: >"${RESTORE_RELEASE}" || fail 'could not release active IPSET restoration fixture'
if wait "${transaction_pid}"; then
	fail 'signal during IPSET restoration unexpectedly succeeded'
fi
[ "$(wc -l <"${RESTORE_CALLS}")" -eq 1 ] || fail 'signal cleanup re-entered active IPSET restoration'
[ ! -e "${CONFIG_STAGE}" ] || fail 'signal during IPSET restoration retained the staged configuration'
rm -rf "${IPSET_SNAPSHOT_DIR}" || fail 'could not clear signal restoration snapshot'

# A signal after mv publishes the stage must not restore IPSET over published state.
reset_case
PUBLISH_MARKER="${TEST_ROOT}/publish-complete"
PUBLISH_RELEASE="${TEST_ROOT}/publish-release"
RESTORE_CALLS="${TEST_ROOT}/publish-restore-calls"
CONFIG_STAGE="${DNSMASQ_CONF_FILE}.signal-publish"
IPSET_SNAPSHOT_DIR="${TEST_ROOT}/.AdGuardHome.dnsmasq-ipset.signal-publish"
printf '%s\n' '# published config' >"${CONFIG_STAGE}" || fail 'could not create signal publication stage'
(
	# dnsmasq_ipset_state_restore records an IPSET state restoration request.
	dnsmasq_ipset_state_restore() {
		printf '%s\n' restore >>"${RESTORE_CALLS}"
		return 1
	}
	# mv moves files and pauses publication of the dnsmasq configuration until the release marker is available.
	mv() {
		if [ "${1:-}" = "${IPSET_SNAPSHOT_DIR}/restore.pending" ]; then
			return 1
		fi
		command mv "$@" || return 1
		if [ "$1" = "${CONFIG_STAGE}" ] && [ "$2" = "${DNSMASQ_CONF_FILE}" ]; then
			read -r transaction_pid _ </proc/self/stat
			printf '%s\n' "${transaction_pid}" >"${PUBLISH_MARKER}"
			wait_for_release "${PUBLISH_RELEASE}" || return 1
		fi
	}
	dnsmasq_publish_staged_config "${DNSMASQ_CONF_FILE}" "${CONFIG_STAGE}" "${IPSET_SNAPSHOT_DIR}"
) &
transaction_pid="$!"
wait_for_file "${PUBLISH_MARKER}" || fail 'signal publication fixture did not publish the stage'
kill -TERM "$(cat "${PUBLISH_MARKER}")" || fail 'could not interrupt after dnsmasq publication'
: >"${PUBLISH_RELEASE}" || fail 'could not release published dnsmasq fixture'
if wait "${transaction_pid}"; then
	fail 'signal after dnsmasq publication unexpectedly succeeded'
fi
grep -qx '# base config' "${DNSMASQ_CONF_FILE}" || fail 'signal marker failure did not restore dnsmasq'
grep -qx 'restore' "${RESTORE_CALLS}" || fail 'signal marker failure did not attempt IPSET rollback'
[ -f "${IPSET_SNAPSHOT_DIR}/restore.pending" ] || fail 'signal marker failure lost its rollback marker'
IPSet_Lock dnsmasq_ipset_state_recover_pending || fail 'next transaction did not retry signal rollback cleanup'
[ ! -e "${IPSET_SNAPSHOT_DIR}" ] || fail 'retried signal rollback cleanup retained its directory'

printf '%s\n' 'dnsmasq LAN-mode tests passed.'
