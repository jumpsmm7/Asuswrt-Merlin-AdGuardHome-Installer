#!/bin/sh
# Verify legacy netcheck does not report success when DNS and WAN probes fail.

set -u

MANAGER_PATH="${1:-AdGuardHome.sh}"
TEST_ROOT="${TMPDIR:-/tmp}/adguardhome-netcheck-legacy.$$"
FUNCTIONS_FILE="${TEST_ROOT}/functions"

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

sed -n \
	'/^netcheck_legacy() {$/,/^}$/p' \
	"${MANAGER_PATH}" >"${FUNCTIONS_FILE}" || fail "could not read ${MANAGER_PATH}"
grep -q '^netcheck_legacy() {$' "${FUNCTIONS_FILE}" || fail 'legacy netcheck helper missing'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

SLEEP_CALLS=0
NSLOOKUP_CALLS=0
PING_CALLS=0
HTTP_CALLS=0

agh_log() {
	:
}

system_time_ready() {
	return 0
}

sleep() {
	SLEEP_CALLS="$((SLEEP_CALLS + 1))"
}

nslookup() {
	NSLOOKUP_CALLS="$((NSLOOKUP_CALLS + 1))"
	return "${NSLOOKUP_RESULT:-1}"
}

ping() {
	PING_CALLS="$((PING_CALLS + 1))"
	return "${PING_RESULT:-1}"
}

http_probe() {
	HTTP_CALLS="$((HTTP_CALLS + 1))"
	return "${HTTP_RESULT:-1}"
}

NSLOOKUP_RESULT=1
PING_RESULT=1
HTTP_RESULT=1
if netcheck_legacy; then
	fail 'legacy netcheck succeeded when DNS and ping both failed'
fi
[ "${NSLOOKUP_CALLS}" -eq 12 ] || fail 'legacy netcheck did not retry all DNS probes'
[ "${PING_CALLS}" -eq 12 ] || fail 'legacy netcheck did not retry all ping probes'
[ "${HTTP_CALLS}" -eq 0 ] || fail 'legacy netcheck attempted HTTP with no WAN reachability'

NSLOOKUP_CALLS=0
PING_CALLS=0
HTTP_CALLS=0
NSLOOKUP_RESULT=1
PING_RESULT=0
HTTP_RESULT=0
netcheck_legacy || fail 'legacy netcheck failed when ping and HTTP fallback succeeded'
[ "${HTTP_CALLS}" -eq 1 ] || fail 'legacy netcheck did not use HTTP fallback after DNS failure'
