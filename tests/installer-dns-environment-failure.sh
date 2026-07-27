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
# pidof reports the simulated PID when the requested process is stubby and it is configured as running.
pidof() {
	[ "${STUBBY_RUNNING:-0}" = 1 ] && [ "$1" = stubby ] || return 1
	printf '%s\n' 1234
}
# kill_processes increments the simulated stubby process termination count when called for stubby.
kill_processes() {
	[ "$1" = stubby ] || return 1
	STUBBY_KILL_COUNT="$((STUBBY_KILL_COUNT + 1))"
}
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
# check_connection checks simulated public network availability and increments the public connectivity check count.
check_connection() {
	PUBLIC_CHECK_COUNT="$((PUBLIC_CHECK_COUNT + 1))"
	[ "${PUBLIC_NETWORK_AVAILABLE:-0}" = 1 ]
}
# rollback_result_write records a rollback status message in the calls log.
rollback_result_write() { printf '%s\n' "rollback $*" >>"${CALLS_FILE}"; }

# nvram_value reads and prints the value associated with a key from the simulated NVRAM file.
nvram_value() {
	awk -v key="$1" 'index($0, key "=") == 1 { print substr($0, length(key) + 2); found=1 } END { exit(found ? 0 : 1) }' "${NVRAM_FILE}"
}

# nvram simulates NVRAM show, get, set, unset, and commit operations with configurable failures.
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

# service simulates restarting dnsmasq and records whether the configured service operation succeeds.
service() {
	case "$*" in
		restart_dnsmasq | 'restart_firewall;restart_dnsmasq') ;;
		*) return 1 ;;
	esac
	SERVICE_COUNT="$((SERVICE_COUNT + 1))"
	printf '%s\n' 'service restart_dnsmasq' >>"${CALLS_FILE}"
	[ "${FAIL_ALL_SERVICES:-0}" = 0 ] && [ "${FAIL_SERVICE_AT:-0}" != "${SERVICE_COUNT}" ]
}

# rm removes files and directories, failing when configured to simulate removal of the active NVRAM transaction directory.
rm() {
	if [ "${FAIL_SNAPSHOT_REMOVE:-0}" = 1 ] && [ "$#" -eq 2 ] && [ "${1:-}" = -rf ] && [ "${2:-}" = "${NVRAM_TRANSACTION_DIR:-}" ]; then
		return 1
	fi
	command rm "$@"
}

# nslookup simulates a DNS lookup, optionally blocking and tracking termination before reporting readiness.
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

# reset_case restores the simulated test environment to its baseline state.
reset_case() {
	nvram_transaction_lock_release || fail 'could not release the previous test transaction lock'
	rm -rf "${BASE_DIR}/.AdGuardHome.nvram/dns-preparation" "${BASE_DIR}/.AdGuardHome.nvram/dnsfilter" "${BASE_DIR}/.AdGuardHome.nvram/lan-domain"
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
	SET_COUNT=0 COMMIT_COUNT=0 SERVICE_COUNT=0 DNS_CHECK_COUNT=0 PUBLIC_CHECK_COUNT=0 STUBBY_KILL_COUNT=0
	FAIL_SHOW=0 FAIL_GET_KEY='' FAIL_ALL_SETS=0 FAIL_SET_AT=0 FAIL_COMMIT_AT=0 FAIL_SERVICE_AT=0 FAIL_ALL_SERVICES=0 FAIL_SNAPSHOT_REMOVE=0 DNS_READY=1 PUBLIC_NETWORK_AVAILABLE=0
	BLOCKING_QUERY=0 TRACK_LOOKUP=0 MONOTONIC_NOW=0 MONOTONIC_FAIL_AT=0 STUBBY_RUNNING=0
	DNS_ENV_READY_TIMEOUT=2 DNS_ENV_RECOVERY_TIMEOUT=1
	rm -f "${TEST_ROOT}/monotonic-calls" "${TEST_ROOT}/lookup-reaped"
	_DNS_NVRAM_SAVED=0 _DNS_NVRAM_ROLLBACK_ATTEMPTED=0
}

