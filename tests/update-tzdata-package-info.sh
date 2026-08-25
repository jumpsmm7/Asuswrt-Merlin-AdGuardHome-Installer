#!/bin/sh

set -eu

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}

if ! REPO_DIR="$(CDPATH= cd -- "$(dirname "${0}")/.." && pwd)"; then
	fail 'Failed to resolve repository directory'
fi
if ! TMP_DIR="$(mktemp -d)"; then
	fail 'Failed to create tzdata test directory'
fi
trap 'rm -rf "${TMP_DIR}"' 0

. "${REPO_DIR}/tools/tzdata-package-info.sh"

mkdir "${TMP_DIR}/plain" "${TMP_DIR}/dotted"
printf '%s\n' 'pkgver = 2026c-1' 'arch = aarch64' >"${TMP_DIR}/plain/.PKGINFO"
cp "${TMP_DIR}/plain/.PKGINFO" "${TMP_DIR}/dotted/.PKGINFO"
tar -cf "${TMP_DIR}/plain.tar" -C "${TMP_DIR}/plain" .PKGINFO
tar -cf "${TMP_DIR}/dotted.tar" -C "${TMP_DIR}/dotted" ./.PKGINFO

for archive in "${TMP_DIR}/plain.tar" "${TMP_DIR}/dotted.tar"; do
	if ! package_info="$(extract_package_info "${archive}")"; then
		fail "Failed to extract package metadata from ${archive}"
	fi
	if ! printf '%s\n' "${package_info}" | grep -q '^pkgver = 2026c-1$'; then
		fail "Failed to extract package metadata from ${archive}"
	fi
done

mkdir -p "${TMP_DIR}/tzdata/usr/share/zoneinfo/Etc" "${TMP_DIR}/tzdata/usr/share/zoneinfo/right/Etc"
printf 'TZif test timezone\n' >"${TMP_DIR}/tzdata/usr/share/zoneinfo/Etc/UTC"
printf 'TZif leap-second timezone\n' >"${TMP_DIR}/tzdata/usr/share/zoneinfo/right/Etc/UTC"
ln -s Etc/UTC "${TMP_DIR}/tzdata/usr/share/zoneinfo/UTC"
printf '%s\n' 'package metadata' >"${TMP_DIR}/tzdata/.PKGINFO"
tar -cjf "${TMP_DIR}/tzdata-without-posix.tar.bz2" -C "${TMP_DIR}/tzdata" .
python3_cmd="${PYTHON3:-python3}"
if ! command -v "${python3_cmd}" >/dev/null 2>&1; then
	fail "Selected Python 3 interpreter is unavailable: ${python3_cmd}"
fi
normalizer="${REPO_DIR}/tools/normalize-tzdata-package.py"
"${python3_cmd}" "${normalizer}" "${TMP_DIR}/tzdata-without-posix.tar.bz2"
if ! tar -xOjf "${TMP_DIR}/tzdata-without-posix.tar.bz2" ./usr/share/zoneinfo/posix/Etc/UTC |
	grep -q '^TZif test timezone$'; then
	fail 'Failed to add the installer-compatible POSIX timezone payload'
fi
if tar -tjf "${TMP_DIR}/tzdata-without-posix.tar.bz2" |
	grep -q '^\./usr/share/zoneinfo/posix/right/'; then
	fail 'Added leap-second-aware timezone data to the POSIX payload'
fi
mkdir "${TMP_DIR}/normalized"
tar -xjf "${TMP_DIR}/tzdata-without-posix.tar.bz2" -C "${TMP_DIR}/normalized" ./usr/share/zoneinfo/posix
if [ -L "${TMP_DIR}/normalized/usr/share/zoneinfo/posix/UTC" ]; then
	fail 'Timezone aliases were not materialized in the POSIX payload'
fi
if [ "$(cat "${TMP_DIR}/normalized/usr/share/zoneinfo/posix/UTC")" != 'TZif test timezone' ]; then
	fail 'Failed to preserve timezone aliases in the POSIX payload'
fi
if ! tar -xOjf "${TMP_DIR}/tzdata-without-posix.tar.bz2" ./.PKGINFO |
	grep -q '^package metadata$'; then
	fail 'Timezone normalization did not preserve package metadata'
fi

cp "${TMP_DIR}/tzdata-without-posix.tar.bz2" "${TMP_DIR}/invalid-suffix.tbz"
if "${python3_cmd}" "${normalizer}" "${TMP_DIR}/invalid-suffix.tbz" >/dev/null 2>&1; then
	fail 'Normalizer accepted a package without the required suffix'
fi
ln -s tzdata-without-posix.tar.bz2 "${TMP_DIR}/linked-package.tar.bz2"
if "${python3_cmd}" "${normalizer}" "${TMP_DIR}/linked-package.tar.bz2" >/dev/null 2>&1; then
	fail 'Normalizer accepted a symbolic-link package path'
fi
"${python3_cmd}" -c '
import io
import sys
import tarfile

with tarfile.open(sys.argv[1], "w:bz2") as package:
	member = tarfile.TarInfo("../escape")
	payload = b"TZif unsafe timezone\n"
	member.size = len(payload)
	package.addfile(member, io.BytesIO(payload))
' "${TMP_DIR}/unsafe-member.tar.bz2"
if "${python3_cmd}" "${normalizer}" "${TMP_DIR}/unsafe-member.tar.bz2" >/dev/null 2>&1; then
	fail 'Normalizer accepted an unsafe archive member path'
fi
[ ! -e "${TMP_DIR}/escape" ] || fail 'Unsafe archive member escaped the test directory'

printf '%s\n' 'not package metadata' >"${TMP_DIR}/README"
printf '%s\n' 'not a tar archive' >"${TMP_DIR}/corrupt.tar"
tar -cf "${TMP_DIR}/missing-metadata.tar" -C "${TMP_DIR}" README

if extract_package_info "${TMP_DIR}/does-not-exist.tar" >/dev/null 2>&1; then
	fail 'Missing archive unexpectedly supplied package metadata'
fi
if extract_package_info "${TMP_DIR}/corrupt.tar" >/dev/null 2>&1; then
	fail 'Corrupt archive unexpectedly supplied package metadata'
fi
if extract_package_info "${TMP_DIR}/missing-metadata.tar" >/dev/null 2>&1; then
	fail 'Archive without .PKGINFO unexpectedly supplied package metadata'
fi

printf '%s\n' 'PASS: update-tzdata package metadata tests passed'
