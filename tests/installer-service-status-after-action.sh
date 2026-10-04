#!/bin/sh
# Verify installer service action status waits before reporting transitional states.

set -u

SCRIPT_PATH="${1:-installer}"
TEST_ROOT="${TMPDIR:-/tmp}/installer-service-status-after-action.$$"
FUNCTIONS_FILE="${TEST_ROOT}/functions"
CALLS_FILE="${TEST_ROOT}/calls"

cleanup() {
	rm -rf "${TEST_ROOT}"
}

# Print the supplied failure message to stderr and exit the test with status 1.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
mkdir -p "${TEST_ROOT}" || fail 'could not create test directory'

sed -n '/^adguard_pid_list_has_new_pid() {$/,/^valid_adguardhome_username() {$/p' "${SCRIPT_PATH}" | sed '$d' >"${FUNCTIONS_FILE}" ||
	fail "could not read ${SCRIPT_PATH}"
sed -n '/^adguard_service_without_nvram_lock_fd() {$/,/^agh_restart() {$/p' "${SCRIPT_PATH}" | sed '$d' >>"${FUNCTIONS_FILE}" ||
	fail "could not read service request helpers from ${SCRIPT_PATH}"
sed -n '/^agh_start_transition_active() {$/,/^}$/p' "${SCRIPT_PATH}" >>"${FUNCTIONS_FILE}" ||
	fail "could not read start transition helper from ${SCRIPT_PATH}"
[ -s "${FUNCTIONS_FILE}" ] || fail 'service status helper was not found'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

INFO='Info:'
ADGUARDHOME_WAIT_TIMEOUT=60
ADGUARDHOME_FIRMWARE_WAIT_TIMEOUT=15
PROCESS_STATE='stopped'
PROCESS_COUNT='0'
CURRENT_PIDS=''
MONITOR_COUNT='0'
SLEEP_CALLS=0

PTXT() {
	printf '%s\n' "$*" >>"${CALLS_FILE}"
}

sleep() {
	SLEEP_CALLS="$((SLEEP_CALLS + 1))"
	if [ "${START_AFTER_SLEEP:-0}" -gt 0 ] && [ "${SLEEP_CALLS}" -ge "${START_AFTER_SLEEP}" ]; then
		PROCESS_STATE='running'
		PROCESS_COUNT='1'
	fi
	if [ "${STOP_AFTER_SLEEP:-0}" -gt 0 ] && [ "${SLEEP_CALLS}" -ge "${STOP_AFTER_SLEEP}" ]; then
		PROCESS_STATE='stopped'
		PROCESS_COUNT='0'
		CURRENT_PIDS=''
	fi
	if [ "${NEW_PID_AFTER_SLEEP:-0}" -gt 0 ] && [ "${SLEEP_CALLS}" -ge "${NEW_PID_AFTER_SLEEP}" ]; then
		PROCESS_STATE='running'
		PROCESS_COUNT='1'
		CURRENT_PIDS='222'
	fi
}

# Print the simulated daemon PIDs when $1 is AdGuardHome; otherwise emit nothing.
pidof() {
	if [ "${1:-}" = 'AdGuardHome' ]; then
		printf '%s\n' "${CURRENT_PIDS}"
	fi
}

# Succeed when the simulated daemon state is running.
agh_is_running() {
	[ "${PROCESS_STATE}" = 'running' ]
}

# Poll the simulated daemon for $1 seconds (default ADGUARDHOME_WAIT_TIMEOUT);
# return success when running, or failure when the simulated wait expires.
agh_wait_started() {
	local elapsed maxwait
	elapsed=0
	maxwait="${1:-${ADGUARDHOME_WAIT_TIMEOUT}}"
	while ! agh_is_running; do
		if [ "${elapsed}" -ge "${maxwait}" ]; then
			return 1
		fi
		sleep 1s
		elapsed="$((elapsed + 1))"
	done
	return 0
}

# Print the simulated process count used by service status checks.
agh_process_count() {
	printf '%s\n' "${PROCESS_COUNT}"
}

