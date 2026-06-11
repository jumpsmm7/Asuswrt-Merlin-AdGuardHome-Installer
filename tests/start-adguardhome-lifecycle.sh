#!/bin/sh
# Verify IPSET preparation stops AdGuardHome before migration and restores it on failure.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
FUNCTION_FILE="${TMPDIR:-/tmp}/start-adguardhome-function.$$"
CALLS_FILE="${TMPDIR:-/tmp}/start-adguardhome-calls.$$"

cleanup() {
	rm -f "${FUNCTION_FILE}" "${CALLS_FILE}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

sed -n '/^start_adguardhome() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" || fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTION_FILE}" ] || fail 'start_adguardhome was not found'

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

IPSet_Setup() {
	printf '%s\n' IPSet_Setup >>"${CALLS_FILE}"
	return "${IPSET_STATUS}"
}

logger() {
	:
}

lower_script() {
	printf '%s\n' "lower_script $1" >>"${CALLS_FILE}"
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

run_setup_failure_test() {
	IPSET_STATUS=1
	RUNNING="$1"
	: >"${CALLS_FILE}"

	if start_adguardhome; then
		fail "startup succeeded when IPSET setup failed (running=${RUNNING})"
	fi

	if [ "${RUNNING}" -eq 1 ]; then
		EXPECTED='lower_script stop
IPSet_Setup
lower_script start'
	else
		EXPECTED='IPSet_Setup'
	fi
	ACTUAL="$(cat "${CALLS_FILE}")"
	[ "${ACTUAL}" = "${EXPECTED}" ] || fail "unexpected IPSET failure lifecycle (running=${RUNNING}): ${ACTUAL}"
}

run_success_order_test() {
	IPSET_STATUS=0
	RUNNING=1
	: >"${CALLS_FILE}"

	# Stop after the lifecycle calls so the function does not enter its router-only wait path.
	service_wait() {
		return 1
	}

	start_adguardhome || true

	EXPECTED='lower_script stop
IPSet_Setup
lower_script start'
	ACTUAL="$(cat "${CALLS_FILE}")"
	[ "${ACTUAL}" = "${EXPECTED}" ] || fail "unexpected successful setup order: ${ACTUAL}"
}

PROCS=AdGuardHome
NAME=AdGuardHome
WORK_DIR=/tmp/adguardhome-test

run_setup_failure_test 0
run_setup_failure_test 1
run_success_order_test
printf '%s\n' 'PASS: AdGuardHome stops before IPSET setup and is restored after rollback'
