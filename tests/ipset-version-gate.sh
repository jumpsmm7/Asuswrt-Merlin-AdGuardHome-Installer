#!/bin/sh
# Verify managed IPSET integration is enabled only for compatible AdGuardHome versions.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
FUNCTION_FILE="${TMPDIR:-/tmp}/ipset-version-functions.$$"
BINARY_FILE="${TMPDIR:-/tmp}/AdGuardHome-version-test.$$"
CALLS_FILE="${TMPDIR:-/tmp}/ipset-version-calls.$$"

cleanup() {
	rm -f "${FUNCTION_FILE}" "${BINARY_FILE}" "${CALLS_FILE}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

sed -n '/^agh_timestamp() {$/,/^}$/p; /^agh_log() {$/,/^}$/p; /^IPSet_Enabled() {$/,/^}$/p; /^IPSet_Refresh() {$/,/^}$/p; /^IPSet_Setup() {$/,/^}$/p; /^IPSet_Setup_For_Start() {$/,/^}$/p; /^IPSet_Supported() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" || fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTION_FILE}" ] || fail 'IPSET version-gate functions were not found'

cat >"${BINARY_FILE}" <<'BINARY'
#!/bin/sh
[ "$1" = '--version' ] || exit 2
[ "${VERSION_STATUS:-0}" -eq 0 ] || exit "${VERSION_STATUS}"
printf '%s\n' "${VERSION_OUTPUT}"
BINARY
chmod +x "${BINARY_FILE}" || fail 'could not create version test binary'

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

conf_value() {
	printf '%s\n' "${IPSET_CONFIG:-YES}"
}

adguard_lan_mode() {
	[ "${INSTALL_MODE:-wan}" = "lan" ]
}

adguard_ipset_allowed() {
	! adguard_lan_mode
}

IPSet_Disable_Managed() {
	printf '%s\n' IPSet_Disable_Managed >>"${CALLS_FILE}"
	return 0
}

IPSet_Lock() {
	printf '%s\n' "lock $1" >>"${CALLS_FILE}"
}

logger() {
	:
}

run_start_case() {
	VERSION_OUTPUT="$1"
	VERSION_STATUS="${2:-0}"
	export VERSION_OUTPUT VERSION_STATUS
	EXPECTED="$3"
	: >"${CALLS_FILE}"

	IPSet_Setup_For_Start || fail "startup setup failed for version output: ${VERSION_OUTPUT}"

	ACTUAL="$(cat "${CALLS_FILE}")"
	[ "${ACTUAL}" = "${EXPECTED}" ] || fail "unexpected startup gate result for ${VERSION_OUTPUT}: ${ACTUAL}"
}

run_case() {
	VERSION_OUTPUT="$1"
	VERSION_STATUS="${2:-0}"
	export VERSION_OUTPUT VERSION_STATUS
	EXPECTED="$3"
	: >"${CALLS_FILE}"

	IPSet_Setup || fail "setup failed for version output: ${VERSION_OUTPUT}"
	IPSet_Refresh || fail "refresh failed for version output: ${VERSION_OUTPUT}"

	ACTUAL="$(cat "${CALLS_FILE}")"
	[ "${ACTUAL}" = "${EXPECTED}" ] || fail "unexpected gate result for ${VERSION_OUTPUT}: ${ACTUAL}"
}

ADGUARDHOME_BINARY="${BINARY_FILE}"
NAME=AdGuardHome
PROCS=AdGuardHome

run_case 'AdGuard Home, version v0.107.12' 0 ''
run_case 'AdGuard Home, version v0.107.13' 0 ''
run_case 'AdGuard Home, version v0.107.47' 0 ''
run_case 'AdGuard Home, version v0.107.48' 0 'lock IPSet_Setup_Locked
lock IPSet_Setup_Locked'
run_case 'AdGuard Home, version v0.107.76' 0 'lock IPSet_Setup_Locked
lock IPSet_Setup_Locked'
run_case 'AdGuard Home, version v0.108.0-b.5' 0 'lock IPSet_Setup_Locked
lock IPSet_Setup_Locked'
run_case 'unknown version' 0 ''
run_case 'AdGuard Home unavailable' 1 ''

run_start_case 'AdGuard Home, version v0.107.12' 0 'lock IPSet_Disable_Managed_For_Start_Locked'
run_start_case 'AdGuard Home, version v0.107.47' 0 'lock IPSet_Disable_Managed_For_Start_Locked'
run_start_case 'AdGuard Home, version v0.107.48' 0 'lock IPSet_Setup_For_Start_Locked'
run_start_case 'unknown version' 0 ''
run_start_case 'AdGuard Home unavailable' 1 ''
IPSET_CONFIG=NO
run_start_case 'AdGuard Home, version v0.107.48' 0 'lock IPSet_Disable_Managed_For_Start_Locked'
IPSET_CONFIG=YES
INSTALL_MODE=lan
run_case 'AdGuard Home, version v0.107.48' 0 ''
run_start_case 'AdGuard Home, version v0.107.48' 0 'IPSet_Disable_Managed'
INSTALL_MODE=wan

printf '%s\n' 'PASS: managed IPSET integration is gated on AdGuardHome v0.107.48 or later'
