#!/bin/sh
# Verify the dnsmasq-to-AdGuardHome handoff is bounded and ordered.

set -u

S99_PATH="${1:-S99AdGuardHome}"
RC_PATH="${2:-rc.func.AdGuardHome}"
MANAGER_PATH="${3:-AdGuardHome.sh}"
TEST_ROOT="${TMPDIR:-/tmp}/adguardhome-dns-handoff.$$"
S99_FUNCTIONS="${TEST_ROOT}/s99-functions"
RC_FUNCTION="${TEST_ROOT}/rc-start-function"
CALLS_FILE="${TEST_ROOT}/calls"
STARTED_FILE="${TEST_ROOT}/started"
DNSMASQ_CONF_FILE="${TEST_ROOT}/dnsmasq.conf"

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
	'/^agh_timestamp() {$/,/^}$/p; /^agh_log() {$/,/^}$/p; /^agh_conf_value() {$/,/^}$/p; /^agh_install_mode() {$/,/^}$/p; /^agh_lan_mode() {$/,/^}$/p; /^agh_dnsmasq_running() {$/,/^}$/p; /^agh_dnsmasq_managed() {$/,/^}$/p; /^agh_dns_handoff_required() {$/,/^}$/p; /^adguardhome_yaml_ipset_file() {$/,/^}$/p; /^chmod_regular_files_600() {$/,/^}$/p; /^ensure_adguardhome_work_dir_permissions() {$/,/^}$/p; /^dns_guard_wait_for_stop() {$/,/^}$/p; /^dns_handoff_dependencies_available() {$/,/^}$/p; /^dns_handoff_path_has_owner_mode() {$/,/^}$/p; /^dns_handoff_directory_is_private() {$/,/^}$/p; /^dns_handoff_marker_is_private() {$/,/^}$/p; /^dns_handoff_process_is_root() {$/,/^}$/p; /^dns_handoff_process_start_time() {$/,/^}$/p; /^dns_handoff_set_current_identity() {$/,/^}$/p; /^dns_handoff_marker_is_active() {$/,/^}$/p; /^remove_inactive_dns_handoff_marker() {$/,/^}$/p; /^dns_handoff_lock_file_is_active() {$/,/^}$/p; /^dns_handoff_lock_is_active() {$/,/^}$/p; /^watchdog_pids() {$/,/^}$/p; /^pid_nice() {$/,/^}$/p; /^save_watchdog_nice() {$/,/^}$/p; /^restore_watchdog_nice() {$/,/^}$/p; /^reap_the_watch_dog() {$/,/^}$/p; /^resume_dns_watchdog() {$/,/^}$/p; /^restore_dns_watchdog_traps() {$/,/^}$/p; /^save_dns_watchdog_traps() {$/,/^}$/p; /^suspend_dns_watchdog() {$/,/^}$/p; /^reclaim_stale_dns_handoff_lock() {$/,/^}$/p; /^release_dns_handoff_lock() {$/,/^}$/p; /^disable_dns_handoff() {$/,/^}$/p; /^prepare_dns_handoff_marker() {$/,/^}$/p; /^enable_dns_handoff() {$/,/^}$/p; /^adguardhome_config_valid() {$/,/^}$/p; /^adguardhome_web_port() {$/,/^}$/p; /^adguardhome_web_port_owned_status() {$/,/^}$/p; /^adguardhome_web_port_available() {$/,/^}$/p; /^adguardhome_startup_checks_ready() {$/,/^}$/p; /^wait_for_adguardhome_startup_checks_failure_reason() {$/,/^}$/p; /^wait_for_adguardhome_startup_checks() {$/,/^}$/p; /^log_adguardhome_start_failure() {$/,/^}$/p; /^dns_retry_limit() {$/,/^}$/p; /^adguardhome_single_process_running() {$/,/^}$/p; /^adguardhome_owns_dns() {$/,/^}$/p; /^dns_port_owner_command() {$/,/^}$/p; /^dns_port_owner_process_name() {$/,/^}$/p; /^adguardhome_dns_bind_scope() {$/,/^}$/p; /^dns_port_unknown_refusal_enabled() {$/,/^}$/p; /^kill_dns_port_owners() {$/,/^}$/p; /^dns_port_available() {$/,/^}$/p; /^release_dns_port_from_dnsmasq() {$/,/^}$/p; /^dns_port_has_foreign_owner() {$/,/^}$/p; /^dns_port_needs_release() {$/,/^}$/p; /^stop_dns_port_guard() {$/,/^}$/p; /^log_adguardhome_dns_wait_failure() {$/,/^}$/p; /^wait_for_adguardhome_dns() {$/,/^}$/p; /^start_dns_port_guard() {$/,/^}$/p; /^post_start_adguardhome() {$/,/^}$/p; /^post_start_failure_adguardhome() {$/,/^}$/p; /^pre_start_adguardhome() {$/,/^}$/p' \
	"${S99_PATH}" >"${S99_FUNCTIONS}" || fail "could not read ${S99_PATH}"
sed -n '/^dns_handoff_is_active() {$/,/^}$/p' "${MANAGER_PATH}" >>"${S99_FUNCTIONS}" ||
	fail "could not read ${MANAGER_PATH}"
sed -n '/^stop_launched_process() {$/,/^}$/p; /^adguardhome_start_handoff_is_prepared() {$/,/^}$/p; /^adguardhome_start_handoff_required() {$/,/^}$/p; /^adguardhome_run_postfailcmd() {$/,/^}$/p; /^start() {$/,/^}$/p' "${RC_PATH}" >"${RC_FUNCTION}" ||
	fail "could not read ${RC_PATH}"
[ -s "${S99_FUNCTIONS}" ] || fail 'DNS handoff functions were not found'
[ -s "${RC_FUNCTION}" ] || fail 'service start function was not found'
grep -q 'DNS_HANDOFF_DIR="/tmp/AdGuardHome.dns-handoff"' "${S99_PATH}" ||
	fail 'service script does not use the private dnsmasq handoff directory'
grep -q 'dns_handoff_is_active || return 0' "${MANAGER_PATH}" ||
	fail 'dnsmasq postconf cannot run before AdGuardHome starts'
if grep -q '${20' "${S99_PATH}"; then
	fail 'service script uses a multi-digit positional parameter unsupported by older BusyBox ash'
fi

grep -q 'restore_dns_watchdog_traps "${_dns_watchdog_saved_traps}"' "${S99_PATH}" ||
	fail 'pre-start watchdog trap cleanup does not restore caller traps'
grep -q 'restore_dns_watchdog_traps "${_dns_guard_saved_traps}"' "${S99_PATH}" ||
	fail 'DNS guard watchdog trap cleanup does not restore caller traps'

WATCHD_NICE_SNAPSHOT=""

# shellcheck disable=SC1090
. "${S99_FUNCTIONS}"
# shellcheck disable=SC1090
. "${RC_FUNCTION}"

PROCS='AdGuardHome'
WORK_DIR="${TEST_ROOT}/AdGuardHome"
mkdir -p "${WORK_DIR}" || fail 'could not create AdGuardHome work directory'
printf '%s\n' 'ADGUARD_WEBUI_PORT="3000"' >"${WORK_DIR}/.config" || fail 'could not create AdGuardHome config'
printf '%s\n' 'bind_host: 0.0.0.0' 'bind_port: 3000' >"${WORK_DIR}/AdGuardHome.yaml" || fail 'could not create AdGuardHome yaml'
printf '%s\n' '#!/bin/sh' 'exit 0' >"${WORK_DIR}/AdGuardHome" || fail 'could not create AdGuardHome binary'
chmod 755 "${WORK_DIR}/AdGuardHome" || fail 'could not chmod AdGuardHome binary'
DNS_HANDOFF_DIR="${TEST_ROOT}/dns-handoff"
DNS_HANDOFF_FILE="${DNS_HANDOFF_DIR}/active"
DNS_HANDOFF_LOCK="${DNS_HANDOFF_DIR}/lock"
umask 077
dns_handoff_set_current_identity ||
	fail 'could not identify the current shell from /proc/self/stat'
CURRENT_PID="${DNS_HANDOFF_CURRENT_PID}"
CURRENT_START_TIME="${DNS_HANDOFF_CURRENT_START_TIME}"
[ "${CURRENT_START_TIME}" = "$(dns_handoff_process_start_time "${CURRENT_PID}")" ] ||
	fail 'current shell identity did not match its proc start time'

# mark_dns_handoff_active marks the DNS handoff as active in the environment.
mark_dns_handoff_active() {
	ADGUARDHOME_DNS_HANDOFF_ACTIVE=1
	export ADGUARDHOME_DNS_HANDOFF_ACTIVE
}

# clear_dns_handoff_active clears the active DNS handoff state.
clear_dns_handoff_active() {
	unset ADGUARDHOME_DNS_HANDOFF_ACTIVE
}

# prepare_active_dns_handoff_test_marker prepares and activates a DNS handoff marker for the current process.
prepare_active_dns_handoff_test_marker() {
	dns_handoff_set_current_identity || return 1
	printf '%s %s\n' "${DNS_HANDOFF_CURRENT_PID}" "${DNS_HANDOFF_CURRENT_START_TIME}" >"${DNS_HANDOFF_FILE}" || return 1
	mark_dns_handoff_active
}
(
	dns_handoff_set_current_identity || exit 1
	[ "${DNS_HANDOFF_CURRENT_START_TIME}" = "$(dns_handoff_process_start_time "${DNS_HANDOFF_CURRENT_PID}")" ]
) &
IDENTITY_TEST_PID="$!"
wait "${IDENTITY_TEST_PID}" ||
	fail 'background shell identity did not match its proc start time'
