#!/bin/sh
# Verify DNS NVRAM changes fail safely and use bounded local readiness checks.

set -u

INSTALLER_PATH="${1:-installer}"
TEST_ROOT="${TMPDIR:-/tmp}/installer-dns-environment-failure.$$"
FUNCTIONS_FILE="${TEST_ROOT}/functions"
NVRAM_FILE="${TEST_ROOT}/nvram"
CALLS_FILE="${TEST_ROOT}/calls"
LOCK_REMOVE_COUNT=0
SYMLINK_LOCK_REMOVE_COUNT=0

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}
cleanup() { rm -rf "${TEST_ROOT}"; }
trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
mkdir -p "${TEST_ROOT}" || fail 'could not create test workspace'

: >"${FUNCTIONS_FILE}" || fail 'could not create test functions file'
sed -n '/^nvram_transaction_begin() {$/,/^installer_lan_domain_set() {$/p' "${INSTALLER_PATH}" |
	sed -e '$d' -e 's|/bin/nvram|nvram|g' -e 's|/bin/grep|grep|g' >>"${FUNCTIONS_FILE}" || fail 'could not extract NVRAM transaction helpers'
sed -n '/^installer_lan_domain_set() {$/,/^rollback_result_write() {$/p' "${INSTALLER_PATH}" | sed -e '$d' -e 's|/bin/nvram|nvram|g' -e 's|/bin/grep|grep|g' >>"${FUNCTIONS_FILE}" || fail 'could not extract LAN-domain transaction helpers'
sed -n '/^check_dns_environment() {$/,/^check_dns_filter() {$/p' "${INSTALLER_PATH}" | sed '$d' >>"${FUNCTIONS_FILE}" || fail 'could not extract DNS environment helper'
sed -n '/^check_dns_filter() {$/,/^save_dns_filter_settings() {$/p' "${INSTALLER_PATH}" | sed '$d' >>"${FUNCTIONS_FILE}" || fail 'could not extract DNSFilter helper'
sed -n '/^restore_dns_filter_settings() {$/,/^check_ipset() {$/p' "${INSTALLER_PATH}" | sed '$d' >>"${FUNCTIONS_FILE}" || fail 'could not extract DNSFilter restore helper'
sed -n '/^on_installer_exit() {$/,/^python_bcrypt_available() {$/p' "${INSTALLER_PATH}" | sed '$d' >>"${FUNCTIONS_FILE}" || fail 'could not extract installer exit handler'
sed -n '/^end_op_message() {$/,/^menu() {$/p' "${INSTALLER_PATH}" | sed '$d' >>"${FUNCTIONS_FILE}" || fail 'could not extract installer restart helper'
[ "$(sed -n '/^nvram_transaction_begin() {$/,/^installer_lan_domain_set() {$/p' "${INSTALLER_PATH}" | /bin/grep -Ec '(^|[[:space:];!])/bin/nvram (show|get|set|unset|commit)([[:space:];]|$)')" -eq 7 ] || fail 'NVRAM transaction helpers do not consistently use /bin/nvram'
[ "$(sed -n '/^nvram_transaction_begin() {$/,/^installer_lan_domain_set() {$/p' "${INSTALLER_PATH}" | /bin/grep -Ec '(^|[[:space:];!])/bin/grep -q ')" -eq 1 ] || fail 'NVRAM transaction helpers do not use /bin/grep for inventory matching'
LOCK_OWNER_FUNC_BODY="$(sed -n '/^nvram_transaction_lock_owner_current() {$/,/^nvram_transaction_lock_owner_live() {$/p' "${INSTALLER_PATH}")" || fail 'could not extract nvram_transaction_lock_owner_current function'
[ "$(
	/bin/grep -Ec '/(bin|usr/bin)/(sed|awk)' <<EOF
${LOCK_OWNER_FUNC_BODY}
EOF
)" -eq 0 ] || fail 'NVRAM lock owner parsing does not resolve sed and awk through PATH'
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
# PTXT appends a message to the calls log.
PTXT() { printf '%s\n' "$*" >>"${CALLS_FILE}"; }
# ptxt_phase forwards a phase message to the test output logger.
ptxt_phase() { PTXT "$1"; }
# ptxt_step writes a step message to the test call log.
ptxt_step() { PTXT "$1"; }
# ptxt_ok writes a success message to the test call log.
ptxt_ok() { PTXT "$1"; }
# pidof reports PID 1234 when the requested process is stubby and it is configured as running.
pidof() {
	[ "${STUBBY_RUNNING:-0}" = 1 ] && [ "$1" = stubby ] || return 1
	printf '%s\n' 1234
}
# killall increments the simulated stubby termination count and stops stubby unless termination is configured to remain stuck.
killall() {
	[ "$*" = '-q -9 stubby' ] || return 1
	STUBBY_KILL_COUNT="$((STUBBY_KILL_COUNT + 1))"
	[ "${STUBBY_KILL_STUCK:-0}" = 0 ] && STUBBY_RUNNING=0
}
# cleanup_api_files performs no operation.
cleanup_api_files() { :; }
# installer_cleanup_tmp_file performs temporary-file cleanup.
installer_cleanup_tmp_file() { :; }
# rollback_pending_mode_migration completes pending mode migration rollback successfully.
rollback_pending_mode_migration() { return 0; }
# sleep advances the simulated monotonic clock by one second.
sleep() { MONOTONIC_NOW="$((MONOTONIC_NOW + 1))"; }
# monotonic_seconds outputs the simulated monotonic timestamp and fails on the configured call number when MONOTONIC_FAIL_AT is set.
monotonic_seconds() {
	if [ "${MONOTONIC_FAIL_AT:-0}" != 0 ]; then
		MONOTONIC_CALLS="$(cat "${TEST_ROOT}/monotonic-calls" 2>/dev/null || printf 0)"
		MONOTONIC_CALLS="$((MONOTONIC_CALLS + 1))"
		printf '%s\n' "${MONOTONIC_CALLS}" >"${TEST_ROOT}/monotonic-calls"
		[ "${MONOTONIC_CALLS}" != "${MONOTONIC_FAIL_AT}" ] || return 1
	fi
	printf '%s\n' "${MONOTONIC_NOW}"
}
# check_connection checks whether the simulated public network is available and increments the connectivity check count.
check_connection() {
	PUBLIC_CHECK_COUNT="$((PUBLIC_CHECK_COUNT + 1))"
	[ "${PUBLIC_NETWORK_AVAILABLE:-0}" = 1 ]
}
# rollback_result_write appends a rollback status message to the calls log.
rollback_result_write() { printf '%s\n' "rollback $*" >>"${CALLS_FILE}"; }

# nvram_value reads and prints the value associated with a key from the simulated NVRAM file.
nvram_value() {
	awk -v key="$1" 'index($0, key "=") == 1 { print substr($0, length(key) + 2); found=1 } END { exit(found ? 0 : 1) }' "${NVRAM_FILE}"
}

# nvram simulates NVRAM display, retrieval, modification, removal, and commit operations with configurable failure injection.
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

# service simulates supported service restarts and returns failure when configured injection targets the restart.
service() {
	case "$*" in
		restart_dnsmasq | 'restart_firewall;restart_dnsmasq') ;;
		restart_stubby)
			STUBBY_RESTART_COUNT="$((STUBBY_RESTART_COUNT + 1))"
			;;
		*) return 1 ;;
	esac
	SERVICE_COUNT="$((SERVICE_COUNT + 1))"
	printf '%s\n' "service $*" >>"${CALLS_FILE}"
	if [ "${FAIL_ALL_SERVICES:-0}" = 0 ] && [ "${FAIL_SERVICE_AT:-0}" != "${SERVICE_COUNT}" ]; then
		case "$*" in
			restart_stubby) STUBBY_RUNNING=1 ;;
		esac
		return 0
	fi
	return 1
}

# rm removes files and directories, with optional simulated failures for staged files or the active NVRAM transaction directory.
rm() {
	if [ "${FAIL_SETUP_MARKER_REMOVE:-0}" = 1 ] && [ "$#" -eq 2 ] && [ "${1:-}" = -f ] && [ "${2:-}" = "${BASE_DIR}/.AdGuardHome.nvram/setup-committed" ]; then
		return 1
	fi
	if [ "${FAIL_STAGED_REMOVE:-0}" = 1 ] && [ "$#" -eq 2 ] && [ "${1:-}" = -f ]; then
		case "${2:-}" in
			"${NVRAM_TRANSACTION_DIR:-}"/new.*) return 1 ;;
		esac
	fi
	if [ "${FAIL_SNAPSHOT_REMOVE:-0}" = 1 ] && [ "$#" -eq 2 ] && [ "${1:-}" = -rf ] && [ "${2:-}" = "${NVRAM_TRANSACTION_DIR:-}" ]; then
		return 1
	fi
	if [ "$#" -eq 2 ] && [ "${1:-}" = -rf ] && [ "${2:-}" = "${BASE_DIR}/.AdGuardHome.nvram.lock.d" ]; then
		LOCK_REMOVE_COUNT="$((LOCK_REMOVE_COUNT + 1))"
		[ "${FAIL_LOCK_REMOVE_AT:-0}" != "${LOCK_REMOVE_COUNT}" ] || return 1
	fi
	if [ "$#" -ge 2 ] && [ "${1:-}" = -f ] && [ "${2:-}" = "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink" ]; then
		SYMLINK_LOCK_REMOVE_COUNT="$((SYMLINK_LOCK_REMOVE_COUNT + 1))"
		[ "${FAIL_SYMLINK_LOCK_REMOVE_AT:-0}" != "${SYMLINK_LOCK_REMOVE_COUNT}" ] || return 1
	fi
	command rm "$@"
}

# nslookup simulates a DNS lookup, optionally blocks for five seconds, and records termination when configured before reporting DNS readiness.
nslookup() {
	printf '%s\n' "nslookup $*" >>"${CALLS_FILE}"
	if [ "${TRACK_LOOKUP:-0}" = 1 ]; then
		trap 'printf "%s\n" reaped >"${TEST_ROOT}/lookup-reaped"; exit 1' TERM
	fi
	[ "${BLOCKING_QUERY:-0}" = 0 ] || /bin/sleep 5
	[ "${DNS_READY:-1}" = 1 ]
}

# dns_check_count counts recorded DNS lookup calls and writes the count to standard output.
dns_check_count() { grep -c '^nslookup ' "${CALLS_FILE}"; }

