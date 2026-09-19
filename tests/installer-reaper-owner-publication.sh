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

sed -n '/^nvram_transaction_setup_files_failure() {$/,/^nvram_transaction_setup_files_restore() {$/p' "${INSTALLER_PATH}" |
	sed '$d' >"${FUNCTIONS_FILE}" || fail 'could not extract setup journal helpers'
sed -n '/^nvram_transaction_recover_startup() {$/,/^installer_lan_domain_set() {$/p' "${INSTALLER_PATH}" |
	sed '$d' >>"${FUNCTIONS_FILE}" || fail 'could not extract transaction lock helpers'
[ -s "${FUNCTIONS_FILE}" ] || fail 'transaction lock helper extraction was empty'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"
for reaper_fn in nvram_transaction_lock_reaper_acquire nvram_transaction_lock_reaper_release; do
	type "${reaper_fn}" >/dev/null 2>&1 || fail "extracted helpers are missing ${reaper_fn}()"
done

reaper_path="${TEST_ROOT}/owner-publication.reaper"
LOCK_OWNER="66816:373949"

# mkdir rejects nonportable temporary artifact names while allowing owner data
# containing a colon to remain inside the published pid file.
mkdir() {
	case "$*" in
		*:*) return 1 ;;
	esac
	command mkdir "$@"
}

# nvram_transaction_lock_flock_supports_fd reports that file-descriptor locking is unavailable.
nvram_transaction_lock_flock_supports_fd() { return 1; }
# nvram_transaction_lock_readlink returns 127 to indicate that symbolic-link support is unavailable.
nvram_transaction_lock_readlink() { return 127; }
# sleep skips acquisition backoff delays in this regression test.
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
mkdir "${reaper_path}.claim.66816.373949" || fail 'could not create colliding claim artifact'
mkdir "${reaper_path}" || fail 'could not create stale reaper fixture'
mv "${reaper_path}.stale-owner" "${reaper_path}/pid" || fail 'could not publish stale reaper owner'
nvram_transaction_lock_reaper_acquire "${reaper_path}" "${LOCK_OWNER}" || fail 'stale published owner was not reclaimed'
[ "$(cat "${reaper_path}/pid" 2>/dev/null)" = "${LOCK_OWNER}" ] || fail 'reclaimed reaper did not preserve the original owner identity'
nvram_transaction_lock_reaper_release "${reaper_path}" "${LOCK_OWNER}" || fail 'stale reaper was not released'
rm -rf "${reaper_path}.claim.66816.373949" || fail 'could not remove colliding claim fixture'

mkdir "${reaper_path}" || fail 'could not create PID-reuse reaper fixture'
printf '%s:0\n' "$$" >"${reaper_path}/pid" || fail 'could not publish PID-reuse owner'
nvram_transaction_lock_reaper_acquire "${reaper_path}" "${LOCK_OWNER}" || fail 'PID-reused owner was not reclaimed'
nvram_transaction_lock_reaper_release "${reaper_path}" "${LOCK_OWNER}" || fail 'PID-reused reaper was not released'

# Exercise the stale-symlink replacement path with the same filename check.
# nvram_transaction_lock_readlink delegates supported symbolic-link reads to the system command.
nvram_transaction_lock_readlink() {
	[ "$#" -gt 0 ] || return 0
	command readlink "$@"
}
# ln rejects colon-bearing destination names while preserving colon-delimited symlink targets.
ln() {
	local destination
	for destination; do :; done
	case "${destination}" in
		*:*) return 1 ;;
	esac
	command ln "$@"
}
ln -s stale-owner "${reaper_path}.symlink" || fail 'could not create stale symlink fixture'
ln -s "${LOCK_OWNER}" "${reaper_path}.symlink.66816.373949" || fail 'could not create colliding temporary symlink fixture'
nvram_transaction_lock_reaper_acquire "${reaper_path}" "${LOCK_OWNER}" || fail 'stale symlink owner was not reclaimed with a filename-safe artifact'
[ "${NVRAM_TRANSACTION_REAPER_LOCK_MODE:-}" = symlink ] || fail 'stale symlink reclaim did not select symlink locking'
[ "$(cat "${reaper_path}/pid" 2>/dev/null)" = "${LOCK_OWNER}" ] || fail 'symlink reclaim changed the colon-delimited pid owner'
nvram_transaction_lock_reaper_release "${reaper_path}" "${LOCK_OWNER}" || fail 'symlink-backed reaper was not released'
rm -f "${reaper_path}.symlink.66816.373949" || fail 'could not remove colliding temporary symlink fixture'

