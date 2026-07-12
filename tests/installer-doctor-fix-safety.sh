#!/bin/sh
# Verify doctor --fix reports unsafe router states with next steps but does not rewrite DNS/firewall/NVRAM or remove active markers.

set -u

fail() {
	printf '%s\n' "FAIL: $1" >&2
	exit 1
}

INSTALLER_PATH="${1:-installer}"
TEST_ROOT="${TMPDIR:-/tmp}/installer-doctor-fix-safety.$$"
FUNCTIONS_FILE="${TEST_ROOT}/installer-doctor-functions"
BIN_DIR="${TEST_ROOT}/bin"
LOG_FILE="${TEST_ROOT}/commands.log"
ACTIVE_MARKER="/tmp/AdGuardHome.dnsmasq.handoff"
ACTIVE_MARKER_BACKUP="${TEST_ROOT}/active-marker.backup"
ACTIVE_MARKER_WAS_PRESENT=0
mkdir -p "${TEST_ROOT}" "${BIN_DIR}" || fail 'could not create test directory'
if [ -f "${ACTIVE_MARKER}" ]; then
	ACTIVE_MARKER_WAS_PRESENT=1
	/bin/cp "${ACTIVE_MARKER}" "${ACTIVE_MARKER_BACKUP}" || fail 'could not preserve active marker'
fi
cleanup() {
	if [ "${ACTIVE_MARKER_WAS_PRESENT}" = 1 ] && [ -f "${ACTIVE_MARKER_BACKUP}" ]; then
		/bin/cp "${ACTIVE_MARKER_BACKUP}" "${ACTIVE_MARKER}"
	else
		[ -f "${ACTIVE_MARKER}" ] && /bin/rm -f "${ACTIVE_MARKER}"
	fi
	/bin/rm -rf "${TEST_ROOT}"
}
trap cleanup EXIT HUP INT TERM

sed -n \
	'/^PTXT() {$/,/^}$/p; /^ai_have_cmd() {$/,/^}$/p; /^agh_dns_bound() {$/,/^}$/p; /^doctor_status() {$/,/^}$/p; /^doctor_fix_msg() {$/,/^}$/p; /^doctor_file_state() {$/,/^}$/p; /^doctor_managed_script_state() {$/,/^}$/p; /^doctor_dns53_state() {$/,/^}$/p; /^doctor_fix_permissions() {$/,/^}$/p; /^doctor_pid_file_is_active() {$/,/^}$/p; /^doctor_run_lock_is_active() {$/,/^}$/p; /^doctor_fix_safe() {$/,/^}$/p; /^doctor_show_nvram_dns() {$/,/^}$/p; /^doctor() {$/,/^}$/p' \
	"${INSTALLER_PATH}" >"${FUNCTIONS_FILE}" || fail "could not read ${INSTALLER_PATH}"
[ -s "${FUNCTIONS_FILE}" ] || fail 'doctor functions were not found'
grep -q '^doctor() {$' "${FUNCTIONS_FILE}" || fail 'installer has no doctor command helper'

cat >"${BIN_DIR}/pidof" <<'STUB'
#!/bin/sh
exit 1
STUB
chmod 755 "${BIN_DIR}/pidof" || fail 'could not chmod pidof stub'

cat >"${BIN_DIR}/netstat" <<'STUB'
#!/bin/sh
printf '%s\n' \
	'tcp        0      0 0.0.0.0:53              0.0.0.0:*               LISTEN      55/dnsmasq' \
	'udp        0      0 0.0.0.0:53              0.0.0.0:*                           55/dnsmasq' \
	'tcp        0      0 192.168.50.1:3000       0.0.0.0:*               LISTEN      66/httpd'
STUB
chmod 755 "${BIN_DIR}/netstat" || fail 'could not chmod netstat stub'

cat >"${BIN_DIR}/nvram" <<'STUB'
#!/bin/sh
printf '%s %s\n' "nvram" "$*" >>"${LOG_FILE}"
case "$1" in
	get) printf '%s\n' 'unsafe-test-value' ;;
	*) exit 2 ;;
esac
STUB
chmod 755 "${BIN_DIR}/nvram" || fail 'could not chmod nvram stub'

for unsafe_cmd in iptables ip6tables service; do
	cat >"${BIN_DIR}/${unsafe_cmd}" <<'STUB'