# reset_case restores the simulated test environment, counters, fault-injection settings, and NVRAM contents to their baseline state.
reset_case() {
	FAIL_LOCK_REMOVE_AT=0 FAIL_SETUP_MARKER_REMOVE=0 FAIL_SNAPSHOT_REMOVE=0 FAIL_STAGED_REMOVE=0
	LOCK_REMOVE_COUNT=0
	nvram_transaction_lock_release || fail 'could not release the previous test transaction lock'
	rm -rf "${BASE_DIR}/.AdGuardHome.nvram/dns-preparation" "${BASE_DIR}/.AdGuardHome.nvram/dnsfilter" "${BASE_DIR}/.AdGuardHome.nvram/lan-domain"
	rm -f "${BASE_DIR}/.AdGuardHome.nvram/setup-committed"
	NVRAM_TRANSACTION_DIR=''
	NVRAM_TRANSACTION_CHANGED=0
	rm -rf "${BASE_DIR}/.AdGuardHome.nvram.lock" "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink" "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink.reaper" "${BASE_DIR}/.AdGuardHome.nvram.lock.d" "${BASE_DIR}/.AdGuardHome.nvram.lock.reaper"
	cat >"${NVRAM_FILE}" <<'EOF_NVRAM'
dnspriv_enable=1
dhcpd_dns_router=0
dhcp_dns1_x=
dhcp_dns2_x=149.112.112.112
EOF_NVRAM
	: >"${CALLS_FILE}"
	SET_COUNT=0 COMMIT_COUNT=0 SERVICE_COUNT=0 DNS_CHECK_COUNT=0 PUBLIC_CHECK_COUNT=0 STUBBY_KILL_COUNT=0 STUBBY_RESTART_COUNT=0
	FAIL_SHOW=0 FAIL_GET_KEY='' FAIL_ALL_SETS=0 FAIL_SET_AT=0 FAIL_COMMIT_AT=0 FAIL_SERVICE_AT=0 FAIL_ALL_SERVICES=0 DNS_READY=1 PUBLIC_NETWORK_AVAILABLE=0
	BLOCKING_QUERY=0 TRACK_LOOKUP=0 MONOTONIC_NOW=0 MONOTONIC_FAIL_AT=0 STUBBY_RUNNING=0 STUBBY_KILL_STUCK=0
	DNS_ENV_READY_TIMEOUT=2 DNS_ENV_RECOVERY_TIMEOUT=1
	rm -f "${TEST_ROOT}/monotonic-calls" "${TEST_ROOT}/lookup-reaped"
	_DNS_STUBBY_STOPPED=0 _DNS_NVRAM_SAVED=0 _DNS_NVRAM_ROLLBACK_ATTEMPTED=0
}

reset_case
SYMLINK_SNAPSHOT_TARGET="${TEST_ROOT}/symlink-snapshot-target"
mkdir -p "${BASE_DIR}/.AdGuardHome.nvram" "${SYMLINK_SNAPSHOT_TARGET}" || fail 'could not create symlink snapshot target'
printf '%s\n' dnspriv_enable >"${SYMLINK_SNAPSHOT_TARGET}/keys" || fail 'could not create symlink snapshot keys'
printf '%s\n' 0 >"${SYMLINK_SNAPSHOT_TARGET}/dnspriv_enable" || fail 'could not create symlink snapshot value'
: >"${SYMLINK_SNAPSHOT_TARGET}/exists.dnspriv_enable" || fail 'could not create symlink snapshot existence marker'
: >"${SYMLINK_SNAPSHOT_TARGET}/dirty" || fail 'could not create symlink snapshot dirty marker'
ln -s "${SYMLINK_SNAPSHOT_TARGET}" "${BASE_DIR}/.AdGuardHome.nvram/dns-preparation" || fail 'could not create symlink transaction snapshot'
if nvram_transaction_begin dns-preparation dnspriv_enable; then
	fail 'symlink transaction snapshot was accepted'
fi
[ "$(nvram get dnspriv_enable)" = 1 ] || fail 'symlink transaction snapshot modified NVRAM'
[ -f "${SYMLINK_SNAPSHOT_TARGET}/dirty" ] || fail 'symlink transaction snapshot target was modified'
[ "${COMMIT_COUNT}" -eq 0 ] || fail 'symlink transaction snapshot committed NVRAM'
[ "${SERVICE_COUNT}" -eq 0 ] || fail 'symlink transaction snapshot restarted a service'
rm -f "${BASE_DIR}/.AdGuardHome.nvram/dns-preparation" || fail 'could not remove symlink transaction snapshot'
rm -rf "${SYMLINK_SNAPSHOT_TARGET}" || fail 'could not remove symlink snapshot target'

reset_case
nvram_transaction_begin lan-domain lan_domain || fail 'startup recovery transaction snapshot failed'
nvram_transaction_set lan_domain interrupted-startup.example || fail 'startup recovery transaction staging failed'
nvram_transaction_apply restart_dnsmasq 1 || fail 'startup recovery transaction apply failed'
nvram_transaction_lock_release || fail 'startup recovery could not simulate the interrupted owner exiting'
NVRAM_TRANSACTION_LOCK_MODE=''
NVRAM_TRANSACTION_DIR=''
NVRAM_TRANSACTION_CHANGED=0
nvram_transaction_recover_pending || fail 'startup recovery did not process the pending transaction'
[ "$(nvram get lan_domain)" = '' ] || fail 'startup recovery did not restore the pending LAN domain transaction'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/lan-domain" ] || fail 'startup recovery retained the restored LAN domain snapshot'
[ -z "${NVRAM_TRANSACTION_LOCK_MODE:-}" ] || fail 'startup recovery retained the NVRAM transaction lock'
[ "$(sed -n '/^trap '\''on_installer_exit'\'' EXIT$/,/^if \[ -n "${BLOCKLIST_ANALYZER_SHA256}" \]; then$/p' "${INSTALLER_PATH}" | grep -c '^if ! nvram_transaction_recover_pending; then$')" -eq 1 ] || fail 'installer startup does not recover pending NVRAM transactions before dispatch'

reset_case
mkdir -p "${BASE_DIR}/.AdGuardHome.nvram/lan-domain" "${BASE_DIR}/.AdGuardHome.nvram/dnsfilter" || fail 'could not create paired transaction snapshots'
: >"${BASE_DIR}/.AdGuardHome.nvram/lan-domain/dirty" || fail 'could not mark the LAN-domain transaction dirty'
: >"${BASE_DIR}/.AdGuardHome.nvram/dnsfilter/dirty" || fail 'could not mark the DNSFilter transaction dirty'
: >"${BASE_DIR}/.AdGuardHome.nvram/setup-committed" || fail 'could not publish the paired transaction completion marker'
rm -f "${BASE_DIR}/.AdGuardHome.nvram/lan-domain/dirty" || fail 'could not simulate interrupted paired transaction cleanup'
nvram_transaction_begin dnsfilter dnsfilter_enable_x || fail 'paired transaction recovery did not permit a new DNSFilter transaction'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/lan-domain" ] || fail 'paired transaction recovery retained the completed LAN-domain snapshot'
[ ! -f "${BASE_DIR}/.AdGuardHome.nvram/dnsfilter/dirty" ] || fail 'paired transaction recovery treated committed DNSFilter state as rollback state'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/setup-committed" ] || fail 'paired transaction recovery retained its completion marker after cleanup'
[ "${COMMIT_COUNT}" -eq 0 ] || fail 'paired transaction recovery rolled back committed NVRAM state'

reset_case
mkdir -p "${BASE_DIR}/.AdGuardHome.nvram" || fail 'could not create the paired transaction root'
: >"${BASE_DIR}/.AdGuardHome.nvram/setup-committed" || fail 'could not publish the stale paired transaction completion marker'
FAIL_SETUP_MARKER_REMOVE=1
if nvram_transaction_begin dnsfilter dnsfilter_enable_x; then
	fail 'new transaction started while the stale setup completion marker could not be removed'
fi
[ -f "${BASE_DIR}/.AdGuardHome.nvram/setup-committed" ] || fail 'failed marker cleanup did not retain the setup completion marker'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/dnsfilter" ] || fail 'failed marker cleanup created a new DNSFilter snapshot'
FAIL_SETUP_MARKER_REMOVE=0
nvram_transaction_begin dnsfilter dnsfilter_enable_x || fail 'transaction did not start after the stale setup completion marker became removable'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/setup-committed" ] || fail 'successful recovery retained the stale setup completion marker'

reset_case
LOCK_OWNER="$(nvram_transaction_lock_owner_current)" || fail 'could not determine the test process lock identity'
reaper_path="${BASE_DIR}/interrupted-publication.reaper"
BASE_DIR="${BASE_DIR}" FUNCTIONS_FILE="${FUNCTIONS_FILE}" reaper_path="${reaper_path}" sh -c '
	. "${FUNCTIONS_FILE}"
	trap '\''
		nvram_transaction_lock_reaper_release_active || exit 1
		[ -z "${NVRAM_TRANSACTION_REAPER_LOCK_MODE:-}" ] || exit 1
		[ -z "${NVRAM_TRANSACTION_REAPER_LOCK_PATH:-}" ] || exit 1
		exit 77
	'\'' HUP INT TERM
	nvram_transaction_lock_flock_supports_fd() {
		kill -TERM "$$"
		return 1
	}
	nvram_transaction_lock_reaper_acquire "${reaper_path}"
'
status="$?"
[ "${status}" -eq 77 ] || fail "interrupted reaper owner publication exited with status ${status} instead of 77"
[ ! -e "${reaper_path}" ] || fail 'interrupted reaper owner publication retained the legacy directory'

reset_case
LOCK_OWNER="$(nvram_transaction_lock_owner_current)" || fail 'could not restore the test process lock identity'
reaper_path="${BASE_DIR}/failed-owner-publication.reaper"
(
	# Fail only the owner publication: the explicit owner avoids an earlier
	# printf from owner discovery and exercises the acquisition rollback.
	printf() { return 1; }
	if nvram_transaction_lock_reaper_acquire "${reaper_path}" "${LOCK_OWNER}"; then
		exit 1
	fi
	[ -z "${NVRAM_TRANSACTION_REAPER_LOCK_MODE:-}" ] || exit 1
	[ -z "${NVRAM_TRANSACTION_REAPER_LOCK_PATH:-}" ] || exit 1
	[ ! -e "${reaper_path}" ] || exit 1
) || fail 'failed reaper owner publication retained active cleanup state'

reset_case
LOCK_OWNER="$(nvram_transaction_lock_owner_current)" || fail 'could not restore the test process lock identity'
reaper_path="${BASE_DIR}/interrupted-symlink-publication.reaper"
BASE_DIR="${BASE_DIR}" FUNCTIONS_FILE="${FUNCTIONS_FILE}" reaper_path="${reaper_path}" sh -c '
	. "${FUNCTIONS_FILE}"
	trap '\''
		nvram_transaction_lock_reaper_release_active || exit 1
		[ -z "${NVRAM_TRANSACTION_REAPER_LOCK_MODE:-}" ] || exit 1
		[ -z "${NVRAM_TRANSACTION_REAPER_LOCK_PATH:-}" ] || exit 1
		exit 78
	'\'' HUP INT TERM
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	ln() {
		command ln "$@" || return 1
		kill -TERM "$$"
	}
	nvram_transaction_lock_reaper_acquire "${reaper_path}"
