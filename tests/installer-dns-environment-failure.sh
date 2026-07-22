#!/bin/sh
# Verify DNS NVRAM changes fail safely and use bounded local readiness checks.

set -u

INSTALLER_PATH="${1:-installer}"
TEST_ROOT="${TMPDIR:-/tmp}/installer-dns-environment-failure.$$"
FUNCTIONS_FILE="${TEST_ROOT}/functions"
NVRAM_FILE="${TEST_ROOT}/nvram"
CALLS_FILE="${TEST_ROOT}/calls"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}
cleanup() { rm -rf "${TEST_ROOT}"; }
trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
mkdir -p "${TEST_ROOT}" || fail 'could not create test workspace'

sed -n '/^check_dns_environment() {$/,/^check_dns_filter() {$/p' "${INSTALLER_PATH}" | sed '$d' >"${FUNCTIONS_FILE}" || fail 'could not extract DNS environment helper'
sed -n '/^save_dns_nvram_environment() {$/,/^}$/p' "${INSTALLER_PATH}" >>"${FUNCTIONS_FILE}" || fail 'could not extract NVRAM snapshot helper'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

INFO='Info:'
ERROR='Error:'
WARNING='Warning:'
DNS_ENV_READY_TIMEOUT=2
DNS_ENV_RECOVERY_TIMEOUT=1
MONOTONIC_NOW=0
PTXT() { printf '%s\n' "$*" >>"${CALLS_FILE}"; }
ptxt_phase() { PTXT "$1"; }
ptxt_step() { PTXT "$1"; }
ptxt_ok() { PTXT "$1"; }
pidof() { return 1; }
kill_processes() { return 0; }
sleep() { MONOTONIC_NOW="$((MONOTONIC_NOW + 1))"; }
monotonic_seconds() { printf '%s\n' "${MONOTONIC_NOW}"; }
check_connection() {
	PUBLIC_CHECK_COUNT="$((PUBLIC_CHECK_COUNT + 1))"
	[ "${PUBLIC_NETWORK_AVAILABLE:-0}" = 1 ]
}

nvram_value() {
	awk -v key="$1" 'index($0, key "=") == 1 { print substr($0, length(key) + 2); found=1 } END { exit(found ? 0 : 1) }' "${NVRAM_FILE}"
}

nvram() {
	case "$1" in
		show)
			[ "${FAIL_SHOW:-0}" = 0 ] || return 1
			cat "${NVRAM_FILE}"
			;;
		get)
			[ "${FAIL_GET_KEY:-}" != "$2" ] || return 1
			nvram_value "$2" || return 0
			;;
		set)
			SET_COUNT="$((SET_COUNT + 1))"
			printf '%s\n' "set $2" >>"${CALLS_FILE}"
			[ "${FAIL_ALL_SETS:-0}" = 0 ] || return 1
			[ "${FAIL_SET_AT:-0}" != "${SET_COUNT}" ] || return 1
			key="${2%%=*}"
			value="${2#*=}"
			awk -v key="${key}" -v value="${value}" 'BEGIN { done=0 } index($0,key "=")==1 { print key "=" value; done=1; next } { print } END { if (!done) print key "=" value }' "${NVRAM_FILE}" >"${NVRAM_FILE}.new" && mv "${NVRAM_FILE}.new" "${NVRAM_FILE}"
			;;
		unset)
			SET_COUNT="$((SET_COUNT + 1))"
			printf '%s\n' "unset $2" >>"${CALLS_FILE}"
			[ "${FAIL_ALL_SETS:-0}" = 0 ] || return 1
			[ "${FAIL_SET_AT:-0}" != "${SET_COUNT}" ] || return 1
			awk -v key="$2" 'index($0,key "=")!=1' "${NVRAM_FILE}" >"${NVRAM_FILE}.new" && mv "${NVRAM_FILE}.new" "${NVRAM_FILE}"
			;;
		commit)
			COMMIT_COUNT="$((COMMIT_COUNT + 1))"
			printf '%s\n' commit >>"${CALLS_FILE}"
			[ "${FAIL_COMMIT_AT:-0}" != "${COMMIT_COUNT}" ]
			;;
		*) return 1 ;;
	esac
}

