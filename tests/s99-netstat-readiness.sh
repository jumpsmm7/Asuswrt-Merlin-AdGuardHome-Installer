#!/bin/sh
# Verify S99AdGuardHome netstat readiness parsing with missing owner data.

set -u

S99_PATH="${1:-S99AdGuardHome}"
TEST_ROOT="${TMPDIR:-/tmp}/s99-netstat-readiness.$$"
FUNCTIONS_FILE="${TEST_ROOT}/s99-functions"

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
	'/^adguardhome_web_port() {$/,/^}$/p; /^adguardhome_web_port_owned_status() {$/,/^}$/p; /^adguardhome_web_port_available() {$/,/^}$/p; /^dns_retry_limit() {$/,/^}$/p; /^adguardhome_single_process_running() {$/,/^}$/p; /^adguardhome_owns_dns() {$/,/^}$/p; /^adguardhome_dns_bind_scope() {$/,/^}$/p; /^dns_port_owner_command() {$/,/^}$/p; /^dns_port_owner_process_name() {$/,/^}$/p; /^dns_port_unknown_refusal_enabled() {$/,/^}$/p; /^kill_dns_port_owners() {$/,/^}$/p; /^dns_port_available() {$/,/^}$/p; /^dns_port_has_foreign_owner() {$/,/^}$/p; /^dns_port_needs_release() {$/,/^}$/p; /^log_adguardhome_dns_wait_failure() {$/,/^}$/p' \
	"${S99_PATH}" >"${FUNCTIONS_FILE}" || fail "could not read ${S99_PATH}"
[ -s "${FUNCTIONS_FILE}" ] || fail 'S99 netstat readiness functions were not found'
grep -q '^adguardhome_single_process_running() {$' "${FUNCTIONS_FILE}" || fail 'single-process fallback helper was not found'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

PROCS='AdGuardHome'
WORK_DIR="${TEST_ROOT}/AdGuardHome"
CALLS_FILE="${TEST_ROOT}/calls"
mkdir -p "${WORK_DIR}" || fail 'could not create AdGuardHome work directory'
printf '%s\n' 'http:' '  address: 0.0.0.0:3000' >"${WORK_DIR}/AdGuardHome.yaml" || fail 'could not create YAML stub'
: >"${CALLS_FILE}" || fail 'could not create calls file'

agh_lan_mode() {
	return 0
}

which() {
	command -v "$1"
}

nvram() {
	[ "${1:-}" = get ] && [ "${2:-}" = lan_ipaddr ] || return 1
	printf '%s\n' '192.168.50.1'
}

cat >"${WORK_DIR}/AdGuardHome.yaml" <<'EOF' || fail 'could not write inline bind-host YAML'
dns:
  bind_hosts: [127.0.0.1, 192.168.50.1]
http:
  address: 0.0.0.0:3000
EOF
[ "$(adguardhome_dns_bind_scope)" = '127.0.0.1 192.168.50.1' ] || fail 'inline DNS bind hosts fell back to global scope'

cat >"${WORK_DIR}/AdGuardHome.yaml" <<'EOF' || fail 'could not write block bind-host YAML'
dns:
  bind_hosts:
    - 127.0.0.1
    - 192.168.50.1
http:
  address: 0.0.0.0:3000
EOF
[ "$(adguardhome_dns_bind_scope)" = '127.0.0.1 192.168.50.1' ] || fail 'block DNS bind-host parsing regressed'

agh_log() {
	printf '%s\n' "$*" >>"${CALLS_FILE}"
}

pidof() {
	[ "${1:-}" = AdGuardHome ] || return 1
	case "${PIDOF_STATE:-one}" in
		one) printf '%s\n' 321 ;;
		two) printf '%s\n' '321 654' ;;
		missing) return 1 ;;
		*) printf '%s\n' "${PIDOF_STATE}" ;;
	esac
}

