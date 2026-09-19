#!/bin/sh
# Verify fallback lock acquisition and actionable failure diagnostics.

set -u

INSTALLER_PATH="${1:-installer}"
TEST_ROOT="${TMPDIR:-/tmp}/installer-lock-diagnostics.$$"
(umask 077 && mkdir "${TEST_ROOT}") || exit 1
FUNCTIONS_FILE="${TEST_ROOT}/functions"

# fail reports a regression failure and terminates the test.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

# cleanup stops any live helper process and removes test artifacts.
cleanup() {
	[ -z "${TEST_LIVE_PID:-}" ] || kill "${TEST_LIVE_PID}" 2>/dev/null || true
	rm -rf "${TEST_ROOT}"
}
trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

sed -n '/^nvram_transaction_lock_cross_reaper_release() {$/,/^nvram_transaction_set() {$/p' "${INSTALLER_PATH}" |
	sed '$d' >"${FUNCTIONS_FILE}" || fail 'could not extract transaction lock helpers'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

BASE_DIR="${TEST_ROOT}/opt/etc"
mkdir -p "${BASE_DIR}" || fail 'could not create simulated /opt/etc'

# Both descriptor-open failures must identify the lock file and the symlink
# that acquisition rolls back.
# nvram_transaction_lock_flock_supports_fd enables descriptor locking for the probe case.
nvram_transaction_lock_flock_supports_fd() { return 0; }
# nvram_transaction_lock_reaper_acquire permits reaper acquisition for the probe case.
nvram_transaction_lock_reaper_acquire() { return 0; }
# nvram_transaction_lock_cross_reaper_release permits probe-case cleanup.
nvram_transaction_lock_cross_reaper_release() { return 0; }
# nvram_transaction_lock_flock_open_fd rejects the descriptor probe operation.
nvram_transaction_lock_flock_open_fd() {
	[ "$1" != probe ]
}
if nvram_transaction_lock_acquire; then
	fail 'acquisition succeeded after injected descriptor probe failure'
fi
case "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" in
	*operation=open-flock-file*path="${BASE_DIR}/.AdGuardHome.nvram.lock"*rolled-back="${BASE_DIR}/.AdGuardHome.nvram.lock.symlink"*reason=probe-failed*) ;;
	*) fail "descriptor probe failure lacked rollback context: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-unset}" ;;
esac

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"
# nvram_transaction_lock_flock_supports_fd enables descriptor locking for the acquire case.
nvram_transaction_lock_flock_supports_fd() { return 0; }
# nvram_transaction_lock_reaper_acquire permits reaper acquisition for the acquire case.
nvram_transaction_lock_reaper_acquire() { return 0; }
# nvram_transaction_lock_cross_reaper_release permits acquire-case cleanup.
nvram_transaction_lock_cross_reaper_release() { return 0; }
# nvram_transaction_lock_flock_open_fd rejects the descriptor acquisition operation.
nvram_transaction_lock_flock_open_fd() {
	[ "$1" != acquire ]
}
if nvram_transaction_lock_acquire; then
	fail 'acquisition succeeded after injected descriptor acquisition failure'
fi
case "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" in
	*operation=open-flock-file*path="${BASE_DIR}/.AdGuardHome.nvram.lock"*rolled-back="${BASE_DIR}/.AdGuardHome.nvram.lock.symlink"*reason=acquire-failed*) ;;
	*) fail "descriptor acquisition failure lacked rollback context: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-unset}" ;;
esac

# Restore helpers before exercising portable fallback behavior.
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

# Exercise acquisition without /usr/bin/flock and force symlink publication to
# fail on the simulated filesystem while retaining the mkdir fallback.
# nvram_transaction_lock_flock_supports_fd forces portable lock fallback.
nvram_transaction_lock_flock_supports_fd() { return 1; }
# ln injects a symlink publication failure.
ln() { return 1; }
nvram_transaction_lock_acquire || fail "mkdir fallback failed: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-missing diagnostic}"
[ "${NVRAM_TRANSACTION_LOCK_MODE:-}" = mkdir ] || fail 'symlink failure did not select mkdir locking'
[ -z "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" ] || fail 'successful fallback retained a failure diagnostic'
nvram_transaction_lock_release || fail 'could not release mkdir fallback lock'
unset -f ln 2>/dev/null || true

