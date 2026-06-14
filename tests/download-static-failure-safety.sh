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

sed -n '/^append_metadata() {$/,/^}$/p; /^acquire_metadata_publication_lock() {$/,/^}$/p; /^download_arch() {$/,/^}$/p; /^recover_archive_publication() {$/,/^}$/p; /^recover_metadata_publication() {$/,/^}$/p; /^release_metadata_publication_lock() {$/,/^}$/p; /^archive_publication_owner_is_active() {$/,/^}$/p; /^acquire_archive_publication_state() {$/,/^}$/p; /^publish_archive_with_md5() {$/,/^}$/p; /^publish_metadata_files() {$/,/^}$/p; /^write_md5sum_file() {$/,/^}$/p' \
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
printf '%s\n' "downloaded archive" >"${TEST_ROOT}/archive.tmp"
printf '%s\n' "newer concurrent archive" >"${TEST_ROOT}/archive"
printf '%s\n' "newer concurrent checksum" >"${TEST_ROOT}/archive.md5sum"
if publish_archive_with_md5 "${TEST_ROOT}/archive.tmp" "${TEST_ROOT}/archive" \
	stalechecksum require-unchanged >/dev/null 2>&1; then
	fail "checksum refresh replaced an archive changed by a concurrent publisher"
fi
[ "$(sed -n '1p' "${TEST_ROOT}/archive")" = "newer concurrent archive" ] ||
	fail "checksum refresh replaced the concurrently published archive"
[ "$(sed -n '1p' "${TEST_ROOT}/archive.md5sum")" = "newer concurrent checksum" ] ||
	fail "checksum refresh replaced the concurrently published checksum"
[ ! -e "${TEST_ROOT}/archive.publish-in-progress" ] ||
	fail "failed checksum refresh left publication state behind"

REAL_RM="$(which rm)" || fail "rm is unavailable"
printf '%s\n' "old archive" >"${TEST_ROOT}/archive"
printf '%s\n' "old checksum" >"${TEST_ROOT}/archive.md5sum"
printf '%s\n' "new archive" >"${TEST_ROOT}/archive.tmp"
rm() {
	case "$*" in
		*archive.publish-in-progress*) return 1 ;;
	esac
	"${REAL_RM}" "$@"
}
if publish_archive_with_md5 "${TEST_ROOT}/archive.tmp" "${TEST_ROOT}/archive" newchecksum >/dev/null 2>&1; then
	fail "archive publication accepted a publication-state cleanup failure"
fi
[ "$(sed -n '1p' "${TEST_ROOT}/archive")" = "new archive" ] ||
	fail "state cleanup failure replaced the newly published archive"
[ "$(sed -n '1p' "${TEST_ROOT}/archive.md5sum")" = "newchecksum" ] ||
	fail "state cleanup failure replaced the newly published checksum"
[ -e "${TEST_ROOT}/archive.previous" ] ||
	fail "state cleanup failure discarded the archive rollback copy"
[ -e "${TEST_ROOT}/archive.md5sum.previous" ] ||
	fail "state cleanup failure discarded the checksum rollback copy"
[ -e "${TEST_ROOT}/archive.publish-in-progress" ] ||
	fail "failed publication state cleanup unexpectedly removed the state marker"
unset -f rm
"${REAL_RM}" -f "${TEST_ROOT}/archive.publish-in-progress" \
	"${TEST_ROOT}/archive.previous" "${TEST_ROOT}/archive.md5sum.previous"

PUBLISH_START_TIME="$(awk '{
	sub(/^.*\) /, "")
	print $20
}' "/proc/$$/stat")" || fail "could not read test process start time"
printf '%s %s\n' "$$" "${PUBLISH_START_TIME}" >"${TEST_ROOT}/archive.publish-in-progress"
printf '%s\n' "untouched rollback archive" >"${TEST_ROOT}/archive.previous"
printf '%s\n' "untouched rollback checksum" >"${TEST_ROOT}/archive.md5sum.previous"
printf '%s\n' "contending archive" >"${TEST_ROOT}/archive.tmp"
if publish_archive_with_md5 "${TEST_ROOT}/archive.tmp" "${TEST_ROOT}/archive" contendingchecksum >/dev/null 2>&1; then
	fail "archive publication acquired state already owned by an active publisher"
fi
[ "$(sed -n '1p' "${TEST_ROOT}/archive.previous")" = "untouched rollback archive" ] ||
	fail "contending archive publication modified the active publisher's archive backup"
[ "$(sed -n '1p' "${TEST_ROOT}/archive.md5sum.previous")" = "untouched rollback checksum" ] ||
	fail "contending archive publication modified the active publisher's checksum backup"

