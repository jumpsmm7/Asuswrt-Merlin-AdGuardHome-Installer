#!/bin/sh
# Update .md5sum and .sha256sum files for release artifacts.
# BusyBox/ash-compatible. Uses the firmware-provided which command for discovery.

set -u

FAILED=0
UPDATED=0

# Functions are sorted alpha-numerically for readability.

calc_sum() {
	_sum_cmd="$1"
	_openssl_alg="$2"
	_file="$3"
	_output=""
	if have_cmd "${_sum_cmd}"; then
		_output="$(${_sum_cmd} "${_file}")" || return 1
		printf '%s\n' "${_output}" | awk 'NF {print $1; found = 1; exit} END {if (!found) exit 1}'
	elif have_cmd openssl; then
		_output="$(openssl dgst -"${_openssl_alg}" "${_file}")" || return 1
		printf '%s\n' "${_output}" | awk 'NF {print $NF; found = 1; exit} END {if (!found) exit 1}'
	else
		return 1
	fi
}

have_cmd() {
	which "$1" >/dev/null 2>&1
}

is_hex_len() {
	_value="$1"
	_len="$2"
	case "${_value}" in
		"" | *[!0123456789abcdefABCDEF]*) return 1 ;;
	esac
	[ "${#_value}" -eq "${_len}" ]
}

update_sum_file() {
	_src_file="$1"
	_sum_file="$2"
	_sum_cmd="$3"
	_openssl_alg="$4"
	_hex_len="$5"

	_sum_value="$(calc_sum "${_sum_cmd}" "${_openssl_alg}" "${_src_file}")" || {
		printf '%s\n' "Error: ${_sum_cmd} or openssl is required." >&2
		FAILED=1
		return 1
	}

	if ! is_hex_len "${_sum_value}" "${_hex_len}"; then
		printf '%s\n' "Error: could not calculate valid ${_sum_cmd} checksum for ${_src_file}" >&2
		FAILED=1
		return 1
	fi

	_current_value=""
	if [ -f "${_sum_file}" ]; then
		_current_value="$(awk 'NF {print $1; exit}' "${_sum_file}")"
	fi

	if [ "${_current_value}" = "${_sum_value}" ]; then
		printf '%s\n' "OK: ${_sum_file} already current"
		return 0
	fi

	printf '%s\n' "${_sum_value}" >"${_sum_file}" || {
		printf '%s\n' "Error: could not write ${_sum_file}" >&2
		FAILED=1
		return 1
	}
	printf '%s\n' "Updated ${_sum_file}: ${_sum_value}"
	UPDATED="$((UPDATED + 1))"
}

update_one() {
	_src_file="$1"

	if [ ! -f "${_src_file}" ]; then
		printf '%s\n' "Skipping missing source: ${_src_file}"
		return 0
	fi

	update_sum_file "${_src_file}" "${_src_file}.md5sum" md5sum md5 32 || true
	update_sum_file "${_src_file}" "${_src_file}.sha256sum" sha256sum sha256 64 || true
}

if [ "$#" -eq 0 ]; then
	set -- installer AdGuardHome.sh S99AdGuardHome rc.func.AdGuardHome
fi

for target; do
	update_one "${target}" || true
done

if [ "${FAILED}" -ne 0 ]; then
	exit 1
fi

if [ "${UPDATED}" -eq 0 ]; then
	printf '%s\n' 'No checksum updates were needed.'
fi
