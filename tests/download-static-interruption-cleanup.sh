#!/bin/sh
# Verify interrupted static downloads remove destination-directory temporary files.

set -u

SCRIPT_PATH="${1:-tools/download-adguardhome-static.sh}"
TEST_ROOT="${TMPDIR:-/tmp}/download-static-interruption-cleanup.$$"
FUNCTION_FILE="${TEST_ROOT}/functions"

cleanup() {
	rm -rf "${TEST_ROOT}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
mkdir -p "${TEST_ROOT}" || fail "could not create test directory"

sed -n '/^cleanup_download_tmp() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" ||
	fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTION_FILE}" ] || fail "download cleanup helper was not found"

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

ACTIVE_DOWNLOAD_TMP="${TEST_ROOT}/AdGuardHome_stable_linux_arm64.tar.gz.tmp.$$"
printf '%s\n' "partial archive" >"${ACTIVE_DOWNLOAD_TMP}" ||
	fail "could not create partial archive"
cleanup_download_tmp
[ ! -e "${TEST_ROOT}/AdGuardHome_stable_linux_arm64.tar.gz.tmp.$$" ] ||
	fail "download cleanup left the partial archive behind"
[ ! -e "${TEST_ROOT}/AdGuardHome_stable_linux_arm64.tar.gz.tmp.$$.sha256sum" ] ||
	fail "download cleanup left unpublished checksum metadata behind"
[ -z "${ACTIVE_DOWNLOAD_TMP}" ] ||
	fail "download cleanup did not clear the tracked path"

grep -F "trap 'cleanup_download_tmp; exit 1' HUP INT QUIT ABRT TERM" "${SCRIPT_PATH}" >/dev/null ||
	fail "download cleanup is not installed for interruption signals"

printf '%s\n' "PASS: interrupted static downloads remove partial archives"