# A failed symlink publication is nonterminal after successful cleanup. The
# mkdir fallback must report its own reaper failure rather than stale context.
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"
# nvram_transaction_lock_flock_supports_fd forces the portable fallback path.
nvram_transaction_lock_flock_supports_fd() { return 1; }
reaper_acquire_count=0
# nvram_transaction_lock_reaper_acquire fails the second acquisition attempt.
nvram_transaction_lock_reaper_acquire() {
	reaper_acquire_count=$((reaper_acquire_count + 1))
	[ "${reaper_acquire_count}" -eq 1 ]
}
# nvram_transaction_lock_reaper_release permits cleanup after publication failure.
nvram_transaction_lock_reaper_release() { return 0; }
# ln injects the nonterminal symlink publication failure.
ln() { return 1; }
if nvram_transaction_lock_acquire; then
	fail 'acquisition succeeded after injected mkdir reaper failure'
fi
case "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" in
	*operation=acquire-reaper*path="${BASE_DIR}/.AdGuardHome.nvram.lock.reaper"*) ;;
	*) fail "mkdir reaper failure retained stale symlink context: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-unset}" ;;
esac
case "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" in
	*operation=publish-symlink*) fail 'nonterminal symlink publication diagnostic was retained' ;;
	*) ;;
esac
unset -f ln 2>/dev/null || true

# If symlink publication and reaper cleanup both fail, publication remains the
# primary terminal diagnostic.
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"
# nvram_transaction_lock_reaper_acquire permits the injected publication attempt.
nvram_transaction_lock_reaper_acquire() { return 0; }
# nvram_transaction_lock_reaper_release injects cleanup failure.
nvram_transaction_lock_reaper_release() { return 1; }
# ln injects the primary symlink publication failure.
ln() { return 1; }
if nvram_transaction_lock_symlink_acquire; then
	fail 'symlink acquisition succeeded after publication and cleanup failures'
fi
case "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" in
	*operation=publish-symlink*path="${BASE_DIR}/.AdGuardHome.nvram.lock.symlink"*) ;;
	*) fail "cleanup replaced the symlink publication diagnostic: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-unset}" ;;
esac
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
# nvram_transaction_lock_symlink_acquire advances acquisition to the mkdir fallback.
nvram_transaction_lock_symlink_acquire() { return 2; }
# nvram_transaction_lock_reaper_acquire injects the terminal reaper failure.
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
# nvram_transaction_lock_flock_supports_fd forces portable reaper acquisition.
nvram_transaction_lock_flock_supports_fd() { return 1; }
owner="$(nvram_transaction_lock_owner_current)" || fail 'could not determine test process identity'

# Reaper contention must preserve the live owner recorded by the acquire
# implementation instead of falling back to an operation-only diagnostic.
sleep 30 &
TEST_LIVE_PID=$!
live_start="$(awk '{ print $22 }' "/proc/${TEST_LIVE_PID}/stat")" || fail 'could not read live contender identity'
live_owner="${TEST_LIVE_PID}:${live_start}"
mkdir "${BASE_DIR}/live.reaper" || fail 'could not create live reaper artifact'
printf '%s\n' "${live_owner}" >"${BASE_DIR}/live.reaper/pid"
NVRAM_TRANSACTION_LOCK_DIAGNOSTIC=""
if nvram_transaction_lock_reaper_acquire "${BASE_DIR}/live.reaper" "${owner}"; then
	fail 'reaper acquisition succeeded against a live owner'
fi
case "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" in
	*operation=acquire-reaper*path="${BASE_DIR}/live.reaper"*reason=live-owner*owner="${live_owner}"*) ;;
	*) fail "live reaper owner diagnostic was not preserved: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-unset}" ;;
esac
kill "${TEST_LIVE_PID}" 2>/dev/null || true
wait "${TEST_LIVE_PID}" 2>/dev/null || true
TEST_LIVE_PID=""
rm -rf "${BASE_DIR}/live.reaper"

