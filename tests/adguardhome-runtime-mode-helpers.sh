#!/bin/sh
# Verify AdGuardHome runtime mode helpers default safely and honor explicit settings.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
TEST_ROOT="${TMPDIR:-/tmp}/adguardhome-runtime-mode-helpers.$$"
FUNCTIONS_FILE="${TEST_ROOT}/functions"

cleanup() {
	rm -rf "${TEST_ROOT}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

write_conf() {
	: >"${CONF_FILE}" || fail 'could not reset config file'
	while [ "$#" -gt 0 ]; do
		printf '%s\n' "$1" >>"${CONF_FILE}" || fail 'could not write config value'
		shift
	done
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
mkdir -p "${TEST_ROOT}" || fail 'could not create test directory'

sed -n \
	'/^conf_value() {$/,/^}$/p; /^adguard_install_mode() {$/,/^}$/p; /^adguard_lan_mode() {$/,/^}$/p; /^adguard_dnsmasq_running() {$/,/^}$/p; /^adguard_dnsmasq_managed() {$/,/^}$/p; /^adguard_restart_dnsmasq_if_managed() {$/,/^}$/p; /^adguard_ipset_allowed() {$/,/^}$/p' \
	"${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" || fail "could not read ${SCRIPT_PATH}"
grep -q '^adguard_ipset_allowed() {$' "${FUNCTIONS_FILE}" || fail 'runtime mode helpers missing'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

pidof() {
	case "${DNSMASQ_RUNNING:-0}" in
		1)
			printf '%s\n' '1234'
			return 0
			;;
		*) return 1 ;;
	esac
}

service() {
	[ "$1" = 'restart_dnsmasq' ] || fail "unexpected service action: $*"
	SERVICE_RESTART_COUNT="$((SERVICE_RESTART_COUNT + 1))"
	return "${SERVICE_RESTART_STATUS:-0}"
}

assert_restart_count() {
	[ "${SERVICE_RESTART_COUNT}" = "$1" ] || fail "$2"
}

CONF_FILE="${TEST_ROOT}/AdGuardHome.config"
SERVICE_RESTART_COUNT=0

rm -f "${CONF_FILE}"
[ "$(adguard_install_mode)" = 'wan' ] || fail 'missing config did not default install mode to wan'
! adguard_lan_mode || fail 'missing config should not be LAN mode'
adguard_ipset_allowed || fail 'missing config should allow IPSET'

write_conf 'ADGUARD_INSTALL_MODE=lan'
[ "$(adguard_install_mode)" = 'lan' ] || fail 'lan install mode was not returned'
adguard_lan_mode || fail 'lan install mode was not detected'
! adguard_ipset_allowed || fail 'lan install mode should not allow IPSET'

write_conf 'ADGUARD_INSTALL_MODE=unexpected'
[ "$(adguard_install_mode)" = 'wan' ] || fail 'invalid install mode did not default to wan'
! adguard_lan_mode || fail 'invalid install mode should not be LAN mode'
adguard_ipset_allowed || fail 'invalid install mode should allow IPSET'

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

DNSMASQ_RUNNING=0
SERVICE_RESTART_COUNT=0
write_conf 'ADGUARD_DNSMASQ_MODE=enabled'
adguard_restart_dnsmasq_if_managed || fail 'enabled dnsmasq restart should succeed even without pidof match'
assert_restart_count 1 'enabled dnsmasq mode should restart dnsmasq'

DNSMASQ_RUNNING=1
SERVICE_RESTART_COUNT=0
write_conf 'ADGUARD_DNSMASQ_MODE=disabled'
adguard_restart_dnsmasq_if_managed || fail 'disabled dnsmasq restart should be skipped successfully'
assert_restart_count 0 'disabled dnsmasq mode should not restart dnsmasq'

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
