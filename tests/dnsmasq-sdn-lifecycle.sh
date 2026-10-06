#!/bin/sh
# Exercise multi-instance release, PID reuse protection, and restoration gates.
set -eu
ROOT="$(mktemp -d)"
trap 'rm -rf "${ROOT}"' EXIT HUP INT TERM
mkdir "${ROOT}/etc"
: >"${ROOT}/etc/dnsmasq-1.conf"
: >"${ROOT}/etc/dnsmasq-2.conf"
: >"${ROOT}/etc/dnsmasq-3.conf"
sed -n '/^agh_install_mode() {$/,/^}$/p; /^agh_lan_mode() {$/,/^}$/p; /^agh_dnsmasq_running() {$/,/^}$/p; /^agh_dnsmasq_managed() {$/,/^}$/p; /^agh_dns_handoff_required() {$/,/^}$/p; /^dns_port_owner_actions() {$/,/^}$/p; /^dns_port_unknown_refusal_enabled() {$/,/^}$/p; /^kill_dns_port_owners() {$/,/^}$/p; /^release_dns_port_from_dnsmasq() {$/,/^}$/p; /^dns_port_available() {$/,/^}$/p; /^dns_socket_snapshot_value() {$/,/^}$/p; /^dns_retry_limit() {$/,/^}$/p; /^dnsmasq_instances_ready() {$/,/^}$/p; /^wait_for_dnsmasq_instances() {$/,/^}$/p; /^post_start_adguardhome() {$/,/^}$/p; /^post_start_failure_adguardhome() {$/,/^}$/p; /^pre_start_adguardhome() {$/,/^}$/p' S99AdGuardHome >"${ROOT}/functions"
# Isolate only the firmware config-directory traversal; retain canonical paths.
sed -n '/^dnsmasq_handoff_configs() {$/,/^}$/p' S99AdGuardHome |
	sed -e 's|for config in /etc/dnsmasq-|for config in "${ROOT}"/etc/dnsmasq-|' \
		-e '/\[ -f "${config}" \] || continue/a\
						config="${config#${ROOT}}"' >>"${ROOT}/functions"
. "${ROOT}/functions"
# Optional resolver switching is covered by local-cache-readiness.sh.
adguard_local_cache_sync() { :; }
dnsmasq_resolv_conf_cleanup() { :; }