'
status="$?"
[ "${status}" -eq 78 ] || fail "interrupted reaper symlink publication exited with status ${status} instead of 78"
[ ! -e "${reaper_path}" ] || fail 'interrupted reaper symlink publication retained the legacy directory'
[ ! -L "${reaper_path}.symlink" ] || fail 'interrupted reaper symlink publication retained the symlink marker'

reset_case
LOCK_OWNER="$(nvram_transaction_lock_owner_current)" || fail 'could not restore the test process lock identity'
reaper_path="${BASE_DIR}/returning-signal-symlink-publication.reaper"
(
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	ln() {
		command ln "$@" || return 1
		nvram_transaction_lock_reaper_release_active || return 1
	}
	nvram_transaction_lock_reaper_acquire "${reaper_path}" "${LOCK_OWNER}"
	status="$?"
	[ "${status}" -eq 1 ] || fail "returning signal cleanup symlink acquisition returned ${status} instead of 1"
	[ -z "${NVRAM_TRANSACTION_REAPER_LOCK_MODE:-}" ] || fail 'returning signal cleanup left symlink reaper mode active'
	[ -z "${NVRAM_TRANSACTION_REAPER_LOCK_PATH:-}" ] || fail 'returning signal cleanup left symlink reaper path active'
	[ ! -e "${reaper_path}" ] || fail 'returning signal cleanup retained the legacy reaper directory'
	[ ! -L "${reaper_path}.symlink" ] || fail 'returning signal cleanup retained the symlink reaper marker'
) || exit 1

reset_case
LOCK_OWNER="$(nvram_transaction_lock_owner_current)" || fail 'could not restore the test process lock identity'
reaper_path="${BASE_DIR}/returning-signal-failed-symlink-publication.reaper"
(
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	ln() {
		nvram_transaction_lock_reaper_release_active || return 1
		return 1
	}
	nvram_transaction_lock_reaper_acquire "${reaper_path}" "${LOCK_OWNER}"
	status="$?"
	[ "${status}" -eq 1 ] || fail "returning signal cleanup after failed symlink publication returned ${status} instead of 1"
	[ -z "${NVRAM_TRANSACTION_REAPER_LOCK_MODE:-}" ] || fail 'failed symlink publication reported an unowned mkdir reaper'
	[ -z "${NVRAM_TRANSACTION_REAPER_LOCK_PATH:-}" ] || fail 'failed symlink publication retained its released reaper path'
	[ ! -e "${reaper_path}" ] || fail 'failed symlink publication retained the released legacy reaper directory'
	[ ! -L "${reaper_path}.symlink" ] || fail 'failed symlink publication unexpectedly created a symlink marker'
) || exit 1

reset_case
LOCK_OWNER="$(nvram_transaction_lock_owner_current)" || fail 'could not restore the test process lock identity'
reaper_path="${BASE_DIR}/interrupted-stale-symlink-reclaim.reaper"
ln -s 999999999 "${reaper_path}.symlink" || fail 'could not prepare stale reaper symlink'
BASE_DIR="${BASE_DIR}" FUNCTIONS_FILE="${FUNCTIONS_FILE}" reaper_path="${reaper_path}" sh -c '
	. "${FUNCTIONS_FILE}"
	trap '\''
		nvram_transaction_lock_reaper_release_active || exit 1
		exit 79
	'\'' HUP INT TERM
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	mv() {
		command mv "$@" || return 1
		kill -TERM "$$"
	}
	printf "%s\n" "$$" >"${reaper_path}.test-pid"
	nvram_transaction_lock_reaper_acquire "${reaper_path}"
'
status="$?"
[ "${status}" -eq 79 ] || fail "interrupted stale reaper symlink reclaim exited with status ${status} instead of 79"
[ ! -e "${reaper_path}" ] || fail 'interrupted stale reaper symlink reclaim retained the legacy directory'
[ ! -L "${reaper_path}.symlink" ] || fail 'interrupted stale reaper symlink reclaim retained the published owner'
reaper_test_pid="$(cat "${reaper_path}.test-pid" 2>/dev/null)"
[ -z "$(find "${BASE_DIR}" -name "$(basename "${reaper_path}").symlink.${reaper_test_pid}:*" -print)" ] ||
	fail 'interrupted stale reaper symlink reclaim retained its temporary marker'
rm -f "${reaper_path}.test-pid"

reset_case
LOCK_OWNER="$(nvram_transaction_lock_owner_current)" || fail 'could not restore the test process lock identity'
reaper_path="${BASE_DIR}/pid-reused-stale-symlink.reaper"
reused_pid="${LOCK_OWNER%%:*}"
ln -s 999999999 "${reaper_path}.symlink" || fail 'could not prepare stale reaper symlink for PID-reuse recovery'
ln -s "${reused_pid}:1" "${reaper_path}.symlink.${reused_pid}" || fail 'could not prepare interrupted PID-only temporary marker'
(
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	nvram_transaction_lock_reaper_acquire "${reaper_path}" "${LOCK_OWNER}" ||
		fail 'PID reuse blocked stale reaper recovery'
	[ "$(nvram_transaction_lock_readlink "${reaper_path}.symlink")" = "${LOCK_OWNER}" ] ||
		fail 'PID-reuse recovery published the wrong reaper owner'
	nvram_transaction_lock_reaper_release "${reaper_path}" "${LOCK_OWNER}" ||
		fail 'PID-reuse recovery reaper was not released'
)
[ -L "${reaper_path}.symlink.${reused_pid}" ] || fail 'PID-reuse recovery removed an unverified legacy temporary marker'
rm -f "${reaper_path}.symlink.${reused_pid}"

reset_case
LOCK_OWNER="$(nvram_transaction_lock_owner_current)" || fail 'could not restore the test process lock identity'
reaper_path="${BASE_DIR}/busybox-mv-stale-symlink.reaper"
malformed_target="${BASE_DIR}/busybox-mv-target"
mkdir "${malformed_target}" || fail 'could not prepare malformed reaper symlink target'
ln -s "${malformed_target}" "${reaper_path}.symlink" || fail 'could not prepare malformed reaper symlink'
(
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	mv() {
		[ "${1:-}" != '-T' ] || return 1
		command mv "$@"
	}
	nvram_transaction_lock_reaper_acquire "${reaper_path}" "${LOCK_OWNER}" ||
		fail 'BusyBox mv rejection blocked stale reaper recovery'
	[ "$(nvram_transaction_lock_readlink "${reaper_path}.symlink")" = "${LOCK_OWNER}" ] ||
		fail 'BusyBox mv fallback published the wrong reaper owner'
	[ -z "$(find "${malformed_target}" -mindepth 1 -maxdepth 1 -print)" ] ||
		fail 'BusyBox mv fallback followed the malformed reaper symlink target'
	[ ! -e "${reaper_path}.symlink.${LOCK_OWNER}" ] && [ ! -L "${reaper_path}.symlink.${LOCK_OWNER}" ] ||
		fail 'BusyBox mv fallback retained its temporary marker'
	nvram_transaction_lock_reaper_release "${reaper_path}" "${LOCK_OWNER}" ||
		fail 'BusyBox mv fallback reaper was not released'
	[ ! -e "${reaper_path}" ] || fail 'BusyBox mv fallback retained the legacy reaper directory'
	[ ! -L "${reaper_path}.symlink" ] || fail 'BusyBox mv fallback retained the published reaper symlink'
)
rm -rf "${malformed_target}"

reset_case
LOCK_OWNER="$(nvram_transaction_lock_owner_current)" || fail 'could not restore the test process lock identity'
(
	# Exercise the terminal mkdir implementation independently of optional flock and readlink support.
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	nvram_transaction_lock_readlink() { return 127; }
	for reaper_path in "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink.reaper" "${BASE_DIR}/.AdGuardHome.nvram.lock.reaper"; do
		mkdir -p "${reaper_path}"
		nvram_transaction_lock_reaper_acquire "${reaper_path}" || fail "ownerless reaper lock was not reclaimed: ${reaper_path}"
		[ "$(cat "${reaper_path}/pid")" = "${LOCK_OWNER}" ] || fail "reclaimed ownerless reaper lock has the wrong owner: ${reaper_path}"
		nvram_transaction_lock_reaper_release "${reaper_path}" || fail "reclaimed ownerless reaper lock was not released: ${reaper_path}"

		mkdir -p "${reaper_path}"
		: >"${reaper_path}/pid"
		if nvram_transaction_lock_reaper_acquire "${reaper_path}"; then
			fail "initializing reaper lock with an empty owner was reclaimed: ${reaper_path}"
		fi
		[ -d "${reaper_path}" ] || fail "initializing reaper lock with an empty owner was removed: ${reaper_path}"
		[ ! -s "${reaper_path}/pid" ] || fail "initializing reaper lock owner was replaced: ${reaper_path}"
		rm -rf "${reaper_path}"

		mkdir -p "${reaper_path}"
		printf '%s\n' 999999999 >"${reaper_path}/pid"
		nvram_transaction_lock_reaper_acquire "${reaper_path}" || fail "stale reaper lock was not reclaimed: ${reaper_path}"
		[ "$(cat "${reaper_path}/pid")" = "${LOCK_OWNER}" ] || fail "reclaimed reaper lock has the wrong owner: ${reaper_path}"
		nvram_transaction_lock_reaper_release "${reaper_path}" || fail "reclaimed reaper lock was not released: ${reaper_path}"

		mkdir -p "${reaper_path}"
		printf '%s\n' "${LOCK_OWNER}" >"${reaper_path}/pid"
		if nvram_transaction_lock_reaper_acquire "${reaper_path}"; then
			fail "live reaper lock was reclaimed: ${reaper_path}"
		fi
		rm -rf "${reaper_path}"

		mkdir -p "${reaper_path}"
		printf '%s:0\n' "$$" >"${reaper_path}/pid"
		nvram_transaction_lock_reaper_acquire "${reaper_path}" || fail "PID-reused reaper lock was not reclaimed: ${reaper_path}"
		[ "$(cat "${reaper_path}/pid")" = "${LOCK_OWNER}" ] || fail "PID-reused reaper lock has the wrong replacement owner: ${reaper_path}"
		nvram_transaction_lock_reaper_release "${reaper_path}" || fail "PID-reused reaper lock was not released: ${reaper_path}"
	done
) || exit 1

