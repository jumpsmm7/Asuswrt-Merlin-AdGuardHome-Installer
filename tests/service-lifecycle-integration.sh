#!/bin/sh
# Run the bounded, router-service integration matrix as one regression suite.

set -u

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd) || exit 1
SUITE_TMP="${TMPDIR:-/tmp}/agh-integration.$$"
RESULTS_FILE="${SUITE_TMP}/results"
TIMEOUT_SECONDS="${AGH_INTEGRATION_TIMEOUT:-90}"
TEST_SHELL="${AGH_INTEGRATION_SHELL:-sh}"
TEST_SHELL_ARG="${AGH_INTEGRATION_SHELL_ARG:-}"
CASE_PID=""
CASE_START_TIME=""
WATCHDOG_PID=""
WATCHDOG_START_TIME=""
WORKSPACE_CREATED=0

# cleanup stops active test and watchdog processes and removes the temporary workspace.
cleanup() {
	trap '' HUP INT TERM
	if [ -n "${WATCHDOG_PID:-}" ]; then
		if [ -n "${WATCHDOG_START_TIME:-}" ] && capture_process_tree "${WATCHDOG_PID}" "${SUITE_TMP}/cleanup-watchdog.pids" "${WATCHDOG_START_TIME}"; then
			signal_process_snapshot TERM "${SUITE_TMP}/cleanup-watchdog.pids"
			signal_process_snapshot KILL "${SUITE_TMP}/cleanup-watchdog.pids"
		fi
		wait "${WATCHDOG_PID}" 2>/dev/null || true
		WATCHDOG_PID=""
		WATCHDOG_START_TIME=""
	fi
	if [ -n "${CASE_PID:-}" ]; then
		if [ -n "${CASE_START_TIME:-}" ] && capture_process_tree "${CASE_PID}" "${SUITE_TMP}/cleanup-case.pids" "${CASE_START_TIME}"; then
			signal_process_snapshot TERM "${SUITE_TMP}/cleanup-case.pids"
			signal_process_snapshot KILL "${SUITE_TMP}/cleanup-case.pids"
		fi
		wait "${CASE_PID}" 2>/dev/null || true
		CASE_PID=""
		CASE_START_TIME=""
	fi
	if [ "${WORKSPACE_CREATED:-0}" -eq 1 ]; then
		rm -rf "${SUITE_TMP}"
		WORKSPACE_CREATED=0
	fi
}

# fail reports an error message to standard error and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

