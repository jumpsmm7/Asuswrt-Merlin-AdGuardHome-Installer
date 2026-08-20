#!/bin/sh
# Verify restart never calls start after a failed stop and propagates the stop status.

set -u

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
RC_PATH="${ROOT_DIR}/rc.func.AdGuardHome"
TEST_ROOT="${TMPDIR:-/tmp}/rc-restart-stop-failure.$$"
DISPATCHER="${TEST_ROOT}/dispatcher.sh"
EVENTS="${TEST_ROOT}/events"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

cleanup() {
	rm -rf "${TEST_ROOT}"
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
umask 077
mkdir "${TEST_ROOT}" || fail 'could not create test workspace'

sed -n '/^rc_dependencies_available || exit 1$/,/^#logger /p' "${RC_PATH}" | sed '$d' >"${DISPATCHER}" ||
	fail 'could not extract rc action dispatcher'
[ -s "${DISPATCHER}" ] || fail 'rc action dispatcher extraction was empty'

: >"${EVENTS}"
(
	rc_dependencies_available() { return 0; }
	check() { return 0; }
	stop() {
		printf '%s\n' stop >>"${EVENTS}"
		return 255
	}
	start() {
		printf '%s\n' start >>"${EVENTS}"
		return 0
	}
	reload() { return 0; }
	PROCS=AdGuardHome
	DESC=AdGuardHome
	ACTION=restart
	ansi_white=''
	ansi_std=''
	# shellcheck disable=SC1090
	. "${DISPATCHER}"
)
_status="$?"
[ "${_status}" -eq 255 ] || fail "failed restart returned ${_status}, expected 255"
[ "$(cat "${EVENTS}")" = stop ] || fail 'restart called start after stop failure'

: >"${EVENTS}"
(
	rc_dependencies_available() { return 0; }
	check() { return 0; }
	stop() {
		printf '%s\n' stop >>"${EVENTS}"
		return 0
	}
	start() {
		printf '%s\n' start >>"${EVENTS}"
		return 0
	}
	reload() { return 0; }
	PROCS=AdGuardHome
	DESC=AdGuardHome
	ACTION=restart
	ansi_white=''
	ansi_std=''
	# shellcheck disable=SC1090
	. "${DISPATCHER}"
) || fail 'successful restart path returned failure'
[ "$(cat "${EVENTS}")" = "$(printf 'stop\nstart')" ] || fail 'successful restart did not stop before start'

: >"${EVENTS}"
(
	rc_dependencies_available() { return 0; }
	check() { return 1; }
	stop() {
		printf '%s\n' stop >>"${EVENTS}"
		return 0
	}
	start() {
		printf '%s\n' start >>"${EVENTS}"
		return 0
	}
	reload() { return 0; }
	PROCS=AdGuardHome
	DESC=AdGuardHome
	ACTION=restart
	ansi_white=''
	ansi_std=''
	# shellcheck disable=SC1090
	. "${DISPATCHER}"
) || fail 'restart of a stopped service returned failure'
[ "$(cat "${EVENTS}")" = start ] || fail 'restart of a stopped service did not start directly'

printf '%s\n' 'PASS: restart propagates stop failure and never starts over a surviving process'
