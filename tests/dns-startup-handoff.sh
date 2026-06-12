#!/bin/sh
# Verify the dnsmasq-to-AdGuardHome handoff is bounded and ordered.

set -u

S99_PATH="${1:-S99AdGuardHome}"
RC_PATH="${2:-rc.func.AdGuardHome}"
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
	'/^adguardhome_owns_dns() {$/,/^}$/p; /^kill_dns_port_owners() {$/,/^}$/p; /^dns_port_available() {$/,/^}$/p; /^stop_dns_port_guard() {$/,/^}$/p; /^wait_for_adguardhome_dns() {$/,/^}$/p; /^guard_dns_port_for_adguardhome() {$/,/^}$/p; /^post_start_adguardhome() {$/,/^}$/p; /^post_start_failure_adguardhome() {$/,/^}$/p; /^pre_start_adguardhome() {$/,/^}$/p' \
	"${S99_PATH}" >"${S99_FUNCTIONS}" || fail "could not read ${S99_PATH}"
sed -n '/^start() {$/,/^}$/p' "${RC_PATH}" >"${RC_FUNCTION}" || fail "could not read ${RC_PATH}"
[ -s "${S99_FUNCTIONS}" ] || fail 'DNS handoff functions were not found'
[ -s "${RC_FUNCTION}" ] || fail 'service start function was not found'

# shellcheck disable=SC1090
. "${S99_FUNCTIONS}"
# shellcheck disable=SC1090
. "${RC_FUNCTION}"

PROCS='AdGuardHome'
logger() {
	printf '%s\n' "logger $*" >>"${CALLS_FILE}"
}
which() {
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
	case "${DNS_STATE:-free}" in
		busy)
			printf '%s\n' 'tcp 0 0 0.0.0.0:53 0.0.0.0:* LISTEN 123/dnsmasq'
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

: >"${CALLS_FILE}"
DNS_STATE=busy
KILL_RELEASES_PORT=1
ADGUARDHOME_DNSMASQ_STOP_RETRIES=3
ADGUARDHOME_DNS_GUARD_RETRIES=0
pre_start_adguardhome || fail 'pre-start did not release a killable port owner'
[ "${DNS_STATE}" = free ] || fail 'pre-start did not synchronously release port 53'
[ "$(grep -c '^service stop_dnsmasq$' "${CALLS_FILE}")" -eq 1 ] || fail 'pre-start did not stop dnsmasq exactly once'
grep -q '^kill -s 9 123$' "${CALLS_FILE}" || fail 'pre-start did not kill the remaining port owner'
stop_dns_port_guard

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
grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'pre-start timeout did not restore dnsmasq'

: >"${CALLS_FILE}"
DNS_STATE=busy
ADGUARDHOME_SKIP_DNSMASQ_RESTART=1
if pre_start_adguardhome; then
	fail 'pre-start succeeded while port 53 remained busy with restart suppression enabled'
fi
! grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'pre-start timeout ignored the dnsmasq restart suppression flag'
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

printf '%s\n' 'DNS startup handoff tests passed.'