# Print the simulated managed-monitor count used by the start transition check.
agh_monitor_count() {
	printf '%s\n' "${MONITOR_COUNT}"
}

# Record that the installer requested a final service status report.
agh_check() {
	printf '%s\n' 'check' >>"${CALLS_FILE}"
}

: >"${CALLS_FILE}"
PROCESS_STATE='stopped'
PROCESS_COUNT='0'
START_AFTER_SLEEP=2
STOP_AFTER_SLEEP=0
NEW_PID_AFTER_SLEEP=0
CURRENT_PIDS=''
SLEEP_CALLS=0
adguard_service_status_after_action restart || fail 'restart helper did not wait for a delayed running process'
grep -q 'Waiting for AdGuardHome to report running state after restart' "${CALLS_FILE}" ||
	fail 'restart helper did not print the restart wait message'
[ "${SLEEP_CALLS}" -eq 2 ] || fail 'restart helper did not poll until the process became running'
grep -q '^check$' "${CALLS_FILE}" || fail 'restart helper did not print service status after settling'
! grep -q 'Restarting\.\.\.' "${CALLS_FILE}" || fail 'restart helper reported transitional state after the process settled'

: >"${CALLS_FILE}"
PROCESS_STATE='running'
PROCESS_COUNT='1'
CURRENT_PIDS='111'
START_AFTER_SLEEP=0
STOP_AFTER_SLEEP=0
NEW_PID_AFTER_SLEEP=3
SLEEP_CALLS=0
adguard_service_status_after_action restart '111' || fail 'restart helper did not wait for a new daemon PID'
[ "${SLEEP_CALLS}" -eq 3 ] || fail 'restart helper accepted the pre-restart daemon PID'
grep -q '^check$' "${CALLS_FILE}" || fail 'restart helper did not print service status after daemon PID changed'

: >"${CALLS_FILE}"
PROCESS_STATE='stopped'
PROCESS_COUNT='0'
CURRENT_PIDS=''
START_AFTER_SLEEP=0
STOP_AFTER_SLEEP=0
NEW_PID_AFTER_SLEEP=0
SLEEP_CALLS=0
if adguard_service_status_after_action start; then
	fail 'start helper succeeded while the process never appeared'
fi
grep -q 'Waiting for AdGuardHome to report running state after start' "${CALLS_FILE}" ||
	fail 'start helper did not print the start wait message'
grep -q 'Restarting\.\.\.' "${CALLS_FILE}" || fail 'start helper did not report the transitional restart state'
[ "${SLEEP_CALLS}" -eq "${ADGUARDHOME_FIRMWARE_WAIT_TIMEOUT}" ] || fail 'start helper did not cap the firmware poll at its configured grace period'
! grep -q '^check$' "${CALLS_FILE}" || fail 'start helper printed final status before the process settled'

: >"${CALLS_FILE}"
PROCESS_STATE='running'
PROCESS_COUNT='1'
START_AFTER_SLEEP=0
STOP_AFTER_SLEEP=3
NEW_PID_AFTER_SLEEP=0
SLEEP_CALLS=0
adguard_service_status_after_action stop || fail 'stop helper did not wait for a delayed stopped process'
grep -q 'Waiting for AdGuardHome to stop cleanly' "${CALLS_FILE}" ||
	fail 'stop helper did not print the stop wait message'
[ "${SLEEP_CALLS}" -eq 3 ] || fail 'stop helper did not poll until the process disappeared'
grep -q '^check$' "${CALLS_FILE}" || fail 'stop helper did not print service status after settling'

: >"${CALLS_FILE}"
PROCESS_STATE='running'
PROCESS_COUNT='1'
START_AFTER_SLEEP=0
STOP_AFTER_SLEEP=0
NEW_PID_AFTER_SLEEP=0
SLEEP_CALLS=0
if adguard_service_status_after_action stop; then
	fail 'stop helper succeeded while the process remained active'
