#!/bin/sh
# Verify installer init, services, and firewall hook updates restore prior state on failure.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_DIR="${TMPDIR:-/tmp}/installer-event-script-transactions.$$"

# cleanup removes the temporary fixture directory.
cleanup() {
	rm -rf "${TMP_DIR}"
}

# fail prints a failure message to standard error and exits with a nonzero status.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"
mkdir -p "${TMP_DIR}/jffs/scripts" "${TMP_DIR}/base" || fail 'could not create transaction fixture'
sed -n '/^event_scripts_snapshot() {$/,$ { /^remove_firewall_event_scripts() {$/q; p; }' "${SCRIPT_PATH}" >"${TMP_DIR}/helpers.part" ||
	fail 'could not extract event-script transaction helpers'
sed -n '/^remove_firewall_event_scripts() {$/,/^}$/p' "${SCRIPT_PATH}" >>"${TMP_DIR}/helpers.part" ||
	fail 'could not complete firewall transaction helper extraction'
sed -n '/^install_wan_event_scripts() {$/,/^}$/p' "${SCRIPT_PATH}" >>"${TMP_DIR}/helpers.part" ||
	fail 'could not extract WAN event-script orchestration helper'
sed "s|/jffs/scripts|${TMP_DIR}/jffs/scripts|g" "${TMP_DIR}/helpers.part" >"${TMP_DIR}/helpers" ||
	fail 'could not rewrite event-script transaction helpers'
# shellcheck disable=SC1091
. "${TMP_DIR}/helpers"
for helper in add_init_event_scripts add_services_event_scripts remove_services_event_scripts add_firewall_event_scripts all_event_scripts_transaction_begin all_event_scripts_transaction_rollback all_event_scripts_rollback install_wan_event_scripts; do
	type "${helper}" >/dev/null 2>&1 || fail "event-script transaction helper extraction failed: ${helper}"
done

BASE_DIR="${TMP_DIR}/base"

printf '%s\n' 'original init' >"${TMP_DIR}/jffs/scripts/init-start"
# write_manager_script simulates a failed init script update.
write_manager_script() {
	printf '%s\n' 'changed init' >"$1"
	return 1
}
if add_init_event_scripts; then
	fail 'init hook publication failure was hidden'
fi
grep -qx 'original init' "${TMP_DIR}/jffs/scripts/init-start" || fail 'init hook was not restored'

printf '%s\n' 'original services-stop' >"${TMP_DIR}/jffs/scripts/services-stop"
printf '%s\n' 'original service-event-end' >"${TMP_DIR}/jffs/scripts/service-event-end"
# del_between_magic performs no action and returns a successful status.
del_between_magic() { return 0; }
# write_manager_script writes the manager script content to the specified path.
write_manager_script() {
	printf '%s\n' 'changed services-stop' >"$1"
}
# write_command_script writes a service event marker to the specified file and reports failure.
write_command_script() {
	printf '%s\n' 'changed service-event-end' >"$1"
	return 1
}
if add_services_event_scripts; then
	fail 'services hook publication failure was hidden'
fi
grep -qx 'original services-stop' "${TMP_DIR}/jffs/scripts/services-stop" || fail 'services-stop was not restored after add failure'
grep -qx 'original service-event-end' "${TMP_DIR}/jffs/scripts/service-event-end" || fail 'service-event-end was not restored after add failure'

remove_calls=0
# del_jffs_script increments the removal counter and writes a services-stop change marker to the specified file.
del_jffs_script() {
	remove_calls="$((remove_calls + 1))"
	printf '%s\n' 'changed services-stop' >"$1"
}
# del_between_magic writes a service-event marker to the specified file and reports failure.
del_between_magic() {
	printf '%s\n' 'changed service-event-end' >"$1"
	return 1
}
if remove_services_event_scripts; then
	fail 'services hook removal failure was hidden'
fi
[ "${remove_calls}" -eq 1 ] || fail 'services-stop removal was not attempted'
grep -qx 'original services-stop' "${TMP_DIR}/jffs/scripts/services-stop" || fail 'services-stop was not restored after remove failure'
grep -qx 'original service-event-end' "${TMP_DIR}/jffs/scripts/service-event-end" || fail 'service-event-end was not restored after remove failure'

printf '%s\n' 'original firewall' >"${TMP_DIR}/jffs/scripts/firewall-start"
# write_manager_script writes a firewall change marker to the specified file and reports failure.
write_manager_script() {
	printf '%s\n' 'changed firewall' >"$1"
	return 1
}
if add_firewall_event_scripts; then
	fail 'firewall hook publication failure was hidden'
