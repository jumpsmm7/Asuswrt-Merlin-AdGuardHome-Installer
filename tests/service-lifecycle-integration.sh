#!/bin/sh
# Run the bounded, router-service integration matrix as one regression suite.

set -u

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd) || exit 1
SUITE_TMP="${TMPDIR:-/tmp}/agh-integration.$$"
RESULTS_FILE="${SUITE_TMP}/results"
TIMEOUT_SECONDS="${AGH_INTEGRATION_TIMEOUT:-180}"
TEST_SHELL="${AGH_INTEGRATION_SHELL:-sh}"
TEST_SHELL_ARG="${AGH_INTEGRATION_SHELL_ARG:-}"
CASE_PID=""
CASE_START_TIME=""
WATCHDOG_PID=""
WATCHDOG_START_TIME=""
SUITE_WATCHDOG_PID=""
SUITE_WATCHDOG_START_TIME=""
SUITE_START_TIME=""
WORKSPACE_CREATED=0
SCENARIO_COUNT=0
CASES_FIXTURE="${ROOT_DIR}/tests/fixtures/service-lifecycle-cases.tsv"
COVERAGE_FIXTURE="${ROOT_DIR}/tests/fixtures/service-lifecycle-coverage.tsv"

# cleanup stops active suite and case watchdogs and test processes, then removes the temporary workspace.
cleanup() {
	trap '' HUP INT TERM
	if [ -n "${SUITE_WATCHDOG_PID:-}" ]; then
		if [ -n "${SUITE_WATCHDOG_START_TIME:-}" ] && capture_process_tree "${SUITE_WATCHDOG_PID}" "${SUITE_TMP}/cleanup-suite-watchdog.pids" "${SUITE_WATCHDOG_START_TIME}"; then
			signal_process_snapshot TERM "${SUITE_TMP}/cleanup-suite-watchdog.pids"
			signal_process_snapshot KILL "${SUITE_TMP}/cleanup-suite-watchdog.pids"
		fi
		wait "${SUITE_WATCHDOG_PID}" 2>/dev/null || true
		SUITE_WATCHDOG_PID=""
		SUITE_WATCHDOG_START_TIME=""
	fi
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

# run_bounded runs a test script within the configured timeout, reports failures, and records successful completion.
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
	) </dev/null >"${case_output}" 2>&1 &
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
	printf '%s\n' "PASS ${case_name}" | tee -a "${RESULTS_FILE}" >/dev/null || fail "could not record ${case_name} result"
	SCENARIO_COUNT="$((SCENARIO_COUNT + 1))"
	printf '%s\n' "PASS ${case_name}"
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
SUITE_START_TIME=$(process_start_time "$$") || fail 'could not record integration suite process identity'
: >"${RESULTS_FILE}" || fail 'could not create result log'

# Validate the declarative matrix before starting it.  This keeps every requested
# lifecycle dimension tied to a bounded regression and prevents a renamed or
# removed component test from silently reducing integration coverage.
[ -r "${CASES_FIXTURE}" ] || fail "missing integration case fixture: ${CASES_FIXTURE}"
[ -r "${COVERAGE_FIXTURE}" ] || fail "missing integration coverage fixture: ${COVERAGE_FIXTURE}"
declared_case_count=$(awk 'NF && $1 !~ /^#/ { count++ } END { print count + 0 }' "${CASES_FIXTURE}") ||
	fail 'could not count integration cases'
