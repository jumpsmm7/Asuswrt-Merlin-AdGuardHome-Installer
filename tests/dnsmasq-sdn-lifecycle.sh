#!/bin/sh
# Exercise multi-instance release, PID reuse protection, and restoration gates.
set -eu
ROOT="$(mktemp -d)"
trap 'rm -rf "${ROOT}"' EXIT HUP INT TERM
sed -n '/^dns_port_owner_actions() {$/,/^}$/p; /^dns_port_unknown_refusal_enabled() {$/,/^}$/p; /^kill_dns_port_owners() {$/,/^}$/p; /^release_dns_port_from_dnsmasq() {$/,/^}$/p; /^dns_port_available() {$/,/^}$/p; /^dns_socket_snapshot_value() {$/,/^}$/p; /^dns_retry_limit() {$/,/^}$/p; /^dnsmasq_instances_ready() {$/,/^}$/p; /^wait_for_dnsmasq_instances() {$/,/^}$/p; /^post_start_adguardhome() {$/,/^}$/p; /^post_start_failure_adguardhome() {$/,/^}$/p' S99AdGuardHome >"${ROOT}/functions"
. "${ROOT}/functions"
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
 for pid in $(cat "${LIVE}"); do
  config="$(dnsmasq_process_config "${pid}")" || continue
  printf '%s 123 %s\n' "${pid}" "${config}"
 done
}
dns_socket_snapshot() {
 DNS_SOCKET_SNAPSHOT="$(while read -r pid; do
  [ "${pid}" != 13 ] || [ "${MISSING_SDN:-0}" != 1 ] || continue
  printf 'tcp 0 0 192.168.%s.1:%s 0.0.0.0:* LISTEN %s/dnsmasq-sdn\n' "${pid}" "${PORT}" "${pid}"
  printf 'udp 0 0 192.168.%s.1:%s 0.0.0.0:* %s/dnsmasq-sdn\n' "${pid}" "${PORT}" "${pid}"
 done <"${LIVE}")"
 DNS_SOCKET_SNAPSHOT_VALID=1
}
service() {
 printf '%s\n' "service $*" >>"${CALLS}"
 case "$1" in
 stop_dnsmasq) [ "${STOP_FAIL:-0}" = 0 ] ;;
 restart_dnsmasq)
  [ "${RESTART_FAIL:-0}" = 0 ] || return 1
  printf '%s\n' 11 12 13 >"${LIVE}"
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
printf '%s\n' 'PASS: all-SDN cleanup, PID reuse, readiness, and failed-restart recovery'
