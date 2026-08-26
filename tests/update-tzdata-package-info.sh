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

for required_command in /usr/bin/xz bzip2 cmp zstd; do
	if ! which "${required_command}" >/dev/null 2>&1; then
		fail "Required validation-host command is unavailable: ${required_command}"
	fi
done

mkdir "${TMP_DIR}/plain" "${TMP_DIR}/dotted"
printf '%s\n' 'pkgver = 2026c-1' 'arch = aarch64' >"${TMP_DIR}/plain/.PKGINFO"
cp "${TMP_DIR}/plain/.PKGINFO" "${TMP_DIR}/dotted/.PKGINFO"
tar -cf "${TMP_DIR}/plain.tar" -C "${TMP_DIR}/plain" .PKGINFO
tar -cf "${TMP_DIR}/dotted.tar" -C "${TMP_DIR}/dotted" ./.PKGINFO
for archive in "${TMP_DIR}/plain.tar" "${TMP_DIR}/dotted.tar"; do
	if ! package_info="$(extract_package_info "${archive}")" ||
		! printf '%s\n' "${package_info}" | grep -q '^pkgver = 2026c-1$'; then
		fail "Failed to extract package metadata from ${archive}"
	fi
done

mkdir -p "${TMP_DIR}/tzdata/usr/share/zoneinfo/Etc" \
	"${TMP_DIR}/tzdata/usr/share/zoneinfo/posix"
printf 'TZif external timezone payload\n' >"${TMP_DIR}/tzdata/usr/share/zoneinfo/Etc/UTC"
ln -s ../Etc/UTC "${TMP_DIR}/tzdata/usr/share/zoneinfo/posix/UTC"
printf '%s\n' 'package metadata' >"${TMP_DIR}/tzdata/.PKGINFO"
tar -cf "${TMP_DIR}/tzdata.tar" -C "${TMP_DIR}/tzdata" .

UPDATE_SCRIPT="${REPO_DIR}/tools/update-tzdata.sh"
if grep -Fq 'normalize-tzdata-package.py' "${UPDATE_SCRIPT}" ||
	grep -Fq 'import tarfile' "${UPDATE_SCRIPT}"; then
	fail 'Update script still inspects or rewrites tzdata package members'
fi
grep -Fq '*.xz) recompress_xz_package "${upstream_file}" "${output_file}" ;;' \
	"${UPDATE_SCRIPT}" || fail 'Update script does not use checked XZ recompression'
grep -Fq '*.zst) recompress_zst_package "${upstream_file}" "${output_file}" ;;' \
	"${UPDATE_SCRIPT}" || fail 'Update script does not use checked Zstandard recompression'
if grep -Eq '(xz|bzip2) -dc([[:space:]]|$)' "${UPDATE_SCRIPT}" "${0}"; then
	fail 'Combined decompression flags are incompatible with BusyBox applets'
fi
awk 'found { print } /^recompress_xz_package\(\) \{/ { found = 1; print } found && /^}/ { exit }' \
	"${UPDATE_SCRIPT}" >"${TMP_DIR}/recompress-functions.sh"
awk 'found { print } /^recompress_zst_package\(\) \{/ { found = 1; print } found && /^}/ { exit }' \
	"${UPDATE_SCRIPT}" >>"${TMP_DIR}/recompress-functions.sh"
. "${TMP_DIR}/recompress-functions.sh"

# Fixture compression is validation-host-only; conversion itself preserves the tar stream.
/usr/bin/xz -c "${TMP_DIR}/tzdata.tar" >"${TMP_DIR}/tzdata.pkg.tar.xz"
recompress_xz_package "${TMP_DIR}/tzdata.pkg.tar.xz" "${TMP_DIR}/from-xz.pkg.tar.bz2"
bzip2 -d -c "${TMP_DIR}/from-xz.pkg.tar.bz2" >"${TMP_DIR}/from-xz.tar"
if ! cmp "${TMP_DIR}/tzdata.tar" "${TMP_DIR}/from-xz.tar"; then
	fail 'XZ-to-bzip2 conversion changed the internal tar byte stream'
fi

cp "${TMP_DIR}/tzdata.pkg.tar.xz" "${TMP_DIR}/malformed.pkg.tar.xz"
printf '\3757zXZ\000' >>"${TMP_DIR}/malformed.pkg.tar.xz"
if recompress_xz_package "${TMP_DIR}/malformed.pkg.tar.xz" \
	"${TMP_DIR}/malformed.pkg.tar.bz2" >/dev/null 2>&1; then
	fail 'Malformed trailing XZ data unexpectedly passed recompression'
fi
if [ -e "${TMP_DIR}/malformed.pkg.tar.bz2" ] ||
	[ -e "${TMP_DIR}/malformed.pkg.tar.bz2.tar" ]; then
	fail 'Failed XZ recompression left conversion files behind'
fi

zstd --quiet --stdout "${TMP_DIR}/tzdata.tar" >"${TMP_DIR}/tzdata.pkg.tar.zst"
recompress_zst_package "${TMP_DIR}/tzdata.pkg.tar.zst" "${TMP_DIR}/from-zst.pkg.tar.bz2"
bzip2 -d -c "${TMP_DIR}/from-zst.pkg.tar.bz2" >"${TMP_DIR}/from-zst.tar"
if ! cmp "${TMP_DIR}/tzdata.tar" "${TMP_DIR}/from-zst.tar"; then
	fail 'Zstandard-to-bzip2 conversion changed the internal tar byte stream'
