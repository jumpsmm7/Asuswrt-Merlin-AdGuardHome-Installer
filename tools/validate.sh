#!/bin/sh
# Local validation runner for repository shell files.
# BusyBox/ash-compatible.

set -u

FAILED=0

check_syntax() {
	_file="$1"
	printf '%s\n' "Checking syntax: ${_file}"
	if ! sh -n "${_file}"; then
		FAILED=1
	fi
}

check_syntax installer

if [ -d tools ]; then
	find tools -type f -name '*.sh' | sort | while read -r script; do
		sh -n "${script}" || exit 1
	done || FAILED=1
fi

if command -v shellcheck >/dev/null 2>&1; then
	printf '%s\n' 'Running ShellCheck advisory checks...'
	shellcheck installer || true
	if [ -d tools ]; then
		find tools -type f -name '*.sh' | sort | while read -r script; do
			shellcheck "${script}" || true
		done
	fi
else
	printf '%s\n' 'ShellCheck not found; skipped advisory checks.'
fi

if [ "${FAILED}" -ne 0 ]; then
	printf '%s\n' 'Validation failed.'
	exit 1
fi

printf '%s\n' 'Validation completed.'
