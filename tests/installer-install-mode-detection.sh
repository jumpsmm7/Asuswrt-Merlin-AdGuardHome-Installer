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

sed -n '/^ipv4_is_valid() {$/,/^port_is_valid() {$/p' "${SCRIPT_PATH}" | sed '$d' >"${FUNCTIONS_FILE}" ||
	fail 'could not extract install mode helpers'
extract_function rollback_pending_mode_migration "${TMP_ROOT}/rollback-function" &&
	cat "${TMP_ROOT}/rollback-function" >>"${FUNCTIONS_FILE}" ||
	fail 'could not extract pending migration rollback helper'
[ -s "${FUNCTIONS_FILE}" ] || fail 'install mode helper extraction was empty'

grep -q '^adguard_install_mode_detect() {$' "${SCRIPT_PATH}" ||
	fail 'install mode detection helper is missing'
grep -q 'write_conf ADGUARD_INSTALL_MODE "\\"${ADGUARD_INSTALL_MODE}\\""' "${SCRIPT_PATH}" ||
	fail 'installer must persist ADGUARD_INSTALL_MODE'
grep -q 'PREVIOUS_ADGUARD_INSTALL_MODE="$(conf_value ADGUARD_INSTALL_MODE 2>/dev/null)"' "${SCRIPT_PATH}" ||
	fail 'installer must preserve the saved install mode before detection'
extract_function backup_restore "${TMP_ROOT}/backup-restore" ||
	fail 'could not extract backup restore helper'
awk '
	/ptxt_ok "Installed staged AdGuardHome backup\."/ { installed = NR }
	/PREVIOUS_ADGUARD_INSTALL_MODE="\$\(conf_value ADGUARD_INSTALL_MODE 2>\/dev\/null\)"/ { restored_mode = NR }
	/if ! adguard_enforce_lan_ipset_disabled; then/ { enforcement = NR }
	END { exit(installed && restored_mode > installed && enforcement > restored_mode ? 0 : 1) }
' "${TMP_ROOT}/backup-restore" ||
	fail 'restore must capture the archived install mode before enforcing the detected router mode'
awk '
	/^case "\$\{1:-\}" in$/ { in_dispatch = 1 }
	in_dispatch && /install \| update \| restore\)/ { mode_actions = 1 }
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
firewall_cleanup_line="$(awk -v after="${service_install_line}" 'NR > after && /^[[:space:]]*cleanup_legacy_firewall$/ { print NR; exit }' "${SCRIPT_PATH}")"
event_cleanup_line="$(grep -n 'yaml_nvars_delete "#Asuswrt-Merlin AdGuardHome Installer" /jffs/scripts/dnsmasq.postconf' "${SCRIPT_PATH}" | head -n 1 | cut -d: -f1)"
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
grep -Fq 'if ! finalize_pending_mode_migration; then' "${TMP_ROOT}/install-path" ||
	fail 'install orchestration must propagate mode migration finalization failures'
awk '
	/if ! finalize_pending_mode_migration; then/ { failure = 1; next }
	failure && /adguard_restart_after_install_abort "\$\{RESTART_AFTER_ABORT\}"/ { restarted = 1; next }
	failure && /end_op_message 1 "\$1"/ { exit(restarted ? 0 : 1) }
	END { if (!failure || !restarted) exit 1 }
' "${TMP_ROOT}/install-path" || fail 'finalization failure does not restart the previous installation'
grep -Fq 'return "${MIGRATE_STATUS}"' "${TMP_ROOT}/install-path" ||
	fail 'install orchestration does not preserve migration rollback failure status'
awk '
	/inst_AdGuardHome "\$\{1:-update\}" "\$\{ADGUARD_BRANCH\}"/ { update_call = 1; next }
	update_call && /^[[:space:]]*$/ { next }
	update_call { exit($0 ~ /^[[:space:]]*return \$\?[[:space:]]*$/ ? 0 : 1) }
	END { if (!update_call) exit 1 }
' "${TMP_ROOT}/install-path" || fail 'recursive package update does not immediately propagate migration failure status'

awk '
	/if ! agh_complete_startup; then/ { readiness = NR }
	/if ! finalize_pending_mode_migration; then/ { finalize = NR }
	END { exit(readiness && finalize > readiness ? 0 : 1) }
