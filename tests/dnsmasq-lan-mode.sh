#!/bin/sh
# Verify dnsmasq postconf LAN-mode gating preserves handoff while skipping IPSET refreshes.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
TEST_ROOT="${TMPDIR:-/tmp}/dnsmasq-lan-mode.$$"
FUNCTIONS_FILE="${TEST_ROOT}/functions"
BIN_DIR="${TEST_ROOT}/bin"
LOG_FILE="${TEST_ROOT}/log"
IPSET_CALLS_FILE="${TEST_ROOT}/ipset-calls"
UMOUNT_CALLS_FILE="${TEST_ROOT}/umount-calls"
DNSMASQ_CONF_FILE="${TEST_ROOT}/dnsmasq.conf"
DNSMASQ_SDN_CONF_FILE="${TEST_ROOT}/dnsmasq-1.conf"

# cleanup removes the test sandbox directory and its contents.
cleanup() {
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
mkdir -p "${BIN_DIR}" || fail 'could not create test directory'

sed -n '/^dnsmasq_delete_matching() {$/,/^interface_ipv4_addr() {$/p' "${SCRIPT_PATH}" | sed '$d' >"${FUNCTIONS_FILE}" ||
	fail 'could not extract dnsmasq helpers'
[ -s "${FUNCTIONS_FILE}" ] || fail 'dnsmasq helper extraction was empty'
# Keep the extracted postconf helper inside the test sandbox instead of touching router paths.
sed -i \
	-e 's|CONFIG="/etc/dnsmasq.conf"|CONFIG="${DNSMASQ_CONF_FILE}"|' \
	-e 's|CONFIG="/etc/dnsmasq-${1}.conf"|CONFIG="${DNSMASQ_SDN_CONF_FILE}"|' \
	"${FUNCTIONS_FILE}" || fail 'could not sandbox dnsmasq config paths'

cat >"${BIN_DIR}/pidof" <<'EOF_PIDOF' || fail 'could not write pidof stub'
#!/bin/sh
case "$1" in
	dnsmasq)
		[ "${DNSMASQ_RUNNING:-0}" = "1" ] && printf '%s\n' 111
		;;
	AdGuardHome)
		[ "${ADGUARD_RUNNING:-0}" = "1" ] && printf '%s\n' 222
		;;
esac
EOF_PIDOF
chmod 700 "${BIN_DIR}/pidof" || fail 'could not make pidof stub executable'
cat >"${BIN_DIR}/umount" <<'EOF_UMOUNT' || fail 'could not write umount stub'
#!/bin/sh
printf '%s\n' "$1" >>"${UMOUNT_CALLS_FILE}"
EOF_UMOUNT
chmod 700 "${BIN_DIR}/umount" || fail 'could not make umount stub executable'
PATH="${BIN_DIR}:${PATH}"
export PATH

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

PROCS='AdGuardHome'
DNS_HANDOFF_ACTIVE='0'
ADGUARD_INSTALL_MODE='wan'
DNSMASQ_RUNNING='0'
ADGUARD_RUNNING='1'
ADGUARD_DNSMASQ_MODE='auto'
RESOLV_CONF_USES_ROM='1'
RESOLV_CONF_TMP_MOUNT='0'
export DNSMASQ_RUNNING ADGUARD_RUNNING UMOUNT_CALLS_FILE

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

# nvram returns the configured value for a supported key when called with the `get` operation.
nvram() {
	[ "$1" = 'get' ] || return 1
	case "$2" in
		rc_support) printf '%s\n' 'mtlancfg' ;;
		lan_ifname) printf '%s\n' 'br0' ;;
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
# The index must be `1`; otherwise, the function returns failure.
sdn_bridge_for_index() {
	[ "$1" = '1' ] || return 1
	printf '%s\n' 'br1'
}

# IPSet_Refresh records an IPSET refresh request for test verification.
IPSet_Refresh() {
	printf '%s\n' "$1" >>"${IPSET_CALLS_FILE}"
}

# reset_case resets test logs, recorded calls, sandboxed dnsmasq configurations, and scenario state to their default values.
reset_case() {
	: >"${LOG_FILE}"
	: >"${IPSET_CALLS_FILE}"
	: >"${UMOUNT_CALLS_FILE}"
	printf '%s\n' '# base config' >"${DNSMASQ_CONF_FILE}" || fail 'could not reset base dnsmasq config'
	printf '%s\n' '# sdn config' >"${DNSMASQ_SDN_CONF_FILE}" || fail 'could not reset sdn dnsmasq config'
	DNS_HANDOFF_ACTIVE='0'
	ADGUARD_INSTALL_MODE='wan'
	DNSMASQ_RUNNING='0'
	ADGUARD_RUNNING='1'
	ADGUARD_DNSMASQ_MODE='auto'
	RESOLV_CONF_USES_ROM='1'
	RESOLV_CONF_TMP_MOUNT='0'
}

