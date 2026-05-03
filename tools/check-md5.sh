#!/bin/sh
# Validate .md5sum files for router-side installer/service artifacts.
# BusyBox/ash-compatible. Avoids bashisms and command -v for Asuswrt-Merlin ash.

set -u

SCRIPT_DIR="${0%/*}"
if [ "${SCRIPT_DIR}" = "$0" ]; then
	SCRIPT_DIR="."
fi
# shellcheck source=tools/script-helpers.sh
. "${SCRIPT_DIR}/script-helpers.sh"

FAILED=0
TARGETS="installer AdGuardHome.sh S99AdGuardHome rc.func.AdGuardHome"

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

validate_one() {
	_src_file="$1"
	_md5_file="${_src_file}.md5sum"

	if [ ! -f "${_src_file}" ]; then
		log_info "Skipping missing source: ${_src_file}"
		return 0
	fi

	if [ ! -f "${_md5_file}" ]; then
		log_error "missing checksum file: ${_md5_file}"
		FAILED=1
		return 1
	fi

	_expected="$(awk 'NF {print $1; exit}' "${_md5_file}")"
	if ! is_md5_hex "${_expected}"; then
		log_error "invalid checksum value in ${_md5_file}: ${_expected}"
		FAILED=1
		return 1
	fi

	_actual="$(calc_md5 "${_src_file}")" || {
		log_error 'md5sum or openssl is required.'
		FAILED=1
		return 1
	}

	if ! is_md5_hex "${_actual}"; then
		log_error "could not calculate valid checksum for ${_src_file}"
		FAILED=1
		return 1
	fi

	if [ "${_expected}" != "${_actual}" ]; then
		log_error "checksum mismatch for ${_src_file}"
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
