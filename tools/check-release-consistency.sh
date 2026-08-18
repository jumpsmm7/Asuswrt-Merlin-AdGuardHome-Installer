#!/bin/sh
# Validate release versions and distributed artifact manifests.
# BusyBox/ash-compatible; Git-only stale-manifest checks are skipped outside a work tree.

set -u

FAILED=0
RELEASE_ROOT="${RELEASE_ROOT:-$(CDPATH= cd "$(dirname "$0")/.." && pwd)}"

fail() {
	printf '%s\n' "Error: $1" >&2
	FAILED=1
}

manifest_value() {
	awk 'NF { value = $1; count++; if (NF != 1) invalid = 1 }
		END { if (count != 1 || invalid) exit 1; print value }' "$1"
}

verify_aggregate() {
	_checksum_file="$1"
	_checksum_dir="${_checksum_file%/*}"
	[ "${_checksum_dir}" != "${_checksum_file}" ] || _checksum_dir=.
	_checksum_lineno=0
	while IFS=' 	' read -r _archive _channel _version _aggregate_md5 _aggregate_sha256 _extra || [ -n "${_archive:-}" ]; do
		_checksum_lineno=$((_checksum_lineno + 1))
		case "${_archive:-}" in
			''|\#*) continue ;;
		esac
		if [ -n "${_extra:-}" ] || [ -z "${_channel:-}" ] || [ -z "${_version:-}" ] ||
			[ -z "${_aggregate_md5:-}" ] || [ -z "${_aggregate_sha256:-}" ]; then
			fail "invalid aggregate checksum entry: ${_checksum_file}:${_checksum_lineno}"
			continue
		fi
		_artifact="${_checksum_dir}/${_archive}"
		if [ ! -f "${_artifact}" ]; then
			fail "aggregate checksum references missing archive: ${_artifact}"
			continue
		fi
		verify_artifact "${_artifact}"
		_expected_md5="$(manifest_value "${_artifact}.md5sum" 2>/dev/null)" || continue
		_expected_sha256="$(manifest_value "${_artifact}.sha256sum" 2>/dev/null)" || continue
		[ "${_aggregate_md5}" = "${_expected_md5}" ] || fail "${_checksum_file}:${_checksum_lineno} has stale MD5 for ${_archive}"
		[ "${_aggregate_sha256}" = "${_expected_sha256}" ] || fail "${_checksum_file}:${_checksum_lineno} has stale SHA-256 for ${_archive}"
	done < "${_checksum_file}"
}

verify_artifact() {
	_artifact="$1"
	_md5_file="${_artifact}.md5sum"
	_sha256_file="${_artifact}.sha256sum"

	for _manifest in "${_md5_file}" "${_sha256_file}"; do
		if [ ! -f "${_manifest}" ]; then
			fail "missing expected manifest: ${_manifest}"
		fi
	done
	[ -f "${_md5_file}" ] && [ -f "${_sha256_file}" ] || return

	_expected_md5="$(manifest_value "${_md5_file}" 2>/dev/null)" || {
		fail "invalid MD5 manifest: ${_md5_file}"
		return
	}
	_expected_sha256="$(manifest_value "${_sha256_file}" 2>/dev/null)" || {
		fail "invalid SHA-256 manifest: ${_sha256_file}"
		return
	}
	_actual_md5="$(md5sum "${_artifact}" 2>/dev/null | awk 'NF { print $1; exit }')" || {
		fail "could not calculate MD5 for ${_artifact}"
		return
	}
	_actual_sha256="$(sha256sum "${_artifact}" 2>/dev/null | awk 'NF { print $1; exit }')" || {
		fail "could not calculate SHA-256 for ${_artifact}"
		return
	}
	[ "${_expected_md5}" = "${_actual_md5}" ] || fail "${_artifact} does not match ${_md5_file}"
	[ "${_expected_sha256}" = "${_actual_sha256}" ] || fail "${_artifact} does not match ${_sha256_file}"

	if [ -n "${RELEASE_BASE_RESOLVED:-}" ] && ! git diff --quiet "${RELEASE_BASE_RESOLVED}" -- "${_artifact}"; then
		for _manifest in "${_md5_file}" "${_sha256_file}"; do
			_old_manifest="$(git show "${RELEASE_BASE_RESOLVED}:${_manifest}" 2>/dev/null || true)"
			_current_manifest="$(cat "${_manifest}")"
			if [ -n "${_old_manifest}" ] && [ "${_old_manifest}" = "${_current_manifest}" ]; then
				fail "changed distributed file has an unchanged stale checksum: ${_manifest}"
			fi
		done
	fi
}

cd "${RELEASE_ROOT}" || exit 1

AI_VERSION="$(awk -F= '/^AI_VERSION="v[0-9][0-9.]*"$/ { gsub(/"/, "", $2); print $2; exit }' installer)"
BANNER_VERSION="$(sed -n 's/^#.* \(v[0-9][0-9.]*\)  *#$/\1/p' installer | head -n 1)"
[ -n "${AI_VERSION}" ] || fail 'installer AI_VERSION is missing or invalid'
[ -n "${BANNER_VERSION}" ] || fail 'installer banner version is missing or invalid'
[ "${AI_VERSION}" = "${BANNER_VERSION}" ] || fail "banner ${BANNER_VERSION:-<missing>} and AI_VERSION ${AI_VERSION:-<missing>} differ"

if grep -q 'v2\.6\.1' installer; then
	fail 'release identifier v2.6.1 remains in installer'
fi

RELEASE_BASE_RESOLVED=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	if git rev-parse --verify "${RELEASE_BASE:-HEAD^}" >/dev/null 2>&1; then
		RELEASE_BASE_RESOLVED="$(git rev-parse --verify "${RELEASE_BASE:-HEAD^}")"
	fi
fi

set -- installer AdGuardHome.sh S99AdGuardHome rc.func.AdGuardHome
for _directory in armv5 armv7 armv8; do
	if [ ! -f "${_directory}/checksum.txt" ]; then
		fail "missing expected aggregate manifest: ${_directory}/checksum.txt"
	else
		verify_aggregate "${_directory}/checksum.txt"
	fi
	for _archive in "${_directory}"/*.tar.gz; do
		[ -f "${_archive}" ] || continue
		set -- "$@" "${_archive}"
	done
done

for _artifact; do
	if [ ! -f "${_artifact}" ]; then
		fail "missing expected distributed file: ${_artifact}"
		continue
	fi
	verify_artifact "${_artifact}"
done

if [ "${FAILED}" -ne 0 ]; then
	exit 1
fi

printf '%s\n' "OK: release ${AI_VERSION} and all distributed manifests are consistent"
