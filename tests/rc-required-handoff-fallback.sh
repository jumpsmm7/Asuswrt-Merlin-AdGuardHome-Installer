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
	'/^stop_launched_process() {$/,/^}$/p; /^adguardhome_start_handoff_is_prepared() {$/,/^}$/p; /^adguardhome_start_handoff_required() {$/,/^}$/p; /^adguardhome_run_postfailcmd() {$/,/^}$/p; /^adguardhome_start_traps_cleanup() {$/,/^}$/p; /^adguardhome_start_traps_restore() {$/,/^}$/p; /^adguardhome_start_traps_save() {$/,/^}$/p; /^adguardhome_start_signal_abort() {$/,/^}$/p; /^start() {$/,/^}$/p' \
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

# trap_snapshot writes dispositions in the current shell; command substitution
# would reset caught traps in dash and other POSIX shells.
trap_snapshot() {
	trap >"$1"
}

# managed_trap_count makes the preservation checks non-vacuous: custom and
# ignored dispositions must be present in snapshots captured by the test shell.
managed_trap_count() {
	awk '/ (SIG)?(HUP|INT|TERM)$/ { count++ } END { print count + 0 }' "$1"
}

# assert_trap_workspace_removed checks both the private state variables and the
# predictable PID portion of the temporary directory name.
assert_trap_workspace_removed() {
	[ -z "${ADGUARDHOME_START_TRAP_FILE:-}" ] || fail 'trap state file variable was not cleared'
	[ -z "${ADGUARDHOME_START_TRAP_DIR:-}" ] || fail 'trap state directory variable was not cleared'
	set -- /tmp/AdGuardHome-start-traps.$$.*
	[ "$1" = "/tmp/AdGuardHome-start-traps.$$.*" ] || fail 'private trap state directory was not removed'
}

# Trap-state preparation failures must complete the pending status line, log
# the failure, and preserve the established startup failure status.
mkdir() {
	return 1
}
: >"${CALLS_FILE}"
rm -f "${STARTED_FILE}"
set +e
start >"${TMP_ROOT}/trap-save-failure-output"
_trap_save_status="$?"
set -e
unset -f mkdir
[ "${_trap_save_status}" -eq 255 ] || fail "trap-state preparation failure returned ${_trap_save_status}"
grep -q 'failed\.' "${TMP_ROOT}/trap-save-failure-output" || fail 'trap-state preparation failure did not print failed status'
grep -q 'Failed to prepare startup trap state for AdGuardHome from test\.' "${CALLS_FILE}" ||
	fail 'trap-state preparation failure was not logged'
assert_trap_workspace_removed

# Save rollback must reset originally-default signals after filtering or final
# permission setup fails; bare trap snapshots omit default dispositions.
for _rollback_stage in filter directory-chmod file-chmod; do
	(
		trap - HUP INT TERM
		trap_snapshot "${TMP_ROOT}/rollback-before-${_rollback_stage}"
		case "${_rollback_stage}" in
			filter)
				awk() { return 1; }
				;;
			directory-chmod)
				chmod() {
					[ "$1" = 700 ] && return 1
					command chmod "$@"
				}
				;;
			file-chmod)
				chmod() {
					[ "$1" = 600 ] && return 1
					command chmod "$@"
				}
				;;
		esac
		adguardhome_start_traps_save && exit 1
		trap_snapshot "${TMP_ROOT}/rollback-after-${_rollback_stage}"
		[ "$(cat "${TMP_ROOT}/rollback-after-${_rollback_stage}")" = "$(cat "${TMP_ROOT}/rollback-before-${_rollback_stage}")" ]
	) || fail "${_rollback_stage} failure did not restore default signal dispositions"
	assert_trap_workspace_removed
done

# Workspace paths must be cleanup-visible before mkdir creates the directory.
set +e
rm -f "${TMP_ROOT}/workspace-published"
(
	mkdir() {
		[ "${ADGUARDHOME_START_TRAP_DIR:-}" = "$1" ] || return 91
		[ "${ADGUARDHOME_START_TRAP_FILE:-}" = "$1/state" ] || return 92
		: >"${TMP_ROOT}/workspace-published"
		return 1
	}
	adguardhome_start_traps_save
)
_workspace_publish_status="$?"
set -e
[ "${_workspace_publish_status}" -eq 1 ] || fail "trap workspace was not published before mkdir (${_workspace_publish_status})"
[ -f "${TMP_ROOT}/workspace-published" ] || fail 'mkdir could not see the published trap workspace'
assert_trap_workspace_removed

