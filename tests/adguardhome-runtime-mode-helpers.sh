#!/bin/sh
# Verify AdGuardHome runtime mode helpers default safely and honor explicit settings.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/adguardhome-runtime-mode-helpers.XXXXXX")" || {
	printf '%s\n' 'FAIL: could not create exclusive test directory' >&2
	exit 1
}
FUNCTIONS_FILE="${TEST_ROOT}/functions"

# cleanup removes the temporary test directory and its contents.
cleanup() {
	rm -rf "${TEST_ROOT}"
}

# fail prints a failure message to standard error and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

# write_conf resets the configuration file, writes the provided configuration lines, and reloads the operation configuration.
write_conf() {
	: >"${CONF_FILE}" || fail 'could not reset config file'
	while [ "$#" -gt 0 ]; do
		printf '%s\n' "$1" >>"${CONF_FILE}" || fail 'could not write config value'
		shift
	done
	load_operation_config action || return 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
/bin/sed -n \
	'/^load_operation_config() {$/,/^}$/p; /^adguard_install_mode() {$/,/^}$/p; /^adguard_lan_mode() {$/,/^}$/p; /^adguard_dnsmasq_running() {$/,/^}$/p; /^adguard_dnsmasq_managed() {$/,/^}$/p; /^adguard_restart_dnsmasq_if_managed() {$/,/^}$/p; /^adguard_ipset_allowed() {$/,/^}$/p; /^adguard_wan_iptables_state_active() {$/,/^}$/p; /^IPSet_Dnsmasq_Restart_After_Unlock() {$/,/^}$/p' \
	"${SCRIPT_PATH}" | /bin/sed 's#/usr/sbin/iptables#iptables#g; s#/bin/nvram#nvram#g' >"${FUNCTIONS_FILE}" || fail "could not read ${SCRIPT_PATH}"
sed -n '/^DEFAULT_ADGUARD_[A-Z_]*=/p' "${SCRIPT_PATH}" >>"${FUNCTIONS_FILE}" || fail 'could not extract runtime defaults'
/bin/grep -q '^adguard_ipset_allowed() {$' "${FUNCTIONS_FILE}" || fail 'runtime mode helpers missing'
/bin/grep -q '^IPSet_Dnsmasq_Restart_After_Unlock() {$' "${FUNCTIONS_FILE}" || fail 'IPSET dnsmasq restart helper missing'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

# pidof reports a fixed process ID when simulated dnsmasq is running.
pidof() {
	case "${DNSMASQ_RUNNING:-0}" in
		1)
			printf '%s\n' '1234'
			return 0
			;;
		*) return 1 ;;
	esac
}

# iptables prints the configured simulated WAN NAT rule.
iptables() {
	[ "$*" = '-t nat -S POSTROUTING' ] || fail "unexpected iptables query: $*"
	[ "${IPTABLES_FAIL:-0}" -eq 0 ] || return 1
	printf '%s\n' "${WAN_NAT_RULE:-}"
}

# nvram supplies fixed WAN, gateway, and PPPoE interface names for the test environment.
nvram() {
	case "$1:$2" in
		get:wan0_ifname) printf '%s\n' 'eth0' ;;
		get:wan0_gw_ifname) printf '%s\n' 'eth1' ;;
		get:wan0_pppoe_ifname) printf '%s\n' 'ppp0' ;;
		get:wan1_ifname) printf '%s\n' 'eth2' ;;
		get:wan1_gw_ifname) printf '%s\n' 'eth3' ;;
		get:wan1_pppoe_ifname) printf '%s\n' 'ppp1' ;;
	esac
}

# service simulates the dnsmasq restart service action and records its invocation status.
service() {
	[ "$1" = 'restart_dnsmasq' ] || fail "unexpected service action: $*"
	SERVICE_RESTART_COUNT="$((SERVICE_RESTART_COUNT + 1))"
	return "${SERVICE_RESTART_STATUS:-0}"
}

# assert_restart_count verifies the recorded dnsmasq restart count matches the expected count and fails with the supplied message otherwise.
assert_restart_count() {
	[ "${SERVICE_RESTART_COUNT}" = "$1" ] || fail "$2"
}

CONF_FILE="${TEST_ROOT}/AdGuardHome.config"
NAME='runtime-mode-test'
SERVICE_RESTART_COUNT=0

rm -f "${CONF_FILE}"
load_operation_config action || fail 'missing config snapshot failed'
[ "$(adguard_install_mode)" = 'wan' ] || fail 'missing config did not default install mode to wan'
! adguard_lan_mode || fail 'missing config should not be LAN mode'
adguard_ipset_allowed || fail 'missing config did not load the WAN default for IPSET'

