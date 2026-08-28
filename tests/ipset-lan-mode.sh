#!/bin/sh
# Verify LAN mode gates service IPSET paths before locks, rewrites, or restarts.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
S99_PATH="${2:-S99AdGuardHome}"
RC_FUNC_PATH="${3:-rc.func.AdGuardHome}"
FUNCTION_FILE="${TMPDIR:-/tmp}/ipset-lan-functions.$$"
CALLS_FILE="${TMPDIR:-/tmp}/ipset-lan-calls.$$"
CONF_FILE="${TMPDIR:-/tmp}/ipset-lan-config.$$"
IPSET_STATE_PATTERN='ADGUARD_IPSET|IPSet_[[:alnum:]_]+|(^|[[:space:];|&()])([^[:space:];|&()]*/)?ipset([[:space:]]|$)'

# cleanup removes temporary test files.
cleanup() {
	rm -f "${FUNCTION_FILE}" "${CALLS_FILE}" "${CONF_FILE}"
}

# fail prints a failure message to stderr and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

[ -f "${S99_PATH}" ] || fail "S99 service script not found: ${S99_PATH}"
[ -f "${RC_FUNC_PATH}" ] || fail "rc.func service script not found: ${RC_FUNC_PATH}"
grep -q '^\[ -z "${SCRIPT_LOC}" \] && \. /jffs/addons/AdGuardHome.d/AdGuardHome.sh$' "${S99_PATH}" ||
	fail 'S99AdGuardHome no longer delegates lifecycle policy to AdGuardHome.sh'
if grep -qE "${IPSET_STATE_PATTERN}" "${S99_PATH}"; then
	fail 'S99AdGuardHome directly manages IPSET enablement instead of delegating to AdGuardHome.sh'
fi
if grep -qE "${IPSET_STATE_PATTERN}" "${RC_FUNC_PATH}"; then
	fail 'rc.func.AdGuardHome directly manages IPSET state'
fi

/bin/sed -n '/^agh_timestamp() {$/,/^}$/p; /^agh_log() {$/,/^}$/p; /^load_operation_config() {$/,/^}$/p; /^adguard_install_mode() {$/,/^}$/p; /^adguard_lan_mode() {$/,/^}$/p; /^adguard_ipset_allowed() {$/,/^}$/p; /^adguard_wan_iptables_state_active() {$/,/^}$/p; /^IPSet_Migrate() {$/,/^}$/p; /^IPSet_Disable_Managed_For_Start_Locked() {$/,/^}$/p; /^IPSet_Enabled() {$/,/^}$/p; /^IPSet_Refresh() {$/,/^}$/p; /^IPSet_Setup_For_Start() {$/,/^}$/p' "${SCRIPT_PATH}" |
	/bin/sed 's#/usr/sbin/iptables#iptables#g; s#/bin/nvram#nvram#g' >"${FUNCTION_FILE}" || fail "could not read ${SCRIPT_PATH}"
sed -n '/^DEFAULT_ADGUARD_[A-Z_]*=/p' "${SCRIPT_PATH}" >>"${FUNCTION_FILE}" || fail 'could not extract runtime defaults'
[ -s "${FUNCTION_FILE}" ] || fail 'LAN IPSET functions were not found'

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

# agh_log records a formatted log entry in the calls file.
agh_log() {
	printf '%s\n' "log $1 $2 $3" >>"${CALLS_FILE}"
}

# IPSet_Disable_Managed records its invocation and returns the configured disable status.
IPSet_Disable_Managed() {
	printf '%s\n' IPSet_Disable_Managed >>"${CALLS_FILE}"
	return "${DISABLE_STATUS:-0}"
}

IPSet_Current_File() {
	printf '%s\n' "${CURRENT_IPSET_FILE:-${IPSET_FILE}}"
}

# IPSet_Lock records its invocation and executes the supplied command.
IPSet_Lock() {
	printf '%s\n' "IPSet_Lock skip_dnsmasq_restart=${ADGUARDHOME_SKIP_DNSMASQ_RESTART:-}" >>"${CALLS_FILE}"
	"$@"
}

# IPSet_Setup_Locked records a locked IPSET setup call and succeeds.
IPSet_Setup_Locked() {
	printf '%s\n' IPSet_Setup_Locked >>"${CALLS_FILE}"
	return 0
}

# IPSet_Supported records that IPSET support was checked and reports success.
IPSet_Supported() {
	printf '%s\n' IPSet_Supported >>"${CALLS_FILE}"
	return 0
}

# lower_script records a lower-script invocation in the call log and succeeds.
lower_script() {
	printf '%s\n' "lower_script $1" >>"${CALLS_FILE}"
	return 0
}

# IPSet_Start_While_Locked records restoration of a running service and succeeds.
IPSet_Start_While_Locked() {
	printf '%s\n' IPSet_Start_While_Locked >>"${CALLS_FILE}"
	return 0
}

# pidof prints a fixed process ID and succeeds.
pidof() {
	printf '%s\n' 1234
	return 0
}