(
	# Exercise explicit-owner handling in the terminal mkdir implementation.
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	nvram_transaction_lock_readlink() { return 127; }
	for reaper_path in "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink.reaper" "${BASE_DIR}/.AdGuardHome.nvram.lock.reaper"; do
		rm -rf "${reaper_path}"
		(
			# nvram_transaction_lock_owner_current reports an error and fails when an owner lookup is invoked unexpectedly.
			nvram_transaction_lock_owner_current() {
				printf '%s\n' 'Error: owner lookup invoked unexpectedly while an explicit owner was supplied' >&2
				return 1
			}
			nvram_transaction_lock_reaper_acquire "${reaper_path}" "${LOCK_OWNER}" || fail "explicit-owner reaper acquire failed while owner lookup was disabled: ${reaper_path}"
			[ "$(cat "${reaper_path}/pid" 2>/dev/null)" = "${LOCK_OWNER}" ] || fail "explicit-owner reaper acquire did not record the supplied owner: ${reaper_path}"
			nvram_transaction_lock_reaper_release "${reaper_path}" "${LOCK_OWNER}" || fail "explicit-owner reaper release failed while owner lookup was disabled: ${reaper_path}"
		) || exit 1
		[ ! -e "${reaper_path}" ] || fail "explicit-owner reaper release did not remove the reaper directory: ${reaper_path}"

		nvram_transaction_lock_reaper_acquire "${reaper_path}" '' || fail "empty explicit owner did not fall back to the owner lookup: ${reaper_path}"
		[ "$(cat "${reaper_path}/pid" 2>/dev/null)" = "${LOCK_OWNER}" ] || fail "empty explicit owner recorded an unexpected owner: ${reaper_path}"
		nvram_transaction_lock_reaper_release "${reaper_path}" '' || fail "empty explicit owner release did not fall back to the owner lookup: ${reaper_path}"
		[ ! -e "${reaper_path}" ] || fail "empty explicit owner release did not remove the reaper directory: ${reaper_path}"
	done
) || exit 1

(
	# A live directory is the mutex used by older installers. New capability
	# modes must honor it before publishing their mode-specific artifacts.
	reaper_path="${BASE_DIR}/.AdGuardHome.nvram.legacy-reaper"
	mkdir "${reaper_path}" || fail 'could not prepare legacy reaper lock'
	printf '%s\n' "${LOCK_OWNER}" >"${reaper_path}/pid" || fail 'could not record legacy reaper owner'
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	nvram_transaction_lock_reaper_acquire "${reaper_path}"
	status="$?"
	[ "${status}" -eq 1 ] || fail "symlink reaper returned ${status} instead of 1 for a live legacy reaper"
	[ ! -L "${reaper_path}.symlink" ] || fail 'symlink reaper bypassed a live legacy reaper'
	[ "$(cat "${reaper_path}/pid" 2>/dev/null)" = "${LOCK_OWNER}" ] || fail 'symlink reaper changed the legacy reaper owner'
	rm -rf "${reaper_path}"
) || exit 1

if nvram_transaction_lock_flock_supports_fd; then
	BASE_DIR="${BASE_DIR}" FUNCTIONS_FILE="${FUNCTIONS_FILE}" sh -c '
		. "${FUNCTIONS_FILE}"
		reaper_path="${BASE_DIR}/returning-signal-flock-acquisition.reaper"
		nvram_transaction_lock_reaper_flock_acquire() {
			/usr/bin/flock -n 9 >/dev/null 2>&1 || return 1
			nvram_transaction_lock_reaper_release_active || return 1
			return 0
		}
		nvram_transaction_lock_reaper_acquire "${reaper_path}"
		status="$?"
		[ "${status}" -ne 0 ] || exit 81
		[ "${status}" -eq 1 ] || exit 82
		[ -z "${NVRAM_TRANSACTION_REAPER_LOCK_MODE:-}" ] || exit 83
		[ -z "${NVRAM_TRANSACTION_REAPER_LOCK_PATH:-}" ] || exit 84
		[ ! -L "/proc/$$/fd/9" ] || exit 85
		[ ! -e "${reaper_path}" ] || exit 86
	'
	status="$?"
	[ "${status}" -eq 0 ] || fail "returning signal cleanup flock regression exited with status ${status}"

	BASE_DIR="${BASE_DIR}" FUNCTIONS_FILE="${FUNCTIONS_FILE}" sh -c '
		. "${FUNCTIONS_FILE}"
		reaper_path="${BASE_DIR}/interrupted-flock-acquisition.reaper"
		trap '\''
			nvram_transaction_lock_reaper_release_active || exit 1
			[ ! -e "/proc/$$/fd/9" ] || exit 1
			[ ! -e "${reaper_path}" ] || exit 1
			exit 80
		'\'' HUP INT TERM
		nvram_transaction_lock_reaper_flock_acquire() {
			/usr/bin/flock -n 9 >/dev/null 2>&1 || return 1
			kill -TERM "$$"
		}
		nvram_transaction_lock_reaper_acquire "${reaper_path}"
	'
	status="$?"
	[ "${status}" -eq 80 ] || fail "interrupted flock reaper acquisition exited with status ${status} instead of 80"
	[ ! -e "${BASE_DIR}/interrupted-flock-acquisition.reaper" ] || fail 'interrupted flock reaper acquisition retained the legacy mutex'

	(
		reaper_path="${BASE_DIR}/.AdGuardHome.nvram.legacy-flock-reaper"
		mkdir "${reaper_path}" || fail 'could not prepare legacy reaper before flock acquisition'
		printf '%s\n' "${LOCK_OWNER}" >"${reaper_path}/pid" || fail 'could not record legacy reaper owner before flock acquisition'
		nvram_transaction_lock_reaper_acquire "${reaper_path}"
		status="$?"
		[ "${status}" -eq 1 ] || fail "flock reaper returned ${status} instead of 1 for a live legacy reaper"
		[ ! -e "/proc/$$/fd/9" ] || fail 'flock reaper opened its descriptor through a live legacy reaper'
		[ "$(cat "${reaper_path}/pid" 2>/dev/null)" = "${LOCK_OWNER}" ] || fail 'flock reaper changed the legacy reaper owner'
		rm -rf "${reaper_path}"
	) || exit 1
fi

(
	reaper_path="${BASE_DIR}/.AdGuardHome.nvram.capability-reaper"
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	nvram_transaction_lock_reaper_acquire "${reaper_path}" || fail 'symlink-capable reaper lock could not be acquired'
	[ "${NVRAM_TRANSACTION_REAPER_LOCK_MODE:-}" = symlink ] || fail 'reaper did not select the symlink transaction-lock capability'
	[ "$(readlink "${reaper_path}.symlink")" = "${LOCK_OWNER}" ] || fail 'symlink-capable reaper recorded the wrong owner'
	nvram_transaction_lock_reaper_release "${reaper_path}" || fail 'symlink-capable reaper lock could not be released'
	[ ! -L "${reaper_path}.symlink" ] || fail 'symlink-capable reaper lock remained after release'
) || exit 1

for reentrant_mode in symlink mkdir; do
	(
		reaper_path="${BASE_DIR}/.AdGuardHome.nvram.reentrant-${reentrant_mode}-reaper"
		nvram_transaction_lock_flock_supports_fd() { return 1; }
		if [ "${reentrant_mode}" = mkdir ]; then
			nvram_transaction_lock_readlink() { return 127; }
		fi
		nvram_transaction_lock_reaper_acquire "${reaper_path}" "${LOCK_OWNER}" ||
			fail "${reentrant_mode} reaper could not be acquired for reentrant release"
		[ "${NVRAM_TRANSACTION_REAPER_LOCK_MODE:-}" = "${reentrant_mode}" ] ||
			fail "${reentrant_mode} reaper selected the wrong mode for reentrant release"
		REENTRANT_RELEASES=0
		rm() {
			if [ "${1:-}" = -rf ] && [ "${2:-}" = "${reaper_path}" ]; then
				command rm "$@" || return 1
				REENTRANT_RELEASES=$((REENTRANT_RELEASES + 1))
				nvram_transaction_lock_reaper_release_active || return 1
				return 0
			fi
			command rm "$@"
		}
		nvram_transaction_lock_reaper_release "${reaper_path}" "${LOCK_OWNER}" ||
			fail "${reentrant_mode} reaper release failed after deleting its mutex"
		[ "${REENTRANT_RELEASES}" -eq 1 ] || fail "${reentrant_mode} reentrant release hook was not reached"
		[ -z "${NVRAM_TRANSACTION_REAPER_LOCK_MODE:-}" ] || fail "${reentrant_mode} reentrant release retained its mode"
		[ -z "${NVRAM_TRANSACTION_REAPER_LOCK_PATH:-}" ] || fail "${reentrant_mode} reentrant release retained its path"
		[ ! -e "${reaper_path}" ] || fail "${reentrant_mode} reentrant release retained its mutex"
	) || exit 1
done

(
	reaper_path="${BASE_DIR}/.AdGuardHome.nvram.unsupported-symlink-reaper"
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	# ln simulates a filesystem that supports readlink but rejects symlink creation.
	ln() { return 1; }
	nvram_transaction_lock_reaper_acquire "${reaper_path}" || fail 'failed symlink publication did not select the mkdir reaper fallback'
	[ "${NVRAM_TRANSACTION_REAPER_LOCK_MODE:-}" = mkdir ] || fail 'failed symlink publication selected the wrong reaper fallback'
	[ "$(cat "${reaper_path}/pid" 2>/dev/null)" = "${LOCK_OWNER}" ] || fail 'mkdir reaper fallback recorded the wrong owner'
	nvram_transaction_lock_reaper_release "${reaper_path}" || fail 'mkdir reaper fallback could not be released'

	mkdir "${reaper_path}" || fail 'could not prepare stale mkdir reaper after failed symlink publication'
	printf '%s\n' 999999999 >"${reaper_path}/pid" || fail 'could not record stale mkdir reaper owner after failed symlink publication'
	nvram_transaction_lock_reaper_acquire "${reaper_path}" || fail 'failed symlink publication blocked stale mkdir reaper recovery'
	[ "${NVRAM_TRANSACTION_REAPER_LOCK_MODE:-}" = mkdir ] || fail 'stale mkdir reaper recovery selected the wrong fallback mode'
	[ "$(cat "${reaper_path}/pid" 2>/dev/null)" = "${LOCK_OWNER}" ] || fail 'stale mkdir reaper was not replaced by the live owner'
	nvram_transaction_lock_reaper_release "${reaper_path}" || fail 'reclaimed mkdir reaper fallback could not be released'
) || exit 1