# logger records its arguments in the test command log.
logger() {
	printf '%s\n' "logger $*" >>"${CALLS_FILE}"
}
# nvram returns stubbed NVRAM values for supported keys.
nvram() {
	[ "${1:-}" = get ] && [ "${2:-}" = http_username ] && printf '%s\n' root
	[ "${1:-}" = get ] && [ "${2:-}" = lan_ipaddr ] && printf '%s\n' 192.168.50.1
}
# rm removes files using the system command, optionally simulating handoff marker removal failure.
rm() {
	if [ "${RM_HANDOFF_FAIL:-0}" -eq 1 ] && [ "${1:-}" = '-f' ] && [ "${2:-}" = "${DNS_HANDOFF_FILE}" ]; then
		return 1
	fi
	command rm "$@"
}
# which reports success for commands stubbed by the test harness and failure for all other commands.
which() {
	case "$1" in
		awk | chmod | kill | ln | logger | ls | mkdir | netstat | nvram | pidof | rm | service | sleep)
			return 0
			;;
	esac
	return 1
}
# pidof reports simulated process IDs for dnsmasq and AdGuardHome based on test state.
pidof() {
	case "$1" in
		dnsmasq)
			[ "${DNSMASQ_RUNNING:-1}" = "1" ] && printf '%s\n' 123
			;;
		AdGuardHome)
			case "${DNS_STATE:-free}" in
				missing)
					return 1
					;;
				*)
					printf '%s\n' 321
					;;
			esac
			;;
		*)
			return 1
			;;
	esac
}
# netstat simulates netstat output for configured DNS and WebUI ownership states, or fails when NETSTAT_FAIL is enabled.
netstat() {
	[ "${NETSTAT_FAIL:-0}" -eq 0 ] || return 1
	case "${DNS_STATE:-free}" in
		busy)
			printf '%s\n' 'tcp 0 0 0.0.0.0:53 0.0.0.0:* LISTEN 123/dnsmasq'
			;;
		busy_alt)
			printf '%s\n' 'udp 0 0 0.0.0.0:53 0.0.0.0:* 0 0 234/custom-dns'
			;;
		busy_alt_lan)
			printf '%s\n' 'udp 0 0 192.168.50.1:53 0.0.0.0:* 0 0 234/custom-dns'
			;;
		busy_loopback)
			printf '%s\n' 'udp 0 0 127.0.0.1:53 0.0.0.0:* 0 0 234/custom-dns'
			;;
		busy_other_lan)
			printf '%s\n' 'udp 0 0 192.168.51.1:53 0.0.0.0:* 0 0 234/custom-dns'
			;;
		busy_wildcard)
			printf '%s\n' 'udp 0 0 0.0.0.0:53 0.0.0.0:* 0 0 234/custom-dns'
			;;
		busy_no_pid)
			printf '%s\n' 'udp 0 0 0.0.0.0:53 0.0.0.0:*'
			;;
		busy_alt_dnsmasq)
			printf '%s\n' 'udp 0 0 0.0.0.0:53 0.0.0.0:* 0 0 234/dnsmasq'
			;;
		owned_lan_alt)
			printf '%s\n' \
				'tcp 0 0 192.168.50.1:53 0.0.0.0:* LISTEN 321/AdGuardHome' \
				'udp 0 0 192.168.50.1:53 0.0.0.0:* 321/AdGuardHome' \
				'tcp 0 0 192.168.51.1:53 0.0.0.0:* LISTEN 123/dnsmasq' \
				'udp 0 0 192.168.51.1:53 0.0.0.0:* 123/dnsmasq' \
				'tcp 0 0 0.0.0.0:3000 0.0.0.0:* LISTEN 321/AdGuardHome'
			;;
		owned)
			printf '%s\n' \
				'tcp 0 0 0.0.0.0:53 0.0.0.0:* LISTEN 321/AdGuardHome' \
				'udp 0 0 0.0.0.0:53 0.0.0.0:* 321/AdGuardHome'
			case "${WEB_STATE:-bound}" in
				bound)
					printf '%s\n' 'tcp 0 0 0.0.0.0:3000 0.0.0.0:* LISTEN 321/AdGuardHome'
					;;
				foreign)
					printf '%s\n' 'tcp 0 0 0.0.0.0:3000 0.0.0.0:* LISTEN 123/httpd'
					;;
				bound80)
					printf '%s\n' 'tcp 0 0 0.0.0.0:80 0.0.0.0:* LISTEN 321/AdGuardHome'
					;;
			esac
			;;
	esac
}
service() {
	printf '%s\n' "service $*" >>"${CALLS_FILE}"
	[ "$*" = 'restart_dnsmasq' ] && [ "${SERVICE_RESTART_FAIL:-0}" -eq 1 ] && return 1
	[ "$*" = 'restart_dnsmasq' ] && [ "${DNSMASQ_RESTART_RELEASES_PORT:-0}" -eq 1 ] && DNS_STATE=free
	return 0
}
kill() {
	printf '%s\n' "kill $*" >>"${CALLS_FILE}"
	if [ "${1:-}" = '-s' ]; then
		if [ "${KILL_FAILS_AFTER_RELEASE:-0}" -eq 1 ]; then
			DNS_STATE=free
			return 1
		fi
		[ "${KILL_RELEASES_PORT:-0}" -eq 1 ] && DNS_STATE=free
		return 0
	fi
	command kill "$@"
}
sleep() {
	SLEEP_CALLS="$((SLEEP_CALLS + 1))"
	if [ "${SLEEP_OWNED_AFTER:-0}" -gt 0 ] && [ "${SLEEP_CALLS}" -ge "${SLEEP_OWNED_AFTER}" ]; then
		DNS_STATE=owned
	fi
	if [ "${SLEEP_BUSY_AFTER:-0}" -gt 0 ] && [ "${SLEEP_CALLS}" -ge "${SLEEP_BUSY_AFTER}" ]; then
		DNS_STATE=busy
	fi
	[ "${SLEEP_SETS_OWNED:-0}" -eq 1 ] && DNS_STATE=owned
	if [ "${SLEEP_WEB_BOUND_AFTER:-0}" -gt 0 ] && [ "${SLEEP_CALLS}" -ge "${SLEEP_WEB_BOUND_AFTER}" ]; then
		WEB_STATE=bound
	fi
	:
}

[ "$(dns_retry_limit invalid 7)" = 7 ] || fail 'invalid DNS retry limit was not replaced with the default'
[ "$(dns_retry_limit 0 7)" = 0 ] || fail 'zero DNS retry limit was not preserved'
NETSTAT_FAIL=1
if dns_port_available; then
	fail 'failed netstat command was treated as an available DNS port'
fi
if kill_dns_port_owners; then
	fail 'failed netstat command was hidden while collecting DNS owners'
fi
if dns_port_has_foreign_owner; then
	fail 'failed netstat command was treated as a foreign DNS owner'
fi
NETSTAT_FAIL=0
SLEEP_CALLS=0
SLEEP_OWNED_AFTER=0
SLEEP_BUSY_AFTER=0

ADGUARDHOME_DNS_BIND_SCOPE=192.168.50.1
DNS_STATE=busy_wildcard
if dns_port_available "${ADGUARDHOME_DNS_BIND_SCOPE}"; then
	fail 'scoped DNS availability ignored a wildcard port 53 owner'
fi
if ! dns_port_has_foreign_owner "${ADGUARDHOME_DNS_BIND_SCOPE}"; then
	fail 'scoped DNS foreign-owner check ignored a wildcard port 53 owner'
fi
DNS_STATE=owned_lan_alt
post_start_adguardhome || fail 'scoped post-start rejected AdGuardHome DNS ownership with off-scope listener'
unset ADGUARDHOME_DNS_BIND_SCOPE
DNS_STATE=free

: >"${CALLS_FILE}"
_dns_saved_test_traps_file="${TEST_ROOT}/caller-traps"
trap >"${_dns_saved_test_traps_file}" || fail 'could not save test traps'
trap 'printf "%s\n" caller-exit >"${TEST_ROOT}/watchdog-caller-exit"' EXIT
trap 'printf "%s\n" caller-term >"${TEST_ROOT}/watchdog-caller-term"' TERM
mkdir -p "${DNS_HANDOFF_DIR}" || fail 'could not create handoff directory for trap test'
DNS_WATCHDOG_TRAP_FILE=""
save_dns_watchdog_traps test || fail 'watchdog helper did not save caller traps'
_dns_saved_watchdog_traps="${DNS_WATCHDOG_TRAP_FILE}"
trap - EXIT TERM
restore_dns_watchdog_traps "${_dns_saved_watchdog_traps}"
trap >"${TEST_ROOT}/watchdog-restored-traps" || fail 'could not inspect restored watchdog traps'
grep -q 'watchdog-caller-exit' "${TEST_ROOT}/watchdog-restored-traps" ||
	fail 'watchdog helper did not restore the caller EXIT trap'
grep -q 'watchdog-caller-term' "${TEST_ROOT}/watchdog-restored-traps" ||
	fail 'watchdog helper did not restore the caller TERM trap'
trap - EXIT HUP INT TERM
eval "$(cat "${_dns_saved_test_traps_file}")"
rm -f "${_dns_saved_test_traps_file}" "${TEST_ROOT}/watchdog-caller-exit" "${TEST_ROOT}/watchdog-caller-term" "${TEST_ROOT}/watchdog-restored-traps"

: >"${CALLS_FILE}"
DNS_STATE=busy
DNSMASQ_RESTART_RELEASES_PORT=1
enable_dns_handoff || fail 'could not enable the dnsmasq postconf handoff'
[ -f "${DNS_HANDOFF_FILE}" ] || fail 'dnsmasq handoff marker was not created'
[ "$(ls -ldn "${DNS_HANDOFF_DIR}" | awk 'NR == 1 { print $3 ":" substr($1, 2, 9) }')" = '0:rwx------' ] ||
	fail 'dnsmasq handoff directory is not root-owned and private'
[ "$(ls -ldn "${DNS_HANDOFF_FILE}" | awk 'NR == 1 { print $3 ":" substr($1, 2, 9) }')" = '0:rw-------' ] ||
	fail 'dnsmasq handoff marker is not root-owned and private'
[ "${DNS_STATE}" = free ] || fail 'dnsmasq was not regenerated onto its alternate port'
grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'dnsmasq was not restarted to apply postconf'
disable_dns_handoff
[ ! -e "${DNS_HANDOFF_FILE}" ] || fail 'dnsmasq handoff marker was not removed'
DNSMASQ_RESTART_RELEASES_PORT=0

chmod 777 "${DNS_HANDOFF_DIR}" || fail 'could not make handoff directory insecure for validation test'
printf '%s %s\n' "${CURRENT_PID}" "${CURRENT_START_TIME}" >"${DNS_HANDOFF_FILE}" ||
	fail 'could not create marker in insecure handoff directory'
if dns_handoff_is_active; then
	fail 'dnsmasq postconf accepted a marker from an insecure handoff directory'
fi
chmod 700 "${DNS_HANDOFF_DIR}" || fail 'could not restore private handoff directory permissions'
chmod 666 "${DNS_HANDOFF_FILE}" || fail 'could not make handoff marker insecure for validation test'
if dns_handoff_is_active; then
	fail 'dnsmasq postconf accepted an insecure handoff marker'
fi
chmod 600 "${DNS_HANDOFF_FILE}" || fail 'could not restore private handoff marker permissions'
disable_dns_handoff || fail 'could not clean up permissions validation marker'

: >"${CALLS_FILE}"
printf '%s\n' "${CURRENT_PID}" >"${DNS_HANDOFF_FILE}" || fail 'could not create handoff marker for removal failure test'
RM_HANDOFF_FAIL=1
if disable_dns_handoff; then
	fail 'handoff cleanup hid a marker removal failure'
fi
grep -q 'Unable to disable the dnsmasq port 553 handoff' "${CALLS_FILE}" ||
	fail 'handoff marker removal failure was not logged'
RM_HANDOFF_FAIL=0
disable_dns_handoff || fail 'could not clean up marker after removal failure test'

: >"${CALLS_FILE}"
DNS_STATE=owned
printf '%s\n' "${CURRENT_PID}" >"${DNS_HANDOFF_FILE}" || fail 'could not create handoff marker for post-start cleanup test'
mark_dns_handoff_active
RM_HANDOFF_FAIL=1
ADGUARDHOME_SKIP_DNSMASQ_RESTART=1
if post_start_adguardhome; then
	fail 'post-start succeeded while the dnsmasq handoff marker remained active'
