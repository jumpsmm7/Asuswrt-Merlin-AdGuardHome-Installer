#!/bin/sh
# Update .md5sum files for router-side installer/service artifacts.
# BusyBox/ash-compatible. Avoids bashisms and command -v for Asuswrt-Merlin ash.

set -u

FAILED=0
UPDATED=0
TARGETS="installer AdGuardHome.sh S99AdGuardHome rc.func.AdGuardHome"

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

update_one() {
	_src_file="$1"
	_md5_file="${_src_file}.md5sum"

	if [ ! -f "${_src_file}" ]; then
		printf '%s\n' "Skipping missing source: ${_src_file}"
		return 0
	fi

	_md5_value="$(calc_md5 "${_src_file}")" || {
		printf '%s\n' 'Error: md5sum or openssl is required.' >&2
		FAILED=1
		return 1
	}

	if ! is_md5_hex "${_md5_value}"; then
		printf '%s\n' "Error: could not calculate valid checksum for ${_src_file}" >&2
		FAILED=1
		return 1
	fi

	_current_value=""
	if [ -f "${_md5_file}" ]; then
		_current_value="$(awk 'NF {print $1; exit}' "${_md5_file}")"
	fi

	if [ "${_current_value}" = "${_md5_value}" ]; then
		printf '%s\n' "OK: ${_md5_file} already current"
		return 0
	fi

	printf '%s\n' "${_md5_value}" >"${_md5_file}" || {
		printf '%s\n' "Error: could not write ${_md5_file}" >&2
		FAILED=1
		return 1
	}
	printf '%s\n' "Updated ${_md5_file}: ${_md5_value}"
	UPDATED="$((UPDATED + 1))"
}

if [ "$#" -gt 0 ]; then
	TARGETS="$*"
fi

for target in ${TARGETS}; do
	update_one "${target}" || true
done

if [ "${FAILED}" -ne 0 ]; then
	exit 1
fi

if [ "${UPDATED}" -eq 0 ]; then
	printf '%s\n' 'No md5sum updates were needed.'
fi