reset_case
for reaper_path in "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink.reaper" "${BASE_DIR}/.AdGuardHome.nvram.lock.reaper"; do
	mkdir -p "${reaper_path}"
	printf '%s\n' 999999999 >"${reaper_path}/pid"
	nvram_transaction_lock_reaper_acquire "${reaper_path}" || fail "stale reaper lock was not reclaimed: ${reaper_path}"
	[ "$(cat "${reaper_path}/pid")" = "$$" ] || fail "reclaimed reaper lock has the wrong owner: ${reaper_path}"
	nvram_transaction_lock_reaper_release "${reaper_path}" || fail "reclaimed reaper lock was not released: ${reaper_path}"

	mkdir -p "${reaper_path}"
	printf '%s\n' "$$" >"${reaper_path}/pid"
	if nvram_transaction_lock_reaper_acquire "${reaper_path}"; then
		fail "live reaper lock was reclaimed: ${reaper_path}"
	fi
	rm -rf "${reaper_path}"
done

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
installer_lan_domain_set router.test 1 || fail 'LAN domain cleanup transaction apply failed'
FAIL_SNAPSHOT_REMOVE=1
installer_lan_domain_restore && fail 'LAN domain snapshot removal failure was ignored'
[ -d "${NVRAM_TRANSACTION_DIR}" ] || fail 'LAN domain snapshot was not retained after removal failure'
FAIL_SNAPSHOT_REMOVE=0
rm -rf "${NVRAM_TRANSACTION_DIR}" || fail 'could not remove LAN domain cleanup transaction snapshot'

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
	cleanup_api_files() { :; }
	# installer_cleanup_tmp_file performs temporary-file cleanup.
	installer_cleanup_tmp_file() { :; }
	# installer_lan_domain_restore restores the original LAN domain settings from the active transaction snapshot.
	installer_lan_domain_restore() { :; }
	# restore_dns_filter_settings restores DNSFilter settings and returns a failure status.
	restore_dns_filter_settings() { return 1; }
	# check_dns_environment prepares the local DNS environment and optionally restores the transactional NVRAM state.
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
		# nvram_transaction_lock_flock_supports_fd determines whether file-descriptor-based flock locking is supported.
		nvram_transaction_lock_flock_supports_fd() { return 1; }
		if [ "${fallback_mode}" = mkdir ]; then
			# nvram_transaction_lock_symlink_acquire reports that symlink-based lock acquisition is unavailable.
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
		# sleep does nothing.
		sleep() { :; }
		# clear_screen does nothing.
		clear_screen() { :; }
		# rollback_result_needs_attention indicates that rollback attention is not needed.
		rollback_result_needs_attention() { return 1; }
		end_op_message 0 ''
	) || fail "installer restart retained its ${fallback_mode} NVRAM transaction lock"
	[ "$(cat "${TEST_ROOT}/restart-${fallback_mode}.branch" 2>/dev/null)" = testing ] || fail "installer restart did not execute after releasing its ${fallback_mode} lock"
