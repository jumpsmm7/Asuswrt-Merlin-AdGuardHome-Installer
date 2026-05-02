#!/bin/sh
# Validate .md5sum files for router-side installer/service artifacts.
# BusyBox/ash-compatible. Avoids bashisms and command -v for Asuswrt-Merlin ash.

set -u

FAILED=0
TARGETS="installer S99AdGuardHome rc.func.AdGuardHome"

have_cmd() {
	which "$1" >/dev/null 2>&1
}

calc_md5() {
	_file="$1"
	if have_cmd md5sum; then
		md5sum "${_file}" | awk '{print $1; exit}'
	elif have_cmd openssl; then
		openssl dgst -md5 "${_file}" | awk '{print $NF; exit}'
	else
		return 1
	fi
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

if [ "$#" -gt 0 ]; then
	TARGETS="$*"
fi

for target in ${TARGETS}; do
	validate_one "${target}" || true
done

if [ "${FAILED}" -ne 0 ]; then
	exit 1
fi