# Exercise successful descriptor locking when the validation host provides
# flock. The optional router capability still falls back when flock is absent.
if [ -x /usr/bin/flock ]; then
	nvram_transaction_lock_flock_supports_fd() { return 0; }
	mkdir "${reaper_path}.claim.66816.373949" || fail 'could not create flock claim collision fixture'
	nvram_transaction_lock_reaper_acquire "${reaper_path}" "${LOCK_OWNER}" || fail 'flock-backed reaper did not bypass a colliding filename-safe claim'
	[ "${NVRAM_TRANSACTION_REAPER_LOCK_MODE:-}" = flock ] || fail 'descriptor-capable reaper did not select flock locking'
	[ "$(cat "${reaper_path}/pid" 2>/dev/null)" = "${LOCK_OWNER}" ] || fail 'flock-backed reaper changed the colon-delimited pid owner'
	nvram_transaction_lock_reaper_release "${reaper_path}" "${LOCK_OWNER}" || fail 'flock-backed reaper was not released'
	[ -z "${NVRAM_TRANSACTION_REAPER_LOCK_MODE:-}" ] || fail 'flock-backed release retained its lock mode'
	rm -rf "${reaper_path}.claim.66816.373949" || fail 'could not remove flock claim collision fixture'
fi

# Reproduce the reported setup-journal boundary with the complete transaction
# lock path. The simulated filesystem rejects the old colon-bearing claim name.
BASE_DIR="${TEST_ROOT}/setup"
YAML_FILE="${TEST_ROOT}/AdGuardHome.yaml"
YAML_ORI="${TEST_ROOT}/AdGuardHome.yaml.original"
YAML_BAK="${TEST_ROOT}/AdGuardHome.yaml.backup"
CONF_FILE="${TEST_ROOT}/.config"
mkdir -p "${BASE_DIR}" || fail 'could not create setup-journal base directory'
mkdir "${BASE_DIR}/.AdGuardHome.nvram.lock.reaper.claim.66816.373949" || fail 'could not create setup-journal claim collision fixture'
nvram_transaction_lock_owner_current() {
	case "${1:-66816}" in
		66816) printf '%s\n' "${LOCK_OWNER}" ;;
		*) return 1 ;;
	esac
}
nvram_transaction_lock_readlink() { return 127; }
nvram_transaction_setup_files_begin || fail "setup journal lock acquisition failed: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-missing diagnostic}"
[ -d "${BASE_DIR}/.AdGuardHome.nvram/setup-files" ] || fail 'setup journal was not published after filename-safe reaper acquisition'
[ "${NVRAM_TRANSACTION_LOCK_MODE:-}" = mkdir ] || fail 'setup journal transaction did not select mkdir locking'
[ "$(cat "${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid" 2>/dev/null)" = "${LOCK_OWNER}" ] || fail 'setup journal lock did not persist the colon-delimited owner identity'
[ -z "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" ] || fail "successful setup journal acquisition retained a lock diagnostic: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC}"
nvram_transaction_lock_release || fail 'setup journal transaction lock was not released'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram.lock.d" ] || fail 'setup journal transaction lock remained after release'
rm -rf "${BASE_DIR}/.AdGuardHome.nvram.lock.reaper.claim.66816.373949" || fail 'could not remove setup-journal claim collision fixture'

if find "${TEST_ROOT}" \( -name '*.claim.*' -o -name '*.symlink.*' \) -print | grep -q .; then
	fail 'temporary reaper publication artifacts remained after release'
fi

printf '%s\n' 'PASS: mkdir reaper preserves paused legacy publishers and reclaims verified stale owners'