fi
RM_HANDOFF_FAIL=0
unset ADGUARDHOME_SKIP_DNSMASQ_RESTART
clear_dns_handoff_active
disable_dns_handoff || fail 'could not clean up marker after post-start cleanup test'

: >"${CALLS_FILE}"
printf '%s\n' "${CURRENT_PID}" >"${DNS_HANDOFF_FILE}" || fail 'could not create handoff marker for failed-start recovery test'
mark_dns_handoff_active
RM_HANDOFF_FAIL=1
if post_start_failure_adguardhome; then
	fail 'failed-start recovery hid a handoff marker cleanup failure'
fi
grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" ||
	fail 'failed-start recovery did not restore dnsmasq after marker cleanup failed'
RM_HANDOFF_FAIL=0
disable_dns_handoff || fail 'could not clean up marker after failed-start recovery test'

: >"${CALLS_FILE}"
printf '%s %s\n' 999999 1 >"${DNS_HANDOFF_FILE}" || fail 'could not create stale handoff marker'
if dns_handoff_is_active; then
	fail 'dnsmasq postconf accepted a handoff marker owned by a dead process'
fi
HANDOFF_START_TIME="${CURRENT_START_TIME}"
printf '%s %s\n' "${CURRENT_PID}" "${HANDOFF_START_TIME}" >"${DNS_HANDOFF_FILE}" ||
	fail 'could not create competing active handoff marker'
: >"${CALLS_FILE}"
if enable_dns_handoff; then
	fail 'handoff setup replaced a marker owned by a live startup'
fi
[ "$(cat "${DNS_HANDOFF_FILE}")" = "${CURRENT_PID} ${HANDOFF_START_TIME}" ] ||
	fail 'competing startup changed the active handoff marker'
! grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" ||
	fail 'competing startup regenerated dnsmasq after losing marker ownership'
disable_dns_handoff || fail 'could not remove competing active handoff marker'

printf '%s %s\n' 999999 1 >"${DNS_HANDOFF_FILE}" ||
	fail 'could not create stale handoff marker for lock-contention test'
printf '%s %s\n' "${CURRENT_PID}" "${HANDOFF_START_TIME}" >"${DNS_HANDOFF_LOCK}" ||
	fail 'could not record simulated marker-update lock owner'
if enable_dns_handoff; then
	fail 'handoff setup ignored a concurrent marker update'
fi
[ "$(cat "${DNS_HANDOFF_FILE}")" = '999999 1' ] ||
	fail 'handoff setup removed a stale marker without acquiring the marker lock'
release_dns_handoff_lock || fail 'could not release simulated marker-update lock'
rm -f "${DNS_HANDOFF_FILE}" || fail 'could not remove stale marker after lock-contention test'

: >"${DNS_HANDOFF_LOCK}" || fail 'could not create abandoned marker-update lock'
DNS_STATE=busy
DNSMASQ_RESTART_RELEASES_PORT=1
enable_dns_handoff || fail 'could not recover an abandoned marker-update lock'
[ ! -e "${DNS_HANDOFF_LOCK}" ] || fail 'abandoned marker-update lock was not removed'
disable_dns_handoff || fail 'could not clean up handoff after abandoned-lock recovery'
DNSMASQ_RESTART_RELEASES_PORT=0

printf '%s %s\n' "${CURRENT_PID}" "${HANDOFF_START_TIME}" >"${DNS_HANDOFF_FILE}" ||
	fail 'could not create active handoff marker'
dns_handoff_is_active || fail 'dnsmasq postconf rejected a live handoff owner'
printf '%s %s\n' "${CURRENT_PID}" "$((HANDOFF_START_TIME + 1))" >"${DNS_HANDOFF_FILE}" ||
	fail 'could not create reused-PID handoff marker'
if dns_handoff_is_active; then
	fail 'dnsmasq postconf accepted a live PID with a different process lifetime'
fi
printf '%s %s\n' "${CURRENT_PID}" "${HANDOFF_START_TIME}" >"${DNS_HANDOFF_FILE}" ||
	fail 'could not restore active handoff marker'
disable_dns_handoff || fail 'could not remove active handoff marker'

: >"${CALLS_FILE}"
printf '%s\n' 4242 >"${DNS_HANDOFF_FILE}" || fail 'could not create foreign handoff marker'
if disable_dns_handoff; then
	fail 'handoff cleanup removed a marker owned by another process'
fi
[ -f "${DNS_HANDOFF_FILE}" ] || fail 'foreign handoff marker was removed'
printf '%s\n' "${CURRENT_PID}" >"${DNS_HANDOFF_FILE}" || fail 'could not reclaim foreign handoff marker'
disable_dns_handoff || fail 'could not remove reclaimed handoff marker'

: >"${CALLS_FILE}"
ln -s "${CALLS_FILE}" "${DNS_HANDOFF_FILE}" || fail 'could not create symbolic-link handoff marker'
if enable_dns_handoff; then
	fail 'handoff setup followed a symbolic-link marker'
fi
[ -L "${DNS_HANDOFF_FILE}" ] || fail 'symbolic-link handoff marker was replaced'
rm -f "${DNS_HANDOFF_FILE}" || fail 'could not remove symbolic-link handoff marker'

: >"${CALLS_FILE}"
DNS_STATE=busy
SERVICE_RESTART_FAIL=1
if enable_dns_handoff; then
	fail 'handoff setup hid a failed dnsmasq restart'
fi
[ ! -e "${DNS_HANDOFF_FILE}" ] || fail 'failed handoff setup left its marker active'
[ "$(grep -c '^service restart_dnsmasq$' "${CALLS_FILE}")" -eq 2 ] ||
	fail 'failed handoff setup did not attempt to restore dnsmasq'
SERVICE_RESTART_FAIL=0

: >"${CALLS_FILE}"
DNS_STATE=busy_alt_dnsmasq
kill_dns_port_owners || fail 'DNS owner parser rejected an alternate BusyBox netstat layout'
grep -q '^kill -s 9 234$' "${CALLS_FILE}" || fail 'DNS owner parser depended on a fixed netstat PID column'

: >"${CALLS_FILE}"
DNS_STATE=busy
KILL_FAILS_AFTER_RELEASE=1
kill_dns_port_owners || fail 'DNS owner cleanup rejected a stale dnsmasq PID after port 53 became free'
grep -q '^kill -s 9 123$' "${CALLS_FILE}" || fail 'DNS owner cleanup did not try to signal the stale dnsmasq PID'
unset KILL_FAILS_AFTER_RELEASE

: >"${CALLS_FILE}"
DNS_STATE=busy_alt
printf '%s\n' 'ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="0"' >"${WORK_DIR}/.config" || fail 'could not write legacy DNS port policy config'
kill_dns_port_owners || fail 'DNS owner cleanup rejected saved legacy cleanup of an unknown port 53 owner'
grep -q '^kill -s 9 234$' "${CALLS_FILE}" || fail 'DNS owner cleanup did not preserve saved legacy unknown-owner cleanup'

: >"${CALLS_FILE}"
DNS_STATE=busy_no_pid
if kill_dns_port_owners; then
	fail 'DNS owner cleanup accepted a port 53 owner without a PID'
fi
! grep -q '^kill ' "${CALLS_FILE}" || fail 'DNS owner cleanup tried to signal an unavailable port 53 owner PID'

: >"${CALLS_FILE}"
DNS_STATE=busy_alt
ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL=1
if kill_dns_port_owners; then
	fail 'DNS owner cleanup accepted an unknown port 53 owner when refusal was requested'
fi
! grep -q '^kill -s 9 234$' "${CALLS_FILE}" || fail 'DNS owner cleanup killed an unknown port 53 owner when refusal was requested'
unset ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL
printf '%s\n' 'ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="1"' >"${WORK_DIR}/.config" || fail 'could not write DNS port policy config'
if kill_dns_port_owners; then
	fail 'DNS owner cleanup ignored configured unknown-owner refusal policy'
fi
! grep -q '^kill -s 9 234$' "${CALLS_FILE}" || fail 'DNS owner cleanup killed an unknown port 53 owner with configured refusal policy'
ADGUARDHOME_FORCE_DNS_PORT_KILL=1
kill_dns_port_owners || fail 'DNS owner cleanup rejected forced cleanup of an unknown port 53 owner'
grep -q '^kill -s 9 234$' "${CALLS_FILE}" || fail 'DNS owner cleanup did not kill an unknown port 53 owner with force'
unset ADGUARDHOME_FORCE_DNS_PORT_KILL
printf '%s\n' 'ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="0"' >"${WORK_DIR}/.config" || fail 'could not reset DNS port policy config'

: >"${CALLS_FILE}"
DNS_STATE=free
kill_dns_port_owners || fail 'DNS owner cleanup failed when no process owned port 53'
! grep -q '^kill ' "${CALLS_FILE}" || fail 'DNS owner cleanup signaled a process for an empty port'

: >"${CALLS_FILE}"
printf '%s\n' 'ADGUARD_WEBUI_PORT="3000"' 'ADGUARD_INSTALL_MODE="lan"' >"${WORK_DIR}/.config" || fail 'could not set LAN install mode'
DNSMASQ_RUNNING=0
DNS_STATE=free
unset ADGUARDHOME_DNS_HANDOFF_ACTIVE ADGUARDHOME_DNS_HANDOFF_REQUIRED ADGUARDHOME_SKIP_DNSMASQ_RESTART
ADGUARDHOME_DNSMASQ_STOP_RETRIES=3
ADGUARDHOME_DNS_GUARD_RETRIES=0
pre_start_adguardhome || fail 'LAN pre-start without dnsmasq rejected an available DNS port'
! grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'LAN pre-start without dnsmasq prepared DNS handoff'
! grep -q '^service stop_dnsmasq$' "${CALLS_FILE}" || fail 'LAN pre-start without dnsmasq stopped dnsmasq'
grep -q 'DNS handoff skipped because LAN mode dnsmasq is not running' "${CALLS_FILE}" ||
	fail 'LAN pre-start without dnsmasq did not log handoff skip'
[ -f "${DNS_HANDOFF_FILE}" ] || fail 'LAN pre-start without dnsmasq did not arm a temporary handoff marker'
[ "${ADGUARDHOME_DNS_HANDOFF_ACTIVE:-0}" = "1" ] || fail 'LAN pre-start without dnsmasq did not mark the temporary handoff active'
[ "${ADGUARDHOME_DNS_HANDOFF_REQUIRED:-1}" = "0" ] || fail 'LAN pre-start without dnsmasq marked handoff required'
[ "${ADGUARDHOME_SKIP_DNSMASQ_RESTART:-0}" = "1" ] || fail 'LAN pre-start without dnsmasq did not suppress dnsmasq restart cleanup'
DNS_STATE=owned
WEB_STATE=bound
post_start_adguardhome || fail 'LAN post-start without dnsmasq did not clean up the temporary handoff'
[ ! -f "${DNS_HANDOFF_FILE}" ] || fail 'LAN post-start without dnsmasq left the temporary handoff marker behind'
[ -z "${ADGUARDHOME_DNS_HANDOFF_ACTIVE:-}" ] || fail 'LAN post-start without dnsmasq did not clear the active handoff flag'
! grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'LAN post-start without dnsmasq restarted absent dnsmasq'
unset ADGUARDHOME_SKIP_DNSMASQ_RESTART

