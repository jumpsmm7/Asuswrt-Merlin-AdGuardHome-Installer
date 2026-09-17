#!/bin/sh
# Verify committed binary backups are retried only through a validated cleanup record.

set -u

SCRIPT_PATH="${1:-installer}"
TEST_ROOT="${TMPDIR:-/tmp}/installer-binary-cleanup.$$"

# fail reports a regression failure and exits the test.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

# cleanup removes the committed-binary fixture.
cleanup() {
	rm -rf "${TEST_ROOT}"
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
mkdir -p "${TEST_ROOT}/base/AdGuardHome" || fail 'could not create cleanup fixture'
sed -n \
	-e '/^adguard_committed_binary_cleanup_path_valid() {$/,/^}/p' \
	-e '/^adguard_committed_binary_cleanup_record_write() {$/,/^}/p' \
	-e '/^adguard_committed_binary_cleanup_retry() {$/,/^}/p' \
	-e '/^adguard_committed_binary_cleanup_finalize() {$/,/^}/p' \
	"${SCRIPT_PATH}" >"${TEST_ROOT}/helpers" || fail 'could not extract committed-binary cleanup helpers'
[ -s "${TEST_ROOT}/helpers" ] || fail 'committed-binary cleanup helper extraction was empty'
awk '
	/^adguard_committed_binary_cleanup_finalize\(\) \{/ { finalize = 1 }
	finalize && /ADGUARD_INSTALL_REPLACE_ACTIVE="0"/ { disarmed = NR }
	finalize && /ADGUARD_INSTALL_OLD_BINARY=""/ { cleared = NR }
	finalize && /adguard_committed_binary_cleanup_record_write/ { cleanup = NR; exit }
	END { exit(disarmed && cleared > disarmed && cleanup > cleared ? 0 : 1) }
' "${SCRIPT_PATH}" || fail 'committed binary cleanup does not disarm rollback before deletion'
# shellcheck disable=SC1090
. "${TEST_ROOT}/helpers"

BASE_DIR="${TEST_ROOT}/base"
TARG_DIR="${BASE_DIR}/AdGuardHome"
ERROR='Error:'
REPORT="${TEST_ROOT}/report"
# PTXT records cleanup errors for later assertions.
PTXT() { printf '%s\n' "$*" >>"${REPORT}"; }
# adguard_install_signal_traps_disable avoids changing fixture signal handling.
adguard_install_signal_traps_disable() { :; }

OLD_BINARY="${TARG_DIR}/.AdGuardHome.previous.123"
printf '%s\n' old >"${OLD_BINARY}"
adguard_committed_binary_cleanup_record_write "${OLD_BINARY}" || fail 'could not write valid cleanup record'
adguard_committed_binary_cleanup_retry || fail 'valid committed-binary cleanup failed'
[ ! -e "${OLD_BINARY}" ] || fail 'successful cleanup retained the committed binary backup'
[ ! -e "${BASE_DIR}/.AdGuardHome.binary-cleanup" ] || fail 'successful cleanup retained its record'

OLD_BINARY="${TARG_DIR}/.AdGuardHome.previous.456"
printf '%s\n' old >"${OLD_BINARY}"
adguard_committed_binary_cleanup_record_write "${OLD_BINARY}" || fail 'could not write retry cleanup record'
# rm injects failure when the committed backup is first removed.
rm() {
	[ "$1" != '-f' ] || [ "$2" != "${OLD_BINARY}" ] || return 1
	/bin/rm "$@"
}
if adguard_committed_binary_cleanup_retry; then
	fail 'committed-binary cleanup hid backup deletion failure'
fi
[ -f "${OLD_BINARY}" ] || fail 'failed cleanup removed the committed binary backup'
[ -f "${BASE_DIR}/.AdGuardHome.binary-cleanup" ] || fail 'failed cleanup removed its retry record'
unset -f rm 2>/dev/null || true
adguard_committed_binary_cleanup_retry || fail 'later committed-binary cleanup retry failed'
[ ! -e "${OLD_BINARY}" ] && [ ! -e "${BASE_DIR}/.AdGuardHome.binary-cleanup" ] ||
	fail 'successful retry retained cleanup artifacts'

OUTSIDE_FILE="${TEST_ROOT}/outside"
printf '%s\n' outside >"${OUTSIDE_FILE}"
printf '%s\n' "${OUTSIDE_FILE}" >"${BASE_DIR}/.AdGuardHome.binary-cleanup"
if adguard_committed_binary_cleanup_retry; then
	fail 'unsafe committed-binary cleanup path was accepted'
fi
[ -f "${OUTSIDE_FILE}" ] || fail 'unsafe cleanup record removed a file outside the managed directory'
[ -f "${BASE_DIR}/.AdGuardHome.binary-cleanup" ] || fail 'unsafe cleanup record was discarded'

/bin/rm -f "${BASE_DIR}/.AdGuardHome.binary-cleanup"
ln -s "${TEST_ROOT}/missing-cleanup-record" "${BASE_DIR}/.AdGuardHome.binary-cleanup" ||
	fail 'could not create dangling cleanup marker fixture'
if adguard_committed_binary_cleanup_retry; then
	fail 'dangling cleanup marker bypassed cleanup validation'
fi
[ -L "${BASE_DIR}/.AdGuardHome.binary-cleanup" ] || fail 'dangling cleanup marker was removed or followed'
/bin/rm -f "${BASE_DIR}/.AdGuardHome.binary-cleanup"
adguard_committed_binary_cleanup_retry || fail 'absent cleanup marker was rejected'

OLD_BINARY="${TARG_DIR}/.AdGuardHome.previous.789"
printf '%s\n' old >"${OLD_BINARY}"
ADGUARD_INSTALL_REPLACE_ACTIVE=1
ADGUARD_INSTALL_OLD_BINARY="${OLD_BINARY}"
ADGUARD_COMMITTED_BINARY_CLEANUP_PENDING=""
adguard_committed_binary_cleanup_record_write() { return 1; }
rm() { return 1; }
if adguard_committed_binary_cleanup_finalize "${OLD_BINARY}"; then
	fail 'double committed-backup cleanup failure was reported as success'
fi
[ "${ADGUARD_INSTALL_REPLACE_ACTIVE}" = 0 ] || fail 'committed replacement remained rollback eligible'
[ -z "${ADGUARD_INSTALL_OLD_BINARY}" ] || fail 'committed backup remained in rollback state'
[ "${ADGUARD_COMMITTED_BINARY_CLEANUP_PENDING}" = "${OLD_BINARY}" ] ||
	fail 'double cleanup failure forgot its in-memory retry path'
unset -f rm 2>/dev/null || true
adguard_committed_binary_cleanup_finalize "${ADGUARD_COMMITTED_BINARY_CLEANUP_PENDING}" ||
	fail 'later in-memory committed-backup cleanup retry failed'
[ ! -e "${OLD_BINARY}" ] || fail 'later cleanup retry retained committed backup'
[ -z "${ADGUARD_COMMITTED_BINARY_CLEANUP_PENDING}" ] || fail 'successful retry retained in-memory cleanup state'

printf '%s\n' 'PASS: committed binary cleanup is durable and path restricted'
