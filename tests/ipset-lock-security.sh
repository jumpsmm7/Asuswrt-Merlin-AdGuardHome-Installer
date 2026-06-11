#!/bin/sh
# Verify IPSET lock state stays in a private root-owned directory.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
FUNCTION_FILE="${TMPDIR:-/tmp}/ipset-lock-function.$$"
TEST_DIR="${TMPDIR:-/tmp}/ipset-lock-test.$$"

cleanup() {
	rm -f "${FUNCTION_FILE}"
	rm -rf "${TEST_DIR}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

sed -n '/^IPSet_Lock() {$/,/^IPSet_Migrate() {/{ /^IPSet_Migrate() {$/d; p; }' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" || fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTION_FILE}" ] || fail 'IPSET lock functions were not found'

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

logger() {
	:
}

mkdir -p "${TEST_DIR}" || fail 'could not create test directory'
NAME=AdGuardHome

TARGET_FILE="${TEST_DIR}/target"
printf '%s\n' unchanged >"${TARGET_FILE}"
IPSET_LOCK_ROOT="${TEST_DIR}/symlink-root"
ln -s "${TARGET_FILE}" "${IPSET_LOCK_ROOT}" || fail 'could not create lock-root symlink'
if IPSet_Lock_Prepare_Root; then
	fail 'accepted a symbolic-link lock root'
fi
[ "$(cat "${TARGET_FILE}")" = unchanged ] || fail 'symbolic-link target was modified'
rm -f "${IPSET_LOCK_ROOT}"

IPSET_LOCK_ROOT="${TEST_DIR}/private-root"
IPSet_Lock_Prepare_Root || fail 'could not prepare private lock root'
[ "$(stat -c %u "${IPSET_LOCK_ROOT}")" = 0 ] || fail 'private lock root is not root-owned'
[ "$(stat -c %a "${IPSET_LOCK_ROOT}")" = 700 ] || fail 'private lock root is not mode 700'

mkdir "${IPSET_LOCK_ROOT}/mkdir" || fail 'could not create fallback lock directory'
printf '%s\n' 1 >"${IPSET_LOCK_ROOT}/mkdir/pid"
chown 65534 "${IPSET_LOCK_ROOT}/mkdir" || fail 'could not assign untrusted fallback owner'
if IPSet_Lock_Mkdir true; then
	fail 'accepted a fallback lock directory not owned by root'
fi
[ -d "${IPSET_LOCK_ROOT}/mkdir" ] || fail 'removed an untrusted fallback lock directory'

printf '%s\n' 'PASS: IPSET lock state rejects symlinks and untrusted fallback owners'
