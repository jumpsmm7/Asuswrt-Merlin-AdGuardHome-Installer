#!/bin/sh
# Verify installer status summarizes service, process, port, version, branch, WebUI, handoff, and startup state without actions.

set -u

fail() {
	printf '%s\n' "FAIL: $1" >&2
	exit 1
}

INSTALLER_PATH="${1:-installer}"
TEST_ROOT="${TMPDIR:-/tmp}/installer-status.$$"
FUNCTIONS_FILE="${TEST_ROOT}/installer-status-functions"
BIN_DIR="${TEST_ROOT}/bin"
mkdir -p "${TEST_ROOT}" "${BIN_DIR}" || fail 'could not create test directory'
trap 'rm -rf "${TEST_ROOT}"' EXIT HUP INT TERM

sed -n \
	'/^PTXT() {$/,/^}$/p; /^ai_have_cmd() {$/,/^}$/p; /^rollback_result_summary() {$/,/^}$/p; /^runtime_port_is_valid() {$/,/^}$/p; /^port_is_valid() {$/,/^}$/p; /^conf_value() {$/,/^}$/p; /^agh_web_port() {$/,/^}$/p; /^agh_is_running() {$/,/^}$/p; /^agh_dns_bound() {$/,/^}$/p; /^web_port_owned_by_agh() {$/,/^}$/p; /^agh_web_bound() {$/,/^}$/p; /^agh_config_valid() {$/,/^}$/p; /^agh_startup_check() {$/,/^}$/p; /^agh_monitor_count() {$/,/^}$/p; /^status_line() {$/,/^}$/p; /^status_dnsmasq_handoff_state() {$/,/^}$/p; /^status_last_startup_result() {$/,/^}$/p; /^status_port53_ownership() {$/,/^}$/p; /^status_webui_address() {$/,/^}$/p; /^status() {$/,/^}$/p' \
	"${INSTALLER_PATH}" >"${FUNCTIONS_FILE}" || fail "could not read ${INSTALLER_PATH}"
[ -s "${FUNCTIONS_FILE}" ] || fail 'status functions were not found'
grep -q '^status() {$' "${FUNCTIONS_FILE}" || fail 'installer has no status command helper'
grep -q '^status_last_startup_result() {$' "${FUNCTIONS_FILE}" || fail 'installer has no startup-result status helper'

cat >"${BIN_DIR}/pidof" <<'STUB'
#!/bin/sh
case "$1" in
	AdGuardHome) printf '%s\n' '111 222' ;;
	*) ;;
esac
STUB
chmod 755 "${BIN_DIR}/pidof" || fail 'could not chmod pidof stub'

cat >"${BIN_DIR}/netstat" <<'STUB'
#!/bin/sh
printf '%s\n' \
	'tcp        0      0 0.0.0.0:53              0.0.0.0:*               LISTEN      111/AdGuardHome' \
	'udp        0      0 0.0.0.0:53              0.0.0.0:*                           111/AdGuardHome' \
	'tcp        0      0 192.168.50.1:3000       0.0.0.0:*               LISTEN      111/AdGuardHome'
STUB
chmod 755 "${BIN_DIR}/netstat" || fail 'could not chmod netstat stub'

cat >"${BIN_DIR}/logread" <<'STUB'
#!/bin/sh
printf '%s\n' \
	'Jan  1 00:00:00 router AdGuardHome[1]: AdGuardHome startup failed: process is not running.' \
	'Jan  1 00:00:01 router AdGuardHome[1]: AdGuardHome startup completed.'
STUB
chmod 755 "${BIN_DIR}/logread" || fail 'could not chmod logread stub'

cat >"${BIN_DIR}/nvram" <<'STUB'
#!/bin/sh
[ "$1" = get ] && [ "$2" = lan_ipaddr ] && printf '%s\n' '192.168.50.1'
STUB
chmod 755 "${BIN_DIR}/nvram" || fail 'could not chmod nvram stub'

PATH="${BIN_DIR}:/bin:/usr/bin" . "${FUNCTIONS_FILE}"
AI_VERSION='vTEST'
CONF_FILE="${TEST_ROOT}/.config"
YAML_FILE="${TEST_ROOT}/AdGuardHome.yaml"
AGH_FILE="${TEST_ROOT}/AdGuardHome"
ROLLBACK_RESULT_FILE="${TEST_ROOT}/.rollback_result"
cat >"${CONF_FILE}" <<'CONF'
INSTALLER_BRANCH="dev"
ADGUARD_WEBUI_PORT="3000"
CONF
cat >"${YAML_FILE}" <<'YAML'
http:
  address: 192.168.50.1:3000
YAML
cat >"${AGH_FILE}" <<'STUB'
#!/bin/sh
case "$1" in
	--version) printf '%s\n' 'AdGuardHome v0.107.test' ;;
	--check-config) exit 0 ;;
esac
STUB
chmod 755 "${AGH_FILE}" || fail 'could not chmod AdGuardHome stub'

agh_monitor_count() { printf '%s\n' '1'; }

STATUS_OUTPUT="$(PATH="${BIN_DIR}:/bin:/usr/bin" status)" || fail 'status command failed'

printf '%s\n' "${STATUS_OUTPUT}" | grep -q '^AdGuardHome Installer Status$' || fail 'status header missing'
printf '%s\n' "${STATUS_OUTPUT}" | grep -q '^AdGuardHome service state: running (ready)$' || fail 'service state missing'
printf '%s\n' "${STATUS_OUTPUT}" | grep -q '^Monitor process state: running (1 process)$' || fail 'monitor state missing'
printf '%s\n' "${STATUS_OUTPUT}" | grep -q '^AdGuardHome PID count: 2$' || fail 'PID count missing'
printf '%s\n' "${STATUS_OUTPUT}" | grep -q '^Port 53 ownership: TCP 111/AdGuardHome; UDP 111/AdGuardHome$' || fail 'port 53 ownership missing'
printf '%s\n' "${STATUS_OUTPUT}" | grep -q '^AdGuardHome version: AdGuardHome v0.107.test$' || fail 'AdGuardHome version missing'
printf '%s\n' "${STATUS_OUTPUT}" | grep -q '^Installer version: vTEST$' || fail 'installer version missing'
printf '%s\n' "${STATUS_OUTPUT}" | grep -q '^Selected branch: dev$' || fail 'branch missing'
printf '%s\n' "${STATUS_OUTPUT}" | grep -q '^WebUI address/port: 192.168.50.1:3000 (port 3000)$' || fail 'WebUI address missing'
printf '%s\n' "${STATUS_OUTPUT}" | grep -q '^dnsmasq handoff state: inactive$' || fail 'dnsmasq handoff state missing'
printf '%s\n' "${STATUS_OUTPUT}" | grep -q '^Last startup result: .*AdGuardHome startup completed\.$' || fail 'last startup result missing'
printf '%s\n' "${STATUS_OUTPUT}" | grep -q '^Last rollback result: none$' || fail 'last rollback result missing'

printf '%s\n' 'PASS: installer status summarizes runtime state'
