#!/bin/sh
# Update .md5sum files for installer/service script artifacts.
# BusyBox/ash-compatible.

set -u

FAILED=0
UPDATED=0
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

	if [ -z "${_md5_value}" ]; then
		printf '%s\n' "Error: could not calculate checksum for ${_src_file}" >&2
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

	printf '%s\n' "${_md5_value}" >"${_md5_file}"
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
