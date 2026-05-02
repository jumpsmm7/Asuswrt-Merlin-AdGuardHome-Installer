#!/bin/sh
# POSIX/BusyBox ash-compatible helper functions for future installer hardening.
# This file is intentionally standalone so changes can be reviewed before being
# folded into the main installer script.

agh_have_cmd() {
	command -v "$1" >/dev/null 2>&1
}

agh_opkg_installed() {
	# Match the package name exactly in `opkg list-installed` output.
	# Avoids false positives such as matching `apache` inside another package name.
	[ -n "$1" ] || return 1
	opkg list-installed 2>/dev/null | awk -v pkg="$1" '$1 == pkg { found=1; exit } END { exit found ? 0 : 1 }'
}

agh_install_pkg() {
	# Install only when missing. This avoids unnecessary force-reinstall behavior
	# during normal authentication/setup paths.
	[ -n "$1" ] || return 1
	if agh_opkg_installed "$1"; then
		return 0
	fi
	opkg install "$1"
}

agh_mktemp_file() {
	# BusyBox mktemp is not always consistent across environments. Prefer mktemp
	# when available, otherwise fall back to a PID-scoped file with noclobber.
	_prefix="${1:-/tmp/agh}"
	if agh_have_cmd mktemp; then
		mktemp "${_prefix}.XXXXXX" 2>/dev/null && return 0
	fi
	_tmp="${_prefix}.$$"
	(set -C; : >"${_tmp}") 2>/dev/null || return 1
	printf '%s\n' "${_tmp}"
}

agh_hash_password_python3() {
	# Read password from stdin instead of interpolating it into Python source.
	# This avoids breakage with quotes, backslashes, shell metacharacters, and
	# other special characters in passwords.
	python3 -c 'import sys, bcrypt; password = sys.stdin.buffer.read(); print(bcrypt.hashpw(password, bcrypt.gensalt(prefix=b"2a", rounds=10)).decode("ascii"))'
}

agh_download() {
	# Centralized curl/wget fallback helper.
	# Usage: agh_download URL OUTPUT_FILE
	_url="$1"
	_out="$2"
	[ -n "${_url}" ] && [ -n "${_out}" ] || return 1

	if agh_have_cmd curl; then
		curl --retry 5 --connect-timeout 25 --retry-delay 5 --max-time 125 --retry-connrefused -fsSL "${_url}" -o "${_out}" && return 0
	fi

	if agh_have_cmd wget; then
		wget --no-cache --no-cookies --tries=5 --timeout=25 --waitretry=5 -q -O "${_out}" "${_url}" && return 0
	fi

	return 1
}

agh_backup_file_once() {
	# Create a timestamped backup without overwriting earlier diagnostics.
	_file="$1"
	[ -f "${_file}" ] || return 1
	_ts="$(date +%Y%m%d-%H%M%S 2>/dev/null || date +%s)"
	cp -p "${_file}" "${_file}.${_ts}.bak"
}
