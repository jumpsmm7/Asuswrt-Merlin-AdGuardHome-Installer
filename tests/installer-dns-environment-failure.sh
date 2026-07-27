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

sed -n '/^nvram_transaction_begin() {$/,/^installer_lan_domain_set() {$/p' "${INSTALLER_PATH}" |
	sed -e '$d' -e 's|/bin/nvram|nvram|g' -e 's|/bin/grep|grep|g' >"${FUNCTIONS_FILE}" || fail 'could not extract NVRAM transaction helpers'
sed -n '/^installer_lan_domain_set() {$/,/^rollback_result_write() {$/p' "${INSTALLER_PATH}" | sed -e '$d' -e 's|/bin/nvram|nvram|g' -e 's|/bin/grep|grep|g' >>"${FUNCTIONS_FILE}" || fail 'could not extract LAN-domain transaction helpers'
sed -n '/^check_dns_environment() {$/,/^check_dns_filter() {$/p' "${INSTALLER_PATH}" | sed '$d' >>"${FUNCTIONS_FILE}" || fail 'could not extract DNS environment helper'
sed -n '/^check_dns_filter() {$/,/^save_dns_filter_settings() {$/p' "${INSTALLER_PATH}" | sed '$d' >>"${FUNCTIONS_FILE}" || fail 'could not extract DNSFilter helper'
sed -n '/^restore_dns_filter_settings() {$/,/^check_ipset() {$/p' "${INSTALLER_PATH}" | sed '$d' >>"${FUNCTIONS_FILE}" || fail 'could not extract DNSFilter restore helper'
sed -n '/^on_installer_exit() {$/,/^python_bcrypt_available() {$/p' "${INSTALLER_PATH}" | sed '$d' >>"${FUNCTIONS_FILE}" || fail 'could not extract installer exit handler'
[ "$(sed -n '/^nvram_transaction_begin() {$/,/^installer_lan_domain_set() {$/p' "${INSTALLER_PATH}" | /bin/grep -Ec '(^|[[:space:];!])/bin/nvram (show|get|set|unset|commit)([[:space:];]|$)')" -eq 7 ] || fail 'NVRAM transaction helpers do not consistently use /bin/nvram'
[ "$(sed -n '/^nvram_transaction_begin() {$/,/^installer_lan_domain_set() {$/p' "${INSTALLER_PATH}" | /bin/grep -Ec '(^|[[:space:];!])/bin/grep -q ')" -eq 1 ] || fail 'NVRAM transaction helpers do not use /bin/grep for inventory matching'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

INFO='Info:'
ERROR='Error:'
WARNING='Warning:'
BASE_DIR="${TEST_ROOT}/base"
ROLLBACK_RESULT_FILE="${BASE_DIR}/rollback-result"
AGH_FILE="${TEST_ROOT}/AdGuardHome"
ADGUARD_INSTALL_MODE=wan
mkdir -p "${BASE_DIR}" || fail 'could not create installer-managed test directory'
DNS_ENV_READY_TIMEOUT=2
DNS_ENV_RECOVERY_TIMEOUT=1
MONOTONIC_NOW=0
PTXT() { printf '%s\n' "$*" >>"${CALLS_FILE}"; }
ptxt_phase() { PTXT "$1"; }
ptxt_step() { PTXT "$1"; }
ptxt_ok() { PTXT "$1"; }
pidof() { return 1; }
kill_processes() { return 0; }
cleanup_api_files() { :; }
installer_cleanup_tmp_file() { :; }
rollback_pending_mode_migration() { return 0; }
sleep() { MONOTONIC_NOW="$((MONOTONIC_NOW + 1))"; }
monotonic_seconds() {
	if [ "${MONOTONIC_FAIL_AT:-0}" != 0 ]; then
		MONOTONIC_CALLS="$(cat "${TEST_ROOT}/monotonic-calls" 2>/dev/null || printf 0)"
		MONOTONIC_CALLS="$((MONOTONIC_CALLS + 1))"
		printf '%s\n' "${MONOTONIC_CALLS}" >"${TEST_ROOT}/monotonic-calls"
		[ "${MONOTONIC_CALLS}" != "${MONOTONIC_FAIL_AT}" ] || return 1
	fi
	printf '%s\n' "${MONOTONIC_NOW}"
}
# check_connection checks simulated public network availability and increments the public connectivity check count.
check_connection() {
	PUBLIC_CHECK_COUNT="$((PUBLIC_CHECK_COUNT + 1))"
	[ "${PUBLIC_NETWORK_AVAILABLE:-0}" = 1 ]
}
# rollback_result_write records a rollback status message in the calls log.
rollback_result_write() { printf '%s\n' "rollback $*" >>"${CALLS_FILE}"; }

