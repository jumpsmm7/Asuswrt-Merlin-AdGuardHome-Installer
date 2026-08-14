#!/bin/sh
# Verify installer-owned proc settings are applied and restored conservatively.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
TMP_ROOT="${TMPDIR:-/tmp}/agh-proc-settings.$$"
FUNCTION_FILE="${TMP_ROOT}/functions"
LOG_FILE="${TMP_ROOT}/log"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	rm -rf "${TMP_ROOT}"
	exit 1
}

mkdir -p "${TMP_ROOT}/proc/net/core" "${TMP_ROOT}/proc/net/netfilter" "${TMP_ROOT}/proc/net/ipv4/neigh/default" "${TMP_ROOT}/proc/net/ipv6/icmp" "${TMP_ROOT}/proc/net/ipv6/neigh/default" "${TMP_ROOT}/proc/kernel" "${TMP_ROOT}/proc/vm" "${TMP_ROOT}/state" || fail 'setup failed'
sed -n '/^proc_config() {$/,/^}$/p; /^proc_optimizations() {$/,/^}$/p; /^proc_swap_active() {$/,/^}$/p; /^proc_target() {$/,/^}$/p; /^proc_restore_ipv6() {$/,/^}$/p; /^proc_write() {$/,/^}$/p; /^proc_restore_one() {$/,/^}$/p; /^proc_restore() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" || fail 'function extraction failed'
# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

PROC_SYS_ROOT="${TMP_ROOT}/proc"
PROC_SWAPS_FILE="${TMP_ROOT}/swaps"
PROC_STATE_DIR="${TMP_ROOT}/state"
DEFAULT_ADGUARD_PROC_OPTIMIZE=NO
DEFAULT_ADGUARD_PROC_PROFILE=aggressive
CONFIG_PROC_OPTIMIZE=YES
CONFIG_PROC_PROFILE=balanced
agh_log() { printf '%s\n' "$*" >>"${LOG_FILE}"; }
nvram() { [ "${1:-}" = get ] && printf '%s\n' native; }

# Targets are allowlisted and requested values must be inside their numeric range.
proc_write '../kernel/pid_max' 4194304 1 4194304 && fail 'unsafe target was accepted'
proc_write rmem_max 1 262144 16777216 && fail 'out-of-range value was accepted'

# Missing entry and read failure must not create ownership state.
proc_write rmem_max 4194304 262144 16777216 && fail 'missing entry succeeded'
[ ! -e "${PROC_STATE_DIR}/rmem_max" ] || fail 'missing entry created state'
mkdir "${PROC_SYS_ROOT}/net/core/rmem_max" || fail 'read-failure setup failed'
proc_write rmem_max 4194304 262144 16777216 && fail 'read failure succeeded'
rmdir "${PROC_SYS_ROOT}/net/core/rmem_max"

# A failed state/write transaction must leave the kernel value and state alone.
printf '%s\n' 524288 >"${PROC_SYS_ROOT}/net/core/rmem_max"
PROC_STATE_DIR="${TMP_ROOT}/not-a-directory"
printf '%s' occupied >"${PROC_STATE_DIR}"
proc_write rmem_max 4194304 262144 16777216 && fail 'write transaction failure succeeded'
[ "$(cat "${PROC_SYS_ROOT}/net/core/rmem_max")" = 524288 ] || fail 'failed write changed value'
rm -f "${PROC_STATE_DIR}"
PROC_STATE_DIR="${TMP_ROOT}/state"

# Apply once; an interrupted second application and monitor checks do not rewrite.
proc_write rmem_max 4194304 262144 16777216 || fail 'application failed'
[ "$(cat "${PROC_STATE_DIR}/rmem_max")" = '524288 4194304' ] || fail 'prior value not preserved'
first_logs="$(wc -l <"${LOG_FILE}")"
proc_write rmem_max 4194304 262144 16777216 || fail 'repeat check failed'
[ "$(wc -l <"${LOG_FILE}")" -eq "${first_logs}" ] || fail 'repeat check logged or wrote'

