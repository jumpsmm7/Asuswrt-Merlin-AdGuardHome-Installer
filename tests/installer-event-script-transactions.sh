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
for helper in add_init_event_scripts add_services_event_scripts remove_services_event_scripts add_firewall_event_scripts all_event_scripts_transaction_begin all_event_scripts_transaction_commit all_event_scripts_transaction_detach_after_mode_rollback all_event_scripts_transaction_rollback all_event_scripts_rollback all_event_scripts_recover_startup install_wan_event_scripts adguard_recover_after_event_hook_abort; do
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
all_event_scripts_transaction_begin "${BASE_DIR}/.AdGuardHome.event-hooks.wan" || fail 'WAN aggregate snapshot failed'
[ -f "${BASE_DIR}/.AdGuardHome.event-hooks-recovery" ] || fail 'WAN aggregate snapshot did not publish its recovery marker'
printf '%s\n' 'changed working YAML' >"${YAML_FILE}"
printf '%s\n' 'changed source YAML' >"${YAML_ORI}"
if install_wan_event_scripts; then
	fail 'WAN orchestration hid a later helper failure'
fi
all_event_scripts_transaction_rollback || fail 'WAN aggregate rollback failed'
[ ! -e "${BASE_DIR}/.AdGuardHome.event-hooks-recovery" ] || fail 'WAN aggregate rollback retained its obsolete recovery marker'
grep -qx 'original dnsmasq' "${TMP_DIR}/jffs/scripts/dnsmasq.postconf" || fail 'WAN rollback did not restore dnsmasq.postconf'
grep -qx 'original dnsmasq SDN' "${TMP_DIR}/jffs/scripts/dnsmasq-sdn.postconf" || fail 'WAN rollback did not restore dnsmasq-sdn.postconf'
grep -qx 'original init' "${TMP_DIR}/jffs/scripts/init-start" || fail 'WAN rollback did not restore init-start'
grep -qx 'original services-stop' "${TMP_DIR}/jffs/scripts/services-stop" || fail 'WAN rollback did not restore services-stop'
grep -qx 'original service-event-end' "${TMP_DIR}/jffs/scripts/service-event-end" || fail 'WAN rollback did not restore service-event-end'
grep -qx 'original firewall' "${TMP_DIR}/jffs/scripts/firewall-start" || fail 'WAN rollback did not restore firewall-start'
grep -qx 'ADGUARD_DNSMASQ_MODE="disabled"' "${CONF_FILE}" || fail 'WAN rollback did not restore dnsmasq configuration'
grep -qx 'original working YAML' "${YAML_FILE}" || fail 'WAN rollback did not restore the working YAML'
grep -qx 'original source YAML' "${YAML_ORI}" || fail 'WAN rollback did not restore the source YAML'

all_event_scripts_transaction_begin "${BASE_DIR}/.AdGuardHome.event-hooks.startup-retry" ||
	fail 'startup-retry aggregate snapshot failed'
printf '%s\n' 'interrupted dnsmasq change' >"${TMP_DIR}/jffs/scripts/dnsmasq.postconf"
EVENT_SCRIPTS_ACTIVE_SNAPSHOT=""
all_event_scripts_recover_startup || fail 'startup did not retry the retained aggregate rollback'
grep -qx 'original dnsmasq' "${TMP_DIR}/jffs/scripts/dnsmasq.postconf" ||
	fail 'startup recovery did not restore the retained dnsmasq hook'
[ ! -e "${BASE_DIR}/.AdGuardHome.event-hooks-recovery" ] ||
	fail 'successful startup recovery retained its obsolete marker'
[ ! -e "${BASE_DIR}/.AdGuardHome.event-hooks.startup-retry" ] ||
	fail 'successful startup recovery retained its obsolete snapshot'

