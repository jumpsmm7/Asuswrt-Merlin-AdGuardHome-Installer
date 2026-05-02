#!/bin/sh
# Update .md5sum files for changed source files.
# BusyBox/ash-compatible, intended for local use before committing.
#
# Mapping rule:
#   file        -> file.md5sum
#   path/file   -> path/file.md5sum
#
# File format:
#   checksum only, no filename
#
# Examples:
#   sh tools/update-changed-md5.sh
#   sh tools/update-changed-md5.sh --staged
#   sh tools/update-changed-md5.sh --all
#   sh tools/update-changed-md5.sh installer

set -u

MODE="changed"
FAILED=0
UPDATED=0
SEEN_FILES=""

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

already_seen() {
	_case_file="$1"
	case "
${SEEN_FILES}
" in
	*"
${_case_file}
"*) return 0 ;;
	*) return 1 ;;
	esac
}

mark_seen() {
	SEEN_FILES="${SEEN_FILES}
$1"
}

update_for_source() {
	_src_file="$1"

	case "${_src_file}" in
	*.md5sum|.git/*|*/.git/*) return 0 ;;
	esac

	[ -n "${_src_file}" ] || return 0
	[ -f "${_src_file}" ] || return 0

	_md5_file="${_src_file}.md5sum"
	[ -f "${_md5_file}" ] || return 0

	if already_seen "${_md5_file}"; then
		return 0
	fi
	mark_seen "${_md5_file}"

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
	UPDATED="$((UPDATED + 1))"
}

process_git_changed_files() {
	case "${MODE}" in
	staged)
		git diff --cached --name-only --diff-filter=ACMR
		;;
	all)
		{
			git diff --name-only --diff-filter=ACMR
			git diff --cached --name-only --diff-filter=ACMR
			git ls-files --others --exclude-standard
		} | sort -u
		;;
	changed|*)
		{
			git diff --name-only --diff-filter=ACMR
			git diff --cached --name-only --diff-filter=ACMR
		} | sort -u
		;;
	esac
}

if [ "$#" -gt 0 ]; then
	case "$1" in
	--staged)
		MODE="staged"
		shift
		;;
	--all)
		MODE="all"
		shift
		;;
	--changed)
		MODE="changed"
		shift
		;;
	--help|-h)
		printf '%s\n' \
			'Usage:' \
			'  sh tools/update-changed-md5.sh [--changed|--staged|--all]' \
			'  sh tools/update-changed-md5.sh FILE [FILE ...]' \
			'' \
			'Updates FILE.md5sum when FILE changed and FILE.md5sum exists.'
		exit 0
		;;
	esac
fi

if [ "$#" -gt 0 ]; then
	for src_file in "$@"; do
		update_for_source "${src_file}" || true
	done
else
	if ! command -v git >/dev/null 2>&1 || ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		printf '%s\n' 'Error: git repository not detected. Pass files explicitly instead.' >&2
		exit 1
	fi

	process_git_changed_files | while read -r src_file; do
		update_for_source "${src_file}" || exit 1
	done || FAILED=1
fi

if [ "${FAILED}" -ne 0 ]; then
	exit 1
fi

if [ "${UPDATED}" -eq 0 ]; then
	printf '%s\n' 'No matching changed .md5sum files needed updates.'
fi
