#!/bin/sh
# Verify installation interruption recovery restarts a previously running service.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-interruption-restart.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions"
CALLS_FILE="${TMP_ROOT}/calls"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

cleanup() {
	rm -rf "${TMP_ROOT}"
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"
mkdir -p "${TMP_ROOT}" || fail 'could not create test directory'
sed -n \
	-e '/^adguard_install_abort_trap_disable() {$/,/^}/p' \
	-e '/^adguard_install_abort_trap_disable_preserve_defer() {$/,/^}/p' \
	-e '/^adguard_install_abort_on_signal() {$/,/^}/p' \
	-e '/^adguard_install_abort_trap_enable() {$/,/^}/p' \
	-e '/^adguard_restore_abort_trap_enable() {$/,/^}/p' \
	-e '/^rollback_result_write() {$/,/^}/p' \
	-e '/^rollback_result_summary() {$/,/^}/p' \
	-e '/^rollback_result_notice() {$/,/^}/p' \
	-e '/^adguard_restore_after_failed_directory_restore() {$/,/^}/p' \
	"${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" || fail 'could not extract interruption trap helpers'
printf 'ROLLBACK_RESULT_FILE="%s/rollback-result"\n' "${TMP_ROOT}" >>"${FUNCTIONS_FILE}"
[ -s "${FUNCTIONS_FILE}" ] || fail 'interruption trap helper extraction was empty'
: >"${CALLS_FILE}"

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	adguard_restart_after_install_abort() {
		printf '%s\n' "restart:$1" >>"${CALLS_FILE}"
	}
	adguard_restore_after_failed_replace() {
		printf '%s\n' "restore:$1:$2" >>"${CALLS_FILE}"
	}
	clear_screen() {
		printf '%s\n' 'clear' >>"${CALLS_FILE}"
	}
	end_op_message() {
		printf '%s\n' "end:$1" >>"${CALLS_FILE}"
	}

	adguard_install_abort_trap_enable 1
	adguard_install_abort_on_signal
) || fail 'interruption recovery handler failed'

EXPECTED="$(printf '%s\n' 'restart:1' 'clear' 'end:2')"
ACTUAL="$(cat "${CALLS_FILE}")"
[ "${ACTUAL}" = "${EXPECTED}" ] ||
	fail "interruption recovery did not restart before the aborted-operation flow: ${ACTUAL}"

: >"${CALLS_FILE}"
STAGE_DIR="${TMP_ROOT}/staging"
mkdir -p "${STAGE_DIR}" || fail 'could not create staging directory'
printf '%s\n' staged >"${STAGE_DIR}/binary"
(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	adguard_restart_after_install_abort() {
		printf '%s\n' "restart:$1" >>"${CALLS_FILE}"
	}
	adguard_restore_after_failed_replace() {
		printf '%s\n' "unexpected-restore:$1:$2" >>"${CALLS_FILE}"
	}
	clear_screen() {
		printf '%s\n' 'clear' >>"${CALLS_FILE}"
	}
	end_op_message() {
		printf '%s\n' "end:$1" >>"${CALLS_FILE}"
	}

	adguard_install_abort_trap_enable 0 "${STAGE_DIR}"
	adguard_install_abort_on_signal
) || fail 'staging interruption cleanup handler failed'

[ ! -e "${STAGE_DIR}" ] || fail 'interruption recovery left the staging directory behind'
EXPECTED="$(printf '%s\n' 'restart:0' 'clear' 'end:2')"
ACTUAL="$(cat "${CALLS_FILE}")"
[ "${ACTUAL}" = "${EXPECTED}" ] ||
	fail "staging interruption cleanup did not continue to the aborted-operation flow: ${ACTUAL}"

: >"${CALLS_FILE}"
(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	adguard_restart_after_install_abort() {
		printf '%s\n' "unexpected-restart:$1" >>"${CALLS_FILE}"
	}
	adguard_restore_after_failed_replace() {
		printf '%s\n' "restore:$1:$2" >>"${CALLS_FILE}"
	}
	clear_screen() {
		printf '%s\n' 'clear' >>"${CALLS_FILE}"
	}
	end_op_message() {
		printf '%s\n' "end:$1" >>"${CALLS_FILE}"
	}

	adguard_install_abort_trap_enable 1
	ADGUARD_INSTALL_OLD_BINARY="${TMP_ROOT}/previous"
	ADGUARD_INSTALL_REPLACE_ACTIVE="1"
	adguard_install_abort_on_signal
) || fail 'interrupted replacement recovery handler failed'