if nvram_transaction_lock_flock_supports_fd; then
	(
		reaper_path="${BASE_DIR}/.AdGuardHome.nvram.capability-reaper"
		nvram_transaction_lock_reaper_acquire "${reaper_path}" || fail 'flock-capable reaper lock could not be acquired'
		[ "${NVRAM_TRANSACTION_REAPER_LOCK_MODE:-}" = flock ] || fail 'reaper did not select the flock transaction-lock capability'
		[ "$(cat "${reaper_path}/pid" 2>/dev/null)" = "${LOCK_OWNER}" ] || fail 'flock-capable reaper did not publish its legacy-compatible owner'
		nvram_transaction_lock_reaper_release "${reaper_path}" || fail 'flock-capable reaper lock could not be released'
	) || exit 1

	(
		reaper_path="${BASE_DIR}/.AdGuardHome.nvram.reentrant-flock-reaper"
		nvram_transaction_lock_reaper_acquire "${reaper_path}" "${LOCK_OWNER}" ||
			fail 'flock reaper could not be acquired for reentrant release'
		REENTRANT_RELEASES=0
		rm() {
			if [ "${1:-}" = -rf ] && [ "${2:-}" = "${reaper_path}" ]; then
				command rm "$@" || return 1
				REENTRANT_RELEASES=$((REENTRANT_RELEASES + 1))
				nvram_transaction_lock_reaper_release_active || return 1
				return 0
			fi
			command rm "$@"
		}
		nvram_transaction_lock_reaper_release "${reaper_path}" "${LOCK_OWNER}" ||
			fail 'flock reaper release failed after deleting its mutex'
		[ "${REENTRANT_RELEASES}" -eq 1 ] || fail 'flock reentrant release hook was not reached'
		[ ! -e "/proc/self/fd/9" ] || fail 'flock reentrant release retained descriptor 9'
		[ -z "${NVRAM_TRANSACTION_REAPER_LOCK_MODE:-}" ] || fail 'flock reentrant release retained its mode'
		[ ! -e "${reaper_path}" ] || fail 'flock reentrant release retained its mutex'
	) || exit 1

	(
		reaper_path="${BASE_DIR}/.AdGuardHome.nvram.retryable-flock-reaper"
		nvram_transaction_lock_reaper_acquire "${reaper_path}" "${LOCK_OWNER}" || fail 'retryable flock reaper lock could not be acquired'
		[ "${NVRAM_TRANSACTION_REAPER_LOCK_MODE:-}" = flock ] || fail 'retryable reaper did not select flock mode'
		REMOVE_ATTEMPTS=0
		rm() {
			if [ "${1:-}" = -rf ] && [ "${2:-}" = "${reaper_path}" ]; then
				REMOVE_ATTEMPTS=$((REMOVE_ATTEMPTS + 1))
				[ "${REMOVE_ATTEMPTS}" -gt 1 ] || return 1
			fi
			command rm "$@"
		}
		if nvram_transaction_lock_reaper_release "${reaper_path}" "${LOCK_OWNER}"; then
			fail 'flock reaper release ignored a transient legacy mutex removal failure'
		else
			release_status=$?
			[ "${release_status}" -eq 1 ] || fail 'unexpected flock reaper release status'
			[ "${REMOVE_ATTEMPTS}" -eq 1 ] || fail 'injected legacy mutex removal failure was not reached'
		fi
		[ "${NVRAM_TRANSACTION_REAPER_LOCK_MODE:-}" = flock ] || fail 'failed flock reaper release discarded its retryable mode'
		[ -e "/proc/self/fd/9" ] || fail 'failed flock reaper release closed its retryable descriptor'
		[ -d "${reaper_path}" ] || fail 'failed flock reaper release unexpectedly removed its legacy mutex'
		[ "$(cat "${reaper_path}/pid" 2>/dev/null)" = "${LOCK_OWNER}" ] ||
			fail 'failed flock reaper release changed its legacy mutex owner'
		nvram_transaction_lock_reaper_release "${reaper_path}" "${LOCK_OWNER}" || fail 'flock reaper release retry did not succeed'
		[ "${REMOVE_ATTEMPTS}" -eq 2 ] || fail 'flock reaper release retry did not repeat legacy mutex removal'
		[ ! -e "/proc/self/fd/9" ] || fail 'successful flock reaper release retained descriptor 9'
		[ ! -e "${reaper_path}" ] || fail 'successful flock reaper release retained its legacy mutex'
		[ -z "${NVRAM_TRANSACTION_REAPER_LOCK_MODE:-}" ] || fail 'successful flock reaper release retained its active mode'
	) || exit 1
fi

if nvram_transaction_lock_flock_supports_fd; then
	# nvram_transaction_lock_owner_current fails to prove flock-mode lock helpers never need the process owner identity.
	# Run this check outside a subshell: flock ownership is tracked via /proc/$$/fd/8, and $$ keeps the
	# nvram_transaction_lock_owner_current() rejects owner lookups when flock mode should provide ownership directly.
	nvram_transaction_lock_owner_current() {
		printf '%s\n' 'Error: owner lookup invoked unexpectedly for flock mode' >&2
		return 1
	}
	nvram_transaction_lock_acquire || fail 'flock transaction lock could not be acquired while owner lookup was disabled'
	[ "${NVRAM_TRANSACTION_LOCK_MODE:-}" = flock ] || fail 'flock mode was not selected while owner lookup was disabled'
	nvram_transaction_lock_owned || fail 'flock transaction lock ownership check failed while owner lookup was disabled'
	nvram_transaction_lock_acquire || fail 'flock transaction lock fast-path re-acquire failed while owner lookup was disabled'
	nvram_transaction_lock_release || fail 'flock transaction lock could not be released while owner lookup was disabled'
	nvram_transaction_lock_owned && fail 'flock transaction lock ownership check succeeded after release while owner lookup was disabled'
	mv "${BASE_DIR}" "${TEST_ROOT}/base-resolved" || fail 'could not prepare resolved flock lock test directory'
	ln -s "${TEST_ROOT}/base-resolved" "${BASE_DIR}" || fail 'could not create symlinked flock lock test directory'
	nvram_transaction_lock_acquire || fail 'flock transaction lock could not be acquired through a symlinked base path'
	nvram_transaction_lock_owned || fail 'flock ownership did not resolve a symlinked base path'
	nvram_transaction_lock_release || fail 'flock transaction lock through a symlinked base path could not be released'
	rm -f "${BASE_DIR}" || fail 'could not remove symlinked flock lock test directory'
	mv "${TEST_ROOT}/base-resolved" "${BASE_DIR}" || fail 'could not restore flock lock test directory'
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
fi

# assert_original verifies that the simulated NVRAM contains the expected original DNS settings, failing with the provided label if any value differs.
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
nvram_transaction_begin staged-cleanup dnspriv_enable || fail 'staged cleanup transaction snapshot failed'
nvram_transaction_set dnspriv_enable 0 || fail 'staged cleanup transaction staging failed'
FAIL_STAGED_REMOVE=1
nvram_transaction_apply - 1 && fail 'staged value removal failure was ignored'
[ "$(nvram get dnspriv_enable)" = 1 ] || fail 'staged value removal failure did not roll back NVRAM'
[ -f "${NVRAM_TRANSACTION_DIR}/new.dnspriv_enable" ] || fail 'staged value removal failure did not preserve recovery evidence'
[ "${NVRAM_TRANSACTION_CHANGED}" = 1 ] || fail 'staged value removal failure cleared the changed-state marker'
FAIL_STAGED_REMOVE=0
rm -rf "${NVRAM_TRANSACTION_DIR}" || fail 'could not remove staged cleanup transaction snapshot'

reset_case
nvram_transaction_begin clean-cleanup dnspriv_enable || fail 'clean cleanup transaction snapshot failed'
FAIL_SNAPSHOT_REMOVE=1
nvram_transaction_restore - && fail 'clean snapshot removal failure was ignored'
[ -d "${NVRAM_TRANSACTION_DIR}" ] || fail 'clean snapshot was not retained after removal failure'
FAIL_SNAPSHOT_REMOVE=0
rm -rf "${NVRAM_TRANSACTION_DIR}" || fail 'could not remove clean cleanup transaction snapshot'

reset_case
nvram_transaction_begin clean-apply-cleanup dnspriv_enable || fail 'clean apply transaction snapshot failed'
FAIL_SNAPSHOT_REMOVE=1
nvram_transaction_apply - && fail 'clean apply snapshot removal failure was ignored'
[ -d "${NVRAM_TRANSACTION_DIR}" ] || fail 'clean apply snapshot was not retained after removal failure'
FAIL_SNAPSHOT_REMOVE=0
rm -rf "${NVRAM_TRANSACTION_DIR}" || fail 'could not remove clean apply transaction snapshot'

reset_case
nvram_transaction_begin dirty-apply-cleanup dnspriv_enable || fail 'dirty apply transaction snapshot failed'
nvram_transaction_set dnspriv_enable 0 || fail 'dirty apply transaction staging failed'
FAIL_SNAPSHOT_REMOVE=1
nvram_transaction_apply - && fail 'dirty apply snapshot removal failure was ignored'
[ -f "${NVRAM_TRANSACTION_DIR}/dirty" ] || fail 'dirty apply snapshot was not retained after removal failure'
[ "$(nvram get dnspriv_enable)" = 0 ] || fail 'dirty apply cleanup failure unexpectedly rolled back NVRAM'
FAIL_SNAPSHOT_REMOVE=0
rm -rf "${NVRAM_TRANSACTION_DIR}" || fail 'could not remove dirty apply transaction snapshot'

reset_case
installer_lan_domain_set router.test 1 || fail 'LAN domain cleanup transaction apply failed'
FAIL_SNAPSHOT_REMOVE=1
installer_lan_domain_restore && fail 'LAN domain snapshot removal failure was ignored'
[ -d "${NVRAM_TRANSACTION_DIR}" ] || fail 'LAN domain snapshot was not retained after removal failure'
FAIL_SNAPSHOT_REMOVE=0
rm -rf "${NVRAM_TRANSACTION_DIR}" || fail 'could not remove LAN domain cleanup transaction snapshot'

reset_case
nvram_transaction_begin dns-preparation dnspriv_enable || fail 'DNS restore cleanup transaction snapshot failed'
nvram_transaction_set dnspriv_enable 0 || fail 'DNS restore cleanup transaction staging failed'
nvram_transaction_apply restart_dnsmasq 1 || fail 'DNS restore cleanup transaction apply failed'
_DNS_NVRAM_SAVED=1
FAIL_SNAPSHOT_REMOVE=1
check_dns_environment 1 && fail 'DNS restore snapshot removal failure was ignored'
[ "${_DNS_NVRAM_SAVED}" = 1 ] || fail 'DNS restore snapshot removal failure cleared the saved-state marker'
[ -d "${NVRAM_TRANSACTION_DIR}" ] || fail 'DNS restore snapshot removal failure did not preserve the snapshot'
grep -q "snapshot preserved at ${NVRAM_TRANSACTION_DIR}" "${CALLS_FILE}" || fail 'DNS restore snapshot removal failure was not recorded as partial'
FAIL_SNAPSHOT_REMOVE=0
rm -rf "${NVRAM_TRANSACTION_DIR}" || fail 'could not remove DNS restore cleanup transaction snapshot'

reset_case
nvram_transaction_begin dns-preparation dnspriv_enable dhcpd_dns_router dhcp_dns1_x dhcp_dns2_x || fail 'interrupted transaction snapshot failed'
if nvram_transaction_lock_flock_supports_fd; then
	[ "${NVRAM_TRANSACTION_LOCK_MODE:-}" = flock ] || fail 'descriptor-capable flock was not preferred for NVRAM transactions'
fi
nvram_transaction_set dnspriv_enable 0 || fail 'interrupted transaction staging failed'
nvram_transaction_apply restart_dnsmasq 1 || fail 'interrupted transaction apply failed'
if BASE_DIR="${BASE_DIR}" FUNCTIONS_FILE="${FUNCTIONS_FILE}" sh -c '
	. "${FUNCTIONS_FILE}"
	exec 8>&-
	nvram_transaction_lock_acquire