# assert_no_ipset_refresh verifies that no IPSET refresh calls were recorded for the test case.
assert_no_ipset_refresh() {
	[ ! -s "${IPSET_CALLS_FILE}" ] || fail "$1: IPSET refresh should not run"
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
dnsmasq_action_handler || fail 'LAN stopped AdGuardHome path failed'
grep -q 'state=skip reason=lan_mode_dnsmasq_not_running' "${LOG_FILE}" ||
	fail 'LAN stopped AdGuardHome path did not log stopped dnsmasq skip reason'
assert_dnsmasq_postconf_not_written "${DNSMASQ_CONF_FILE}" 'LAN stopped AdGuardHome path'
assert_no_ipset_refresh 'LAN stopped AdGuardHome path'

reset_case
ADGUARD_INSTALL_MODE='lan'
DNSMASQ_RUNNING='0'
ADGUARD_DNSMASQ_MODE='disabled'
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
DNS_HANDOFF_ACTIVE='1'
dnsmasq_action_handler || fail 'LAN disabled handoff path failed'
! grep -q 'state=skip reason=lan_mode_dnsmasq_not_running' "${LOG_FILE}" ||
	fail 'LAN disabled handoff path logged stopped dnsmasq skip reason'
assert_dnsmasq_postconf_written "${DNSMASQ_CONF_FILE}" 'LAN disabled handoff path'
assert_no_ipset_refresh 'LAN disabled handoff path'

reset_case
ADGUARD_INSTALL_MODE='lan'
DNSMASQ_RUNNING='1'
ADGUARD_DNSMASQ_MODE='auto'
dnsmasq_action_handler || fail 'LAN running dnsmasq base path failed'
assert_dnsmasq_postconf_written "${DNSMASQ_CONF_FILE}" 'LAN running dnsmasq base path'
assert_resolv_conf_not_unmounted 'LAN running dnsmasq base path'
assert_no_ipset_refresh 'LAN running dnsmasq base path'

reset_case
ADGUARD_INSTALL_MODE='lan'
DNSMASQ_RUNNING='1'
ADGUARD_DNSMASQ_MODE='auto'
dnsmasq_action_handler 1 || fail 'LAN running dnsmasq SDN path failed'
assert_dnsmasq_postconf_written "${DNSMASQ_SDN_CONF_FILE}" 'LAN running dnsmasq SDN path'
assert_no_ipset_refresh 'LAN running dnsmasq SDN path'

reset_case
ADGUARD_INSTALL_MODE='lan'
DNSMASQ_RUNNING='0'
ADGUARD_DNSMASQ_MODE='auto'
dnsmasq_action_handler 1 || fail 'LAN stopped dnsmasq SDN path failed'
grep -q 'state=skip reason=lan_mode_dnsmasq_not_running' "${LOG_FILE}" ||
	fail 'LAN stopped dnsmasq SDN path did not log stopped dnsmasq skip reason'
assert_dnsmasq_postconf_not_written "${DNSMASQ_SDN_CONF_FILE}" 'LAN stopped dnsmasq SDN path'
assert_no_ipset_refresh 'LAN stopped dnsmasq SDN path'

reset_case
ADGUARD_INSTALL_MODE='wan'
DNSMASQ_RUNNING='0'
ADGUARD_DNSMASQ_MODE='auto'
dnsmasq_action_handler || fail 'WAN stopped dnsmasq path failed'
assert_dnsmasq_postconf_written "${DNSMASQ_CONF_FILE}" 'WAN stopped dnsmasq path'
grep -q "${DNSMASQ_CONF_FILE}" "${IPSET_CALLS_FILE}" || fail 'WAN stopped dnsmasq path did not refresh IPSET'

reset_case
ADGUARD_INSTALL_MODE='wan'
DNSMASQ_RUNNING='0'
ADGUARD_RUNNING='0'
ADGUARD_DNSMASQ_MODE='auto'
dnsmasq_action_handler || fail 'WAN stopped AdGuardHome path failed'
assert_dnsmasq_postconf_not_written "${DNSMASQ_CONF_FILE}" 'WAN stopped AdGuardHome path'
assert_no_ipset_refresh 'WAN stopped AdGuardHome path'

reset_case
ADGUARD_INSTALL_MODE='lan'
DNSMASQ_RUNNING='0'
ADGUARD_DNSMASQ_MODE='enabled'
dnsmasq_action_handler || fail 'LAN managed stopped dnsmasq startup path failed'
! grep -q 'state=skip reason=lan_mode_dnsmasq_not_running' "${LOG_FILE}" ||
	fail 'LAN managed stopped dnsmasq startup path logged stopped dnsmasq skip reason'
assert_dnsmasq_postconf_written "${DNSMASQ_CONF_FILE}" 'LAN managed stopped dnsmasq startup path'
assert_no_ipset_refresh 'LAN managed stopped dnsmasq startup path'

reset_case
ADGUARD_INSTALL_MODE='lan'
DNSMASQ_RUNNING='0'
ADGUARD_DNSMASQ_MODE='auto'
DNS_HANDOFF_ACTIVE='1'
ADGUARD_RUNNING='0'
dnsmasq_action_handler || fail 'LAN stopped dnsmasq handoff path failed'
! grep -q 'state=skip reason=lan_mode_dnsmasq_not_running' "${LOG_FILE}" ||
	fail 'LAN stopped dnsmasq handoff path logged stopped dnsmasq skip reason'
assert_dnsmasq_postconf_written "${DNSMASQ_CONF_FILE}" 'LAN stopped dnsmasq handoff path'
assert_no_ipset_refresh 'LAN stopped dnsmasq handoff path'

printf '%s\n' 'dnsmasq LAN-mode tests passed.'