PROCS=AdGuardHome
WORK_DIR="${ROOT}"
DNS_HANDOFF_FILE="${ROOT}/handoff"
CALLS="${ROOT}/calls"
LIVE="${ROOT}/live"
: >"${CALLS}"
printf '%s\n' 11 12 13 >"${LIVE}"
ADGUARDHOME_DNSMASQ_CONFIGS='/etc/dnsmasq.conf /etc/dnsmasq-1.conf /etc/dnsmasq-2.conf'
ADGUARDHOME_DNSMASQ_READY_RETRIES=2
PORT=53
agh_log() { :; }
dns_port_owner_command() { printf '%s\n' dnsmasq; }
dns_port_owner_process_name() { printf '%s\n' dnsmasq; }
dnsmasq_process_config() {
	grep -qx "$1" "${LIVE}" || return 1
	case "$1" in
		11) printf '%s\n' /etc/dnsmasq.conf ;;
		12) printf '%s\n' /etc/dnsmasq-1.conf ;;
		13) printf '%s\n' /etc/dnsmasq-2.conf ;;
		*) return 1 ;;
	esac
}
dnsmasq_process_start_time() {
	if [ "${REUSE:-0}" = 1 ] && [ -f "${ROOT}/classified" ]; then printf '%s\n' 999; else printf '%s\n' 123; fi
}
dnsmasq_managed_instances() {
	# Persistent DHCP script helpers share daemon identity but own no sockets.
	[ "${HELPERS_FIRST:-0}" = 0 ] || printf '%s\n' '21 123 /etc/dnsmasq.conf' '22 123 /etc/dnsmasq-1.conf' '23 123 /etc/dnsmasq-2.conf'
	for pid in $(cat "${LIVE}"); do
		config="$(dnsmasq_process_config "${pid}")" || continue
		printf '%s 123 %s\n' "${pid}" "${config}"
	done
}
dns_socket_snapshot() {
	DNS_SOCKET_SNAPSHOT="$(while read -r pid; do
		[ "${pid}" != 13 ] || [ "${MISSING_SDN:-0}" != 1 ] || continue
		[ "${pid}" != 11 ] || [ "${MISSING_MAIN:-0}" != 1 ] || continue
		printf 'tcp 0 0 192.168.%s.1:%s 0.0.0.0:* LISTEN %s/dnsmasq-sdn\n' "${pid}" "${PORT}" "${pid}"
		printf 'udp 0 0 192.168.%s.1:%s 0.0.0.0:* %s/dnsmasq-sdn\n' "${pid}" "${PORT}" "${pid}"
	done <"${LIVE}")"
	DNS_SOCKET_SNAPSHOT_VALID=1
	if [ "${EXIT_BEFORE_IDENTITY:-0}" = 1 ]; then
		: >"${LIVE}"
	elif [ "${EXIT_BEFORE_IDENTITY:-0}" = partial ]; then
		printf '%s\n' 11 >"${LIVE}"
		EXIT_BEFORE_IDENTITY=0
	fi
}
service() {
	printf '%s\n' "service $*" >>"${CALLS}"
	case "$1" in
		stop_dnsmasq) [ "${STOP_FAIL:-0}" = 0 ] ;;
		restart_dnsmasq)
			[ "${RESTART_FAIL:-0}" = 0 ] || return 1
			if [ "${CREATE_SDN_CONFIGS:-0}" = 1 ]; then
				: >"${ROOT}/etc/dnsmasq-1.conf"
				: >"${ROOT}/etc/dnsmasq-2.conf"
			fi
			printf '%s\n' 11 12 >"${LIVE}"
			[ "${SDN2_ENABLED:-1}" != 1 ] || printf '%s\n' 13 >>"${LIVE}"
			;;
	esac
}
kill() {
	printf '%s\n' "kill $*" >>"${CALLS}"
	grep -vx "$3" "${LIVE}" >"${LIVE}.new" || true
	mv "${LIVE}.new" "${LIVE}"
}
sleep() { printf '%s\n' wait >>"${CALLS}"; }
# A firmware stop failure still permits verified, deduplicated survivor cleanup.
STOP_FAIL=1
release_dns_port_from_dnsmasq test global || exit 1
[ ! -s "${LIVE}" ]
[ "$(grep -c '^kill -s 9' "${CALLS}")" -eq 3 ]
# Normal exit between netstat and identity inspection must not abort startup.
printf '%s\n' 11 >"${LIVE}"
: >"${CALLS}"
EXIT_BEFORE_IDENTITY=1
kill_dns_port_owners
! grep -q '^kill ' "${CALLS}"
EXIT_BEFORE_IDENTITY=0
# Retiring one owner must not prevent cleanup of the remaining managed owner.
printf '%s\n' 11 12 >"${LIVE}"
EXIT_BEFORE_IDENTITY=partial
kill_dns_port_owners
[ ! -s "${LIVE}" ]
[ "$(grep -c '^kill -s 9' "${CALLS}")" -eq 1 ]
: >"${CALLS}"
# An owner that remains but cannot be verified is still refused.
printf '%s\n' 99 >"${LIVE}"
if kill_dns_port_owners; then exit 1; else [ "$?" -eq 2 ]; fi
! grep -q '^kill ' "${CALLS}"
# PID changes between classification and escalation never receive a signal.
printf '%s\n' 11 >"${LIVE}"
: >"${CALLS}"
dns_port_owner_command() { : >"${ROOT}/classified"; }
REUSE=1
kill_dns_port_owners
[ -s "${LIVE}" ]
! grep -q '^kill ' "${CALLS}"
REUSE=0
rm "${ROOT}/classified"
# Post-start restoration gates completion on every SDN, not just main LAN.
wait_for_adguardhome_dns() { printf '%s\n' agh-ready >>"${CALLS}"; }
wait_for_adguardhome_startup_checks() { return 0; }
stop_dns_port_guard() { :; }
resume_dns_watchdog() { :; }
disable_dns_handoff() { printf '%s\n' clear-handoff >>"${CALLS}"; }
log_adguardhome_start_failure() { :; }
ADGUARDHOME_DNS_HANDOFF_ACTIVE=1
PORT=553
HELPERS_FIRST=1
post_start_adguardhome
[ "${ADGUARDHOME_DNS_HANDOFF_ACTIVE:-0}" = 0 ]
MISSING_SDN=1
ADGUARDHOME_DNS_HANDOFF_ACTIVE=1
if post_start_adguardhome; then exit 1; fi
[ "${ADGUARDHOME_DNS_HANDOFF_ACTIVE}" = 1 ]
MISSING_SDN=0
PORT=53
post_start_failure_adguardhome
[ "${ADGUARDHOME_DNS_HANDOFF_ACTIVE:-0}" = 0 ]
RESTART_FAIL=1
ADGUARDHOME_DNS_HANDOFF_ACTIVE=1
if post_start_failure_adguardhome; then exit 1; fi
[ "${ADGUARDHOME_DNS_HANDOFF_ACTIVE}" = 1 ]
# A boot-time empty inventory must still require the managed main/enabled SDNs.
RESTART_FAIL=0
HELPERS_FIRST=0
: >"${LIVE}"
MODE=auto
INSTALL_MODE=wan
agh_conf_value() {
	case "$1" in
		ADGUARD_DNSMASQ_MODE) printf '%s\n' "${MODE}" ;;
		ADGUARD_INSTALL_MODE) printf '%s\n' "${INSTALL_MODE}" ;;
	esac
}
nvram() { printf '%s\n' mtlancfg; }
get_mtlan() {
	case "${TOPOLOGY_STATE:-valid}" in
		incomplete)
			printf '%s\n' '|-enable: [1]' '|-sdn_idx: [1]'
			return 0
			;;
		malformed)
			printf '%s\n' '|-enable: [0]' '|-sdn_idx: [3]' '|-sdn_idx: [2]'
			return 0
			;;
		conflicting) printf '%s\n' '|-enable: [1]' '|-sdn_idx: [2]' ;;
	esac
	printf '%s\n' '|-enable: [1]' '|-sdn_idx: [1]' "|-enable: [${SDN2_ENABLED:-1}]" '|-sdn_idx: [2]'
	[ "${TOPOLOGY_STATE:-valid}" != failed ]
}
sdn_bridge_for_index() {
	case "$1" in
		1) printf 'br%s\n' "$1" ;;
		2) [ "${SDN2_ENABLED:-1}" != 1 ] || printf 'br%s\n' "$1" ;;
	esac
}
ensure_adguardhome_work_dir_permissions() { :; }
adguardhome_config_valid() { :; }
adguardhome_dns_bind_scope() { printf '%s\n' global; }
dns_handoff_dependencies_available() { :; }
enable_dns_handoff() { :; }
pidof() { return 1; }
which() { return 1; }
save_dns_watchdog_traps() { :; }
restore_dns_watchdog_traps() { :; }
launch_dns_port_guard() { :; }
remove_inactive_dns_handoff_marker() { :; }
dns_handoff_marker_is_active() { return 1; }
prepare_dns_handoff_marker() { :; }
for missing in main sdn; do
	: >"${LIVE}"
	PORT=53
	pre_start_adguardhome
	[ "$(printf '%s\n' "${ADGUARDHOME_DNSMASQ_CONFIGS}" | wc -l)" -eq 3 ]
	printf '%s\n' "${ADGUARDHOME_DNSMASQ_CONFIGS}" | grep -qx /etc/dnsmasq.conf
	! printf '%s\n' "${ADGUARDHOME_DNSMASQ_CONFIGS}" | grep -qx /etc/dnsmasq-3.conf
	case "${missing}" in main) MISSING_MAIN=1 ;; sdn) MISSING_SDN=1 ;; esac
	PORT=553
	if post_start_adguardhome; then exit 1; fi
	[ "${ADGUARDHOME_DNS_HANDOFF_ACTIVE}" = 1 ]
	PORT=53
	if post_start_failure_adguardhome; then exit 1; fi
	[ "${ADGUARDHOME_DNS_HANDOFF_ACTIVE}" = 1 ]
	MISSING_MAIN=0
	MISSING_SDN=0
	post_start_failure_adguardhome
	[ "${ADGUARDHOME_DNS_HANDOFF_ACTIVE:-0}" = 0 ]