# A value already set by someone else is neither rewritten nor claimed.
printf '%s\n' 1048576 >"${PROC_SYS_ROOT}/net/core/wmem_max"
proc_write wmem_max 1048576 262144 16777216 || fail 'matching-value check failed'
[ ! -e "${PROC_STATE_DIR}/wmem_max" ] || fail 'matching value was incorrectly claimed'
[ "$(wc -l <"${LOG_FILE}")" -eq "${first_logs}" ] || fail 'matching value was logged as a change'

# Never undo or overwrite a later administrator change.
printf '%s\n' 8388608 >"${PROC_SYS_ROOT}/net/core/rmem_max"
proc_write rmem_max 4194304 262144 16777216 || fail 'administrator-change check failed'
[ "$(cat "${PROC_SYS_ROOT}/net/core/rmem_max")" = 8388608 ] || fail 'administrator value overwritten'
[ ! -e "${PROC_STATE_DIR}/rmem_max" ] || fail 'stale ownership retained'

# Aggressive memory protection is applied, while unrelated legacy tuning stays removed.
printf '%s\n' 524288 >"${PROC_SYS_ROOT}/net/core/rmem_max"
printf '%s\n' 524288 >"${PROC_SYS_ROOT}/net/core/wmem_max"
printf '%s\n' 120 >"${PROC_SYS_ROOT}/net/netfilter/nf_conntrack_tcp_timeout_max_retrans"
printf '%s\n' 0 >"${PROC_SYS_ROOT}/vm/overcommit_memory"
printf '%s\n' 20 >"${PROC_SYS_ROOT}/vm/swappiness"
printf '%s\n' 75 >"${PROC_SYS_ROOT}/vm/overcommit_ratio"
printf '%s\n' 32768 >"${PROC_SYS_ROOT}/kernel/pid_max"
printf '%s\n' 1000 >"${PROC_SYS_ROOT}/net/ipv4/icmp_ratelimit"
printf '%s\n' 128 >"${PROC_SYS_ROOT}/net/ipv4/neigh/default/gc_thresh1"
printf '%s\n' 512 >"${PROC_SYS_ROOT}/net/ipv4/neigh/default/gc_thresh2"
printf '%s\n' 1024 >"${PROC_SYS_ROOT}/net/ipv4/neigh/default/gc_thresh3"
printf '%s\n' 1000 >"${PROC_SYS_ROOT}/net/ipv6/icmp/ratelimit"
printf '%s\n' 128 >"${PROC_SYS_ROOT}/net/ipv6/neigh/default/gc_thresh1"
printf '%s\n' 512 >"${PROC_SYS_ROOT}/net/ipv6/neigh/default/gc_thresh2"
printf '%s\n' 1024 >"${PROC_SYS_ROOT}/net/ipv6/neigh/default/gc_thresh3"
printf '%s\n' 'Filename Type Size Used Priority' '/tmp/swap file 1024 0 -2' >"${PROC_SWAPS_FILE}"
CONFIG_PROC_PROFILE=aggressive
proc_optimizations || fail 'profile application failed'
[ "$(cat "${PROC_SYS_ROOT}/net/netfilter/nf_conntrack_tcp_timeout_max_retrans")" = 240 ] || fail 'conntrack memory protection not applied'
[ "$(cat "${PROC_SYS_ROOT}/vm/overcommit_memory")" = 2 ] || fail 'strict memory commitment not applied'
[ "$(cat "${PROC_SYS_ROOT}/vm/swappiness")" = 60 ] || fail 'swap reclaim setting not applied'
[ "$(cat "${PROC_SYS_ROOT}/vm/overcommit_ratio")" = 50 ] || fail 'memory reserve ratio not applied'
[ "$(cat "${PROC_SYS_ROOT}/kernel/pid_max")" = 4194304 ] || fail 'PID collision protection not applied'
[ "$(cat "${PROC_SYS_ROOT}/net/ipv4/icmp_ratelimit")" = 0 ] || fail 'IPv4 ICMP tuning not applied'
[ "$(cat "${PROC_SYS_ROOT}/net/ipv4/neigh/default/gc_thresh3")" = 2048 ] || fail 'IPv4 neighbour tuning not applied'
[ "$(cat "${PROC_SYS_ROOT}/net/ipv6/icmp/ratelimit")" = 0 ] || fail 'IPv6 ICMP tuning not applied'
[ "$(cat "${PROC_SYS_ROOT}/net/ipv6/neigh/default/gc_thresh3")" = 2048 ] || fail 'IPv6 neighbour tuning not applied'