EXPECTED="$(printf '%s\n' "restore:${TMP_ROOT}/previous:1" 'clear' 'end:2')"
ACTUAL="$(cat "${CALLS_FILE}")"
[ "${ACTUAL}" = "${EXPECTED}" ] ||
	fail "interruption recovery did not restore the previous binary: ${ACTUAL}"

: >"${CALLS_FILE}"
(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	adguard_restart_after_install_abort() {
		printf '%s\n' "unexpected-restart:$1" >>"${CALLS_FILE}"
	}
	adguard_restore_after_failed_replace() {
		printf '%s\n' "restore:$1:$2" >>"${CALLS_FILE}"
	}
	clear_screen() {
		printf '%s\n' 'clear' >>"${CALLS_FILE}"
	}
	end_op_message() {
		printf '%s\n' "end:$1" >>"${CALLS_FILE}"
	}

	adguard_install_abort_trap_enable 0
	ADGUARD_INSTALL_OLD_BINARY="${TMP_ROOT}/stopped-previous"
	ADGUARD_INSTALL_REPLACE_ACTIVE="1"
	adguard_install_abort_on_signal
) || fail 'interrupted stopped-installation replacement recovery failed'

EXPECTED="$(printf '%s\n' "restore:${TMP_ROOT}/stopped-previous:0" 'clear' 'end:2')"
ACTUAL="$(cat "${CALLS_FILE}")"
[ "${ACTUAL}" = "${EXPECTED}" ] ||
	fail "interruption recovery did not restore a stopped installation without restarting it: ${ACTUAL}"

: >"${CALLS_FILE}"
RESTORE_ROOT="${TMP_ROOT}/restore"
RESTORE_TARGET="${RESTORE_ROOT}/AdGuardHome"
RESTORE_ROLLBACK="${RESTORE_ROOT}/.AdGuardHome.rollback"
RESTORE_STAGE="${RESTORE_ROOT}/.AdGuardHome.restore"
mkdir -p "${RESTORE_TARGET}" "${RESTORE_ROLLBACK}" "${RESTORE_STAGE}" || fail 'could not create restore interruption directories'
printf '%s\n' current >"${RESTORE_TARGET}/AdGuardHome"
printf '%s\n' previous >"${RESTORE_ROLLBACK}/AdGuardHome"
printf '%s\n' staged >"${RESTORE_STAGE}/AdGuardHome"
(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	INFO="Info:"
	ERROR="Error:"
	PTXT() {
		printf '%s\n' "$*" >>"${CALLS_FILE}"
	}
	adguard_restart_after_install_abort() {
		printf '%s\n' "unexpected-restart:$1" >>"${CALLS_FILE}"
	}
	adguard_restore_after_failed_replace() {
		printf '%s\n' "unexpected-binary-restore:$1:$2" >>"${CALLS_FILE}"
	}
	agh_is_running() {
		return 0
	}
	agh_stop() {
		printf '%s\n' "restore-stop" >>"${CALLS_FILE}"
		return 0
	}
	adguard_restart_after_failed_replace() {
		printf '%s\n' "restore-restart:$1" >>"${CALLS_FILE}"
	}
	clear_screen() {
		printf '%s\n' 'clear' >>"${CALLS_FILE}"
	}
	end_op_message() {
		[ "${ADGUARD_DEFER_END_OP:-0}" = "0" ] || fail 'restore abort left deferred end_op_message enabled'
		printf '%s\n' "end:$1" >>"${CALLS_FILE}"
	}

	adguard_restore_abort_trap_enable "${RESTORE_ROLLBACK}" "${RESTORE_TARGET}" "${RESTORE_STAGE}" 1
	ADGUARD_DEFER_END_OP="1"
	adguard_install_abort_on_signal
) || fail 'interrupted restore rollback handler failed'