# nvram_value reads and prints the value for a key from the simulated NVRAM file.
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
	case "$*" in
		restart_dnsmasq | 'restart_firewall;restart_dnsmasq') ;;
		*) return 1 ;;
	esac
	SERVICE_COUNT="$((SERVICE_COUNT + 1))"
	printf '%s\n' 'service restart_dnsmasq' >>"${CALLS_FILE}"
	[ "${FAIL_SERVICE_AT:-0}" != "${SERVICE_COUNT}" ]
}

nslookup() {
	printf '%s\n' "nslookup $*" >>"${CALLS_FILE}"
	if [ "${TRACK_LOOKUP:-0}" = 1 ]; then
		trap 'printf "%s\n" reaped >"${TEST_ROOT}/lookup-reaped"; exit 1' TERM
	fi
	[ "${BLOCKING_QUERY:-0}" = 0 ] || /bin/sleep 5
	[ "${DNS_READY:-1}" = 1 ]
}

# dns_check_count counts the DNS lookup calls recorded in the calls log and writes the count to stdout.
dns_check_count() { grep -c '^nslookup ' "${CALLS_FILE}"; }

# reset_case resets the simulated NVRAM, call log, counters, failure injections, and DNS test state for a test case.
reset_case() {
	nvram_transaction_lock_release || fail 'could not release the previous test transaction lock'
	rm -rf "${BASE_DIR}/.AdGuardHome.nvram/dns-preparation"
	rm -rf "${BASE_DIR}/.AdGuardHome.nvram.lock" "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink" "${BASE_DIR}/.AdGuardHome.nvram.lock.d"
	cat >"${NVRAM_FILE}" <<'EOF_NVRAM'
dnspriv_enable=1
dhcpd_dns_router=0
dhcp_dns1_x=
dhcp_dns2_x=149.112.112.112
EOF_NVRAM
	: >"${CALLS_FILE}"
	SET_COUNT=0 COMMIT_COUNT=0 SERVICE_COUNT=0 DNS_CHECK_COUNT=0 PUBLIC_CHECK_COUNT=0
	FAIL_SHOW=0 FAIL_GET_KEY='' FAIL_ALL_SETS=0 FAIL_SET_AT=0 FAIL_COMMIT_AT=0 FAIL_SERVICE_AT=0 DNS_READY=1 PUBLIC_NETWORK_AVAILABLE=0
	BLOCKING_QUERY=0 TRACK_LOOKUP=0 MONOTONIC_NOW=0 MONOTONIC_FAIL_AT=0
	rm -f "${TEST_ROOT}/monotonic-calls" "${TEST_ROOT}/lookup-reaped"
	_DNS_NVRAM_SAVED=0 _DNS_NVRAM_ROLLBACK_ATTEMPTED=0
}

assert_original() {
	[ "$(nvram_value dnspriv_enable)" = 1 ] || fail "$1: dnspriv_enable was not restored"
	[ "$(nvram_value dhcpd_dns_router)" = 0 ] || fail "$1: dhcpd_dns_router was not restored"
	[ "$(nvram_value dhcp_dns1_x)" = '' ] || fail "$1: empty value was not restored"
	[ "$(nvram_value dhcp_dns2_x)" = 149.112.112.112 ] || fail "$1: dhcp_dns2_x was not restored"
}

