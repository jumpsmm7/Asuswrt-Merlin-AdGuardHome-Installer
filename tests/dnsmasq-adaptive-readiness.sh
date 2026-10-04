#!/bin/sh
# Verify stop recovery uses a bounded adaptive dnsmasq readiness budget.
set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dnsmasq-adaptive-readiness.XXXXXX")" || exit 1
FUNCTIONS_FILE="${TMP_ROOT}/functions"
CALLS_FILE="${TMP_ROOT}/calls"

cleanup() { rm -rf "${TMP_ROOT}"; }
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}
trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

sed -n '/^monotonic_seconds() {$/,/^}$/p; /^post_stop_dnsmasq_timeout() {$/,/^}$/p; /^stop_adguardhome() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" || fail 'could not extract adaptive dnsmasq helpers'
[ -s "${FUNCTIONS_FILE}" ] || fail 'adaptive dnsmasq helper extraction was empty'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

case "$(monotonic_seconds 2>/dev/null)" in
	"" | *[!0-9]*) fail 'production monotonic uptime reader did not return integer seconds' ;;
esac
[ "$(post_stop_dnsmasq_timeout 0)" -eq 15 ] || fail 'default dnsmasq readiness floor is not 15 seconds'
[ "$(post_stop_dnsmasq_timeout 4)" -eq 22 ] || fail 'dnsmasq timeout did not adapt to observed restart duration'
[ "$(post_stop_dnsmasq_timeout 999999)" -eq 60 ] || fail 'adaptive dnsmasq timeout did not enforce the 60 second cap'
ADGUARDHOME_DNSMASQ_READY_TIMEOUT=30
[ "$(post_stop_dnsmasq_timeout 0)" -eq 30 ] || fail 'valid dnsmasq timeout override was not honored'
ADGUARDHOME_DNSMASQ_READY_TIMEOUT=4
[ "$(post_stop_dnsmasq_timeout 0)" -eq 15 ] || fail 'out-of-range dnsmasq timeout override bypassed the adaptive floor'
unset ADGUARDHOME_DNSMASQ_READY_TIMEOUT

PROCS='AdGuardHome'
WORK_DIR="${TMP_ROOT}/work"
MONOTONIC_NOW=100
RESTART_SECONDS=0
READY_AFTER=0
READY_CHECKS=0
SLEEP_CALLS=0
SERVICE_STATUS=0

monotonic_seconds() { printf '%s\n' "${MONOTONIC_NOW}"; }
adguard_dnsmasq_managed() { return 0; }
post_stop_process_ready() { return 0; }
post_stop_handoff_cleared() { return 0; }
post_stop_dnsmasq_ready() {
	READY_CHECKS="$((READY_CHECKS + 1))"
	[ "${READY_CHECKS}" -gt "${READY_AFTER}" ]
}
pidof() { return 1; }
lower_script() { return 0; }
remove_database_link() { :; }
agh_log() { printf '%s\n' "$*" >>"${CALLS_FILE}"; }
service() {
	printf '%s\n' "service $*" >>"${CALLS_FILE}"
	MONOTONIC_NOW="$((MONOTONIC_NOW + RESTART_SECONDS))"
	return "${SERVICE_STATUS}"
}
sleep() { SLEEP_CALLS="$((SLEEP_CALLS + 1))"; }

reset_case() {
	: >"${CALLS_FILE}"
	MONOTONIC_NOW=100
	RESTART_SECONDS=0
	READY_AFTER=0
	READY_CHECKS=0
	SLEEP_CALLS=0
	SERVICE_STATUS=0
	unset ADGUARDHOME_DNSMASQ_READY_TIMEOUT ADGUARDHOME_SKIP_DNSMASQ_RESTART
}

reset_case
READY_AFTER=7
stop_adguardhome || fail 'dnsmasq readiness after the old five-attempt threshold still failed'
[ "${READY_CHECKS}" -eq 8 ] || fail 'extended default readiness did not reach the delayed success'
[ "${SLEEP_CALLS}" -eq 7 ] || fail 'extended default readiness used the wrong delay count'
[ "$(grep -c '^service restart_dnsmasq$' "${CALLS_FILE}")" -eq 1 ] || fail 'adaptive timing added an extra dnsmasq restart'

reset_case
RESTART_SECONDS=4
READY_AFTER=20
stop_adguardhome || fail 'observed slow dnsmasq restart did not expand readiness budget'
[ "${READY_CHECKS}" -eq 21 ] || fail 'adaptive readiness did not wait to the simulated slow success'
[ "${SLEEP_CALLS}" -eq 20 ] || fail 'adaptive readiness used the wrong slow-restart delay count'
grep -q 'restart_elapsed=4.*timeout=22' "${CALLS_FILE}" || fail 'adaptive dnsmasq timing was not reflected in lifecycle logging'

reset_case
READY_AFTER=999
if stop_adguardhome; then fail 'never-ready dnsmasq bypassed the bounded timeout'; fi
[ "${READY_CHECKS}" -eq 15 ] || fail 'never-ready dnsmasq did not stop at the 15 second floor'
[ "${SLEEP_CALLS}" -eq 14 ] || fail 'never-ready dnsmasq slept outside the bounded retry window'
grep -q 'reason=dnsmasq_not_ready.*attempts=15.*timeout=15' "${CALLS_FILE}" || fail 'bounded dnsmasq timeout was not logged'

printf '%s\n' 'PASS: adaptive dnsmasq stop readiness'