ERROR=ERROR
WARNING=WARNING
# PTXT appends the provided text to the rollback report.
PTXT() { printf '%s\n' "$*" >>"${TMP_DIR}/rollback-report"; }
COMMIT_RETRY_SNAPSHOT="${BASE_DIR}/.AdGuardHome.event-hooks.commit-retry"
all_event_scripts_transaction_begin "${COMMIT_RETRY_SNAPSHOT}" || fail 'could not create commit retry snapshot fixture'
marker_remove_calls=0
# rm injects one recovery-marker removal failure before delegating to the real command.
rm() {
	if [ "$*" = "-f ${BASE_DIR}/.AdGuardHome.event-hooks-recovery" ]; then
		marker_remove_calls="$((marker_remove_calls + 1))"
		[ "${marker_remove_calls}" -gt 1 ] || return 1
	fi
	/bin/rm "$@"
}
all_event_scripts_transaction_commit || fail 'event-hook commit did not retry marker removal'
[ "${marker_remove_calls}" -eq 2 ] || fail 'event-hook commit did not make exactly two marker-removal attempts'
[ ! -e "${BASE_DIR}/.AdGuardHome.event-hooks-recovery" ] || fail 'successful event-hook commit retained its marker'
[ ! -e "${COMMIT_RETRY_SNAPSHOT}" ] || fail 'successful event-hook commit retained its snapshot'
unset -f rm 2>/dev/null || true

PARTIAL_CLEANUP_SNAPSHOT="${BASE_DIR}/.AdGuardHome.event-hooks.partial-cleanup"
all_event_scripts_transaction_begin "${PARTIAL_CLEANUP_SNAPSHOT}" || fail 'could not create partial cleanup snapshot fixture'
printf '%s\n' 'committed dnsmasq' >"${TMP_DIR}/jffs/scripts/dnsmasq.postconf"
# rm simulates a post-commit snapshot cleanup that deletes one entry before failing.
rm() {
	if [ "$*" = "-rf ${PARTIAL_CLEANUP_SNAPSHOT}" ]; then
		/bin/rm -f "${PARTIAL_CLEANUP_SNAPSHOT}/dnsmasq.postconf"
		return 1
	fi
	/bin/rm "$@"
}
all_event_scripts_transaction_commit || fail 'post-commit snapshot residue was treated as a rollback failure'
[ -z "${EVENT_SCRIPTS_ACTIVE_SNAPSHOT:-}" ] || fail 'post-commit snapshot residue remained active for rollback'
[ ! -e "${BASE_DIR}/.AdGuardHome.event-hooks-recovery" ] || fail 'partial snapshot cleanup recreated the recovery marker'
all_event_scripts_recover_startup || fail 'startup rejected marker-free post-commit residue'
grep -qx 'committed dnsmasq' "${TMP_DIR}/jffs/scripts/dnsmasq.postconf" || fail 'startup replayed a partially deleted snapshot'
unset -f rm 2>/dev/null || true
/bin/rm -rf "${PARTIAL_CLEANUP_SNAPSHOT}"

COMMIT_FAILURE_SNAPSHOT="${BASE_DIR}/.AdGuardHome.event-hooks.commit-failure"
printf '%s\n' 'original dnsmasq' >"${TMP_DIR}/jffs/scripts/dnsmasq.postconf"
all_event_scripts_transaction_begin "${COMMIT_FAILURE_SNAPSHOT}" || fail 'could not create commit failure snapshot fixture'
printf '%s\n' 'changed dnsmasq before failed commit' >"${TMP_DIR}/jffs/scripts/dnsmasq.postconf"
# rm persistently rejects recovery-marker removal while allowing other cleanup.
rm() {
	[ "$*" != "-f ${BASE_DIR}/.AdGuardHome.event-hooks-recovery" ] || return 1
	/bin/rm "$@"
}
if all_event_scripts_transaction_commit; then
	fail 'event-hook commit hid persistent marker-removal failure'
fi
[ "${EVENT_SCRIPTS_ACTIVE_SNAPSHOT}" = "${COMMIT_FAILURE_SNAPSHOT}" ] || fail 'failed commit detached its active snapshot'
[ -f "${BASE_DIR}/.AdGuardHome.event-hooks-recovery" ] || fail 'failed commit removed its recovery marker'
[ -d "${COMMIT_FAILURE_SNAPSHOT}" ] || fail 'failed commit removed its recovery snapshot'
if all_event_scripts_transaction_rollback; then
	fail 'event-hook rollback hid persistent marker-removal failure'
fi
grep -qx 'original dnsmasq' "${TMP_DIR}/jffs/scripts/dnsmasq.postconf" || fail 'failed commit rollback did not restore prior configuration'
[ "${EVENT_SCRIPTS_ACTIVE_SNAPSHOT}" = "${COMMIT_FAILURE_SNAPSHOT}" ] || fail 'incomplete rollback detached its active snapshot'
grep -q "${COMMIT_FAILURE_SNAPSHOT}" "${TMP_DIR}/rollback-report" || fail 'incomplete rollback did not report its retained snapshot'
unset -f rm 2>/dev/null || true
all_event_scripts_transaction_rollback || fail 'could not clean up retained commit-failure snapshot'