# Swap-specific settings are restored when swap disappears, even in aggressive mode.
printf '%s\n' 'Filename Type Size Used Priority' >"${PROC_SWAPS_FILE}"
proc_optimizations || fail 'no-swap aggressive refresh failed'
[ "$(cat "${PROC_SYS_ROOT}/vm/overcommit_memory")" = 0 ] || fail 'overcommit mode remained without swap'
[ "$(cat "${PROC_SYS_ROOT}/vm/swappiness")" = 20 ] || fail 'swappiness remained without swap'
[ "$(cat "${PROC_SYS_ROOT}/vm/overcommit_ratio")" = 75 ] || fail 'overcommit ratio remained without swap'

# Switching to balanced restores aggressive-only values without disturbing shared settings.
CONFIG_PROC_PROFILE=balanced
proc_optimizations || fail 'balanced profile switch failed'
[ "$(cat "${PROC_SYS_ROOT}/vm/overcommit_memory")" = 0 ] || fail 'balanced switch did not restore overcommit mode'
[ "$(cat "${PROC_SYS_ROOT}/vm/swappiness")" = 20 ] || fail 'balanced switch did not restore swappiness'
[ "$(cat "${PROC_SYS_ROOT}/vm/overcommit_ratio")" = 75 ] || fail 'balanced switch did not restore overcommit ratio'
[ "$(cat "${PROC_SYS_ROOT}/net/netfilter/nf_conntrack_tcp_timeout_max_retrans")" = 240 ] || fail 'balanced switch dropped conntrack protection'
[ "$(cat "${PROC_SYS_ROOT}/kernel/pid_max")" = 4194304 ] || fail 'balanced switch dropped PID protection'

# Profile switch to off restores every value still owned by the installer.
CONFIG_PROC_PROFILE=off
proc_optimizations || fail 'profile switch failed'
[ "$(cat "${PROC_SYS_ROOT}/net/core/rmem_max")" = 524288 ] || fail 'profile switch did not restore rmem'
[ "$(cat "${PROC_SYS_ROOT}/net/core/wmem_max")" = 524288 ] || fail 'profile switch did not restore wmem'
[ "$(cat "${PROC_SYS_ROOT}/net/netfilter/nf_conntrack_tcp_timeout_max_retrans")" = 120 ] || fail 'profile switch did not restore conntrack timeout'
[ "$(cat "${PROC_SYS_ROOT}/kernel/pid_max")" = 32768 ] || fail 'profile switch did not restore pid_max'
[ "$(cat "${PROC_SYS_ROOT}/net/ipv4/icmp_ratelimit")" = 1000 ] || fail 'profile switch did not restore IPv4 ICMP limit'
[ "$(cat "${PROC_SYS_ROOT}/net/ipv6/icmp/ratelimit")" = 1000 ] || fail 'profile switch did not restore IPv6 ICMP limit'

# Simulate an interrupted application after rollback publication, then restore.
printf '%s\n' 524288 >"${PROC_SYS_ROOT}/net/core/rmem_max"
mkdir -p "${PROC_STATE_DIR}"
printf '%s\n' '524288 4194304' >"${PROC_STATE_DIR}/rmem_max"
printf '%s\n' 4194304 >"${PROC_SYS_ROOT}/net/core/rmem_max"
proc_restore
[ "$(cat "${PROC_SYS_ROOT}/net/core/rmem_max")" = 524288 ] || fail 'interrupted application was not restored'

# Uninstall must request restoration before deleting the installation tree.
sed -n '/^uninst_all() {$/,/^}/p' installer | grep -q 'AdGuardHome.sh.*proc-restore' || fail 'uninstall does not request proc restoration'

rm -rf "${TMP_ROOT}"
printf '%s\n' 'PASS: proc settings are validated, owned, and restored conservatively'
