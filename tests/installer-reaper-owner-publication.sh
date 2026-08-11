#!/bin/sh
# Verify stale ownerless reapers are reclaimed after atomic owner publication.

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

# This directory represents a power loss from an older installer after mkdir
# and before writing pid. New acquisition must reclaim it and publish atomically.
mkdir "${reaper_path}" || fail 'could not create ownerless reaper directory'
nvram_transaction_lock_reaper_acquire "${reaper_path}" "${LOCK_OWNER}" ||
	fail 'a stale ownerless reaper was not reclaimed'
[ "$(cat "${reaper_path}/pid" 2>/dev/null)" = "${LOCK_OWNER}" ] || fail 'published reaper owner changed'
nvram_transaction_lock_reaper_release "${reaper_path}" "${LOCK_OWNER}" || fail 'reclaimed reaper was not released'
[ ! -e "${reaper_path}" ] || fail 'released reaper directory remained'

printf '%s\n' 'PASS: mkdir reaper atomically publishes and reclaims ownerless artifacts'