#!/bin/sh
printf '%s %s\n' "$(basename "$0")" "$*" >>"${LOG_FILE}"
exit 0
STUB
	chmod 755 "${BIN_DIR}/${unsafe_cmd}" || fail "could not chmod ${unsafe_cmd} stub"
done

: >"${LOG_FILE}" || fail 'could not create command log'
printf '%s\n' "$$" >"${ACTIVE_MARKER}" || fail 'could not create active marker'

PATH="${BIN_DIR}:/bin:/usr/bin" LOG_FILE="${LOG_FILE}" . "${FUNCTIONS_FILE}"

entware_available() { return 0; }
ensure_adguardhome_directory_permissions() { printf '%s\n' 'permissions checked' >>"${LOG_FILE}"; return 0; }
agh_monitor_count() { printf '%s\n' '1'; }
web_port_owned_by_agh() { return 1; }
conf_value() { [ "$1" = INSTALLER_BRANCH ] && printf '%s\n' 'dev'; }
agh_web_port() { printf '%s\n' '3000'; }
adguard_archive_is_safe() { return 1; }
adguardhome_yaml_ipset_file() { printf '%s\n' 'configured-ipset.conf'; }
chmod() { printf '%s %s\n' 'chmod' "$*" >>"${LOG_FILE}"; return 0; }
chown() { printf '%s %s\n' 'chown' "$*" >>"${LOG_FILE}"; return 0; }
mkdir() { printf '%s %s\n' 'mkdir' "$*" >>"${LOG_FILE}"; return 0; }
ln() { printf '%s %s\n' 'ln' "$*" >>"${LOG_FILE}"; return 0; }
rm() { printf '%s %s\n' 'rm' "$*" >>"${LOG_FILE}"; return 0; }

AI_VERSION='vTEST'
BASE_DIR="${TEST_ROOT}"
TARG_DIR="${TEST_ROOT}/AdGuardHome"
ADDON_DIR="${TEST_ROOT}/addons"
CONF_FILE="${TEST_ROOT}/AdGuardHome.conf"
YAML_FILE="${TEST_ROOT}/AdGuardHome.yaml"
AGH_FILE="${TEST_ROOT}/missing-AdGuardHome"
/bin/mkdir -p "${TARG_DIR}" "${ADDON_DIR}" || fail 'could not create fixture directories'
printf '%s\n' 'ADGUARD_WEBUI_PORT="3000"' >"${CONF_FILE}" || fail 'could not write config'
printf '%s\n' 'bind_host: 192.168.50.1' >"${YAML_FILE}" || fail 'could not write yaml'

DOCTOR_OUTPUT="$(PATH="${BIN_DIR}:/bin:/usr/bin" LOG_FILE="${LOG_FILE}" doctor --fix 2>&1)" || true

printf '%s\n' "${DOCTOR_OUTPUT}" | grep -q '^\[WARN\].*DNS port 53 TCP and UDP are not both owned by AdGuardHome.*Next:' || fail 'DNS warning did not include next step'
printf '%s\n' "${DOCTOR_OUTPUT}" | grep -q '^\[WARN\].*WebUI port 3000 not owned by AdGuardHome.*Next:' || fail 'WebUI warning did not include next step'
printf '%s\n' "${DOCTOR_OUTPUT}" | grep -q '^\[FAIL\].*/opt/sbin/AdGuardHome target is .*Next:' || fail 'symlink failure did not include next step'

grep -q '^nvram get ' "${LOG_FILE}" || fail 'NVRAM values were not inspected'
if grep -q '^nvram \(set\|commit\)' "${LOG_FILE}"; then
	fail 'doctor --fix attempted an unsafe NVRAM write'
fi
if grep -q '^\(iptables\|ip6tables\|service\) ' "${LOG_FILE}"; then
	fail 'doctor --fix attempted unsafe firewall or service changes'
fi
if grep -q "^rm .*${ACTIVE_MARKER}" "${LOG_FILE}"; then
	fail 'doctor --fix attempted to remove an active dnsmasq handoff marker'
fi
[ -f "${ACTIVE_MARKER}" ] || fail 'active marker was removed'

printf '%s\n' 'PASS: doctor --fix reports unsafe states without modifying DNS/firewall/NVRAM or active markers'
