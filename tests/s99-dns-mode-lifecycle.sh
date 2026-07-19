#!/bin/sh
# Verify S99AdGuardHome DNS handoff lifecycle honors WAN/LAN dnsmasq mode.

set -u

S99_PATH="${1:-S99AdGuardHome}"
TEST_ROOT="${TMPDIR:-/tmp}/s99-dns-mode-lifecycle.$$"
FUNCTIONS_FILE="${TEST_ROOT}/s99-functions"
CALLS_FILE="${TEST_ROOT}/calls"

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
	'/^agh_conf_value() {$/,/^}$/p; /^agh_install_mode() {$/,/^}$/p; /^agh_lan_mode() {$/,/^}$/p; /^agh_dnsmasq_running() {$/,/^}$/p; /^agh_dnsmasq_managed() {$/,/^}$/p; /^agh_dns_handoff_required() {$/,/^}$/p; /^pre_start_adguardhome() {$/,/^}$/p; /^post_start_adguardhome() {$/,/^}$/p; /^post_start_failure_adguardhome() {$/,/^}$/p' \
	"${S99_PATH}" >"${FUNCTIONS_FILE}" || fail "could not read ${S99_PATH}"
[ -s "${FUNCTIONS_FILE}" ] || fail 'S99 DNS lifecycle functions were not found'
grep -q '^pre_start_adguardhome() {$' "${FUNCTIONS_FILE}" || fail 'pre-start helper was not found'
grep -q '^post_start_adguardhome() {$' "${FUNCTIONS_FILE}" || fail 'post-start helper was not found'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

PROCS='AdGuardHome'
WORK_DIR="${TEST_ROOT}/AdGuardHome"
DNS_HANDOFF_FILE="${TEST_ROOT}/handoff"
mkdir -p "${WORK_DIR}" || fail 'could not create AdGuardHome work directory'

agh_log() {
	printf '%s\n' "log $*" >>"${CALLS_FILE}"
}

ensure_adguardhome_work_dir_permissions() {
	printf '%s\n' ensure_permissions >>"${CALLS_FILE}"
	return 0
}

adguardhome_config_valid() {
	printf '%s\n' config_valid >>"${CALLS_FILE}"
	return 0
}

dns_handoff_dependencies_available() {
	printf '%s\n' handoff_dependencies >>"${CALLS_FILE}"
	return 0
}

enable_dns_handoff() {
	printf '%s\n' enable_dns_handoff >>"${CALLS_FILE}"
	: >"${DNS_HANDOFF_FILE}"
	return 0
}

disable_dns_handoff() {
	printf '%s\n' disable_dns_handoff >>"${CALLS_FILE}"
	rm -f "${DNS_HANDOFF_FILE}"
	return 0
}

prepare_dns_handoff_marker() {
	printf '%s\n' prepare_dns_handoff_marker >>"${CALLS_FILE}"
	: >"${DNS_HANDOFF_FILE}"
	return 0
}

remove_inactive_dns_handoff_marker() {
	printf '%s\n' remove_inactive_marker >>"${CALLS_FILE}"
	rm -f "${DNS_HANDOFF_FILE}"
	return 0
}

dns_handoff_marker_is_active() {
	[ -f "${DNS_HANDOFF_FILE}" ]
}

adguardhome_dns_bind_scope() {
	printf '%s\n' "${DNS_BIND_SCOPE:-global}"
}

dns_retry_limit() {
	case "${1:-}" in
		"" | *[!0-9]*) printf '%s\n' "${2:-10}" ;;
		*) printf '%s\n' "$1" ;;
	esac
}

dns_port_available() {
	printf '%s\n' "dns_port_available ${1:-global}" >>"${CALLS_FILE}"
	[ "${DNS_PORT_AVAILABLE:-1}" -eq 1 ]
}

dns_port_needs_release() {
	printf '%s\n' "dns_port_needs_release ${1:-global}" >>"${CALLS_FILE}"
	return 1
}

start_dns_port_guard() {
	printf '%s\n' start_dns_port_guard >>"${CALLS_FILE}"
	return 0
}

stop_dns_port_guard() {
	printf '%s\n' stop_dns_port_guard >>"${CALLS_FILE}"
	return 0
}