write_conf 'ADGUARD_INSTALL_MODE=lan'
[ "$(adguard_install_mode)" = 'lan' ] || fail 'lan install mode was not returned'
adguard_lan_mode || fail 'lan install mode was not detected'
! adguard_ipset_allowed || fail 'lan install mode should not allow IPSET'
WAN_NAT_RULE='-A POSTROUTING -o eth0 -j MASQUERADE'
adguard_ipset_allowed || fail 'LAN install mode with WAN NAT state should allow IPSET'
WAN_NAT_RULE='-A POSTROUTING ! -o eth0 -j MASQUERADE'
! adguard_ipset_allowed || fail 'LAN install mode with negated WAN NAT state should not allow IPSET'
WAN_NAT_RULE='-A POSTROUTING -s 192.168.50.0/24 -o eth0 -j MASQUERADE'
adguard_ipset_allowed || fail 'LAN install mode with source-scoped WAN NAT state should allow IPSET'
WAN_NAT_RULE='-A POSTROUTING --source 192.168.50.0/24 -o eth0 -j SNAT --to-source 192.0.2.1'
adguard_ipset_allowed || fail 'LAN install mode with long-form source-scoped WAN NAT state should allow IPSET'
WAN_NAT_RULE='-A POSTROUTING -i br1 -o eth0 -j MASQUERADE'
! adguard_ipset_allowed || fail 'LAN install mode with guest-network input-interface NAT state should not allow IPSET'
WAN_NAT_RULE='-A POSTROUTING -m comment --comment "-o eth0 -j MASQUERADE" -o br0 -j ACCEPT'
! adguard_wan_iptables_state_active || fail 'WAN interface text inside a comment qualified as WAN NAT state'
WAN_NAT_RULE='-A POSTROUTING -o eth1 -j MASQUERADE'
adguard_wan_iptables_state_active || fail 'wan0 gateway interface did not qualify as WAN NAT state'
WAN_NAT_RULE='-A POSTROUTING -o ppp0 -j MASQUERADE'
adguard_wan_iptables_state_active || fail 'wan0 PPPoE interface did not qualify as WAN NAT state'
WAN_NAT_RULE='-A POSTROUTING -o eth2 -j MASQUERADE'
adguard_wan_iptables_state_active || fail 'wan1 interface did not qualify as WAN NAT state'
WAN_NAT_RULE='-A POSTROUTING -o eth3 -j SNAT --to-source 192.0.2.1'
adguard_wan_iptables_state_active || fail 'wan1 gateway interface did not qualify as WAN NAT state'
WAN_NAT_RULE='-A POSTROUTING -o ppp1 -j MASQUERADE'
adguard_wan_iptables_state_active || fail 'wan1 PPPoE interface did not qualify as WAN NAT state'
WAN_NAT_RULE=''
IPTABLES_FAIL=1
! adguard_ipset_allowed || fail 'LAN install mode allowed IPSET when iptables was unavailable'
IPTABLES_FAIL=0

CONFIG_INSTALL_MODE='ap'
! adguard_ipset_allowed || fail 'AP install mode without WAN NAT state should not allow IPSET'
WAN_NAT_RULE='-A POSTROUTING -o eth0 -j SNAT --to-source 192.0.2.1'
adguard_ipset_allowed || fail 'AP install mode with WAN NAT state should allow IPSET'
CONFIG_INSTALL_MODE='bridge'
adguard_ipset_allowed || fail 'bridge install mode with WAN NAT state should allow IPSET'
WAN_NAT_RULE=''
! adguard_ipset_allowed || fail 'bridge install mode without WAN NAT state should not allow IPSET'
CONFIG_INSTALL_MODE='unexpected'
! adguard_ipset_allowed || fail 'unsupported install mode should not allow IPSET'
CONFIG_INSTALL_MODE=''
! adguard_ipset_allowed || fail 'empty install mode should not allow IPSET'
unset CONFIG_INSTALL_MODE

if write_conf 'ADGUARD_INSTALL_MODE=unexpected'; then
	fail 'invalid install mode was accepted'
fi
write_conf || fail 'could not restore default snapshot'

DNSMASQ_RUNNING=0
write_conf
! adguard_dnsmasq_running || fail 'dnsmasq running helper ignored missing pid'
! adguard_dnsmasq_managed || fail 'dnsmasq management fallback ignored missing pid'

DNSMASQ_RUNNING=1
adguard_dnsmasq_running || fail 'dnsmasq running helper did not accept pidof success'
adguard_dnsmasq_managed || fail 'dnsmasq management fallback did not accept running service'

DNSMASQ_RUNNING=1
write_conf 'ADGUARD_DNSMASQ_MODE=disabled'
! adguard_dnsmasq_managed || fail 'disabled dnsmasq mode should override running service'

DNSMASQ_RUNNING=0
write_conf 'ADGUARD_DNSMASQ_MODE=enabled'
adguard_dnsmasq_managed || fail 'enabled dnsmasq mode should override missing service'