# process_start_time prints the kernel start time for a PID so a retained PID
# process_start_time prints the kernel start time recorded for a process ID.
process_start_time() {
	[ -r "/proc/$1/stat" ] || return 1
	IFS= read -r process_stat <"/proc/$1/stat" || return 1
	process_stat=${process_stat##*) }
	# Intentional field splitting: start time is field 20 after the comm value.
	# shellcheck disable=SC2086
	set -- ${process_stat}
	process_field=1
	while [ "${process_field}" -lt 20 ]; do
		shift
		process_field=$((process_field + 1))
	done
	printf '%s\n' "$1"
}

# process_identity_matches verifies that a process has the recorded start time for the specified process ID.
process_identity_matches() {
	identity_pid="$1"
	identity_start_time="$2"
	[ -n "${identity_start_time}" ] || return 1
	current_start_time=$(process_start_time "${identity_pid}") || return 1
	[ "${current_start_time}" = "${identity_start_time}" ]
}

# append_process_tree records descendants before their parent.  The retained
# append_process_tree records a process and its descendants with their kernel start times, listing descendants before their parent.
append_process_tree() {
	parent_pid="$1"
	pid_file="$2"
	for status_file in /proc/[0-9]*/status; do
		[ -r "${status_file}" ] || continue
		child_pid=${status_file#/proc/}
		child_pid=${child_pid%/status}
		child_parent=""
		while read -r status_key status_value status_rest; do
			if [ "${status_key}" = 'PPid:' ]; then
				child_parent="${status_value}"
				break
			fi
		done <"${status_file}"
		if [ "${child_parent}" = "${parent_pid}" ]; then
			(append_process_tree "${child_pid}" "${pid_file}")
		fi
	done
	parent_start_time=$(process_start_time "${parent_pid}") || return 0
	printf '%s %s\n' "${parent_pid}" "${parent_start_time}" >>"${pid_file}"
}

# capture_process_tree records a process and its descendants, verifies the process identity before and after capture when an expected start time is provided, and writes the snapshot to a file.
capture_process_tree() {
	capture_pid="$1"
	capture_file="$2"
	expected_start_time="${3:-}"
	if [ -n "${expected_start_time}" ]; then
		process_identity_matches "${capture_pid}" "${expected_start_time}" || return 1
	fi
	: >"${capture_file}" || return 1
	append_process_tree "${capture_pid}" "${capture_file}"
	if [ -n "${expected_start_time}" ]; then
		process_identity_matches "${capture_pid}" "${expected_start_time}" || {
			: >"${capture_file}"
			return 1
		}
	fi
}

# signal_process_snapshot sends the specified signal to recorded processes whose identities still match.
signal_process_snapshot() {
	tree_signal="$1"
	pid_file="$2"
	[ -r "${pid_file}" ] || return 0
	while IFS=' ' read -r retained_pid retained_start_time; do
		[ -n "${retained_pid}" ] || continue
		current_start_time=$(process_start_time "${retained_pid}") || continue
		[ "${current_start_time}" = "${retained_start_time}" ] || continue
		kill "-${tree_signal}" "${retained_pid}" 2>/dev/null || true
	done <"${pid_file}"
}

# run_bounded runs one integration scenario with a portable watchdog.  It does
# run_bounded runs a test script within the configured timeout and records successful completion.
run_bounded() {
	case_name="$1"
	test_script="$2"
	case_output="${SUITE_TMP}/${case_name}.out"
	timed_out="${SUITE_TMP}/${case_name}.timeout"

	(
		cd "${ROOT_DIR}" || exit 1
		if [ -n "${TEST_SHELL_ARG}" ]; then
			exec "${TEST_SHELL}" "${TEST_SHELL_ARG}" "${test_script}"
		fi
		exec "${TEST_SHELL}" "${test_script}"
	) >"${case_output}" 2>&1 &
	case_pid=$!
	CASE_PID="${case_pid}"
	case_start_time=$(process_start_time "${case_pid}") || case_start_time=""
	CASE_START_TIME="${case_start_time}"
	(
		[ -n "${case_start_time}" ] || exit 0
		elapsed=0
		while [ "${elapsed}" -lt "${TIMEOUT_SECONDS}" ]; do
			process_identity_matches "${case_pid}" "${case_start_time}" || exit 0
			sleep 1
			elapsed=$((elapsed + 1))
		done
		process_identity_matches "${case_pid}" "${case_start_time}" || exit 0
		: >"${timed_out}"
		capture_process_tree "${case_pid}" "${case_output}.pids" "${case_start_time}" || exit 0
		signal_process_snapshot TERM "${case_output}.pids"
		sleep 2
		signal_process_snapshot KILL "${case_output}.pids"
	) &
	watchdog_pid=$!
	WATCHDOG_PID="${watchdog_pid}"
	WATCHDOG_START_TIME=$(process_start_time "${watchdog_pid}") || WATCHDOG_START_TIME=""

	case_status=0
	wait "${case_pid}" || case_status=$?
	CASE_PID=""
	CASE_START_TIME=""
	wait "${watchdog_pid}" || true
	WATCHDOG_PID=""
	WATCHDOG_START_TIME=""

	if [ -e "${timed_out}" ]; then
		cat "${case_output}" >&2
		fail "${case_name} exceeded ${TIMEOUT_SECONDS}s"
	fi
	if [ "${case_status}" -ne 0 ]; then
		cat "${case_output}" >&2
		fail "${case_name} exited with status ${case_status}"
	fi
	printf '%s\n' "PASS ${case_name}" | tee -a "${RESULTS_FILE}"
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
case "${TIMEOUT_SECONDS}" in
	'' | *[!0-9]*) fail 'AGH_INTEGRATION_TIMEOUT must be a positive integer' ;;
	0) fail 'AGH_INTEGRATION_TIMEOUT must be greater than zero' ;;
esac
umask 077
mkdir "${SUITE_TMP}" || fail 'could not create exclusive integration workspace'
WORKSPACE_CREATED=1
: >"${RESULTS_FILE}" || fail 'could not create result log'

# The component regressions use command shims and isolated filesystems.  Taken
# together they exercise the real extracted installer/service functions across
# the lifecycle and failure dimensions below without changing the host DNS or
# NVRAM state.
run_bounded artifacts tests/installer-file-failure-safety.sh
run_bounded upgrade_restart tests/installer-post-replace-restart.sh
run_bounded preflight_storage tests/installer-preflight-actions.sh
run_bounded readonly_jffs tests/installer-jffs-failure.sh
run_bounded yaml_hooks tests/installer-staged-yaml-validation.sh
run_bounded mode_matrix tests/s99-dns-mode-lifecycle.sh
run_bounded dns_handoff tests/dns-startup-handoff.sh
run_bounded netstat_matrix tests/s99-netstat-readiness.sh
run_bounded process_signals tests/rc-process-signaling.sh
run_bounded monitor_restart tests/monitor-retry-backoff.sh
run_bounded stop_failures tests/stop-adguardhome-failure.sh
run_bounded rollback_record tests/installer-doctor-rollback-result.sh
run_bounded rollback_cleanup tests/installer-end-op-rollback.sh
run_bounded interruption_restore tests/installer-interruption-restart.sh
run_bounded lock_matrix tests/installer-service-lock-fd.sh
run_bounded webui_failure tests/installer-web-port-failure.sh
run_bounded bind_matrix tests/installer-bind-addresses.sh
run_bounded dns_environment tests/installer-dns-environment-failure.sh
run_bounded runtime_modes tests/adguardhome-runtime-mode-helpers.sh
run_bounded custom_config tests/adguardhome-scoped-config.sh

[ "$(wc -l <"${RESULTS_FILE}")" -eq 20 ] || fail 'integration matrix did not complete every scenario group'
printf '%s\n' 'PASS: installer and service lifecycle integration matrix'
