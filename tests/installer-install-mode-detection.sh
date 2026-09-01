#!/bin/sh
# Verify sw_mode no longer hard-exits LAN-mode install paths.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-install-mode-detection.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions"

# cleanup removes the temporary test workspace.
cleanup() {
	rm -rf "${TMP_ROOT}"
}

# fail prints a failure message to standard error and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

# extract_function writes a complete shell function, including nested brace groups, to the requested file.
extract_function() {
	_function_name="$1"
	_output_file="$2"
	awk -v name="${_function_name}" '
		$0 == name "() {" { copying = 1; found = 1 }
		copying {
			print
			line = $0
			opens = gsub(/\{/, "", line)
			line = $0
			closes = gsub(/\}/, "", line)
			depth += opens - closes
			if (depth == 0) { complete = 1; exit }
		}
		END { if (!found || !complete || depth != 0) exit 1 }
	' "${SCRIPT_PATH}" >"${_output_file}"
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"
mkdir -p "${TMP_ROOT}" || fail 'could not create test directory'

_extracted="$(sed -n \
	'/^conf_value() {$/,/^md5_is_valid() {$/p; /^write_conf() {$/,/^}$/p; /^ipv4_is_valid() {$/,/^port_is_valid() {$/p; /^setup_AdGuardHome() {$/,/^setup_amtmupdate() {$/p' \
	"${SCRIPT_PATH}")" || fail 'could not extract install mode helpers'
printf '%s\n' "${_extracted}" | sed '/^md5_is_valid() {$/d; /^port_is_valid() {$/d; /^setup_amtmupdate() {$/d' >"${FUNCTIONS_FILE}" ||
	fail 'could not extract install mode helpers'
extract_function rollback_pending_mode_migration "${TMP_ROOT}/rollback-function" &&
	cat "${TMP_ROOT}/rollback-function" >>"${FUNCTIONS_FILE}" ||
	fail 'could not extract pending migration rollback helper'
[ -s "${FUNCTIONS_FILE}" ] || fail 'install mode helper extraction was empty'
grep -q '^setup_AdGuardHome_impl() {$' "${FUNCTIONS_FILE}" ||
	fail 'setup orchestration helper is missing from the extracted functions'

grep -q '^adguard_install_mode_detect() {$' "${SCRIPT_PATH}" ||
	fail 'install mode detection helper is missing'
grep -q 'write_conf ADGUARD_INSTALL_MODE "\\"${ADGUARD_INSTALL_MODE}\\""' "${SCRIPT_PATH}" ||
	fail 'installer must persist ADGUARD_INSTALL_MODE'
grep -q 'PREVIOUS_ADGUARD_INSTALL_MODE="$(conf_value ADGUARD_INSTALL_MODE 2>/dev/null)"' "${SCRIPT_PATH}" ||
	fail 'installer must preserve the saved install mode before detection'
branch_doctor_line="$(grep -n '^if \[ "${2:-}" = "doctor" \]; then' "${SCRIPT_PATH}" | cut -d: -f1)"
startup_detection_line="$(grep -n '^PREVIOUS_ADGUARD_INSTALL_MODE=' "${SCRIPT_PATH}" | head -n 1 | cut -d: -f1)"
[ -n "${branch_doctor_line}" ] && [ "${branch_doctor_line}" -lt "${startup_detection_line}" ] ||
	fail 'branch-qualified doctor must dispatch before the fresh-install mode gate'
extract_function startup_action_allows_unknown_install_mode "${TMP_ROOT}/unknown-mode-action" ||
	fail 'could not extract unknown-mode recovery action helper'
(
	# shellcheck disable=SC1090
	. "${TMP_ROOT}/unknown-mode-action"
	for recovery_args in 'uninstall ' 'uninstall --yes' 'master uninstall' 'master 2'; do
		set -- ${recovery_args}
		startup_action_allows_unknown_install_mode "${1:-}" "${2:-}" ||
			fail "${recovery_args}: uninstall retry must bypass the fresh-install mode gate"
	done
	for gated_args in 'install --yes' 'update --yes' 'restore --yes' 'master install' 'master migrate-runtime-defaults' 'master 1'; do
		set -- ${gated_args}
		if startup_action_allows_unknown_install_mode "${1:-}" "${2:-}"; then
			fail "${gated_args}: mode-dependent action bypassed the fresh-install mode gate"
		fi
	done
) || exit $?
if sed -n '/^[[:space:]]*case "\$2" in$/,/^[[:space:]]*if menu_action_allowed "\$2"; then$/p' "${SCRIPT_PATH}" |
	grep -q 'migrate-runtime-defaults | \[mM\]'; then
	fail 'branch-qualified runtime migration must require confirmed install-mode detection'
fi
extract_function cli_action_requires_install_mode "${TMP_ROOT}/cli-mode-action" ||
	fail 'could not extract CLI install-mode action helper'
(
	# shellcheck disable=SC1090
	. "${TMP_ROOT}/cli-mode-action"
	for mode_action in install update restore; do
		cli_action_requires_install_mode "${mode_action}" ||
			fail "${mode_action} must detect the current install mode before CLI dispatch"
	done
	cli_action_requires_install_mode migrate-runtime-defaults ||
		fail 'migrate-runtime-defaults must require confirmed install-mode detection'
	for recovery_action in backup doctor status uninstall; do
		if cli_action_requires_install_mode "${recovery_action}"; then
			fail "${recovery_action} must remain available when install-mode detection fails"
		fi
	done
) || exit $?
extract_function backup_restore "${TMP_ROOT}/backup-restore" ||
	fail 'could not extract backup restore helper'
awk '
	/ptxt_ok "Installed staged AdGuardHome backup\."/ { installed = NR }
	/PREVIOUS_ADGUARD_INSTALL_MODE="\$\(conf_value ADGUARD_INSTALL_MODE 2>\/dev\/null\)"/ { restored_mode = NR }
	/if adguard_install_mode_confirmed && ! adguard_enforce_lan_ipset_disabled; then/ { enforcement = NR }
	END { exit(installed && restored_mode > installed && enforcement > restored_mode ? 0 : 1) }
' "${TMP_ROOT}/backup-restore" ||
	fail 'restore must capture the archived install mode before enforcing the detected router mode'
awk '
	/^case "\$\{1:-\}" in$/ { in_dispatch = 1 }
	in_dispatch && /if cli_action_requires_install_mode "\$\{1:-\}"; then/ { mode_actions = 1 }
	mode_actions && /adguard_install_mode_detect \|\| exit 1/ { detected = 1 }
	mode_actions && /cli_run "\$@"/ { exit(detected ? 0 : 1) }
	END { if (!in_dispatch || !mode_actions) exit 1 }
' "${SCRIPT_PATH}" || fail 'install/update/restore CLI dispatch does not detect install mode before cli_run'
grep -q 'adguard_migrate_detected_install_mode "${PREVIOUS_ADGUARD_INSTALL_MODE:-}"' "${SCRIPT_PATH}" ||
	fail 'install/update orchestration must migrate mode-dependent settings'
if sed -n '/^PREVIOUS_ADGUARD_INSTALL_MODE=/,/^if \[ "${ADGUARD_INSTALL_MODE}" = "wan" \]/p' "${SCRIPT_PATH}" |
	grep -q 'adguard_migrate_detected_install_mode'; then
	fail 'installer startup must not migrate mode-dependent settings before action dispatch'
fi
service_install_line="$(grep -n 'ptxt_ok "AdGuardHome service files installed\."' "${SCRIPT_PATH}" | cut -d: -f1)"
migration_line="$(grep -n 'adguard_migrate_detected_install_mode "${PREVIOUS_ADGUARD_INSTALL_MODE:-}"' "${SCRIPT_PATH}" | cut -d: -f1)"
[ -n "${service_install_line}" ] && [ -n "${migration_line}" ] && [ "${migration_line}" -gt "${service_install_line}" ] ||
	fail 'mode migration must run only after mode-aware service scripts are installed'
firewall_cleanup_line="$(awk -v after="${service_install_line}" 'NR > after && /^[[:space:]]*(if[[:space:]]+![[:space:]]+)?cleanup_legacy_firewall([[:space:]]*;[[:space:]]*then)?[[:space:]]*$/ { print NR; exit }' "${SCRIPT_PATH}")"
event_cleanup_line="$(grep -n 'yaml_nvars_file_action delete "#Asuswrt-Merlin AdGuardHome Installer" /jffs/scripts/dnsmasq.postconf' "${SCRIPT_PATH}" | head -n 1 | cut -d: -f1)"
[ -n "${firewall_cleanup_line}" ] && [ -n "${event_cleanup_line}" ] &&
	[ "${migration_line}" -lt "${firewall_cleanup_line}" ] && [ "${migration_line}" -lt "${event_cleanup_line}" ] ||
	fail 'mode migration must finish before firewall state or event hooks are changed'
extract_function adguard_migrate_detected_install_mode "${TMP_ROOT}/migration" ||
	fail 'could not extract install-mode migration helper'
wan_hooks_line="$(grep -n 'install_wan_event_scripts' "${TMP_ROOT}/migration" | cut -d: -f1)"
mode_write_line="$(grep -n 'write_conf ADGUARD_INSTALL_MODE' "${TMP_ROOT}/migration" | head -n 1 | cut -d: -f1)"
[ -n "${wan_hooks_line}" ] && [ -n "${mode_write_line}" ] && [ "${wan_hooks_line}" -lt "${mode_write_line}" ] ||
	fail 'LAN-to-WAN migration must install WAN event hooks before persisting WAN mode'
grep -q '! backup_mode_migration_wan_hooks "${hooks_backup}"' "${TMP_ROOT}/migration" &&
	grep -q '\[ "${previous_mode}" = "lan" \] && ! install_wan_event_scripts' "${TMP_ROOT}/migration" ||
	fail 'LAN-to-WAN migration does not preserve and synchronize WAN event scripts'
rollback_count="$(grep -c 'rollback_pending_mode_migration || return 2' "${TMP_ROOT}/migration")"
[ "${rollback_count}" -eq 4 ] ||
	fail 'mode migration failure paths do not propagate rollback failures'
grep -q 'MODE_MIGRATION_HOOKS_BACKUP="${hooks_backup}"' "${TMP_ROOT}/migration" ||
	fail 'mode migration does not retain hook rollback state for orchestration failures'
awk '
	/MODE_MIGRATION_YAML_ORI_BACKUP="\$\{yaml_ori_backup\}"/ { yaml_ori = NR }
	/MODE_MIGRATION_CONFIG_BACKUP="\$\{config_backup\}"/ { config = NR }
	/MODE_MIGRATION_HOOKS_BACKUP="\$\{hooks_backup\}"/ { hooks = NR }
	/MODE_MIGRATION_YAML_FILE_BACKUP="\$\{yaml_file_backup\}"/ { pending = NR }
	/setup_sync_mode_dependent_yaml_and_snapshot/ { sync = NR }
	END { exit(yaml_ori && config && hooks && pending > yaml_ori && pending > config && pending > hooks && sync > pending ? 0 : 1) }
' "${TMP_ROOT}/migration" || fail 'mode migration publishes pending state before rollback paths are complete'
awk '
	/if ! rm -rf "\$\{hooks_backup\}"; then/ { cleanup = 1; next }
	cleanup && /^[[:space:]]*fi[[:space:]]*$/ { exit 1 }
	cleanup && /Unable to clear stale mode-migration event-script backups/ { logged = 1; next }
	cleanup && logged && /^[[:space:]]*return 1[[:space:]]*$/ { guarded = 1; next }
	END { exit(guarded ? 0 : 1) }
' "${TMP_ROOT}/migration" || fail 'mode migration does not abort when stale hook backup cleanup fails'
extract_function backup_mode_migration_wan_hooks "${TMP_ROOT}/hook-backup" ||
	fail 'could not extract event-hook backup helper'
grep -Fq 'stage_dir="${1}.stage.$$"' "${TMP_ROOT}/hook-backup" &&
	grep -Fq 'mv "${stage_dir}" "${backup_dir}"' "${TMP_ROOT}/hook-backup" ||
	fail 'mode migration must publish event-hook backups only after staging completes'
extract_function restore_mode_migration_yaml "${TMP_ROOT}/yaml-restore" ||
	fail 'could not extract YAML migration restore helper'
grep -Fq 'mode-migration.restore.$$' "${TMP_ROOT}/yaml-restore" &&
	grep -Fq 'mv -f "${yaml_file_stage}" "${YAML_FILE}"' "${TMP_ROOT}/yaml-restore" &&
	grep -Fq 'mv -f "${yaml_ori_stage}" "${YAML_ORI}"' "${TMP_ROOT}/yaml-restore" ||
	fail 'mode migration YAML recovery must atomically publish staged files'
extract_function finalize_pending_mode_migration "${TMP_ROOT}/migration-finalize" ||
	fail 'could not extract mode migration finalizer'
grep -Fq '[ "${cleanup_status}" -eq 0 ] || PTXT' "${TMP_ROOT}/migration-finalize" ||
	fail 'mode migration finalization must not block service recovery on backup cleanup failure'
awk '
	/MODE_MIGRATION_YAML_FILE_BACKUP=""/ { detached = NR }
	/rm -f "\$\{yaml_file_backup\}"/ { cleanup = NR }
	END { exit(detached && cleanup > detached ? 0 : 1) }
' "${TMP_ROOT}/migration-finalize" || fail 'mode migration finalization exposes partially deleted backups to signal rollback'
awk '
	/MODE_MIGRATION_YAML_FILE_BACKUP=""/ { detached = NR }
	/rm -f "\$\{yaml_file_backup\}"/ { cleanup = NR }
	END { exit(detached && cleanup > detached ? 0 : 1) }
' "${TMP_ROOT}/rollback-function" || fail 'mode migration rollback exposes partially deleted backups to signal cleanup'
extract_function inst_AdGuardHome "${TMP_ROOT}/install-path" ||
	fail 'could not extract install orchestration path'
sed 's|/bin/grep|grep|g' "${TMP_ROOT}/install-path" >"${TMP_ROOT}/install-path.fixture" &&
	mv "${TMP_ROOT}/install-path.fixture" "${TMP_ROOT}/install-path" ||
	fail 'could not route extracted install-path grep calls through the fixture'
extract_function adguard_restart_after_install_abort "${TMP_ROOT}/install-abort-restart" ||
	fail 'could not extract install-abort restart helper'
extract_function adguard_recover_after_event_hook_abort "${TMP_ROOT}/event-hook-recovery" ||
	fail 'could not extract event-hook recovery helper'
awk '
	/agh_stop \|\| RESTART_RECOVERY_STATUS=1/ { stop = NR }
	/check_dns_environment 1 \|\| NVRAM_ROLLBACK_STATUS=1/ { restore = NR }
	END { exit(stop && restore > stop ? 0 : 1) }
' "${TMP_ROOT}/event-hook-recovery" ||
	fail 'event-hook abort recovery must stop AdGuardHome before restoring the DNS environment'
grep -Fq 'return "${MIGRATE_STATUS}"' "${TMP_ROOT}/install-path" ||
	fail 'install orchestration does not preserve migration rollback failure status'
awk '
	/inst_AdGuardHome "\$\{1:-update\}" "\$\{ADGUARD_BRANCH\}"/ { update_call = 1; next }
	update_call && /^[[:space:]]*$/ { next }
	update_call { exit($0 ~ /^[[:space:]]*return \$\?[[:space:]]*$/ ? 0 : 1) }
	END { if (!update_call) exit 1 }
' "${TMP_ROOT}/install-path" || fail 'recursive package update does not immediately propagate migration failure status'
# run_install_failure executes an injected cleanup or post-migration failure and verifies observable recovery behavior.
run_install_failure() (
	FAILURE_CASE="$1"
	CALLS_FILE="${TMP_ROOT}/legacy-cleanup-${FAILURE_CASE}"
	BASE_DIR="${TMP_ROOT}/legacy-base-${FAILURE_CASE}"
	TARG_DIR="${TMP_ROOT}/legacy-target-${FAILURE_CASE}"
	ADDON_DIR="${TMP_ROOT}/legacy-addon-${FAILURE_CASE}"
	AGH_FILE="${TARG_DIR}/AdGuardHome"
	SCRIPT_LOC="${TMP_ROOT}/missing-installer"
	CONF_FILE="${TMP_ROOT}/legacy-config-${FAILURE_CASE}"
	ADGUARD_ARCH="armv7"
	ADGUARD_INSTALL_MODE="wan"
	PREVIOUS_ADGUARD_INSTALL_MODE="wan"
	MODE_MIGRATION_YAML_FILE_BACKUP="${BASE_DIR}/mode-migration-yaml"
	SERVICE_REFRESH_ONLY=0
	RURL="https://example.invalid"
	URL_ARCH="https://example.invalid"
	ERROR='Error:'
	INFO='Info:'
	: >"${CALLS_FILE}"
	mkdir -p "${BASE_DIR}" "${TARG_DIR}" || fail "${FAILURE_CASE}: could not create cleanup fixture"
	# shellcheck disable=SC1090
	. "${TMP_ROOT}/install-abort-restart"
	# shellcheck disable=SC1090
	. "${TMP_ROOT}/event-hook-recovery"
	# shellcheck disable=SC1090
	. "${TMP_ROOT}/install-path"
	# ptxt_phase marks a test phase boundary.
	ptxt_phase() { :; }
	# ptxt_step provides a no-op progress-step hook.
	ptxt_step() { :; }
	# ptxt_ok is a no-op placeholder function.
	ptxt_ok() { :; }
	# ptxt_warn accepts warning messages without producing output.
	ptxt_warn() { :; }
	PTXT() { :; }
	# ensure_sha256sum_tool ensures the sha256sum tool is available.
	ensure_sha256sum_tool() { return 0; }
	# adguard_remote_archive returns the name of the fixture archive.
	adguard_remote_archive() { printf '%s\n' 'fixture.tar.gz'; }
	# adguard_remote_md5 computes the remote MD5 checksum for AdGuard.
	adguard_remote_md5() { :; }
	# adguard_remote_sha256 is a no-op placeholder for the remote SHA-256 value.
	adguard_remote_sha256() { :; }
	# adguard_remote_url prints the remote URL for the AdGuard fixture archive.
	adguard_remote_url() { printf '%s\n' 'https://example.invalid/fixture.tar.gz'; }
	# download_file creates an empty fixture archive when the requested path is the base directory.
	download_file() {
		case "$1" in
			"${BASE_DIR}") : >"${BASE_DIR}/fixture.tar.gz" ;;
		esac
	}
	# sha256_is_valid reports that the SHA-256 value is invalid.
	sha256_is_valid() { return 1; }
	# md5_is_valid determines whether an MD5 checksum is valid and always reports failure.
	md5_is_valid() { return 1; }
	# agh_process_count prints the process count as 1.
	agh_process_count() { printf '%s\n' '1'; }
	# install_adguard_archive creates an executable placeholder AdGuard Home archive script at `${AGH_FILE}`.
	install_adguard_archive() {
		cat >"${AGH_FILE}" <<'EOF'
#!/bin/sh
printf '%s\n' 'AdGuard Home version v0.0.0'
EOF
		chmod 755 "${AGH_FILE}"
	}
	# ln does nothing and always succeeds.
	ln() { return 0; }
	# rm preserves /opt/sbin/AdGuardHome and delegates other removals to /bin/rm.
	rm() {
		case "$*" in
			*'/opt/sbin/AdGuardHome'*) return 0 ;;
		esac
		/bin/rm "$@"
	}
	# create_dir creates the specified directory and any missing parent directories.
	create_dir() { mkdir -p "$1"; }
	# configure_runtime_defaults configures default runtime settings.
	configure_runtime_defaults() { return 0; }
	# adguard_install_mode_confirmed confirms that the AdGuard installation mode is known and valid.
	adguard_install_mode_confirmed() { return 0; }
	# adguard_migrate_detected_install_mode determines the detected installation mode for migration.
	adguard_migrate_detected_install_mode() { return 0; }
	# all_event_scripts_transaction_begin records the start of an event-script transaction.
	all_event_scripts_transaction_begin() { printf '%s\n' 'transaction:begin' >>"${CALLS_FILE}"; }
	# all_event_scripts_transaction_detach_after_mode_rollback detaches a newer aggregate snapshot after restoring the prior mode.
	all_event_scripts_transaction_detach_after_mode_rollback() { printf '%s\n' 'transaction:detach' >>"${CALLS_FILE}"; }
	# all_event_scripts_transaction_rollback records an event-script transaction rollback.
	all_event_scripts_transaction_rollback() { printf '%s\n' 'transaction:rollback' >>"${CALLS_FILE}"; }
	# all_event_scripts_transaction_commit records publication of the aggregate event-script transaction.
	all_event_scripts_transaction_commit() { printf '%s\n' 'transaction:commit' >>"${CALLS_FILE}"; }
	# nvram_transaction_lock_owned reports that these hook-failure fixtures have no active NVRAM transaction.
	nvram_transaction_lock_owned() { return 1; }
	# install_wan_event_scripts reports successful WAN event-script synchronization.
	install_wan_event_scripts() { return 0; }
	# rollback_pending_mode_migration records rollback and retains ownership only for the injected rollback failure.
	rollback_pending_mode_migration() {
		printf '%s\n' 'mode:rollback' >>"${CALLS_FILE}"
		[ "${FAILURE_CASE}" != "rollback" ] || return 1
		MODE_MIGRATION_YAML_FILE_BACKUP=""
		return 0
	}
	# cleanup_legacy_firewall reports whether the legacy firewall cleanup failure case is active.
	cleanup_legacy_firewall() {
		[ "${FAILURE_CASE}" != "firewall" ]
	}
	# legacy_firewall_cleanup_needed determines whether legacy firewall cleanup is required.
	legacy_firewall_cleanup_needed() { return 0; }
	# yaml_nvars_file_action determines whether the YAML NVRAM file action should proceed based on the configured failure case.
	yaml_nvars_file_action() {
		[ "${FAILURE_CASE}" != "dnsmasq" ]
	}
	# grep filters selected script invocations during failure-case tests and delegates all other searches to the system grep.
	grep() {
		case "$*" in
			*"/jffs/scripts/${FAILURE_CASE}"*)
				case "$*" in *' &'*) return 1 ;; *) return 0 ;; esac
				;;
			*'/jffs/scripts/init-start'* | *'/jffs/scripts/services-stop'*) return 1 ;;
		esac
		/bin/grep "$@"
	}
	# del_jffs_script records a hook-removal request and reports failure.
	del_jffs_script() {
		printf '%s\n' "hook-remove:$1" >>"${CALLS_FILE}"
		return 1
	}
	# adguard_install_abort_trap_disable_preserve_defer provides a no-op hook for preserving deferred abort-trap handling.
	adguard_install_abort_trap_disable_preserve_defer() { :; }
	# agh_is_running reports that the service is not running.
	agh_is_running() { return 1; }
	# agh_wait_started records the independently observed monitor recovery.
	agh_wait_started() {
		printf '%s\n' 'monitor:restarted' >>"${CALLS_FILE}"
	}
	# agh_start records service recovery without simulating monitor recovery.
	agh_start() {
		printf '%s\n' 'service:restarted' >>"${CALLS_FILE}"
	}
	# rollback_result_write records a rollback result in the calls log.
	rollback_result_write() { printf '%s\n' "rollback-result:$*" >>"${CALLS_FILE}"; }
	# rollback_result_notice performs no operation.
	rollback_result_notice() { :; }
	# set_timezone injects the timezone failure or records successful timezone setup.
	set_timezone() {
		printf '%s\n' 'timezone' >>"${CALLS_FILE}"
		[ "${FAILURE_CASE}" != "timezone" ] && [ "${FAILURE_CASE}" != "rollback" ]
	}
	# setup_AdGuardHome injects the first-run setup failure when requested.
	setup_AdGuardHome() {
		printf '%s\n' 'setup' >>"${CALLS_FILE}"
		[ "${FAILURE_CASE}" != "setup" ]
	}
	# agh_complete_startup injects readiness failure after recording the check.
	agh_complete_startup() {
		printf '%s\n' 'readiness' >>"${CALLS_FILE}"
		[ "${FAILURE_CASE}" != "readiness" ]
	}
	# agh_stop records removal of the newly started process before service restoration.
	agh_stop() { printf '%s\n' 'service:stopped' >>"${CALLS_FILE}"; }
	# finalize_dns_environment records finalization and injects its failure when requested.
	finalize_dns_environment() {
		printf '%s\n' 'dns:finalize' >>"${CALLS_FILE}"
		[ "${FAILURE_CASE}" != "finalization" ]
	}
	# finalize_pending_mode_migration records successful post-readiness migration finalization.
	finalize_pending_mode_migration() { printf '%s\n' 'mode:finalize' >>"${CALLS_FILE}"; }
	# end_op_message records the operation status in the calls log.
	end_op_message() { printf '%s\n' "end-status:$1" >>"${CALLS_FILE}"; }
	install_action=update
	case "${FAILURE_CASE}" in
		timezone | setup | readiness | rollback) install_action=install ;;
	esac
	if inst_AdGuardHome "${install_action}" release; then
		fail "${FAILURE_CASE}: injected installation failure returned success"
	else
		cleanup_status=$?
	fi
	expected_status=1
	[ "${FAILURE_CASE}" != "rollback" ] || expected_status=2
	[ "${cleanup_status}" -eq "${expected_status}" ] || fail "${FAILURE_CASE}: unexpected cleanup exit status ${cleanup_status}"
	grep -qx 'transaction:begin' "${CALLS_FILE}" || fail "${FAILURE_CASE}: transaction did not begin"
	grep -qx 'transaction:rollback' "${CALLS_FILE}" || fail "${FAILURE_CASE}: aggregate rollback was not attempted"
	grep -qx 'mode:rollback' "${CALLS_FILE}" || fail "${FAILURE_CASE}: mode rollback was not attempted"
	grep -qx 'service:restarted' "${CALLS_FILE}" || fail "${FAILURE_CASE}: service recovery was not attempted"
	grep -qx 'monitor:restarted' "${CALLS_FILE}" || fail "${FAILURE_CASE}: monitor recovery was not attempted"
	grep -q '^rollback-result:install-abort rollback complete ' "${CALLS_FILE}" || fail "${FAILURE_CASE}: successful rollback result was not recorded"
	grep -qx 'end-status:1' "${CALLS_FILE}" || fail "${FAILURE_CASE}: failure completion status was not reported"
	rollback_line="$(grep -n '^transaction:rollback$' "${CALLS_FILE}" | head -n 1 | cut -d: -f1)"
	mode_line="$(grep -n '^mode:rollback$' "${CALLS_FILE}" | head -n 1 | cut -d: -f1)"
	restart_line="$(grep -n '^service:restarted$' "${CALLS_FILE}" | head -n 1 | cut -d: -f1)"
	end_line="$(grep -n '^end-status:1$' "${CALLS_FILE}" | head -n 1 | cut -d: -f1)"
	[ "${rollback_line}" -lt "${mode_line}" ] && [ "${mode_line}" -lt "${restart_line}" ] && [ "${restart_line}" -lt "${end_line}" ] ||
		fail "${FAILURE_CASE}: rollback and service recovery calls occurred out of order"
	case "${FAILURE_CASE}" in
		finalization)
			grep -qx 'dns:finalize' "${CALLS_FILE}" || fail 'finalization: injected finalizer was not reached'
			;;
		readiness)
			grep -qx 'readiness' "${CALLS_FILE}" || fail 'readiness: injected readiness check was not reached'
			if grep -q '^dns:finalize$' "${CALLS_FILE}"; then
				fail 'readiness: DNS finalization ran after readiness failed'
			fi
			;;
		timezone)
			grep -qx 'timezone' "${CALLS_FILE}" || fail 'timezone: injected timezone setup was not reached'
			if grep -q '^setup$' "${CALLS_FILE}"; then
				fail 'timezone: first-run setup ran after timezone setup failed'
			fi
			;;
		setup)
			grep -qx 'setup' "${CALLS_FILE}" || fail 'setup: injected first-run setup was not reached'
			if grep -q '^readiness$' "${CALLS_FILE}"; then
				fail 'setup: readiness ran after first-run setup failed'
			fi
			;;
	esac
	case "${FAILURE_CASE}" in
		finalization | readiness)
			stop_line="$(grep -n '^service:stopped$' "${CALLS_FILE}" | head -n 1 | cut -d: -f1)"
			[ -n "${stop_line}" ] && [ "${stop_line}" -lt "${restart_line}" ] ||
				fail "${FAILURE_CASE}: replacement service was not stopped before previous service recovery"
			;;
	esac
	case "${FAILURE_CASE}" in
		firewall | dnsmasq | init-start | services-stop | finalization | timezone | setup | readiness)
			[ -z "${MODE_MIGRATION_YAML_FILE_BACKUP}" ] || fail "${FAILURE_CASE}: successful rollback retained migration ownership"
			;;
		rollback)
			[ -n "${MODE_MIGRATION_YAML_FILE_BACKUP}" ] || fail 'rollback: failed rollback discarded migration ownership'
			;;
	esac
)