printf '%s %s\n' "$$" "${PUBLISH_START_TIME}" >"${TEST_ROOT}/archive.publish-in-progress"
printf '%s\n' "live archive" >"${TEST_ROOT}/archive"
printf '%s\n' "live checksum" >"${TEST_ROOT}/archive.md5sum"
printf '%s\n' "rollback archive" >"${TEST_ROOT}/archive.previous"
printf '%s\n' "rollback checksum" >"${TEST_ROOT}/archive.md5sum.previous"
if recover_archive_publication "${TEST_ROOT}/archive" >/dev/null 2>&1; then
	fail "active archive publication was treated as interrupted"
fi
[ "$(sed -n '1p' "${TEST_ROOT}/archive")" = "live archive" ] ||
	fail "active publication recovery replaced the live archive"
[ "$(sed -n '1p' "${TEST_ROOT}/archive.md5sum")" = "live checksum" ] ||
	fail "active publication recovery replaced the live checksum"
[ -e "${TEST_ROOT}/archive.publish-in-progress" ] ||
	fail "active publication state was removed"

printf '%s %s preparing\n' "999999" "1" >"${TEST_ROOT}/archive.publish-in-progress"
printf '%s\n' "complete archive" >"${TEST_ROOT}/archive"
printf '%s\n' "complete checksum" >"${TEST_ROOT}/archive.md5sum"
printf '%s\n' "partial rollback archive" >"${TEST_ROOT}/archive.previous"
"${REAL_RM}" -f "${TEST_ROOT}/archive.md5sum.previous"
recover_archive_publication "${TEST_ROOT}/archive" >/dev/null 2>&1 ||
	fail "incomplete archive backup preparation was not recovered"
[ "$(sed -n '1p' "${TEST_ROOT}/archive")" = "complete archive" ] ||
	fail "incomplete backup recovery removed the published archive"
[ "$(sed -n '1p' "${TEST_ROOT}/archive.md5sum")" = "complete checksum" ] ||
	fail "incomplete backup recovery removed the published checksum"
[ ! -e "${TEST_ROOT}/archive.publish-in-progress" ] ||
	fail "incomplete backup preparation state was not cleared"
[ ! -e "${TEST_ROOT}/archive.previous" ] ||
	fail "partial archive rollback copy was not discarded"

:
>"${TEST_ROOT}/archive.publish-in-progress"
printf '%s\n' "complete archive" >"${TEST_ROOT}/archive"
printf '%s\n' "complete checksum" >"${TEST_ROOT}/archive.md5sum"
recover_archive_publication "${TEST_ROOT}/archive" >/dev/null 2>&1 ||
	fail "empty archive publication state was not recovered"
[ "$(sed -n '1p' "${TEST_ROOT}/archive")" = "complete archive" ] ||
	fail "empty publication state removed the published archive"
[ "$(sed -n '1p' "${TEST_ROOT}/archive.md5sum")" = "complete checksum" ] ||
	fail "empty publication state removed the published checksum"
[ ! -e "${TEST_ROOT}/archive.publish-in-progress" ] ||
	fail "empty publication state was not cleared"

printf '%s\n' "old archive" >"${TEST_ROOT}/archive.previous"
printf '%s\n' "old checksum" >"${TEST_ROOT}/archive.md5sum.previous"
printf '%s\n' "new archive" >"${TEST_ROOT}/archive"
printf '%s\n' "old checksum" >"${TEST_ROOT}/archive.md5sum"
printf '%s %s ready 1 1\n' "999999" "1" \
	>"${TEST_ROOT}/archive.publish-in-progress"
recover_archive_publication "${TEST_ROOT}/archive" >/dev/null 2>&1 ||
	fail "interrupted archive publication was not recovered"
[ "$(sed -n '1p' "${TEST_ROOT}/archive")" = "old archive" ] ||
	fail "interrupted publication did not restore the previous archive"
[ "$(sed -n '1p' "${TEST_ROOT}/archive.md5sum")" = "old checksum" ] ||
	fail "interrupted publication did not restore the previous checksum"
[ ! -e "${TEST_ROOT}/archive.publish-in-progress" ] ||
	fail "interrupted publication state was not cleared"

mkdir -p "${TEST_ROOT}/metadata" || fail "could not create metadata directory"
acquire_metadata_publication_lock "${TEST_ROOT}/metadata" ||
	fail "could not acquire metadata publication lock"
if acquire_metadata_publication_lock "${TEST_ROOT}/metadata" >/dev/null 2>&1; then
	fail "concurrent metadata generation acquired the active lock"
fi
[ ! -e "${TEST_ROOT}/metadata/VERSION.txt.tmp" ] ||
	fail "lock contention modified shared VERSION metadata"
