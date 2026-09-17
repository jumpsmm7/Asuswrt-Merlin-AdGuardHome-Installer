#!/bin/sh
# Verify committed binary cleanup is retried by EXIT and gates startup work.

set -u

SCRIPT_PATH="${1:-installer}"
TEST_ROOT="${TMPDIR:-/tmp}/installer-binary-cleanup-lifecycle.$$"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

cleanup() {
	rm -rf "${TEST_ROOT}"
}

(umask 077 && mkdir "${TEST_ROOT}") || fail 'could not create committed-binary lifecycle fixture'
trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
sed -n \
	-e '/^on_installer_exit() {$/,/^}/p' \
	-e '/^adguard_committed_binary_cleanup_path_valid() {$/,/^}/p' \
	-e '/^adguard_committed_binary_cleanup_record_write() {$/,/^}/p' \
	-e '/^adguard_committed_binary_cleanup_retry() {$/,/^}/p' \
	"${SCRIPT_PATH}" >"${TEST_ROOT}/helpers" || fail 'could not extract committed-binary lifecycle helpers'
sed -n '/^if ! adguard_committed_binary_cleanup_retry; then$/,/^fi$/p' "${SCRIPT_PATH}" >"${TEST_ROOT}/startup-preflight" ||
	fail 'could not extract committed-binary startup preflight'
[ -s "${TEST_ROOT}/helpers" ] || fail 'committed-binary lifecycle helper extraction was empty'
[ -s "${TEST_ROOT}/startup-preflight" ] || fail 'committed-binary startup preflight extraction was empty'
# shellcheck disable=SC1090
. "${TEST_ROOT}/helpers"

ERROR='Error:'
WARNING='Warning:'
REPORT="${TEST_ROOT}/report"
PTXT() { printf '%s\n' "$*" >>"${REPORT}"; }
nvram_transaction_lock_owned() { return 1; }
nvram_transaction_lock_release() { return 0; }
cleanup_api_files() { :; }
installer_cleanup_tmp_file() { :; }
all_event_scripts_transaction_rollback() { :; }
rollback_pending_mode_migration() { :; }
adguard_restart_after_install_abort() { :; }
adguard_restart_after_failed_replace() { :; }
MODE_MIGRATION_YAML_FILE_BACKUP=""
EVENT_SCRIPTS_ACTIVE_SNAPSHOT=""
ADGUARD_INSTALL_RESTART_PENDING=0
ADGUARD_INSTALL_REPLACE_ACTIVE=0

BASE_DIR="${TEST_ROOT}/exit-base"
TARG_DIR="${BASE_DIR}/AdGuardHome"
BACKUP="${TARG_DIR}/.AdGuardHome.previous.101"
mkdir -p "${TARG_DIR}" || fail 'could not create EXIT cleanup fixture'
printf '%s\n' old >"${BACKUP}"
adguard_committed_binary_cleanup_record_write "${BACKUP}" || fail 'could not create EXIT cleanup record'
rm() {
	[ "$1" != '-f' ] || [ "$2" != "${BACKUP}" ] || return 1
	/bin/rm "$@"
}
on_installer_exit || fail 'EXIT cleanup propagated committed-binary cleanup failure'
[ -f "${BACKUP}" ] || fail 'failed EXIT cleanup removed the previous-binary backup'
[ -f "${BASE_DIR}/.AdGuardHome.binary-cleanup" ] || fail 'failed EXIT cleanup removed its cleanup record'
unset -f rm 2>/dev/null || true
on_installer_exit || fail 'EXIT cleanup retry failed after backup removal recovered'
[ ! -e "${BACKUP}" ] || fail 'successful EXIT retry retained the previous-binary backup'
[ ! -e "${BASE_DIR}/.AdGuardHome.binary-cleanup" ] || fail 'successful EXIT retry retained its cleanup record'

BASE_DIR="${TEST_ROOT}/startup-base"
TARG_DIR="${BASE_DIR}/AdGuardHome"
BACKUP="${TARG_DIR}/.AdGuardHome.previous.202"
DISPATCHED="${TEST_ROOT}/startup-dispatched"
mkdir -p "${TARG_DIR}" || fail 'could not create startup cleanup fixture'
printf '%s\n' old >"${BACKUP}"
adguard_committed_binary_cleanup_record_write "${BACKUP}" || fail 'could not create startup cleanup record'
rm() {
	[ "$1" != '-f' ] || [ "$2" != "${BACKUP}" ] || return 1
	/bin/rm "$@"
}
if (
	# shellcheck disable=SC1090
	. "${TEST_ROOT}/startup-preflight"
	: >"${DISPATCHED}"
); then
	fail 'startup continued while committed-binary cleanup remained pending'
fi
[ ! -e "${DISPATCHED}" ] || fail 'failed startup cleanup dispatched installer work'
[ -f "${BACKUP}" ] || fail 'failed startup cleanup removed the previous-binary backup'
[ -f "${BASE_DIR}/.AdGuardHome.binary-cleanup" ] || fail 'failed startup cleanup removed its cleanup record'
unset -f rm 2>/dev/null || true
(
	# shellcheck disable=SC1090
	. "${TEST_ROOT}/startup-preflight"
	: >"${DISPATCHED}"
) || fail 'startup did not proceed after committed-binary cleanup recovered'
[ -f "${DISPATCHED}" ] || fail 'successful startup cleanup did not reach installer dispatch'
[ ! -e "${BACKUP}" ] || fail 'successful startup cleanup retained the previous-binary backup'
[ ! -e "${BASE_DIR}/.AdGuardHome.binary-cleanup" ] || fail 'successful startup cleanup retained its cleanup record'

printf '%s\n' 'PASS: committed binary cleanup spans EXIT and startup lifecycle boundaries'
