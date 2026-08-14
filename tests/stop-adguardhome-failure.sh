#!/bin/sh
# Verify stop failures are limited to process, dnsmasq restart, and local DNS recovery.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
TEST_ROOT="${TMPDIR:-/tmp}/stop-adguardhome-failure.$$"
FUNCTION_FILE="${TEST_ROOT}/function"
CALLS_FILE="${TEST_ROOT}/calls"
DATABASE_LINK_CALLS_FILE="${TEST_ROOT}/database-link-calls"

# cleanup removes the temporary test environment.
cleanup() { rm -rf "${TEST_ROOT}"; }
# fail reports a test failure and exits with a nonzero status.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}
trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
mkdir -p "${TEST_ROOT}" || fail "could not create test directory"

sed -n '/^post_stop_process_ready() {$/,/^}$/p; /^post_stop_handoff_cleared() {$/,/^}$/p; /^post_stop_dnsmasq_ready() {$/,/^}$/p; /^stop_adguardhome() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" ||
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
DNSMASQ_READY_AFTER="0"
DNSMASQ_READY_CHECKS="0"

# agh_log records a message in the test call log.
agh_log() { printf '%s\n' "$*" >>"${CALLS_FILE}"; }
# canonical_path returns a failure status.
canonical_path() { return 1; }
# remove_database_link records a database-link removal request in the test call log.
remove_database_link() {
	printf '%s -> %s\n' "$1" "$2" >>"${DATABASE_LINK_CALLS_FILE}"
}
# lower_script records the requested action and returns its configured status for stop or kill operations.
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
adguard_dnsmasq_running() {
	DNSMASQ_READY_CHECKS="$((DNSMASQ_READY_CHECKS + 1))"
	[ "${DNSMASQ_READY_CHECKS}" -gt "${DNSMASQ_READY_AFTER}" ] && [ "${DNSMASQ_RUNNING}" -eq 1 ]
}
adguard_dnsmasq_managed() { [ "${DNSMASQ_MANAGED}" -eq 1 ]; }
service() {
	printf '%s\n' "service $*" >>"${CALLS_FILE}"
	return "${SERVICE_STATUS}"
}
netstat() {
	case "${SOCKET_MODE}" in
		ipv4)
			printf '%s\n' \
				'tcp 0 0 0.0.0.0:53 0.0.0.0:* LISTEN 88/dnsmasq' \
				'udp 0 0 0.0.0.0:53 0.0.0.0:* 88/dnsmasq'
			;;
		ipv6)
			printf '%s\n' \
				'tcp6 0 0 :::53 :::* LISTEN 88/dnsmasq' \
				'udp6 0 0 :::53 :::* 88/dnsmasq'
			;;
		ipv4_ownerless)
			printf '%s\n' \
				'tcp 0 0 0.0.0.0:53 0.0.0.0:* LISTEN' \
				'udp 0 0 0.0.0.0:53 0.0.0.0:*'
			;;
		ipv6_ownerless)
			printf '%s\n' \
				'tcp6 0 0 :::53 :::* LISTEN' \
				'udp6 0 0 :::53 :::*'
			;;
		lan)
			printf '%s\n' \
				'tcp 0 0 192.168.50.1:53 0.0.0.0:* LISTEN 88/dnsmasq' \
				'udp 0 0 192.168.50.1:53 0.0.0.0:* 88/dnsmasq'
			;;
		missing_tcp) printf '%s\n' 'udp 0 0 0.0.0.0:53 0.0.0.0:* 88/dnsmasq' ;;
		missing_udp) printf '%s\n' 'tcp 0 0 0.0.0.0:53 0.0.0.0:* LISTEN 88/dnsmasq' ;;
		foreign)
			printf '%s\n' \
				'tcp 0 0 0.0.0.0:53 0.0.0.0:* LISTEN 88/dnsmasq' \
				'udp 0 0 0.0.0.0:53 0.0.0.0:* 99/AdGuardHome'
			;;
		none) : ;;
	esac
}
nslookup() {
	printf '%s\n' "nslookup $*" >>"${CALLS_FILE}"
	case "${LOOKUP_MODE}:$2" in ipv4:192.168.50.1 | ipv6:::1 | lan:192.168.50.1) return 0 ;; esac
	return 1
}
nvram() {
	[ "$1" = get ] && [ "$2" = lan_ipaddr ] && printf '%s\n' 192.168.50.1
}
netcheck() {
	printf '%s\n' netcheck >>"${CALLS_FILE}"
	return "${NETCHECK_STATUS}"
}
sleep() { printf '%s\n' "sleep $*" >>"${CALLS_FILE}"; }

# reset_case resets mocked call logs, temporary handoff state, and test scenario variables.
reset_case() {
	: >"${CALLS_FILE}"
	: >"${DATABASE_LINK_CALLS_FILE}"
	rm -rf "${DNS_HANDOFF_DIR}"
	unset ADGUARDHOME_SKIP_DNSMASQ_RESTART
	RUNNING="0" DNSMASQ_MANAGED="1" DNSMASQ_RUNNING="1"
	LOWER_STOP_STATUS="0" LOWER_KILL_STATUS="0" SERVICE_STATUS="0"
	SOCKET_MODE="ipv4" LOOKUP_MODE="ipv4" NETCHECK_STATUS="0"
	DNSMASQ_READY_AFTER="0" DNSMASQ_READY_CHECKS="0"
}

