#!/bin/sh

set -u

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
HELPERS=$(sed -n '/^process_pids() {/,/^# Service action helpers/p' "${ROOT_DIR}/rc.func.AdGuardHome")

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

run_case() (
	PIDOF_OUTPUT="$1"
	PIDOF_STATUS="$2"
	MATCHING_PIDS="$3"
	expected_status="$4"
	expected_kill="$5"
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
		return 0
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
	service_mark_transition() { :; }
	service_clear_transition() { :; }
	signal_process() { SIGNAL_LOG="${SIGNAL_LOG}${SIGNAL_LOG:+ }$1"; }
	process_wait_for_stop() {
		WAIT_LOG="${WAIT_LOG}${WAIT_LOG:+ }$2"
		[ "$2" -eq 3 ]
	}
	process_pids() { return 1; }
	stop >/dev/null || fail 'bounded stop escalation did not succeed after KILL'
	[ "${SIGNAL_LOG}" = 'TERM INT KILL' ] || fail "unexpected escalation signals: ${SIGNAL_LOG}"
	[ "${WAIT_LOG}" = '10 5 3' ] || fail "unexpected escalation waits: ${WAIT_LOG}"
)

printf '%s\n' 'rc process signaling tests passed'
