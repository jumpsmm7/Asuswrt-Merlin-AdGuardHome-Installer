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

sed -n '/^cleanup_download_tmp() {$/,/^}$/p; /^write_md5sum_file() {$/,/^}$/p; /^write_sha256sum_file() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" ||
	fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTION_FILE}" ] || fail "download cleanup helpers were not found"

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

_archive_file="${TEST_ROOT}/AdGuardHome_stable_linux_arm64.tar.gz"
ACTIVE_DOWNLOAD_TMP="${_archive_file}.tmp.$$"
ACTIVE_DOWNLOAD_MD5_TMP="${_archive_file}.md5sum.tmp.$$"
ACTIVE_DOWNLOAD_SHA256_TMP="${_archive_file}.sha256sum.tmp.$$"
_archive_tmp="${ACTIVE_DOWNLOAD_TMP}"
_md5_tmp="${ACTIVE_DOWNLOAD_MD5_TMP}"
_sha256_tmp="${ACTIVE_DOWNLOAD_SHA256_TMP}"
printf '%s\n' "partial archive" >"${_archive_tmp}" || fail "could not create partial archive"
printf '%s\n' "partial md5" >"${_md5_tmp}" || fail "could not create partial MD5 checksum"
printf '%s\n' "partial sha256" >"${_sha256_tmp}" || fail "could not create partial SHA256 checksum"
grep -F 'ACTIVE_DOWNLOAD_MD5_TMP="${_md5_tmp}"' "${SCRIPT_PATH}" >/dev/null ||
	fail "publisher does not track the MD5 publication temporary"
grep -F 'ACTIVE_DOWNLOAD_SHA256_TMP="${_sha256_tmp}"' "${SCRIPT_PATH}" >/dev/null ||
	fail "publisher does not track the SHA256 publication temporary"
cleanup_download_tmp
for _tracked_tmp in "${_archive_tmp}" "${_md5_tmp}" "${_sha256_tmp}"; do
	[ ! -e "${_tracked_tmp}" ] || fail "download cleanup left tracked temporary ${_tracked_tmp} behind"
done
[ -z "${ACTIVE_DOWNLOAD_TMP}" ] || fail "download cleanup did not clear the tracked archive path"
[ -z "${ACTIVE_DOWNLOAD_MD5_TMP}" ] || fail "download cleanup did not clear the tracked MD5 path"
[ -z "${ACTIVE_DOWNLOAD_SHA256_TMP}" ] || fail "download cleanup did not clear the tracked SHA256 path"

run_interrupted_checksum_writer() {
	_writer="$1"
	_suffix="$2"
	_digest="$3"
	_archive="${TEST_ROOT}/${_writer}.tar.gz"

	if sh -c '
		. "$1"
		ACTIVE_DOWNLOAD_TMP=""
		ACTIVE_DOWNLOAD_MD5_TMP=""
		ACTIVE_DOWNLOAD_SHA256_TMP=""
		ACTIVE_PUBLICATION_ARCHIVE=""
		FAILED=0
		chmod() {
			kill -TERM "$$"
			return 1
		}
		trap "cleanup_download_tmp; exit 97" TERM
		"$2" "$3" "$4"
	' sh "${FUNCTION_FILE}" "${_writer}" "${_archive}" "${_digest}"; then
		fail "${_writer} did not terminate when interrupted"
	fi
	for _writer_tmp in "${_archive}.${_suffix}.tmp."*; do
		[ ! -e "${_writer_tmp}" ] || fail "${_writer} left interrupted temporary ${_writer_tmp} behind"
	done
}

run_interrupted_checksum_writer write_md5sum_file md5sum 0123456789abcdef0123456789abcdef
run_interrupted_checksum_writer write_sha256sum_file sha256sum 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef

grep -F "trap 'cleanup_download_tmp; exit 1' HUP INT QUIT ABRT TERM" "${SCRIPT_PATH}" >/dev/null ||
	fail "download cleanup is not installed for interruption signals"

printf '%s\n' "PASS: interrupted static downloads remove partial archives and checksum publication temporaries"
