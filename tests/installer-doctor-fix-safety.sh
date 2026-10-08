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
export LOG_FILE
ACTIVE_MARKER="${TEST_ROOT}/AdGuardHome.dnsmasq.handoff"
DANGLING_MARKER="${TEST_ROOT}/AdGuardHome.dnsmasq.lock"
mkdir -p "${TEST_ROOT}" "${BIN_DIR}" || fail 'could not create test directory'
# cleanup removes the temporary test directory and its contents.
cleanup() {
	/bin/rm -rf "${TEST_ROOT}"
}
trap cleanup EXIT HUP INT TERM

sed -n \
	'/^PTXT() {$/,/^}$/p; /^ai_have_cmd() {$/,/^}$/p; /^rollback_result_summary() {$/,/^}$/p; /^agh_dns_bound() {$/,/^}$/p; /^doctor_status() {$/,/^}$/p; /^doctor_fix_msg() {$/,/^}$/p; /^doctor_file_state() {$/,/^}$/p; /^doctor_managed_script_state() {$/,/^}$/p; /^doctor_dns53_state() {$/,/^}$/p; /^doctor_fix_permissions() {$/,/^}$/p; /^doctor_pid_file_is_active() {$/,/^}$/p; /^doctor_run_lock_is_active() {$/,/^}$/p; /^doctor_fix_safe() {$/,/^}$/p; /^doctor_show_nvram_dns() {$/,/^}$/p; /^doctor() {$/,/^}$/p' \
	"${INSTALLER_PATH}" >"${FUNCTIONS_FILE}" || fail "could not read ${INSTALLER_PATH}"
awk '
	/^(doctor_check_managed_hooks|managed_hook_[a-z_]+|service_event_hook_command|write_managed_hook|write_manager_script|write_command_script|del_between_magic|del_jffs_script|adguard_ipset_allowed)\(\) \{/ { copying = 1 }
	copying { print }
	copying && /^}/ { copying = 0 }
' "${INSTALLER_PATH}" >>"${FUNCTIONS_FILE}" || fail 'could not extract managed-hook helpers'
sed "s#/tmp/AdGuardHome\.dnsmasq\.handoff#${ACTIVE_MARKER}#g" "${FUNCTIONS_FILE}" >"${FUNCTIONS_FILE}.tmp" || fail 'could not isolate active marker path'
/bin/mv "${FUNCTIONS_FILE}.tmp" "${FUNCTIONS_FILE}" || fail 'could not update isolated fixture'
DANGLING_MARKER_SED="$(printf '%s\n' "${DANGLING_MARKER}" | sed 's/[\&#]/\\&/g')" || fail 'could not escape dangling marker path'
sed "s#/tmp/AdGuardHome\.dnsmasq\.lock#${DANGLING_MARKER_SED}#g" "${FUNCTIONS_FILE}" >"${FUNCTIONS_FILE}.tmp" || fail 'could not isolate dangling marker path'
/bin/mv "${FUNCTIONS_FILE}.tmp" "${FUNCTIONS_FILE}" || fail 'could not update dangling marker fixture'
sed "s|/tmp/AdGuardHome-service-lock|${TEST_ROOT}/service-lock|g; s|/tmp/AdGuardHome|${TEST_ROOT}/legacy|g" "${FUNCTIONS_FILE}" >"${FUNCTIONS_FILE}.tmp" || fail 'could not isolate service lock paths'
/bin/mv "${FUNCTIONS_FILE}.tmp" "${FUNCTIONS_FILE}" || fail 'could not update isolated service lock fixture'
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
	[ -x "${BIN_DIR}/${unsafe_cmd}" ] || fail "${unsafe_cmd} stub is not executable"
done

: >"${LOG_FILE}" || fail 'could not create command log'
printf '%s\n' "$$" >"${ACTIVE_MARKER}" || fail 'could not create active marker'
ln -s "${TEST_ROOT}/missing-marker-target" "${DANGLING_MARKER}" || fail 'could not create dangling marker'

PATH="${BIN_DIR}:/bin:/usr/bin" LOG_FILE="${LOG_FILE}" . "${FUNCTIONS_FILE}"

