#!/bin/sh
# Verify fallback lock acquisition and actionable failure diagnostics.

set -u

INSTALLER_PATH="${1:-installer}"
TEST_ROOT="${TMPDIR:-/tmp}/installer-lock-diagnostics.$$"
(umask 077 && mkdir "${TEST_ROOT}") || exit 1
FUNCTIONS_FILE="${TEST_ROOT}/functions"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

cleanup() { rm -rf "${TEST_ROOT}"; }
trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

sed -n '/^nvram_transaction_lock_cross_reaper_release() {$/,/^nvram_transaction_set() {$/p' "${INSTALLER_PATH}" |
	sed '$d' >"${FUNCTIONS_FILE}" || fail 'could not extract transaction lock helpers'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

BASE_DIR="${TEST_ROOT}/opt/etc"
mkdir -p "${BASE_DIR}" || fail 'could not create simulated /opt/etc'

# Exercise acquisition without /usr/bin/flock and force symlink publication to
# fail on the simulated filesystem while retaining the mkdir fallback.
nvram_transaction_lock_flock_supports_fd() { return 1; }
ln() { return 1; }
nvram_transaction_lock_acquire || fail "mkdir fallback failed: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-missing diagnostic}"
[ "${NVRAM_TRANSACTION_LOCK_MODE:-}" = mkdir ] || fail 'symlink failure did not select mkdir locking'
[ -z "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" ] || fail 'successful fallback retained a failure diagnostic'
nvram_transaction_lock_release || fail 'could not release mkdir fallback lock'
unset -f ln 2>/dev/null || true

# A failed reaper acquisition must identify the operation and path.
nvram_transaction_lock_symlink_acquire() { return 2; }
nvram_transaction_lock_reaper_acquire() { return 1; }
if nvram_transaction_lock_acquire; then
	fail 'acquisition succeeded after injected reaper acquisition failure'
fi
case "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" in
	*operation=acquire-reaper*path="${BASE_DIR}/.AdGuardHome.nvram.lock.reaper"*) ;;
	*) fail "reaper acquisition diagnostic was not preserved: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-unset}" ;;
esac

# Restore the helpers, publish a lock owned by this live process, and verify
# that contention reports the recorded owner rather than calling it current.
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"
nvram_transaction_lock_flock_supports_fd() { return 1; }
owner="$(nvram_transaction_lock_owner_current)" || fail 'could not determine test process identity'
ln -s "${owner}" "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink" || fail 'could not publish live contender'
if nvram_transaction_lock_acquire; then
	fail 'acquisition succeeded against a live owner'
fi
case "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" in
	*operation=validate-stale-lock*reason=live-owner*owner="${owner}"*) ;;
	*) fail "live-owner contention diagnostic was not preserved: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-unset}" ;;
esac

# A release failure after publication must retain both the failed operation
# and the artifact that acquisition rolls back.
rm -f "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink"
nvram_transaction_lock_reaper_release() { return 1; }
if nvram_transaction_lock_acquire; then
	fail 'acquisition succeeded after injected reaper release failure'
fi
case "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" in
	*operation=release-reaper*rolled-back="${BASE_DIR}/.AdGuardHome.nvram.lock.symlink"*) ;;
	*) fail "reaper release diagnostic omitted rollback artifact: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-unset}" ;;
esac

printf '%s\n' 'PASS: installer lock fallbacks preserve actionable diagnostics'