fi
grep -q 'Stopping\.\.\.' "${CALLS_FILE}" || fail 'stop helper did not report the transitional stopping state'
[ "${SLEEP_CALLS}" -eq "${ADGUARDHOME_FIRMWARE_WAIT_TIMEOUT}" ] || fail 'stop helper did not cap the firmware poll at its configured grace period'
! grep -q '^check$' "${CALLS_FILE}" || fail 'stop helper printed final status before the process stopped'

ptxt_step() {
	printf '%s\n' "$*" >>"${CALLS_FILE}"
}

# A firmware stop that outlasts its grace period must switch to a separately
# labelled direct-init poll with the full fallback timeout.
(
	STOP_PHASE=firmware
	STOP_POLLS=0
	: >"${CALLS_FILE}"
	# Accept stop requests and reset the poll counter when direct init takes over.
	adguard_service_without_nvram_lock_fd() {
		case "$*" in
			service\ stop_AdGuardHome)
				STOP_PHASE=firmware
				;;
			/opt/etc/init.d/S99AdGuardHome\ stop\ x)
				STOP_PHASE=fallback
				STOP_POLLS=0
				;;
			*) fail "unexpected stop command: $*" ;;
		esac
		return 0
	}
	# Report one process until the direct-init phase has completed 16 polls.
	agh_process_count() {
		if [ "${STOP_PHASE}" = fallback ] && [ "${STOP_POLLS}" -ge 16 ]; then
			printf '%s\n' 0
		else
			printf '%s\n' 1
		fi
	}
	# Advance the stop poll counter without waiting in real time.
	sleep() { STOP_POLLS="$((STOP_POLLS + 1))"; }
	agh_request_stop || fail 'direct stop fallback did not finish after the firmware grace period'
	grep -q 'Waiting for AdGuardHome to stop cleanly (firmware service)' "${CALLS_FILE}" ||
		fail 'firmware stop poll was not labelled'
	grep -q 'Waiting for AdGuardHome to stop cleanly (direct init fallback)' "${CALLS_FILE}" ||
		fail 'direct stop fallback poll was not labelled'
) || fail 'firmware and fallback stop polling regression failed'

# Log command arguments and simulate immediate state changes for direct init actions.
adguard_service_without_nvram_lock_fd() {
	printf '%s\n' "$*" >>"${CALLS_FILE}"
	case "$*" in
		/opt/etc/init.d/S99AdGuardHome\ start\ x)
			PROCESS_STATE='running'
			PROCESS_COUNT='1'
			CURRENT_PIDS='222'
			;;
		/opt/etc/init.d/S99AdGuardHome\ restart\ x)
			PROCESS_STATE='running'
			PROCESS_COUNT='1'
			CURRENT_PIDS='333'
			;;
		/opt/etc/init.d/S99AdGuardHome\ stop\ x)
			PROCESS_STATE='stopped'
			PROCESS_COUNT='0'
			CURRENT_PIDS=''
			;;
		*) ;;
	esac
	return 0
}

: >"${CALLS_FILE}"
PROCESS_STATE='stopped'
PROCESS_COUNT='0'
CURRENT_PIDS=''
SLEEP_CALLS=0
agh_request_start || fail 'start request did not recover from an uncompleted firmware service event'
grep -q '^service start_AdGuardHome$' "${CALLS_FILE}" || fail 'start request did not try the firmware service event'
grep -q '^/opt/etc/init.d/S99AdGuardHome start x$' "${CALLS_FILE}" ||
	fail 'start request did not fall back to the direct init script'
[ "${CURRENT_PIDS}" = '222' ] || fail 'direct start fallback did not produce the replacement daemon'

: >"${CALLS_FILE}"
PROCESS_STATE='stopped'
PROCESS_COUNT='0'
CURRENT_PIDS=''
MONITOR_COUNT='1'
START_AFTER_SLEEP="$((ADGUARDHOME_FIRMWARE_WAIT_TIMEOUT + ADGUARDHOME_WAIT_TIMEOUT))"
SLEEP_CALLS=0
agh_request_start || fail 'start request rejected an active firmware monitor'
! grep -q '^/opt/etc/init.d/S99AdGuardHome start x$' "${CALLS_FILE}" ||
	fail 'start request duplicated an active firmware monitor with direct init'