# Function wrappers keep BusyBox builds that prefer internal applets on the isolated socket fixtures.
netstat() { "${BIN_DIR}/netstat" "$@"; }
# pidof routes process discovery through the isolated command stub.
pidof() { "${BIN_DIR}/pidof" "$@"; }
entware_available() { return 0; }
ensure_adguardhome_directory_permissions() {
	printf '%s\n' 'permissions checked' >>"${LOG_FILE}"
	return 0
}
agh_monitor_count() { printf '%s\n' '1'; }
web_port_owned_by_agh() { return 1; }
conf_value() { [ "$1" = INSTALLER_BRANCH ] && printf '%s\n' 'dev'; }
agh_web_port() { printf '%s\n' '3000'; }
adguard_archive_is_safe() { return 1; }
adguardhome_yaml_ipset_file() { printf '%s\n' 'configured-ipset.conf'; }
AI_VERSION='vTEST'
BASE_DIR="${TEST_ROOT}"
TARG_DIR="${TEST_ROOT}/AdGuardHome"
ADDON_DIR="${TEST_ROOT}/addons"
CONF_FILE="${TEST_ROOT}/AdGuardHome.conf"
YAML_FILE="${TEST_ROOT}/AdGuardHome.yaml"
AGH_FILE="${TEST_ROOT}/missing-AdGuardHome"
ROLLBACK_RESULT_FILE="${TEST_ROOT}/.rollback_result"
/bin/mkdir -p "${TARG_DIR}" "${ADDON_DIR}" || fail 'could not create fixture directories'
printf '%s\n' 'ADGUARD_WEBUI_PORT="3000"' >"${CONF_FILE}" || fail 'could not write config'
printf '%s\n' 'bind_host: 192.168.50.1' >"${YAML_FILE}" || fail 'could not write yaml'

chmod() {
	printf '%s %s\n' 'chmod' "$*" >>"${LOG_FILE}"
	return 0
}
chown() {
	printf '%s %s\n' 'chown' "$*" >>"${LOG_FILE}"
	return 0
}
mkdir() {
	printf '%s %s\n' 'mkdir' "$*" >>"${LOG_FILE}"
	return 0
}
ln() {
	printf '%s %s\n' 'ln' "$*" >>"${LOG_FILE}"
	return 0
}
rm() {
	printf '%s %s\n' 'rm' "$*" >>"${LOG_FILE}"
	return 0
}

DOCTOR_OUTPUT="$(PATH="${BIN_DIR}:/bin:/usr/bin" LOG_FILE="${LOG_FILE}" doctor --fix 2>&1)" || true

printf '%s\n' "${DOCTOR_OUTPUT}" | grep -q '^\[WARN\].*DNS port 53 TCP and UDP are not both owned by AdGuardHome.*Next:' || fail 'DNS warning did not include next step'
printf '%s\n' "${DOCTOR_OUTPUT}" | grep -q '^\[WARN\].*WebUI port 3000 not owned by AdGuardHome.*Next:' || fail 'WebUI warning did not include next step'
printf '%s\n' "${DOCTOR_OUTPUT}" | grep -q '^\[WARN\].*nvram dnsfilter_enable_x=unsafe-test-value; DNSFilter may redirect client DNS.*Next:' || fail 'NVRAM warning did not include next step'
printf '%s\n' "${DOCTOR_OUTPUT}" | grep -q '^\[FAIL\].*/opt/sbin/AdGuardHome target is .*Next:' || fail 'symlink failure did not include next step'
printf '%s\n' "${DOCTOR_OUTPUT}" | awk -v marker="${DANGLING_MARKER}" '
	/^\[WARN\]/ && index($0, marker) && index($0, "| Next:") { found = 1 }
	END { exit found ? 0 : 1 }
' || fail 'dangling handoff marker was not reported with its path and next step'
printf '%s\n' "${DOCTOR_OUTPUT}" | awk '/^\[(WARN|FAIL)\]/ && $0 !~ /\| Next:/ { missing = 1 } END { exit missing ? 0 : 1 }' && fail 'a WARN or FAIL line did not include a next step'

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

