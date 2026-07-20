#!/bin/sh
# Verify LAN mode gates service IPSET paths before locks, rewrites, or restarts.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
FUNCTION_FILE="${TMPDIR:-/tmp}/ipset-lan-functions.$$"
CALLS_FILE="${TMPDIR:-/tmp}/ipset-lan-calls.$$"
CONF_FILE="${TMPDIR:-/tmp}/ipset-lan-config.$$"

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

sed -n '/^agh_timestamp() {$/,/^}$/p; /^agh_log() {$/,/^}$/p; /^conf_value() {$/,/^}$/p; /^adguard_install_mode() {$/,/^}$/p; /^adguard_lan_mode() {$/,/^}$/p; /^adguard_ipset_allowed() {$/,/^}$/p; /^IPSet_Migrate() {$/,/^}$/p; /^IPSet_Enabled() {$/,/^}$/p; /^IPSet_Refresh() {$/,/^}$/p; /^IPSet_Setup_For_Start() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" || fail "could not read ${SCRIPT_PATH}"
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

# IPSet_Lock records its invocation and executes the supplied command.
IPSet_Lock() {
	printf '%s\n' IPSet_Lock >>"${CALLS_FILE}"
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

# pidof prints a fixed process ID and succeeds.
pidof() {
	printf '%s\n' 1234
	return 0
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
DISABLE_STATUS=0
: >"${CALLS_FILE}"
if IPSet_Enabled; then
	fail 'IPSet_Enabled returned true when .config has LAN mode and IPSET enabled'
fi
[ ! -s "${CALLS_FILE}" ] || fail 'IPSet_Enabled caused side effects in LAN mode'

IPSet_Refresh || fail 'LAN refresh did not return success'
ACTUAL="$(cat "${CALLS_FILE}")"
case "${ACTUAL}" in
	*IPSet_Lock* | *IPSet_Supported* | *lower_script*) fail "LAN refresh touched managed path: ${ACTUAL}" ;;
esac
case "${ACTUAL}" in
	*'reason=lan_mode'*) : ;;
	*) fail 'LAN refresh did not log skip reason' ;;
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

cat >"${CONF_FILE}" <<'EOF_CONF' || fail 'could not write WAN config'
ADGUARD_INSTALL_MODE="wan"
ADGUARD_IPSET="YES"
EOF_CONF
: >"${CALLS_FILE}"
IPSet_Enabled || fail 'IPSet_Enabled returned false in WAN mode with IPSET enabled'
IPSet_Refresh || fail 'WAN refresh returned failure with supported IPSET'
ACTUAL="$(cat "${CALLS_FILE}")"
case "${ACTUAL}" in
	*IPSet_Supported*IPSet_Lock*) : ;;
	*) fail "WAN refresh did not preserve supported lock path: ${ACTUAL}" ;;
esac

printf '%s\n' 'PASS: LAN mode skips IPSET locks, rewrites, and restarts while WAN mode remains unchanged'
