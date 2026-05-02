#!/bin/sh
# Update one or more .md5sum files from their matching source files.
# BusyBox/ash-compatible.
#
# Usage:
#   sh tools/update-md5.sh                       # update all *.md5sum files found in repo
#   sh tools/update-md5.sh installer.md5sum      # update one checksum file
#
# Mapping rule:
#   path/to/file.md5sum -> path/to/file
#
# File format:
#   checksum only, no filename

set -u

FAILED=0

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
	_md5_file="$1"
	case "${_md5_file}" in
	*.md5sum) ;;
	*)
		printf '%s\n' "Skipping non-md5sum file: ${_md5_file}" >&2
		return 0
		;;
	esac

	_src_file="${_md5_file%.md5sum}"

	if [ ! -f "${_src_file}" ]; then
		printf '%s\n' "Error: source file not found for ${_md5_file}: ${_src_file}" >&2
		FAILED=1
		return 1
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

	printf '%s\n' "${_md5_value}" >"${_md5_file}"
	printf '%s\n' "Updated ${_md5_file}: ${_md5_value}"
}

if [ "$#" -gt 0 ]; then
	for md5_file in "$@"; do
		update_one "${md5_file}" || true
	done
else
	find . -type f -name '*.md5sum' ! -path './.git/*' | sort | while read -r md5_file; do
		update_one "${md5_file#./}" || exit 1
	done || FAILED=1
fi

if [ "${FAILED}" -ne 0 ]; then
	exit 1
fi
