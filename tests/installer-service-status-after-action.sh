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
[ -s "${FUNCTIONS_FILE}" ] || fail 'service status helper was not found'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

INFO='Info:'
ADGUARDHOME_WAIT_TIMEOUT=60
PROCESS_STATE='stopped'
PROCESS_COUNT='0'
CURRENT_PIDS=''
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

pidof() {
	if [ "${1:-}" = 'AdGuardHome' ]; then
		printf '%s\n' "${CURRENT_PIDS}"
	fi
}

agh_is_running() {
	[ "${PROCESS_STATE}" = 'running' ]
}

agh_process_count() {
	printf '%s\n' "${PROCESS_COUNT}"
}

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
[ "${SLEEP_CALLS}" -eq 5 ] || fail 'start helper did not cap the short poll at five seconds'
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
[ "${SLEEP_CALLS}" -eq 5 ] || fail 'stop helper did not cap the short poll at five seconds'
! grep -q '^check$' "${CALLS_FILE}" || fail 'stop helper printed final status before the process stopped'

ptxt_step() {
	printf '%s\n' "$*" >>"${CALLS_FILE}"
}

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

# Direct dispatch queues monitor work. Startup may outlast both short probes,
# and restart must wait for a replacement PID rather than the original daemon.
for requested_action in start restart; do
	(
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
		grep -qx "/opt/etc/init.d/S99AdGuardHome ${requested_action} x" "${CALLS_FILE}" ||
			fail "${requested_action} did not dispatch the direct fallback"

		# A queued action that never creates a replacement must still fail within
		# the initial five-second probe plus the bounded direct-start budget.
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
		[ "${SLEEP_CALLS}" -eq "$((5 + ADGUARDHOME_WAIT_TIMEOUT))" ] ||
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
sed -n '/^case "${1:-}" in$/,$p' "${RUNTIME_PATH}" >"${DISPATCH_FILE}" ||
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
load_operation_config() { return 0; }
manager_dependencies_available() { return 0; }
canonical_path() { printf '%s\n' "$1"; }
pidof() { return 1; }
timezone() { :; }
proc_optimizations() { :; }
proc_restore() { :; }
service() { printf '%s\n' "service $*" >>"${CALLS_FILE}"; }
start_monitor() {
	printf '%s\n' 444 >"${MONITOR_STATE_FILE}"
	case "${DIRECT_ACTION}" in
		restart) printf '%s\n' 333 >"${STATE_FILE}" ;;
		*) printf '%s\n' 222 >"${STATE_FILE}" ;;
	esac
}
stop_monitor() {
	[ "${FAIL_DIRECT_STOP:-0}:${DIRECT_ACTION}" != '1:stop' ] || return 1
	: >"${STATE_FILE}"
	: >"${MONITOR_STATE_FILE}"
}
# shellcheck disable=SC1090
. "${DISPATCH_FILE}"
EOF
chmod 700 "${INIT_FILE}" || fail 'could not prepare simulated init entry point'
export TEST_ROOT DISPATCH_FILE CALLS_FILE STATE_FILE MONITOR_STATE_FILE

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
pidof() { cat "${STATE_FILE}"; }
agh_is_running() { [ -s "${STATE_FILE}" ]; }
agh_process_count() { cat "${STATE_FILE}" "${MONITOR_STATE_FILE}" | wc -w; }
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
	FAIL_DIRECT_STOP=0
	export FAIL_DIRECT_STOP
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
			if [ "${action}" = stop ]; then
				# A stopped daemon still has a live monitor that can respawn it.
				: >"${STATE_FILE}"
			else
				printf '%s\n' 111 >"${STATE_FILE}"
			fi
			printf '%s\n' 444 >"${MONITOR_STATE_FILE}"
			agh_request_stop || fail "direct ${action} fallback did not reach runtime shutdown"
			[ ! -s "${STATE_FILE}" ] || fail "direct ${action} left the daemon running"
			[ ! -s "${MONITOR_STATE_FILE}" ] || fail "direct ${action} left the monitor running"
			;;
	esac
	[ "$(grep -c '^service ' "${CALLS_FILE}")" -eq 1 ] ||
		fail "direct ${action} fallback requeued the firmware service event"
	grep -qx "/opt/etc/init.d/S99AdGuardHome ${action} x" "${CALLS_FILE}" ||
		fail "direct ${action} fallback did not pass the runtime bypass argument"
done

printf '%s\n' 'PASS: installer service status helper waits through transitional states'
