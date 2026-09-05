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
grep -q '^remove_firewall_event_scripts() {$' "${SCRIPT_PATH}" || fail 'firewall transaction helper extraction boundary is missing'
grep -q '^install_wan_event_scripts() {$' "${SCRIPT_PATH}" || fail 'WAN event-script orchestration helper is missing'
grep -q '^adguard_recover_after_event_hook_abort() {$' "${SCRIPT_PATH}" || fail 'event-hook abort recovery helper is missing'
sed -n '/^event_scripts_snapshot() {$/,/^remove_firewall_event_scripts() {$/p' "${SCRIPT_PATH}" >"${TMP_DIR}/helpers.range" ||
	fail 'could not extract event-script transaction helpers'
tail -n 1 "${TMP_DIR}/helpers.range" | grep -q '^remove_firewall_event_scripts() {$' ||
	fail 'firewall transaction helper extraction did not end at its boundary'
sed '$d' "${TMP_DIR}/helpers.range" >"${TMP_DIR}/helpers.part" ||
	fail 'could not remove the firewall transaction helper extraction boundary'
sed -n '/^remove_firewall_event_scripts() {$/,/^}$/p' "${SCRIPT_PATH}" >>"${TMP_DIR}/helpers.part" ||
	fail 'could not complete firewall transaction helper extraction'
sed -n '/^install_wan_event_scripts() {$/,/^}$/p' "${SCRIPT_PATH}" >>"${TMP_DIR}/helpers.part" ||
	fail 'could not extract WAN event-script orchestration helper'
sed -n '/^adguard_recover_after_event_hook_abort() {$/,/^}$/p' "${SCRIPT_PATH}" >>"${TMP_DIR}/helpers.part" ||
	fail 'could not extract event-hook abort recovery helper'
grep -q "^trap 'on_installer_exit' EXIT$" "${TMP_DIR}/helpers.part"
grep_status="$?"
case "${grep_status}" in
	0) fail 'event-script transaction helper extraction included installer top-level flow' ;;
	1) : ;;
	*) fail 'could not inspect extracted event-script helpers' ;;
esac
sed "s|/jffs/scripts|${TMP_DIR}/jffs/scripts|g" "${TMP_DIR}/helpers.part" >"${TMP_DIR}/helpers" ||
	fail 'could not rewrite event-script transaction helpers'
# shellcheck disable=SC1091
. "${TMP_DIR}/helpers"
for helper in add_init_event_scripts add_services_event_scripts remove_services_event_scripts add_firewall_event_scripts all_event_scripts_transaction_begin all_event_scripts_transaction_detach_after_mode_rollback all_event_scripts_transaction_rollback all_event_scripts_rollback install_wan_event_scripts adguard_recover_after_event_hook_abort; do
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
YAML_FILE="${TMP_DIR}/AdGuardHome.yaml"
YAML_ORI="${TMP_DIR}/AdGuardHome.yaml.original"
printf '%s\n' 'ADGUARD_DNSMASQ_MODE="disabled"' >"${CONF_FILE}"
printf '%s\n' 'original working YAML' >"${YAML_FILE}"
printf '%s\n' 'original source YAML' >"${YAML_ORI}"
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
printf '%s\n' 'changed working YAML' >"${YAML_FILE}"
printf '%s\n' 'changed source YAML' >"${YAML_ORI}"
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
grep -qx 'original working YAML' "${YAML_FILE}" || fail 'WAN rollback did not restore the working YAML'
grep -qx 'original source YAML' "${YAML_ORI}" || fail 'WAN rollback did not restore the source YAML'

FAILED_SNAPSHOT_DIR="${BASE_DIR}/failed-rollback"
mkdir -p "${FAILED_SNAPSHOT_DIR}" || fail 'could not create failed rollback snapshot fixture'
printf '%s\n' 'preserved recovery data' >"${FAILED_SNAPSHOT_DIR}/dnsmasq.postconf"
ERROR=ERROR
INFO=INFO
# nvram_transaction_lock_owned reports no active setup transaction for the hook-only fixtures.
nvram_transaction_lock_owned() { return 1; }
# PTXT appends the provided text to the rollback report.
PTXT() { printf '%s\n' "$*" >>"${TMP_DIR}/rollback-report"; }
# all_event_scripts_restore restores all event-script files and reports failure when restoration is unsuccessful.
all_event_scripts_restore() { return 1; }
if all_event_scripts_rollback "${FAILED_SNAPSHOT_DIR}"; then
	fail 'aggregate rollback hid a restoration failure'
fi
[ -f "${FAILED_SNAPSHOT_DIR}/dnsmasq.postconf" ] || fail 'failed rollback discarded the recovery snapshot'
grep -q "${FAILED_SNAPSHOT_DIR}" "${TMP_DIR}/rollback-report" || fail 'failed rollback did not report the retained recovery snapshot path'

