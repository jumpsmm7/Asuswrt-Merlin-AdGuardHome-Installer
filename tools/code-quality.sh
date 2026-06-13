#!/bin/sh
# Run local quality checks for shell scripts and installer checksums.
# BusyBox/ash-compatible; keep this script POSIX sh only.
# Use --fix to apply shfmt formatting instead of checking the diff.

set -u

FAILED=0
FIX=0
SCRIPT_LIST=""

case "${1:-}" in
	--fix) FIX=1 ;;
	"") ;;
	*)
		printf '%s\n' "Usage: $0 [--fix]" >&2
		exit 2
		;;
esac

# Functions are sorted alpha-numerically for readability.

cleanup() {
	if [ -n "${SCRIPT_LIST}" ] && [ -f "${SCRIPT_LIST}" ]; then
		rm -f "${SCRIPT_LIST}"
	fi
}

have_cmd() {
	which "$1" >/dev/null 2>&1
}

require_cmd() {
	_cmd="$1"
	if have_cmd "${_cmd}"; then
		return 0
	fi

	printf '%s\n' "Error: ${_cmd} is required. Install it and re-run this script." >&2
	FAILED=1
	return 1
}

run_check() {
	_name="$1"
	shift
	printf '%s\n' "==> ${_name}"
	if "$@"; then
		printf '%s\n' "OK: ${_name}"
	else
		printf '%s\n' "FAILED: ${_name}" >&2
		FAILED=1
	fi
}

run_script_list_check() {
	_name="$1"
	shift
	_check_failed=0

	printf '%s\n' "==> ${_name}"
	while IFS= read -r _script; do
		if [ -n "${_script}" ]; then
			if ! "$@" "${_script}"; then
				_check_failed=1
			fi
		fi
	done <"${SCRIPT_LIST}"

	if [ "${_check_failed}" -eq 0 ]; then
		printf '%s\n' "OK: ${_name}"
	else
		printf '%s\n' "FAILED: ${_name}" >&2
		FAILED=1
	fi

	return "${_check_failed}"
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

SCRIPT_LIST="${TMPDIR:-/tmp}/code-quality-scripts.$$"
if ! sh tools/list-shell-scripts.sh >"${SCRIPT_LIST}"; then
	printf '%s\n' 'Error: could not list shell scripts.' >&2
	exit 1
fi

run_check 'md5sum files match installer artifacts' sh tools/check-md5.sh
run_check 'Installer menu range regression' sh tests/installer-menu-range.sh
run_check 'Installer branch switch cancellation regression' sh tests/installer-branch-switch-cancel.sh
run_check 'Installer local-cache preference save failure regression' sh tests/installer-local-cache-save-failure.sh
run_check 'Installer IPSET preference save failure regression' sh tests/installer-ipset-save-failure.sh
run_check 'Installer setup IPSET preference save failure regression' sh tests/installer-ipset-setup-save-failure.sh
run_check 'AdGuardHome startup lifecycle regression' sh tests/start-adguardhome-lifecycle.sh
run_check 'AdGuardHome monitor retry backoff regression' sh tests/monitor-retry-backoff.sh
run_check 'AdGuardHome DNS startup handoff regression' sh tests/dns-startup-handoff.sh
run_check 'AdGuardHome IPSET version gate regression' sh tests/ipset-version-gate.sh
run_check 'AdGuardHome empty IPSET data regression' sh tests/ipset-empty-rules.sh
run_check 'AdGuardHome IPSET lock security regression' sh tests/ipset-lock-security.sh
run_check 'AdGuardHome legacy IPSET disable regression' sh tests/ipset-legacy-disable.sh
run_check 'IPSET current-file YAML scalar regression' sh tests/ipset-current-file.sh
run_check 'IPSET setup rollback regression' sh tests/ipset-setup-rollback.sh

if require_cmd shellcheck; then
	run_script_list_check 'ShellCheck POSIX sh static analysis' shellcheck -s sh --severity=warning
fi

if require_cmd shfmt; then
	SHFMT_FAILED=0
	if [ "${FIX}" -eq 1 ]; then
		run_script_list_check 'shfmt mksh formatting update' shfmt -w -ln mksh -i 0 -ci || SHFMT_FAILED=1
	else
		run_script_list_check 'shfmt mksh formatting check' shfmt -d -ln mksh -i 0 -ci || SHFMT_FAILED=1
	fi

	if [ "${SHFMT_FAILED}" -ne 0 ] && [ "${FIX}" -eq 0 ]; then
		printf '%s\n' 'Hint: shfmt reported formatting differences. Run tools/code-quality.sh --fix locally, or run the Create shfmt formatting PR workflow against this branch.' >&2
	fi
fi

if [ "${FAILED}" -ne 0 ]; then
	exit 1
fi