: >"${CALLS_FILE}"
printf '%s\n' '#!/bin/sh' 'exit 1' >"${WORK_DIR}/AdGuardHome" || fail 'could not create failing AdGuardHome binary'
chmod 755 "${WORK_DIR}/AdGuardHome" || fail 'could not chmod failing AdGuardHome binary'
DNSMASQ_RUNNING=0
DNS_STATE=free
if pre_start_adguardhome; then
	fail 'LAN pre-start without dnsmasq accepted an invalid AdGuardHome config'
fi
! grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'LAN invalid-config pre-start restarted absent dnsmasq'
grep -q 'AdGuardHome configuration validation failed; restoring dnsmasq' "${CALLS_FILE}" ||
	fail 'LAN invalid-config pre-start did not log validation failure'
printf '%s\n' '#!/bin/sh' 'exit 0' >"${WORK_DIR}/AdGuardHome" || fail 'could not restore AdGuardHome binary'
chmod 755 "${WORK_DIR}/AdGuardHome" || fail 'could not chmod restored AdGuardHome binary'

: >"${CALLS_FILE}"
printf '%s %s\n' 999999 1 >"${DNS_HANDOFF_FILE}" || fail 'could not create stale no-handoff marker'
DNSMASQ_RUNNING=0
DNS_STATE=free
pre_start_adguardhome || fail 'LAN pre-start without dnsmasq rejected an available DNS port with a stale marker'
[ -f "${DNS_HANDOFF_FILE}" ] || fail 'LAN no-handoff pre-start did not replace stale marker with temporary handoff'
[ "${ADGUARDHOME_DNS_HANDOFF_ACTIVE:-0}" = "1" ] || fail 'LAN stale-marker pre-start did not mark the temporary handoff active'
post_start_failure_adguardhome || fail 'LAN failed-start without dnsmasq did not clean up the temporary handoff'
[ ! -f "${DNS_HANDOFF_FILE}" ] || fail 'LAN failed-start without dnsmasq left the temporary handoff marker behind'
[ -z "${ADGUARDHOME_DNS_HANDOFF_ACTIVE:-}" ] || fail 'LAN failed-start without dnsmasq did not clear the active handoff flag'
unset ADGUARDHOME_SKIP_DNSMASQ_RESTART
! grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'LAN stale-marker pre-start prepared DNS handoff'
! grep -q '^service stop_dnsmasq$' "${CALLS_FILE}" || fail 'LAN stale-marker pre-start stopped dnsmasq'

: >"${CALLS_FILE}"
printf '%s %s\n' "${CURRENT_PID}" "${CURRENT_START_TIME}" >"${DNS_HANDOFF_FILE}" ||
	fail 'could not create active no-handoff marker'
DNSMASQ_RUNNING=0
DNS_STATE=free
if pre_start_adguardhome; then
	fail 'LAN pre-start without dnsmasq accepted an active handoff marker'
fi
[ -f "${DNS_HANDOFF_FILE}" ] || fail 'LAN no-handoff pre-start removed an active handoff marker'
! grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'LAN active-marker pre-start prepared DNS handoff'
! grep -q '^service stop_dnsmasq$' "${CALLS_FILE}" || fail 'LAN active-marker pre-start stopped dnsmasq'
grep -q 'DNS handoff is already active; startup aborted without DNS handoff' "${CALLS_FILE}" ||
	fail 'LAN active-marker pre-start did not log handoff-in-progress failure'
disable_dns_handoff || fail 'could not clean up active no-handoff marker'

: >"${CALLS_FILE}"
DNSMASQ_RUNNING=0
DNS_STATE=busy
if pre_start_adguardhome; then
	fail 'LAN pre-start without dnsmasq accepted an unavailable DNS port'
fi
! grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'LAN busy-port pre-start without dnsmasq prepared DNS handoff'
! grep -q '^service stop_dnsmasq$' "${CALLS_FILE}" || fail 'LAN busy-port pre-start without dnsmasq stopped dnsmasq'
grep -q 'Port 53 is not available for AdGuardHome; startup aborted without DNS handoff' "${CALLS_FILE}" ||
	fail 'LAN busy-port pre-start without dnsmasq did not log DNS availability failure'

: >"${CALLS_FILE}"
printf '%s\n' 'dns:' '  bind_hosts:' '    - 192.168.50.1' '  port: 53' >"${WORK_DIR}/AdGuardHome.yaml" ||
	fail 'could not set LAN DNS bind host'
DNSMASQ_RUNNING=0
DNS_STATE=busy_alt
if pre_start_adguardhome; then
	fail 'LAN scoped pre-start accepted wildcard DNS owner'
fi
grep -q 'Port 53 is not available for AdGuardHome; startup aborted without DNS handoff' "${CALLS_FILE}" ||
	fail 'LAN scoped pre-start did not treat wildcard DNS owner as a conflict'
unset ADGUARDHOME_SKIP_DNSMASQ_RESTART

: >"${CALLS_FILE}"
DNSMASQ_RUNNING=0
DNS_STATE=busy_alt_lan
if pre_start_adguardhome; then
	fail 'LAN scoped pre-start accepted selected LAN IP owner'
fi
! grep -q '^service stop_dnsmasq$' "${CALLS_FILE}" || fail 'LAN scoped pre-start stopped absent dnsmasq'
! grep -q '^kill -s 9 234$' "${CALLS_FILE}" || fail 'LAN scoped pre-start killed conflicting owner without force'
grep -q 'mode=lan dnsmasq=absent handoff=skipped' "${CALLS_FILE}" ||
	fail 'LAN scoped pre-start did not log mode/dnsmasq/handoff context'

: >"${CALLS_FILE}"
printf '%s\n' 'dns:' '  bind_hosts:' '    - 192.168.50.1' '    - 127.0.0.1' '  port: 53' >"${WORK_DIR}/AdGuardHome.yaml" ||
	fail 'could not set multi-host LAN DNS bind hosts'
[ "$(adguardhome_dns_bind_scope)" = '192.168.50.1 127.0.0.1' ] || fail 'multi-host DNS bind scope did not include LAN and loopback hosts'
DNSMASQ_RUNNING=0
DNS_STATE=busy_loopback
if pre_start_adguardhome; then
	fail 'LAN multi-host pre-start accepted configured loopback bind host owner'
fi
grep -q 'Port 53 is not available for AdGuardHome; startup aborted without DNS handoff' "${CALLS_FILE}" ||
	fail 'LAN multi-host pre-start did not check loopback scope'
unset ADGUARDHOME_SKIP_DNSMASQ_RESTART

DNS_STATE=busy_other_lan
if ! dns_port_available "$(adguardhome_dns_bind_scope)"; then
	fail 'LAN multi-host scope rejected off-scope DNS owner'
fi

: >"${CALLS_FILE}"
printf '%s\n' 'dns:' '  bind_hosts:' '    - 0.0.0.0' '  port: 53' >"${WORK_DIR}/AdGuardHome.yaml" ||
	fail 'could not set wildcard DNS bind host'
DNSMASQ_RUNNING=0
DNS_STATE=busy_alt
if pre_start_adguardhome; then
	fail 'LAN wildcard pre-start accepted global port owner'
fi
grep -q 'Port 53 is not available for AdGuardHome; startup aborted without DNS handoff' "${CALLS_FILE}" ||
	fail 'LAN wildcard pre-start did not use global port check'
unset ADGUARDHOME_SKIP_DNSMASQ_RESTART

printf '%s\n' 'bind_host: 0.0.0.0' 'bind_port: 3000' >"${WORK_DIR}/AdGuardHome.yaml" || fail 'could not restore AdGuardHome yaml'

printf '%s\n' 'ADGUARD_INSTALL_MODE="wan"' 'ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="0"' >"${WORK_DIR}/.config" ||
	fail 'could not restore WAN install mode'
DNSMASQ_RUNNING=1

: >"${CALLS_FILE}"
printf '%s %s\n' 999999 1 >"${DNS_HANDOFF_FILE}" || fail 'could not create stale handoff marker before invalid config'
printf '%s\n' '#!/bin/sh' 'exit 1' >"${WORK_DIR}/AdGuardHome" || fail 'could not create failing AdGuardHome binary'
chmod 755 "${WORK_DIR}/AdGuardHome" || fail 'could not chmod failing AdGuardHome binary'
clear_dns_handoff_active
if pre_start_adguardhome; then
	fail 'WAN pre-start accepted invalid config with stale handoff state'
fi
[ ! -f "${DNS_HANDOFF_FILE}" ] || fail 'invalid-config stale handoff recovery left marker behind'
grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'invalid-config stale handoff recovery did not restart dnsmasq'
[ -z "${ADGUARDHOME_DNS_HANDOFF_ACTIVE:-}" ] || fail 'invalid-config stale handoff recovery set the active flag'
printf '%s\n' '#!/bin/sh' 'exit 0' >"${WORK_DIR}/AdGuardHome" || fail 'could not restore AdGuardHome binary'
chmod 755 "${WORK_DIR}/AdGuardHome" || fail 'could not chmod restored AdGuardHome binary'

: >"${CALLS_FILE}"
DNS_STATE=free
ADGUARDHOME_DNSMASQ_STOP_RETRIES=3
ADGUARDHOME_DNS_GUARD_RETRIES=0
pre_start_adguardhome || fail 'pre-start rejected an already-free DNS port'
! grep -q '^service stop_dnsmasq$' "${CALLS_FILE}" || fail 'pre-start stopped dnsmasq after port 53 was already free'
stop_dns_port_guard
disable_dns_handoff || fail 'could not clean up free-port pre-start handoff'

: >"${CALLS_FILE}"
DNS_STATE=owned
ADGUARDHOME_DNSMASQ_STOP_RETRIES=3
ADGUARDHOME_DNS_GUARD_RETRIES=0
pre_start_adguardhome || fail 'pre-start rejected AdGuardHome-owned DNS port'
! grep -q '^service stop_dnsmasq$' "${CALLS_FILE}" || fail 'pre-start stopped dnsmasq after AdGuardHome owned port 53'
stop_dns_port_guard
disable_dns_handoff || fail 'could not clean up owned-port pre-start handoff'

: >"${CALLS_FILE}"
DNS_STATE=free
ADGUARDHOME_DNS_GUARD_RETRIES=3
start_dns_port_guard &
ADGUARDHOME_DNS_GUARD_PID="$!"
command sleep 0.01
command kill -0 "${ADGUARDHOME_DNS_GUARD_PID}" 2>/dev/null || fail 'DNS guard exited before AdGuardHome owned DNS'
stop_dns_port_guard
! grep -q '^service stop_dnsmasq$' "${CALLS_FILE}" || fail 'DNS guard stopped dnsmasq after port 53 was free'

