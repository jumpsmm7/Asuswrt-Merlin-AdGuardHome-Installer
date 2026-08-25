#!/bin/sh

set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname "${0}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' 0

extract_function="$({
	awk '
		/^extract_package_info\(\) \{/ { copying = 1 }
		copying { print }
		copying && /^}/ { exit }
	' "${REPO_DIR}/tools/update-tzdata.sh"
})"
if [ -z "${extract_function}" ]; then
	printf '%s\n' 'extract_package_info function not found' >&2
	exit 1
fi
eval "${extract_function}"

mkdir "${TMP_DIR}/plain" "${TMP_DIR}/dotted"
printf '%s\n' 'pkgver = 2026c-1' 'arch = aarch64' >"${TMP_DIR}/plain/.PKGINFO"
cp "${TMP_DIR}/plain/.PKGINFO" "${TMP_DIR}/dotted/.PKGINFO"
tar -cf "${TMP_DIR}/plain.tar" -C "${TMP_DIR}/plain" .PKGINFO
tar -cf "${TMP_DIR}/dotted.tar" -C "${TMP_DIR}/dotted" ./.PKGINFO

for archive in "${TMP_DIR}/plain.tar" "${TMP_DIR}/dotted.tar"; do
	package_info="$(extract_package_info "${archive}")"
	if ! printf '%s\n' "${package_info}" | grep -q '^pkgver = 2026c-1$'; then
		printf 'Failed to extract package metadata from %s\n' "${archive}" >&2
		exit 1
	fi
done

printf '%s\n' 'update-tzdata package metadata tests passed'
