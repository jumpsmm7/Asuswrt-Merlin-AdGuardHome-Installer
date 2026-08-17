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
WATCHDOG_PID=""
WORKSPACE_CREATED=0

cleanup() {
	trap '' HUP INT TERM
	if [ -n "${WATCHDOG_PID:-}" ]; then
		signal_process_tree TERM "${WATCHDOG_PID}"
		signal_process_tree KILL "${WATCHDOG_PID}"
		wait "${WATCHDOG_PID}" 2>/dev/null || true
		WATCHDOG_PID=""
	fi
	if [ -n "${CASE_PID:-}" ]; then
		signal_process_tree TERM "${CASE_PID}"
		signal_process_tree KILL "${CASE_PID}"
		wait "${CASE_PID}" 2>/dev/null || true
		CASE_PID=""
	fi
	if [ "${WORKSPACE_CREATED:-0}" -eq 1 ]; then
		rm -rf "${SUITE_TMP}"
		WORKSPACE_CREATED=0
	fi
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

# signal_process_tree signals descendants before their parent.  Reading PPid
# from procfs avoids setsid(1), which is not part of the router stock command
# inventory, and prevents background test helpers surviving a timed-out case.
signal_process_tree() {
	tree_signal="$1"
	parent_pid="$2"
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
			(signal_process_tree "${tree_signal}" "${child_pid}")
		fi
	done
	kill "-${tree_signal}" "${parent_pid}" 2>/dev/null || true
}

# run_bounded runs one integration scenario with a portable watchdog.  It does
# not depend on timeout(1), which is not available in the router stock PATH.
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
	(
		elapsed=0
		while [ "${elapsed}" -lt "${TIMEOUT_SECONDS}" ]; do
			kill -0 "${case_pid}" 2>/dev/null || exit 0
			sleep 1
			elapsed=$((elapsed + 1))
		done
		kill -0 "${case_pid}" 2>/dev/null || exit 0
		: >"${timed_out}"
		signal_process_tree TERM "${case_pid}"
		sleep 2
		signal_process_tree KILL "${case_pid}"
	) &
	watchdog_pid=$!
	WATCHDOG_PID="${watchdog_pid}"

	case_status=0
	wait "${case_pid}" || case_status=$?
	CASE_PID=""
	wait "${watchdog_pid}" || true
	WATCHDOG_PID=""

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