fi
grep -qx 'original firewall' "${TMP_DIR}/jffs/scripts/firewall-start" || fail 'firewall hook was not restored'

printf '%s\n' 'original dnsmasq' >"${TMP_DIR}/jffs/scripts/dnsmasq.postconf"
printf '%s\n' 'original dnsmasq SDN' >"${TMP_DIR}/jffs/scripts/dnsmasq-sdn.postconf"
printf '%s\n' 'original init' >"${TMP_DIR}/jffs/scripts/init-start"
printf '%s\n' 'original services-stop' >"${TMP_DIR}/jffs/scripts/services-stop"
printf '%s\n' 'original service-event-end' >"${TMP_DIR}/jffs/scripts/service-event-end"
printf '%s\n' 'original firewall' >"${TMP_DIR}/jffs/scripts/firewall-start"
CONF_FILE="${TMP_DIR}/config"
printf '%s\n' 'ADGUARD_DNSMASQ_MODE="disabled"' >"${CONF_FILE}"
# add_dnsmasq_event_scripts writes simulated DNSMasq event-script and configuration changes to the temporary fixture.
add_dnsmasq_event_scripts() {
	printf '%s\n' 'changed dnsmasq' >"${TMP_DIR}/jffs/scripts/dnsmasq.postconf"
	printf '%s\n' 'ADGUARD_DNSMASQ_MODE="enabled"' >"${CONF_FILE}"
}
# add_init_event_scripts writes the init event script fixture.
add_init_event_scripts() {
	printf '%s\n' 'changed init' >"${TMP_DIR}/jffs/scripts/init-start"
}
# add_services_event_scripts adds a services-stop event script and reports failure.
add_services_event_scripts() {
	printf '%s\n' 'changed services-stop' >"${TMP_DIR}/jffs/scripts/services-stop"
	return 1
}
# add_firewall_event_scripts adds a test stub that reports an error if WAN orchestration reaches firewall processing after a services failure.
add_firewall_event_scripts() { fail 'WAN orchestration continued after services failure'; }
all_event_scripts_transaction_begin "${BASE_DIR}/wan-aggregate" || fail 'WAN aggregate snapshot failed'
if install_wan_event_scripts; then
	fail 'WAN orchestration hid a later helper failure'
fi
all_event_scripts_transaction_rollback || fail 'WAN aggregate rollback failed'
grep -qx 'original dnsmasq' "${TMP_DIR}/jffs/scripts/dnsmasq.postconf" || fail 'WAN rollback did not restore dnsmasq.postconf'
grep -qx 'original dnsmasq SDN' "${TMP_DIR}/jffs/scripts/dnsmasq-sdn.postconf" || fail 'WAN rollback did not restore dnsmasq-sdn.postconf'
grep -qx 'original init' "${TMP_DIR}/jffs/scripts/init-start" || fail 'WAN rollback did not restore init-start'
grep -qx 'original services-stop' "${TMP_DIR}/jffs/scripts/services-stop" || fail 'WAN rollback did not restore services-stop'
grep -qx 'original service-event-end' "${TMP_DIR}/jffs/scripts/service-event-end" || fail 'WAN rollback did not restore service-event-end'
grep -qx 'original firewall' "${TMP_DIR}/jffs/scripts/firewall-start" || fail 'WAN rollback did not restore firewall-start'
grep -qx 'ADGUARD_DNSMASQ_MODE="disabled"' "${CONF_FILE}" || fail 'WAN rollback did not restore dnsmasq configuration'

FAILED_SNAPSHOT_DIR="${BASE_DIR}/failed-rollback"
mkdir -p "${FAILED_SNAPSHOT_DIR}" || fail 'could not create failed rollback snapshot fixture'
printf '%s\n' 'preserved recovery data' >"${FAILED_SNAPSHOT_DIR}/dnsmasq.postconf"
ERROR=ERROR
# PTXT appends the provided text to the rollback report.
PTXT() { printf '%s\n' "$*" >>"${TMP_DIR}/rollback-report"; }
# all_event_scripts_restore restores all event-script files and reports failure when restoration is unsuccessful.
all_event_scripts_restore() { return 1; }
if all_event_scripts_rollback "${FAILED_SNAPSHOT_DIR}"; then
	fail 'aggregate rollback hid a restoration failure'
fi
[ -f "${FAILED_SNAPSHOT_DIR}/dnsmasq.postconf" ] || fail 'failed rollback discarded the recovery snapshot'
grep -q "${FAILED_SNAPSHOT_DIR}" "${TMP_DIR}/rollback-report" || fail 'failed rollback did not report the retained recovery snapshot path'

printf '%s\n' 'PASS: installer event-script transaction regression'