' "${TMP_ROOT}/install-path" || fail 'mode migration is finalized before post-install readiness succeeds'
awk '
	/if ! set_timezone; then/ { failure = "timezone" }
	/if ! setup_AdGuardHome "" "\$\{1:-install\}"; then/ { failure = "setup" }
	/if ! agh_complete_startup; then/ { failure = "readiness" }
	failure && /rollback_pending_mode_migration/ { rollback[failure] = 1 }
	failure && /end_op_message 1/ {
		if (!rollback[failure]) exit 1
		failure = ""
	}
	END { exit(rollback["timezone"] && rollback["setup"] && rollback["readiness"] ? 0 : 1) }
' "${TMP_ROOT}/install-path" || fail 'post-migration failure paths can re-enter the menu before rollback'
awk '
	/adguard_migrate_detected_install_mode/ { migration = 1; next }
	migration && /MIGRATE_STATUS=\$\?/ { status = 1; next }
	status && /\[ "\$\{MIGRATE_STATUS\}" -eq 2 \] \|\| adguard_restart_after_install_abort/ { guarded = 1; exit }
	END { exit(guarded ? 0 : 1) }
' "${TMP_ROOT}/install-path" || fail 'migration rollback failure does not block the previous installation restart'
awk '
	/Required service-event-end hook could not be configured/ { failure = 1; next }
	failure && /if rollback_pending_mode_migration; then/ { rollback = 1; next }
	rollback && /adguard_restart_after_install_abort/ { verified = 1; exit }
	failure && /return 1/ { exit 1 }
	END { exit(verified ? 0 : 1) }
' "${TMP_ROOT}/install-path" || fail 'service-event failure does not require successful rollback before restart'
grep -q 'Unable to install the required WAN-mode event scripts' "${TMP_ROOT}/migration" ||
	fail 'LAN-to-WAN migration does not abort when WAN event-script synchronization fails'
grep -q 'wan:lan | lan:wan | :lan)' "${SCRIPT_PATH}" ||
	fail 'installer must migrate legacy installs without a saved mode when LAN mode is detected'
grep -Fq '[ "${PREVIOUS_ADGUARD_INSTALL_MODE:-}" = "wan" ] || [ -z "${PREVIOUS_ADGUARD_INSTALL_MODE:-}" ]' "${FUNCTIONS_FILE}" ||
	fail 'legacy WAN migration rollback does not restore active firewall state'
grep -q 'if \[ "${ADGUARD_INSTALL_MODE}" = "wan" \] && \[ -n "${NAT_ENV}" \]' "${SCRIPT_PATH}" ||
	fail 'double-NAT warning must be gated by WAN install mode'
grep -q 'if \[ "${ADGUARD_INSTALL_MODE}" = "wan" \]; then' "${SCRIPT_PATH}" ||
	fail 'DNS environment preparation must be gated by WAN install mode'
grep -q 'if \[ "${ADGUARD_INSTALL_MODE:-wan}" = "wan" \] && \[ -n "${DNS_FILTER_SELECTION:-}" \]; then' "${SCRIPT_PATH}" ||
	fail 'DNSFilter mutation must be gated by WAN install mode'
grep -q 'if { \[ "${ADGUARD_INSTALL_MODE:-wan}" = "lan" \] || \[ -n "${DNS_FILTER_SELECTION:-}" \]; } &&' "${SCRIPT_PATH}" ||
	fail 'LAN runtime defaults must not depend on DNSFilter selection'
grep -q 'if \[ "${ADGUARD_INSTALL_MODE:-wan}" = "wan" \] && \[ ! -f "${AGH_FILE}" \]; then' "${SCRIPT_PATH}" ||
	fail 'DNS environment restore must be gated by WAN install mode'
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
run_case unknown-non-router-lan 9 192.168.50.1 0 lan
run_case repeater-without-lan-ip 2 "" 1 ""
run_case ap-with-invalid-lan-ip 3 999.168.50.1 1 ""
run_case ap-with-wildcard-lan-ip 3 0.0.0.0 1 ""
run_case ap-with-loopback-lan-ip 3 127.0.0.1 1 ""
run_case ap-with-multicast-lan-ip 3 224.0.0.1 1 ""
run_case missing-sw-mode-with-lan-ip "" 192.168.50.1 0 lan
run_case missing-sw-mode-without-lan-ip "" "" 1 ""
run_case missing-sw-mode-with-invalid-lan-ip "" 999.168.50.1 1 ""

printf '%s\n' 'PASS: installer install-mode detection accepts LAN pathways'
