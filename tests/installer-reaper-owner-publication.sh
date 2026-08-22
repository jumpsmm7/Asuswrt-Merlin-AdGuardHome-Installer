#!/bin/sh
# Verify stale ownerless reapers are reclaimed after atomic owner publication.

set -u

INSTALLER_PATH="${1:-installer}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/installer-reaper-owner-publication.XXXXXX")" || {
	printf '%s\n' 'FAIL: could not create exclusive reaper test workspace' >&2
	exit 1
}
FUNCTIONS_FILE="${TEST_ROOT}/functions"

# fail reports a test failure and exits with a nonzero status.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

# cleanup removes the temporary test workspace.
cleanup() { rm -rf "${TEST_ROOT}"; }
trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

sed -n '/^nvram_transaction_recover_startup() {$/,/^installer_lan_domain_set() {$/p' "${INSTALLER_PATH}" |
	sed '$d' >"${FUNCTIONS_FILE}" || fail 'could not extract transaction lock helpers'
[ -s "${FUNCTIONS_FILE}" ] || fail 'transaction lock helper extraction was empty'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"
for reaper_fn in nvram_transaction_lock_reaper_acquire nvram_transaction_lock_reaper_release; do
	type "${reaper_fn}" >/dev/null 2>&1 || fail "extracted helpers are missing ${reaper_fn}()"
done

reaper_path="${TEST_ROOT}/owner-publication.reaper"
LOCK_OWNER="$$:1"

# nvram_transaction_lock_flock_supports_fd reports that file-descriptor locking is unavailable.
nvram_transaction_lock_flock_supports_fd() { return 1; }
# nvram_transaction_lock_readlink returns 127 to indicate that symbolic-link support is unavailable.
nvram_transaction_lock_readlink() { return 127; }
sleep() { :; }

# This directory represents an older installer paused after mkdir and before
# writing pid. A new installer must not steal its directory while it can resume.
mkdir "${reaper_path}" || fail 'could not create ownerless reaper directory'
if nvram_transaction_lock_reaper_acquire "${reaper_path}" "${LOCK_OWNER}"; then
	fail 'a contender stole a paused legacy owner publication'
fi
[ -d "${reaper_path}" ] || fail 'a contender removed the paused legacy reaper'
printf '%s\n' "${LOCK_OWNER}" >"${reaper_path}/pid" || fail 'paused legacy owner could not resume publication'
[ "$(cat "${reaper_path}/pid" 2>/dev/null)" = "${LOCK_OWNER}" ] || fail 'resumed legacy publication changed owner'
rm -rf "${reaper_path}"

# Dead and PID-reused published owners remain safely reclaimable.
printf '%s\n' 999999999 >"${reaper_path}.stale-owner"
mkdir "${reaper_path}" || fail 'could not create stale reaper fixture'
mv "${reaper_path}.stale-owner" "${reaper_path}/pid" || fail 'could not publish stale reaper owner'
nvram_transaction_lock_reaper_acquire "${reaper_path}" "${LOCK_OWNER}" || fail 'stale published owner was not reclaimed'
nvram_transaction_lock_reaper_release "${reaper_path}" "${LOCK_OWNER}" || fail 'stale reaper was not released'

mkdir "${reaper_path}" || fail 'could not create PID-reuse reaper fixture'
printf '%s:0\n' "$$" >"${reaper_path}/pid" || fail 'could not publish PID-reuse owner'
nvram_transaction_lock_reaper_acquire "${reaper_path}" "${LOCK_OWNER}" || fail 'PID-reused owner was not reclaimed'
nvram_transaction_lock_reaper_release "${reaper_path}" "${LOCK_OWNER}" || fail 'PID-reused reaper was not released'

printf '%s\n' 'PASS: mkdir reaper preserves paused legacy publishers and reclaims verified stale owners'