# A signal received while the trap workspace is being initialized must be
# deferred until start() can run the normal abort and recovery pathway.
_save_interrupt_ready="${TMP_ROOT}/trap-save-interrupt-ready"
: >"${CALLS_FILE}"
rm -f "${STARTED_FILE}" "${_save_interrupt_ready}"
(
	set +e
	mkdir() {
		: >"${_save_interrupt_ready}"
		sleep 1
		command mkdir "$@"
	}
	trap 'printf "%s\n" caller_signal >>"${CALLS_FILE}"' HUP INT TERM
	start >/dev/null
) &
_save_interrupt_pid="$!"
_save_interrupt_waits=0
while [ ! -f "${_save_interrupt_ready}" ] && [ "${_save_interrupt_waits}" -lt 100 ]; do
	sleep 0.01
	_save_interrupt_waits="$((_save_interrupt_waits + 1))"
done
[ -f "${_save_interrupt_ready}" ] || fail 'trap-save interruption did not reach workspace initialization'
kill -TERM "${_save_interrupt_pid}" || fail 'could not interrupt trap workspace initialization'
set +e
wait "${_save_interrupt_pid}"
_save_interrupt_status="$?"
set -e
[ "${_save_interrupt_status}" -eq 255 ] || fail "trap-save interruption returned ${_save_interrupt_status}"
[ ! -f "${STARTED_FILE}" ] || fail 'trap-save interruption launched AdGuardHome'
grep -q '^post_failure_hook$' "${CALLS_FILE}" || fail 'trap-save interruption skipped failure recovery'
! grep -q '^caller_signal$' "${CALLS_FILE}" || fail 'trap-save interruption ran the caller handler before recovery'
assert_trap_workspace_removed

# Predictable legacy directory names must not be able to deny startup.
_collision_counter=0
while [ "${_collision_counter}" -lt 10 ]; do
	mkdir "/tmp/AdGuardHome-start-traps.$$.$_collision_counter" || fail 'could not prepare trap directory collision'
	_collision_counter="$((_collision_counter + 1))"
done
adguardhome_start_traps_save || fail 'predictable trap directory collisions denied startup'
adguardhome_start_traps_restore
_collision_counter=0
while [ "${_collision_counter}" -lt 10 ]; do
	rmdir "/tmp/AdGuardHome-start-traps.$$.$_collision_counter" || fail 'could not remove trap directory collision'
	_collision_counter="$((_collision_counter + 1))"
done

# Saving signal traps must neither capture nor later restore an unrelated EXIT trap.
(
	trap 'printf "%s\n" initial_exit >/dev/null' 0
	trap 'printf "%s\n" caller_signal >/dev/null' HUP INT TERM
	adguardhome_start_traps_save || exit 1
	grep -E ' (SIG)?(HUP|INT|TERM)$' "${ADGUARDHOME_START_TRAP_FILE}" >"${TMP_ROOT}/saved-signal-traps" || exit 1
	[ "$(wc -l <"${TMP_ROOT}/saved-signal-traps")" -eq 3 ] || exit 1
	[ "$(cat "${ADGUARDHOME_START_TRAP_FILE}")" = "$(cat "${TMP_ROOT}/saved-signal-traps")" ] || exit 1
	trap 'printf "%s\n" replacement_exit >/dev/null' 0
	trap_snapshot "${TMP_ROOT}/before-exit-traps"
	adguardhome_start_traps_restore
	trap_snapshot "${TMP_ROOT}/after-exit-traps"
	[ "$(grep 'EXIT\| 0$' "${TMP_ROOT}/after-exit-traps")" = "$(grep 'EXIT\| 0$' "${TMP_ROOT}/before-exit-traps")" ]
) || fail 'saved trap state was not restricted to HUP, INT, and TERM'
rm -f "${TMP_ROOT}/saved-signal-traps"
assert_trap_workspace_removed

# A literal newline in a managed action must remain part of one restorable record.
(
	trap "printf '%s\\n' \"it's fine
signal\" >/dev/null" HUP
	trap_snapshot "${TMP_ROOT}/before-multiline-traps"
	[ "$(managed_trap_count "${TMP_ROOT}/before-multiline-traps")" -eq 1 ] || exit 1
	adguardhome_start_traps_save || exit 1
	trap - HUP
	adguardhome_start_traps_restore
	trap_snapshot "${TMP_ROOT}/after-multiline-traps"
	[ "$(cat "${TMP_ROOT}/after-multiline-traps")" = "$(cat "${TMP_ROOT}/before-multiline-traps")" ]
) || fail 'multiline signal trap action was not preserved intact'
assert_trap_workspace_removed

