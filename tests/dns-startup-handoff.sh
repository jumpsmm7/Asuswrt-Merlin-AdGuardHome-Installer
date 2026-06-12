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
	'/^adguardhome_owns_dns() {$/,/^}$/p; /^kill_dns_port_owners() {$/,/^}$/p; /^dns_port_available() {$/,/^}$/p; /^wait_for_adguardhome_dns() {$/,/^}$/p; /^guard_dns_port_for_adguardhome() {$/,/^}$/p; /^post_start_adguardhome() {$/,/^}$/p; /^pre_start_adguardhome() {$/,/^}$/p' \
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
}
kill() {
	printf '%s\n' "kill $*" >>"${CALLS_FILE}"
	[ "${KILL_RELEASES_PORT:-0}" -eq 1 ] && DNS_STATE=free
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

: >"${CALLS_FILE}"
DNS_STATE=busy
KILL_RELEASES_PORT=0
SLEEP_SETS_OWNED=1
ADGUARDHOME_DNS_GUARD_RETRIES=3
guard_dns_port_for_adguardhome || fail 'bounded guard did not survive dnsmasq reclaiming port 53'
grep -q '^service stop_dnsmasq$' "${CALLS_FILE}" || fail 'bounded guard did not stop a respawned dnsmasq'
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
	rm -f "${STARTED_FILE}"
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

printf '%s\n' 'DNS startup handoff tests passed.'
