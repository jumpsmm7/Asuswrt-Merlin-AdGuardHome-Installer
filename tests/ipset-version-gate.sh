#!/bin/sh
# Verify managed IPSET integration is enabled only for compatible AdGuardHome versions.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ipset-version-gate.XXXXXX")" || {
	printf '%s\n' 'FAIL: could not create exclusive test directory' >&2
	exit 1
}
FUNCTION_FILE="${TEST_ROOT}/functions"
BINARY_FILE="${TEST_ROOT}/AdGuardHome"
CALLS_FILE="${TEST_ROOT}/calls"
IPSET_FILE="${TEST_ROOT}/managed-ipset"

# cleanup removes the temporary test directory and its contents.
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

sed -n '/^agh_timestamp() {$/,/^}$/p; /^agh_log() {$/,/^}$/p; /^IPSet_Enabled() {$/,/^}$/p; /^IPSet_Refresh() {$/,/^}$/p; /^IPSet_Refresh_After_Recovery() {$/,/^}$/p; /^IPSet_Setup() {$/,/^}$/p; /^IPSet_Setup_For_Start() {$/,/^}$/p; /^IPSet_Supported() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" || fail "could not read ${SCRIPT_PATH}"
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

# conf_value prints the configured IPSET value, defaulting to YES when IPSET_CONFIG is unset.
conf_value() {
	printf '%s\n' "${IPSET_CONFIG:-YES}"
}

# adguard_lan_mode determines whether the installation is configured for LAN mode.
adguard_lan_mode() {
	[ "${INSTALL_MODE:-wan}" = "lan" ]
}

# adguard_ipset_allowed determines whether managed IPSET integration is allowed for the current installation mode.
adguard_ipset_allowed() {
	! adguard_lan_mode
}

# IPSet_Current_File reports the path of the active managed IPSET fixture file.
IPSet_Current_File() {
	printf '%s\n' "${IPSET_FILE}"
}

# IPSet_Disable_Managed records the managed IPSET disable operation, removes its state file when successful, and returns the configured status.
IPSet_Disable_Managed() {
	printf '%s\n' IPSet_Disable_Managed >>"${CALLS_FILE}"
	[ "${DISABLE_STATUS:-0}" -eq 0 ] && rm -f "${IPSET_FILE}"
	return "${DISABLE_STATUS:-0}"
}

# IPSet_Lock records a lock request for the specified IPSET operation.
IPSet_Lock() {
	local lock_status
	if [ "$1" = "IPSet_Refresh_After_Recovery" ]; then
		IPSET_LOCK_ACTIVE=1
		"$@"
		lock_status="$?"
		IPSET_LOCK_ACTIVE=0
		return "${lock_status}"
	fi
	printf '%s\n' "lock $1" >>"${CALLS_FILE}"
}

# dnsmasq_ipset_state_recover_pending provides successful pending-state recovery for version-gate cases.
dnsmasq_ipset_state_recover_pending() { return 0; }

logger() {
	:
}

# run_start_case exercises startup IPSET gating and verifies the resulting calls and status for a simulated AdGuardHome version.
run_start_case() {
	VERSION_OUTPUT="$1"
	VERSION_STATUS="${2:-0}"
	EXPECTED="$3"
	EXPECTED_STATUS="${4:-0}"
	export VERSION_OUTPUT VERSION_STATUS
	: >"${CALLS_FILE}"

	if IPSet_Setup_For_Start; then
		ACTUAL_STATUS=0
	else
		ACTUAL_STATUS=$?
	fi
	[ "${ACTUAL_STATUS}" -eq "${EXPECTED_STATUS}" ] || fail "startup setup returned ${ACTUAL_STATUS}, expected ${EXPECTED_STATUS} for version output: ${VERSION_OUTPUT}"

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
CONFIG_IPSET="${IPSET_CONFIG}"
run_start_case 'AdGuard Home, version v0.107.48' 0 'lock IPSet_Disable_Managed_For_Start_Locked'
IPSET_CONFIG=YES
CONFIG_IPSET="${IPSET_CONFIG}"
INSTALL_MODE=lan
: >"${IPSET_FILE}" || fail 'could not create managed IPSET fixture'
run_case 'AdGuard Home, version v0.107.48' 0 'lock IPSet_Disable_Managed_For_Start_Locked'
: >"${IPSET_FILE}" || fail 'could not recreate managed IPSET fixture for startup'
run_start_case 'AdGuard Home, version v0.107.48' 0 'IPSet_Disable_Managed'
[ ! -e "${IPSET_FILE}" ] || fail 'rejected LAN setup retained managed IPSET state'
: >"${IPSET_FILE}" || fail 'could not reset managed IPSET fixture'
DISABLE_STATUS=1
run_start_case 'AdGuard Home, version v0.107.48' 0 'IPSet_Disable_Managed' 1
[ -e "${IPSET_FILE}" ] || fail 'failed managed IPSET disable removed the fixture'
DISABLE_STATUS=0
INSTALL_MODE=wan

printf '%s\n' 'PASS: managed IPSET integration is gated on AdGuardHome v0.107.48 or later'