[ ! -e "${RESTORE_STAGE}" ] || fail 'interrupted restore left staging directory behind'
[ ! -e "${RESTORE_ROLLBACK}" ] || fail 'interrupted restore left rollback directory behind'
[ "$(sed -n '1p' "${RESTORE_TARGET}/AdGuardHome")" = "previous" ] ||
	fail 'interrupted restore did not restore the previous installation'
EXPECTED="$(printf '%s\n' 'Info: Stopping AdGuardHome before restoring the previous installation.' 'restore-stop' 'restore-restart:1' 'clear' 'end:2')"
ACTUAL="$(cat "${CALLS_FILE}")"
[ "${ACTUAL}" = "${EXPECTED}" ] ||
	fail "interrupted restore did not continue to the aborted-operation flow: ${ACTUAL}"

: >"${CALLS_FILE}"
EARLY_RESTORE_ROOT="${TMP_ROOT}/restore-before-rollback"
EARLY_RESTORE_TARGET="${EARLY_RESTORE_ROOT}/AdGuardHome"
EARLY_RESTORE_ROLLBACK="${EARLY_RESTORE_ROOT}/.AdGuardHome.rollback"
EARLY_RESTORE_STAGE="${EARLY_RESTORE_ROOT}/.AdGuardHome.restore"
mkdir -p "${EARLY_RESTORE_TARGET}" "${EARLY_RESTORE_STAGE}" || fail 'could not create early restore interruption directories'
printf '%s\n' current >"${EARLY_RESTORE_TARGET}/AdGuardHome"
printf '%s\n' staged >"${EARLY_RESTORE_STAGE}/AdGuardHome"
(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	ERROR="Error:"
	PTXT() {
		printf '%s\n' "$*" >>"${CALLS_FILE}"
	}
	adguard_restart_after_install_abort() {
		printf '%s\n' "unexpected-restart:$1" >>"${CALLS_FILE}"
	}
	agh_is_running() {
		return 1
	}
	adguard_restart_after_failed_replace() {
		printf '%s\n' "restore-restart:$1" >>"${CALLS_FILE}"
	}
	clear_screen() {
		printf '%s\n' 'clear' >>"${CALLS_FILE}"
	}
	end_op_message() {
		printf '%s\n' "end:$1" >>"${CALLS_FILE}"
	}

	adguard_restore_abort_trap_enable "${EARLY_RESTORE_ROLLBACK}" "${EARLY_RESTORE_TARGET}" "${EARLY_RESTORE_STAGE}" 0
	adguard_install_abort_on_signal
) || fail 'early interrupted restore cleanup handler failed'

[ ! -e "${EARLY_RESTORE_STAGE}" ] || fail 'early interrupted restore left staging directory behind'
[ "$(sed -n '1p' "${EARLY_RESTORE_TARGET}/AdGuardHome")" = "current" ] ||
	fail 'early interrupted restore removed the current installation before rollback existed'
EXPECTED="$(printf '%s\n' 'restore-restart:0' 'clear' 'end:2')"
ACTUAL="$(cat "${CALLS_FILE}")"
[ "${ACTUAL}" = "${EXPECTED}" ] ||
	fail "early interrupted restore did not continue to the aborted-operation flow: ${ACTUAL}"