save_dns_watchdog_traps() {
	printf '%s\n' "save_traps ${1:-}" >>"${CALLS_FILE}"
	DNS_WATCHDOG_TRAP_FILE="${TEST_ROOT}/traps"
	return 0
}

restore_dns_watchdog_traps() {
	printf '%s\n' "restore_traps ${1:-}" >>"${CALLS_FILE}"
	return 0
}

resume_dns_watchdog() {
	printf '%s\n' resume_watchdog >>"${CALLS_FILE}"
	return 0
}

suspend_dns_watchdog() {
	printf '%s\n' suspend_watchdog >>"${CALLS_FILE}"
	return 0
}

wait_for_adguardhome_dns() {
	printf '%s\n' wait_dns >>"${CALLS_FILE}"
	case "${DNS_BIND_SCOPE:-global}" in
		192.168.50.1) [ "${AGH_BINDS_LAN_IP:-0}" -eq 1 ] ;;
		*) return 0 ;;
	esac
}

wait_for_adguardhome_startup_checks() {
	printf '%s\n' wait_startup >>"${CALLS_FILE}"
	return 0
}

log_adguardhome_start_failure() {
	printf '%s\n' log_start_failure >>"${CALLS_FILE}"
}

service() {
	printf '%s\n' "service $*" >>"${CALLS_FILE}"
	return 0
}

pidof() {
	case "${1:-}" in
		dnsmasq) [ "${DNSMASQ_RUNNING:-0}" -eq 1 ] && printf '%s\n' 88 ;;
		*) return 1 ;;
	esac
}

which() {
	return 0
}

scribe() {
	printf '%s\n' "scribe $*" >>"${CALLS_FILE}"
}

assert_count() {
	pattern="$1"
	expected="$2"
	message="$3"
	actual="$(grep -c "${pattern}" "${CALLS_FILE}" 2>/dev/null)"
	[ "${actual}" -eq "${expected}" ] || fail "${message}: found ${actual}, expected ${expected}"
}

run_case() {
	case_name="$1"
	mode="$2"
	dnsmasq_running="$3"
	bind_scope="$4"
	agh_binds_lan_ip="$5"
	expect_handoff="$6"
	expect_restart="$7"
	dnsmasq_mode="${8:-auto}"
	printf '%s\n' "ADGUARD_INSTALL_MODE=\"${mode}\"" "ADGUARD_DNSMASQ_MODE=\"${dnsmasq_mode}\"" >"${WORK_DIR}/.config" || fail "${case_name}: could not write config"
	: >"${CALLS_FILE}"
	DNSMASQ_RUNNING="${dnsmasq_running}"
	DNS_BIND_SCOPE="${bind_scope}"
	AGH_BINDS_LAN_IP="${agh_binds_lan_ip}"
	DNS_PORT_AVAILABLE=1
	unset ADGUARDHOME_DNS_HANDOFF_ACTIVE ADGUARDHOME_DNS_HANDOFF_REQUIRED ADGUARDHOME_SKIP_DNSMASQ_RESTART ADGUARDHOME_DNS_GUARD_PID ADGUARDHOME_DNS_BIND_SCOPE
	pre_start_adguardhome || fail "${case_name}: pre-start failed"
	post_start_adguardhome || fail "${case_name}: post-start failed"
	assert_count '^enable_dns_handoff$' "${expect_handoff}" "${case_name}: dnsmasq handoff call count mismatch"
	assert_count '^service restart_dnsmasq$' "${expect_restart}" "${case_name}: dnsmasq restart count mismatch"
	grep -q "^dns_port_available ${bind_scope}$" "${CALLS_FILE}" || fail "${case_name}: did not check configured DNS bind scope"
	grep -q '^wait_dns$' "${CALLS_FILE}" || fail "${case_name}: post-start did not wait for AdGuardHome DNS bind"
	grep -q '^wait_startup$' "${CALLS_FILE}" || fail "${case_name}: post-start did not run startup readiness"
}

run_case 'WAN mode' wan 0 global 0 1 1
run_case 'LAN mode with dnsmasq running' lan 1 192.168.50.1 1 1 1
run_case 'LAN mode without dnsmasq' lan 0 192.168.50.1 1 0 0
run_case 'LAN mode with dnsmasq disabled but running' lan 1 192.168.50.1 1 0 0 disabled

printf '%s\n' 'PASS: S99 DNS handoff lifecycle honors WAN/LAN dnsmasq mode'
