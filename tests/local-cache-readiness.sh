#!/bin/sh
# Optional resolver switching must follow complete DNS readiness and recover.
set -eu
ROOT="$(mktemp -d)"
trap 'rm -rf "${ROOT}"' EXIT HUP INT TERM
mkdir -p "${ROOT}/etc"
: >"${ROOT}/etc/dnsmasq.conf"
: >"${ROOT}/etc/dnsmasq-1.conf"
: >"${ROOT}/etc/dnsmasq-2.conf"
sed -n '/^adguard_local_cache_ready() {$/,/^}$/p; /^adguard_local_cache_sync() {$/,/^}$/p; /^dnsmasq_resolv_conf_cleanup() {$/,/^}$/p; /^dnsmasq_resolv_conf_cleanup_locked() {$/,/^}$/p; /^adguard_local_cache_sync_locked() {$/,/^}$/p' AdGuardHome.sh |
	sed 's|/etc/dnsmasq|${ROOT}/etc/dnsmasq|g' >"${ROOT}/functions"
. "${ROOT}/functions"
CALLS="${ROOT}/calls"
: >"${CALLS}"
CONFIG_LOCAL=YES
# Cross-process locking and persisted preference are covered by serialization test.
adguard_local_cache_lock() { "$@"; }
# load_operation_config preserves the in-memory preference selected by the readiness case.
load_operation_config() { :; }
# adguard_local_cache_service_active reports a manager operation only when SERVICE_ACTIVE is set.
adguard_local_cache_service_active() { [ "${SERVICE_ACTIVE:-0}" = 1 ]; }
PROCS=AdGuardHome
# pidof reports the simulated daemon as running unless PROCESS_READY is cleared.
pidof() { [ "${PROCESS_READY:-1}" = 1 ]; }
MOUNTED=0
HANDOFF=1
DNS_READY=0
LOOKUP_READY=0
SDN_READY=0
NATIVE_ROM=0
MANAGED=1
# agh_log appends service diagnostics to the fixture call log.
agh_log() { printf '%s\n' "$*" >>"${CALLS}"; }
# dns_handoff_is_active returns success while the simulated handoff is active.
dns_handoff_is_active() { [ "${HANDOFF}" = 1 ]; }
# adguardhome_dns_bind_scope selects global DNS binding for the readiness fixture.
adguardhome_dns_bind_scope() { printf '%s\n' global; }
# adguardhome_owns_dns reports listener ownership according to DNS_READY.
adguardhome_owns_dns() { [ "${DNS_READY}" = 1 ]; }
# nslookup records a loopback lookup and succeeds only when LOOKUP_READY is set.
nslookup() {
	printf '%s\n' lookup >>"${CALLS}"
	# BusyBox 1.25 uses libc: bare localhost can succeed only from /etc/hosts.
	case "${1:-}" in
		localhost) return 0 ;;
		localhost.) [ "${2:-}" = 127.0.0.1 ] && [ "${LOOKUP_READY}" = 1 ] ;;
		*) return 1 ;;
	esac
}
# agh_dnsmasq_managed reports managed dnsmasq integration according to MANAGED.
agh_dnsmasq_managed() { [ "${MANAGED}" = 1 ]; }
# nvram advertises SDN capability for the synthetic configurations.
nvram() { printf '%s\n' mtlancfg; }
# sdn_bridge_for_index prints the enabled bridge name for fixture index $1.
sdn_bridge_for_index() { printf 'br%s\n' "$1"; }
# dnsmasq_instances_ready checks the requested port and expected configs, then returns the simulated SDN readiness.
dnsmasq_instances_ready() {
	[ "$1" = 553 ]
	if [ "${MANAGED}" = 1 ]; then
		[ "${ADGUARDHOME_DNSMASQ_CONFIGS}" = "${ROOT}/etc/dnsmasq.conf ${ROOT}/etc/dnsmasq-1.conf ${ROOT}/etc/dnsmasq-2.conf" ]
	fi
	[ "${SDN_READY}" = 1 ]
}
# resolv_conf_uses_rom reports whether native resolver routing already uses the ROM file.
resolv_conf_uses_rom() { [ "${NATIVE_ROM}" = 1 ]; }
# resolv_conf_is_tmp_mount reports the simulated resolver bind state.
resolv_conf_is_tmp_mount() { [ "${MOUNTED}" = 1 ]; }
# mount records a resolver bind, optionally failing or starting a handoff during the switch.
mount() {
	printf '%s\n' "mount $*" >>"${CALLS}"
	[ "${MOUNT_FAIL:-0}" = 0 ] || return 1
	MOUNTED=1
	[ "${RESTART_DURING_SWITCH:-0}" = 0 ] || HANDOFF=1
	return 0
}
# umount records resolver cleanup and clears MOUNTED unless failure is requested.
umount() {
	printf '%s\n' "umount $*" >>"${CALLS}"
	[ "${UNMOUNT_FAIL:-0}" = 0 ] || return 1
	MOUNTED=0
}
# Each missing prerequisite preserves native routing.
if adguard_local_cache_sync; then exit 1; fi
HANDOFF=0
if adguard_local_cache_sync; then exit 1; fi
DNS_READY=1
SDN_READY=1
if adguard_local_cache_sync; then exit 1; fi
SDN_READY=0
LOOKUP_READY=1
if adguard_local_cache_sync; then exit 1; fi
! grep -q '^mount ' "${CALLS}"
SDN_READY=1
SERVICE_ACTIVE=1
if adguard_local_cache_sync; then exit 1; fi
[ "${MOUNTED}" = 0 ]
SERVICE_ACTIVE=0
adguard_local_cache_sync
[ "${MOUNTED}" = 1 ]
adguard_local_cache_sync
[ "$(grep -c '^mount ' "${CALLS}")" -eq 1 ]
SERVICE_ACTIVE=1
if adguard_local_cache_sync; then exit 1; fi
[ "${MOUNTED}" = 0 ]
SERVICE_ACTIVE=0
adguard_local_cache_sync
# An active cache avoids repeated full probes, but periodic verification recovers.
before="$(grep -c '^lookup$' "${CALLS}")"
LOOKUP_READY=0
adguard_local_cache_sync
[ "${MOUNTED}" = 1 ]
[ "$(grep -c '^lookup$' "${CALLS}")" -eq "${before}" ]
if adguard_local_cache_sync verify; then exit 1; fi
[ "${MOUNTED}" = 0 ]
LOOKUP_READY=1
adguard_local_cache_sync
PROCESS_READY=0
if adguard_local_cache_sync; then exit 1; fi
[ "${MOUNTED}" = 0 ]
PROCESS_READY=1
# Loss of readiness, disablement, failed switching and concurrent restart.
DNS_READY=0
if adguard_local_cache_sync; then exit 1; fi
[ "${MOUNTED}" = 0 ]
DNS_READY=1
MOUNT_FAIL=1
if adguard_local_cache_sync; then exit 1; fi
[ "${MOUNTED}" = 0 ]
MOUNT_FAIL=0
RESTART_DURING_SWITCH=1
if adguard_local_cache_sync; then exit 1; fi
[ "${MOUNTED}" = 0 ]
HANDOFF=0
RESTART_DURING_SWITCH=0
adguard_local_cache_sync
CONFIG_LOCAL=NO
adguard_local_cache_sync
[ "${MOUNTED}" = 0 ]
CONFIG_LOCAL=YES
NATIVE_ROM=1
before="$(wc -l <"${CALLS}")"
adguard_local_cache_sync
[ "$(wc -l <"${CALLS}")" -eq "${before}" ]
NATIVE_ROM=0
adguard_local_cache_sync
CONFIG_LOCAL=NO
UNMOUNT_FAIL=1
if adguard_local_cache_sync; then exit 1; fi
[ "${MOUNTED}" = 1 ]
# Configuration hooks may restore native routing, but never bind the resolver.
if sed -n '/^dnsmasq_params() {$/,/^}$/p' AdGuardHome.sh | grep -q 'mount -o bind'; then exit 1; fi
printf '%s\n' 'PASS: readiness-gated Local Cache, idempotence, restart race and recovery'