EVENT_SCRIPTS_ACTIVE_SNAPSHOT="${FAILED_SNAPSHOT_DIR}"
# rollback_pending_mode_migration must not run when no mode-migration snapshot exists.
rollback_pending_mode_migration() { fail 'event-hook recovery attempted a nonexistent mode rollback'; }
# adguard_restart_after_install_abort simulates successful service recovery.
adguard_restart_after_install_abort() { return 0; }
adguard_recover_after_event_hook_abort 1 || fail 'event-hook recovery without a mode migration reported failure'
[ "${EVENT_SCRIPTS_ACTIVE_SNAPSHOT}" = "${FAILED_SNAPSHOT_DIR}" ] || fail 'event-hook recovery detached a failed aggregate rollback without a mode migration'
[ -f "${FAILED_SNAPSHOT_DIR}/dnsmasq.postconf" ] || fail 'event-hook recovery deleted a failed aggregate rollback snapshot without a mode migration'

MODE_ROLLBACK_SNAPSHOT="${BASE_DIR}/post-migration-aggregate"
mkdir -p "${MODE_ROLLBACK_SNAPSHOT}" || fail 'could not create post-migration aggregate snapshot fixture'
printf '%s\n' 'manual recovery data' >"${MODE_ROLLBACK_SNAPSHOT}/dnsmasq.postconf"
EVENT_SCRIPTS_ACTIVE_SNAPSHOT="${MODE_ROLLBACK_SNAPSHOT}"
MODE_MIGRATION_YAML_FILE_BACKUP="${BASE_DIR}/mode-migration-yaml"
# all_event_scripts_restore succeeds in this scenario so an unexpected replay cannot satisfy the retained-path assertion through an earlier failure.
all_event_scripts_restore() { return 0; }
: >"${TMP_DIR}/rollback-report"
# rollback_pending_mode_migration simulates a successful restoration of the older mode snapshot.
rollback_pending_mode_migration() { return 0; }
# adguard_restart_after_install_abort simulates successful service recovery.
adguard_restart_after_install_abort() { return 0; }
adguard_recover_after_event_hook_abort 1 || fail 'successful mode rollback recovery reported failure'
[ -z "${EVENT_SCRIPTS_ACTIVE_SNAPSHOT:-}" ] || fail 'mode rollback left the newer aggregate snapshot active for EXIT replay'
[ ! -e "${MODE_ROLLBACK_SNAPSHOT}" ] || fail 'mode rollback retained a superseded aggregate snapshot'
grep -q 'Superseded event-hook rollback snapshot removed after mode rollback' "${TMP_DIR}/rollback-report" ||
	fail 'mode rollback did not report successful aggregate snapshot cleanup'

STOP_FAILURE_SNAPSHOT="${BASE_DIR}/stop-failure-aggregate"
mkdir -p "${STOP_FAILURE_SNAPSHOT}" || fail 'could not create stop-failure aggregate snapshot fixture'
printf '%s\n' 'retained recovery data' >"${STOP_FAILURE_SNAPSHOT}/dnsmasq.postconf"
EVENT_SCRIPTS_ACTIVE_SNAPSHOT="${STOP_FAILURE_SNAPSHOT}"
MODE_MIGRATION_YAML_FILE_BACKUP=""
dns_restore_calls=0
# agh_stop reports that the running installation could not be stopped.
agh_stop() { return 1; }
# nvram_transaction_lock_owned exposes a pending DNS/NVRAM recovery snapshot.
nvram_transaction_lock_owned() { return 0; }
# nvram_transaction_setup_committed reports that DNS/NVRAM restoration remains pending.
nvram_transaction_setup_committed() { return 1; }
# check_dns_environment records any unsafe attempt to restore DNS/NVRAM while the daemon is still running.
check_dns_environment() { dns_restore_calls="$((dns_restore_calls + 1))"; }
if adguard_recover_after_event_hook_abort 1 1; then
	fail 'failed post-readiness service stop was reported as recovered'
fi
[ "${dns_restore_calls}" -eq 0 ] || fail 'failed service stop restored DNS/NVRAM while the installation was still running'
[ "${EVENT_SCRIPTS_ACTIVE_SNAPSHOT}" = "${STOP_FAILURE_SNAPSHOT}" ] || fail 'failed service stop detached the recovery snapshot'
[ -f "${STOP_FAILURE_SNAPSHOT}/dnsmasq.postconf" ] || fail 'failed service stop discarded the recovery snapshot'

MODE_MIGRATION_YAML_FILE_BACKUP=""
EVENT_SCRIPTS_ACTIVE_SNAPSHOT=""
stop_calls=0
restart_calls=0
# nvram_transaction_lock_owned reports no pending DNS/NVRAM transaction for successful service recovery.
nvram_transaction_lock_owned() { return 1; }
# agh_stop records that the post-readiness daemon was stopped before recovery.
agh_stop() { stop_calls="$((stop_calls + 1))"; }
# adguard_restart_after_install_abort records service recovery after configuration rollback.
adguard_restart_after_install_abort() { restart_calls="$((restart_calls + 1))"; }
adguard_recover_after_event_hook_abort 1 1 || fail 'post-readiness service recovery reported failure'
[ "${stop_calls}" -eq 1 ] || fail 'post-readiness recovery did not stop the daemon before loading restored configuration'
[ "${restart_calls}" -eq 1 ] || fail 'post-readiness recovery did not restore the pre-install service state'

printf '%s\n' 'PASS: installer event-script transaction regression'
