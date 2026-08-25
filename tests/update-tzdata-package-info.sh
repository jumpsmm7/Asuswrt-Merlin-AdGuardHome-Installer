#!/bin/sh

set -eu

if ! REPO_DIR="$(CDPATH= cd -- "$(dirname "${0}")/.." && pwd)"; then
	printf '%s\n' 'Failed to resolve repository directory' >&2
	exit 1
fi
if ! TMP_DIR="$(mktemp -d)"; then
	printf '%s\n' 'Failed to create tzdata test directory' >&2
	exit 1
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
		printf 'Failed to extract package metadata from %s\n' "${archive}" >&2
		exit 1
	fi
	if ! printf '%s\n' "${package_info}" | grep -q '^pkgver = 2026c-1$'; then
		printf 'Failed to extract package metadata from %s\n' "${archive}" >&2
		exit 1
	fi
done

printf '%s\n' 'update-tzdata package metadata tests passed'
