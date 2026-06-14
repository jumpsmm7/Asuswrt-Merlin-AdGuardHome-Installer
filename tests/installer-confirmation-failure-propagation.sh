#!/bin/sh
# Verify installation prompts abort on confirmation read failures.

set -u

SCRIPT_PATH="${1:-installer}"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"

INSTALL_FUNCTION="$(sed -n '/^inst_AdGuardHome() {$/,/^setup_AdGuardHome() {$/p' "${SCRIPT_PATH}" | sed '$d')"
[ -n "${INSTALL_FUNCTION}" ] || fail 'could not extract inst_AdGuardHome function'
eval "${INSTALL_FUNCTION}"

ROOT="${TMPDIR:-/tmp}/installer-confirmation-failure-propagation.$$"
BASE_DIR="${ROOT}/opt/etc"
TARG_DIR="${BASE_DIR}/AdGuardHome"
AGH_FILE="${TARG_DIR}/AdGuardHome"
SCRIPT_LOC="${TARG_DIR}/installer"
ADGUARD_ARCH='amd64'
REMOTE_VER='1'
REMOTE_BETA='1'
REMOTE_EDGE='1'
INFO='Info:'
ERROR='Error:'
CHECK_LOG="${ROOT}/continued"
BACKUP_STATUS=0
mkdir -p "${BASE_DIR}"
trap 'rm -rf "${ROOT}"' 0 HUP INT TERM

read_yesno() {
	return 2
}
file_md5() {
	:
}
PTXT() {
	:
}
end_op_message() {
	:
}
backup_restore() {
	return "${BACKUP_STATUS}"
}
check_connection() {
	printf '%s\n' continued >>"${CHECK_LOG}"
	return 0
}

mkdir -p "${BASE_DIR}"
: >"${BASE_DIR}/backup_AdGuardHome.tar.gz"
inst_AdGuardHome install ""
STATUS=$?
[ "${STATUS}" -eq 2 ] || fail 'restore confirmation failure was not propagated'
[ ! -e "${CHECK_LOG}" ] || fail 'installation continued after restore confirmation failure'

rm -f "${BASE_DIR}/backup_AdGuardHome.tar.gz" "${CHECK_LOG}"
mkdir -p "${TARG_DIR}"
: >"${AGH_FILE}"
inst_AdGuardHome update ""
STATUS=$?
[ "${STATUS}" -eq 2 ] || fail 'backup confirmation failure was not propagated'
[ ! -e "${CHECK_LOG}" ] || fail 'update continued after backup confirmation failure'

read_yesno() {
	return 0
}
BACKUP_STATUS=1
rm -f "${CHECK_LOG}"
inst_AdGuardHome update ""
STATUS=$?
[ "${STATUS}" -eq 1 ] || fail 'pre-update backup failure was not propagated'
[ ! -e "${CHECK_LOG}" ] || fail 'update continued after pre-update backup failure'

printf '%s\n' 'PASS: installation confirmation and backup failures are propagated'