grep -q 'Firmware service start is still in progress' "${CALLS_FILE}" ||
	fail 'start request did not report the active firmware monitor'
[ "${SLEEP_CALLS}" -eq "$((ADGUARDHOME_FIRMWARE_WAIT_TIMEOUT + ADGUARDHOME_WAIT_TIMEOUT))" ] ||
	fail 'start request did not wait through the managed monitor startup budget'
MONITOR_COUNT='0'

# A managed monitor that never creates the daemon must still fall back after
# the bounded managed-start wait expires.
(
	ADGUARDHOME_WAIT_TIMEOUT=3
	: >"${CALLS_FILE}"
	PROCESS_STATE='stopped'
	PROCESS_COUNT='0'
	CURRENT_PIDS=''
	MONITOR_COUNT='1'
	START_AFTER_SLEEP=0
	SLEEP_CALLS=0
	agh_request_start || fail 'start request did not recover after the managed monitor wait expired'
	grep -q '^/opt/etc/init.d/S99AdGuardHome start x$' "${CALLS_FILE}" ||
		fail 'start request did not fall back after the managed monitor wait expired'
	[ "${SLEEP_CALLS}" -eq "$((ADGUARDHOME_WAIT_TIMEOUT * 2))" ] ||
		fail 'start request did not enforce the managed monitor startup budget'
) || fail 'managed monitor startup timeout regression failed'
START_AFTER_SLEEP=0

: >"${CALLS_FILE}"
PROCESS_STATE='running'
PROCESS_COUNT='1'
CURRENT_PIDS='111'
SLEEP_CALLS=0
agh_request_restart '111' || fail 'restart request did not recover from an uncompleted firmware service event'
grep -q '^service restart_AdGuardHome$' "${CALLS_FILE}" || fail 'restart request did not try the firmware service event'
grep -q '^/opt/etc/init.d/S99AdGuardHome restart x$' "${CALLS_FILE}" ||
	fail 'restart request did not fall back to the direct init script'
[ "${CURRENT_PIDS}" = '333' ] || fail 'direct restart fallback did not produce a replacement daemon'

: >"${CALLS_FILE}"
PROCESS_STATE='running'
PROCESS_COUNT='2'
CURRENT_PIDS='333'
SLEEP_CALLS=0
agh_request_stop || fail 'stop request did not recover from an uncompleted firmware service event'
grep -q '^service stop_AdGuardHome$' "${CALLS_FILE}" || fail 'stop request did not try the firmware service event'
grep -q '^/opt/etc/init.d/S99AdGuardHome stop x$' "${CALLS_FILE}" ||
	fail 'stop request did not fall back to the direct init script'
[ "${PROCESS_COUNT}" = '0' ] || fail 'direct stop fallback left the service or monitor running'

