#!/bin/sh
# Verify static archive maintenance preserves published checksum files on failures.

set -u

SCRIPT_PATH="${1:-tools/download-adguardhome-static.sh}"
TEST_ROOT="${TMPDIR:-/tmp}/download-static-failure-safety.$$"
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
mkdir -p "${TEST_ROOT}/out/armv7" || fail "could not create test directory"

sed -n '/^append_metadata() {$/,/^}$/p; /^download_arch() {$/,/^}$/p; /^publish_archive_with_md5() {$/,/^}$/p; /^publish_metadata_files() {$/,/^}$/p; /^write_md5sum_file() {$/,/^}$/p' \
	"${SCRIPT_PATH}" >"${FUNCTION_FILE}" || fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTION_FILE}" ] || fail "static download helpers were not found"

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

FAILED=0

printf '%s\n' "known checksum" >"${TEST_ROOT}/archive.md5sum"
chmod() {
	return 1
}
if write_md5sum_file "${TEST_ROOT}/archive" newchecksum >/dev/null 2>&1; then
	fail "write_md5sum_file accepted a chmod failure"
fi
[ "$(sed -n '1p' "${TEST_ROOT}/archive.md5sum")" = "known checksum" ] ||
	fail "failed checksum update replaced the published checksum"

unset -f chmod
REAL_MV="$(which mv)" || fail "mv is unavailable"
printf '%s\n' "old archive" >"${TEST_ROOT}/archive"
printf '%s\n' "old checksum" >"${TEST_ROOT}/archive.md5sum"
printf '%s\n' "new archive" >"${TEST_ROOT}/archive.tmp"
ARCHIVE_WAS_PUBLISHED=0
mv() {
	case "$1" in
		"${TEST_ROOT}/archive.tmp")
			if [ -f "${TEST_ROOT}/archive" ] &&
				[ "$(sed -n '1p' "${TEST_ROOT}/archive")" = "old archive" ]; then
				ARCHIVE_WAS_PUBLISHED=1
			fi
			;;
		*.md5sum.tmp.*)
			return 1
			;;
	esac
	"${REAL_MV}" "$@"
}
if publish_archive_with_md5 "${TEST_ROOT}/archive.tmp" "${TEST_ROOT}/archive" newchecksum >/dev/null 2>&1; then
	fail "archive publication accepted a checksum move failure"
fi
[ "$(sed -n '1p' "${TEST_ROOT}/archive")" = "old archive" ] ||
	fail "failed archive publication did not restore the previous archive"
[ "$(sed -n '1p' "${TEST_ROOT}/archive.md5sum")" = "old checksum" ] ||
	fail "failed archive publication did not restore the previous checksum"
[ "${ARCHIVE_WAS_PUBLISHED}" -eq 1 ] ||
	fail "archive publication removed the previous archive before replacement"

unset -f mv
mkdir -p "${TEST_ROOT}/metadata" || fail "could not create metadata directory"
printf '%s\n' "old version" >"${TEST_ROOT}/metadata/VERSION.txt"
printf '%s\n' "old metadata checksum" >"${TEST_ROOT}/metadata/checksum.txt"
printf '%s\n' "new version" >"${TEST_ROOT}/metadata/VERSION.txt.tmp"
printf '%s\n' "new metadata checksum" >"${TEST_ROOT}/metadata/checksum.txt.tmp"
mv() {
	case "$1" in
		*/checksum.txt.tmp)
			return 1
			;;
	esac
	"${REAL_MV}" "$@"
}
if publish_metadata_files "${TEST_ROOT}/metadata" >/dev/null 2>&1; then
	fail "metadata publication accepted a checksum metadata move failure"
fi
[ "$(sed -n '1p' "${TEST_ROOT}/metadata/VERSION.txt")" = "old version" ] ||
	fail "failed metadata publication did not restore VERSION.txt"
[ "$(sed -n '1p' "${TEST_ROOT}/metadata/checksum.txt")" = "old metadata checksum" ] ||
	fail "failed metadata publication did not restore checksum.txt"

printf '%s\n' "PASS: static archive and metadata publication preserves complete working sets on failure"
