#!/bin/sh
# Verify rc.func independently enforces a required AdGuardHome DNS handoff.

set -u

RC_PATH="${1:-rc.func.AdGuardHome}"
TMP_ROOT="${TMPDIR:-/tmp}/rc-required-handoff-fallback.$$"
FUNCTION_FILE="${TMP_ROOT}/functions"
CALLS_FILE="${TMP_ROOT}/calls"
STARTED_FILE="${TMP_ROOT}/started"

# cleanup removes the temporary test workspace.
cleanup() {
	rm -rf "${TMP_ROOT}"
}

# fail prints a failure message to standard error and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
mkdir -p "${TMP_ROOT}" || fail 'could not create test directory'

sed -n \
	'/^stop_launched_process() {$/,/^}$/p; /^adguardhome_start_handoff_is_prepared() {$/,/^}$/p; /^adguardhome_start_handoff_required() {$/,/^}$/p; /^adguardhome_run_postfailcmd() {$/,/^}$/p; /^start() {$/,/^}$/p' \
	"${RC_PATH}" >"${FUNCTION_FILE}" || fail "could not read ${RC_PATH}"
[ -s "${FUNCTION_FILE}" ] || fail 'required rc.func startup helpers were not found'

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

ACTION='start'
CALLER='test'
CRITICAL='yes'
ENABLED='yes'
DESC='AdGuardHome'
PROC='AdGuardHome'
PREARGS=''
ARGS=''
PRECMD='pre_hook'
POSTCMD='post_hook'
POSTFAILCMD='post_failure_hook'
DNS_HANDOFF_FILE="${TMP_ROOT}/missing-marker"
ansi_white=''
ansi_yellow=''
ansi_red=''
ansi_green=''
ansi_std=''

# service_mark_transition performs no action.
service_mark_transition() {
	:
}

# process_pids prints the simulated process ID when the service start marker exists.
process_pids() {
	[ -f "${STARTED_FILE}" ] && printf '%s\n' 456
}

# process_wait_for_start waits for the simulated service start marker to appear, returning success when it appears within 100 checks and failure otherwise.
process_wait_for_start() {
	_counter=0
	while [ "${_counter}" -lt 100 ]; do
		[ -f "${STARTED_FILE}" ] && return 0
		_counter="$((_counter + 1))"
		sleep 0.01
	done
	return 1
}

# process_wait_for_stop checks whether the simulated service has stopped.
process_wait_for_stop() {
	[ ! -f "${STARTED_FILE}" ]
}

# signal_process records the signal invocation and simulates process termination by removing the started marker.
signal_process() {
	printf '%s\n' "signal $*" >>"${CALLS_FILE}"
	rm -f "${STARTED_FILE}"
}

# logger records a logger invocation and its arguments in the calls log.
logger() {
	printf '%s\n' "logger $*" >>"${CALLS_FILE}"
}

# AdGuardHome starts the simulated AdGuardHome service by creating its started marker file.
AdGuardHome() {
	: >"${STARTED_FILE}"
}

# adguardhome_start_handoff_is_prepared reports whether the required AdGuardHome DNS handoff preparation is complete.
adguardhome_start_handoff_is_prepared() {
	return 1
}

# pre_hook records that the pre-start hook was invoked and succeeds.
pre_hook() {
	printf '%s\n' pre_hook >>"${CALLS_FILE}"
	return 0
}

# post_hook records invocation of the post-start hook and succeeds.
post_hook() {
	printf '%s\n' post_hook >>"${CALLS_FILE}"
	return 0
}

# post_failure_hook records that the post-failure hook was invoked and returns success.
post_failure_hook() {
	printf '%s\n' post_failure_hook >>"${CALLS_FILE}"
	return 0
}

# agh_dns_handoff_required indicates whether AdGuardHome requires DNS handoff preparation before starting.
# The runtime helper remains authoritative when PRECMD does not export the handoff requirement.
agh_dns_handoff_required() {
	return 0
}

: >"${CALLS_FILE}"
rm -f "${STARTED_FILE}"
unset ADGUARDHOME_DNS_HANDOFF_REQUIRED ADGUARDHOME_DNS_HANDOFF_ACTIVE
if start >/dev/null; then
	fail 'rc.func launched AdGuardHome without a required DNS handoff marker'
fi
[ ! -f "${STARTED_FILE}" ] || fail 'AdGuardHome launched after the independent handoff check failed'
grep -q '^pre_hook$' "${CALLS_FILE}" || fail 'required-handoff fallback skipped the pre-start hook'
! grep -q '^post_hook$' "${CALLS_FILE}" || fail 'required-handoff fallback ran the post-start hook'
grep -q 'Pre-start hook did not prepare required DNS handoff' "${CALLS_FILE}" || fail 'required-handoff fallback did not log the abort'

# An explicit pre-start decision remains authoritative even when a runtime
# recheck would otherwise report that handoff is required.
: >"${CALLS_FILE}"
rm -f "${STARTED_FILE}"
ADGUARDHOME_DNS_HANDOFF_REQUIRED=0
export ADGUARDHOME_DNS_HANDOFF_REQUIRED
start >/dev/null || fail 'rc.func overrode an explicit no-handoff decision'
grep -q '^pre_hook$' "${CALLS_FILE}" || fail 'explicit no-handoff start skipped the pre-start hook'
grep -q '^post_hook$' "${CALLS_FILE}" || fail 'explicit no-handoff start skipped the post-start hook'
[ -f "${STARTED_FILE}" ] || fail 'explicit no-handoff start did not launch AdGuardHome'

# agh_dns_handoff_required indicates that DNS handoff is not required for a LAN start.
agh_dns_handoff_required() {
	return 1
}

: >"${CALLS_FILE}"
rm -f "${STARTED_FILE}"
unset ADGUARDHOME_DNS_HANDOFF_REQUIRED ADGUARDHOME_DNS_HANDOFF_ACTIVE
start >/dev/null || fail 'rc.func rejected a valid no-handoff start'
grep -q '^pre_hook$' "${CALLS_FILE}" || fail 'no-handoff start skipped the pre-start hook'
grep -q '^post_hook$' "${CALLS_FILE}" || fail 'no-handoff start skipped the post-start hook'
[ -f "${STARTED_FILE}" ] || fail 'no-handoff start did not launch AdGuardHome'

printf '%s\n' 'PASS: rc.func independently enforces required DNS handoff preparation'