# A failed flock probe is nonterminal inside reaper acquisition. If the later
# portable fallback fails silently, the wrapper must report that terminal
# acquisition failure rather than stale probe-cleanup context.
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"
probe_reaper_path="${BASE_DIR}/probe.reaper"
# nvram_transaction_lock_reaper_legacy_claim publishes the fallback owner record.
nvram_transaction_lock_reaper_legacy_claim() {
	mkdir "$1" || return 1
	printf '%s\n' "$2" >"$1/pid"
}
# nvram_transaction_lock_flock_supports_fd injects a noisy capability miss.
nvram_transaction_lock_flock_supports_fd() {
	nvram_transaction_lock_failure 'operation=flock-probe-cleanup path=stale-probe' || true
	return 1
}
# nvram_transaction_lock_readlink makes the portable fallback fail silently.
nvram_transaction_lock_readlink() {
	NVRAM_TRANSACTION_REAPER_LOCK_PATH=""
	return 127
}
NVRAM_TRANSACTION_LOCK_DIAGNOSTIC=""
if nvram_transaction_lock_reaper_acquire "${probe_reaper_path}" "${owner}"; then
	fail 'reaper acquisition succeeded after injected portable fallback failure'
fi
case "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" in
	"operation=acquire-reaper path=${probe_reaper_path}") ;;
	*) fail "reaper fallback retained stale flock probe context: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-unset}" ;;
esac
rm -rf "${probe_reaper_path}"

# Losing stale-symlink reclamation must retain the observed contender, and a
# failed legacy cleanup must be appended as secondary context.
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"
reclaim_path="${BASE_DIR}/reclaim.reaper"
filename_safe_owner="66816:373949"
# nvram_transaction_lock_flock_supports_fd selects legacy reaper locking.
nvram_transaction_lock_flock_supports_fd() { return 1; }
# nvram_transaction_lock_owner_live marks the observed owner as stale.
nvram_transaction_lock_owner_live() { return 1; }
# nvram_transaction_lock_reaper_legacy_claim publishes a competing owner record.
nvram_transaction_lock_reaper_legacy_claim() {
	mkdir "$1" || return 1
	printf '%s\n' "$2" >"$1/pid"
}
# nvram_transaction_lock_reaper_legacy_release injects secondary cleanup failure.
nvram_transaction_lock_reaper_legacy_release() { return 1; }
# The temporary-symlink call boundary rejects nonportable artifact names, but
# permits a colon in the target because it remains the original owner identity.
nvram_transaction_lock_reaper_temp_symlink_create() {
	case "$2" in
		*:*) return 1 ;;
	esac
	/bin/ln -s "$1" "$2"
}
# mv simulates losing ownership during stale-symlink reclamation.
mv() {
	case "$1" in
		*:*) return 1 ;;
	esac
	command mv "$@" || return 1
	rm -f "${reclaim_path}.symlink" || return 1
	command ln -s winning-owner "${reclaim_path}.symlink"
}
ln -s stale-owner "${reclaim_path}.symlink" || fail 'could not create stale reaper symlink'
NVRAM_TRANSACTION_LOCK_DIAGNOSTIC=""
if nvram_transaction_lock_reaper_acquire "${reclaim_path}" "${filename_safe_owner}"; then
	fail 'reaper acquisition succeeded after losing stale-symlink reclamation'
fi
case "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" in
	*operation=acquire-reaper*path="${reclaim_path}.symlink"*reason=ownership-lost*owner=winning-owner*after-failed-operation="release-reaper:${reclaim_path}"*) ;;
	*) fail "reaper ownership-loss cleanup diagnostic was incomplete: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-unset}" ;;
esac
[ ! -e "${reclaim_path}.symlink.66816.373949" ] && [ ! -L "${reclaim_path}.symlink.66816.373949" ] || fail 'failed reclaim left its filename-safe temporary symlink'
unset -f mv 2>/dev/null || true
unset -f nvram_transaction_lock_reaper_temp_symlink_create 2>/dev/null || true
rm -rf "${reclaim_path}" "${reclaim_path}.symlink"

