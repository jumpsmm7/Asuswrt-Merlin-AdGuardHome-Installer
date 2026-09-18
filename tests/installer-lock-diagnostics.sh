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

# An unsafe mkdir-lock artifact is the terminal fallback failure and must not
# be hidden by the optional flock capability miss.
: >"${BASE_DIR}/.AdGuardHome.nvram.lock.d" || fail 'could not create unsafe lock artifact'
if nvram_transaction_lock_acquire; then
	fail 'acquisition succeeded with an unsafe mkdir-lock artifact'
fi
case "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" in
	*operation=validate-mkdir-lock*path="${BASE_DIR}/.AdGuardHome.nvram.lock.d"*reason=unsafe-artifact*) ;;
	*) fail "unsafe fallback artifact lacked a diagnostic: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-unset}" ;;
esac
rm -f "${BASE_DIR}/.AdGuardHome.nvram.lock.d"

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

# A cleanup failure is secondary to the live-owner contention that made the
# acquisition fail.
nvram_transaction_lock_reaper_release_impl() { return 1; }
NVRAM_TRANSACTION_LOCK_DIAGNOSTIC="operation=validate-stale-lock path=${BASE_DIR}/.AdGuardHome.nvram.lock.symlink reason=live-owner owner=${owner}"
if nvram_transaction_lock_reaper_release "${BASE_DIR}/.AdGuardHome.nvram.lock.reaper" "${owner}"; then
	fail 'injected reaper release failure succeeded'
fi
case "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" in
	*operation=validate-stale-lock*path="${BASE_DIR}/.AdGuardHome.nvram.lock.symlink"*reason=live-owner*owner="${owner}"*after-failed-operation="release-reaper:${BASE_DIR}/.AdGuardHome.nvram.lock.reaper"*) ;;
	*) fail "reaper release replaced the primary diagnostic: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-unset}" ;;
esac
NVRAM_TRANSACTION_LOCK_DIAGNOSTIC=""
if nvram_transaction_lock_reaper_release "${BASE_DIR}/standalone.reaper" "${owner}"; then
	fail 'standalone injected reaper release failure succeeded'
fi
case "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" in
	"operation=release-reaper path=${BASE_DIR}/standalone.reaper") ;;
	*) fail "standalone reaper release diagnostic was incorrect: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-unset}" ;;
esac

# A release ownership mismatch reported by the implementation must remain
# more specific than the wrapper's generic release failure.
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"
mkdir "${BASE_DIR}/mismatched.reaper" || fail 'could not create mismatched reaper'
printf '%s\n' 'different-owner' >"${BASE_DIR}/mismatched.reaper/pid"
NVRAM_TRANSACTION_REAPER_LOCK_MODE=mkdir
NVRAM_TRANSACTION_REAPER_LOCK_PATH="${BASE_DIR}/mismatched.reaper"
NVRAM_TRANSACTION_LOCK_DIAGNOSTIC=""
if nvram_transaction_lock_reaper_release "${BASE_DIR}/mismatched.reaper" "${owner}"; then
	fail 'mismatched reaper release succeeded'
fi
case "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" in
	*operation=release-reaper*path="${BASE_DIR}/mismatched.reaper/pid"*reason=owner-mismatch*owner="${owner}"*) ;;
	*) fail "reaper owner mismatch lacked a specific diagnostic: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-unset}" ;;
esac
rm -rf "${BASE_DIR}/mismatched.reaper"
NVRAM_TRANSACTION_REAPER_LOCK_MODE=""
NVRAM_TRANSACTION_REAPER_LOCK_PATH=""

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

# An expected flock capability miss must not obscure the terminal portable
# fallback failure.
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"
nvram_transaction_lock_flock_supports_fd() {
	nvram_transaction_lock_failure 'operation=flock-probe path=/usr/bin/flock reason=unavailable' || true
	return 1
}
nvram_transaction_lock_symlink_acquire() { return 1; }
if nvram_transaction_lock_acquire; then
	fail 'acquisition succeeded after injected terminal symlink failure'
fi
case "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" in
	*operation=symlink-lock-acquire*path="${BASE_DIR}/.AdGuardHome.nvram.lock.symlink"*reason=terminal-fallback-failure*) ;;
	*) fail "fallback failure retained the flock probe diagnostic: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-unset}" ;;
esac

# Existing setup journals require ownership by the current lock holder.
sed -n '/^setup_files_begin_if_needed() {$/,/^setup_files_journal_diagnostic() {$/p' "${INSTALLER_PATH}" |
	sed '$d' >>"${FUNCTIONS_FILE}" || fail 'could not extract setup journal helper'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"
mkdir -p "${BASE_DIR}/.AdGuardHome.nvram/setup-files" || fail 'could not create existing setup journal'
SETUP_FILES_JOURNALED=0
nvram_transaction_lock_owned() { return 1; }
if setup_files_begin_if_needed; then
	fail 'existing setup journal was reused without lock ownership'
fi
case "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" in
	*operation=journal-reuse*path="${BASE_DIR}/.AdGuardHome.nvram/setup-files"*reason=lock-ownership-rejected*) ;;
	*) fail "journal ownership rejection lacked a diagnostic: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-unset}" ;;
esac

printf '%s\n' 'PASS: installer lock fallbacks preserve actionable diagnostics'
