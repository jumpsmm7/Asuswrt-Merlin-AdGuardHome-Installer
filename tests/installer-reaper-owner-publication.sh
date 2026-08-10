#!/bin/sh
# Verify the mkdir reaper cannot reclaim a directory while its owner is being published.

set -u

INSTALLER_PATH="${1:-installer}"
TEST_ROOT="${TMPDIR:-/tmp}/installer-reaper-owner-publication.$$"
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

mkdir -p "${TEST_ROOT}" || fail 'could not create test workspace'
sed -n '/^nvram_transaction_recover_startup() {$/,/^installer_lan_domain_set() {$/p' "${INSTALLER_PATH}" |
	sed '$d' >"${FUNCTIONS_FILE}" || fail 'could not extract transaction lock helpers'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

reaper_path="${TEST_ROOT}/owner-publication.reaper"
LOCK_OWNER="$$:1"

# nvram_transaction_lock_flock_supports_fd reports that file-descriptor locking is unavailable.
nvram_transaction_lock_flock_supports_fd() { return 1; }
# nvram_transaction_lock_readlink returns 127 to indicate that symbolic-link support is unavailable.
nvram_transaction_lock_readlink() { return 127; }
sleep() { :; }

# This directory represents an installer paused after mkdir and before writing pid.
mkdir "${reaper_path}" || fail 'could not create ownerless reaper directory'
if nvram_transaction_lock_reaper_acquire "${reaper_path}" "${LOCK_OWNER}"; then
	fail 'a contender reclaimed an ownerless reaper during owner publication'
fi
[ -d "${reaper_path}" ] || fail 'a contender removed the ownerless reaper directory'
[ ! -e "${reaper_path}/pid" ] || fail 'a contender overwrote the pending reaper owner'

# The original installer must still be able to finish publishing into its directory.
printf '%s\n' "${LOCK_OWNER}" >"${reaper_path}/pid" || fail 'original owner could not finish publication'
[ "$(cat "${reaper_path}/pid" 2>/dev/null)" = "${LOCK_OWNER}" ] || fail 'published reaper owner changed'

printf '%s\n' 'PASS: mkdir reaper preserves owner publication ownership'
