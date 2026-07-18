#!/bin/sh
# Verify runtime DNS environment preparation skips DNS NVRAM rewrites in LAN mode.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
TEST_ROOT="${TMPDIR:-/tmp}/adguardhome-dns-env-lan-mode.$$"
FUNCTIONS_FILE="${TEST_ROOT}/functions"
NVRAM_FILE="${TEST_ROOT}/nvram"
NVRAM_SETS_FILE="${TEST_ROOT}/nvram-sets"

cleanup() {
	rm -rf "${TEST_ROOT}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

write_conf() {
	: >"${CONF_FILE}" || fail 'could not reset config file'
	while [ "$#" -gt 0 ]; do
		printf '%s\n' "$1" >>"${CONF_FILE}" || fail 'could not write config value'
		shift
	done
}

nvram_value() {
	awk -v KEY="$1" '
		index($0, KEY "=") == 1 { print substr($0, length(KEY) + 2); found = 1 }
		END { exit(found ? 0 : 1) }
	' "${NVRAM_FILE}"
}

assert_nvram_value() {
	value="$(nvram_value "$1")" || fail "$2: missing $1"
	[ "${value}" = "$2" ] || fail "$1: expected $2, got ${value}"
}

reset_nvram() {
	cat >"${NVRAM_FILE}" <<'EOF_NVRAM' || fail 'could not write nvram state'
dnspriv_enable=1
dhcpd_dns_router=0
dhcp_dns1_x=9.9.9.9
dhcp_dns2_x=149.112.112.112
EOF_NVRAM
	: >"${NVRAM_SETS_FILE}" || fail 'could not reset nvram sets'
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
mkdir -p "${TEST_ROOT}" || fail 'could not create test directory'

sed -n \
	'/^conf_value() {$/,/^}$/p; /^adguard_install_mode() {$/,/^}$/p; /^adguard_lan_mode() {$/,/^}$/p; /^check_dns_environment() {$/,/^}$/p' \
	"${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" || fail "could not read ${SCRIPT_PATH}"
grep -q '^check_dns_environment() {$' "${FUNCTIONS_FILE}" || fail 'check_dns_environment helper missing'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

CONF_FILE="${TEST_ROOT}/AdGuardHome.config"
_DNS_NVRAM_SAVED=0
_OLD_dnspriv_enable=''
_OLD_dhcpd_dns_router=''
_OLD_dhcp_dns1_x=''
_OLD_dhcp_dns2_x=''

nvram() {
	case "$1" in
		get)
			nvram_value "$2"
			;;
		set)
			key="${2%%=*}"
			value="${2#*=}"
			awk -v KEY="${key}" -v VALUE="${value}" '
				BEGIN { done = 0 }
				index($0, KEY "=") == 1 { print KEY "=" VALUE; done = 1; next }
				{ print }
				END { if (!done) print KEY "=" VALUE }
			' "${NVRAM_FILE}" >"${NVRAM_FILE}.tmp" || return 1
			mv "${NVRAM_FILE}.tmp" "${NVRAM_FILE}" || return 1
			printf '%s\n' "$2" >>"${NVRAM_SETS_FILE}"
			;;
		commit)
			printf '%s\n' 'commit' >>"${NVRAM_SETS_FILE}"
			;;
		*) return 1 ;;
	esac
}

save_dns_nvram_environment() {
	_OLD_dnspriv_enable="$(nvram get dnspriv_enable 2>/dev/null)"
	_OLD_dhcpd_dns_router="$(nvram get dhcpd_dns_router 2>/dev/null)"
	_OLD_dhcp_dns1_x="$(nvram get dhcp_dns1_x 2>/dev/null)"
	_OLD_dhcp_dns2_x="$(nvram get dhcp_dns2_x 2>/dev/null)"
	_DNS_NVRAM_SAVED=1
}

pidof() { return 1; }
killall() { fail "unexpected killall: $*"; }
adguard_restart_dnsmasq_if_managed() {
	DNSMASQ_RESTART_COUNT="$((DNSMASQ_RESTART_COUNT + 1))"
}
service_wait() {
	SERVICE_WAIT_COUNT="$((SERVICE_WAIT_COUNT + 1))"
}
agh_log() { :; }

DNSMASQ_RESTART_COUNT=0
SERVICE_WAIT_COUNT=0
reset_nvram
write_conf 'ADGUARD_INSTALL_MODE=lan'
check_dns_environment running || fail 'LAN runtime DNS environment check failed'
[ ! -s "${NVRAM_SETS_FILE}" ] || fail 'LAN mode should not set or commit DNS NVRAM values'
[ "${DNSMASQ_RESTART_COUNT}" = '0' ] || fail 'LAN mode should not restart dnsmasq'
[ "${SERVICE_WAIT_COUNT}" = '0' ] || fail 'LAN mode should not wait on netcheck'
assert_nvram_value dnspriv_enable '1'
assert_nvram_value dhcpd_dns_router '0'
assert_nvram_value dhcp_dns1_x '9.9.9.9'
assert_nvram_value dhcp_dns2_x '149.112.112.112'

DNSMASQ_RESTART_COUNT=0
SERVICE_WAIT_COUNT=0
reset_nvram
write_conf 'ADGUARD_INSTALL_MODE=wan'
check_dns_environment running || fail 'WAN runtime DNS environment check failed'
grep -q '^dnspriv_enable=0$' "${NVRAM_SETS_FILE}" || fail 'WAN mode did not apply dnspriv profile'
grep -q '^dhcpd_dns_router=1$' "${NVRAM_SETS_FILE}" || fail 'WAN mode did not apply dhcp router profile'
grep -q '^commit$' "${NVRAM_SETS_FILE}" || fail 'WAN mode did not commit DNS NVRAM changes'
[ "${DNSMASQ_RESTART_COUNT}" = '1' ] || fail 'WAN mode should restart managed dnsmasq once'
[ "${SERVICE_WAIT_COUNT}" = '1' ] || fail 'WAN mode should wait on netcheck once'