: >"${CALLS_FILE}"
DNS_STATE=free
SLEEP_CALLS=0
SLEEP_BUSY_AFTER=1
KILL_RELEASES_PORT=0
ADGUARDHOME_DNS_GUARD_RETRIES=3
start_dns_port_guard &
ADGUARDHOME_DNS_GUARD_PID="$!"
_guard_check_attempts=0
while ! grep -q '^service stop_dnsmasq$' "${CALLS_FILE}" && [ "${_guard_check_attempts}" -lt 20 ]; do
	_guard_check_attempts="$((_guard_check_attempts + 1))"
	command sleep 0.01
done
grep -q '^service stop_dnsmasq$' "${CALLS_FILE}" || fail 'DNS guard did not stop dnsmasq after it reclaimed a free port'
stop_dns_port_guard
SLEEP_BUSY_AFTER=0

: >"${CALLS_FILE}"
DNS_STATE=owned
ADGUARDHOME_DNS_GUARD_RETRIES=3
start_dns_port_guard &
ADGUARDHOME_DNS_GUARD_PID="$!"
command sleep 0.01
stop_dns_port_guard
! grep -q '^service stop_dnsmasq$' "${CALLS_FILE}" || fail 'DNS guard stopped dnsmasq after AdGuardHome owned port 53'

: >"${CALLS_FILE}"
DNS_STATE=owned
WEB_STATE=foreign
if adguardhome_web_port_available; then
	fail 'WebUI check accepted a foreign listener on the configured port'
fi
grep -q 'WebUI port is unavailable' "${CALLS_FILE}" &&
	fail 'WebUI helper logged while checking a foreign listener directly'
WEB_STATE=bound

printf '%s\n' 'ADGUARD_WEBUI_PORT="3000"' >"${WORK_DIR}/.config" || fail 'could not reset stale AdGuardHome config'
printf '%s\n' 'http:' '  address: 0.0.0.0:3001' >"${WORK_DIR}/AdGuardHome.yaml" || fail 'could not set alternate AdGuardHome yaml port'
if [ "$(adguardhome_web_port)" != 3001 ]; then
	fail 'WebUI port check did not prefer the YAML port over stale .config'
fi
printf '%s\n' 'http:' '  address: 0.0.0.0:80' >"${WORK_DIR}/AdGuardHome.yaml" || fail 'could not set low AdGuardHome yaml port'
if [ "$(adguardhome_web_port)" != 80 ]; then
	fail 'WebUI port check rejected a valid low YAML port'
fi
WEB_STATE=bound80
if ! adguardhome_web_port_available; then
	fail 'WebUI availability check rejected AdGuardHome on a valid low YAML port'
fi
WEB_STATE=bound
printf '%s\n' 'ADGUARD_WEBUI_PORT="3000"' >"${WORK_DIR}/.config" || fail 'could not restore AdGuardHome config'
printf '%s\n' 'bind_host: 0.0.0.0' 'bind_port: 3000' >"${WORK_DIR}/AdGuardHome.yaml" || fail 'could not restore AdGuardHome yaml'

: >"${CALLS_FILE}"
DNS_STATE=busy
KILL_RELEASES_PORT=1
ADGUARDHOME_DNSMASQ_STOP_RETRIES=3
ADGUARDHOME_DNS_GUARD_RETRIES=0
pre_start_adguardhome || fail 'pre-start did not release a killable port owner'
[ "${DNS_STATE}" = free ] || fail 'pre-start did not synchronously release port 53'
[ "$(grep -c '^service restart_dnsmasq$' "${CALLS_FILE}")" -eq 1 ] || fail 'pre-start did not regenerate dnsmasq configuration'
[ "$(grep -c '^service stop_dnsmasq$' "${CALLS_FILE}")" -eq 1 ] || fail 'pre-start did not stop the remaining DNS owner exactly once'
grep -q '^kill -s 9 123$' "${CALLS_FILE}" || fail 'pre-start did not kill the remaining port owner'
grep -q 'pre_start_adguardhome: Validating AdGuardHome configuration and permissions' "${CALLS_FILE}" ||
	fail 'pre-start did not log validation progress'
grep -q 'pre_start_adguardhome: Port 53 released; starting AdGuardHome' "${CALLS_FILE}" ||
	fail 'pre-start did not log the transition to AdGuardHome startup'
stop_dns_port_guard
disable_dns_handoff || fail 'could not clean up successful pre-start handoff'

: >"${CALLS_FILE}"
printf '%s\n' '#!/bin/sh' 'exit 1' >"${WORK_DIR}/AdGuardHome" || fail 'could not set failing AdGuardHome config check'
chmod 755 "${WORK_DIR}/AdGuardHome" || fail 'could not chmod failing AdGuardHome binary'
DNS_STATE=busy
if pre_start_adguardhome; then
	fail 'pre-start accepted an invalid AdGuardHome configuration'
fi
grep -q 'AdGuardHome configuration validation failed; restoring dnsmasq' "${CALLS_FILE}" ||
	fail 'pre-start did not log config validation recovery'
[ "$(grep -c '^service restart_dnsmasq$' "${CALLS_FILE}")" -eq 1 ] || fail 'failed config validation did not restore dnsmasq exactly once'
printf '%s\n' '#!/bin/sh' 'exit 0' >"${WORK_DIR}/AdGuardHome" || fail 'could not restore AdGuardHome config check'
chmod 755 "${WORK_DIR}/AdGuardHome" || fail 'could not chmod restored AdGuardHome binary'

: >"${CALLS_FILE}"
DNS_STATE=busy
KILL_RELEASES_PORT=1
ADGUARDHOME_DNSMASQ_STOP_RETRIES=3
ADGUARDHOME_DNS_GUARD_RETRIES=3
pre_start_adguardhome || fail 'pre-start rejected a port that became free after one stop'
[ "$(grep -c '^service stop_dnsmasq$' "${CALLS_FILE}")" -eq 1 ] || fail 'pre-start stopped dnsmasq again after port 53 became free'
stop_dns_port_guard
disable_dns_handoff || fail 'could not clean up one-stop pre-start handoff'

: >"${CALLS_FILE}"
DNS_STATE=busy
KILL_RELEASES_PORT=0
ADGUARDHOME_DNSMASQ_STOP_RETRIES=3
ADGUARDHOME_DNS_GUARD_RETRIES=0
if pre_start_adguardhome; then
	fail 'pre-start succeeded while dnsmasq continuously reclaimed port 53'
fi
[ "$(grep -c '^service stop_dnsmasq$' "${CALLS_FILE}")" -eq 3 ] || fail 'pre-start retry limit was not enforced'
grep -q 'Unable to release port 53 after 3 attempt(s)' "${CALLS_FILE}" || fail 'pre-start timeout was not logged'
[ "$(grep -c '^service restart_dnsmasq$' "${CALLS_FILE}")" -eq 2 ] || fail 'pre-start did not configure and then restore dnsmasq'
[ ! -e "${DNS_HANDOFF_FILE}" ] || fail 'failed pre-start left the dnsmasq handoff enabled'

: >"${CALLS_FILE}"
DNS_STATE=busy
ADGUARDHOME_SKIP_DNSMASQ_RESTART=1
if pre_start_adguardhome; then
	fail 'pre-start succeeded while port 53 remained busy with restart suppression enabled'
fi
[ "$(grep -c '^service restart_dnsmasq$' "${CALLS_FILE}")" -eq 1 ] || fail 'pre-start timeout ignored restart suppression during recovery'
unset ADGUARDHOME_SKIP_DNSMASQ_RESTART

: >"${CALLS_FILE}"
DNS_STATE=busy
NETSTAT_FAIL=1
ADGUARDHOME_DNSMASQ_STOP_RETRIES=2
ADGUARDHOME_DNS_GUARD_RETRIES=0
if pre_start_adguardhome; then
	fail 'pre-start succeeded while port ownership could not be inspected'
fi
! grep -q '^service stop_dnsmasq$' "${CALLS_FILE}" || fail 'pre-start stopped dnsmasq without confirming a foreign port 53 owner'
NETSTAT_FAIL=0

: >"${CALLS_FILE}"
DNS_STATE=busy
KILL_RELEASES_PORT=0
SLEEP_SETS_OWNED=1
ADGUARDHOME_DNS_GUARD_RETRIES=3
start_dns_port_guard &
ADGUARDHOME_DNS_GUARD_PID="$!"
_guard_check_attempts=0
while ! grep -q '^service stop_dnsmasq$' "${CALLS_FILE}" && [ "${_guard_check_attempts}" -lt 20 ]; do
	_guard_check_attempts="$((_guard_check_attempts + 1))"
	command sleep 0.01
done
grep -q '^service stop_dnsmasq$' "${CALLS_FILE}" || fail 'bounded guard did not stop a respawned dnsmasq'
command sleep 0.01
command kill -0 "${ADGUARDHOME_DNS_GUARD_PID}" 2>/dev/null || fail 'DNS guard exited before explicit cleanup'
_guard_pid="${ADGUARDHOME_DNS_GUARD_PID}"
stop_dns_port_guard
if command kill -0 "${_guard_pid}" 2>/dev/null; then
	fail 'DNS guard remained alive after explicit cleanup'
fi
[ -z "${ADGUARDHOME_DNS_GUARD_PID:-}" ] || fail 'DNS guard PID was not cleared after cleanup'
grep -q "^kill ${_guard_pid}$" "${CALLS_FILE}" || fail 'DNS guard was not explicitly terminated'
SLEEP_SETS_OWNED=0

: >"${CALLS_FILE}"
DNS_STATE=busy
SLEEP_CALLS=0
SLEEP_OWNED_AFTER=12
unset ADGUARDHOME_DNS_WAIT_RETRIES
ADGUARDHOME_SKIP_DNSMASQ_RESTART=1
post_start_adguardhome || fail 'post-start did not wait long enough for delayed AdGuardHome DNS ownership'
[ "${SLEEP_CALLS}" -gt 10 ] || fail 'post-start did not wait past the old 10 second default'
! grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'post-start ignored restart suppression after delayed DNS ownership'
SLEEP_OWNED_AFTER=0
unset ADGUARDHOME_SKIP_DNSMASQ_RESTART

: >"${CALLS_FILE}"
DNS_STATE=missing
SLEEP_CALLS=0
ADGUARDHOME_DNS_WAIT_RETRIES=30
if post_start_adguardhome; then
	fail 'post-start succeeded after AdGuardHome exited before DNS ownership'
fi
[ "${SLEEP_CALLS}" -eq 0 ] || fail 'post-start kept waiting after AdGuardHome exited'
grep -q 'AdGuardHome process is missing' "${CALLS_FILE}" || fail 'missing AdGuardHome process was not logged'

: >"${CALLS_FILE}"
DNS_STATE=busy
ADGUARDHOME_DNS_WAIT_RETRIES=2
unset ADGUARDHOME_SKIP_DNSMASQ_RESTART
if post_start_adguardhome; then
	fail 'post-start succeeded before AdGuardHome owned port 53'