netstat() {
	case "${NETSTAT_STATE:-owned}" in
		owned)
			printf '%s\n' \
				'tcp 0 0 0.0.0.0:53 0.0.0.0:* LISTEN 123/AdGuardHome' \
				'udp 0 0 0.0.0.0:53 0.0.0.0:* 123/AdGuardHome' \
				'tcp 0 0 0.0.0.0:3000 0.0.0.0:* LISTEN 123/AdGuardHome'
			;;
		no_owner)
			printf '%s\n' \
				'tcp 0 0 0.0.0.0:53 0.0.0.0:* LISTEN' \
				'udp 0 0 0.0.0.0:53 0.0.0.0:*' \
				'tcp 0 0 0.0.0.0:3000 0.0.0.0:* LISTEN'
			;;
		foreign_dnsmasq)
			printf '%s\n' \
				'tcp 0 0 0.0.0.0:53 0.0.0.0:* LISTEN 88/dnsmasq' \
				'udp 0 0 0.0.0.0:53 0.0.0.0:* 88/dnsmasq' \
				'tcp 0 0 0.0.0.0:3000 0.0.0.0:* LISTEN'
			;;
		foreign_web)
			printf '%s\n' \
				'tcp 0 0 0.0.0.0:53 0.0.0.0:* LISTEN' \
				'udp 0 0 0.0.0.0:53 0.0.0.0:*' \
				'tcp 0 0 0.0.0.0:3000 0.0.0.0:* LISTEN 88/httpd'
			;;
		unknown_other_lan_ip)
			printf '%s\n' \
				'tcp 0 0 192.168.50.2:53 0.0.0.0:* LISTEN 77/customdns' \
				'udp 0 0 192.168.50.2:53 0.0.0.0:* 77/customdns'
			;;
		unknown_configured_lan_ip)
			printf '%s\n' \
				'tcp 0 0 192.168.50.1:53 0.0.0.0:* LISTEN 77/customdns' \
				'udp 0 0 192.168.50.1:53 0.0.0.0:* 77/customdns'
			;;
		loopback_only_dns)
			printf '%s\n' \
				'tcp 0 0 127.0.0.1:53 0.0.0.0:* LISTEN 123/AdGuardHome' \
				'udp 0 0 127.0.0.1:53 0.0.0.0:* 123/AdGuardHome'
			;;
		scoped_loopback_lan_dns)
			printf '%s\n' \
				'tcp 0 0 127.0.0.1:53 0.0.0.0:* LISTEN 123/AdGuardHome' \
				'udp 0 0 127.0.0.1:53 0.0.0.0:* 123/AdGuardHome' \
				'tcp 0 0 192.168.50.1:53 0.0.0.0:* LISTEN 123/AdGuardHome' \
				'udp 0 0 192.168.50.1:53 0.0.0.0:* 123/AdGuardHome'
			;;
		missing_udp)
			printf '%s\n' \
				'tcp 0 0 0.0.0.0:53 0.0.0.0:* LISTEN' \
				'tcp 0 0 0.0.0.0:3000 0.0.0.0:* LISTEN'
			;;
		missing_tcp)
			printf '%s\n' \
				'udp 0 0 0.0.0.0:53 0.0.0.0:*' \
				'tcp 0 0 0.0.0.0:3000 0.0.0.0:* LISTEN'
			;;
	esac
}

kill() {
	printf '%s\n' "kill $*" >>"${CALLS_FILE}"
	return 0
}

PIDOF_STATE=one
NETSTAT_STATE=owned
adguardhome_owns_dns || fail 'owner-aware DNS readiness rejected 123/AdGuardHome ownership'
adguardhome_web_port_available || fail 'owner-aware WebUI readiness rejected 123/AdGuardHome ownership'
dns_port_available || fail 'DNS port availability rejected AdGuardHome-owned port 53'
if dns_port_has_foreign_owner; then
	fail 'foreign-owner check reported AdGuardHome as foreign'