fi
printf '%s\n' 'not a zstd stream' >"${TMP_DIR}/malformed.pkg.tar.zst"
if recompress_zst_package "${TMP_DIR}/malformed.pkg.tar.zst" \
	"${TMP_DIR}/malformed-zst.pkg.tar.bz2" >/dev/null 2>&1; then
	fail 'Malformed Zstandard data unexpectedly passed recompression'
fi
if [ -e "${TMP_DIR}/malformed-zst.pkg.tar.bz2" ] ||
	[ -e "${TMP_DIR}/malformed-zst.pkg.tar.bz2.tar" ]; then
	fail 'Failed Zstandard recompression left conversion files behind'
fi

grep -Fq 'download_package aarch64 aarch64' "${UPDATE_SCRIPT}" ||
	fail 'Update script does not publish the aarch64 package'
grep -Fq 'download_package armv7h arm' "${UPDATE_SCRIPT}" ||
	fail 'Update script does not publish the armv7h package'
grep -Fq '*) TZ_ZONEINFO_DIR="usr/share/zoneinfo" ;;' "${REPO_DIR}/installer" ||
	fail 'Installer does not extract link targets from the complete zoneinfo subtree'

awk 'found { print } /^filter_timezone_members\(\) \{/ { found = 1; print } found && /^}/ { exit }' \
	"${REPO_DIR}/installer" >"${TMP_DIR}/installer-timezone.sh"
awk 'found { print } /^format_timezone_menu\(\) \{/ { found = 1; print } found && /^}/ { exit }' \
	"${REPO_DIR}/installer" >>"${TMP_DIR}/installer-timezone.sh"
awk 'found { print } /^set_timezone\(\) \{/ { found = 1; print } found && /^}/ { exit }' \
	"${REPO_DIR}/installer" |
	sed 's|TMP="/root"|TMP="${TEST_ROOT}"|; s|/opt/bin/column|${COLUMN_CMD}|g' \
	>>"${TMP_DIR}/installer-timezone.sh"
. "${TMP_DIR}/installer-timezone.sh"
TEST_ROOT="${TMP_DIR}/installer"
ADDON_DIR="${TEST_ROOT}/addon"
COLUMN_CMD="${TEST_ROOT}/column"
RURL='fixture:'
ERROR='ERROR:'
INFO='INFO:'
CHOSEN=''
mkdir -p "${ADDON_DIR}"
printf '%s\n' '#!/bin/sh' 'cat' >"${COLUMN_CMD}"
chmod 755 "${COLUMN_CMD}"
cp "${TMP_DIR}/from-xz.pkg.tar.bz2" "${TEST_ROOT}/tzdata-2026c-1-aarch64.pkg.tar.bz2.fixture"
printf '%s\n' 'must remain unchanged' >"${TEST_ROOT}/outside-localtime"
ln -s "${TEST_ROOT}/outside-localtime" "${ADDON_DIR}/localtime"
ensure_opkg_package() { return 0; }
ai_have_cmd() { return 0; }
PTXT() { printf '%s\n' "$1"; }
uname() { printf '%s\n' 'aarch64'; }
download_file() {
	cp "${TEST_ROOT}/tzdata-2026c-1-aarch64.pkg.tar.bz2.fixture" "$1/tzdata-2026c-1-aarch64.pkg.tar.bz2"
}
read_input_num() { CHOSEN=1; }
if ! set_timezone >/dev/null; then
	fail 'Installer failed to install a timezone alias whose target is outside posix/'
fi
if [ -L "${ADDON_DIR}/localtime" ] || [ ! -f "${ADDON_DIR}/localtime" ] ||
	[ "$(cat "${ADDON_DIR}/localtime")" != 'TZif external timezone payload' ]; then
	fail 'Installer did not atomically install the dereferenced timezone payload'
fi
if [ "$(cat "${TEST_ROOT}/outside-localtime")" != 'must remain unchanged' ]; then
	fail 'Installer followed the previous localtime destination alias'
fi
if find "${ADDON_DIR}" -name '.localtime.*' -print | grep -q .; then
	fail 'Installer left a localtime staging file after successful replacement'
fi

printf '%s\n' 'not package metadata' >"${TMP_DIR}/README"
printf '%s\n' 'not a tar archive' >"${TMP_DIR}/corrupt.tar"
tar -cf "${TMP_DIR}/missing-metadata.tar" -C "${TMP_DIR}" README
if extract_package_info "${TMP_DIR}/does-not-exist.tar" >/dev/null 2>&1 ||
	extract_package_info "${TMP_DIR}/corrupt.tar" >/dev/null 2>&1 ||
	extract_package_info "${TMP_DIR}/missing-metadata.tar" >/dev/null 2>&1; then
	fail 'Invalid archive unexpectedly supplied package metadata'
fi

printf '%s\n' 'PASS: tzdata compression-only conversion tests passed'
