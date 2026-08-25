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

mkdir -p "${TMP_DIR}/tzdata/usr/share/zoneinfo/Etc" \
	"${TMP_DIR}/tzdata/usr/share/zoneinfo/posix/Etc"
printf 'TZif test timezone\n' >"${TMP_DIR}/tzdata/usr/share/zoneinfo/Etc/UTC"
printf 'TZif POSIX test timezone\n' >"${TMP_DIR}/tzdata/usr/share/zoneinfo/posix/Etc/UTC"
printf '%s\n' 'package metadata' >"${TMP_DIR}/tzdata/.PKGINFO"
tar -cf "${TMP_DIR}/tzdata.tar" -C "${TMP_DIR}/tzdata" .
xz -c "${TMP_DIR}/tzdata.tar" >"${TMP_DIR}/tzdata.pkg.tar.xz"
xz -d -c "${TMP_DIR}/tzdata.pkg.tar.xz" |
	bzip2 -9 >"${TMP_DIR}/tzdata.pkg.tar.bz2"
bzip2 -d -c "${TMP_DIR}/tzdata.pkg.tar.bz2" >"${TMP_DIR}/recompressed.tar"
if ! cmp "${TMP_DIR}/tzdata.tar" "${TMP_DIR}/recompressed.tar"; then
	fail 'xz-to-bzip2 conversion changed the tar byte stream'
fi

UPDATE_SCRIPT="${REPO_DIR}/tools/update-tzdata.sh"
grep -Fq '*.xz) xz -d -c "${upstream_file}" | bzip2 -9 >"${output_file}" ;;' \
	"${UPDATE_SCRIPT}" || fail 'Update script does not preserve the xz tar stream during recompression'
if grep -Eq '(xz|bzip2) -dc([[:space:]]|$)' "${UPDATE_SCRIPT}" "${0}"; then
	fail 'Combined decompression flags are incompatible with the BusyBox applets'
fi
grep -Fq 'download_package aarch64 aarch64' "${UPDATE_SCRIPT}" ||
	fail 'Update script does not publish the aarch64 package'
grep -Fq 'download_package armv7h arm' "${UPDATE_SCRIPT}" ||
	fail 'Update script does not publish the armv7h package'
if grep -Fq 'normalize-tzdata-package.py' "${UPDATE_SCRIPT}"; then
	fail 'Update script still rewrites tzdata package contents'
fi
grep -Fq 'if not has_posix_timezone:' "${UPDATE_SCRIPT}" ||
	fail 'Update script does not reject packages without a usable POSIX timezone payload'
grep -Fq 'if member.isfile() and normalized_name.startswith("usr/share/zoneinfo/posix/"):' \
	"${UPDATE_SCRIPT}" || fail 'Update script does not require a regular POSIX timezone file'

mkdir -p "${TMP_DIR}/without-posix/usr/share/zoneinfo/Etc"
printf 'TZif test timezone\n' >"${TMP_DIR}/without-posix/usr/share/zoneinfo/Etc/UTC"
tar -cjf "${TMP_DIR}/without-posix.tar.bz2" -C "${TMP_DIR}/without-posix" .
awk 'found && $0 == "PY" { exit } found { print } /^import posixpath$/ { found = 1; print }' \
	"${UPDATE_SCRIPT}" >"${TMP_DIR}/validate-package.py"
python3_cmd="${PYTHON3:-/usr/bin/python3}"
if [ ! -x "${python3_cmd}" ]; then
	fail "Selected Python 3 interpreter is unavailable: ${python3_cmd}"
fi
if "${python3_cmd}" "${TMP_DIR}/validate-package.py" \
	"${TMP_DIR}/without-posix.tar.bz2" >/dev/null 2>&1; then
	fail 'Archive without a POSIX timezone payload unexpectedly passed validation'
fi
if ! "${python3_cmd}" "${TMP_DIR}/validate-package.py" \
	"${TMP_DIR}/tzdata.pkg.tar.bz2"; then
	fail 'Archive with a POSIX timezone payload unexpectedly failed validation'
fi

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

printf '%s\n' 'PASS: update-tzdata package conversion tests passed'