[ ! -e "${TEST_ROOT}/metadata/checksum.txt.tmp" ] ||
	fail "lock contention modified shared checksum metadata"
release_metadata_publication_lock "${TEST_ROOT}/metadata" ||
	fail "could not release metadata publication lock"
mkdir "${TEST_ROOT}/metadata/.metadata.lock" ||
	fail "could not create abandoned metadata lock"
printf '%s\n' "abandoned" >"${TEST_ROOT}/metadata/.metadata.lock/owner"
acquire_metadata_publication_lock "${TEST_ROOT}/metadata" ||
	fail "could not recover abandoned metadata publication lock"
release_metadata_publication_lock "${TEST_ROOT}/metadata" ||
	fail "could not release recovered metadata publication lock"

printf '%s %s ready 1 1\n' "$$" "${PUBLISH_START_TIME}" \
	>"${TEST_ROOT}/metadata/.metadata.publish-in-progress"
printf '%s\n' "untouched metadata version backup" \
	>"${TEST_ROOT}/metadata/VERSION.txt.previous"
printf '%s\n' "untouched metadata checksum backup" \
	>"${TEST_ROOT}/metadata/checksum.txt.previous"
printf '%s\n' "contending version" >"${TEST_ROOT}/metadata/VERSION.txt.tmp"
printf '%s\n' "contending checksum" >"${TEST_ROOT}/metadata/checksum.txt.tmp"
if publish_metadata_files "${TEST_ROOT}/metadata" >/dev/null 2>&1; then
	fail "metadata publication acquired state already owned by an active publisher"
fi
[ "$(sed -n '1p' "${TEST_ROOT}/metadata/VERSION.txt.previous")" = \
	"untouched metadata version backup" ] ||
	fail "contending metadata publication modified the active version backup"
[ "$(sed -n '1p' "${TEST_ROOT}/metadata/checksum.txt.previous")" = \
	"untouched metadata checksum backup" ] ||
	fail "contending metadata publication modified the active checksum backup"
"${REAL_RM}" -f "${TEST_ROOT}/metadata/.metadata.publish-in-progress" \
	"${TEST_ROOT}/metadata/VERSION.txt.previous" \
	"${TEST_ROOT}/metadata/checksum.txt.previous"

printf '%s\n' "old version" >"${TEST_ROOT}/metadata/VERSION.txt"
printf '%s\n' "old metadata checksum" >"${TEST_ROOT}/metadata/checksum.txt"
printf '%s\n' "new version" >"${TEST_ROOT}/metadata/VERSION.txt.tmp"
printf '%s\n' "new metadata checksum" >"${TEST_ROOT}/metadata/checksum.txt.tmp"
METADATA_WAS_PUBLISHED=0
mv() {
	case "$1" in
		*/VERSION.txt.tmp)
			if [ -f "${TEST_ROOT}/metadata/VERSION.txt" ] &&
				[ -f "${TEST_ROOT}/metadata/checksum.txt" ] &&
				[ "$(sed -n '1p' "${TEST_ROOT}/metadata/VERSION.txt")" = "old version" ] &&
				[ "$(sed -n '1p' "${TEST_ROOT}/metadata/checksum.txt")" = "old metadata checksum" ]; then
				METADATA_WAS_PUBLISHED=1
			fi
			;;
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
[ "${METADATA_WAS_PUBLISHED}" -eq 1 ] ||
	fail "metadata publication removed previous files before replacement"

unset -f mv
printf '%s\n' "old version" >"${TEST_ROOT}/metadata/VERSION.txt.previous"
printf '%s\n' "old metadata checksum" >"${TEST_ROOT}/metadata/checksum.txt.previous"
printf '%s\n' "new version" >"${TEST_ROOT}/metadata/VERSION.txt"
printf '%s\n' "old metadata checksum" >"${TEST_ROOT}/metadata/checksum.txt"
printf '%s\n' "interrupted" >"${TEST_ROOT}/metadata/.metadata.publish-in-progress"
recover_metadata_publication "${TEST_ROOT}/metadata" >/dev/null 2>&1 ||
	fail "interrupted metadata publication was not recovered"
[ "$(sed -n '1p' "${TEST_ROOT}/metadata/VERSION.txt")" = "old version" ] ||
	fail "interrupted metadata publication did not restore VERSION.txt"
[ "$(sed -n '1p' "${TEST_ROOT}/metadata/checksum.txt")" = "old metadata checksum" ] ||
	fail "interrupted metadata publication did not restore checksum.txt"
[ ! -e "${TEST_ROOT}/metadata/.metadata.publish-in-progress" ] ||
	fail "interrupted metadata publication state was not cleared"

printf '%s\n' "PASS: static archive and metadata publication preserves complete working sets on failure"