service() {
	[ "$*" = restart_dnsmasq ] || return 1
	SERVICE_COUNT="$((SERVICE_COUNT + 1))"
	printf '%s\n' 'service restart_dnsmasq' >>"${CALLS_FILE}"
	[ "${FAIL_SERVICE_AT:-0}" != "${SERVICE_COUNT}" ]
}

nslookup() {
	DNS_CHECK_COUNT="$((DNS_CHECK_COUNT + 1))"
	printf '%s\n' "nslookup $*" >>"${CALLS_FILE}"
	[ "${BLOCKING_QUERY:-0}" = 0 ] || MONOTONIC_NOW="$((MONOTONIC_NOW + 10))"
	[ "${DNS_READY:-1}" = 1 ]
}

reset_case() {
	cat >"${NVRAM_FILE}" <<'EOF_NVRAM'
dnspriv_enable=1
dhcpd_dns_router=0
dhcp_dns1_x=
dhcp_dns2_x=149.112.112.112
EOF_NVRAM
	: >"${CALLS_FILE}"
	SET_COUNT=0 COMMIT_COUNT=0 SERVICE_COUNT=0 DNS_CHECK_COUNT=0 PUBLIC_CHECK_COUNT=0
	FAIL_SHOW=0 FAIL_GET_KEY='' FAIL_ALL_SETS=0 FAIL_SET_AT=0 FAIL_COMMIT_AT=0 FAIL_SERVICE_AT=0 DNS_READY=1 PUBLIC_NETWORK_AVAILABLE=0
	BLOCKING_QUERY=0 MONOTONIC_NOW=0
	_DNS_NVRAM_SAVED=0 _DNS_NVRAM_ROLLBACK_ATTEMPTED=0
}

assert_original() {
	[ "$(nvram_value dnspriv_enable)" = 1 ] || fail "$1: dnspriv_enable was not restored"
	[ "$(nvram_value dhcpd_dns_router)" = 0 ] || fail "$1: dhcpd_dns_router was not restored"
	[ "$(nvram_value dhcp_dns1_x)" = '' ] || fail "$1: empty value was not restored"
	[ "$(nvram_value dhcp_dns2_x)" = 149.112.112.112 ] || fail "$1: dhcp_dns2_x was not restored"
}

reset_case
FAIL_SHOW=1
check_dns_environment 0 && fail 'NVRAM inventory read failure was accepted'
[ "${SET_COUNT}" = 0 ] || fail 'NVRAM changed after a failed inventory read'
[ "${_DNS_NVRAM_SAVED}" = 0 ] || fail 'failed inventory snapshot was marked valid'

reset_case
FAIL_GET_KEY=dhcp_dns1_x
check_dns_environment 0 && fail 'NVRAM read failure was accepted'
[ "${SET_COUNT}" = 0 ] || fail 'NVRAM changed after an incomplete snapshot'
[ "${_DNS_NVRAM_SAVED}" = 0 ] || fail 'incomplete snapshot was marked valid'

reset_case
DNS_ENV_READY_TIMEOUT=invalid
DNS_ENV_RECOVERY_TIMEOUT=invalid
check_dns_environment 0 || fail 'public network unavailability blocked local DNS preparation'
[ "${PUBLIC_CHECK_COUNT}" = 0 ] || fail 'DNS preparation used a public connectivity check'
[ "${DNS_ENV_READY_TIMEOUT}" = 60 ] || fail 'invalid startup readiness timeout did not use its numeric default'
[ "${DNS_ENV_RECOVERY_TIMEOUT}" = 15 ] || fail 'invalid recovery timeout did not use its numeric default'
check_dns_environment 1 || fail 'successful DNS preparation could not restore its snapshot'
assert_original 'successful preparation'
DNS_ENV_READY_TIMEOUT=2
DNS_ENV_RECOVERY_TIMEOUT=1

reset_case
sed '/^dhcp_dns2_x=/d' "${NVRAM_FILE}" >"${NVRAM_FILE}.new" && mv "${NVRAM_FILE}.new" "${NVRAM_FILE}"
check_dns_environment 0 || fail 'snapshot with an absent NVRAM key was rejected'
check_dns_environment 1 || fail 'snapshot with an absent NVRAM key was not restored'
if nvram_value dhcp_dns2_x >/dev/null 2>&1; then fail 'originally absent NVRAM key was restored as an empty key'; fi

