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
	'/^adguardhome_config_valid() {$/,/^}$/p; /^adguardhome_web_port() {$/,/^}$/p; /^adguardhome_web_port_owned_status() {$/,/^}$/p; /^adguardhome_web_port_available() {$/,/^}$/p; /^adguardhome_single_process_running() {$/,/^}$/p; /^adguardhome_startup_checks_ready() {$/,/^}$/p; /^wait_for_adguardhome_startup_checks_failure_reason() {$/,/^}$/p' \
	"${S99_PATH}" >"${FUNCTIONS_FILE}" || fail "could not read ${S99_PATH}"
[ -s "${FUNCTIONS_FILE}" ] || fail 'S99 startup readiness functions were not found'
grep -q '^adguardhome_web_port() {$' "${FUNCTIONS_FILE}" || fail 'S99 WebUI port helper was not found'
grep -q '^adguardhome_startup_checks_ready() {$' "${FUNCTIONS_FILE}" || fail 'S99 startup readiness helper was not found'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

PROCS='AdGuardHome'
WORK_DIR="${TEST_ROOT}/AdGuardHome"
mkdir -p "${WORK_DIR}" || fail 'could not create AdGuardHome work directory'
# Leave the YAML WebUI address unusable so adguardhome_web_port() must
# exercise the .config fallback branch under test.
printf '%s\n' 'http:' '  address:' >"${WORK_DIR}/AdGuardHome.yaml" || fail 'could not create YAML stub'
printf '%s\n' 'ADGUARD_WEBUI_PORT="808"' >"${WORK_DIR}/.config" || fail 'could not create config stub'
printf '%s\n' '#!/bin/sh' 'exit 0' >"${WORK_DIR}/AdGuardHome" || fail 'could not create AdGuardHome stub'
chmod 755 "${WORK_DIR}/AdGuardHome" || fail 'could not chmod AdGuardHome stub'

pidof() {
	[ "${1:-}" = AdGuardHome ] || return 1
	[ "${PIDOF_STATE:-one}" = missing ] && return 1
	printf '%s\n' 321
}

netstat() {
	case "${NETSTAT_STATE:-owned}" in
		owned) printf '%s\n' 'tcp 0 0 0.0.0.0:808 0.0.0.0:* LISTEN 321/AdGuardHome' ;;
		foreign) printf '%s\n' 'tcp 0 0 0.0.0.0:808 0.0.0.0:* LISTEN 654/httpd' ;;
		no_owner) printf '%s\n' 'tcp 0 0 0.0.0.0:808 0.0.0.0:* LISTEN' ;;
		*) return 1 ;;
	esac
}

[ "$(adguardhome_web_port)" = 808 ] || fail 'S99 rejected a valid low .config WebUI port'
adguardhome_startup_checks_ready || fail 'S99 startup readiness rejected a valid low .config WebUI port'

NETSTAT_STATE=foreign
adguardhome_startup_checks_ready
[ "$?" -eq 3 ] || fail 'S99 startup readiness did not return 3 for foreign WebUI ownership'
[ "$(wait_for_adguardhome_startup_checks_failure_reason 3)" = 'WebUI port is not owned by AdGuardHome' ] ||
	fail 'S99 startup readiness did not explain foreign WebUI ownership'

NETSTAT_STATE=no_owner
adguardhome_startup_checks_ready || fail 'S99 startup readiness rejected ownerless WebUI bind with one AdGuardHome process'

PIDOF_STATE=missing
adguardhome_startup_checks_ready
[ "$?" -eq 2 ] || fail 'S99 startup readiness did not return 2 when AdGuardHome exited'
[ "$(wait_for_adguardhome_startup_checks_failure_reason 2)" = 'process exited before readiness completed' ] ||
	fail 'S99 startup readiness did not explain exited AdGuardHome process'

PIDOF_STATE=one
NETSTAT_STATE=owned
chmod 644 "${WORK_DIR}/AdGuardHome" || fail 'could not remove AdGuardHome executable bit'
adguardhome_startup_checks_ready
[ "$?" -eq 4 ] || fail 'S99 startup readiness did not return 4 for config validation failure'
[ "$(wait_for_adguardhome_startup_checks_failure_reason 4)" = 'configuration validation failed' ] ||
	fail 'S99 startup readiness did not explain configuration validation failure'