for legacy_cleanup_failure in firewall dnsmasq init-start services-stop; do
	run_install_failure "${legacy_cleanup_failure}" ||
		fail "${legacy_cleanup_failure}: legacy cleanup recovery scenario failed"
done
for recovery_failure in finalization readiness timezone setup rollback; do
	run_install_failure "${recovery_failure}" ||
		fail "${recovery_failure}: install recovery scenario failed"
done
grep -q 'Unable to install the required WAN-mode event scripts' "${TMP_ROOT}/migration" ||
	fail 'LAN-to-WAN migration does not abort when WAN event-script synchronization fails'
grep -q 'wan:lan | lan:wan | :lan)' "${SCRIPT_PATH}" ||
	fail 'installer must migrate legacy installs without a saved mode when LAN mode is detected'
grep -Fq '[ "${PREVIOUS_ADGUARD_INSTALL_MODE:-}" = "wan" ] || [ -z "${PREVIOUS_ADGUARD_INSTALL_MODE:-}" ]' "${FUNCTIONS_FILE}" ||
	fail 'legacy WAN migration rollback does not restore active firewall state'
# Behavioral test: verify that the installer properly handles LAN mode by checking
# that setup_AdGuardHome_impl invokes check_dns_filter and configure_runtime_defaults
# correctly for LAN mode without DNS filter selection.
(
	# shellcheck disable=SC1090
	WRAPPED_FUNCTIONS="${TMP_ROOT}/functions-wrapped"
	extract_function configure_runtime_defaults "${TMP_ROOT}/original-runtime-defaults" ||
		fail 'could not extract configure_runtime_defaults for wrapping'
	sed 's/^configure_runtime_defaults() {$/_original_configure_runtime_defaults() {/' \
		"${TMP_ROOT}/original-runtime-defaults" >"${WRAPPED_FUNCTIONS}" ||
		fail 'could not rename extracted configure_runtime_defaults'
	cat >>"${WRAPPED_FUNCTIONS}" <<'EOF'
configure_runtime_defaults() {
	printf '%s\n' 'configure_runtime_defaults' >>"${CALLS_FILE}"
	_original_configure_runtime_defaults "$@"
}
EOF
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	# shellcheck disable=SC1090
	. "${WRAPPED_FUNCTIONS}"

	# Mock environment for LAN mode without DNS filter selection
	BASE_DIR="${TMP_ROOT}"
	ADGUARD_INSTALL_MODE="lan"
	DNS_FILTER_SELECTION=""
	CONF_FILE="${TMP_ROOT}/AdGuardHome.conf"
	YAML_FILE="${TMP_ROOT}/AdGuardHome.yaml"
	YAML_ORI="${TMP_ROOT}/AdGuardHome.yaml.ori"
	TARG_DIR="${TMP_ROOT}/target"
	AGH_FILE="${TARG_DIR}/AdGuardHome"
	CALLS_FILE="${TMP_ROOT}/calls"

	# Create minimal installer environment
	mkdir -p "${TARG_DIR}" || fail 'could not create target directory'
	cat >"${AGH_FILE}" <<'AGH_STUB'
#!/bin/sh
printf '%s\n' 'AdGuard Home, version test Schema version: 27'
AGH_STUB
	chmod 755 "${AGH_FILE}" || fail 'could not create AdGuardHome stub'
	: >"${CONF_FILE}"
	: >"${CALLS_FILE}"

	# assert_count verifies that a pattern appears in the calls file the expected number of times.
	assert_count() {
		pattern="$1"
		expected="$2"
		message="$3"
		actual="$(grep -c "${pattern}" "${CALLS_FILE}" 2>/dev/null)" || actual=0
		[ "${actual}" -eq "${expected}" ] || fail "${message}: found ${actual}, expected ${expected}"
	}

	# Stub dependencies called by setup_AdGuardHome_impl
	INFO='Info:'
	ERROR='Error:'
	WARNING='Warning:'
	# PTXT prints each argument on a separate line.
	PTXT() { printf '%s\n' "$@"; }
	# ptxt_ok performs no action.
	ptxt_ok() { :; }
	# create_dir creates the specified directory and any required parent directories.
	create_dir() { mkdir -p "$1"; }
	# read_input_port sets the web interface port to 3000.
	read_input_port() { WEB_PORT=3000; }
	# read_input_dns sets a default primary bootstrap DNS address or assigns a secondary address when the primary is already set.
	read_input_dns() {
		if [ -z "${BOOTSTRAP1:-}" ]; then
			BOOTSTRAP1=9.9.9.9
		else
			BOOTSTRAP2=8.8.8.8
		fi
	}
	# read_yesno prompts for and evaluates a yes-or-no response.
	read_yesno() { return 1; }
	# AdGuardHome_authen appends the default administrator account configuration to the specified file.
	AdGuardHome_authen() {
		printf '%s\n' 'users:' '- name: admin' '  password: hash' >>"$2"
	}
	# check_AdGuardHome_yaml checks the AdGuard Home YAML configuration.
	check_AdGuardHome_yaml() { :; }
	# save_dns_filter_settings creates the specified directory for DNS filter settings.
	save_dns_filter_settings() { mkdir -p "$1"; }
	# restore_dns_filter_settings removes the file or directory at the specified path.
	restore_dns_filter_settings() { rm -rf "$1"; }
	# installer_lan_domain_set marks the LAN domain as configured.
	installer_lan_domain_set() { :; }
	# installer_lan_domain_restore restores an interrupted LAN-domain configuration transaction.
	installer_lan_domain_restore() { :; }
	# nvram_transaction_finalize_setup_pair records the committed NVRAM setup and removes temporary setup files.
	nvram_transaction_finalize_setup_pair() {
		mkdir -p "${BASE_DIR}/.AdGuardHome.nvram" || return 1
		: >"${BASE_DIR}/.AdGuardHome.nvram/setup-committed" || return 1
		rm -rf "${BASE_DIR}/.AdGuardHome.nvram/setup-files" 2>/dev/null || true
		return 0
	}
	# nvram_transaction_setup_committed reports whether the setup commit marker exists.
	nvram_transaction_setup_committed() { [ -f "${BASE_DIR}/.AdGuardHome.nvram/setup-committed" ]; }
	# nvram_transaction_lock_owned reports that this isolated setup fixture owns its transaction lock.
	nvram_transaction_lock_owned() { return 0; }
	# nvram_transaction_setup_files_begin creates a setup journal and records the existing configuration or its absence for rollback.
	nvram_transaction_setup_files_begin() {
		printf '%s\n' 'nvram_transaction_setup_files_begin' >>"${CALLS_FILE}"
		local journal_root
		journal_root="${BASE_DIR}/.AdGuardHome.nvram/setup-files"
		[ ! -e "${journal_root}" ] || return 1
		mkdir -p "${journal_root}" || return 1
		: >"${journal_root}/yaml-file.absent"
		: >"${journal_root}/yaml-original.absent"
		if [ -f "${CONF_FILE}" ]; then
			cp -p "${CONF_FILE}" "${journal_root}/config" || return 1
		else
			: >"${journal_root}/config.absent"
		fi
		return 0
	}
	# nvram_transaction_setup_files_restore indicates successful setup-file restoration.
	nvram_transaction_setup_files_restore() { return 0; }
	# check_dns_filter records a DNS filter check invocation and succeeds.
	check_dns_filter() {
		printf '%s\n' 'check_dns_filter' >>"${CALLS_FILE}"
		return 0
	}
	# check_dns_local checks local DNS availability.
	check_dns_local() { :; }
	# check_ipset checks whether the required ipset functionality is available.
	check_ipset() { :; }
	# adguard_ipset_allowed checks whether ipset functionality is permitted for the current install mode.
	adguard_ipset_allowed() {
		printf '%s\n' 'adguard_ipset_allowed' >>"${CALLS_FILE}"
		case "${ADGUARD_INSTALL_MODE:-}" in
			lan) return 1 ;;
		esac
		return 0
	}
	# ai_have_cmd always reports that the requested command is unavailable.
	ai_have_cmd() { return 1; }
	# nvram returns predefined test values for selected keys and accepts set and commit operations.
	nvram() {
		case "${1:-}:${2:-}" in
			get:sw_mode) printf '%s\n' '2' ;;
			get:lan_ipaddr) printf '%s\n' '192.168.50.1' ;;
			get:lan_ifname) printf '%s\n' '' ;;
			get:dns_local_cache) printf '%s\n' '1' ;;
			get:ipv6_rtr_addr) printf '%s\n' '' ;;
			get:lan_domain) printf '%s\n' 'lan' ;;
			get:lan_gateway) printf '%s\n' '192.168.1.1' ;;
			set:*) : ;;
			commit:) : ;;
			*) return 1 ;;
		esac
	}

	# Invoke the real setup entry point
	STDERR_OUTPUT="${TMP_ROOT}/setup-stderr"
	if ! setup_AdGuardHome_impl '' install >"${TMP_ROOT}/setup-stdout" 2>"${STDERR_OUTPUT}"; then
		cat "${STDERR_OUTPUT}" >&2
		fail 'setup_AdGuardHome_impl failed for LAN mode without DNS filter selection'
	fi
	if grep -Eq 'command not found|not found' "${STDERR_OUTPUT}"; then
		cat "${STDERR_OUTPUT}" >&2
		fail 'setup_AdGuardHome_impl encountered missing command in LAN mode test'
	fi

	# Assert that check_dns_filter was not called in LAN mode without DNS filter selection
	assert_count '^check_dns_filter$' 0 'check_dns_filter must not be called in LAN mode without DNS filter selection'

	# Assert that configure_runtime_defaults was called exactly once
	assert_count '^configure_runtime_defaults$' 1 'configure_runtime_defaults call count mismatch'

	# Assert that nvram_transaction_setup_files_begin was called (journal creation)
	assert_count '^nvram_transaction_setup_files_begin$' 1 'nvram transaction journal creation call count mismatch'

	# Verify journal directory was removed after successful finalization
	if [ -e "${BASE_DIR}/.AdGuardHome.nvram/setup-files" ]; then
		fail 'setup_AdGuardHome_impl did not remove NVRAM transaction journal directory after successful finalization'
	fi

	# Verify install mode was persisted
	grep -q '^ADGUARD_INSTALL_MODE="lan"$' "${CONF_FILE}" ||
		fail 'setup_AdGuardHome_impl did not persist LAN install mode'
) || exit $?
grep -q 'if \[ "${ADGUARD_INSTALL_MODE:-wan}" = "wan" \]; then' "${SCRIPT_PATH}" ||
	fail 'DNS environment restore must be gated by WAN install mode'