# run_with_trap_disposition verifies exact preservation for custom, ignored,
# and default signal dispositions around a selected startup result.
run_with_trap_disposition() {
	_disposition="$1"
	_expected_status="$2"
	case "${_disposition}" in
		custom) trap 'printf "%s\n" caller_signal >>"${CALLS_FILE}"' HUP INT TERM ;;
		ignored) trap '' HUP INT TERM ;;
		default) trap - HUP INT TERM ;;
	esac
	trap_snapshot "${TMP_ROOT}/before-traps"
	case "${_disposition}" in
		custom | ignored) _expected_trap_count=3 ;;
		default) _expected_trap_count=0 ;;
	esac
	[ "$(managed_trap_count "${TMP_ROOT}/before-traps")" -eq "${_expected_trap_count}" ] ||
		fail "${_disposition} traps were not captured in the current test shell"
	set +e
	start >/dev/null
	_status="$?"
	set -e
	trap_snapshot "${TMP_ROOT}/after-traps"
	[ "${_status}" -eq "${_expected_status}" ] || fail "${_disposition} traps: unexpected start status ${_status}"
	[ "$(managed_trap_count "${TMP_ROOT}/after-traps")" -eq "${_expected_trap_count}" ] ||
		fail "${_disposition} traps were not retained in the current test shell"
	[ "$(cat "${TMP_ROOT}/after-traps")" = "$(cat "${TMP_ROOT}/before-traps")" ] || fail "${_disposition} traps were not restored exactly"
	assert_trap_workspace_removed
}

set -e
ADGUARDHOME_DNS_HANDOFF_REQUIRED=0
export ADGUARDHOME_DNS_HANDOFF_REQUIRED

# Successful startup preserves each possible caller disposition.
for _disposition in custom ignored default; do
	rm -f "${STARTED_FILE}"
	PRECMD='pre_hook'
	POSTCMD='post_hook'
	run_with_trap_disposition "${_disposition}" 0
done

# Each ordinary failure path restores custom handlers and removes private state.
PRECMD='false'
rm -f "${STARTED_FILE}"
run_with_trap_disposition custom 255

PRECMD='pre_hook'
ADGUARDHOME_DNS_HANDOFF_REQUIRED=1
export ADGUARDHOME_DNS_HANDOFF_REQUIRED
rm -f "${STARTED_FILE}"
run_with_trap_disposition custom 255

ADGUARDHOME_DNS_HANDOFF_REQUIRED=0
export ADGUARDHOME_DNS_HANDOFF_REQUIRED
process_wait_for_start() { return 1; }
rm -f "${STARTED_FILE}"
run_with_trap_disposition custom 255

process_wait_for_start() { [ -f "${STARTED_FILE}" ]; }
POSTCMD='false'
rm -f "${STARTED_FILE}"
run_with_trap_disposition custom 255
POSTCMD='post_hook'

# interrupt_phase waits while the parent sends TERM during each startup phase.
interrupt_phase() {
	printf '%s\n' "interrupt ${INTERRUPT_PHASE}" >>"${CALLS_FILE}"
	: >"${INTERRUPT_READY_FILE}"
	while :; do
		sleep 1
	done
}

for INTERRUPT_PHASE in pre handoff launch post; do
	rm -f "${STARTED_FILE}"
	INTERRUPT_READY_FILE="${TMP_ROOT}/interrupt-ready-${INTERRUPT_PHASE}"
	INTERRUPT_BEFORE_FILE="${TMP_ROOT}/interrupt-before-${INTERRUPT_PHASE}"
	INTERRUPT_AFTER_FILE="${TMP_ROOT}/interrupt-after-${INTERRUPT_PHASE}"
	rm -f "${INTERRUPT_READY_FILE}" "${INTERRUPT_BEFORE_FILE}" "${INTERRUPT_AFTER_FILE}"
	PRECMD='pre_hook'
	POSTCMD='post_hook'
	ADGUARDHOME_DNS_HANDOFF_REQUIRED=0
	export ADGUARDHOME_DNS_HANDOFF_REQUIRED
	adguardhome_start_handoff_is_prepared() { return 1; }
	process_wait_for_start() {
		_start_waits=0
		while [ "${_start_waits}" -lt 100 ]; do
			[ -f "${STARTED_FILE}" ] && return 0
			_start_waits="$((_start_waits + 1))"
			sleep 0.01
		done
		return 1
	}
	case "${INTERRUPT_PHASE}" in
		pre) PRECMD='interrupt_phase' ;;
		handoff)
			HANDOFF_CHECKS=0
			adguardhome_start_handoff_is_prepared() {
				HANDOFF_CHECKS="$((HANDOFF_CHECKS + 1))"
				[ "${HANDOFF_CHECKS}" -eq 1 ] || interrupt_phase
				return 1
			}
			;;
		launch) process_wait_for_start() {
			interrupt_phase
			return 1
		} ;;
		post)
			HANDOFF_CHECKS=0
			adguardhome_start_handoff_is_prepared() {
				HANDOFF_CHECKS="$((HANDOFF_CHECKS + 1))"
				[ "${HANDOFF_CHECKS}" -gt 1 ]
			}
			POSTCMD='interrupt_phase'
			;;
	esac
	(
		trap 'printf "%s\n" caller_signal >>"${CALLS_FILE}"' HUP INT TERM
		trap_snapshot "${INTERRUPT_BEFORE_FILE}"
		trap 'trap_snapshot "${INTERRUPT_AFTER_FILE}"' 0
		set +e
		start >/dev/null
	) &
	_interrupt_pid="$!"
	_interrupt_waits=0
	while [ ! -f "${INTERRUPT_READY_FILE}" ] && [ "${_interrupt_waits}" -lt 100 ]; do
		sleep 0.01
		_interrupt_waits="$((_interrupt_waits + 1))"
	done
	[ -f "${INTERRUPT_READY_FILE}" ] || fail "${INTERRUPT_PHASE} interruption did not reach its startup phase"
	kill -TERM "${_interrupt_pid}" || fail "could not interrupt ${INTERRUPT_PHASE} startup phase"
	set +e
	wait "${_interrupt_pid}"
	_interrupt_status="$?"
	set -e
	[ "${_interrupt_status}" -eq 255 ] || fail "${INTERRUPT_PHASE} interruption returned ${_interrupt_status}"
	[ "$(cat "${INTERRUPT_AFTER_FILE}")" = "$(cat "${INTERRUPT_BEFORE_FILE}")" ] ||
		fail "${INTERRUPT_PHASE} interruption did not restore caller traps before exit"
	assert_trap_workspace_removed
