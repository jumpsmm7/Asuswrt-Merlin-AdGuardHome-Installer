#!/bin/sh
# Verify AdGuardHome service launches cannot inherit the NVRAM transaction lock descriptor.

set -u

INSTALLER_PATH="${1:-installer}"

# fail prints an error message to standard error and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

TEST_ROOT="$(mktemp -d)" || fail 'could not create test workspace'
FUNCTIONS_FILE="${TEST_ROOT}/functions"

# cleanup removes the temporary test workspace.
cleanup() { rm -rf "${TEST_ROOT}"; }
trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

sed -n '/^adguard_service_without_nvram_lock_fd() {$/,/^}$/p' "${INSTALLER_PATH}" >"${FUNCTIONS_FILE}" ||
	fail 'could not extract service descriptor helper'
[ -s "${FUNCTIONS_FILE}" ] || fail 'service descriptor helper was not found'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

exec 8>"${TEST_ROOT}/nvram.lock" || fail 'could not open simulated NVRAM lock descriptor'
adguard_service_without_nvram_lock_fd sh -c '
	[ ! -e "/proc/$$/fd/8" ] || exit 1
	printf "%s\n" launched >"$1"
' sh "${TEST_ROOT}/launched" || fail 'service command inherited descriptor 8'
[ "$(cat "${TEST_ROOT}/launched" 2>/dev/null)" = launched ] || fail 'service command was not executed'
[ -e "/proc/$$/fd/8" ] || fail 'helper closed the installer lock descriptor'

if adguard_service_without_nvram_lock_fd sh -c 'exit 23'; then
	fail 'helper hid a failing service command'
else
	[ "$?" -eq 23 ] || fail 'helper changed the service command status'
fi

service_launches="$(grep -Ec '(^|[[:space:]])(service (start|restart)_AdGuardHome|/opt/etc/init.d/S99AdGuardHome (start|restart))([[:space:];]|$)' "${INSTALLER_PATH}")"
protected_launches="$(grep -Ec 'adguard_service_without_nvram_lock_fd (service (start|restart)_AdGuardHome|/opt/etc/init.d/S99AdGuardHome (start|restart))([[:space:];]|$)' "${INSTALLER_PATH}")"
[ "${service_launches}" -gt 0 ] || fail 'no AdGuardHome service launch was found; the coverage pattern is stale'
[ "${service_launches}" -eq "${protected_launches}" ] || fail 'an AdGuardHome service launch bypasses descriptor isolation'

printf '%s\n' 'Installer service lock descriptor tests passed.'
