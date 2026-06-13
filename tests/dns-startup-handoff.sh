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
	'/^dns_handoff_dependencies_available() {$/,/^}$/p; /^dns_handoff_process_start_time() {$/,/^}$/p; /^dns_handoff_marker_is_active() {$/,/^}$/p; /^disable_dns_handoff() {$/,/^}$/p; /^enable_dns_handoff() {$/,/^}$/p; /^dns_retry_limit() {$/,/^}$/p; /^adguardhome_owns_dns() {$/,/^}$/p; /^kill_dns_port_owners() {$/,/^}$/p; /^dns_port_available() {$/,/^}$/p; /^stop_dns_port_guard() {$/,/^}$/p; /^wait_for_adguardhome_dns() {$/,/^}$/p; /^guard_dns_port_for_adguardhome() {$/,/^}$/p; /^post_start_adguardhome() {$/,/^}$/p; /^post_start_failure_adguardhome() {$/,/^}$/p; /^pre_start_adguardhome() {$/,/^}$/p' \
	"${S99_PATH}" >"${S99_FUNCTIONS}" || fail "could not read ${S99_PATH}"
sed -n '/^dns_handoff_is_active() {$/,/^}$/p' "${MANAGER_PATH}" >>"${S99_FUNCTIONS}" ||
	fail "could not read ${MANAGER_PATH}"
sed -n '/^stop_launched_process() {$/,/^}$/p; /^start() {$/,/^}$/p' "${RC_PATH}" >"${RC_FUNCTION}" ||
	fail "could not read ${RC_PATH}"
[ -s "${S99_FUNCTIONS}" ] || fail 'DNS handoff functions were not found'
[ -s "${RC_FUNCTION}" ] || fail 'service start function was not found'
grep -q 'DNS_HANDOFF_FILE="/tmp/AdGuardHome.dns-handoff"' "${S99_PATH}" ||
	fail 'service script does not use the shared dnsmasq handoff marker'
grep -q 'dns_handoff_is_active || return 0' "${MANAGER_PATH}" ||
	fail 'dnsmasq postconf cannot run before AdGuardHome starts'

# shellcheck disable=SC1090
. "${S99_FUNCTIONS}"
# shellcheck disable=SC1090
. "${RC_FUNCTION}"