DNSMASQ_RUNNING=0
SERVICE_RESTART_COUNT=0
write_conf 'ADGUARD_INSTALL_MODE=lan'
adguard_restart_dnsmasq_if_managed || fail 'unmanaged LAN restart should be skipped successfully'
assert_restart_count 0 'unmanaged LAN restart should not call service'

DNSMASQ_RUNNING=1
SERVICE_RESTART_COUNT=0
write_conf 'ADGUARD_INSTALL_MODE=lan'
adguard_restart_dnsmasq_if_managed || fail 'running LAN dnsmasq restart should succeed'
assert_restart_count 1 'running LAN dnsmasq should be restarted'

DNSMASQ_RUNNING=1
write_conf 'ADGUARD_INSTALL_MODE=lan'
adguard_dnsmasq_managed || fail 'running LAN dnsmasq without an explicit mode should be managed by default'

DNSMASQ_RUNNING=1
write_conf 'ADGUARD_INSTALL_MODE=lan' 'ADGUARD_DNSMASQ_MODE=disabled'
! adguard_dnsmasq_managed || fail 'disabled dnsmasq mode should override a running LAN dnsmasq'

DNSMASQ_RUNNING=1
write_conf 'ADGUARD_INSTALL_MODE=lan' 'ADGUARD_DNSMASQ_MODE=enabled'
adguard_dnsmasq_managed || fail 'enabled dnsmasq mode should keep a running LAN dnsmasq managed'

DNSMASQ_RUNNING=0
SERVICE_RESTART_COUNT=0
write_conf 'ADGUARD_DNSMASQ_MODE=enabled'
adguard_restart_dnsmasq_if_managed || fail 'enabled WAN dnsmasq restart should succeed even without pidof match'
assert_restart_count 1 'enabled WAN dnsmasq mode should restart dnsmasq'

DNSMASQ_RUNNING=0
SERVICE_RESTART_COUNT=0
write_conf 'ADGUARD_INSTALL_MODE=lan' 'ADGUARD_DNSMASQ_MODE=enabled'
adguard_restart_dnsmasq_if_managed || fail 'enabled LAN restart without dnsmasq should be skipped successfully'
assert_restart_count 0 'enabled LAN restart without dnsmasq should not call service'

DNSMASQ_RUNNING=1
SERVICE_RESTART_COUNT=0
write_conf 'ADGUARD_DNSMASQ_MODE=disabled'
adguard_restart_dnsmasq_if_managed || fail 'disabled dnsmasq restart should be skipped successfully'
assert_restart_count 0 'disabled dnsmasq mode should not restart dnsmasq'

DNSMASQ_RUNNING=0
SERVICE_RESTART_COUNT=0
IPSET_DNSMASQ_RESTART_PENDING=1
write_conf 'ADGUARD_INSTALL_MODE=lan' 'ADGUARD_DNSMASQ_MODE=enabled'
IPSet_Dnsmasq_Restart_After_Unlock || fail 'IPSET pending unlock restart should succeed'
assert_restart_count 1 'IPSET pending unlock restart should call service even if dnsmasq is stopped'
[ "${IPSET_DNSMASQ_RESTART_PENDING}" -eq 0 ] || fail 'IPSET pending unlock did not clear restart pending flag'

DNSMASQ_RUNNING=0
SERVICE_RESTART_COUNT=0
IPSET_DNSMASQ_RESTART_PENDING=1
ADGUARDHOME_SKIP_DNSMASQ_RESTART=1
write_conf
IPSet_Dnsmasq_Restart_After_Unlock || fail 'IPSET pending unlock with skip should be skipped successfully'
assert_restart_count 0 'IPSET pending unlock with skip should not call service'
[ "${IPSET_DNSMASQ_RESTART_PENDING}" -eq 0 ] || fail 'IPSET pending unlock with skip did not clear restart pending flag'
unset ADGUARDHOME_SKIP_DNSMASQ_RESTART

DNSMASQ_RUNNING=1
SERVICE_RESTART_COUNT=0
IPSET_DNSMASQ_RESTART_PENDING=1
write_conf 'ADGUARD_INSTALL_MODE=lan'
IPSet_Dnsmasq_Restart_After_Unlock || fail 'IPSET LAN unlock with dnsmasq should restart successfully'
assert_restart_count 1 'IPSET LAN unlock with dnsmasq should call service'
[ "${IPSET_DNSMASQ_RESTART_PENDING}" -eq 0 ] || fail 'IPSET LAN restart did not clear restart pending flag'

DNSMASQ_RUNNING=1
SERVICE_RESTART_COUNT=0
SERVICE_RESTART_STATUS=1
write_conf
if adguard_restart_dnsmasq_if_managed; then
	fail 'managed dnsmasq restart failure was not propagated'
fi
assert_restart_count 1 'managed dnsmasq restart failure should call service once'
SERVICE_RESTART_STATUS=0

printf '%s\n' 'PASS: AdGuardHome runtime mode helpers honor config defaults and dnsmasq overrides'