done
# Firmware may create enabled SDN configurations after the initial capture.
rm "${ROOT}/etc/dnsmasq-1.conf" "${ROOT}/etc/dnsmasq-2.conf"
: >"${LIVE}"
PORT=53
pre_start_adguardhome
[ "${ADGUARDHOME_DNSMASQ_CONFIGS}" = /etc/dnsmasq.conf ]
CREATE_SDN_CONFIGS=1
MISSING_SDN=1
PORT=553
if post_start_adguardhome; then exit 1; fi
printf '%s\n' "${ADGUARDHOME_DNSMASQ_CONFIGS}" | grep -qx /etc/dnsmasq-2.conf
[ "${ADGUARDHOME_DNS_HANDOFF_ACTIVE}" = 1 ]
# Retain that requirement even while firmware replaces its configuration.
CREATE_SDN_CONFIGS=0
rm "${ROOT}/etc/dnsmasq-2.conf"
PORT=53
if post_start_failure_adguardhome; then exit 1; fi
printf '%s\n' "${ADGUARDHOME_DNSMASQ_CONFIGS}" | grep -qx /etc/dnsmasq-2.conf
[ "${ADGUARDHOME_DNS_HANDOFF_ACTIVE}" = 1 ]
MISSING_SDN=0
post_start_failure_adguardhome
[ "${ADGUARDHOME_DNS_HANDOFF_ACTIVE:-0}" = 0 ]
# A topology update can disable an SDN between capture and service restoration.
: >"${LIVE}"
: >"${ROOT}/etc/dnsmasq-2.conf"
SDN2_ENABLED=1
PORT=53
pre_start_adguardhome
printf '%s\n' "${ADGUARDHOME_DNSMASQ_CONFIGS}" | grep -qx /etc/dnsmasq-2.conf
SDN2_ENABLED=0
PORT=553
post_start_adguardhome
! printf '%s\n' "${ADGUARDHOME_DNSMASQ_CONFIGS}" | grep -qx /etc/dnsmasq-2.conf
[ "${ADGUARDHOME_DNS_HANDOFF_ACTIVE:-0}" = 0 ]
# Failure recovery likewise restores only the networks that remain enabled.
ADGUARDHOME_DNSMASQ_CONFIGS='/etc/dnsmasq.conf /etc/dnsmasq-1.conf /etc/dnsmasq-2.conf'
ADGUARDHOME_DNS_HANDOFF_ACTIVE=1
PORT=53
post_start_failure_adguardhome
! printf '%s\n' "${ADGUARDHOME_DNSMASQ_CONFIGS}" | grep -qx /etc/dnsmasq-2.conf
[ "${ADGUARDHOME_DNS_HANDOFF_ACTIVE:-0}" = 0 ]
# Failed, incomplete or ambiguous topology must never silently drop an SDN.
for topology in failed incomplete malformed conflicting; do
	: >"${LIVE}"
	SDN2_ENABLED=1
	TOPOLOGY_STATE=valid
	PORT=53
	pre_start_adguardhome
	SDN2_ENABLED=0
	TOPOLOGY_STATE="${topology}"
	PORT=553
	if post_start_adguardhome; then exit 1; fi
	printf '%s\n' "${ADGUARDHOME_DNSMASQ_CONFIGS}" | grep -qx /etc/dnsmasq-2.conf
	[ "${ADGUARDHOME_DNS_HANDOFF_ACTIVE}" = 1 ]
	TOPOLOGY_STATE=valid
	PORT=53
	post_start_failure_adguardhome
	[ "${ADGUARDHOME_DNS_HANDOFF_ACTIVE:-0}" = 0 ]
done
SDN2_ENABLED=1
# Disabled integration and unmanaged LAN handoff do not invent requirements.
: >"${LIVE}"
MODE=disabled
pre_start_adguardhome
[ -z "${ADGUARDHOME_DNSMASQ_CONFIGS}" ]
PORT=553
post_start_adguardhome
MODE=auto
INSTALL_MODE=lan
: >"${LIVE}"
PORT=53
pre_start_adguardhome
[ -z "${ADGUARDHOME_DNSMASQ_CONFIGS}" ]
post_start_adguardhome
printf '%s\n' 'PASS: all-SDN cleanup, PID reuse, topology-aware readiness, and failed-restart recovery'