fi
if dns_port_needs_release; then
	fail 'release check reported AdGuardHome as needing release'
fi

NETSTAT_STATE=no_owner
adguardhome_owns_dns || fail 'DNS fallback rejected bound TCP/UDP port 53 without PID/program ownership'
adguardhome_web_port_available || fail 'WebUI fallback rejected bound port without PID/program ownership'
dns_port_available || fail 'DNS port availability rejected bound ownerless port 53 with one AdGuardHome process'
if dns_port_has_foreign_owner; then
	fail 'ownerless DNS port was treated as an explicit foreign owner'
fi
if dns_port_needs_release; then
	fail 'release check rejected ownerless DNS port with one AdGuardHome process'
fi

PIDOF_STATE=two
if adguardhome_owns_dns; then
	fail 'DNS fallback accepted ownerless sockets with multiple AdGuardHome processes'
fi
if adguardhome_web_port_available; then
	fail 'WebUI fallback accepted ownerless sockets with multiple AdGuardHome processes'
fi
if ! dns_port_needs_release; then
	fail 'release check missed ownerless DNS port with multiple AdGuardHome processes'
fi
PIDOF_STATE=one

NETSTAT_STATE=loopback_only_dns
if adguardhome_owns_dns '127.0.0.1 192.168.50.1'; then
	fail 'scoped LAN DNS readiness accepted loopback-only ownership'
fi

NETSTAT_STATE=scoped_loopback_lan_dns
adguardhome_owns_dns '127.0.0.1 192.168.50.1' || fail 'scoped LAN DNS readiness rejected ownership on every bind address'

NETSTAT_STATE=foreign_dnsmasq
if adguardhome_owns_dns; then
	fail 'DNS readiness accepted explicit dnsmasq ownership'
fi
if dns_port_available; then
	fail 'DNS port availability accepted explicit dnsmasq ownership'
fi
dns_port_has_foreign_owner || fail 'foreign-owner check missed explicit dnsmasq ownership'
dns_port_needs_release || fail 'release check missed explicit dnsmasq ownership'

NETSTAT_STATE=foreign_web
if adguardhome_web_port_available; then
	fail 'WebUI readiness accepted explicit foreign ownership'
fi

NETSTAT_STATE=unknown_other_lan_ip
ADGUARDHOME_FORCE_DNS_PORT_KILL=1
if ! kill_dns_port_owners 192.168.50.1; then
	fail 'scoped release rejected unrelated unknown owner on a different LAN IP'
fi
[ ! -s "${CALLS_FILE}" ] || fail 'scoped release logged or killed unrelated unknown owner on a different LAN IP'

NETSTAT_STATE=unknown_configured_lan_ip
: >"${CALLS_FILE}"
if ! kill_dns_port_owners 192.168.50.1; then
	fail 'scoped forced release rejected unknown owner on configured LAN IP'
fi
grep -q '^kill -s 9 77$' "${CALLS_FILE}" || fail 'scoped forced release did not kill unknown owner on configured LAN IP'

unset ADGUARDHOME_FORCE_DNS_PORT_KILL

NETSTAT_STATE=missing_udp
if adguardhome_owns_dns; then
	fail 'DNS readiness accepted missing UDP port 53 bind'
fi
: >"${CALLS_FILE}"
log_adguardhome_dns_wait_failure
grep -q 'UDP port 53 is not bound' "${CALLS_FILE}" || fail 'DNS wait failure did not explain missing UDP bind'

NETSTAT_STATE=missing_tcp
if adguardhome_owns_dns; then
	fail 'DNS readiness accepted missing TCP port 53 bind'
fi
: >"${CALLS_FILE}"
log_adguardhome_dns_wait_failure
grep -q 'TCP port 53 is not bound' "${CALLS_FILE}" || fail 'DNS wait failure did not explain missing TCP bind'
