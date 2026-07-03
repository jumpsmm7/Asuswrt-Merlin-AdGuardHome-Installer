#!/bin/sh
# Verify S99AdGuardHome startup readiness accepts low .config WebUI ports.

set -u

S99_PATH="${1:-S99AdGuardHome}"
TEST_ROOT="${TMPDIR:-/tmp}/s99-startup-readiness.$$"
FUNCTIONS_FILE="${TEST_ROOT}/s99-functions"

cleanup() {
	rm -rf "${TEST_ROOT}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
mkdir -p "${TEST_ROOT}" || fail 'could not create test directory'

sed -n \
	'/^adguardhome_config_valid() {$/,/^}$/p; /^adguardhome_web_port() {$/,/^}$/p; /^adguardhome_web_port_available() {$/,/^}$/p; /^adguardhome_single_process_running() {$/,/^}$/p; /^adguardhome_startup_checks_ready() {$/,/^}$/p' \
	"${S99_PATH}" >"${FUNCTIONS_FILE}" || fail "could not read ${S99_PATH}"
[ -s "${FUNCTIONS_FILE}" ] || fail 'S99 startup readiness functions were not found'
grep -q '^adguardhome_web_port() {$' "${FUNCTIONS_FILE}" || fail 'S99 WebUI port helper was not found'
grep -q '^adguardhome_startup_checks_ready() {$' "${FUNCTIONS_FILE}" || fail 'S99 startup readiness helper was not found'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

PROCS='AdGuardHome'
WORK_DIR="${TEST_ROOT}/AdGuardHome"
mkdir -p "${WORK_DIR}" || fail 'could not create AdGuardHome work directory'
printf '%s\n' 'http:' '  address:' >"${WORK_DIR}/AdGuardHome.yaml" || fail 'could not create YAML stub'
printf '%s\n' 'ADGUARD_WEBUI_PORT="808"' >"${WORK_DIR}/.config" || fail 'could not create config stub'
printf '%s\n' '#!/bin/sh' 'exit 0' >"${WORK_DIR}/AdGuardHome" || fail 'could not create AdGuardHome stub'
chmod 755 "${WORK_DIR}/AdGuardHome" || fail 'could not chmod AdGuardHome stub'

pidof() {
	[ "${1:-}" = AdGuardHome ] || return 1
	printf '%s\n' 321
}

netstat() {
	printf '%s\n' 'tcp 0 0 0.0.0.0:808 0.0.0.0:* LISTEN 321/AdGuardHome'
}

[ "$(adguardhome_web_port)" = 808 ] || fail 'S99 rejected a valid low .config WebUI port'
adguardhome_startup_checks_ready || fail 'S99 startup readiness rejected a valid low .config WebUI port'
