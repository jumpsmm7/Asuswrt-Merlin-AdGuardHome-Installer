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
# BusyBox provides only the xz decompressor; fixture creation is host-only.
/usr/bin/xz -c "${TMP_DIR}/tzdata.tar" >"${TMP_DIR}/tzdata.pkg.tar.xz"
xz -d -c "${TMP_DIR}/tzdata.pkg.tar.xz" |
	bzip2 -9 >"${TMP_DIR}/tzdata.pkg.tar.bz2"
bzip2 -d -c "${TMP_DIR}/tzdata.pkg.tar.bz2" >"${TMP_DIR}/recompressed.tar"
if ! cmp "${TMP_DIR}/tzdata.tar" "${TMP_DIR}/recompressed.tar"; then
	fail 'xz-to-bzip2 conversion changed the tar byte stream'
fi

UPDATE_SCRIPT="${REPO_DIR}/tools/update-tzdata.sh"
grep -Fq '*.xz) recompress_xz_package "${upstream_file}" "${output_file}" ;;' \
	"${UPDATE_SCRIPT}" || fail 'Update script does not verify xz decompression before recompression'
if grep -Eq '(xz|bzip2) -dc([[:space:]]|$)' "${UPDATE_SCRIPT}" "${0}"; then
	fail 'Combined decompression flags are incompatible with the BusyBox applets'
fi
awk 'found { print } /^recompress_xz_package\(\) \{/ { found = 1; print } found && /^}/ { exit }' \
	"${UPDATE_SCRIPT}" >"${TMP_DIR}/recompress-xz-package.sh"
. "${TMP_DIR}/recompress-xz-package.sh"
cp "${TMP_DIR}/tzdata.pkg.tar.xz" "${TMP_DIR}/malformed.pkg.tar.xz"
printf '\3757zXZ\000' >>"${TMP_DIR}/malformed.pkg.tar.xz"
printf '%s\n' 'stale output' >"${TMP_DIR}/malformed.pkg.tar.bz2"
printf '%s\n' 'stale temporary stream' >"${TMP_DIR}/malformed.pkg.tar.bz2.tar"
if recompress_xz_package "${TMP_DIR}/malformed.pkg.tar.xz" \
	"${TMP_DIR}/malformed.pkg.tar.bz2" >/dev/null 2>&1; then
	fail 'Malformed trailing XZ data unexpectedly passed recompression'
fi
if [ -e "${TMP_DIR}/malformed.pkg.tar.bz2" ] || \
	[ -e "${TMP_DIR}/malformed.pkg.tar.bz2.tar" ]; then
	fail 'Failed XZ decompression left conversion files behind'
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
mkdir -p "${TMP_DIR}/symlink-posix/usr/share/zoneinfo/posix"
ln -s Etc/UTC "${TMP_DIR}/symlink-posix/usr/share/zoneinfo/posix/UTC"
tar -cjf "${TMP_DIR}/symlink-posix.tar.bz2" -C "${TMP_DIR}/symlink-posix" .
if "${python3_cmd}" "${TMP_DIR}/validate-package.py" \
	"${TMP_DIR}/symlink-posix.tar.bz2" >/dev/null 2>&1; then
	fail 'Archive with only a safe POSIX timezone symbolic link unexpectedly passed validation'
fi
mkdir -p "${TMP_DIR}/alias-posix/usr/share/zoneinfo/posix/Etc"
printf 'TZif POSIX test timezone\n' >"${TMP_DIR}/alias-posix/usr/share/zoneinfo/posix/Etc/UTC"
ln -s Etc/UTC "${TMP_DIR}/alias-posix/usr/share/zoneinfo/posix/UTC"
tar -cjf "${TMP_DIR}/alias-posix.tar.bz2" -C "${TMP_DIR}/alias-posix" .
if "${python3_cmd}" "${TMP_DIR}/validate-package.py" \
	"${TMP_DIR}/alias-posix.tar.bz2" >/dev/null 2>&1; then
	fail 'Archive with a selectable POSIX timezone alias unexpectedly passed validation'
fi
mkdir -p "${TMP_DIR}/empty-posix/usr/share/zoneinfo/posix/Etc"
: >"${TMP_DIR}/empty-posix/usr/share/zoneinfo/posix/Etc/UTC"
tar -cjf "${TMP_DIR}/empty-posix.tar.bz2" -C "${TMP_DIR}/empty-posix" .
if "${python3_cmd}" "${TMP_DIR}/validate-package.py" \
	"${TMP_DIR}/empty-posix.tar.bz2" >/dev/null 2>&1; then
	fail 'Archive with only an empty POSIX timezone file unexpectedly passed validation'
fi
mkdir -p "${TMP_DIR}/invalid-posix/usr/share/zoneinfo/posix/Etc"
printf 'not timezone data\n' >"${TMP_DIR}/invalid-posix/usr/share/zoneinfo/posix/Etc/UTC"
tar -cjf "${TMP_DIR}/invalid-posix.tar.bz2" -C "${TMP_DIR}/invalid-posix" .
if "${python3_cmd}" "${TMP_DIR}/validate-package.py" \
	"${TMP_DIR}/invalid-posix.tar.bz2" >/dev/null 2>&1; then
	fail 'Archive with invalid POSIX timezone data unexpectedly passed validation'
fi
if ! "${python3_cmd}" "${TMP_DIR}/validate-package.py" \
	"${TMP_DIR}/tzdata.pkg.tar.bz2"; then
	fail 'Archive with a POSIX timezone payload unexpectedly failed validation'
fi
"${python3_cmd}" - "${TMP_DIR}/unsafe-hard-link.tar.bz2" <<'PY'
import io
import sys
import tarfile

with tarfile.open(sys.argv[1], "w:bz2") as package:
    timezone = tarfile.TarInfo("./usr/share/zoneinfo/posix/Etc/UTC")
    payload = b"TZif POSIX test timezone\n"
    timezone.size = len(payload)
    package.addfile(timezone, io.BytesIO(payload))

    hard_link = tarfile.TarInfo("./usr/share/zoneinfo/posix/Etc/Unsafe")
    hard_link.type = tarfile.LNKTYPE
    hard_link.linkname = "../../etc/passwd"
    package.addfile(hard_link)
PY
if "${python3_cmd}" "${TMP_DIR}/validate-package.py" \
	"${TMP_DIR}/unsafe-hard-link.tar.bz2" >/dev/null 2>&1; then
	fail 'Archive with an archive-root-traversing hard link unexpectedly passed validation'
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
