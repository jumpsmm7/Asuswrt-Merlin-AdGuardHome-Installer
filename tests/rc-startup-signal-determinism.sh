#!/bin/sh
# Verify startup-signal recovery at controlled synchronization points without timing windows.

set -u

RC_PATH="${1:-rc.func.AdGuardHome}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rc-startup-signal-determinism.XXXXXX")" || {
	printf '%s\n' 'FAIL: could not create exclusive startup-signal test directory' >&2
	exit 1
}
FUNCTION_FILE="${TMP_ROOT}/functions"
CALLS_FILE="${TMP_ROOT}/calls"
STARTED_FILE="${TMP_ROOT}/started"
TRANSITION_FILE="${TMP_ROOT}/transition"

cleanup() {
	rm -rf "${TMP_ROOT}"
	for _path in /tmp/AdGuardHome-start-traps.$$.*; do
		[ "${_path}" = "/tmp/AdGuardHome-start-traps.$$.*" ] && break
		rm -rf "${_path}" 2>/dev/null || true
	done
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

wait_for_marker() {
	_marker="$1"
	_label="$2"
	_waits=0
	while [ ! -f "${_marker}" ] && [ "${_waits}" -lt 60 ]; do
		sleep 1
		_waits="$((_waits + 1))"
	done
	[ -f "${_marker}" ] || fail "timed out waiting for ${_label}"
}

hold_until_release() {
	_ready="$1"
	_release="$2"
	_label="$3"
	: >"${_ready}" || return 1
	_waits=0
	while [ ! -f "${_release}" ] && [ "${_waits}" -lt 60 ]; do
		sleep 1
		_waits="$((_waits + 1))"
	done
	[ -f "${_release}" ] || {
		printf '%s\n' "timeout ${_label}" >>"${CALLS_FILE}"
		return 1
	}
	printf '%s\n' "released ${_label}" >>"${CALLS_FILE}"
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

sed -n \
	'/^stop_launched_process() {$/,/^}$/p; /^adguardhome_start_handoff_is_prepared() {$/,/^}$/p; /^adguardhome_start_handoff_required() {$/,/^}$/p; /^hook_function_is_valid() {$/,/^}$/p; /^start_hooks_are_valid() {$/,/^}$/p; /^adguardhome_run_postfailcmd() {$/,/^}$/p; /^adguardhome_start_traps_cleanup() {$/,/^}$/p; /^adguardhome_start_traps_restore() {$/,/^}$/p; /^adguardhome_start_traps_save() {$/,/^}$/p; /^adguardhome_start_signal_abort() {$/,/^}$/p; /^start() {$/,/^}$/p' \
	"${RC_PATH}" >"${FUNCTION_FILE}" || fail "could not read ${RC_PATH}"
[ -s "${FUNCTION_FILE}" ] || fail 'required rc.func startup helpers were not found'

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"
for _helper in adguardhome_run_postfailcmd adguardhome_start_signal_abort adguardhome_start_traps_restore adguardhome_start_traps_save start; do
	type "${_helper}" >/dev/null 2>&1 || fail "startup helper extraction missing ${_helper}"
done

ACTION='start'
CALLER='test'
CRITICAL='yes'
ENABLED='yes'
DESC='AdGuardHome'
PROC='AdGuardHome'
PRECMD='pre_hook'
POSTCMD='post_hook'
POSTFAILCMD='post_failure_hook'
DNS_HANDOFF_FILE="${TMP_ROOT}/missing-marker"
PREARGS=''
ARGS=''
ansi_white=''
ansi_yellow=''
ansi_red=''
ansi_green=''
ansi_std=''
ADGUARDHOME_LAUNCH_HELPER=1
ADGUARDHOME_DNS_HANDOFF_REQUIRED=0
export ADGUARDHOME_DNS_HANDOFF_REQUIRED

service_mark_transition() {
	: >"${TRANSITION_FILE}"
}

process_pids() {
	[ -f "${STARTED_FILE}" ] && printf '%s\n' 456
}

process_wait_for_start() {
	[ -f "${STARTED_FILE}" ]
}

process_wait_for_stop() {
	[ ! -f "${STARTED_FILE}" ]
}

signal_process() {
	printf '%s\n' "signal $*" >>"${CALLS_FILE}"
	rm -f "${STARTED_FILE}"
}

logger() {
	printf '%s\n' "logger $*" >>"${CALLS_FILE}"
}

AdGuardHome() {
	: >"${STARTED_FILE}"
}

launch_adguardhome() {
	AdGuardHome
}

adguardhome_start_handoff_is_prepared() {
	return 1
}

pre_hook() {
	printf '%s\n' pre_hook >>"${CALLS_FILE}"
}

post_hook() {
	printf '%s\n' post_hook >>"${CALLS_FILE}"
}

post_failure_hook() {
	printf '%s\n' post_failure_hook >>"${CALLS_FILE}"
}

trap_snapshot() {
	trap >"$1"
}

assert_trap_workspace_removed() {
	set -- /tmp/AdGuardHome-start-traps.$$.*
	[ "$1" = "/tmp/AdGuardHome-start-traps.$$.*" ] ||
		fail 'private startup trap workspace was not removed'
}

# The child cannot leave the mocked mkdir until the parent has enqueued TERM
# and then publishes the release marker.  This removes the previous one-second
# scheduling window while still exercising the real deferral path in
# adguardhome_start_traps_save().
SAVE_READY_FILE="${TMP_ROOT}/save-ready"
SAVE_RELEASE_FILE="${TMP_ROOT}/save-release"
: >"${CALLS_FILE}"
rm -f "${STARTED_FILE}" "${SAVE_READY_FILE}" "${SAVE_RELEASE_FILE}"
(
	set +e
	mkdir() {
		case "$1" in
			/tmp/AdGuardHome-start-traps.*)
				hold_until_release "${SAVE_READY_FILE}" "${SAVE_RELEASE_FILE}" trap-save || return 1
				;;
		esac
		command mkdir "$@"
	}
	trap 'printf "%s\n" caller_signal >>"${CALLS_FILE}"' HUP INT TERM
	start >/dev/null
) &
_save_pid="$!"
wait_for_marker "${SAVE_READY_FILE}" 'trap-save synchronization point'
[ ! -f "${STARTED_FILE}" ] || fail 'service launched before trap-save signal injection'
kill -TERM "${_save_pid}" || fail 'could not inject TERM during trap workspace initialization'
: >"${SAVE_RELEASE_FILE}" || fail 'could not release trap-save synchronization point'
set +e
wait "${_save_pid}"
_save_status="$?"
set -e
[ "${_save_status}" -eq 255 ] || fail "trap-save signal returned ${_save_status}"
[ ! -f "${STARTED_FILE}" ] || fail 'trap-save signal launched AdGuardHome'
grep -q '^post_failure_hook$' "${CALLS_FILE}" || fail 'trap-save signal skipped failure recovery'
! grep -q '^caller_signal$' "${CALLS_FILE}" || fail 'trap-save signal reached caller handler before recovery'
grep -q '^released trap-save$' "${CALLS_FILE}" || fail 'trap-save synchronization point was not explicitly released'
assert_trap_workspace_removed

# A repeated TERM must be ignored while adguardhome_start_signal_abort is
# already recovering.  Each recovery phase blocks on a parent-controlled
# release marker, so the second TERM is guaranteed to be sent while that phase
# is active rather than during a scheduler-dependent sleep window.
for REPEAT_PHASE in stop postfail; do
	REPEAT_ARMED_FILE="${TMP_ROOT}/repeat-armed-${REPEAT_PHASE}"
	REPEAT_READY_FILE="${TMP_ROOT}/repeat-ready-${REPEAT_PHASE}"
	REPEAT_RELEASE_FILE="${TMP_ROOT}/repeat-release-${REPEAT_PHASE}"
	REPEAT_BEFORE_FILE="${TMP_ROOT}/repeat-before-${REPEAT_PHASE}"
	REPEAT_AFTER_FILE="${TMP_ROOT}/repeat-after-${REPEAT_PHASE}"
	rm -f "${REPEAT_ARMED_FILE}" "${REPEAT_READY_FILE}" "${REPEAT_RELEASE_FILE}" \
		"${REPEAT_BEFORE_FILE}" "${REPEAT_AFTER_FILE}" "${STARTED_FILE}"
	: >"${CALLS_FILE}"
	(
		trap 'printf "%s\n" caller_signal >>"${CALLS_FILE}"' HUP INT TERM
		trap_snapshot "${REPEAT_BEFORE_FILE}"

		stop_launched_process() {
			if [ "${REPEAT_PHASE}" = stop ]; then
				hold_until_release "${REPEAT_READY_FILE}" "${REPEAT_RELEASE_FILE}" repeat-stop
			fi
		}

		post_failure_hook() {
			if [ "${REPEAT_PHASE}" = postfail ]; then
				hold_until_release "${REPEAT_READY_FILE}" "${REPEAT_RELEASE_FILE}" repeat-postfail || return 1
			fi
			printf '%s\n' repeat_post_failure >>"${CALLS_FILE}"
		}

		trap 'trap_snapshot "${REPEAT_AFTER_FILE}"' 0
		adguardhome_start_traps_save || exit 1
		trap 'adguardhome_start_signal_abort' HUP INT TERM
		: >"${REPEAT_ARMED_FILE}"
		while :; do
			sleep 1
		done
	) &
	_repeat_pid="$!"
	wait_for_marker "${REPEAT_ARMED_FILE}" "${REPEAT_PHASE} recovery arm"
	kill -TERM "${_repeat_pid}" || fail "could not start ${REPEAT_PHASE} signal recovery"
	wait_for_marker "${REPEAT_READY_FILE}" "${REPEAT_PHASE} recovery synchronization point"
	[ ! -f "${REPEAT_RELEASE_FILE}" ] || fail "${REPEAT_PHASE} recovery released itself before repeated TERM"
	kill -TERM "${_repeat_pid}" || fail "could not inject repeated TERM during ${REPEAT_PHASE} recovery"
	: >"${REPEAT_RELEASE_FILE}" || fail "could not release ${REPEAT_PHASE} recovery synchronization point"
	set +e
	wait "${_repeat_pid}"
	_repeat_status="$?"
	set -e
	[ "${_repeat_status}" -eq 255 ] || fail "${REPEAT_PHASE} repeated-signal recovery returned ${_repeat_status}"
	grep -q '^repeat_post_failure$' "${CALLS_FILE}" || fail "${REPEAT_PHASE} repeated TERM skipped post-failure recovery"
	! grep -q '^caller_signal$' "${CALLS_FILE}" || fail "${REPEAT_PHASE} repeated TERM escaped the recovery signal mask"
	case "${REPEAT_PHASE}" in
		stop) grep -q '^released repeat-stop$' "${CALLS_FILE}" || fail 'stop recovery was not explicitly released' ;;
		postfail) grep -q '^released repeat-postfail$' "${CALLS_FILE}" || fail 'post-failure recovery was not explicitly released' ;;
	esac
	[ "$(cat "${REPEAT_AFTER_FILE}")" = "$(cat "${REPEAT_BEFORE_FILE}")" ] ||
		fail "${REPEAT_PHASE} repeated TERM prevented caller trap restoration"
	assert_trap_workspace_removed
done

printf '%s\n' 'PASS: startup signal deferral and repeated-signal recovery use deterministic synchronization points'