FAILED_SNAPSHOT_DIR="${BASE_DIR}/.AdGuardHome.event-hooks.failed-rollback"
all_event_scripts_transaction_begin "${FAILED_SNAPSHOT_DIR}" || fail 'could not create failed rollback snapshot fixture'
INFO=INFO
# nvram_transaction_lock_owned reports no active setup transaction for the hook-only fixtures.
nvram_transaction_lock_owned() { return 1; }
# all_event_scripts_restore restores all event-script files and reports failure when restoration is unsuccessful.
all_event_scripts_restore() { return 1; }
if all_event_scripts_transaction_rollback; then
	fail 'aggregate rollback hid a restoration failure'
fi
[ -f "${FAILED_SNAPSHOT_DIR}/dnsmasq.postconf" ] || fail 'failed rollback discarded the recovery snapshot'
[ -f "${BASE_DIR}/.AdGuardHome.event-hooks-recovery" ] || fail 'failed rollback discarded the durable recovery marker'
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

FAILED_COMMIT_SNAPSHOT="${BASE_DIR}/failed-commit-aggregate"
mkdir -p "${FAILED_COMMIT_SNAPSHOT}" || fail 'could not create failed-commit aggregate snapshot fixture'
printf '%s\n' 'retry recovery data' >"${FAILED_COMMIT_SNAPSHOT}/dnsmasq.postconf"
printf '%s\n' "${FAILED_COMMIT_SNAPSHOT}" >"${BASE_DIR}/.AdGuardHome.event-hooks-recovery"
EVENT_SCRIPTS_ACTIVE_SNAPSHOT="${FAILED_COMMIT_SNAPSHOT}"
MODE_MIGRATION_YAML_FILE_BACKUP="${BASE_DIR}/failed-commit-mode-migration"
restart_calls=0
nvram_restore_calls=0
# nvram_transaction_lock_owned exposes independent NVRAM recovery work.
nvram_transaction_lock_owned() { return 0; }
# nvram_transaction_setup_committed reports that the NVRAM transaction needs restoration.
nvram_transaction_setup_committed() { return 1; }
# setup_restore_nvram_journal records independent journal restoration.
setup_restore_nvram_journal() { nvram_restore_calls="$((nvram_restore_calls + 1))"; }
# installer_lan_domain_restore accepts fixture domain restoration.
installer_lan_domain_restore() { :; }
# restore_dns_filter_settings accepts fixture DNS-filter restoration.
restore_dns_filter_settings() { :; }
# check_dns_environment accepts fixture DNS-environment restoration.
check_dns_environment() { :; }
# adguard_restart_after_install_abort records independent service recovery.
adguard_restart_after_install_abort() { restart_calls="$((restart_calls + 1))"; }
adguard_recover_after_event_hook_abort 1 0 1 || fail 'failed event-hook rollback blocked independent abort recovery'
[ "${EVENT_SCRIPTS_ACTIVE_SNAPSHOT}" = "${FAILED_COMMIT_SNAPSHOT}" ] ||
	fail 'failed event-hook rollback detached its active recovery snapshot'
[ -f "${BASE_DIR}/.AdGuardHome.event-hooks-recovery" ] || fail 'failed event-hook rollback removed its recovery marker'
[ -f "${FAILED_COMMIT_SNAPSHOT}/dnsmasq.postconf" ] || fail 'failed event-hook rollback removed its recovery copy'
[ "${nvram_restore_calls}" -gt 0 ] || fail 'failed event-hook rollback skipped independent NVRAM recovery'
[ "${restart_calls}" -eq 1 ] || fail 'failed event-hook rollback skipped independent service recovery'
MODE_MIGRATION_YAML_FILE_BACKUP=""
all_event_scripts_transaction_rollback || fail 'startup-style event-hook rollback retry failed'
[ -z "${EVENT_SCRIPTS_ACTIVE_SNAPSHOT:-}" ] || fail 'successful event-hook rollback retry retained active state'
[ ! -e "${BASE_DIR}/.AdGuardHome.event-hooks-recovery" ] || fail 'successful event-hook rollback retry retained its marker'
[ ! -e "${FAILED_COMMIT_SNAPSHOT}" ] || fail 'successful event-hook rollback retry retained its snapshot'

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
