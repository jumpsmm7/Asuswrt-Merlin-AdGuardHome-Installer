#!/bin/sh
# Validate .md5sum files for router-side installer/service artifacts.
# BusyBox/ash-compatible. Uses the firmware-provided which command for discovery.

set -u

FAILED=0

# Functions are sorted alpha-numerically for readability.

calc_md5() {
	_file="$1"
	_output=""
	if have_cmd md5sum; then
		_output="$(md5sum "${_file}")" || return 1
		printf '%s\n' "${_output}" | awk 'NF {print $1; found = 1; exit} END {if (!found) exit 1}'
	elif have_cmd openssl; then
		_output="$(openssl dgst -md5 "${_file}")" || return 1
		printf '%s\n' "${_output}" | awk 'NF {print $NF; found = 1; exit} END {if (!found) exit 1}'
	else
		return 1
	fi
}

have_cmd() {
	which "$1" >/dev/null 2>&1
}

is_md5_hex() {
	_value="$1"
	case "${_value}" in
		????????????????????????????????)
			case "${_value}" in
				*[!0123456789abcdefABCDEF]*) return 1 ;;
				*) return 0 ;;
			esac
			;;
		*) return 1 ;;
	esac
}

validate_one() {
	_src_file="$1"
	_md5_file="${_src_file}.md5sum"

	if [ ! -f "${_src_file}" ]; then
		printf '%s\n' "Skipping missing source: ${_src_file}"
		return 0
	fi

	if [ ! -f "${_md5_file}" ]; then
		printf '%s\n' "Error: missing checksum file: ${_md5_file}" >&2
		FAILED=1
		return 1
	fi

	_expected="$(awk 'NF {print $1; exit}' "${_md5_file}")"
	if ! is_md5_hex "${_expected}"; then
		printf '%s\n' "Error: invalid checksum value in ${_md5_file}: ${_expected}" >&2
		FAILED=1
		return 1
	fi

	_actual="$(calc_md5 "${_src_file}")" || {
		printf '%s\n' 'Error: md5sum or openssl is required.' >&2
		FAILED=1
		return 1
	}

	if ! is_md5_hex "${_actual}"; then
		printf '%s\n' "Error: could not calculate valid checksum for ${_src_file}" >&2
		FAILED=1
		return 1
	fi

	if [ "${_expected}" != "${_actual}" ]; then
		printf '%s\n' "Error: checksum mismatch for ${_src_file}" >&2
		printf '%s\n' "  expected: ${_expected}" >&2
		printf '%s\n' "  actual:   ${_actual}" >&2
		FAILED=1
		return 1
	fi

	printf '%s\n' "OK: ${_md5_file} matches ${_src_file}"
}

if [ "$#" -eq 0 ]; then
	set -- installer AdGuardHome.sh S99AdGuardHome rc.func.AdGuardHome \
		armv5/*.tar.gz armv7/*.tar.gz armv8/*.tar.gz
fi

for target; do
	validate_one "${target}" || true
done

if [ "${FAILED}" -ne 0 ]; then
	exit 1
fi
