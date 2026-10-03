#!/bin/sh
# Verify flock transaction-lock release remains retryable across cleanup failures.
set -u

INSTALLER_PATH="${1:-installer}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/installer-lock-release.XXXXXX")" || exit 1
FUNCTIONS_FILE="${TEST_ROOT}/functions"

cleanup() { exec 8>&- 2>/dev/null || true; rm -rf "${TEST_ROOT}"; }
fail() { printf '%s\n' "FAIL: $*" >&2; exit 1; }
trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

sed -n '/^nvram_transaction_lock_release() {$/,/^}$/p' "${INSTALLER_PATH}" >"${FUNCTIONS_FILE}" || fail 'could not extract release helper'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

BASE_DIR="${TEST_ROOT}"
LOCK_PATH="${BASE_DIR}/.AdGuardHome.nvram.lock"
OWNER='123:456'
NVRAM_TRANSACTION_LOCK_MODE=flock
RM_FAIL=0
UNLOCK_FAIL=0
REAPER_RELEASE_FAIL=0
REAPER_ACTIVE=0

nvram_transaction_lock_owner_current() { printf '%s\n' "${OWNER}"; }
nvram_transaction_lock_readlink() { readlink "$@"; }
nvram_transaction_lock_failure() { NVRAM_TRANSACTION_LOCK_DIAGNOSTIC="$1"; return 1; }
nvram_transaction_lock_flock_owned() {
	[ -e "/proc/$$/fd/8" ] && [ "$(readlink "${LOCK_PATH}.symlink" 2>/dev/null)" = "${OWNER}" ]
}
nvram_transaction_lock_reaper_acquire() { REAPER_ACTIVE=1; return 0; }
nvram_transaction_lock_reaper_release() {
	[ "${REAPER_ACTIVE}" -eq 1 ] || return 1
	[ "${REAPER_RELEASE_FAIL}" -eq 0 ] || return 1
	REAPER_ACTIVE=0
}
nvram_transaction_lock_flock_unlock() {
	[ "${REAPER_ACTIVE}" -eq 1 ] || fail 'release transition dropped mutual exclusion before flock unlock'
	[ "${UNLOCK_FAIL}" -eq 0 ] || return 1
	return 0
}
rm() {
	if [ "${RM_FAIL}" -eq 1 ] && [ "${1:-}" = -f ] && [ "${2:-}" = "${LOCK_PATH}.symlink" ]; then
		return 1
	fi
	command rm "$@"
}

reset_case() {
	exec 8>&- 2>/dev/null || true
	: >"${LOCK_PATH}"
	exec 8>"${LOCK_PATH}" || fail 'could not open lock descriptor'
	command rm -f "${LOCK_PATH}.symlink"
	ln -s "${OWNER}" "${LOCK_PATH}.symlink" || fail 'could not publish owner symlink'
	NVRAM_TRANSACTION_LOCK_MODE=flock
	NVRAM_TRANSACTION_LOCK_RELEASE_OWNER=
	NVRAM_TRANSACTION_LOCK_RELEASE_PHASE=
	NVRAM_TRANSACTION_LOCK_DIAGNOSTIC=
	RM_FAIL=0
	UNLOCK_FAIL=0
	REAPER_RELEASE_FAIL=0
	REAPER_ACTIVE=0
}

reset_case
RM_FAIL=1
nvram_transaction_lock_release && fail 'owner-symlink removal failure returned success'
[ -e "/proc/$$/fd/8" ] || fail 'owner removal failure closed the flock descriptor'
[ -L "${LOCK_PATH}.symlink" ] || fail 'owner removal failure lost the ownership artifact'
[ "${REAPER_ACTIVE}" -eq 0 ] || fail 'owner removal failure retained the reaper unnecessarily'
RM_FAIL=0
nvram_transaction_lock_release || fail 'owner removal retry failed'
[ "${NVRAM_TRANSACTION_LOCK_MODE}" = '' ] || fail 'successful retry retained lock mode'

reset_case
UNLOCK_FAIL=1
nvram_transaction_lock_release && fail 'flock unlock failure returned success'
[ "${NVRAM_TRANSACTION_LOCK_RELEASE_PHASE}" = symlink-removed ] || fail 'unlock failure lost retry phase'
[ "${REAPER_ACTIVE}" -eq 1 ] || fail 'unlock failure released mutual exclusion'
[ -e "/proc/$$/fd/8" ] || fail 'unlock failure closed the retryable descriptor'
UNLOCK_FAIL=0
nvram_transaction_lock_release || fail 'flock unlock retry failed'

reset_case
REAPER_RELEASE_FAIL=1
nvram_transaction_lock_release && fail 'reaper release failure returned success'
[ "${NVRAM_TRANSACTION_LOCK_RELEASE_PHASE}" = unlocked ] || fail 'reaper failure lost post-unlock retry phase'
[ ! -e "/proc/$$/fd/8" ] || fail 'reaper failure retained an already unlocked descriptor'
[ "${REAPER_ACTIVE}" -eq 1 ] || fail 'reaper failure lost explicit active state'
REAPER_RELEASE_FAIL=0
nvram_transaction_lock_release || fail 'reaper release retry failed'
[ "${NVRAM_TRANSACTION_LOCK_MODE}" = '' ] || fail 'reaper retry retained lock mode'

printf '%s\n' 'PASS: flock NVRAM transaction lock release is retryable'