PROCS='AdGuardHome'
DNS_HANDOFF_FILE="${TEST_ROOT}/dns-handoff"
logger() {
	printf '%s\n' "logger $*" >>"${CALLS_FILE}"
}
rm() {
	if [ "${RM_HANDOFF_FAIL:-0}" -eq 1 ] && [ "${1:-}" = '-f' ] && [ "${2:-}" = "${DNS_HANDOFF_FILE}" ]; then
		return 1
	fi
	command rm "$@"
}
which() {
	case "$1" in
		awk | kill | logger | netstat | pidof | rm | service | sleep)
			return 0
			;;
	esac
	return 1
}
pidof() {
	case "$1" in
		AdGuardHome)
			[ "${DNS_STATE:-free}" = owned ] && printf '%s\n' 321
			;;
	esac
	return 0
}
netstat() {
	[ "${NETSTAT_FAIL:-0}" -eq 0 ] || return 1
	case "${DNS_STATE:-free}" in
		busy)
			printf '%s\n' 'tcp 0 0 0.0.0.0:53 0.0.0.0:* LISTEN 123/dnsmasq'
			;;
		busy_alt)
			printf '%s\n' 'udp 0 0 0.0.0.0:53 0.0.0.0:* 0 0 234/custom-dns'
			;;
		owned)
			printf '%s\n' \
				'tcp 0 0 0.0.0.0:53 0.0.0.0:* LISTEN 321/AdGuardHome' \
				'udp 0 0 0.0.0.0:53 0.0.0.0:* 321/AdGuardHome'
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
		[ "${KILL_RELEASES_PORT:-0}" -eq 1 ] && DNS_STATE=free
		return 0
	fi
	command kill "$@"
}
sleep() {
	[ "${SLEEP_SETS_OWNED:-0}" -eq 1 ] && DNS_STATE=owned
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
NETSTAT_FAIL=0

: >"${CALLS_FILE}"
DNS_STATE=busy
DNSMASQ_RESTART_RELEASES_PORT=1
enable_dns_handoff || fail 'could not enable the dnsmasq postconf handoff'
[ -f "${DNS_HANDOFF_FILE}" ] || fail 'dnsmasq handoff marker was not created'
[ "${DNS_STATE}" = free ] || fail 'dnsmasq was not regenerated onto its alternate port'
grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'dnsmasq was not restarted to apply postconf'
disable_dns_handoff
[ ! -e "${DNS_HANDOFF_FILE}" ] || fail 'dnsmasq handoff marker was not removed'
DNSMASQ_RESTART_RELEASES_PORT=0

: >"${CALLS_FILE}"
printf '%s\n' "$$" >"${DNS_HANDOFF_FILE}" || fail 'could not create handoff marker for removal failure test'
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
printf '%s\n' "$$" >"${DNS_HANDOFF_FILE}" || fail 'could not create handoff marker for post-start cleanup test'
RM_HANDOFF_FAIL=1
ADGUARDHOME_SKIP_DNSMASQ_RESTART=1
if post_start_adguardhome; then
	fail 'post-start succeeded while the dnsmasq handoff marker remained active'
fi
RM_HANDOFF_FAIL=0
unset ADGUARDHOME_SKIP_DNSMASQ_RESTART
disable_dns_handoff || fail 'could not clean up marker after post-start cleanup test'

: >"${CALLS_FILE}"
printf '%s\n' "$$" >"${DNS_HANDOFF_FILE}" || fail 'could not create handoff marker for failed-start recovery test'
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
HANDOFF_START_TIME="$(dns_handoff_process_start_time "$$")" ||
	fail 'could not read the test process start time'
printf '%s %s\n' "$$" "${HANDOFF_START_TIME}" >"${DNS_HANDOFF_FILE}" ||
	fail 'could not create competing active handoff marker'
: >"${CALLS_FILE}"
if enable_dns_handoff; then
	fail 'handoff setup replaced a marker owned by a live startup'
fi
[ "$(cat "${DNS_HANDOFF_FILE}")" = "$$ ${HANDOFF_START_TIME}" ] ||
	fail 'competing startup changed the active handoff marker'
! grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" ||
	fail 'competing startup regenerated dnsmasq after losing marker ownership'
disable_dns_handoff || fail 'could not remove competing active handoff marker'

printf '%s %s\n' "$$" "${HANDOFF_START_TIME}" >"${DNS_HANDOFF_FILE}" ||
	fail 'could not create active handoff marker'
dns_handoff_is_active || fail 'dnsmasq postconf rejected a live handoff owner'
printf '%s %s\n' "$$" "$((HANDOFF_START_TIME + 1))" >"${DNS_HANDOFF_FILE}" ||
	fail 'could not create reused-PID handoff marker'
if dns_handoff_is_active; then
	fail 'dnsmasq postconf accepted a live PID with a different process lifetime'
fi
printf '%s %s\n' "$$" "${HANDOFF_START_TIME}" >"${DNS_HANDOFF_FILE}" ||
	fail 'could not restore active handoff marker'
disable_dns_handoff || fail 'could not remove active handoff marker'

: >"${CALLS_FILE}"
printf '%s\n' 4242 >"${DNS_HANDOFF_FILE}" || fail 'could not create foreign handoff marker'
if disable_dns_handoff; then
	fail 'handoff cleanup removed a marker owned by another process'
fi
[ -f "${DNS_HANDOFF_FILE}" ] || fail 'foreign handoff marker was removed'
printf '%s\n' "$$" >"${DNS_HANDOFF_FILE}" || fail 'could not reclaim foreign handoff marker'
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
DNS_STATE=busy_alt
kill_dns_port_owners || fail 'DNS owner parser rejected an alternate BusyBox netstat layout'
grep -q '^kill -s 9 234$' "${CALLS_FILE}" || fail 'DNS owner parser depended on a fixed netstat PID column'

: >"${CALLS_FILE}"
DNS_STATE=free
kill_dns_port_owners || fail 'DNS owner cleanup failed when no process owned port 53'
! grep -q '^kill ' "${CALLS_FILE}" || fail 'DNS owner cleanup signaled a process for an empty port'

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
stop_dns_port_guard
disable_dns_handoff || fail 'could not clean up successful pre-start handoff'

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
KILL_RELEASES_PORT=0
SLEEP_SETS_OWNED=1
ADGUARDHOME_DNS_GUARD_RETRIES=3
guard_dns_port_for_adguardhome &
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
ADGUARDHOME_DNS_WAIT_RETRIES=2
unset ADGUARDHOME_SKIP_DNSMASQ_RESTART
if post_start_adguardhome; then
	fail 'post-start succeeded before AdGuardHome owned port 53'
fi
! grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'post-start restarted dnsmasq before AdGuardHome owned DNS'

: >"${CALLS_FILE}"
DNS_STATE=owned
ADGUARDHOME_SKIP_DNSMASQ_RESTART=1
post_start_adguardhome || fail 'post-start rejected valid AdGuardHome DNS ownership'
! grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'post-start ignored the dnsmasq restart suppression flag'

: >"${CALLS_FILE}"
unset ADGUARDHOME_SKIP_DNSMASQ_RESTART
post_start_adguardhome || fail 'post-start rejected valid AdGuardHome DNS ownership'
grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'post-start did not restart dnsmasq after DNS ownership was established'

: >"${CALLS_FILE}"
SERVICE_RESTART_FAIL=1
if post_start_adguardhome; then
	fail 'post-start ignored a failed dnsmasq restart'
fi
grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'post-start did not attempt the failed dnsmasq restart'
SERVICE_RESTART_FAIL=0

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
post_hook() {
	return 0
}
post_failure_hook() {
	post_start_failure_adguardhome
}

# Interrupting startup after the pre-start hook has spawned the DNS guard must
# reap that child and run the same dnsmasq recovery used by other failed starts.
INTERRUPT_READY_FILE="${TEST_ROOT}/interrupt-ready"
INTERRUPT_GUARD_PID_FILE="${TEST_ROOT}/interrupt-guard-pid"
: >"${CALLS_FILE}"
rm -f "${INTERRUPT_READY_FILE}" "${INTERRUPT_GUARD_PID_FILE}"
(
	pre_hook() {
		command sh -c 'trap "exit 0" HUP INT TERM; while :; do sleep 1; done' &
		ADGUARDHOME_DNS_GUARD_PID="$!"
		printf '%s\n' "${ADGUARDHOME_DNS_GUARD_PID}" >"${INTERRUPT_GUARD_PID_FILE}"
	}
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

: >"${CALLS_FILE}"
rm -f "${STARTED_FILE}"
if start >/dev/null; then
	fail 'rc.func ignored a failed pre-start hook'
fi
[ ! -f "${STARTED_FILE}" ] || fail 'rc.func launched AdGuardHome after pre-start failure'

pre_hook() {
	return 0
}
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
