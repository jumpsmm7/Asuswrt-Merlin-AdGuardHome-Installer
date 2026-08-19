#!/bin/sh

set -u

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
HELPERS=$(sed -n '/^process_pids() {/,/^# Service action helpers/p' "${ROOT_DIR}/rc.func.AdGuardHome")

# fail prints a failure message to standard error and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

# run_case executes a process-signaling test case and verifies its status, signal, and variable-isolation results.
run_case() (
	PIDOF_OUTPUT="$1"
	PIDOF_STATUS="$2"
	MATCHING_PIDS="$3"
	expected_status="$4"
	expected_kill="$5"
	KILL_EXIT_STATUS="${6:-0}"
	KILL_LOG=""
	_SIGNAL=outer-signal
	_PROC=outer-process
	_PIDS=outer-pids
	_PID=outer-pid
	_VALID_PIDS=outer-valid-pids
	_PIDOF_STATUS=outer-status

	eval "${HELPERS}"
	process_pids() {
		[ -n "${PIDOF_OUTPUT}" ] && printf '%s\n' "${PIDOF_OUTPUT}"
		return "${PIDOF_STATUS}"
	}
	process_pid_matches() {
		case " ${MATCHING_PIDS} " in
			*" $1 "*) [ "$2" = AdGuardHome ] ;;
			*) return 1 ;;
		esac
	}
	kill() {
		KILL_LOG="$*"
		return "${KILL_EXIT_STATUS}"
	}

	status=0
	signal_process TERM AdGuardHome || status=$?
	[ "${status}" -eq "${expected_status}" ] || fail "status ${status}, expected ${expected_status} for '${PIDOF_OUTPUT}'"
	[ "${KILL_LOG}" = "${expected_kill}" ] || fail "kill '${KILL_LOG}', expected '${expected_kill}' for '${PIDOF_OUTPUT}'"
	[ "${_SIGNAL}" = outer-signal ] && [ "${_PROC}" = outer-process ] &&
		[ "${_PIDS}" = outer-pids ] && [ "${_PID}" = outer-pid ] &&
		[ "${_VALID_PIDS}" = outer-valid-pids ] && [ "${_PIDOF_STATUS}" = outer-status ] ||
		fail 'signal_process scratch variables leaked into its caller'
)

# Empty pidof output and pidof failure must never cause a broad name-based signal.
run_case '' 0 '' 0 ''
run_case '' 2 '' 2 ''

# Reserved and wholly malformed PID lists are refused.
run_case '0' 0 '' 1 ''
run_case '1' 0 '' 1 ''
run_case 'bad nope' 0 '' 1 ''

# Malformed/reserved fields are discarded, while valid decimal PIDs are deduplicated.
run_case '0 bad 22 1 22 0033' 0 '22 33' 0 '-s TERM 22 33'

# Malformed glob fields must be rejected before intentional PID-list splitting.
GLOB_ROOT=$(mktemp -d) || fail 'unable to create glob-expansion test directory'
trap 'rm -rf "${GLOB_ROOT}"' 0
trap 'rm -rf "${GLOB_ROOT}"; exit 1' HUP INT TERM
touch "${GLOB_ROOT}/66" || fail 'unable to create numeric glob-expansion fixture'
(
	cd "${GLOB_ROOT}" || exit 1
	run_case '* 22' 0 '22 66' 0 '-s TERM 22'
) || fail 'malformed glob field was expanded before PID validation'

# A process that exits before the identity recheck is not signaled.
run_case '44' 0 '' 1 ''

# PID reuse is refused when /proc identity no longer names the expected process.
run_case '55' 0 '99' 1 ''

# A non-zero pidof exit status must short-circuit before PID validation/signaling
# even when pidof also printed PID-shaped output alongside its failure.
run_case '22' 3 '22' 3 ''

# Leading-zero-padded and unpadded spellings of the same PID must collapse to a
# single signaled PID, not merely identical repeated tokens.
run_case '22 022' 0 '22' 0 '-s TERM 22'

# When every PID survives validation and identity recheck but the final kill
# invocation itself fails, signal_process must propagate kill's exit status
# rather than reporting success.
run_case '22' 0 '22' 5 '-s TERM 22' 5