'; then
	fail 'overlapping installer acquired the live NVRAM transaction lock'
fi
for inherited_lock_mode in flock symlink mkdir invalid; do
	if BASE_DIR="${BASE_DIR}" FUNCTIONS_FILE="${FUNCTIONS_FILE}" NVRAM_TRANSACTION_LOCK_MODE="${inherited_lock_mode}" sh -c '
		. "${FUNCTIONS_FILE}"
		exec 8>&-
		nvram_transaction_lock_acquire
	'; then
		fail "inherited ${inherited_lock_mode} mode bypassed the live NVRAM transaction lock"
	fi
done
if nvram_transaction_lock_flock_supports_fd; then
	BASE_DIR="${BASE_DIR}" FUNCTIONS_FILE="${FUNCTIONS_FILE}" TEST_ROOT="${TEST_ROOT}" sh -c '
		. "${FUNCTIONS_FILE}"
		exec 8>"${TEST_ROOT}/unrelated-fd"
		NVRAM_TRANSACTION_LOCK_MODE=flock
		nvram_transaction_lock_owned && exit 1
		nvram_transaction_lock_release && exit 1
		printf "%s\n" retained >&8
	' || fail 'unrelated descriptor was accepted, closed, or released as the flock transaction lock'
	[ "$(cat "${TEST_ROOT}/unrelated-fd")" = retained ] || fail 'unrelated descriptor content was not preserved'
	if BASE_DIR="${BASE_DIR}" FUNCTIONS_FILE="${FUNCTIONS_FILE}" TEST_ROOT="${TEST_ROOT}" sh -c '
		. "${FUNCTIONS_FILE}"
		exec 8>"${TEST_ROOT}/unrelated-acquire-fd"
		NVRAM_TRANSACTION_LOCK_MODE=flock
		nvram_transaction_lock_acquire
	'; then
		fail 'unrelated descriptor bypassed the live flock transaction lock'
	fi
fi
BASE_DIR="${BASE_DIR}" FUNCTIONS_FILE="${FUNCTIONS_FILE}" TEST_ROOT="${TEST_ROOT}" sh -c '
	. "${FUNCTIONS_FILE}"
	exec 8>&-
	ADGUARD_INSTALL_MODE=wan
	AGH_FILE="${TEST_ROOT}/missing-AdGuardHome"
	cleanup_api_files() { :; }
	installer_cleanup_tmp_file() { :; }
	installer_lan_domain_restore() { : >"${TEST_ROOT}/non-owner-rollback"; }
	restore_dns_filter_settings() { : >"${TEST_ROOT}/non-owner-rollback"; }
	check_dns_environment() { : >"${TEST_ROOT}/non-owner-rollback"; }
	PTXT() { :; }
	on_installer_exit
' || fail 'non-owner installer exit handler failed'
[ ! -e "${TEST_ROOT}/non-owner-rollback" ] || fail 'non-owner installer exit rolled back the live NVRAM transaction'
[ "$(nvram_value dnspriv_enable)" = 0 ] || fail 'overlapping installer restored a live NVRAM transaction'
[ "${COMMIT_COUNT}" = 1 ] || fail 'overlapping installer committed while another transaction owner was live'

(
	ADGUARD_INSTALL_MODE=wan
	ERROR='Error:'
	# cleanup_api_files performs no operation.
	cleanup_api_files() { :; }
	# installer_cleanup_tmp_file performs temporary-file cleanup.
	installer_cleanup_tmp_file() { :; }
	# installer_lan_domain_restore restores the original LAN domain settings from the active transaction snapshot.
	installer_lan_domain_restore() { :; }
	# restore_dns_filter_settings restores DNSFilter settings and returns a failure status.
	restore_dns_filter_settings() { return 1; }
	# check_dns_environment prepares the local DNS environment, verifies local DNS readiness within bounded deadlines, and restores transactional NVRAM state when requested.
	check_dns_environment() { :; }
	# nvram_transaction_lock_owned reports that the current process owns the NVRAM transaction lock.
	nvram_transaction_lock_owned() { return 0; }
	# nvram_transaction_lock_release releases the active NVRAM transaction lock.
	nvram_transaction_lock_release() { return 0; }
	: >"${CALLS_FILE}"
	on_installer_exit
	grep -Fq "Unable to restore the DNSFilter NVRAM settings; review ${ROLLBACK_RESULT_FILE} and the preserved snapshot before restarting setup." "${CALLS_FILE}" ||
		fail 'installer exit did not report an actionable DNSFilter rollback failure'
) || exit 1

NVRAM_TRANSACTION_DIR=''
nvram_transaction_lock_release || fail 'live transaction owner could not release its lock'
nvram_transaction_begin dns-preparation dnspriv_enable dhcpd_dns_router dhcp_dns1_x dhcp_dns2_x || fail 'dirty transaction snapshot blocked a rerun'
assert_original 'dirty snapshot rerun'
[ "${COMMIT_COUNT}" = 2 ] || fail 'dirty snapshot rerun did not commit its restoration'
[ "${SERVICE_COUNT}" = 2 ] || fail 'dirty snapshot rerun did not restart dnsmasq after restoration'
[ -f "${NVRAM_TRANSACTION_DIR}/keys" ] || fail 'dirty snapshot rerun did not create a replacement snapshot'

nvram_transaction_lock_release || fail 'transaction owner could not release its lock for stale-lock recovery'
for fallback_mode in symlink mkdir; do
	(
		# nvram_transaction_lock_flock_supports_fd reports whether file-descriptor-based flock locking is supported.
		nvram_transaction_lock_flock_supports_fd() { return 1; }
		if [ "${fallback_mode}" = mkdir ]; then
			# nvram_transaction_lock_symlink_acquire indicates that symlink-based lock acquisition is unavailable.
			nvram_transaction_lock_symlink_acquire() { return 2; }
		fi
		nvram_transaction_lock_acquire || fail "could not acquire ${fallback_mode} lock before installer restart"
		[ "${NVRAM_TRANSACTION_LOCK_MODE:-}" = "${fallback_mode}" ] || fail "installer restart test did not select ${fallback_mode} mode"
		TARG_DIR="${TEST_ROOT}/restart-${fallback_mode}"
		SCRIPT_LOC="${TEST_ROOT}/missing-installer"
		BRANCH=testing
		CLI_MODE=0
		ADGUARD_DEFER_END_OP=0
		ROLLBACK_RESULT_UPDATED=1
		mkdir -p "${TARG_DIR}" || fail "could not create ${fallback_mode} restart target"
		cat >"${TARG_DIR}/installer" <<EOF_RESTART
#!/bin/sh
[ ! -L "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink" ] || exit 1
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram.lock.d" ] || exit 1
printf '%s\n' "\$1" >"${TEST_ROOT}/restart-${fallback_mode}.branch"
EOF_RESTART
		chmod 755 "${TARG_DIR}/installer" || fail "could not make ${fallback_mode} restart target executable"
		# sleep advances the simulated clock by one second.
		sleep() { :; }
		# clear_screen performs no action.
		clear_screen() { :; }
		# rollback_result_needs_attention reports whether rollback requires attention.
		rollback_result_needs_attention() { return 1; }
		end_op_message 0 ''
	) || fail "installer restart retained its ${fallback_mode} NVRAM transaction lock"
	[ "$(cat "${TEST_ROOT}/restart-${fallback_mode}.branch" 2>/dev/null)" = testing ] || fail "installer restart did not execute after releasing its ${fallback_mode} lock"
done
for reaper_mode in symlink mkdir flock; do
	if [ "${reaper_mode}" = flock ] && ! nvram_transaction_lock_flock_supports_fd; then
		continue
	fi
	(
		case "${reaper_mode}" in
			flock) ;;
			symlink) nvram_transaction_lock_flock_supports_fd() { return 1; } ;;
			mkdir)
				nvram_transaction_lock_flock_supports_fd() { return 1; }
				nvram_transaction_lock_readlink() { return 127; }
				;;
		esac
		nvram_transaction_lock_reaper_acquire "${BASE_DIR}/restart-${reaper_mode}.reaper" || fail "could not acquire ${reaper_mode} reaper before installer restart"
		[ "${NVRAM_TRANSACTION_REAPER_LOCK_MODE:-}" = "${reaper_mode}" ] || fail "installer restart test did not select ${reaper_mode} reaper mode"
		TARG_DIR="${TEST_ROOT}/restart-reaper-${reaper_mode}"
		SCRIPT_LOC="${TEST_ROOT}/missing-installer"
		BRANCH=testing
		CLI_MODE=0
		ADGUARD_DEFER_END_OP=0
		ROLLBACK_RESULT_UPDATED=1
		mkdir -p "${TARG_DIR}" || fail "could not create ${reaper_mode} reaper restart target"
		cat >"${TARG_DIR}/installer" <<EOF_REAPER_RESTART
#!/bin/sh
[ ! -L "${BASE_DIR}/restart-${reaper_mode}.reaper.symlink" ] || exit 1
[ ! -e "${BASE_DIR}/restart-${reaper_mode}.reaper" ] || exit 1
[ ! -e "/proc/\$\$/fd/9" ] || exit 1
printf '%s\n' "\$1" >"${TEST_ROOT}/restart-reaper-${reaper_mode}.branch"
EOF_REAPER_RESTART
		chmod 755 "${TARG_DIR}/installer" || fail "could not make ${reaper_mode} reaper restart target executable"
		sleep() { :; }
		clear_screen() { :; }
		rollback_result_needs_attention() { return 1; }
		end_op_message 2 ''
	) || fail "signal restart retained its ${reaper_mode} NVRAM transaction reaper"
	[ "$(cat "${TEST_ROOT}/restart-reaper-${reaper_mode}.branch" 2>/dev/null)" = testing ] || fail "signal restart did not execute after releasing its ${reaper_mode} reaper"
