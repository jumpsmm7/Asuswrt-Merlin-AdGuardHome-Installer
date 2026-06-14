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
	-e '/^adguard_install_abort_on_signal() {$/,/^}/p' \
	-e '/^adguard_install_abort_trap_enable() {$/,/^}/p' \
	"${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" || fail 'could not extract interruption trap helpers'
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

printf '%s\n' 'PASS: installation interruption restarts the previously running service'