fi
! grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'post-start restarted dnsmasq before AdGuardHome owned DNS'
grep -q 'AdGuardHome startup failed: process is running but DNS is not bound' "${CALLS_FILE}" || fail 'DNS startup failure did not log the concise DNS-bound message'

: >"${CALLS_FILE}"
DNS_STATE=owned
WEB_STATE=missing
ADGUARDHOME_SKIP_DNSMASQ_RESTART=1
if post_start_adguardhome; then
	fail 'post-start succeeded with an unavailable WebUI port'
fi
grep -q 'AdGuardHome startup failed: WebUI port is unavailable' "${CALLS_FILE}" || fail 'WebUI startup failure did not log the concise WebUI message'
WEB_STATE=bound

: >"${CALLS_FILE}"
DNS_STATE=owned
WEB_STATE=missing
SLEEP_CALLS=0
SLEEP_WEB_BOUND_AFTER=2
ADGUARDHOME_STARTUP_CHECK_RETRIES=5
ADGUARDHOME_SKIP_DNSMASQ_RESTART=1
post_start_adguardhome || fail 'post-start did not wait for delayed WebUI readiness'
[ "${SLEEP_CALLS}" -eq 2 ] || fail 'post-start did not retry WebUI readiness until it became available'
! grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'post-start ignored restart suppression after delayed WebUI readiness'
unset ADGUARDHOME_SKIP_DNSMASQ_RESTART
unset ADGUARDHOME_STARTUP_CHECK_RETRIES
SLEEP_WEB_BOUND_AFTER=0
WEB_STATE=bound

: >"${CALLS_FILE}"
DNS_STATE=owned
WEB_STATE=missing
unset ADGUARDHOME_SKIP_DNSMASQ_RESTART
mark_dns_handoff_active
if post_start_adguardhome; then
	fail 'post-start succeeded with an unavailable WebUI port before restoring dnsmasq'
fi
grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'WebUI startup failure did not restore dnsmasq'
WEB_STATE=bound
clear_dns_handoff_active

printf '%s\n' '#!/bin/sh' 'exit 1' >"${WORK_DIR}/AdGuardHome" || fail 'could not replace AdGuardHome binary'
chmod 755 "${WORK_DIR}/AdGuardHome" || fail 'could not chmod failing AdGuardHome binary'
: >"${CALLS_FILE}"
mark_dns_handoff_active
if post_start_adguardhome; then
	fail 'post-start succeeded with a failing configuration check'
fi
grep -q 'AdGuardHome startup failed: configuration check failed' "${CALLS_FILE}" || fail 'config startup failure did not log the concise config message'
grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'config startup failure did not restore dnsmasq'
clear_dns_handoff_active
printf '%s\n' '#!/bin/sh' 'exit 0' >"${WORK_DIR}/AdGuardHome" || fail 'could not restore AdGuardHome binary'
chmod 755 "${WORK_DIR}/AdGuardHome" || fail 'could not chmod restored AdGuardHome binary'

: >"${CALLS_FILE}"
DNS_STATE=owned
ADGUARDHOME_SKIP_DNSMASQ_RESTART=1
post_start_adguardhome || fail 'post-start rejected valid AdGuardHome DNS ownership'
! grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'post-start ignored the dnsmasq restart suppression flag'

: >"${CALLS_FILE}"
unset ADGUARDHOME_SKIP_DNSMASQ_RESTART
mark_dns_handoff_active
post_start_adguardhome || fail 'post-start rejected valid AdGuardHome DNS ownership'
grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'post-start did not restart dnsmasq after DNS ownership was established'
grep -q 'post_start_adguardhome: Restarting dnsmasq after successful AdGuardHome startup' "${CALLS_FILE}" ||
	fail 'post-start did not log the dnsmasq restart'
grep -q 'post_start_adguardhome: AdGuardHome startup completed' "${CALLS_FILE}" ||
	fail 'post-start did not log startup completion'

: >"${CALLS_FILE}"
mark_dns_handoff_active
SERVICE_RESTART_FAIL=1
if post_start_adguardhome; then
	fail 'post-start ignored a failed dnsmasq restart'
fi
grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'post-start did not attempt the failed dnsmasq restart'
[ "${ADGUARDHOME_DNS_HANDOFF_ACTIVE:-}" = "1" ] || fail 'post-start cleared active handoff after failed dnsmasq restart'
SERVICE_RESTART_FAIL=0
: >"${CALLS_FILE}"
post_start_failure_adguardhome || fail 'failure recovery did not retry dnsmasq after post-start restart failure'
grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'failure recovery did not retry the failed dnsmasq restart'
[ -z "${ADGUARDHOME_DNS_HANDOFF_ACTIVE:-}" ] || fail 'failure recovery did not clear active handoff after retry'
clear_dns_handoff_active

: >"${CALLS_FILE}"
prepare_active_dns_handoff_test_marker || fail 'could not prepare active marker for failed recovery restart test'
SERVICE_RESTART_FAIL=1
if post_start_failure_adguardhome; then
	fail 'failure recovery ignored a failed dnsmasq restart'
fi
grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'failure recovery did not attempt the failed dnsmasq restart'
[ "${ADGUARDHOME_DNS_HANDOFF_ACTIVE:-}" = "1" ] || fail 'failure recovery cleared active handoff after failed dnsmasq restart'
SERVICE_RESTART_FAIL=0
: >"${CALLS_FILE}"
post_start_failure_adguardhome || fail 'failure recovery did not retry dnsmasq after failed recovery restart'
grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'failure recovery did not retry failed recovery restart'
[ -z "${ADGUARDHOME_DNS_HANDOFF_ACTIVE:-}" ] || fail 'failure recovery did not clear active handoff after restart retry'
clear_dns_handoff_active

# Verify rc.func treats either hook failure as a failed start instead of launching
# through a bad handoff or reporting a short-lived process as healthy.
ansi_white=''
ansi_yellow=''
ansi_red=''
ansi_green=''
ansi_std=''
CALLER='test'
CRITICAL='yes'
ENABLED='yes'
DESC='AdGuardHome'
PROC='AdGuardHome'
PREARGS=''
ARGS=''
PRECMD='pre_hook'
POSTCMD='post_hook'
POSTFAILCMD='post_failure_hook'

process_pids() {
	[ -f "${STARTED_FILE}" ] && printf '%s\n' 456
}
process_wait_for_start() {
	_counter=0
	while [ "${_counter}" -lt 20 ]; do
		[ -f "${STARTED_FILE}" ] && return 0
		_counter="$((_counter + 1))"
		command sleep 0.01
	done
	return 1
}
process_wait_for_stop() {
	[ ! -f "${STARTED_FILE}" ]
}
signal_process() {
	printf '%s\n' "signal $*" >>"${CALLS_FILE}"
	[ "${STOP_ON_SIGNAL:-TERM}" = "$1" ] && rm -f "${STARTED_FILE}"
}
grep() {
	case "$*" in
		*'/etc/dnsmasq.conf'*) return 1 ;;
	esac
	command grep "$@"
}
AdGuardHome() {
	: >"${STARTED_FILE}"
}

pre_hook() {
	return 1
}
# post_hook returns success after the AdGuardHome start hook completes.
post_hook() {
	return 0
}
# post_failure_hook records the DNSMasq restart-suppression state and performs AdGuardHome start-failure recovery.
post_failure_hook() {
	printf '%s\n' "post_failure_hook ${ADGUARDHOME_SKIP_DNSMASQ_RESTART:-0}" >>"${CALLS_FILE}"
	post_start_failure_adguardhome
}

# The pre-start hook changes dnsmasq to port 553.  Post-start cleanup must be
# tied to this invocation having run that hook, not to the mutated config.
: >"${CALLS_FILE}"
rm -f "${STARTED_FILE}"
(
	HANDOFF_ENABLED=0
	# grep filters dnsmasq configuration checks by the simulated handoff state and delegates all other searches to the system grep command.
	grep() {
		case "$*" in
			*'/etc/dnsmasq.conf'*) [ "${HANDOFF_ENABLED}" -eq 1 ] ;;
			*) command grep "$@" ;;
		esac
	}
	# pre_hook enables DNS handoff, prepares its active marker, and records the hook invocation.
	pre_hook() {
		HANDOFF_ENABLED=1
		prepare_active_dns_handoff_test_marker || return 1
		printf '%s\n' pre_hook >>"${CALLS_FILE}"
	}
	# post_hook records that the post-start hook was invoked.
	post_hook() {
		printf '%s\n' post_hook >>"${CALLS_FILE}"
	}
	start >/dev/null
) || fail 'rc.func failed a successful handoff start'
grep -q '^pre_hook$' "${CALLS_FILE}" || fail 'rc.func did not run the pre-start handoff hook'
grep -q '^post_hook$' "${CALLS_FILE}" || fail 'rc.func skipped post-start cleanup after dnsmasq changed to port 553'

# A stale dnsmasq port 553 config without an active marker must be recovered by
# running the pre-start hook again.  The old skip was keyed only to the config
# content and would bypass the hook in this state.
: >"${CALLS_FILE}"
printf '%s\n' 'port=553' >"${DNSMASQ_CONF_FILE}" || fail 'could not seed stale dnsmasq config'
rm -f "${STARTED_FILE}" "${DNS_HANDOFF_FILE}"
(
	# grep overrides searches for `/etc/dnsmasq.conf` to inspect the test dnsmasq configuration file.
	grep() {
		case "$*" in
			*'/etc/dnsmasq.conf'*)
				shift "$#"
				command grep '^port=553' "${DNSMASQ_CONF_FILE}"
				;;
			*) command grep "$@" ;;
		esac
	}
	# pre_hook prepares the active DNS handoff marker and records its invocation.
	pre_hook() {
		prepare_active_dns_handoff_test_marker || return 1
		printf '%s\n' stale_pre_hook >>"${CALLS_FILE}"
	}
	# post_hook records a stale post-start hook invocation in the test call log.
	post_hook() {
		printf '%s\n' stale_post_hook >>"${CALLS_FILE}"
	}
	start >/dev/null
) || fail 'rc.func failed to recover a stale dnsmasq port 553 startup'
grep -q '^stale_pre_hook$' "${CALLS_FILE}" || fail 'rc.func skipped pre-start with stale dnsmasq port 553 and no active handoff marker'
grep -q '^stale_post_hook$' "${CALLS_FILE}" || fail 'rc.func skipped post-start cleanup after stale dnsmasq port 553 recovery'

# If the initial start check does not require handoff but PRECMD prepares one
# after dnsmasq appears, post-start cleanup must run without dnsmasq restart
# suppression so the real handoff is restored.
: >"${CALLS_FILE}"
rm -f "${STARTED_FILE}" "${DNS_HANDOFF_FILE}"
(
	# agh_dns_handoff_required determines whether DNS handoff is required and reports that it is not required.
	agh_dns_handoff_required() {
		return 1
	}
	# pre_hook prepares the active DNS handoff marker and records its execution.
	pre_hook() {
		prepare_active_dns_handoff_test_marker || return 1
		printf '%s\n' late_handoff_pre_hook >>"${CALLS_FILE}"
	}
	# post_hook succeeds when dnsmasq restart recovery is enabled.
	post_hook() {
		printf '%s\n' "late_handoff_post_hook ${ADGUARDHOME_SKIP_DNSMASQ_RESTART:-0}" >>"${CALLS_FILE}"
		[ "${ADGUARDHOME_SKIP_DNSMASQ_RESTART:-0}" = "0" ]
	}
	start >/dev/null
) || fail 'rc.func failed a late handoff prepared by pre-start'
grep -q '^late_handoff_pre_hook$' "${CALLS_FILE}" || fail 'rc.func skipped late handoff pre-start hook'
grep -q '^late_handoff_post_hook 0$' "${CALLS_FILE}" || fail 'rc.func suppressed dnsmasq restart after late handoff marker was prepared'

