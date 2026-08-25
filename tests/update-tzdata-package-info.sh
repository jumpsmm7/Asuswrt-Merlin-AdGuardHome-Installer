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