# Direct dispatch queues monitor work. Startup may outlast the firmware grace
# period, and restart must wait for a replacement PID rather than the original daemon.
for requested_action in start restart; do
	(
		# Accept and log queued actions; the sleep stub controls their completion.
		adguard_service_without_nvram_lock_fd() {
			printf '%s\n' "$*" >>"${CALLS_FILE}"
			return 0
		}
		START_AFTER_SLEEP=0
		STOP_AFTER_SLEEP=0
		NEW_PID_AFTER_SLEEP=13
		SLEEP_CALLS=0
		CURRENT_PIDS=''
		PROCESS_STATE=stopped
		if [ "${requested_action}" = restart ]; then
			CURRENT_PIDS=111
			PROCESS_STATE=running
		fi
		: >"${CALLS_FILE}"
		"agh_request_${requested_action}" 111 || fail "${requested_action} abandoned delayed monitor startup"
		[ "${SLEEP_CALLS}" -eq 13 ] || fail "${requested_action} did not wait for monitor completion"
		[ "${CURRENT_PIDS}" = 222 ] || fail "${requested_action} accepted the old daemon"
		! grep -qx "/opt/etc/init.d/S99AdGuardHome ${requested_action} x" "${CALLS_FILE}" ||
			fail "${requested_action} fell back before the firmware grace period elapsed"

		# A queued action that never creates a replacement must still fail within
		# the firmware grace period plus the bounded direct-start budget.
		NEW_PID_AFTER_SLEEP=0
		SLEEP_CALLS=0
		CURRENT_PIDS=''
		PROCESS_STATE=stopped
		if [ "${requested_action}" = restart ]; then
			CURRENT_PIDS=111
			PROCESS_STATE=running
		fi
		if "agh_request_${requested_action}" 111; then
			fail "${requested_action} succeeded without a replacement daemon"
		fi
		[ "${SLEEP_CALLS}" -eq "$((ADGUARDHOME_FIRMWARE_WAIT_TIMEOUT + ADGUARDHOME_WAIT_TIMEOUT))" ] ||
			fail "${requested_action} did not enforce its completion timeout"
	) || fail "delayed ${requested_action} regression failed"
done

# Exercise the actual runtime dispatcher as well: S99AdGuardHome sources this
# tail, which sends actions without x straight back to firmware service events.
# Router operations are stubbed, but argument forwarding and dispatch are real.
RUNTIME_PATH="${SCRIPT_PATH%/*}/AdGuardHome.sh"
[ "${SCRIPT_PATH}" != "${SCRIPT_PATH%/*}" ] || RUNTIME_PATH=AdGuardHome.sh
DISPATCH_FILE="${TEST_ROOT}/dispatch.sh"
INIT_FILE="${TEST_ROOT}/S99AdGuardHome"
STATE_FILE="${TEST_ROOT}/state"
MONITOR_STATE_FILE="${TEST_ROOT}/monitor-state"
STOPPED_MONITORS_FILE="${TEST_ROOT}/stopped-monitors"
DISPATCH_STDERR="${TEST_ROOT}/dispatch-stderr"
sed -n '/^adguard_monitor_pids() {$/,/^}$/p; /^stop_all_monitors() {$/,/^}$/p; /^[{] for PID in \$(adguard_monitor_pids); do/p' "${RUNTIME_PATH}" >"${DISPATCH_FILE}" ||
	fail 'could not extract runtime monitor helpers'
sed -n '/^case "${1:-}" in$/,$p' "${RUNTIME_PATH}" >>"${DISPATCH_FILE}" ||
	fail 'could not extract runtime action dispatcher'
grep -q 'service "${1}"_AdGuardHome' "${DISPATCH_FILE}" ||
	fail 'runtime action dispatcher extraction omitted firmware delegation'