: >"${CALLS_FILE}"
DEFER_RESTORE_ROOT="${TMP_ROOT}/defer-restore"
DEFER_RESTORE_TARGET="${DEFER_RESTORE_ROOT}/AdGuardHome"
DEFER_RESTORE_ROLLBACK="${DEFER_RESTORE_ROOT}/.AdGuardHome.rollback"
DEFER_RESTORE_STAGE="${DEFER_RESTORE_ROOT}/.AdGuardHome.restore"
mkdir -p "${DEFER_RESTORE_TARGET}" "${DEFER_RESTORE_ROLLBACK}" "${DEFER_RESTORE_STAGE}" || fail 'could not create deferred restore interruption directories'
printf '%s\n' current >"${DEFER_RESTORE_TARGET}/AdGuardHome"
printf '%s\n' previous >"${DEFER_RESTORE_ROLLBACK}/AdGuardHome"
(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	INFO="Info:"
	ERROR="Error:"
	PTXT() {
		printf '%s\n' "$*" >>"${CALLS_FILE}"
	}
	adguard_restart_after_install_abort() {
		printf '%s\n' "unexpected-restart:$1" >>"${CALLS_FILE}"
	}
	adguard_restore_after_failed_replace() {
		printf '%s\n' "unexpected-binary-restore:$1:$2" >>"${CALLS_FILE}"
	}
	agh_is_running() {
		return 1
	}
	adguard_restart_after_failed_replace() {
		printf '%s\n' "restore-restart:$1" >>"${CALLS_FILE}"
	}
	clear_screen() {
		printf '%s\n' 'clear' >>"${CALLS_FILE}"
	}
	end_op_message() {
		printf '%s\n' "end:$1" >>"${CALLS_FILE}"
	}

	adguard_restore_abort_trap_enable "${DEFER_RESTORE_ROLLBACK}" "${DEFER_RESTORE_TARGET}" "${DEFER_RESTORE_STAGE}" 1
	ADGUARD_DEFER_END_OP="1"
	adguard_install_abort_trap_disable_preserve_defer
	adguard_install_abort_on_signal
) || fail 'deferred restore interruption rollback handler failed'

[ ! -e "${DEFER_RESTORE_STAGE}" ] || fail 'deferred restore interruption left staging directory behind'
[ ! -e "${DEFER_RESTORE_ROLLBACK}" ] || fail 'deferred restore interruption left rollback directory behind'
[ "$(sed -n '1p' "${DEFER_RESTORE_TARGET}/AdGuardHome")" = "previous" ] ||
	fail 'deferred restore interruption did not restore the previous installation'
EXPECTED="$(printf '%s\n' 'restore-restart:1' 'clear' 'end:2')"
ACTUAL="$(cat "${CALLS_FILE}")"
[ "${ACTUAL}" = "${EXPECTED}" ] ||
	fail "deferred restore interruption did not preserve restart state: ${ACTUAL}"

awk '
	/^install_adguard_archive\(\) \{/ { in_function = 1 }
	in_function && /adguard_install_abort_trap_enable/ { enable = NR }
	in_function && /adguard_archive_is_safe/ { validate = NR }
	in_function && /agh_prepare_binary_replace/ { prepare = NR }
	in_function && /ADGUARD_INSTALL_REPLACE_ACTIVE="1"/ { replace = NR }
	in_function && /mv "\$\{STAGE_BINARY\}" "\$\{AGH_FILE\}"/ { publish = NR }
	in_function && /^}/ { exit }
	END { exit !(enable && validate && enable < validate && prepare && enable < prepare && replace && publish && replace < publish) }
' "${SCRIPT_PATH}" || fail 'interruption rollback is not armed for existing binaries before publication'

awk '
	/^backup_restore\(\) \{/ { in_function = 1 }
	in_function && /RESTORE_STAGE_DIR="\$\{BASE_DIR\}\/\.AdGuardHome\.restore\.\$\$"/ { stage = NR }
	in_function && /adguard_restore_abort_trap_enable/ { enable = NR }
	in_function && /tar -xzvf "\$\{BASE_DIR\}\/backup_AdGuardHome\.tar\.gz"/ { extract = NR }
	in_function && /mv "\$\{TARG_DIR\}" "\$\{RESTORE_ROLLBACK_DIR\}"/ { rollback = NR }
	in_function && /^}/ { exit }
	END { exit !(stage && enable && extract && rollback && stage < enable && enable < extract && extract < rollback) }
' "${SCRIPT_PATH}" || fail 'restore cleanup trap is not armed before staging extraction'