done
(
	# nvram_transaction_lock_flock_supports_fd reports whether file-descriptor-based flock locking is supported.
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	ln -s 999999 "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink" || fail 'could not prepare stale symlink transaction lock'
	nvram_transaction_lock_acquire || fail 'stale symlink transaction lock blocked recovery'
	[ "${NVRAM_TRANSACTION_LOCK_MODE:-}" = symlink ] || fail 'stale symlink lock did not select symlink mode'
	[ "$(readlink "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink")" = "${LOCK_OWNER}" ] || fail 'stale symlink lock was not replaced by the live owner'
	BASE_DIR="${BASE_DIR}" FUNCTIONS_FILE="${FUNCTIONS_FILE}" sh -c '
		. "${FUNCTIONS_FILE}"
		nvram_transaction_lock_flock_supports_fd() { return 1; }
		nvram_transaction_lock_symlink_acquire
	'
	status="$?"
	[ "${status}" -eq 1 ] || fail "symlink fallback returned ${status} instead of 1 for overlapping NVRAM transaction owner"
	nvram_transaction_lock_release || fail 'symlink transaction owner could not release its lock'
	ln -s "$$:0" "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink" || fail 'could not prepare PID-reused symlink transaction lock'
	nvram_transaction_lock_acquire || fail 'PID-reused symlink transaction lock blocked recovery'
	[ "$(readlink "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink")" = "${LOCK_OWNER}" ] || fail 'PID-reused symlink lock was not replaced'
	nvram_transaction_lock_release || fail 'PID-reused symlink transaction owner could not release its lock'
) || exit 1
(
	# A failed reaper release must abort stale mkdir recovery and roll back a
	# newly published lock that is still owned by this process.
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	nvram_transaction_lock_symlink_acquire() { return 2; }
	nvram_transaction_lock_reaper_acquire() { return 0; }
	nvram_transaction_lock_reaper_release() { return 1; }
	mkdir "${BASE_DIR}/.AdGuardHome.nvram.lock.d" || fail 'could not prepare stale mkdir lock for reaper-release failure'
	printf '%s\n' 999999999 >"${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid" || fail 'could not record stale mkdir owner for reaper-release failure'
	nvram_transaction_lock_acquire
	status="$?"
	[ "${status}" -eq 1 ] || fail "mkdir recovery returned ${status} instead of 1 after reaper-release failure"
	[ ! -e "${BASE_DIR}/.AdGuardHome.nvram.lock.d" ] || fail 'failed reaper release retained the newly published mkdir lock'
) || exit 1
(
	# A failed rollback after reaper-release failure is terminal: returning to
	# the same process would leave its live owner recorded and self-deadlock.
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	nvram_transaction_lock_symlink_acquire() { return 2; }
	nvram_transaction_lock_reaper_acquire() { return 0; }
	nvram_transaction_lock_reaper_release() { return 1; }
	mkdir "${BASE_DIR}/.AdGuardHome.nvram.lock.d" || fail 'could not prepare stale mkdir lock for rollback failure'
	printf '%s\n' 999999999 >"${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid" || fail 'could not record stale mkdir owner for rollback failure'
	FAIL_LOCK_REMOVE_AT=2
	nvram_transaction_lock_acquire
	: >"${TEST_ROOT}/continued-after-lock-rollback-failure"
) 2>"${TEST_ROOT}/lock-rollback-failure.stderr"
status="$?"
[ "${status}" -eq 1 ] || fail "failed mkdir lock rollback exited with status ${status} instead of 1"
[ ! -e "${TEST_ROOT}/continued-after-lock-rollback-failure" ] || fail 'installer continued after failing to roll back its owned mkdir lock'
[ -e "${BASE_DIR}/.AdGuardHome.nvram.lock.d" ] || fail 'failed rollback unexpectedly removed the owned mkdir lock'
grep -Fq 'unable to roll back owned NVRAM transaction lock' "${TEST_ROOT}/lock-rollback-failure.stderr" || fail 'terminal mkdir lock rollback failure was not reported'
FAIL_LOCK_REMOVE_AT=0
rm -rf "${BASE_DIR}/.AdGuardHome.nvram.lock.d"
(
	# If ownership changes before a failed reaper release, preserve the other
	# owner's lock rather than deleting unverified state.
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	nvram_transaction_lock_symlink_acquire() { return 2; }
	nvram_transaction_lock_reaper_acquire() { return 0; }
	nvram_transaction_lock_reaper_release() {
		printf '%s\n' 1 >"${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid"
		return 1
	}
	mkdir "${BASE_DIR}/.AdGuardHome.nvram.lock.d" || fail 'could not prepare stale mkdir lock for ownership-change cleanup'
	printf '%s\n' 999999999 >"${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid" || fail 'could not record stale mkdir owner for ownership-change cleanup'
	if nvram_transaction_lock_acquire; then
		fail 'mkdir recovery continued after reaper release failed with changed ownership'
	fi
	[ "$(cat "${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid" 2>/dev/null)" = 1 ] || fail 'failed reaper release removed the replacement mkdir owner'
	rm -rf "${BASE_DIR}/.AdGuardHome.nvram.lock.d"
) || exit 1
(
	# nvram_transaction_lock_flock_supports_fd reports whether file-descriptor-based flock locking is supported.
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	# Simulate another installer holding the reaper during fresh symlink publication.
	nvram_transaction_lock_reaper_acquire() {
		ln -s 1 "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink"
		return 1
	}
	nvram_transaction_lock_symlink_acquire
	status="$?"
	[ "${status}" -eq 1 ] || fail "fresh symlink acquisition returned ${status} instead of 1 for active stale-lock reaper"
	[ "$(readlink "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink")" = 1 ] || fail 'fresh symlink acquisition replaced the reaper owner'
	rm -f "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink"
) || exit 1
(
	# Reach the post-publication cleanup path by failing only the reaper release.
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	nvram_transaction_lock_reaper_acquire() { return 0; }
	nvram_transaction_lock_reaper_release() { return 1; }
	nvram_transaction_lock_symlink_acquire
	status="$?"
	[ "${status}" -eq 1 ] || fail "symlink publication returned ${status} instead of 1 when reaper release failed"
	if [ -e "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink" ] ||
		[ -L "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink" ]; then
		fail 'failed reaper release retained the newly published symlink lock'
	fi
) || exit 1
(
	# A failed rollback of the published symlink lock is terminal so the
	# installer cannot resume while its unpublished live-owner lock remains.
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	nvram_transaction_lock_reaper_acquire() { return 0; }
	nvram_transaction_lock_reaper_release() { return 1; }
	FAIL_SYMLINK_LOCK_REMOVE_AT=1
	SYMLINK_LOCK_REMOVE_COUNT=0
	nvram_transaction_lock_symlink_acquire
	: >"${TEST_ROOT}/continued-after-symlink-lock-rollback-failure"
) 2>"${TEST_ROOT}/symlink-lock-rollback-failure.stderr"
status="$?"
[ "${status}" -eq 1 ] || fail "failed symlink lock rollback exited with status ${status} instead of 1"
[ ! -e "${TEST_ROOT}/continued-after-symlink-lock-rollback-failure" ] || fail 'installer continued after failing to roll back its owned symlink lock'
[ -L "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink" ] || fail 'failed rollback unexpectedly removed the owned symlink lock'
grep -Fq 'unable to roll back owned NVRAM transaction lock' "${TEST_ROOT}/symlink-lock-rollback-failure.stderr" || fail 'terminal symlink lock rollback failure was not reported'
command rm -f "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink"
(
	# nvram_transaction_lock_flock_supports_fd reports whether file-descriptor-based flock locking is supported.
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	ln -s 999999 "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink" || fail 'could not prepare raced stale symlink transaction lock'
	# nvram_transaction_lock_reaper_acquire acquires the NVRAM transaction lock for reaping.
	nvram_transaction_lock_reaper_acquire() {
		rm -f "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink" || return 1
		ln -s "${LOCK_OWNER}" "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink"
	}
	# nvram_transaction_lock_reaper_release releases the NVRAM transaction lock reaper.
	nvram_transaction_lock_reaper_release() { :; }
	nvram_transaction_lock_symlink_acquire
	status="$?"
	[ "${status}" -eq 1 ] || fail "stale-owner race returned ${status} instead of 1"
	[ "$(readlink "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink")" = "${LOCK_OWNER}" ] || fail 'symlink stale-lock reaper removed a new live owner'
	rm -f "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink"
) || exit 1
(
	# nvram_transaction_lock_flock_supports_fd reports whether file-descriptor-based flock locking is supported.
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	# nvram_transaction_lock_readlink indicates that symbolic-link lock inspection is unavailable.
	nvram_transaction_lock_readlink() { return 127; }
	nvram_transaction_lock_acquire || fail 'missing readlink did not select the mkdir transaction lock fallback'
	[ "${NVRAM_TRANSACTION_LOCK_MODE:-}" = mkdir ] || fail 'missing readlink selected an unusable symlink transaction lock'
	nvram_transaction_lock_release || fail 'mkdir fallback could not be released after missing readlink'
	ln -s 999999 "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink" || fail 'could not prepare an uninspectable symlink transaction lock'
	if nvram_transaction_lock_symlink_acquire 2>"${TEST_ROOT}/readlink-unavailable.stderr"; then
		fail 'uninspectable symlink transaction lock was accepted'
	fi
	grep -q 'readlink is unavailable' "${TEST_ROOT}/readlink-unavailable.stderr" || fail 'missing readlink did not report the uninspectable symlink lock'
	rm -f "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink"
) || exit 1
(
	# nvram_transaction_lock_flock_supports_fd reports whether file-descriptor-based flock locking is supported.
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	# nvram_transaction_lock_symlink_acquire indicates that symlink-based lock acquisition is unavailable.
	nvram_transaction_lock_symlink_acquire() { return 2; }
	mkdir "${BASE_DIR}/.AdGuardHome.nvram.lock.d" || fail 'could not prepare stale transaction lock'
	printf '%s\n' 999999999 >"${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid" || fail 'could not record stale transaction lock owner'
	nvram_transaction_lock_acquire || fail 'stale NVRAM transaction lock blocked recovery'
	[ "$(cat "${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid")" = "${LOCK_OWNER}" ] || fail 'stale transaction lock was not replaced by the live owner'
	if BASE_DIR="${BASE_DIR}" FUNCTIONS_FILE="${FUNCTIONS_FILE}" sh -c '
		. "${FUNCTIONS_FILE}"
		nvram_transaction_lock_flock_supports_fd() { return 1; }
		nvram_transaction_lock_symlink_acquire() { return 2; }
		nvram_transaction_lock_acquire
	'; then
		fail 'mkdir fallback allowed an overlapping NVRAM transaction owner'
	fi
	nvram_transaction_lock_release || fail 'mkdir transaction owner could not release its lock'
	mkdir "${BASE_DIR}/.AdGuardHome.nvram.lock.d" || fail 'could not prepare missing-pid transaction lock'
	nvram_transaction_lock_acquire || fail 'missing-pid transaction lock blocked recovery'
	[ "$(cat "${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid")" = "${LOCK_OWNER}" ] || fail 'missing-pid transaction lock was not replaced by the live owner'
	nvram_transaction_lock_release || fail 'missing-pid transaction owner could not release its lock'
	mkdir "${BASE_DIR}/.AdGuardHome.nvram.lock.d" || fail 'could not prepare malformed-pid transaction lock'
	printf '%s\n' invalid >"${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid" || fail 'could not record malformed transaction lock owner'
	nvram_transaction_lock_acquire || fail 'malformed-pid transaction lock blocked recovery'
	[ "$(cat "${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid")" = "${LOCK_OWNER}" ] || fail 'malformed-pid transaction lock was not replaced by the live owner'
	nvram_transaction_lock_release || fail 'malformed-pid transaction owner could not release its lock'
	mkdir "${BASE_DIR}/.AdGuardHome.nvram.lock.d" || fail 'could not prepare PID-reused transaction lock'
	printf '%s:0\n' "$$" >"${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid" || fail 'could not record PID-reused transaction lock owner'
	nvram_transaction_lock_acquire || fail 'PID-reused transaction lock blocked recovery'
	[ "$(cat "${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid")" = "${LOCK_OWNER}" ] || fail 'PID-reused transaction lock was not replaced'
	nvram_transaction_lock_release || fail 'PID-reused transaction owner could not release its lock'
) || exit 1
(
	# nvram_transaction_lock_flock_supports_fd reports whether file-descriptor-based flock locking is supported.
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	# nvram_transaction_lock_symlink_acquire indicates that symlink-based lock acquisition is unavailable.
	nvram_transaction_lock_symlink_acquire() { return 2; }
	mkdir "${BASE_DIR}/.AdGuardHome.nvram.lock.d" || fail 'could not prepare raced stale mkdir transaction lock'
	printf '%s\n' 999999999 >"${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid" || fail 'could not record raced stale mkdir transaction lock owner'
	# nvram_transaction_lock_reaper_acquire recreates the NVRAM transaction lock reaper directory and records owner ID 1 in its pid marker.
	nvram_transaction_lock_reaper_acquire() {
		rm -rf "${BASE_DIR}/.AdGuardHome.nvram.lock.d" || return 1
		mkdir "${BASE_DIR}/.AdGuardHome.nvram.lock.d" || return 1
		printf '%s\n' 1 >"${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid"
	}
	# nvram_transaction_lock_reaper_release releases the NVRAM transaction lock reaper.
	nvram_transaction_lock_reaper_release() { :; }
	if nvram_transaction_lock_acquire; then
		fail 'mkdir stale-lock reaper replaced a new live owner'
	fi
	[ "$(cat "${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid")" = 1 ] || fail 'mkdir stale-lock reaper removed a new live owner'
	rm -rf "${BASE_DIR}/.AdGuardHome.nvram.lock.d"
) || exit 1
(
	# nvram_transaction_lock_flock_supports_fd reports whether file-descriptor-based flock locking is supported.
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	# nvram_transaction_lock_symlink_acquire indicates that symlink-based lock acquisition is unavailable.
	nvram_transaction_lock_symlink_acquire() { return 2; }
	mkdir "${BASE_DIR}/.AdGuardHome.nvram.lock.d" || fail 'could not prepare stale transaction lock for owner-lookup counting'
	printf '%s\n' 999999999 >"${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid" || fail 'could not record stale transaction lock owner for owner-lookup counting'
	OWNER_CALLS_FILE="${TEST_ROOT}/owner-lookup-calls"
	: >"${OWNER_CALLS_FILE}"
	# nvram_transaction_lock_owner_current counts self-owner lookups while preserving the real liveness check for other PIDs.
	# nvram_transaction_lock_owner_current returns the current lock owner or a PID and process-start-time identifier for the specified process.
	# nvram_transaction_lock_owner_current returns the current lock owner or a PID and process start-time identifier for a numeric PID.
	# nvram_transaction_lock_owner_current reports the current lock owner or resolves a numeric process ID to its PID and start time.
	nvram_transaction_lock_owner_current() {
		if [ "$#" -eq 0 ]; then
			printf '%s\n' x >>"${OWNER_CALLS_FILE}"
			printf '%s\n' "${LOCK_OWNER}"
			return 0
		fi
		case "$1" in
			"" | *[!0-9]*) return 1 ;;
		esac
		owner_start="$(/bin/sed 's/^.*) //' "/proc/$1/stat" 2>/dev/null | /usr/bin/awk '{print $20}')"
		case "${owner_start}" in
			"" | *[!0-9]*) return 1 ;;
		esac
		printf '%s:%s\n' "$1" "${owner_start}"
	}
	nvram_transaction_lock_acquire || fail 'stale mkdir transaction lock reclaim failed while counting owner lookups'
	[ "${NVRAM_TRANSACTION_LOCK_MODE:-}" = mkdir ] || fail 'stale mkdir transaction lock reclaim did not select mkdir mode while counting owner lookups'
	[ "$(cat "${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid")" = "${LOCK_OWNER}" ] || fail 'stale mkdir transaction lock reclaim did not record the live owner while counting owner lookups'
	[ "$(wc -l <"${OWNER_CALLS_FILE}")" -eq 1 ] || fail "stale mkdir transaction lock reclaim looked up its own owner $(wc -l <"${OWNER_CALLS_FILE}") time(s) instead of once"
	nvram_transaction_lock_release || fail 'could not release the counted stale mkdir transaction lock'
) || exit 1
rm -rf "${BASE_DIR}/.AdGuardHome.nvram.lock.d"

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
check_dns_environment 0 || fail 'DNS preparation for interrupted snapshot cleanup failed'
DNS_SNAPSHOT="${BASE_DIR}/.AdGuardHome.nvram/dns-preparation"
NVRAM_TRANSACTION_DIR="${DNS_SNAPSHOT}"
FAIL_SNAPSHOT_REMOVE=1
finalize_dns_environment || fail 'completed DNS snapshot cleanup failure was treated as a failed commit'
[ -d "${DNS_SNAPSHOT}" ] || fail 'snapshot cleanup failure injection did not retain the DNS snapshot'
[ ! -f "${DNS_SNAPSHOT}/dirty" ] || fail 'DNS snapshot remained rollback-eligible after finalization committed'
FAIL_SNAPSHOT_REMOVE=0
nvram_transaction_begin dns-preparation dnspriv_enable dhcpd_dns_router dhcp_dns1_x dhcp_dns2_x || fail 'completed DNS snapshot blocked a later installer run'
[ "${COMMIT_COUNT}" -eq 1 ] || fail 'completed DNS snapshot was restored after cleanup interruption'
rm -rf "${NVRAM_TRANSACTION_DIR}"

reset_case
cat >"${NVRAM_FILE}" <<'EOF_NVRAM'
dnspriv_enable=0
dhcpd_dns_router=1
dhcp_dns1_x=
dhcp_dns2_x=
EOF_NVRAM
STUBBY_RUNNING=1
check_dns_environment 0 || fail 'stopping stubby with prepared DNS NVRAM was rejected'
[ "${STUBBY_KILL_COUNT}" = 1 ] || fail 'running stubby was not stopped exactly once'
[ "${COMMIT_COUNT}" = 0 ] || fail 'stopping stubby caused an unnecessary NVRAM commit'
[ "${SERVICE_COUNT}" = 1 ] || fail 'dnsmasq was not restarted after stopping stubby without NVRAM changes'
[ "$(dns_check_count)" = 1 ] || fail 'local DNS was not checked after stopping stubby without NVRAM changes'
rm -rf "${NVRAM_TRANSACTION_DIR}"

reset_case
STUBBY_RUNNING=1
STUBBY_KILL_STUCK=1
check_dns_environment 0 && fail 'DNS preparation continued while stubby remained running'
[ "${STUBBY_KILL_COUNT}" = 1 ] || fail 'running stubby termination was not attempted exactly once'
[ "${COMMIT_COUNT}" = 0 ] || fail 'NVRAM was changed while stubby remained running'

reset_case
cat >"${NVRAM_FILE}" <<'EOF_NVRAM'
dnspriv_enable=0
dhcpd_dns_router=1
dhcp_dns1_x=
dhcp_dns2_x=
EOF_NVRAM
STUBBY_RUNNING=1
FAIL_SERVICE_AT=1
check_dns_environment 0 && fail 'initial dnsmasq restart failure after stopping stubby was accepted'
[ "${SERVICE_COUNT}" = 3 ] || fail 'dnsmasq restart failure was not retried before stubby recovery'
[ "$(dns_check_count)" = 1 ] || fail 'recovered dnsmasq restart after stopping stubby was not checked'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram/dns-preparation" ] || fail 'successful dnsmasq recovery retained its snapshot'

reset_case
cat >"${NVRAM_FILE}" <<'EOF_NVRAM'
dnspriv_enable=0
dhcpd_dns_router=1
dhcp_dns1_x=
dhcp_dns2_x=
EOF_NVRAM
STUBBY_RUNNING=1
FAIL_ALL_SERVICES=1
check_dns_environment 0 && fail 'unrecoverable dnsmasq restart failure after stopping stubby was accepted'
[ "${SERVICE_COUNT}" = 3 ] || fail 'unrecoverable dnsmasq restart failure and stubby recovery were not attempted before returning'
[ -f "${BASE_DIR}/.AdGuardHome.nvram/dns-preparation/dirty" ] || fail 'unrecoverable dnsmasq restart failure did not preserve recovery state'
grep -q 'snapshot preserved' "${CALLS_FILE}" || fail 'unrecoverable dnsmasq restart failure did not record rollback evidence'
[ "${STUBBY_RESTART_COUNT}" = 1 ] || fail 'unrecoverable DNS preparation did not restore stubby'

reset_case
STUBBY_RUNNING=1
FAIL_SET_AT=1
check_dns_environment 0 && fail 'DNS staging failure after stopping stubby was accepted'
[ "${STUBBY_RESTART_COUNT}" = 1 ] || fail 'DNS staging failure did not restore stubby'

reset_case
STUBBY_RUNNING=1
FAIL_SET_AT=1
FAIL_SERVICE_AT=2
check_dns_environment 0 && fail 'stubby restore failure after DNS staging failure was accepted'
[ "${SERVICE_COUNT}" = 2 ] || fail 'stubby restore failure did not participate in service failure injection'
[ "${STUBBY_RESTART_COUNT}" = 1 ] || fail 'stubby restore failure was not attempted exactly once'
grep -q '^service restart_stubby$' "${CALLS_FILE}" || fail 'stubby restore failure was not recorded'
grep -q 'Unable to restart stubby after DNS preparation failed.' "${CALLS_FILE}" || fail 'stubby restore failure was not reported'
[ "${_DNS_STUBBY_STOPPED}" = 1 ] || fail 'stubby restore failure did not preserve stopped state for later recovery'

reset_case
STUBBY_RUNNING=1
FAIL_SET_AT=1
check_dns_environment 0 && fail 'successful stubby restore after DNS staging failure was unexpectedly accepted'
[ "${STUBBY_RESTART_COUNT}" = 1 ] || fail 'successful stubby restore was not attempted exactly once'
[ "${STUBBY_RUNNING}" = 1 ] || fail 'successful stubby restore did not set stubby to running state'
grep -q '^service restart_stubby$' "${CALLS_FILE}" || fail 'successful stubby restore was not recorded'

reset_case
[ "${_DNS_STUBBY_STOPPED}" = 0 ] || fail 'reset leaked stopped stubby state from the previous case'
STUBBY_RUNNING=1
FAIL_COMMIT_AT=1
check_dns_environment 0 && fail 'DNS apply failure after stopping stubby was accepted'
[ "${STUBBY_RESTART_COUNT}" = 1 ] || fail 'DNS apply failure did not restore stubby'

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
