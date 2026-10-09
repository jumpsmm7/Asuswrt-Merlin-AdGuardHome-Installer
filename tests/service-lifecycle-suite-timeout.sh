#!/bin/sh
# Regression test for lifecycle watchdog bounds, cancellation and expiry.

set -u

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd) || exit 1
SCRIPT_PATH="${ROOT_DIR}/tests/service-lifecycle-integration.sh"
CASES_FIXTURE="${ROOT_DIR}/tests/fixtures/service-lifecycle-cases.tsv"

# fail prints a failure message containing the specified reason and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $1" >&2
	exit 1
}

TMP_ROOT=$(mktemp -d) || fail 'unable to create exclusive temp workspace'
WATCHDOG_PID=""
SLEEP_PID=""
# cleanup joins only this fixture's child processes before removing its workspace.
cleanup() {
	[ -z "${SLEEP_PID}" ] || kill -TERM "${SLEEP_PID}" 2>/dev/null || true
	[ -z "${WATCHDOG_PID}" ] || kill -TERM "${WATCHDOG_PID}" 2>/dev/null || true
	[ -z "${WATCHDOG_PID}" ] || wait "${WATCHDOG_PID}" 2>/dev/null || true
	rm -rf "${TMP_ROOT}"
}
trap cleanup EXIT
trap 'cleanup; exit 1' HUP INT TERM

FUNCTIONS_FILE="${TMP_ROOT}/functions.sh"
[ "$(grep -c '^suite_timeout_seconds() {$' "${SCRIPT_PATH}")" -eq 1 ] || fail 'suite timeout helper start boundary is missing'
sed -n '/^suite_timeout_seconds() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" ||
	fail 'could not extract suite timeout helper'
[ -s "${FUNCTIONS_FILE}" ] || fail 'suite timeout helper extraction was empty'
tail -n 1 "${FUNCTIONS_FILE}" | grep -q '^}$' || fail 'suite timeout helper end boundary is missing'
[ "$(awk '$0 == "suite_timeout_seconds() {" { helper = 1; next } helper && $0 == "}" { getline; print; exit }' "${SCRIPT_PATH}")" = 'trap cleanup 0' ] ||
	fail 'suite timeout helper end boundary is not followed by trap cleanup 0'
if grep -q "^trap 'on_installer_exit' EXIT$" "${FUNCTIONS_FILE}"; then
	fail 'suite timeout helper extraction included installer top-level execution'
fi

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

STUB_DECLARED_CASE_COUNT=28
fixture_case_count=$(awk -F '\t' 'NF && $1 !~ /^#/ { count++ } END { print count + 0 }' "${CASES_FIXTURE}") ||
	fail 'could not count service lifecycle fixture cases'
[ "${STUB_DECLARED_CASE_COUNT}" -eq "${fixture_case_count}" ] ||
	fail "declared case count does not match fixture: ${fixture_case_count}"
OUTER_TIMEOUT_SECONDS=$(sed -n 's/^SUITE_OUTER_TIMEOUT_SECONDS=\([0-9][0-9]*\)$/\1/p' "${SCRIPT_PATH}") ||
	fail 'could not extract suite outer timeout'
case "${OUTER_TIMEOUT_SECONDS}" in
	'' | *[!0-9]*) fail 'could not extract suite outer timeout' ;;
esac
suite_timeout=$(suite_timeout_seconds "${STUB_DECLARED_CASE_COUNT}" 180 "${OUTER_TIMEOUT_SECONDS}") ||
	fail '180-second per-case timeout was rejected'
[ "${suite_timeout}" -lt "${OUTER_TIMEOUT_SECONDS}" ] ||
	fail 'suite timeout is not below the outer timeout'
[ "${suite_timeout}" -eq 5134 ] ||
	fail "suite timeout did not include the three-second per-case allowance: ${suite_timeout}"
[ "${suite_timeout}" -ne 5106 ] ||
	fail 'suite timeout used only a two-second per-case allowance'

if suite_timeout_seconds "${STUB_DECLARED_CASE_COUNT}" 181 "${OUTER_TIMEOUT_SECONDS}" >/dev/null; then
	fail '181-second per-case timeout exceeded the outer limit without rejection'
