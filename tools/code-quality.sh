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

run_dns_handoff_check() {
	if [ "$(id -u)" -eq 0 ]; then
		sh tests/dns-startup-handoff.sh
		return
	fi

	if have_cmd sudo && sudo -n true >/dev/null 2>&1; then
		sudo -n sh tests/dns-startup-handoff.sh
		return
	fi

	printf '%s\n' 'Error: the DNS startup handoff regression requires root privileges or passwordless sudo.' >&2
	return 1
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
run_check 'Repository shell portability regression' sh tools/check-shell-portability.sh
run_check 'Command failure propagation regression' sh tests/command-failure-propagation.sh
run_check 'Canonical path final-symlink regression' sh tests/canonical-path-symlink.sh
run_check 'Router runtime PATH priority regression' sh tests/router-path-priority.sh
run_check 'Static archive failure safety regression' sh tests/download-static-failure-safety.sh
run_check 'Static archive interruption cleanup regression' sh tests/download-static-interruption-cleanup.sh
run_check 'Installer file failure safety regression' sh tests/installer-file-failure-safety.sh
run_check 'Installer progress output regression' sh tests/installer-progress-output.sh
run_check 'Installer legacy hook cleanup regression' sh tests/installer-legacy-hook-cleanup.sh
run_check 'Installer post-replacement restart regression' sh tests/installer-post-replace-restart.sh
run_check 'Installer interruption restart regression' sh tests/installer-interruption-restart.sh
run_check 'Installer menu range regression' sh tests/installer-menu-range.sh
run_check 'Installer single-argument action regression' sh tests/installer-single-arg-actions.sh
run_check 'Installer SHA-256 helper regression' sh tests/installer-sha256-helper.sh
run_check 'Installer blocklist cleanup regression' sh tests/installer-blocklist-cleanup.sh
run_check 'Installer iterative input regression' sh tests/installer-input-loops.sh
run_check 'Installer staged authentication regression' sh tests/installer-staged-authentication.sh
run_check 'Installer staged YAML validation regression' sh tests/installer-staged-yaml-validation.sh
run_check 'Installer startup readiness regression' sh tests/installer-startup-readiness.sh
run_check 'Installer service status wait regression' sh tests/installer-service-status-after-action.sh
run_check 'Installer mandatory numeric input failure regression' sh tests/installer-mandatory-number-failure.sh
run_check 'Installer DNS input failure regression' sh tests/installer-dns-input-failure.sh
run_check 'Installer WebUI port failure regression' sh tests/installer-web-port-failure.sh
run_check 'Installer timezone failure regression' sh tests/installer-timezone-failure.sh
run_check 'Installer branch switch cancellation regression' sh tests/installer-branch-switch-cancel.sh
run_check 'Installer setting confirmation failure regression' sh tests/installer-setting-confirmation-failure.sh
run_check 'Installer confirmation failure propagation regression' sh tests/installer-confirmation-failure-propagation.sh
run_check 'Installer local-cache preference save failure regression' sh tests/installer-local-cache-save-failure.sh
run_check 'Installer IPSET preference save failure regression' sh tests/installer-ipset-save-failure.sh
run_check 'Installer setup IPSET preference save failure regression' sh tests/installer-ipset-setup-save-failure.sh
run_check 'AdGuardHome permission repair regression' sh tests/adguardhome-permissions.sh
run_check 'AdGuardHome startup lifecycle regression' sh tests/start-adguardhome-lifecycle.sh
run_check 'AdGuardHome stop failure regression' sh tests/stop-adguardhome-failure.sh
run_check 'AdGuardHome monitor retry backoff regression' sh tests/monitor-retry-backoff.sh
run_check 'AdGuardHome DNS startup handoff regression' run_dns_handoff_check
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