iptables() {
	printf '%s\n' "${WAN_NAT_RULE:-}"
}

nvram() {
	case "$1:$2" in
		get:wan0_ifname) printf '%s\n' 'eth0' ;;
	esac
}

IPSET_FILE=/tmp/ipset.conf
IPSET_USER_FILE=/tmp/ipset.user
YAML_FILE=/tmp/AdGuardHome.yaml
PROCS=AdGuardHome
NAME=AdGuardHome
cat >"${CONF_FILE}" <<'EOF_CONF' || fail 'could not write LAN config'
ADGUARD_INSTALL_MODE="lan"
ADGUARD_IPSET="YES"
EOF_CONF
load_operation_config action || fail 'could not load LAN operation snapshot'
DISABLE_STATUS=0
: >"${CALLS_FILE}"
if IPSet_Enabled; then
	fail 'IPSet_Enabled returned true when .config has LAN mode and IPSET enabled'
fi
[ ! -s "${CALLS_FILE}" ] || fail 'IPSet_Enabled caused side effects in LAN mode'

IPSET_REFRESH_FROM_DNSMASQ=1
ADGUARDHOME_SKIP_DNSMASQ_RESTART='original'
IPSet_Refresh || fail 'LAN refresh did not disable stale managed mappings'
[ "${ADGUARDHOME_SKIP_DNSMASQ_RESTART}" = 'original' ] || fail 'LAN refresh did not restore the dnsmasq restart guard'
ACTUAL="$(cat "${CALLS_FILE}")"
case "${ACTUAL}" in
	*'IPSet_Lock skip_dnsmasq_restart=1'*'lower_script stop'*IPSet_Disable_Managed*IPSet_Start_While_Locked*) : ;;
	*) fail "LAN refresh did not use the locked managed-disable/restart path: ${ACTUAL}" ;;
esac
case "${ACTUAL}" in
	*'reason=topology_disallowed'*) : ;;
	*) fail 'LAN refresh did not log the topology transition' ;;
esac

: >"${CALLS_FILE}"
IPSet_Migrate || fail 'LAN migration did not return success'
[ "$(cat "${CALLS_FILE}")" = 'IPSet_Disable_Managed' ] || fail 'LAN migration did not attempt managed cleanup'

DISABLE_STATUS=1
: >"${CALLS_FILE}"
if IPSet_Migrate; then
	fail 'LAN migration treated failed cleanup as successful'
fi
ACTUAL="$(cat "${CALLS_FILE}")"
case "${ACTUAL}" in
	*IPSet_Disable_Managed*'reason=lan_mode_remove_failed'*) : ;;
	*) fail "LAN migration did not log non-fatal cleanup failure: ${ACTUAL}" ;;
esac

: >"${CALLS_FILE}"
if IPSet_Setup_For_Start; then
	fail 'LAN startup setup treated failed cleanup as non-fatal'
fi
ACTUAL="$(cat "${CALLS_FILE}")"
case "${ACTUAL}" in
	*IPSet_Disable_Managed*'reason=lan_mode_remove_failed'*) : ;;
	*) fail "LAN startup setup did not log fatal cleanup failure: ${ACTUAL}" ;;
esac
case "${ACTUAL}" in
	*IPSet_Lock* | *IPSet_Supported*) fail "LAN startup setup touched lock/support path: ${ACTUAL}" ;;
esac

WAN_NAT_RULE='-A POSTROUTING -o eth0 -j MASQUERADE'
DISABLE_STATUS=0
: >"${CALLS_FILE}"
IPSet_Enabled || fail 'IPSet_Enabled returned false for LAN mode with qualifying WAN NAT state'
IPSet_Refresh || fail 'LAN double-NAT refresh returned failure with supported IPSET'
ACTUAL="$(cat "${CALLS_FILE}")"
case "${ACTUAL}" in
	*IPSet_Supported*IPSet_Lock*) : ;;
	*) fail "LAN double-NAT refresh did not use the supported lock path: ${ACTUAL}" ;;
esac
WAN_NAT_RULE=''

cat >"${CONF_FILE}" <<'EOF_CONF' || fail 'could not write WAN config'
ADGUARD_INSTALL_MODE="wan"
ADGUARD_IPSET="YES"
EOF_CONF
load_operation_config action || fail 'could not load WAN operation snapshot'
: >"${CALLS_FILE}"
IPSet_Enabled || fail 'IPSet_Enabled returned false in WAN mode with IPSET enabled'
IPSet_Refresh || fail 'WAN refresh returned failure with supported IPSET'
ACTUAL="$(cat "${CALLS_FILE}")"
case "${ACTUAL}" in
	*IPSet_Supported*IPSet_Lock*) : ;;
	*) fail "WAN refresh did not preserve supported lock path: ${ACTUAL}" ;;
esac

printf '%s\n' 'PASS: LAN mode gates IPSET on qualifying WAN NAT while WAN mode remains enabled'