grep -q 'installer_lan_domain_restore || PTXT' "${SCRIPT_PATH}" ||
	fail 'installer exit must restore interrupted LAN-domain transactions'
grep -q 'if \[ ! -f "${AGH_FILE}" \]; then' "${SCRIPT_PATH}" ||
	fail 'DNS environment restore must remain limited to an absent local installation'
grep -q 'configure_runtime_defaults new-install "${ADGUARD_INSTALL_MODE:-wan}" "${LOCAL_CACHE_SELECTION:-0}"' "${SCRIPT_PATH}" ||
	fail 'runtime defaults must receive install mode before local cache selection'
if grep -q '\[ "$(nvram get sw_mode)" != "1" \].*exit 1' "${SCRIPT_PATH}"; then
	fail 'installer must not hard-exit on non-router sw_mode'
fi

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

ERROR='Error:'

# PTXT prints its arguments as a single line.
PTXT() {
	printf '%s\n' "$*"
}

# Verify every recovery operation can block restart by retaining pending state and returning failure.
(
	for failed_restore in yaml config hooks; do
		MODE_MIGRATION_YAML_FILE_BACKUP="${TMP_ROOT}/yaml-backup"
		MODE_MIGRATION_YAML_ORI_BACKUP="${TMP_ROOT}/yaml-ori-backup"
		MODE_MIGRATION_CONFIG_BACKUP="${TMP_ROOT}/config-backup"
		MODE_MIGRATION_HOOKS_BACKUP="${TMP_ROOT}/hooks-backup"
		PREVIOUS_ADGUARD_INSTALL_MODE=lan
		ADDON_DIR="${TMP_ROOT}/addon"
		rm -rf "${MODE_MIGRATION_HOOKS_BACKUP}"
		mkdir -p "${MODE_MIGRATION_HOOKS_BACKUP}" || fail 'could not create hook backup fixture'
		: >"${MODE_MIGRATION_YAML_FILE_BACKUP}" || fail 'could not create YAML backup fixture'
		: >"${MODE_MIGRATION_YAML_ORI_BACKUP}" || fail 'could not create original YAML backup fixture'
		: >"${MODE_MIGRATION_CONFIG_BACKUP}" || fail 'could not create installer backup fixture'
		: >"${MODE_MIGRATION_HOOKS_BACKUP}/firewall-start" || fail 'could not create hook file fixture'
		# restore_mode_migration_yaml reports whether YAML state restoration succeeded.
		restore_mode_migration_yaml() { [ "${failed_restore}" != yaml ]; }
		# restore_installer_config restores the installer configuration and reports whether the restoration succeeded.
		restore_installer_config() { [ "${failed_restore}" != config ]; }
		# restore_mode_migration_wan_hooks reports whether WAN event-hook restoration succeeded.
		restore_mode_migration_wan_hooks() { [ "${failed_restore}" != hooks ]; }
		# discard_installer_config_backup discards the backup of the installer configuration.
		discard_installer_config_backup() { :; }
		if rollback_pending_mode_migration >/dev/null 2>&1; then
			fail "${failed_restore} rollback failure was reported as success"
		fi
		[ -f "${MODE_MIGRATION_YAML_FILE_BACKUP}" ] &&
			[ -f "${MODE_MIGRATION_YAML_ORI_BACKUP}" ] &&
			[ -f "${MODE_MIGRATION_CONFIG_BACKUP}" ] &&
			[ -f "${MODE_MIGRATION_HOOKS_BACKUP}/firewall-start" ] ||
			fail "${failed_restore} rollback failure discarded recovery artifacts"
	done
) || exit $?