for invalid_mode in '' invalid; do
	rm -rf "${BASE_DIR}/.AdGuardHome.nvram/dnsfilter"
	if check_dns_filter "${invalid_mode}" 2>"${TEST_ROOT}/invalid-mode.stderr"; then
		fail "invalid DNSFilter mode '${invalid_mode}' was accepted"
	fi
	[ ! -s "${TEST_ROOT}/invalid-mode.stderr" ] || fail "invalid DNSFilter mode '${invalid_mode}' emitted a shell diagnostic"
	[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/dnsfilter" ] || fail "invalid DNSFilter mode '${invalid_mode}' created a transaction snapshot"
done

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
nvram_transaction_begin cleanup dnspriv_enable || fail 'cleanup transaction snapshot failed'
nvram_transaction_set dnspriv_enable 0 || fail 'cleanup transaction staging failed'
: >"${NVRAM_TRANSACTION_DIR}/new.untracked" || fail 'could not create unrelated snapshot file'
nvram_transaction_apply - 1 || fail 'cleanup transaction apply failed'
[ ! -e "${NVRAM_TRANSACTION_DIR}/new.dnspriv_enable" ] || fail 'staged transaction value was not removed'
[ -f "${NVRAM_TRANSACTION_DIR}/new.untracked" ] || fail 'transaction cleanup removed an untracked file'
rm -rf "${NVRAM_TRANSACTION_DIR}" || fail 'could not remove cleanup transaction snapshot'

reset_case
nvram_transaction_begin dns-preparation dnspriv_enable dhcpd_dns_router dhcp_dns1_x dhcp_dns2_x || fail 'interrupted transaction snapshot failed'
[ ! -x /usr/bin/flock ] || [ "${NVRAM_TRANSACTION_LOCK_MODE:-}" = flock ] || fail 'descriptor-capable flock was not preferred for NVRAM transactions'
nvram_transaction_set dnspriv_enable 0 || fail 'interrupted transaction staging failed'
nvram_transaction_apply restart_dnsmasq 1 || fail 'interrupted transaction apply failed'
if BASE_DIR="${BASE_DIR}" FUNCTIONS_FILE="${FUNCTIONS_FILE}" sh -c '
	. "${FUNCTIONS_FILE}"
	rollback_result_write() { :; }
	nvram() { return 1; }
	service() { return 1; }
	nvram_transaction_begin dns-preparation dnspriv_enable dhcpd_dns_router dhcp_dns1_x dhcp_dns2_x
'; then
	fail 'overlapping installer acquired the live NVRAM transaction lock'
fi
[ "$(nvram_value dnspriv_enable)" = 0 ] || fail 'overlapping installer restored a live NVRAM transaction'
[ "${COMMIT_COUNT}" = 1 ] || fail 'overlapping installer committed while another transaction owner was live'
NVRAM_TRANSACTION_DIR=''
nvram_transaction_lock_release || fail 'live transaction owner could not release its lock'
nvram_transaction_begin dns-preparation dnspriv_enable dhcpd_dns_router dhcp_dns1_x dhcp_dns2_x || fail 'dirty transaction snapshot blocked a rerun'
assert_original 'dirty snapshot rerun'
[ "${COMMIT_COUNT}" = 2 ] || fail 'dirty snapshot rerun did not commit its restoration'
[ "${SERVICE_COUNT}" = 2 ] || fail 'dirty snapshot rerun did not restart dnsmasq after restoration'
[ -f "${NVRAM_TRANSACTION_DIR}/keys" ] || fail 'dirty snapshot rerun did not create a replacement snapshot'

nvram_transaction_lock_release || fail 'transaction owner could not release its lock for stale-lock recovery'
nvram_transaction_lock_flock_supports_fd() { return 1; }
ln -s 999999 "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink" || fail 'could not prepare stale symlink transaction lock'
nvram_transaction_begin stale-symlink-lock dnspriv_enable || fail 'stale symlink transaction lock blocked recovery'
[ "$(/usr/bin/readlink "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink")" = "$$" ] || fail 'stale symlink lock was not replaced by the live owner'
if BASE_DIR="${BASE_DIR}" FUNCTIONS_FILE="${FUNCTIONS_FILE}" sh -c '
	. "${FUNCTIONS_FILE}"
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	rollback_result_write() { :; }
	nvram() { return 1; }
	service() { return 1; }
	nvram_transaction_begin stale-symlink-lock dnspriv_enable
'; then
	fail 'symlink fallback allowed an overlapping NVRAM transaction owner'
fi
nvram_transaction_lock_release || fail 'symlink transaction owner could not release its lock'
nvram_transaction_lock_symlink_acquire() { return 2; }
mkdir "${BASE_DIR}/.AdGuardHome.nvram.lock.d" || fail 'could not prepare stale transaction lock'
printf '%s\n' 999999 >"${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid" || fail 'could not record stale transaction lock owner'
nvram_transaction_begin stale-lock dnspriv_enable || fail 'stale NVRAM transaction lock blocked recovery'
[ "$(cat "${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid")" = "$$" ] || fail 'stale transaction lock was not replaced by the live owner'
if BASE_DIR="${BASE_DIR}" FUNCTIONS_FILE="${FUNCTIONS_FILE}" sh -c '
	. "${FUNCTIONS_FILE}"
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	rollback_result_write() { :; }
	nvram() { return 1; }
	service() { return 1; }
	nvram_transaction_begin stale-lock dnspriv_enable
'; then
	fail 'mkdir fallback allowed an overlapping NVRAM transaction owner'
fi

reset_case
nvram_transaction_begin dns-preparation dnspriv_enable dhcpd_dns_router dhcp_dns1_x dhcp_dns2_x || fail 'clean transaction snapshot failed'
: >"${NVRAM_TRANSACTION_DIR}/stale" || fail 'could not mark clean snapshot for replacement check'
NVRAM_TRANSACTION_DIR=''
nvram_transaction_begin dns-preparation dnspriv_enable dhcpd_dns_router dhcp_dns1_x dhcp_dns2_x || fail 'clean transaction snapshot blocked a rerun'
[ ! -e "${NVRAM_TRANSACTION_DIR}/stale" ] || fail 'clean stale snapshot was not replaced'

reset_case
printf '%s\n' 'dnsfilter_enable_x=0' >>"${NVRAM_FILE}" || fail 'could not seed DNSFilter NVRAM state'
nvram_transaction_begin lan-domain lan_domain || fail 'LAN-domain interruption snapshot failed'
nvram_transaction_set lan_domain interrupted.example || fail 'LAN-domain interruption staging failed'
nvram_transaction_apply restart_dnsmasq 1 || fail 'LAN-domain interruption apply failed'
[ "$(nvram_value lan_domain)" = interrupted.example ] || fail 'LAN-domain interruption setup did not apply its change'
nvram_transaction_begin dnsfilter dnsfilter_enable_x || fail 'DNSFilter interruption snapshot failed'
nvram_transaction_set dnsfilter_enable_x 1 || fail 'DNSFilter interruption staging failed'
nvram_transaction_apply 'restart_firewall;restart_dnsmasq' 1 || fail 'DNSFilter interruption apply failed'
[ "$(nvram_value dnsfilter_enable_x)" = 1 ] || fail 'DNSFilter interruption setup did not apply its change'
on_installer_exit
[ "$(nvram_value lan_domain)" = '' ] || fail 'installer exit did not restore the interrupted LAN domain'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/lan-domain" ] || fail 'installer exit retained a successfully restored LAN-domain snapshot'
[ "$(nvram_value dnsfilter_enable_x)" = 0 ] || fail 'installer exit did not restore interrupted DNSFilter values'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/dnsfilter" ] || fail 'installer exit retained a successfully restored DNSFilter snapshot'

reset_case
DNS_ENV_READY_TIMEOUT=invalid
DNS_ENV_RECOVERY_TIMEOUT=invalid
check_dns_environment 0 || fail 'public network unavailability blocked local DNS preparation'
[ "${PUBLIC_CHECK_COUNT}" = 0 ] || fail 'DNS preparation used a public connectivity check'
[ "${DNS_ENV_READY_TIMEOUT}" = 60 ] || fail 'invalid startup readiness timeout did not use its numeric default'
[ "${DNS_ENV_RECOVERY_TIMEOUT}" = 15 ] || fail 'invalid recovery timeout did not use its numeric default'
finalize_dns_environment || fail 'successful DNS preparation snapshot could not be finalized'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/dns-preparation" ] || fail 'successful install retained its DNS preparation snapshot'
[ "$(nvram get dnspriv_enable)" = 0 ] || fail 'snapshot finalization restored successfully applied DNS settings'
nvram_transaction_begin dns-preparation dnspriv_enable dhcpd_dns_router dhcp_dns1_x dhcp_dns2_x || fail 'finalized DNS preparation snapshot blocked a later installer run'
rm -rf "${NVRAM_TRANSACTION_DIR}"

reset_case
DNS_ENV_READY_TIMEOUT=invalid
DNS_ENV_RECOVERY_TIMEOUT=invalid
check_dns_environment 0 || fail 'DNS preparation for explicit restore failed'
check_dns_environment 1 || fail 'successful DNS preparation could not restore its snapshot'
assert_original 'successful preparation'
DNS_ENV_READY_TIMEOUT=2
DNS_ENV_RECOVERY_TIMEOUT=1

reset_case
DNS_ENV_READY_TIMEOUT=08
DNS_ENV_RECOVERY_TIMEOUT=09
check_dns_environment 0 || fail 'leading-zero timeout fallback blocked DNS preparation'
[ "${DNS_ENV_READY_TIMEOUT}" = 60 ] || fail 'invalid octal startup timeout did not use its numeric default'
[ "${DNS_ENV_RECOVERY_TIMEOUT}" = 15 ] || fail 'invalid octal recovery timeout did not use its numeric default'
check_dns_environment 1 || fail 'leading-zero timeout case could not restore its snapshot'
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
[ ! -d "${BASE_DIR}/.AdGuardHome.nvram/dns-preparation" ] || fail 'completed set-failure rollback retained its snapshot'

reset_case
FAIL_ALL_SETS=1
check_dns_environment 0 && fail 'complete NVRAM set failure was accepted'
grep -q 'rollback NVRAM transaction rollback partial' "${CALLS_FILE}" || fail 'incomplete set-failure rollback did not preserve evidence'
[ -d "${BASE_DIR}/.AdGuardHome.nvram/dns-preparation" ] || fail 'incomplete set-failure rollback removed its snapshot'

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
[ "$(dns_check_count)" = 2 ] || fail 'local DNS and recovery checks were not bounded by their configured deadlines'

reset_case
DNS_READY=0
BLOCKING_QUERY=1
check_dns_environment 0 && fail 'blocking local DNS readiness failure was accepted'
[ "$(dns_check_count)" = 2 ] || fail 'blocking DNS queries exceeded the startup and recovery deadlines'

reset_case
BLOCKING_QUERY=1
TRACK_LOOKUP=1
MONOTONIC_FAIL_AT=2
check_dns_environment 0 && fail 'monotonic clock failure was accepted'
[ -f "${TEST_ROOT}/lookup-reaped" ] || fail 'monotonic clock failure did not reap the active DNS lookup'

reset_case
FAIL_COMMIT_AT=2
DNS_READY=0
check_dns_environment 0 && fail 'rollback commit failure was accepted'
grep -q 'rollback partial' "${CALLS_FILE}" || fail 'rollback commit failure was not reported as partial'

reset_case
FAIL_SERVICE_AT=2
DNS_READY=0
check_dns_environment 0 && fail 'rollback service restart failure was accepted'
grep -q 'rollback partial' "${CALLS_FILE}" || fail 'rollback service failure was not reported as partial'

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
grep -q '^[[:space:]]*if \[ "${ADGUARD_INSTALL_MODE:-wan}" = "wan" \] && ! finalize_dns_environment; then$' "${INSTALLER_PATH}" || fail 'successful WAN installation does not finalize its DNS preparation snapshot'

reset_case
(
	trap 'check_dns_environment 1 >/dev/null 2>&1 || :; exit 0' TERM
	nvram_transaction_begin dns-preparation dnspriv_enable dhcpd_dns_router dhcp_dns1_x dhcp_dns2_x || exit 1
	: >"${NVRAM_TRANSACTION_DIR}/dirty" || exit 1
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