[ "${declared_case_count}" -gt 0 ] || fail 'integration case fixture contains no runnable cases'
# Every case has its own timeout and may spend two additional seconds terminating
# descendants. The suite watchdog covers the complete serial matrix plus setup.
SUITE_TIMEOUT_SECONDS="$((declared_case_count * (TIMEOUT_SECONDS + 2) + 10))"
(
	sleep "${SUITE_TIMEOUT_SECONDS}"
	process_identity_matches "$$" "${SUITE_START_TIME}" || exit 0
	printf '%s\n' "FAIL: service lifecycle integration suite exceeded ${SUITE_TIMEOUT_SECONDS}s for ${declared_case_count} serial cases" >&2
	kill -TERM "$$" 2>/dev/null || true
) &
SUITE_WATCHDOG_PID="$!"
SUITE_WATCHDOG_START_TIME=$(process_start_time "${SUITE_WATCHDOG_PID}") || SUITE_WATCHDOG_START_TIME=""
dimension_count=$(awk -F '\t' '
	function invalid(message) {
		print message
		failed = 1
		exit 1
	}
	BEGIN {
		expected_dimensions["mode_wan"] = 1
		expected_dimensions["mode_ap"] = 1
		expected_dimensions["mode_repeater"] = 1
		expected_dimensions["mode_bridge"] = 1
		expected_dimensions["dnsmasq_running"] = 1
		expected_dimensions["dnsmasq_stopped"] = 1
		expected_dimensions["dnsmasq_missing"] = 1
		expected_dimensions["dnsmasq_failing"] = 1
		expected_dimensions["ipv4_only"] = 1
		expected_dimensions["ipv6_only"] = 1
		expected_dimensions["dual_stack"] = 1
		expected_dimensions["netstat_owner_rich"] = 1
		expected_dimensions["netstat_ownerless"] = 1
		expected_dimensions["flock_missing"] = 1
		expected_dimensions["flock_incapable"] = 1
		expected_dimensions["flock_descriptor"] = 1
		expected_dimensions["launch_failure"] = 1
		expected_dimensions["bind_failure"] = 1
		expected_dimensions["webui_failure"] = 1
		expected_dimensions["duplicate_process"] = 1
		expected_dimensions["early_exit"] = 1
		expected_dimensions["hung_stop"] = 1
		expected_dimensions["interrupt_every_transition"] = 1
		expected_dimensions["offline_wan"] = 1
		expected_dimensions["readonly_jffs"] = 1
		expected_dimensions["opt_initially_unavailable"] = 1
		expected_dimensions["opt_disappears"] = 1
		expected_dimensions["constrained_tmp"] = 1
		expected_dimensions["custom_yaml"] = 1
		expected_dimensions["custom_hooks"] = 1
		expected_dimensions["bounded_completion"] = 1
		expected_dimensions["service_continuity"] = 1
		expected_dimensions["exact_recovery"] = 1
		expected_dimensions["no_nvram_commit"] = 1
		expected_dimensions["child_reaping"] = 1
		expected_dimensions["cleanup_trap"] = 1
		expected_dimensions["no_stale_artifacts"] = 1
		expected_dimensions["preserve_failed_rollback"] = 1
	}
	NR == FNR {
		if (NF && $1 !~ /^#/) cases[$1] = 1
		next
	}
	!NF || $1 ~ /^#/ { next }
	NF != 3 { invalid("coverage row " FNR " must have exactly three tab-separated fields") }
	$1 == "" { invalid("coverage row " FNR " has no dimension") }
	!($1 in expected_dimensions) { invalid("coverage fixture has unexpected dimension " $1) }
	seen_dimensions[$1]++ { invalid("coverage fixture repeats dimension " $1) }
	$2 == "" { invalid("coverage row " $1 " has no case") }
	!($2 in cases) { invalid("coverage row " $1 " references unknown case " $2) }
	$3 == "" || $3 ~ /^ / || $3 ~ / $/ || $3 ~ /  / {
		invalid("coverage row " $1 " has a malformed component list")
	}
	{
		component_count = split($3, components, " ")
		for (component_index = 1; component_index <= component_count; component_index++) {
			component = components[component_index]
			if (component != "installer" && component != "S99AdGuardHome" &&
				component != "rc.func.AdGuardHome" && component != "AdGuardHome.sh") {
				invalid("coverage row " $1 " has unknown component " component)
			}
			if (row_components[$1, component]++) {
				invalid("coverage row " $1 " repeats component " component)
			}
			covered[component] = 1
		}
		dimension_count++
	}
	END {
		if (failed) exit 1
		for (dimension in expected_dimensions) {
			if (!(dimension in seen_dimensions)) invalid("coverage fixture omits dimension " dimension)
		}
		required[1] = "installer"
		required[2] = "S99AdGuardHome"
		required[3] = "rc.func.AdGuardHome"
		required[4] = "AdGuardHome.sh"
		for (required_index = 1; required_index <= 4; required_index++) {
			component = required[required_index]
			if (!(component in covered)) invalid("coverage fixture omits " component)
		}
		print dimension_count + 0
	}
' "${CASES_FIXTURE}" "${COVERAGE_FIXTURE}") ||
	fail "${dimension_count:-could not validate integration coverage fixture}"
[ "${dimension_count}" -eq 38 ] || fail "coverage fixture has ${dimension_count} dimensions, expected 38"

# The component regressions use command shims and isolated filesystems.  Taken
# together they exercise the real extracted installer/service functions across
# the lifecycle and failure dimensions below without changing the host DNS or
# NVRAM state.
while IFS="$(printf '\t')" read -r case_name test_script; do
	case "${case_name}" in '' | \#*) continue ;; esac
	[ -f "${ROOT_DIR}/${test_script}" ] || fail "integration case ${case_name} references missing ${test_script}"
	run_bounded "${case_name}" "${test_script}"
done <"${CASES_FIXTURE}"

[ "${SCENARIO_COUNT}" -eq "$(awk 'NF && $1 !~ /^#/ { count++ } END { print count + 0 }' "${CASES_FIXTURE}")" ] ||
	fail 'integration matrix skipped one or more declared cases'
[ "$(wc -l <"${RESULTS_FILE}")" -eq "${SCENARIO_COUNT}" ] || fail 'integration matrix did not complete every scenario group'
printf '%s\n' 'PASS: installer and service lifecycle integration matrix'
