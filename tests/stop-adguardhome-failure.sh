#!/bin/sh
# Verify stop failures are limited to process, dnsmasq restart, and local DNS recovery.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
TEST_ROOT="${TMPDIR:-/tmp}/stop-adguardhome-failure.$$"
FUNCTION_FILE="${TEST_ROOT}/function"
CALLS_FILE="${TEST_ROOT}/calls"

cleanup() { rm -rf "${TEST_ROOT}"; }
fail() { printf '%s\n' "FAIL: $*" >&2; exit 1; }
trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
mkdir -p "${TEST_ROOT}" || fail "could not create test directory"

sed -n '/^post_stop_process_ready() {$/,/^}$/p; /^post_stop_handoff_cleared() {$/,/^}$/p; /^post_stop_dnsmasq_ready() {$/,/^}$/p; /^post_stop_internet_check() {$/,/^}$/p; /^stop_adguardhome() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" ||
	fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTION_FILE}" ] || fail "stop verification functions were not found"
# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

PROCS="AdGuardHome"
WORK_DIR="${TEST_ROOT}/work"
DNS_HANDOFF_DIR="${TEST_ROOT}/handoff"
DNS_HANDOFF_FILE="${DNS_HANDOFF_DIR}/active"
RUNNING="0"
DNSMASQ_MANAGED="1"
DNSMASQ_RUNNING="1"
LOWER_STOP_STATUS="0"
LOWER_KILL_STATUS="0"
SERVICE_STATUS="0"
SOCKET_MODE="ipv4"
LOOKUP_MODE="ipv4"
NETCHECK_STATUS="0"

agh_log() { printf '%s\n' "$*" >>"${CALLS_FILE}"; }
canonical_path() { return 1; }
lower_script() {
	printf '%s\n' "lower_script $1" >>"${CALLS_FILE}"
	case "$1" in stop) return "${LOWER_STOP_STATUS}" ;; kill) return "${LOWER_KILL_STATUS}" ;; esac
}
pidof() {
	case "$1" in
		AdGuardHome) [ "${RUNNING}" -eq 1 ] && printf '%s\n' 123 ;;
		dnsmasq) [ "${DNSMASQ_RUNNING}" -eq 1 ] && printf '%s\n' 88 ;;
	esac
	return 0
}
adguard_dnsmasq_running() { [ "${DNSMASQ_RUNNING}" -eq 1 ]; }
adguard_dnsmasq_managed() { [ "${DNSMASQ_MANAGED}" -eq 1 ]; }
service() {
	printf '%s\n' "service $*" >>"${CALLS_FILE}"
	return "${SERVICE_STATUS}"
}
netstat() {
	case "${SOCKET_MODE}" in
		ipv4) printf '%s\n' 'udp 0 0 0.0.0.0:53 0.0.0.0:* 88/dnsmasq' ;;
		ipv6) printf '%s\n' 'udp6 0 0 :::53 :::* 88/dnsmasq' ;;
		foreign) printf '%s\n' 'udp 0 0 0.0.0.0:53 0.0.0.0:* 99/AdGuardHome' ;;
		none) : ;;
	esac
}
nslookup() {
	printf '%s\n' "nslookup $*" >>"${CALLS_FILE}"
	case "${LOOKUP_MODE}:$2" in ipv4:127.0.0.1 | ipv6:::1) return 0 ;; esac
	return 1
}
netcheck() {
	printf '%s\n' netcheck >>"${CALLS_FILE}"
	return "${NETCHECK_STATUS}"
}

reset_case() {
	: >"${CALLS_FILE}"
	rm -rf "${DNS_HANDOFF_DIR}"
	RUNNING="0" DNSMASQ_MANAGED="1" DNSMASQ_RUNNING="1"
	LOWER_STOP_STATUS="0" LOWER_KILL_STATUS="0" SERVICE_STATUS="0"
	SOCKET_MODE="ipv4" LOOKUP_MODE="ipv4" NETCHECK_STATUS="0"
}

# An offline WAN is informational once dnsmasq and the local resolver are ready.
reset_case
NETCHECK_STATUS="1"
stop_adguardhome || fail "offline WAN made a locally healthy stop fail"
grep -q 'reason=public_connectivity_unavailable.*result=informational' "${CALLS_FILE}" ||
	fail "offline WAN was not logged as informational"

# IPv6-only local DNS is accepted without requiring an IPv4 listener.
reset_case
SOCKET_MODE="ipv6" LOOKUP_MODE="ipv6"
stop_adguardhome || fail "IPv6-only local DNS recovery failed"

# Local DNS success does not depend on HTTP reachability.
reset_case
stop_adguardhome || fail "DNS-without-HTTP recovery failed"
! grep -q '^http' "${CALLS_FILE}" || fail "stop recovery attempted an HTTP readiness probe"

# A managed dnsmasq restart failure remains fatal.
reset_case
SERVICE_STATUS="1"
if stop_adguardhome; then fail "dnsmasq restart failure was hidden"; fi
grep -q 'reason=service_restart_failed' "${CALLS_FILE}" || fail "dnsmasq restart failure was not logged"

# AdGuard Home remaining active remains fatal, while DNS restoration is still attempted.
reset_case
RUNNING="1" LOWER_STOP_STATUS="1" LOWER_KILL_STATUS="1"
if stop_adguardhome; then fail "active AdGuard Home process was hidden"; fi
grep -q 'reason=process_still_active' "${CALLS_FILE}" || fail "active process failure was not logged"
grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail "DNS restoration was not attempted after stop failure"

# Unmanaged LAN mode checks only process state and stale installer handoff markers.
reset_case
DNSMASQ_MANAGED="0" DNSMASQ_RUNNING="0" SOCKET_MODE="none" LOOKUP_MODE="none" NETCHECK_STATUS="1"
stop_adguardhome || fail "unmanaged LAN stop incorrectly required dnsmasq or Internet readiness"
! grep -q '^netcheck$' "${CALLS_FILE}" || fail "unmanaged LAN stop performed an Internet connectivity check"
mkdir -p "${DNS_HANDOFF_DIR}" && : >"${DNS_HANDOFF_FILE}"
if stop_adguardhome; then fail "unmanaged LAN stop ignored a stale handoff marker"; fi
grep -q 'reason=installer_marker_remains' "${CALLS_FILE}" || fail "stale handoff marker was not logged"

printf '%s\n' "PASS: stop verification separates process, local DNS, and Internet readiness"
