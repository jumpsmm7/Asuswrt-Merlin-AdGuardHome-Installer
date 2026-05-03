#!/bin/sh
# Shared POSIX/BusyBox ash-compatible helper functions for local tooling.
# Source this file from helper scripts when common behavior is needed.

log_info() {
	printf '%s\n' "INFO: $*"
}

log_warn() {
	printf '%s\n' "WARN: $*" >&2
}

log_error() {
	printf '%s\n' "ERROR: $*" >&2
}

have_cmd() {
	which "$1" >/dev/null 2>&1
}

normalize_amtm_action() {
	case "$1" in
		amtm*) printf '%s\n' "${1#amtm}" ;;
		*) printf '%s\n' "$1" ;;
	esac
}

mktemp_file() {
	_tmp="$(mktemp)" || return 1
	printf '%s\n' "${_tmp}"
}

safe_remove_file() {
	case "$1" in
		""|"/"|"."|"..")
			log_error "refusing to remove unsafe path: $1"
			return 1
			;;
		*)
			rm -f -- "$1"
			;;
	esac
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
