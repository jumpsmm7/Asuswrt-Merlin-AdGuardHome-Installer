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

verify_artifact() {
	_artifact="$1"
	_metadata_md5="${2:-}"
	_metadata_sha256="${3:-}"
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
	_actual_md5="$(md5sum "${_artifact}" 2>/dev/null | awk 'NF { print $1; exit }')"
	if [ -z "${_actual_md5}" ]; then
		fail "could not calculate MD5 for ${_artifact}"
		return
	fi
	_actual_sha256="$(sha256sum "${_artifact}" 2>/dev/null | awk 'NF { print $1; exit }')"
	if [ -z "${_actual_sha256}" ]; then
		fail "could not calculate SHA-256 for ${_artifact}"
		return
	fi
	[ "${_expected_md5}" = "${_actual_md5}" ] || fail "${_artifact} does not match ${_md5_file}"
	[ "${_expected_sha256}" = "${_actual_sha256}" ] || fail "${_artifact} does not match ${_sha256_file}"
	[ -z "${_metadata_md5}" ] || [ "${_metadata_md5}" = "${_actual_md5}" ] || fail "${_artifact} MD5 does not match architecture checksum.txt"
	[ -z "${_metadata_sha256}" ] || [ "${_metadata_sha256}" = "${_actual_sha256}" ] || fail "${_artifact} SHA-256 does not match architecture checksum.txt"

	_base_blob=""
	_current_blob=""
	if [ -n "${RELEASE_BASE_RESOLVED:-}" ]; then
		_base_blob="$(git rev-parse "${RELEASE_BASE_RESOLVED}:${_artifact}" 2>/dev/null || true)"
		_current_blob="$(git hash-object "${_artifact}" 2>/dev/null || true)"
	fi
	if [ -n "${_base_blob}" ] && [ -n "${_current_blob}" ] && [ "${_base_blob}" != "${_current_blob}" ]; then
		for _manifest in "${_md5_file}" "${_sha256_file}"; do
			_old_manifest="$(git show "${RELEASE_BASE_RESOLVED}:${_manifest}" 2>/dev/null || true)"
			_current_manifest="$(cat "${_manifest}")"
			if [ -n "${_old_manifest}" ] && [ "${_old_manifest}" = "${_current_manifest}" ]; then
				fail "changed distributed file has an unchanged stale checksum: ${_manifest}"
			fi
		done
	fi
}