# When PRECMD decides DNS handoff is required, rc.func must fail if the
# required marker was not prepared successfully.
: >"${CALLS_FILE}"
rm -f "${STARTED_FILE}" "${DNS_HANDOFF_FILE}"
(
	# pre_hook marks the DNS handoff as required and records the hook invocation.
	pre_hook() {
		ADGUARDHOME_DNS_HANDOFF_REQUIRED=1
		export ADGUARDHOME_DNS_HANDOFF_REQUIRED
		printf '%s\n' required_handoff_missing_pre_hook >>"${CALLS_FILE}"
	}
	# post_hook records that the required DNS handoff marker is missing after startup.
	post_hook() {
		printf '%s\n' required_handoff_missing_post_hook >>"${CALLS_FILE}"
	}
	if start >/dev/null; then
		exit 1
	fi
) || fail 'rc.func accepted a required handoff that PRECMD did not prepare'
grep -q '^required_handoff_missing_pre_hook$' "${CALLS_FILE}" || fail 'rc.func skipped required-handoff pre-start hook'
! grep -q '^required_handoff_missing_post_hook$' "${CALLS_FILE}" || fail 'rc.func ran post-start after missing required handoff'
[ ! -f "${STARTED_FILE}" ] || fail 'rc.func launched AdGuardHome after missing required handoff'

# If PRECMD activated the required handoff but the marker is missing before
# rc.func verifies ownership, failed-start recovery must run without dnsmasq
# restart suppression so dnsmasq is restored from the prepared handoff state.
: >"${CALLS_FILE}"
rm -f "${STARTED_FILE}" "${DNS_HANDOFF_FILE}"
(
	# pre_hook prepares a required DNS handoff marker, removes it to simulate marker loss, and records the test event.
	pre_hook() {
		ADGUARDHOME_DNS_HANDOFF_REQUIRED=1
		export ADGUARDHOME_DNS_HANDOFF_REQUIRED
		prepare_active_dns_handoff_test_marker || return 1
		rm -f "${DNS_HANDOFF_FILE}" || return 1
		printf '%s\n' required_handoff_lost_marker_pre_hook >>"${CALLS_FILE}"
	}
	# post_hook records that the required handoff marker was lost during the post-start hook.
	post_hook() {
		printf '%s\n' required_handoff_lost_marker_post_hook >>"${CALLS_FILE}"
	}
	if start >/dev/null; then
		exit 1
	fi
) || fail 'rc.func accepted a required handoff whose active marker was lost'
grep -q '^required_handoff_lost_marker_pre_hook$' "${CALLS_FILE}" || fail 'rc.func skipped required-handoff lost-marker pre-start hook'
grep -q '^post_failure_hook 0$' "${CALLS_FILE}" || fail 'rc.func suppressed dnsmasq restart after required handoff marker was lost'
grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'rc.func did not restore dnsmasq after required handoff marker was lost'
! grep -q '^required_handoff_lost_marker_post_hook$' "${CALLS_FILE}" || fail 'rc.func ran post-start after required handoff marker was lost'
[ ! -f "${STARTED_FILE}" ] || fail 'rc.func launched AdGuardHome after required handoff marker was lost'

# If required handoff preparation is interrupted after PRECMD has activated the
# dnsmasq handoff, failed-start recovery must restore dnsmasq instead of
# treating the start as a no-handoff flow.
REQUIRED_PRE_INTERRUPT_READY_FILE="${TEST_ROOT}/required-pre-interrupt-ready"
: >"${CALLS_FILE}"
rm -f "${STARTED_FILE}" "${DNS_HANDOFF_FILE}" "${REQUIRED_PRE_INTERRUPT_READY_FILE}"
(
	# pre_hook marks DNS handoff as required, prepares its active marker, records readiness, and waits until interrupted.
	pre_hook() {
		ADGUARDHOME_DNS_HANDOFF_REQUIRED=1
		export ADGUARDHOME_DNS_HANDOFF_REQUIRED
		prepare_active_dns_handoff_test_marker || return 1
		printf '%s\n' required_pre_interrupt_hook >>"${CALLS_FILE}"
		: >"${REQUIRED_PRE_INTERRUPT_READY_FILE}"
		while :; do
			command sleep 1
		done
	}
	start >/dev/null
) &
_required_pre_interrupt_pid="$!"
_required_pre_interrupt_waits=0
while [ ! -f "${REQUIRED_PRE_INTERRUPT_READY_FILE}" ] && [ "${_required_pre_interrupt_waits}" -lt 100 ]; do
	_required_pre_interrupt_waits="$((_required_pre_interrupt_waits + 1))"
	command sleep 0.01
done
[ -f "${REQUIRED_PRE_INTERRUPT_READY_FILE}" ] || fail 'interrupted required pre-start did not reach the guarded pre-start window'
command kill -TERM "${_required_pre_interrupt_pid}" 2>/dev/null || fail 'could not interrupt required pre-start'
if wait "${_required_pre_interrupt_pid}"; then
	fail 'interrupted required pre-start reported success'
fi
grep -q '^required_pre_interrupt_hook$' "${CALLS_FILE}" || fail 'interrupted required pre-start skipped pre-start hook'
grep -q '^post_failure_hook 0$' "${CALLS_FILE}" || fail 'interrupted required pre-start suppressed dnsmasq restart during recovery'
grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'interrupted required pre-start did not restore dnsmasq'
disable_dns_handoff || fail 'could not clean up interrupted required pre-start handoff'

# A LAN-mode start where pre-start intentionally skips the dnsmasq handoff must
# still run post-start readiness checks, but suppress dnsmasq restart cleanup.
: >"${CALLS_FILE}"
rm -f "${STARTED_FILE}" "${DNS_HANDOFF_FILE}"
(
	# pre_hook marks DNS handoff as unnecessary, suppresses dnsmasq restart recovery, and records its invocation.
	pre_hook() {
		ADGUARDHOME_DNS_HANDOFF_REQUIRED=0
		ADGUARDHOME_SKIP_DNSMASQ_RESTART=1
		export ADGUARDHOME_DNS_HANDOFF_REQUIRED ADGUARDHOME_SKIP_DNSMASQ_RESTART
		printf '%s\n' no_handoff_pre_hook >>"${CALLS_FILE}"
	}
	# post_hook reports whether dnsmasq restart suppression is enabled and succeeds when suppression is active.
	post_hook() {
		printf '%s\n' "no_handoff_post_hook ${ADGUARDHOME_SKIP_DNSMASQ_RESTART:-0}" >>"${CALLS_FILE}"
		[ "${ADGUARDHOME_SKIP_DNSMASQ_RESTART:-0}" = "1" ]
	}
	start >/dev/null
) || fail 'rc.func failed a successful no-handoff start'
grep -q '^no_handoff_pre_hook$' "${CALLS_FILE}" || fail 'rc.func did not run the no-handoff pre-start hook'
grep -q '^no_handoff_post_hook 1$' "${CALLS_FILE}" || fail 'rc.func did not run no-handoff post-start checks with restart suppression'

: >"${CALLS_FILE}"
rm -f "${STARTED_FILE}" "${DNS_HANDOFF_FILE}"
(
	# pre_hook configures the test to skip DNS handoff and dnsmasq restart, then records its invocation.
	pre_hook() {
		ADGUARDHOME_DNS_HANDOFF_REQUIRED=0
		ADGUARDHOME_SKIP_DNSMASQ_RESTART=1
		export ADGUARDHOME_DNS_HANDOFF_REQUIRED ADGUARDHOME_SKIP_DNSMASQ_RESTART
		printf '%s\n' no_handoff_fail_pre_hook >>"${CALLS_FILE}"
	}
	# post_hook records a simulated post-start hook failure and returns failure.
	post_hook() {
		printf '%s\n' no_handoff_fail_post_hook >>"${CALLS_FILE}"
		return 1
	}
	if start >/dev/null; then
		exit 1
	fi
) || fail 'rc.func ignored a failed no-handoff post-start readiness check'
grep -q '^no_handoff_fail_post_hook$' "${CALLS_FILE}" || fail 'rc.func skipped failing no-handoff post-start checks'
grep -q '^signal TERM AdGuardHome$' "${CALLS_FILE}" || fail 'rc.func did not stop AdGuardHome after no-handoff post-start failure'
grep -q '^post_failure_hook 1$' "${CALLS_FILE}" || fail 'rc.func did not suppress dnsmasq restart during no-handoff post-start failure recovery'

# Interrupting startup after the pre-start hook has spawned the DNS guard must
# reap that child and run the same dnsmasq recovery used by other failed starts.
INTERRUPT_READY_FILE="${TEST_ROOT}/interrupt-ready"
INTERRUPT_GUARD_PID_FILE="${TEST_ROOT}/interrupt-guard-pid"
: >"${CALLS_FILE}"
rm -f "${INTERRUPT_READY_FILE}" "${INTERRUPT_GUARD_PID_FILE}"
(
	HANDOFF_ENABLED=0
	#adguardhome_start_handoff_is_prepared determines whether the AdGuardHome startup DNS handoff is prepared.
	# Returns a successful status when the handoff is enabled; otherwise, returns a failure status.
	adguardhome_start_handoff_is_prepared() {
		[ "${HANDOFF_ENABLED}" -eq 1 ]
	}
	# pre_hook starts the DNS handoff guard and records its process identity for interrupt recovery.
	pre_hook() {
		command sh -c 'trap "exit 0" HUP INT TERM; while :; do sleep 1; done' &
		ADGUARDHOME_DNS_GUARD_PID="$!"
		printf '%s\n' "${ADGUARDHOME_DNS_GUARD_PID}" >"${INTERRUPT_GUARD_PID_FILE}"
		HANDOFF_ENABLED=1
		mark_dns_handoff_active
	}
	# process_pids returns successfully without producing any process IDs.
	process_pids() {
		return 0
	}
	process_wait_for_start() {
		: >"${INTERRUPT_READY_FILE}"
		while :; do
			command sleep 1
		done
	}
	AdGuardHome() {
		return 0
	}
	start >/dev/null
) &
_interrupt_start_pid="$!"
_interrupt_wait_attempts=0
while [ ! -f "${INTERRUPT_READY_FILE}" ] && [ "${_interrupt_wait_attempts}" -lt 100 ]; do
	_interrupt_wait_attempts="$((_interrupt_wait_attempts + 1))"
	command sleep 0.01
