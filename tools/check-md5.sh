#!/bin/sh
# Validate .md5sum files for tracked installer/service script artifacts.
# BusyBox/ash-compatible.

set -u

FAILED=0
TARGETS="installer S99AdGuardHome rc.func.AdGuardHome"

calc_md5() {
	_file="$1"
	if command -v md5sum >/dev/null 2>&1; then
		md5sum "${_file}" | awk '{print $1; exit}'
	elif command -v openssl >/dev/null 2>&1; then
		openssl dgst -md5 "${_file}" | awk '{print $NF; exit}'
	else
		return 1
	fi
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
	_actual="$(calc_md5 "${_src_file}")" || {
		printf '%s\n' 'Error: md5sum or openssl is required.' >&2
		FAILED=1
		return 1
	}

	case "${_expected}" in
	""|*[!0123456789abcdefABCDEF]*|?????????????????????????????????*)
		printf '%s\n' "Error: invalid checksum value in ${_md5_file}: ${_expected}" >&2
		FAILED=1
		return 1
		;;
	esac

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