verify_architecture_metadata() {
	_directory="$1"
	_channel_file="${_directory}/checksum.txt"
	_seen_channels=""
	case "${_directory}" in
		armv5) _archive_arch='armv5' ;;
		armv7) _archive_arch='armv7' ;;
		armv8) _archive_arch='arm64' ;;
		*)
			fail "unsupported architecture directory: ${_directory}"
			return
			;;
	esac

	if [ ! -f "${_channel_file}" ]; then
		fail "missing expected channel manifest: ${_channel_file}"
		return
	fi

	while read -r _file _channel _version _md5 _sha256 _extra; do
		case "${_file}" in
			'' | \#*) continue ;;
		esac
		if [ -n "${_extra:-}" ]; then
			fail "malformed channel manifest entry in ${_channel_file}: ${_file}"
			continue
		fi
		case "${_file}" in
			*/* | .* | *[!A-Za-z0-9._+=-]*)
				fail "invalid archive name in ${_channel_file}: ${_file}"
				continue
				;;
			*.tar.gz) ;;
			*)
				fail "invalid archive name in ${_channel_file}: ${_file}"
				continue
				;;
		esac
		case "${_channel}" in
			stable | beta | edge) ;;
			*)
				fail "invalid channel in ${_channel_file}: ${_channel:-<missing>}"
				continue
				;;
		esac
		_expected_file="AdGuardHome_${_channel}_linux_${_archive_arch}.tar.gz"
		if [ "${_file}" != "${_expected_file}" ]; then
			fail "archive name mismatch in ${_channel_file}: expected ${_expected_file}, advertised ${_file}"
			continue
		fi
		case " ${_seen_channels} " in
			*" ${_channel} "*)
				fail "duplicate ${_channel} channel in ${_channel_file}"
				continue
				;;
		esac
		_seen_channels="${_seen_channels}${_seen_channels:+ }${_channel}"
		case "${_version}" in
			version=?*) ;;
			*)
				fail "invalid version in ${_channel_file} for ${_file}"
				continue
				;;
		esac
		_version="${_version#version=}"
		case "${_channel}" in
			stable)
				if [ -z "${EXPECTED_STABLE_VERSION}" ]; then
					EXPECTED_STABLE_VERSION="${_version}"
				elif [ "${EXPECTED_STABLE_VERSION}" != "${_version}" ]; then
					fail "stable channel version differs in ${_channel_file}: expected ${EXPECTED_STABLE_VERSION}, actual ${_version}"
				fi
				;;
			beta)
				if [ -z "${EXPECTED_BETA_VERSION}" ]; then
					EXPECTED_BETA_VERSION="${_version}"
				elif [ "${EXPECTED_BETA_VERSION}" != "${_version}" ]; then
					fail "beta channel version differs in ${_channel_file}: expected ${EXPECTED_BETA_VERSION}, actual ${_version}"
				fi
				;;
			edge)
				if [ -z "${EXPECTED_EDGE_VERSION}" ]; then
					EXPECTED_EDGE_VERSION="${_version}"
				elif [ "${EXPECTED_EDGE_VERSION}" != "${_version}" ]; then
					fail "edge channel version differs in ${_channel_file}: expected ${EXPECTED_EDGE_VERSION}, actual ${_version}"
				fi
				;;
		esac
		case "${_md5}" in
			????????????????????????????????) ;;
			*)
				fail "invalid MD5 in ${_channel_file} for ${_file}"
				continue
				;;
		esac
		case "${_md5}" in *[!0123456789abcdefABCDEF]*)
			fail "invalid MD5 in ${_channel_file} for ${_file}"
			continue
			;;
		esac
		case "${_sha256}" in
			????????????????????????????????????????????????????????????????) ;;
			*)
				fail "invalid SHA-256 in ${_channel_file} for ${_file}"
				continue
				;;
		esac
		case "${_sha256}" in *[!0123456789abcdefABCDEF]*)
			fail "invalid SHA-256 in ${_channel_file} for ${_file}"
			continue
			;;
		esac

		_artifact="${_directory}/${_file}"
		if [ ! -f "${_artifact}" ]; then
			fail "channel manifest references missing archive: ${_artifact}"
			continue
		fi
		verify_artifact "${_artifact}" "${_md5}" "${_sha256}"
	done <"${_channel_file}"

	for _required_channel in stable beta edge; do
		case " ${_seen_channels} " in
			*" ${_required_channel} "*) ;;
			*) fail "missing ${_required_channel} channel in ${_channel_file}" ;;
		esac
	done

	# Intentional glob expansion enumerates archives so unadvertised files cannot bypass validation.
	for _archive in "${_directory}"/*.tar.gz; do
		[ -f "${_archive}" ] || continue
		_archive_name="${_archive##*/}"
		awk -v archive="${_archive_name}" '$1 == archive && $1 !~ /^#/ { found = 1 } END { exit !found }' "${_channel_file}" ||
			fail "archive is not advertised by ${_channel_file}: ${_archive}"
	done
}

cd "${RELEASE_ROOT}" || exit 1

AI_VERSION="$(awk -F= '/^AI_VERSION="v[0-9]{1,2}(\.[0-9]{1,2}){2}"$/ { gsub(/"/, "", $2); print $2; exit }' installer)"
BANNER_VERSION="$(awk '{ for (field = 1; field <= NF; field++) if ($field ~ /^v[0-9]{1,2}(\.[0-9]{1,2}){2}$/) { print $field; exit } }' installer)"
[ -n "${AI_VERSION}" ] || fail 'installer AI_VERSION is missing or invalid'
[ -n "${BANNER_VERSION}" ] || fail 'installer banner version is missing or invalid'
[ "${AI_VERSION}" = "${BANNER_VERSION}" ] || fail "banner ${BANNER_VERSION:-<missing>} and AI_VERSION ${AI_VERSION:-<missing>} differ"

STALE_RELEASE_VERSION="${AI_VERSION%.*}.1"
STALE_RELEASE_PATTERN="$(printf '%s\n' "${STALE_RELEASE_VERSION}" | sed 's/\./\\./g')"
if [ "${STALE_RELEASE_VERSION}" != "${AI_VERSION}" ] && grep -q "${STALE_RELEASE_PATTERN}\\([^0-9]\\|$\\)" installer; then
	fail "release identifier ${STALE_RELEASE_VERSION} remains in installer"
fi

RELEASE_BASE_RESOLVED=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	if git rev-parse --verify "${RELEASE_BASE:-HEAD^}" >/dev/null 2>&1; then
		RELEASE_BASE_RESOLVED="$(git rev-parse --verify "${RELEASE_BASE:-HEAD^}")"
	fi
fi

set -- installer AdGuardHome.sh S99AdGuardHome rc.func.AdGuardHome
EXPECTED_STABLE_VERSION=""
EXPECTED_BETA_VERSION=""
EXPECTED_EDGE_VERSION=""
for _directory in armv5 armv7 armv8; do
	verify_architecture_metadata "${_directory}"
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
