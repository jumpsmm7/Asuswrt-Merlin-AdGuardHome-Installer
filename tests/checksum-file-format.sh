#!/bin/sh
# Verify checksum generators emit digest-only files and validators reject a second field.

set -u

fail() {
	printf '%s\n' "FAIL: $1" >&2
	exit 1
}

TMP_ROOT=$(mktemp -d) || fail 'unable to create temporary workspace'
trap 'rm -rf "${TMP_ROOT}"' EXIT
trap 'rm -rf "${TMP_ROOT}"; exit 1' HUP INT TERM

TARGET="${TMP_ROOT}/artifact"
printf '%s\n' 'checksum format fixture' >"${TARGET}" || fail 'unable to create checksum fixture'

MD5=$(md5sum "${TARGET}" | awk 'NF { print $1; exit }') || fail 'unable to calculate fixture MD5'
SHA256=$(sha256sum "${TARGET}" | awk 'NF { print $1; exit }') || fail 'unable to calculate fixture SHA-256'
printf '%s  %s\n' "${MD5}" "${TARGET}" >"${TARGET}.md5sum"
printf '%s  %s\n' "${SHA256}" "${TARGET}" >"${TARGET}.sha256sum"

if sh tools/check-md5.sh "${TARGET}" >/dev/null 2>&1; then
	fail 'MD5 validator accepted a checksum filename as a second field'
fi
if sh tools/check-sha256.sh "${TARGET}" >/dev/null 2>&1; then
	fail 'SHA-256 validator accepted a checksum filename as a second field'
fi

sh tools/update-checksums.sh "${TARGET}" >/dev/null || fail 'checksum updater failed'
[ "$(cat "${TARGET}.md5sum")" = "${MD5}" ] || fail 'checksum updater did not normalize MD5 to one value'
[ "$(cat "${TARGET}.sha256sum")" = "${SHA256}" ] || fail 'checksum updater did not normalize SHA-256 to one value'
sh tools/check-md5.sh "${TARGET}" >/dev/null || fail 'MD5 validator rejected normalized output'
sh tools/check-sha256.sh "${TARGET}" >/dev/null || fail 'SHA-256 validator rejected normalized output'

printf '%s\n' 'PASS: checksum files contain exactly one digest value'