done
(
	# nvram_transaction_lock_flock_supports_fd determines whether file-descriptor-based flock locking is supported.
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	ln -s 999999 "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink" || fail 'could not prepare stale symlink transaction lock'
	nvram_transaction_lock_acquire || fail 'stale symlink transaction lock blocked recovery'
	[ "${NVRAM_TRANSACTION_LOCK_MODE:-}" = symlink ] || fail 'stale symlink lock did not select symlink mode'
	[ "$(readlink "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink")" = "$$" ] || fail 'stale symlink lock was not replaced by the live owner'
	if BASE_DIR="${BASE_DIR}" FUNCTIONS_FILE="${FUNCTIONS_FILE}" sh -c '
		. "${FUNCTIONS_FILE}"
		nvram_transaction_lock_flock_supports_fd() { return 1; }
		nvram_transaction_lock_symlink_acquire
	'; then
		fail 'symlink fallback allowed an overlapping NVRAM transaction owner'
	else
		[ "$?" -ne 2 ] || fail 'live symlink lock was reported as unsupported'
	fi
	nvram_transaction_lock_release || fail 'symlink transaction owner could not release its lock'
) || exit 1
(
	# nvram_transaction_lock_flock_supports_fd determines whether file-descriptor-based flock locking is supported.
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	ln -s 999999 "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink" || fail 'could not prepare raced stale symlink transaction lock'
	# nvram_transaction_lock_reaper_acquire removes any existing transaction lock symlink and creates a new one for reaper ownership.
	nvram_transaction_lock_reaper_acquire() {
		rm -f "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink" || return 1
		ln -s 1 "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink"
	}
	# nvram_transaction_lock_reaper_release releases the NVRAM transaction lock reaper.
	nvram_transaction_lock_reaper_release() { :; }
	if nvram_transaction_lock_symlink_acquire; then
		fail 'symlink stale-lock reaper replaced a new live owner'
	fi
	[ "$(readlink "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink")" = 1 ] || fail 'symlink stale-lock reaper removed a new live owner'
	rm -f "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink"
) || exit 1
(
	# nvram_transaction_lock_flock_supports_fd determines whether file-descriptor-based flock locking is supported.
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
	# nvram_transaction_lock_flock_supports_fd determines whether file-descriptor-based flock locking is supported.
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	# nvram_transaction_lock_symlink_acquire reports that symlink-based lock acquisition is unavailable.
	nvram_transaction_lock_symlink_acquire() { return 2; }
	mkdir "${BASE_DIR}/.AdGuardHome.nvram.lock.d" || fail 'could not prepare stale transaction lock'
	printf '%s\n' 999999999 >"${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid" || fail 'could not record stale transaction lock owner'
	nvram_transaction_lock_acquire || fail 'stale NVRAM transaction lock blocked recovery'
	[ "$(cat "${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid")" = "$$" ] || fail 'stale transaction lock was not replaced by the live owner'
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
	[ "$(cat "${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid")" = "$$" ] || fail 'missing-pid transaction lock was not replaced by the live owner'
	nvram_transaction_lock_release || fail 'missing-pid transaction owner could not release its lock'
	mkdir "${BASE_DIR}/.AdGuardHome.nvram.lock.d" || fail 'could not prepare malformed-pid transaction lock'
	printf '%s\n' invalid >"${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid" || fail 'could not record malformed transaction lock owner'
	nvram_transaction_lock_acquire || fail 'malformed-pid transaction lock blocked recovery'
	[ "$(cat "${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid")" = "$$" ] || fail 'malformed-pid transaction lock was not replaced by the live owner'
	nvram_transaction_lock_release || fail 'malformed-pid transaction owner could not release its lock'
) || exit 1
(
	# nvram_transaction_lock_flock_supports_fd determines whether file-descriptor-based flock locking is supported.
	nvram_transaction_lock_flock_supports_fd() { return 1; }
	# nvram_transaction_lock_symlink_acquire reports that symlink-based lock acquisition is unavailable.
	nvram_transaction_lock_symlink_acquire() { return 2; }
	mkdir "${BASE_DIR}/.AdGuardHome.nvram.lock.d" || fail 'could not prepare raced stale mkdir transaction lock'
	printf '%s\n' 999999999 >"${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid" || fail 'could not record raced stale mkdir transaction lock owner'
	# nvram_transaction_lock_reaper_acquire creates the NVRAM transaction lock reaper directory and writes its ownership marker.
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
cat >"${NVRAM_FILE}" <<'EOF_NVRAM'
dnspriv_enable=0
dhcpd_dns_router=1
dhcp_dns1_x=
dhcp_dns2_x=
EOF_NVRAM
STUBBY_RUNNING=1
FAIL_SERVICE_AT=1
check_dns_environment 0 && fail 'initial dnsmasq restart failure after stopping stubby was accepted'
[ "${SERVICE_COUNT}" = 2 ] || fail 'dnsmasq restart failure after stopping stubby was not retried'
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
[ "${SERVICE_COUNT}" = 2 ] || fail 'unrecoverable dnsmasq restart failure was not retried before returning'
[ -f "${BASE_DIR}/.AdGuardHome.nvram/dns-preparation/dirty" ] || fail 'unrecoverable dnsmasq restart failure did not preserve recovery state'
grep -q 'snapshot preserved' "${CALLS_FILE}" || fail 'unrecoverable dnsmasq restart failure did not record rollback evidence'

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