# Private service locks retain their inode and are inspected without following unsafe targets.
SERVICE_LOCK_DIR="${TEST_ROOT}/service-lock"
/bin/mkdir -p "${SERVICE_LOCK_DIR}/action" || fail 'could not create active private lock fixture'
/bin/chmod 700 "${SERVICE_LOCK_DIR}" "${SERVICE_LOCK_DIR}/action" || fail 'could not secure private lock fixture'
doctor_run_lock_is_active || fail 'doctor ignored an active or unverified private action lock'
/bin/rmdir "${SERVICE_LOCK_DIR}/action" || fail 'could not remove isolated action fixture'
printf '%s\n' 'stable lock inode contents' >"${SERVICE_LOCK_DIR}/flock" || fail 'could not create descriptor lock fixture'
/bin/chmod 600 "${SERVICE_LOCK_DIR}/flock" || fail 'could not secure descriptor lock fixture'
LOCK_INODE="$(ls -i "${SERVICE_LOCK_DIR}/flock" | awk '{ print $1 }')"
doctor_run_lock_is_active && fail 'doctor reported an uncontended validated descriptor as active'
doctor --fix >"${TEST_ROOT}/second-doctor-output" 2>&1 || true
[ "$(ls -i "${SERVICE_LOCK_DIR}/flock" | awk '{ print $1 }')" = "${LOCK_INODE}" ] || fail 'doctor replaced or removed the stable descriptor inode'
grep -qx 'stable lock inode contents' "${SERVICE_LOCK_DIR}/flock" || fail 'doctor truncated descriptor lock contents'
/bin/rm -f "${SERVICE_LOCK_DIR}/flock" || fail 'could not remove isolated descriptor fixture'
printf '%s\n' 'foreign lock target contents' >"${TEST_ROOT}/foreign-lock-target" || fail 'could not create foreign lock target'
/bin/ln -s "${TEST_ROOT}/foreign-lock-target" "${SERVICE_LOCK_DIR}/flock" || fail 'could not create unsafe descriptor fixture'
doctor_run_lock_is_active || fail 'doctor treated an unsafe descriptor target as idle'
grep -qx 'foreign lock target contents' "${TEST_ROOT}/foreign-lock-target" || fail 'doctor followed or truncated descriptor symlink target'
/bin/rm -f "${SERVICE_LOCK_DIR}/flock" || fail 'could not remove unsafe descriptor fixture'
/bin/mkdir -p "${TEST_ROOT}/legacy" || fail 'could not create unpublished legacy lock fixture'
doctor_run_lock_is_active || fail 'doctor treated an unpublished legacy mkdir owner as idle'
/bin/chmod 755 "${TEST_ROOT}/legacy" || fail 'could not create historical mkdir mode fixture'
printf '%s\n' 'historical stable descriptor contents' >"${TEST_ROOT}/legacy.lock" || fail 'could not create historical descriptor fixture'
/bin/chmod 644 "${TEST_ROOT}/legacy.lock" || fail 'could not create historical descriptor mode fixture'
LEGACY_LOCK_INODE="$(ls -i "${TEST_ROOT}/legacy.lock" | awk '{ print $1 }')"
(
	# Use actual removal for isolated historical paths to detect cleanup-order and inode regressions.
	rm() {
		case "$*" in
			"-rf ${TEST_ROOT}/legacy.lock" | "-rf ${TEST_ROOT}/legacy") command rm "$@" ;;
			*) return 0 ;;
		esac
	}
	doctor_fix_safe >"${TEST_ROOT}/legacy-doctor-fix-output" 2>&1
) || fail 'historical lock repair fixture failed'
[ -f "${TEST_ROOT}/legacy.lock" ] || fail 'doctor unlinked the stable historical descriptor inode'
[ "$(ls -i "${TEST_ROOT}/legacy.lock" | awk '{ print $1 }')" = "${LEGACY_LOCK_INODE}" ] || fail 'doctor replaced the stable historical descriptor inode'
grep -qx 'historical stable descriptor contents' "${TEST_ROOT}/legacy.lock" || fail 'doctor truncated historical descriptor contents'
doctor_run_lock_is_active && fail 'doctor stranded idle historical metadata as an unpublished active lock'
for pending_marker in action.claim action.transition; do
	case "${pending_marker}" in
		action.claim) /bin/ln -s '1234 1234' "${SERVICE_LOCK_DIR}/${pending_marker}" ;;
		action.transition) printf '%s\n' '1234 1234 5678 5678' >"${SERVICE_LOCK_DIR}/${pending_marker}" ;;
	esac
	doctor_run_lock_is_active || fail "doctor ignored a pending ${pending_marker} ownership transition"
	/bin/rm -f "${SERVICE_LOCK_DIR}/${pending_marker}" || fail 'could not remove isolated pending ownership marker'
done

printf '%s\n' 'PASS: doctor --fix reports unsafe states without modifying DNS/firewall/NVRAM or active markers'
