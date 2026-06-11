#!/bin/sh
# Verify startup acquires the IPSET lock before stopping AdGuardHome and restores it on failure.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
FUNCTION_FILE="${TMPDIR:-/tmp}/start-adguardhome-function.$$"
SERVICE_WAIT_FILE="${TMPDIR:-/tmp}/service-wait-function.$$"
CALLS_FILE="${TMPDIR:-/tmp}/start-adguardhome-calls.$$"

cleanup() {
	rm -f "${FUNCTION_FILE}" "${SERVICE_WAIT_FILE}" "${CALLS_FILE}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

sed -n '/^start_adguardhome() {$/,/^}$/p; /^IPSet_Lock_Interrupt_Cleanup() {$/,/^}$/p; /^IPSet_Start_Restore() {$/,/^}$/p; /^IPSet_Setup_For_Start() {$/,/^}$/p; /^IPSet_Setup_For_Start_Locked() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" || fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTION_FILE}" ] || fail 'startup lifecycle functions were not found'
sed -n '/^service_wait() {$/,/^}$/p' "${SCRIPT_PATH}" >"${SERVICE_WAIT_FILE}" || fail "could not read ${SCRIPT_PATH}"
[ -s "${SERVICE_WAIT_FILE}" ] || fail 'service-wait function was not found'

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

IPSet_Supported() {
	printf '%s\n' IPSet_Supported >>"${CALLS_FILE}"
	return "${SUPPORTED_STATUS}"
}

IPSet_Lock() {
	printf '%s\n' 'IPSet_Lock acquired' >>"${CALLS_FILE}"
	[ "${LOCK_STATUS}" -eq 0 ] || return "${LOCK_STATUS}"
	"$@"
	STATUS="$?"
	printf '%s\n' 'IPSet_Lock released' >>"${CALLS_FILE}"
	if [ "${INTERRUPT_AFTER_UNLOCK}" -eq 1 ]; then
		printf '%s\n' 'interrupt after lock release' >>"${CALLS_FILE}"
		[ "${IPSET_START_STOPPED}" -eq 0 ] || fail 'post-lock interrupt found AdGuardHome stopped'
		IPSet_Lock_Interrupt_Cleanup
	fi
	return "${STATUS}"
}

IPSet_Setup_Locked() {
	printf '%s\n' IPSet_Setup_Locked >>"${CALLS_FILE}"
	return "${IPSET_STATUS}"
}

logger() {
	:
}

lower_script() {
	printf '%s\n' "lower_script $1" >>"${CALLS_FILE}"
	case "$1" in
	stop)
		if [ "${INTERRUPT_ON_STOP}" -eq 1 ]; then
			IPSet_Lock_Interrupt_Cleanup
			return 1
		fi
		return "${STOP_STATUS}"
		;;
	start) return "${START_STATUS}" ;;
	esac
	return 0
}

pidof() {
	[ "${RUNNING}" -eq 1 ] && printf '%s\n' 1234
	return 0
}

readlink() {
	[ "$1" = '-f' ] || fail "unexpected readlink arguments: $*"
	printf '/mock/%s\n' "${2##*/}"
}

ln() {
	fail "database-link setup escaped the test double: $*"
}

# Stop successful starts before the function enters its router-only health-check path.
service_wait() {
	return 1
}

run_test() {
	DESCRIPTION="$1"
	RUNNING="$2"
	SUPPORTED_STATUS="$3"
	LOCK_STATUS="$4"
	STOP_STATUS="$5"
	IPSET_STATUS="$6"
	START_STATUS="$7"
	EXPECTED_STATUS="$8"
	EXPECTED="$9"
	: >"${CALLS_FILE}"

	if start_adguardhome; then
		ACTUAL_STATUS=0
	else
		ACTUAL_STATUS=$?
	fi
	[ "${ACTUAL_STATUS}" -eq "${EXPECTED_STATUS}" ] || fail "${DESCRIPTION}: returned ${ACTUAL_STATUS}, expected ${EXPECTED_STATUS}"

	ACTUAL="$(cat "${CALLS_FILE}")"
	[ "${ACTUAL}" = "${EXPECTED}" ] || fail "${DESCRIPTION}: unexpected lifecycle: ${ACTUAL}"
}