awk '
	/^backup_restore\(\) \{/ { in_function = 1 }
	in_function && /inst_AdGuardHome "\$\{1:-RESTORE\}"/ { final_setup = NR; next }
	in_function && final_setup && /if \[ "\$\{INSTALL_STATUS\}" -ne 0 \]; then/ { in_final_failure = 1; next }
	in_final_failure && /^[[:space:]]*fi$/ { in_final_failure = 0; next }
	in_function && final_setup && !in_final_failure && /adguard_install_abort_trap_disable/ { disable = NR }
	in_function && final_setup && !in_final_failure && /rm -rf "\$\{RESTORE_ROLLBACK_DIR\}"/ { cleanup = NR; exit }
	END { exit !(final_setup && disable && cleanup && final_setup < disable && disable < cleanup) }
' "${SCRIPT_PATH}" || fail 'restore trap is not disabled before rollback cleanup removal'

awk '
	/^backup_restore\(\) \{/ { in_function = 1 }
	in_function && /inst_AdGuardHome "\$\{1:-RESTORE\}"/ { install = NR }
	in_function && install && /adguard_install_abort_trap_disable/ { disable = NR }
	in_function && /finalize_pending_mode_migration/ { finalize = NR }
	in_function && /rm -rf "\$\{RESTORE_ROLLBACK_DIR\}"/ { cleanup = NR }
	in_function && /^}/ { exit }
	END { exit !(install && disable && finalize && cleanup && install < disable && disable < finalize && finalize < cleanup) }
' "${SCRIPT_PATH}" || fail 'restore does not disable directory rollback before finalizing mode migration and removing its rollback directory'

awk '
	/^backup_restore\(\) \{/ { in_function = 1 }
	in_function && /inst_AdGuardHome "\$\{1:-RESTORE\}"/ { install = NR; next }
	in_function && install && /if \[ "\$\{INSTALL_STATUS\}" -ne 0 \]; then/ { failure = 1; next }
	failure && /rollback_pending_mode_migration/ { migration = NR; next }
	failure && /adguard_restore_after_failed_directory_restore/ { directory = NR; exit }
	in_function && /^}/ { exit }
	END { exit !(install && failure && migration && directory && migration < directory) }
' "${SCRIPT_PATH}" || fail 'failed restore replaces the installation directory before rolling back its pending mode migration'

awk '
	/^backup_restore\(\) \{/ { in_function = 1 }
	in_function && /inst_AdGuardHome "\$\{1:-RESTORE\}"/ { install = 1; next }
	install && /MIGRATION_ROLLBACK_STATUS=1/ { rollback_failed = 1; next }
	rollback_failed && !preserved_hooks && /MIGRATION_HOOKS_RECOVERY=.*RESTORE_ROLLBACK_DIR/ { preserved_hooks = NR; next }
	rollback_failed && !detached && /MODE_MIGRATION_YAML_FILE_BACKUP=""/ { detached = NR; next }
	rollback_failed && !retained_hooks && /MODE_MIGRATION_HOOKS_BACKUP="\$\{MIGRATION_HOOKS_RECOVERY\}"/ { retained_hooks = NR; next }
	rollback_failed && !restored_without_restart && /adguard_restore_after_failed_directory_restore .* "0" "1"/ { restored_without_restart = NR; next }
	restored_without_restart && !retried_hooks && /restore_mode_migration_wan_hooks "\$\{MIGRATION_HOOKS_RECOVERY\}"/ { retried_hooks = NR; next }
	retried_hooks && /MODE_MIGRATION_HOOKS_BACKUP=""/ { cleared_hooks = NR; next }
	restored_without_restart && /return 2/ { preserved_status = 1; exit }
	END { exit !(rollback_failed && preserved_hooks && detached && retained_hooks && restored_without_restart && retried_hooks && cleared_hooks && preserved_hooks < detached && detached < retained_hooks && retained_hooks < restored_without_restart && restored_without_restart < retried_hooks && retried_hooks < cleared_hooks && preserved_status) }
' "${SCRIPT_PATH}" || fail 'restore rollback failure does not preserve and retry hook recovery around directory rollback, suppress restart, or preserve status 2'

awk '
	/^adguard_install_abort_on_signal\(\) \{/ { in_function = 1 }
	in_function && /rollback_pending_mode_migration/ { migration = NR }
	in_function && /adguard_restore_after_failed_directory_restore/ { restore = NR }
	in_function && /adguard_restart_after_install_abort/ { restart = NR }
	in_function && /^}/ { exit }
	END { exit !(migration && restore && restart && migration < restore && migration < restart) }
' "${SCRIPT_PATH}" || fail 'signal cleanup does not roll back pending mode migration before service recovery'

printf '%s\n' 'PASS: installation interruption restarts the previously running service'