fi

# Run the actual watchdog body while intercepting its parent signal. The real
# sleep child is interrupted during cancellation, as suite cleanup does.
WATCHDOG_BODY="${TMP_ROOT}/watchdog-body"
sed -n '/^[[:space:]]*sleep "${SUITE_TIMEOUT_SECONDS}"/,/^) &$/ { /^) &$/d; p; }' "${SCRIPT_PATH}" >"${WATCHDOG_BODY}" ||
	fail 'could not extract suite watchdog body'
[ "$(grep -c 'sleep "${SUITE_TIMEOUT_SECONDS}"' "${WATCHDOG_BODY}")" -eq 1 ] ||
	fail 'suite watchdog sleep boundary changed'
cat >"${TMP_ROOT}/watchdog" <<'EOF_WATCHDOG'
#!/bin/sh
set -u
watchdog_dir="$1"
SUITE_TIMEOUT_SECONDS="$2"
SUITE_START_TIME=fixture
declared_case_count=1
# process_identity_matches models the still-live parent during suite cleanup.
process_identity_matches() { return 0; }
# kill records the watchdog's parent signal without terminating this fixture.
kill() { printf '%s\n' "$*" >"${watchdog_dir}/signaled"; }
# sleep announces a genuine sleep child so the controller can cancel it.
sleep() {
	/bin/sleep "$@" &
	sleep_pid="$!"
	printf '%s\n' "${sleep_pid}" >"${watchdog_dir}/sleep-pid.new" || return 1
	mv "${watchdog_dir}/sleep-pid.new" "${watchdog_dir}/sleep-pid" || return 1
	wait "${sleep_pid}"
}
EOF_WATCHDOG
cat "${WATCHDOG_BODY}" >>"${TMP_ROOT}/watchdog" || fail 'could not assemble watchdog fixture'
SHELL_BIN=$(readlink "/proc/$$/exe") || fail 'could not identify fixture shell'
# run_watchdog preserves the current shell, including BusyBox applet dispatch.
run_watchdog() {
	case "${SHELL_BIN}" in
		*busybox*) "${SHELL_BIN}" ash "${TMP_ROOT}/watchdog" "$@" ;;
		*) "${SHELL_BIN}" "${TMP_ROOT}/watchdog" "$@" ;;
	esac
}
mkdir "${TMP_ROOT}/cancel" "${TMP_ROOT}/expire" || fail 'could not create watchdog scenarios'
run_watchdog "${TMP_ROOT}/cancel" 30 >"${TMP_ROOT}/cancel/log" 2>&1 &
WATCHDOG_PID="$!"
attempts=0
while [ ! -f "${TMP_ROOT}/cancel/sleep-pid" ] && [ "${attempts}" -lt 5 ]; do
	sleep 1
	attempts="$((attempts + 1))"
done
[ -f "${TMP_ROOT}/cancel/sleep-pid" ] || fail 'watchdog did not start its cancellable sleep'
IFS= read -r SLEEP_PID <"${TMP_ROOT}/cancel/sleep-pid" || fail 'could not read watchdog sleep identity'
kill -TERM "${SLEEP_PID}" || fail 'could not cancel watchdog sleep'
wait "${WATCHDOG_PID}" || fail 'cancelled watchdog did not exit successfully'
WATCHDOG_PID=""
SLEEP_PID=""
if grep -q '^FAIL:' "${TMP_ROOT}/cancel/log" || [ -e "${TMP_ROOT}/cancel/signaled" ]; then
	fail 'cancelled watchdog reported timeout or signaled its live parent'
fi
run_watchdog "${TMP_ROOT}/expire" 1 >"${TMP_ROOT}/expire/log" 2>&1 ||
	fail 'expired watchdog fixture could not complete'
grep -q '^FAIL: service lifecycle integration suite exceeded 1s' "${TMP_ROOT}/expire/log" ||
	fail 'actual watchdog expiry did not report timeout'
[ -f "${TMP_ROOT}/expire/signaled" ] || fail 'actual watchdog expiry did not signal its parent'

printf '%s\n' 'PASS: lifecycle watchdog bounds, cancellation and actual expiry'