done
[ -f "${INTERRUPT_READY_FILE}" ] || fail 'interrupted start did not reach the guarded startup window'
command kill -TERM "${_interrupt_start_pid}" 2>/dev/null || fail 'could not interrupt guarded startup'
if wait "${_interrupt_start_pid}"; then
	fail 'interrupted guarded startup reported success'
fi
_interrupt_guard_pid="$(cat "${INTERRUPT_GUARD_PID_FILE}")"
if command kill -0 "${_interrupt_guard_pid}" 2>/dev/null; then
	fail 'DNS guard survived an interrupted startup'
fi
grep -q "^kill ${_interrupt_guard_pid}$" "${CALLS_FILE}" || fail 'interrupted startup did not terminate the DNS guard'
grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'interrupted startup did not restore dnsmasq'

# Interrupting a LAN/no-handoff startup must not restart dnsmasq through the
# signal trap's failed-start recovery path.
NO_HANDOFF_INTERRUPT_READY_FILE="${TEST_ROOT}/no-handoff-interrupt-ready"
: >"${CALLS_FILE}"
rm -f "${STARTED_FILE}" "${DNS_HANDOFF_FILE}" "${NO_HANDOFF_INTERRUPT_READY_FILE}"
(
	# pre_hook prepares an interrupt test without requiring DNS handoff or dnsmasq restart recovery.
	pre_hook() {
		ADGUARDHOME_DNS_HANDOFF_REQUIRED=0
		ADGUARDHOME_SKIP_DNSMASQ_RESTART=1
		export ADGUARDHOME_DNS_HANDOFF_REQUIRED ADGUARDHOME_SKIP_DNSMASQ_RESTART
		printf '%s\n' no_handoff_interrupt_pre_hook >>"${CALLS_FILE}"
	}
	# process_pids returns successfully without producing any process IDs.
	process_pids() {
		return 0
	}
	# process_wait_for_start waits indefinitely until interrupted after signaling readiness for no-handoff interrupt tests.
	process_wait_for_start() {
		: >"${NO_HANDOFF_INTERRUPT_READY_FILE}"
		while :; do
			command sleep 1
		done
	}
	AdGuardHome() {
		return 0
	}
	start >/dev/null
) &
_no_handoff_interrupt_pid="$!"
_no_handoff_interrupt_waits=0
while [ ! -f "${NO_HANDOFF_INTERRUPT_READY_FILE}" ] && [ "${_no_handoff_interrupt_waits}" -lt 100 ]; do
	_no_handoff_interrupt_waits="$((_no_handoff_interrupt_waits + 1))"
	command sleep 0.01
done
[ -f "${NO_HANDOFF_INTERRUPT_READY_FILE}" ] || fail 'interrupted no-handoff start did not reach the startup window'
command kill -TERM "${_no_handoff_interrupt_pid}" 2>/dev/null || fail 'could not interrupt no-handoff startup'
if wait "${_no_handoff_interrupt_pid}"; then
	fail 'interrupted no-handoff startup reported success'
fi
grep -q '^no_handoff_interrupt_pre_hook$' "${CALLS_FILE}" || fail 'interrupted no-handoff start skipped pre-start hook'
grep -q '^post_failure_hook 1$' "${CALLS_FILE}" || fail 'interrupted no-handoff startup did not suppress dnsmasq restart during recovery'
! grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'interrupted no-handoff startup restarted dnsmasq'

# The no-handoff decision must be visible to the signal trap before PRECMD
# runs, so an interrupt during pre-start validation does not restart dnsmasq.
NO_HANDOFF_PRE_INTERRUPT_READY_FILE="${TEST_ROOT}/no-handoff-pre-interrupt-ready"
: >"${CALLS_FILE}"
rm -f "${STARTED_FILE}" "${DNS_HANDOFF_FILE}" "${NO_HANDOFF_PRE_INTERRUPT_READY_FILE}"
(
	# agh_dns_handoff_required determines whether DNS handoff is required and reports that it is not required.
	agh_dns_handoff_required() {
		return 1
	}
	# pre_hook marks the startup as requiring no DNS handoff and waits for interruption.
	pre_hook() {
		ADGUARDHOME_DNS_HANDOFF_REQUIRED=0
		ADGUARDHOME_SKIP_DNSMASQ_RESTART=1
		export ADGUARDHOME_DNS_HANDOFF_REQUIRED ADGUARDHOME_SKIP_DNSMASQ_RESTART
		printf '%s\n' no_handoff_pre_interrupt_hook >>"${CALLS_FILE}"
		: >"${NO_HANDOFF_PRE_INTERRUPT_READY_FILE}"
		while :; do
			command sleep 1
		done
	}
	start >/dev/null
) &
_no_handoff_pre_interrupt_pid="$!"
_no_handoff_pre_interrupt_waits=0
while [ ! -f "${NO_HANDOFF_PRE_INTERRUPT_READY_FILE}" ] && [ "${_no_handoff_pre_interrupt_waits}" -lt 100 ]; do
	_no_handoff_pre_interrupt_waits="$((_no_handoff_pre_interrupt_waits + 1))"
	command sleep 0.01
done
[ -f "${NO_HANDOFF_PRE_INTERRUPT_READY_FILE}" ] || fail 'interrupted no-handoff pre-start did not reach the guarded pre-start window'
command kill -TERM "${_no_handoff_pre_interrupt_pid}" 2>/dev/null || fail 'could not interrupt no-handoff pre-start'
if wait "${_no_handoff_pre_interrupt_pid}"; then
	fail 'interrupted no-handoff pre-start reported success'
fi
grep -q '^no_handoff_pre_interrupt_hook$' "${CALLS_FILE}" || fail 'interrupted no-handoff pre-start skipped pre-start hook'
grep -q '^post_failure_hook 1$' "${CALLS_FILE}" || fail 'interrupted no-handoff pre-start did not suppress dnsmasq restart during recovery'
! grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'interrupted no-handoff pre-start restarted dnsmasq'

: >"${CALLS_FILE}"
rm -f "${STARTED_FILE}"
if start >/dev/null; then
	fail 'rc.func ignored a failed pre-start hook'
fi
[ ! -f "${STARTED_FILE}" ] || fail 'rc.func launched AdGuardHome after pre-start failure'

# pre_hook prepares and activates the DNS handoff test marker, returning failure if preparation fails.
pre_hook() {
	prepare_active_dns_handoff_test_marker || return 1
	return 0
}
# post_hook indicates that the post-start hook failed.
post_hook() {
	return 1
}
: >"${CALLS_FILE}"
rm -f "${STARTED_FILE}"
if start >/dev/null; then
	fail 'rc.func ignored a failed post-start hook'
fi
grep -q '^signal TERM AdGuardHome$' "${CALLS_FILE}" || fail 'rc.func did not stop AdGuardHome after post-start failure'
grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'rc.func did not restore dnsmasq after post-start failure'
_signal_line="$(grep -n '^signal TERM AdGuardHome$' "${CALLS_FILE}" | cut -d: -f1)"
_restart_line="$(grep -n '^service restart_dnsmasq$' "${CALLS_FILE}" | cut -d: -f1)"
[ "${_signal_line}" -lt "${_restart_line}" ] || fail 'dnsmasq was restored before failed AdGuardHome stopped'

: >"${CALLS_FILE}"
rm -f "${STARTED_FILE}"
STOP_ON_SIGNAL=KILL
if start >/dev/null; then
	fail 'rc.func ignored a failed post-start hook requiring forced termination'
fi
grep -q '^signal TERM AdGuardHome$' "${CALLS_FILE}" || fail 'rc.func did not first send TERM after post-start failure'
grep -q '^signal INT AdGuardHome$' "${CALLS_FILE}" || fail 'rc.func did not escalate to INT after TERM timed out'
grep -q '^signal KILL AdGuardHome$' "${CALLS_FILE}" || fail 'rc.func did not escalate to KILL after INT timed out'
grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'rc.func did not restore dnsmasq after forced termination'
_kill_line="$(grep -n '^signal KILL AdGuardHome$' "${CALLS_FILE}" | cut -d: -f1)"
_restart_line="$(grep -n '^service restart_dnsmasq$' "${CALLS_FILE}" | cut -d: -f1)"
[ "${_kill_line}" -lt "${_restart_line}" ] || fail 'dnsmasq was restored before forced AdGuardHome termination'
unset STOP_ON_SIGNAL

: >"${CALLS_FILE}"
rm -f "${STARTED_FILE}"
ADGUARDHOME_SKIP_DNSMASQ_RESTART=1
if start >/dev/null; then
	fail 'rc.func ignored a failed post-start hook with restart suppression enabled'
fi
grep -q '^signal TERM AdGuardHome$' "${CALLS_FILE}" || fail 'rc.func did not stop failed AdGuardHome when restart was suppressed'
! grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'failure recovery ignored the dnsmasq restart suppression flag'
unset ADGUARDHOME_SKIP_DNSMASQ_RESTART

: >"${CALLS_FILE}"
rm -f "${STARTED_FILE}"
AdGuardHome() {
	return 1
}
post_hook() {
	printf '%s\n' post_hook >>"${CALLS_FILE}"
	return 0
}
if start >/dev/null; then
	fail 'rc.func reported success when the service process never started'
fi
! grep -q '^post_hook$' "${CALLS_FILE}" || fail 'rc.func ran the post-start hook for a process that never started'
grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'failed launch did not restore dnsmasq'

# A launch that outlives the startup wait must be terminated and reaped before
# dnsmasq is restored, otherwise it can claim port 53 after recovery.
: >"${CALLS_FILE}"
rm -f "${STARTED_FILE}"
LATE_LAUNCH_PID_FILE="${TEST_ROOT}/late-launch-pid"
rm -f "${LATE_LAUNCH_PID_FILE}"
AdGuardHome() {
	exec sh -c '
		trap "exit 0" TERM
		printf "%s\n" "$$" >"$1"
		while :; do sleep 1; done
	' sh "${LATE_LAUNCH_PID_FILE}"
}
process_wait_for_start() {
	while [ ! -f "${LATE_LAUNCH_PID_FILE}" ]; do
		command sleep 0.01
	done
	return 1
}
post_failure_hook() {
	_late_launch_pid="$(cat "${LATE_LAUNCH_PID_FILE}")"
	if command kill -0 "${_late_launch_pid}" 2>/dev/null; then
		printf '%s\n' launch_alive_during_recovery >>"${CALLS_FILE}"
	fi
	post_start_failure_adguardhome
}
if start >/dev/null; then
	fail 'rc.func reported success when a launch exceeded the startup wait'
fi
_late_launch_pid="$(cat "${LATE_LAUNCH_PID_FILE}")"
if command kill -0 "${_late_launch_pid}" 2>/dev/null; then
	fail 'launch survived the startup timeout'
fi
! grep -q '^launch_alive_during_recovery$' "${CALLS_FILE}" || fail 'dnsmasq recovery ran before the timed-out launch stopped'
grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'timed-out launch did not restore dnsmasq'

printf '%s\n' 'DNS startup handoff tests passed.'