reset_case
FAIL_SET_AT=2
check_dns_environment 0 && fail 'NVRAM set failure was accepted'
assert_original 'set failure'
grep -q 'rollback was complete' "${CALLS_FILE}" || fail 'set failure rollback result was not reported'

reset_case
FAIL_ALL_SETS=1
check_dns_environment 0 && fail 'complete NVRAM set failure was accepted'
grep -q 'rollback was failed' "${CALLS_FILE}" || fail 'rollback with no successful restoration was not reported as failed'

reset_case
FAIL_COMMIT_AT=1
check_dns_environment 0 && fail 'NVRAM commit failure was accepted'
assert_original 'commit failure'
[ "${COMMIT_COUNT}" = 2 ] || fail 'rollback did not commit the restoration after apply commit failure'

reset_case
FAIL_SERVICE_AT=1
check_dns_environment 0 && fail 'dnsmasq restart failure was accepted'
assert_original 'service failure'
[ "${SERVICE_COUNT}" = 2 ] || fail 'rollback did not restart dnsmasq exactly once after apply restart failure'

reset_case
DNS_READY=0
check_dns_environment 0 && fail 'local DNS readiness failure was accepted'
assert_original 'DNS readiness failure'
[ "${DNS_CHECK_COUNT}" = 3 ] || fail 'local DNS and recovery checks were not bounded by their configured deadlines'

reset_case
DNS_READY=0
BLOCKING_QUERY=1
check_dns_environment 0 && fail 'blocking local DNS readiness failure was accepted'
[ "${DNS_CHECK_COUNT}" = 2 ] || fail 'blocking DNS queries exceeded the startup and recovery deadlines'

reset_case
FAIL_COMMIT_AT=2
DNS_READY=0
check_dns_environment 0 && fail 'rollback commit failure was accepted'
grep -q 'rollback was partial' "${CALLS_FILE}" || fail 'rollback commit failure was not reported as partial'

reset_case
FAIL_SERVICE_AT=2
DNS_READY=0
check_dns_environment 0 && fail 'rollback service restart failure was accepted'
grep -q 'rollback was partial' "${CALLS_FILE}" || fail 'rollback service failure was not reported as partial'

reset_case
check_dns_environment 0 || fail 'DNS preparation for partial exit restoration failed'
FAIL_SET_AT=5
check_dns_environment 1 && fail 'partial exit restoration was reported as complete'
[ "${COMMIT_COUNT}" = 2 ] || fail 'partial exit restoration did not commit successful restores'
[ "${SERVICE_COUNT}" = 2 ] || fail 'partial exit restoration did not restart dnsmasq'

reset_case
FAIL_COMMIT_AT=2
DNS_READY=0
check_dns_environment 0 && fail 'rollback retry setup was unexpectedly accepted'
FAIL_COMMIT_AT=0
DNS_READY=1
check_dns_environment 1 || fail 'incomplete automatic rollback could not be retried'
assert_original 'retried rollback'

grep -q 'check_dns_environment 0 || return 1' "${INSTALLER_PATH}" || fail 'CLI install does not propagate DNS preparation failure'
grep -q 'check_dns_environment 0 || exit 1' "${INSTALLER_PATH}" || fail 'interactive install does not propagate DNS preparation failure'

reset_case
(
	trap 'check_dns_environment 1 >/dev/null 2>&1 || :; exit 0' TERM
	save_dns_nvram_environment || exit 1
	nvram set dnspriv_enable=0 || exit 1
	: >"${TEST_ROOT}/signal-ready"
	while :; do :; done
) &
signal_pid="$!"
signal_wait=0
while [ ! -f "${TEST_ROOT}/signal-ready" ] && [ "${signal_wait}" -lt 20 ]; do
	/bin/sleep 1
	signal_wait="$((signal_wait + 1))"
done
[ -f "${TEST_ROOT}/signal-ready" ] || fail 'signal test did not reach the interrupted state'
kill -TERM "${signal_pid}" || fail 'could not inject termination signal'
wait "${signal_pid}" || fail 'signal-interruption rollback failed'
assert_original 'signal interruption'

printf '%s\n' 'PASS: installer DNS environment failures are bounded and rolled back'