# Restore helpers before the main lock-contention scenario.
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"
# nvram_transaction_lock_flock_supports_fd selects portable contention handling.
nvram_transaction_lock_flock_supports_fd() { return 1; }
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
# nvram_transaction_lock_reaper_release_impl injects a detailed cleanup failure.
nvram_transaction_lock_reaper_release_impl() {
	nvram_transaction_lock_failure "operation=release-reaper path=$1 reason=cleanup-failed" || true
	return 1
}
NVRAM_TRANSACTION_LOCK_DIAGNOSTIC="operation=validate-stale-lock path=${BASE_DIR}/.AdGuardHome.nvram.lock.symlink reason=live-owner owner=${owner}"
if nvram_transaction_lock_reaper_release "${BASE_DIR}/.AdGuardHome.nvram.lock.reaper" "${owner}"; then
	fail 'injected reaper release failure succeeded'
fi
case "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" in
	*operation=validate-stale-lock*path="${BASE_DIR}/.AdGuardHome.nvram.lock.symlink"*reason=live-owner*owner="${owner}"*after-failed-operation="release-reaper:${BASE_DIR}/.AdGuardHome.nvram.lock.reaper"*release-diagnostic=operation=release-reaper*reason=cleanup-failed*) ;;
	*) fail "reaper release replaced the primary diagnostic: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-unset}" ;;
esac
# nvram_transaction_lock_reaper_release_impl injects a silent standalone failure.
nvram_transaction_lock_reaper_release_impl() { return 1; }
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
NVRAM_TRANSACTION_REAPER_LOCK_MODE="mkdir"
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

# A release failure after symlink publication validation must preserve the
# validation diagnostic and append cleanup failure context.
rm -f "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink"
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"
# nvram_transaction_lock_flock_supports_fd selects portable publication validation.
nvram_transaction_lock_flock_supports_fd() { return 1; }
# nvram_transaction_lock_reaper_acquire permits publication validation to run.
nvram_transaction_lock_reaper_acquire() { return 0; }
# nvram_transaction_lock_reaper_release_impl injects detailed validation cleanup failure.
nvram_transaction_lock_reaper_release_impl() {
	nvram_transaction_lock_failure "operation=release-reaper path=$1 reason=cleanup-failed" || true
	return 1
}
# ln replaces the published owner to simulate validation loss.
ln() {
	command ln "$@" || return 1
	rm -f "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink" || return 1
	command ln -s different-owner "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink"
}
if nvram_transaction_lock_acquire; then
	fail 'acquisition succeeded after symlink validation and reaper release failures'
fi
case "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" in
	*operation=validate-symlink-publication*rolled-back="${BASE_DIR}/.AdGuardHome.nvram.lock.symlink"*after-failed-operation="release-reaper:${BASE_DIR}/.AdGuardHome.nvram.lock.reaper"*release-diagnostic=operation=release-reaper*reason=cleanup-failed*) ;;
	*) fail "reaper release replaced the symlink validation diagnostic: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-unset}" ;;
esac
rm -f "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink"
unset -f ln 2>/dev/null || true

# An expected flock capability miss must not obscure the terminal portable
# fallback failure.
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"
# nvram_transaction_lock_flock_supports_fd injects an expected capability miss.
nvram_transaction_lock_flock_supports_fd() {
	nvram_transaction_lock_failure 'operation=flock-probe path=/usr/bin/flock reason=unavailable' || true
	return 1
}
# nvram_transaction_lock_symlink_acquire injects terminal portable fallback failure.
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
# nvram_transaction_lock_owned rejects reuse by a nonowner.
nvram_transaction_lock_owned() { return 1; }
if setup_files_begin_if_needed; then
	fail 'existing setup journal was reused without lock ownership'
fi
case "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" in
	*operation=journal-reuse*path="${BASE_DIR}/.AdGuardHome.nvram/setup-files"*reason=lock-ownership-rejected*) ;;
	*) fail "journal ownership rejection lacked a diagnostic: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-unset}" ;;
esac

printf '%s\n' 'PASS: installer lock fallbacks preserve actionable diagnostics'
