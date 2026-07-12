#!/bin/sh
# Verify doctor exits nonzero when the last rollback record reports incomplete rollback.

set -u

fail() {
	printf '%s\n' "FAIL: $1" >&2
	exit 1
}

INSTALLER_PATH="${1:-installer}"
TEST_ROOT="${TMPDIR:-/tmp}/installer-doctor-rollback-result.$$"
FUNCTIONS_FILE="${TEST_ROOT}/installer-doctor-functions"
BIN_DIR="${TEST_ROOT}/bin"
mkdir -p "${TEST_ROOT}" "${BIN_DIR}" || fail 'could not create test directory'
trap 'rm -rf "${TEST_ROOT}"' EXIT HUP INT TERM

sed -n \
	'/^PTXT() {$/,/^}$/p; /^ai_have_cmd() {$/,/^}$/p; /^rollback_result_summary() {$/,/^}$/p; /^rollback_result_needs_attention() {$/,/^}$/p; /^agh_dns_bound() {$/,/^}$/p; /^doctor_status() {$/,/^}$/p; /^doctor_fix_msg() {$/,/^}$/p; /^doctor_file_state() {$/,/^}$/p; /^doctor_managed_script_state() {$/,/^}$/p; /^doctor_dns53_state() {$/,/^}$/p; /^doctor_fix_permissions() {$/,/^}$/p; /^doctor_pid_file_is_active() {$/,/^}$/p; /^doctor_run_lock_is_active() {$/,/^}$/p; /^doctor_fix_safe() {$/,/^}$/p; /^doctor_show_nvram_dns() {$/,/^}$/p; /^doctor() {$/,/^}$/p' \
	"${INSTALLER_PATH}" >"${FUNCTIONS_FILE}" || fail "could not read ${INSTALLER_PATH}"
[ -s "${FUNCTIONS_FILE}" ] || fail 'doctor functions were not found'
grep -q '^rollback_result_needs_attention() {$' "${FUNCTIONS_FILE}" || fail 'rollback attention helper was not found'
grep -q '^doctor() {$' "${FUNCTIONS_FILE}" || fail 'installer has no doctor command helper'

cat >"${BIN_DIR}/pidof" <<'STUB'
#!/bin/sh
case "$1" in
	AdGuardHome) printf '%s\n' '111' ;;
	*) ;;
esac
STUB
chmod 755 "${BIN_DIR}/pidof" || fail 'could not chmod pidof stub'

cat >"${BIN_DIR}/netstat" <<'STUB'
#!/bin/sh
printf '%s\n' \
	'tcp        0      0 0.0.0.0:53              0.0.0.0:*               LISTEN      111/AdGuardHome' \
	'udp        0      0 0.0.0.0:53              0.0.0.0:*                           111/AdGuardHome'
STUB
chmod 755 "${BIN_DIR}/netstat" || fail 'could not chmod netstat stub'

PATH="${BIN_DIR}:/bin:/usr/bin" . "${FUNCTIONS_FILE}"

entware_available() { return 0; }
agh_monitor_count() { printf '%s\n' '1'; }
web_port_owned_by_agh() { return 0; }
conf_value() { [ "$1" = INSTALLER_BRANCH ] && printf '%s\n' 'dev'; }
agh_web_port() { printf '%s\n' '3000'; }
adguard_archive_is_safe() { return 0; }
adguardhome_yaml_ipset_file() { return 1; }
AI_VERSION='vTEST'
TARG_DIR="${TEST_ROOT}/AdGuardHome"
ADDON_DIR="${TEST_ROOT}/addons"
CONF_FILE="${TEST_ROOT}/AdGuardHome.conf"
YAML_FILE="${TEST_ROOT}/AdGuardHome.yaml"
AGH_FILE="${TEST_ROOT}/AdGuardHome/AdGuardHome"
ROLLBACK_RESULT_FILE="${TARG_DIR}/.rollback_result"
mkdir -p "${TARG_DIR}" "${ADDON_DIR}" || fail 'could not create fixture directories'
printf '%s\n' 'ADGUARD_WEBUI_PORT="3000"' >"${CONF_FILE}" || fail 'could not write config'
printf '%s\n' 'bind_host: 192.168.50.1' >"${YAML_FILE}" || fail 'could not write yaml'
for result in 'rollback failed' 'rollback partial' 'rollback unavailable' 'failed: rollback unavailable'; do
	cat >"${ROLLBACK_RESULT_FILE}" <<RESULT
time=2026-07-12 00:00:00
context=binary-replace
result=${result}
detail=previous binary remains at /tmp/old
RESULT
	DOCTOR_OUTPUT="$(PATH="${BIN_DIR}:/bin:/usr/bin" doctor 2>&1)" && fail "doctor succeeded with ${result} record"
	printf '%s\n' "${DOCTOR_OUTPUT}" | grep -q "^\[FAIL\] last rollback result: ${result} .*Next:" || fail "${result} record was not reported as FAIL with next step"
done

printf '%s\n' 'PASS: doctor fails on incomplete rollback result records'