cat >"${INIT_FILE}" <<'EOF'
#!/bin/sh
SCRIPT_LOC="$0"
UPPER_SCRIPT="$0"
LOWER_SCRIPT="${TEST_ROOT}/unused-lower-script"
PROCS=AdGuardHome
MON_PID=""
DIRECT_ACTION="${DIRECT_ACTION:-${1:-}}"
export DIRECT_ACTION
# Accept configuration loading without reading router files.
load_operation_config() { return 0; }
# Report dependencies available so dispatch can run in the fixture.
manager_dependencies_available() { return 0; }
# Echo $1 unchanged; fixture paths are already suitable for identity checks.
canonical_path() { printf '%s\n' "$1"; }
# Return simulated monitor candidates for the managed entry-point names when
# discovery is enabled, including an optional unrelated PID for filtering checks.
pidof() {
	[ "${DISCOVER_MONITORS:-0}" = 1 ] || return 1
	[ "$*" = "S99${PROCS} AdGuardHome.sh rc.func.${PROCS}" ] || return 1
	cat "${MONITOR_STATE_FILE}"
	[ -z "${EXTRA_MONITOR_PID:-}" ] || printf '%s\n' "${EXTRA_MONITOR_PID}"
}
# Succeed only when the supplied PID belongs to a simulated active monitor.
monitor_process_matches() {
	for monitor_pid in $(cat "${MONITOR_STATE_FILE}"); do
		[ "${monitor_pid}" = "${1:-}" ] && return 0
	done
	return 1
}
# Simulate reading /proc/<pid>/cmdline: emit monitor-start for active monitor
# PIDs and fail for unrelated PIDs or unsupported paths.
awk() {
	case "${2:-}" in
		/proc/*/cmdline)
			monitor_pid="${2#/proc/}"
			monitor_pid="${monitor_pid%/cmdline}"
			if monitor_process_matches "${monitor_pid}"; then
				printf '%s\n' monitor-start
			else
				printf '%s\n' "awk: /proc/${monitor_pid}/cmdline: No such file or directory" >&2
				return 1
			fi
			;;
		*) return 1 ;;
	esac
}
# Accept timezone setup without changing the host environment.
timezone() { :; }
# Accept process tuning without changing host procfs settings.
proc_optimizations() { :; }
# Accept process restoration without changing host procfs settings.
proc_restore() { :; }
# Log firmware service requests without dispatching real router actions.
service() { printf '%s\n' "service $*" >>"${CALLS_FILE}"; }
# Record a monitor PID and a daemon PID selected by the requested start/restart.
start_monitor() {
	printf '%s\n' 444 >"${MONITOR_STATE_FILE}"
	case "${DIRECT_ACTION}" in
		restart) printf '%s\n' 333 >"${STATE_FILE}" ;;
		*) printf '%s\n' 222 >"${STATE_FILE}" ;;
	esac
}
# Stop the monitor selected by MON_PID and clear the simulated daemon state;
# record each stopped PID, or fail when direct-stop failure is requested.
stop_monitor() {
	[ "${FAIL_DIRECT_STOP:-0}:${DIRECT_ACTION}" != '1:stop' ] || return 1
	printf '%s\n' "${MON_PID}" >>"${STOPPED_MONITORS_FILE}"
	remaining_pids=""
	for monitor_pid in $(cat "${MONITOR_STATE_FILE}"); do
		[ "${monitor_pid}" = "${MON_PID}" ] || remaining_pids="${remaining_pids}${remaining_pids:+ }${monitor_pid}"
	done
	: >"${STATE_FILE}"
	printf '%s\n' "${remaining_pids}" >"${MONITOR_STATE_FILE}"
}
# Record the requested daemon action and simulate cleanup by clearing its state.
adguardhome_run() {
	printf '%s\n' "adguardhome_run $*" >>"${CALLS_FILE}"
	: >"${STATE_FILE}"
}
# shellcheck disable=SC1090
. "${DISPATCH_FILE}"
EOF
chmod 700 "${INIT_FILE}" || fail 'could not prepare simulated init entry point'
export TEST_ROOT DISPATCH_FILE CALLS_FILE STATE_FILE MONITOR_STATE_FILE STOPPED_MONITORS_FILE

# Log firmware requests and route direct init arguments through the real dispatcher;
# return its status, or fail the test for an unexpected command.
adguard_service_without_nvram_lock_fd() {
	case "${1:-}" in
		service)
			printf '%s\n' "$*" >>"${CALLS_FILE}"
			;;
		/opt/etc/init.d/S99AdGuardHome)
			printf '%s\n' "$*" >>"${CALLS_FILE}"
			shift
			"${INIT_FILE}" "$@"
			;;
		*) fail "unexpected service command: $*" ;;
	esac
}
# Print the simulated daemon PIDs recorded by the runtime dispatcher fixture.
pidof() { cat "${STATE_FILE}"; }
# Succeed when the fixture's daemon state file contains a PID.
agh_is_running() { [ -s "${STATE_FILE}" ]; }
# Print the combined daemon and monitor PID count from the fixture state files.
agh_process_count() { cat "${STATE_FILE}" "${MONITOR_STATE_FILE}" | wc -w; }
# Wait one real second per poll so asynchronous dispatcher work can complete.
sleep() { command sleep 1; }

# Confirm the fixture retains the real gate before checking the bypass path.
: >"${CALLS_FILE}"
: >"${STATE_FILE}"
: >"${MONITOR_STATE_FILE}"
"${INIT_FILE}" start || fail 'runtime firmware delegation failed'
grep -qx 'service start_AdGuardHome' "${CALLS_FILE}" ||
	fail 'runtime dispatcher did not retain its normal firmware delegation'
[ ! -s "${STATE_FILE}" ] || fail 'ordinary init action bypassed firmware dispatch'

for action in start restart stop kill; do
	: >"${CALLS_FILE}"
	: >"${STOPPED_MONITORS_FILE}"
	FAIL_DIRECT_STOP=0
	DISCOVER_MONITORS=0
	EXTRA_MONITOR_PID=""
	export FAIL_DIRECT_STOP DISCOVER_MONITORS EXTRA_MONITOR_PID
	case "${action}" in
		start)
			: >"${STATE_FILE}"
			agh_request_start || fail 'direct start fallback did not reach runtime startup'
			[ "$(cat "${STATE_FILE}")" = 222 ] || fail 'direct start did not create the daemon'
			;;
		restart)
			printf '%s\n' 111 >"${STATE_FILE}"
			agh_request_restart 111 || fail 'direct restart fallback did not reach runtime startup'
			[ "$(cat "${STATE_FILE}")" = 333 ] || fail 'direct restart did not replace the daemon'
			;;
		stop | kill)
			[ "${action}" != kill ] || FAIL_DIRECT_STOP=1
			DISCOVER_MONITORS=1
			EXTRA_MONITOR_PID=999
			if [ "${action}" = stop ]; then
				# A stopped daemon still has a live monitor that can respawn it.
				: >"${STATE_FILE}"
			else
				printf '%s\n' 111 >"${STATE_FILE}"
			fi
			printf '%s\n' '456 457 458' >"${MONITOR_STATE_FILE}"
			: >"${DISPATCH_STDERR}"
			agh_request_stop 2>"${DISPATCH_STDERR}" || fail "direct ${action} fallback did not reach runtime shutdown"
			[ ! -s "${DISPATCH_STDERR}" ] || fail "direct ${action} leaked procfs discovery diagnostics"
			[ ! -s "${STATE_FILE}" ] || fail "direct ${action} left the daemon running"
			[ -z "$(cat "${MONITOR_STATE_FILE}")" ] || fail "direct ${action} left a monitor running"
			[ "$(wc -l <"${STOPPED_MONITORS_FILE}")" -eq 3 ] || fail "direct ${action} did not stop every monitor"
			for monitor_pid in 456 457 458; do
				grep -qx "${monitor_pid}" "${STOPPED_MONITORS_FILE}" || fail "direct ${action} skipped monitor ${monitor_pid}"
			done
			;;
	esac
	[ "$(grep -c '^service ' "${CALLS_FILE}")" -eq 1 ] ||
		fail "direct ${action} fallback requeued the firmware service event"
	grep -qx "/opt/etc/init.d/S99AdGuardHome ${action} x" "${CALLS_FILE}" ||
		fail "direct ${action} fallback did not pass the runtime bypass argument"
done

# With no monitor present, the direct stop still runs the daemon cleanup.
: >"${CALLS_FILE}"
: >"${MONITOR_STATE_FILE}"
printf '%s\n' 111 >"${STATE_FILE}"
DISCOVER_MONITORS=1
EXTRA_MONITOR_PID=""
export DISCOVER_MONITORS EXTRA_MONITOR_PID
"${INIT_FILE}" stop x || fail 'direct stop without a monitor failed'
grep -qx 'adguardhome_run stop_adguardhome' "${CALLS_FILE}" ||
	fail 'direct stop without a monitor skipped daemon cleanup'
[ ! -s "${STATE_FILE}" ] || fail 'direct stop without a monitor left the daemon running'

printf '%s\n' 'PASS: installer service status helper waits through transitional states'