# Stop completion does not run the potentially long public-connectivity probe.
reset_case
NETCHECK_STATUS="1"
stop_adguardhome || fail "offline WAN made a locally healthy stop fail"
! grep -q '^netcheck$' "${CALLS_FILE}" || fail "managed stop performed an Internet connectivity check"
[ "$(cat "${DATABASE_LINK_CALLS_FILE}")" = "/tmp/stats.db -> ${WORK_DIR}/data/stats.db
/tmp/sessions.db -> ${WORK_DIR}/data/sessions.db" ] || fail 'stop delegated incorrect optional database link pairs'

# IPv6-only local DNS is accepted without requiring an IPv4 listener.
reset_case
SOCKET_MODE="ipv6" LOOKUP_MODE="ipv6"
stop_adguardhome || fail "IPv6-only local DNS recovery failed"

# A bind-interfaces configuration that excludes loopback is probed on the
# address reported by the dnsmasq-owned socket instead of localhost.
reset_case
SOCKET_MODE="lan" LOOKUP_MODE="lan"
stop_adguardhome || fail "LAN-only dnsmasq listener was not probed"
grep -q '^nslookup localhost 192\.168\.50\.1$' "${CALLS_FILE}" ||
	fail "LAN-only dnsmasq listener address was not used"

# BusyBox netstat may omit PID/program metadata; a running dnsmasq and a
# successful local lookup verify ownerless IPv4 and IPv6 socket rows.
for socket_family in ipv4 ipv6; do
	reset_case
	SOCKET_MODE="${socket_family}_ownerless" LOOKUP_MODE="${socket_family}"
	stop_adguardhome || fail "ownerless ${socket_family} dnsmasq socket was rejected"
done

# Both TCP and UDP port 53 listeners are required even when UDP lookup succeeds.
for missing_protocol in missing_tcp missing_udp; do
	reset_case
	SOCKET_MODE="${missing_protocol}"
	if stop_adguardhome; then fail "${missing_protocol} DNS socket was accepted"; fi
	[ "${DNSMASQ_READY_CHECKS}" -eq 5 ] || fail "${missing_protocol} did not use the bounded retry count"
	grep -q 'reason=dnsmasq_not_ready.*attempts=5' "${CALLS_FILE}" ||
		fail "${missing_protocol} failure was not logged"
done

# Explicit ownership by another process is never covered by the ownerless fallback.
reset_case
SOCKET_MODE="foreign"
if stop_adguardhome; then fail "foreign-owned DNS socket was accepted"; fi
grep -q 'reason=dnsmasq_not_ready.*attempts=5' "${CALLS_FILE}" || fail "foreign DNS owner failure was not logged"

# Local DNS success does not depend on HTTP reachability.
reset_case
stop_adguardhome || fail "DNS-without-HTTP recovery failed"
! grep -q '^http' "${CALLS_FILE}" || fail "stop recovery attempted an HTTP readiness probe"

# A dispatched dnsmasq restart is polled until its process and resolver become ready.
reset_case
DNSMASQ_READY_AFTER="2"
stop_adguardhome || fail "delayed dnsmasq readiness made a healthy stop fail"
[ "${DNSMASQ_READY_CHECKS}" -eq 3 ] || fail "dnsmasq readiness was not retried to success"
[ "$(grep -c '^sleep 1$' "${CALLS_FILE}")" -eq 2 ] || fail "dnsmasq readiness retry delay count was incorrect"

# A dnsmasq restart that never becomes ready fails after the bounded retry window.
reset_case
DNSMASQ_RUNNING="0"
if stop_adguardhome; then fail "dnsmasq readiness timeout was hidden"; fi
[ "${DNSMASQ_READY_CHECKS}" -eq 5 ] || fail "dnsmasq readiness did not use the bounded retry count"
[ "$(grep -c '^sleep 1$' "${CALLS_FILE}")" -eq 4 ] || fail "dnsmasq readiness timeout delay count was incorrect"
grep -q 'reason=dnsmasq_not_ready.*attempts=5' "${CALLS_FILE}" || fail "dnsmasq readiness timeout was not logged"

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

# Unmanaged LAN mode checks only process state and installer handoff markers.
reset_case
DNSMASQ_MANAGED="0" DNSMASQ_RUNNING="0" SOCKET_MODE="none" LOOKUP_MODE="none" NETCHECK_STATUS="1"
stop_adguardhome || fail "unmanaged LAN stop incorrectly required dnsmasq or Internet readiness"
! grep -q '^netcheck$' "${CALLS_FILE}" || fail "unmanaged LAN stop performed an Internet connectivity check"

# Every managed, unmanaged, and restart-skipped pathway requires every configured
# installer handoff marker, including a dangling symlink, to be cleared.
for marker in "${DNS_HANDOFF_FILE}" "${DNS_HANDOFF_DIR}/lock"; do
	for marker_type in file dangling-symlink; do
		for pathway in managed unmanaged restart-skipped; do
			reset_case
			case "${pathway}" in
				unmanaged) DNSMASQ_MANAGED="0" ;;
				restart-skipped) ADGUARDHOME_SKIP_DNSMASQ_RESTART="1" ;;
			esac
			mkdir -p "${DNS_HANDOFF_DIR}"
			case "${marker_type}" in
				file) : >"${marker}" ;;
				dangling-symlink) ln -s "${TEST_ROOT}/missing-handoff-target" "${marker}" ;;
			esac
			if stop_adguardhome; then fail "${pathway} stop ignored stale ${marker_type} ${marker}"; fi
			grep -q 'reason=installer_marker_remains' "${CALLS_FILE}" ||
				fail "${pathway} stale ${marker_type} ${marker} was not logged"
		done
	done
done

printf '%s\n' "PASS: stop verification separates process, local DNS, and Internet readiness"