# run_case executes an install-mode detection test case and fails if the result does not match the expected status or mode.
run_case() {
	case_name="$1"
	sw_value="$2"
	lan_value="$3"
	expected_status="$4"
	expected_mode="$5"

	ADGUARD_INSTALL_MODE=""
	nvram() {
		case "${1:-}:${2:-}" in
			get:sw_mode) printf '%s\n' "${sw_value}" ;;
			get:lan_ipaddr) printf '%s\n' "${lan_value}" ;;
			*) return 1 ;;
		esac
	}

	if adguard_install_mode_detect >/dev/null 2>&1; then
		actual_status="0"
	else
		actual_status="1"
	fi

	if [ "${actual_status}" != "${expected_status}" ]; then
		fail "${case_name}: expected status ${expected_status}, got ${actual_status}"
	fi
	if [ "${ADGUARD_INSTALL_MODE:-}" != "${expected_mode}" ]; then
		fail "${case_name}: expected mode ${expected_mode}, got ${ADGUARD_INSTALL_MODE:-empty}"
	fi
}

run_case router-wan 1 192.168.50.1 0 wan
run_case repeater-lan 2 192.168.50.1 0 lan
run_case ap-lan 3 192.168.50.1 0 lan
run_case media-bridge-lan 4 192.168.50.1 0 lan
run_case unknown-non-router 9 192.168.50.1 0 ""
run_case repeater-without-lan-ip 2 "" 0 ""
run_case ap-with-invalid-lan-ip 3 999.168.50.1 0 ""
run_case ap-with-wildcard-lan-ip 3 0.0.0.0 0 ""
run_case ap-with-loopback-lan-ip 3 127.0.0.1 0 ""
run_case ap-with-multicast-lan-ip 3 224.0.0.1 0 ""
run_case missing-sw-mode-with-lan-ip "" 192.168.50.1 0 ""
run_case missing-sw-mode-without-lan-ip "" "" 0 ""
run_case missing-sw-mode-with-invalid-lan-ip "" 999.168.50.1 0 ""

printf '%s\n' 'PASS: installer install-mode detection reports WAN, LAN, and unknown states'