run_service_wait_terminal_test() {
	: >"${CALLS_FILE}"
	(
		# shellcheck disable=SC1090
		. "${SERVICE_WAIT_FILE}"
		timezone() { :; }
		nvram() { printf '%s\n' 1; }
		terminal_failure() {
			printf '%s\n' called >>"${CALLS_FILE}"
			SERVICE_WAIT_TERMINAL_FAILURE="1"
			return 1
		}
		service_wait terminal_failure 30
	)
	STATUS="$?"
	[ "${STATUS}" -eq 1 ] || fail "service_wait returned ${STATUS}, expected terminal failure"
	[ "$(wc -l <"${CALLS_FILE}")" -eq 1 ] || fail 'service_wait retried a terminal failure'
}

run_interrupt_cleanup_test() {
	DESCRIPTION="$1"
	START_STATUS="$2"
	IPSET_START_STOPPED="1"
	: >"${CALLS_FILE}"

	IPSet_Lock_Interrupt_Cleanup
	[ "${IPSET_START_STOPPED}" -eq 0 ] || fail "${DESCRIPTION}: left restoration armed"
	ACTUAL="$(cat "${CALLS_FILE}")"
	[ "${ACTUAL}" = 'lower_script start' ] || fail "${DESCRIPTION}: unexpected lifecycle: ${ACTUAL}"
}

PROCS=AdGuardHome
NAME=AdGuardHome
WORK_DIR=/tmp/adguardhome-test
INTERRUPT_ON_STOP=0
INTERRUPT_AFTER_UNLOCK=0

run_service_wait_terminal_test

run_test 'setup failure while stopped' 0 0 0 0 1 0 1 'IPSet_Supported
IPSet_Lock acquired
IPSet_Setup_Locked
IPSet_Lock released'
run_test 'setup failure restores running service with terminal failure' 1 0 0 0 1 0 1 'IPSet_Supported
IPSet_Lock acquired
lower_script stop
IPSet_Setup_Locked
IPSet_Lock released
lower_script start'
[ "${SERVICE_WAIT_TERMINAL_FAILURE}" -eq 1 ] || fail 'restored setup failure was not marked terminal'
run_test 'failed restoration remains an error' 1 0 0 0 1 1 1 'IPSet_Supported
IPSet_Lock acquired
lower_script stop
IPSet_Setup_Locked
IPSet_Lock released
lower_script start'
run_test 'lock contention leaves running service untouched' 1 0 7 0 0 0 1 'IPSet_Supported
IPSet_Lock acquired'
run_test 'stop failure aborts setup' 1 0 0 1 0 0 1 'IPSet_Supported
IPSet_Lock acquired
lower_script stop
IPSet_Lock released'
INTERRUPT_ON_STOP=1
run_test 'interrupt during stop restores running service' 1 0 0 0 0 0 1 'IPSet_Supported
IPSet_Lock acquired
lower_script stop
lower_script start
IPSet_Lock released'
INTERRUPT_ON_STOP=0
run_test 'unsupported integration leaves running service available' 1 1 0 0 0 0 1 'IPSet_Supported
lower_script start'

run_interrupt_cleanup_test 'interrupt restores stopped service' 0
run_interrupt_cleanup_test 'failed interrupt restoration is not retried' 1

run_test 'successful setup restarts before releasing lock' 1 0 0 0 0 0 1 'IPSet_Supported
IPSet_Lock acquired
lower_script stop
IPSet_Setup_Locked
lower_script start
IPSet_Lock released'
INTERRUPT_AFTER_UNLOCK=1
run_test 'post-lock interrupt cannot strand the service' 1 0 0 0 0 0 1 'IPSet_Supported
IPSet_Lock acquired
lower_script stop
IPSet_Setup_Locked
lower_script start
IPSet_Lock released
interrupt after lock release'
INTERRUPT_AFTER_UNLOCK=0
run_test 'failed locked restart is not retried' 1 0 0 0 0 1 1 'IPSet_Supported
IPSet_Lock acquired
lower_script stop
IPSet_Setup_Locked
lower_script start
IPSet_Lock released'

printf '%s\n' 'PASS: startup acquires the IPSET lock before stopping AdGuardHome and preserves rollback behavior'