done

# A repeated termination request during process shutdown or the post-failure
# hook must not bypass recovery or trap cleanup.
REPEAT_ARMED_FILE="${TMP_ROOT}/repeat-armed"
REPEAT_BEFORE_FILE="${TMP_ROOT}/repeat-before"
REPEAT_AFTER_FILE="${TMP_ROOT}/repeat-after"
REPEAT_READY_FILE="${TMP_ROOT}/repeat-ready"
for REPEAT_PHASE in stop postfail; do
	rm -f "${REPEAT_READY_FILE}" "${REPEAT_ARMED_FILE}" "${REPEAT_BEFORE_FILE}" "${REPEAT_AFTER_FILE}" "${STARTED_FILE}"
	: >"${CALLS_FILE}"
	(
		trap 'printf "%s\n" caller_signal >>"${CALLS_FILE}"' HUP INT TERM
		trap_snapshot "${REPEAT_BEFORE_FILE}"
		stop_launched_process() {
			if [ "${REPEAT_PHASE}" = "stop" ]; then
				: >"${REPEAT_READY_FILE}"
				sleep 1
			fi
		}
		post_failure_hook() {
			if [ "${REPEAT_PHASE}" = "postfail" ]; then
				: >"${REPEAT_READY_FILE}"
				sleep 1
			fi
			printf '%s\n' repeat_post_failure >>"${CALLS_FILE}"
		}
		trap 'trap_snapshot "${REPEAT_AFTER_FILE}"' 0
		adguardhome_start_traps_save || exit 1
		trap 'adguardhome_start_signal_abort' HUP INT TERM
		: >"${REPEAT_ARMED_FILE}"
		while :; do sleep 1; done
	) &
	_repeat_pid="$!"
	_repeat_waits=0
	while [ ! -f "${REPEAT_ARMED_FILE}" ] && [ "${_repeat_waits}" -lt 100 ]; do
		sleep 0.01
		_repeat_waits="$((_repeat_waits + 1))"
	done
	[ -f "${REPEAT_ARMED_FILE}" ] || fail 'repeated-signal test did not arm its startup trap'
	kill -TERM "${_repeat_pid}" || fail 'could not start repeated-signal recovery'
	_repeat_waits=0
	while [ ! -f "${REPEAT_READY_FILE}" ] && [ "${_repeat_waits}" -lt 100 ]; do
		sleep 0.01
		_repeat_waits="$((_repeat_waits + 1))"
	done
	[ -f "${REPEAT_READY_FILE}" ] || fail "signal recovery did not reach ${REPEAT_PHASE}"
	kill -TERM "${_repeat_pid}" || fail "could not repeat signal during ${REPEAT_PHASE}"
	set +e
	wait "${_repeat_pid}"
	_repeat_status="$?"
	set -e
	[ "${_repeat_status}" -eq 255 ] || fail "${REPEAT_PHASE} repeated-signal recovery returned ${_repeat_status}"
	grep -q '^repeat_post_failure$' "${CALLS_FILE}" || fail "${REPEAT_PHASE} repeated signal skipped post-failure recovery"
	[ "$(cat "${REPEAT_AFTER_FILE}")" = "$(cat "${REPEAT_BEFORE_FILE}")" ] ||
		fail "${REPEAT_PHASE} repeated signal prevented caller trap restoration"
	assert_trap_workspace_removed
done

printf '%s\n' 'PASS: rc.func independently enforces required DNS handoff preparation'
