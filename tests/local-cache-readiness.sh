#!/bin/sh
# Optional resolver switching must follow complete DNS readiness and recover.
set -eu
ROOT="$(mktemp -d)"
trap 'rm -rf "${ROOT}"' EXIT HUP INT TERM
mkdir -p "${ROOT}/etc"
: >"${ROOT}/etc/dnsmasq.conf"
: >"${ROOT}/etc/dnsmasq-1.conf"
: >"${ROOT}/etc/dnsmasq-2.conf"
sed -n '/^adguard_local_cache_ready() {$/,/^}$/p; /^adguard_local_cache_sync() {$/,/^}$/p; /^dnsmasq_resolv_conf_cleanup() {$/,/^}$/p' AdGuardHome.sh |
	sed 's|/etc/dnsmasq|${ROOT}/etc/dnsmasq|g' >"${ROOT}/functions"
. "${ROOT}/functions"
CALLS="${ROOT}/calls"
: >"${CALLS}"
CONFIG_LOCAL=YES
MOUNTED=0
HANDOFF=1
DNS_READY=0
LOOKUP_READY=0
SDN_READY=0
NATIVE_ROM=0
MANAGED=1
agh_log() { printf '%s\n' "$*" >>"${CALLS}"; }
dns_handoff_is_active() { [ "${HANDOFF}" = 1 ]; }
adguardhome_dns_bind_scope() { printf '%s\n' global; }
adguardhome_owns_dns() { [ "${DNS_READY}" = 1 ]; }
nslookup() { [ "${LOOKUP_READY}" = 1 ]; }
agh_dnsmasq_managed() { [ "${MANAGED}" = 1 ]; }
nvram() { printf '%s\n' mtlancfg; }
sdn_bridge_for_index() { printf 'br%s\n' "$1"; }
dnsmasq_instances_ready() {
	[ "$1" = 553 ]
	if [ "${MANAGED}" = 1 ]; then
		[ "${ADGUARDHOME_DNSMASQ_CONFIGS}" = "${ROOT}/etc/dnsmasq.conf ${ROOT}/etc/dnsmasq-1.conf ${ROOT}/etc/dnsmasq-2.conf" ]
	fi
	[ "${SDN_READY}" = 1 ]
}
resolv_conf_uses_rom() { [ "${NATIVE_ROM}" = 1 ]; }
resolv_conf_is_tmp_mount() { [ "${MOUNTED}" = 1 ]; }
mount() {
	printf '%s\n' "mount $*" >>"${CALLS}"
	[ "${MOUNT_FAIL:-0}" = 0 ] || return 1
	MOUNTED=1
	[ "${RESTART_DURING_SWITCH:-0}" = 0 ] || HANDOFF=1
	return 0
}
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
if adguard_local_cache_sync; then exit 1; fi
LOOKUP_READY=1
if adguard_local_cache_sync; then exit 1; fi
! grep -q '^mount ' "${CALLS}"
SDN_READY=1
adguard_local_cache_sync
[ "${MOUNTED}" = 1 ]
adguard_local_cache_sync
[ "$(grep -c '^mount ' "${CALLS}")" -eq 1 ]
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