# process_pid_matches reads the real /proc filesystem; exercise it directly
# against this shell's own live PID/comm instead of only through the stub
# used by run_case above.
(
	eval "${HELPERS}"
	OWN_COMM=""
	IFS= read -r OWN_COMM <"/proc/$$/comm" || fail 'unable to read this process comm entry for the process_pid_matches regression'
	[ -n "${OWN_COMM}" ] || fail '/proc/$$/comm was empty for the process_pid_matches regression'
	process_pid_matches "$$" "${OWN_COMM}" || fail 'process_pid_matches rejected this live process against its own /proc comm name'
	process_pid_matches "$$" "${OWN_COMM}-not-a-real-name" && fail 'process_pid_matches matched an incorrect process name'
	process_pid_matches 999999999 "${OWN_COMM}" && fail 'process_pid_matches matched an implausible nonexistent PID'
	:
) || fail 'process_pid_matches direct /proc regression failed'

# The service stop path retains its bounded TERM -> INT -> KILL escalation.
(
	STOP_HELPER=$(sed -n '/^stop() {/,/^rc_dependencies_available/p' "${ROOT_DIR}/rc.func.AdGuardHome" | sed '$d')
	eval "${STOP_HELPER}"
	ACTION=stop
	PROC=AdGuardHome
	ansi_white=''
	ansi_std=''
	ansi_red=''
	ansi_green=''
	SIGNAL_LOG=''
	WAIT_LOG=''
	# service_mark_transition provides a no-op service transition marker.
	service_mark_transition() { :; }
	# service_clear_transition clears the service transition state.
	service_clear_transition() { :; }
	# signal_process records the requested signal for a process.
	signal_process() { SIGNAL_LOG="${SIGNAL_LOG}${SIGNAL_LOG:+ }$1"; }
	# process_wait_for_stop records the requested wait duration and succeeds for a three-second wait.
	process_wait_for_stop() {
		WAIT_LOG="${WAIT_LOG}${WAIT_LOG:+ }$2"
		[ "$2" -eq 3 ]
	}
	# process_pids returns failure.
	process_pids() { return 1; }
	stop >/dev/null || fail 'bounded stop escalation did not succeed after KILL'
	[ "${SIGNAL_LOG}" = 'TERM INT KILL' ] || fail "unexpected escalation signals: ${SIGNAL_LOG}"
	[ "${WAIT_LOG}" = '10 5 3' ] || fail "unexpected escalation waits: ${WAIT_LOG}"
) || fail 'bounded TERM/INT/KILL escalation regression failed'

# rc_dependencies_available no longer requires killall now that signal_process
# only signals identity-rechecked PIDs directly; a router without killall
# installed must still be able to start the service.
DEPENDENCIES_HELPER=$(sed -n '/^rc_dependencies_available() {$/,/^}$/p' "${ROOT_DIR}/rc.func.AdGuardHome")
[ -n "${DEPENDENCIES_HELPER}" ] || fail 'could not extract rc_dependencies_available from rc.func.AdGuardHome'
case "${DEPENDENCIES_HELPER}" in
	*killall*) fail 'rc_dependencies_available still lists killall as a required command' ;;
esac

DEPS_ROOT=$(mktemp -d) || fail 'unable to create exclusive dependency-check test directory'
trap 'rm -rf "${GLOB_ROOT}" "${DEPS_ROOT}"' 0
trap 'rm -rf "${GLOB_ROOT}" "${DEPS_ROOT}"; exit 1' HUP INT TERM

# All commands rc_dependencies_available actually requires must be reported
# available (killall is deliberately absent, proving it is no longer checked).
(
	CALLER=rc-dependency-test
	# which reports whether a command is available to the test environment.
	which() {
		case "$1" in
			awk | chmod | date | dd | dirname | grep | kill | logger | ls | md5sum | mkdir | mv | pidof | rm | sleep) return 0 ;;
			*) return 1 ;;
		esac
	}
	eval "${DEPENDENCIES_HELPER}"
	rc_dependencies_available
) || fail 'rc_dependencies_available failed without killall even though every command it actually checks is available'

# A genuinely missing required command (kill) must still fail the gate with
# an actionable diagnostic naming that command.
DEPS_ERR_FILE="${DEPS_ROOT}/missing-kill.err"
(
	CALLER=rc-dependency-test
	# which reports whether a command is available in the test environment.
	which() {
		case "$1" in
			awk | chmod | date | dd | dirname | grep | logger | ls | md5sum | mkdir | mv | pidof | rm | sleep) return 0 ;;
			*) return 1 ;;
		esac
	}
	eval "${DEPENDENCIES_HELPER}"
	rc_dependencies_available
) 2>"${DEPS_ERR_FILE}" && fail 'rc_dependencies_available succeeded despite a missing required command (kill)'
grep -Fq 'rc-dependency-test: required service command is unavailable: kill' "${DEPS_ERR_FILE}" ||
	fail "rc_dependencies_available did not report the missing kill command, got: $(cat "${DEPS_ERR_FILE}")"

printf '%s\n' 'rc process signaling tests passed'
