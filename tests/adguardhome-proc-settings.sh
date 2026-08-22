#!/bin/sh
# Verify installer-owned proc settings are applied and restored conservatively.

set -u

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
SCRIPT_PATH="${1:-AdGuardHome.sh}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/agh-proc-settings.XXXXXX")" || {
	printf '%s\n' 'FAIL: could not create exclusive test directory' >&2
	exit 1
}
FUNCTION_FILE="${TMP_ROOT}/functions"
LOG_FILE="${TMP_ROOT}/log"
BACKGROUND_PID=""

# cleanup stops the background process, waits for it to exit, and removes the temporary test directory.
cleanup() {
	if [ -n "${BACKGROUND_PID:-}" ] && kill -0 "${BACKGROUND_PID}" 2>/dev/null; then
		kill "${BACKGROUND_PID}" 2>/dev/null || true
		wait "${BACKGROUND_PID}" 2>/dev/null || true
	fi
	rm -rf "${TMP_ROOT}"
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

# fail reports a failure message to standard error and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

mkdir -p "${TMP_ROOT}/proc/net/core" "${TMP_ROOT}/proc/net/netfilter" "${TMP_ROOT}/proc/net/ipv4/neigh/default" "${TMP_ROOT}/proc/net/ipv6/icmp" "${TMP_ROOT}/proc/net/ipv6/neigh/default" "${TMP_ROOT}/proc/kernel" "${TMP_ROOT}/proc/vm" "${TMP_ROOT}/state" || fail 'setup failed'
sed -n '/^proc_config() {$/,/^}$/p; /^proc_optimizations_locked() {$/,/^}$/p; /^proc_optimizations() {$/,/^}$/p; /^proc_swap_active() {$/,/^}$/p; /^proc_target() {$/,/^}$/p; /^proc_boot_id() {$/,/^}$/p; /^proc_process_start_time() {$/,/^}$/p; /^proc_lock_claim_matches() {$/,/^}$/p; /^proc_lock_claim_acquire() {$/,/^}$/p; /^proc_lock_claim_release() {$/,/^}$/p; /^proc_lock_mkdir_cleanup() {$/,/^}$/p; /^proc_lock_run() {$/,/^}$/p; /^proc_restore_ipv6() {$/,/^}$/p; /^proc_write() {$/,/^}$/p; /^proc_restore_one() {$/,/^}$/p; /^proc_restore_locked() {$/,/^}$/p; /^proc_restore() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" || fail 'function extraction failed'
# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

PROC_SYS_ROOT="${TMP_ROOT}/proc"
PROC_SWAPS_FILE="${TMP_ROOT}/swaps"
PROC_BOOT_ID_FILE="${TMP_ROOT}/boot_id"
PROC_STATE_DIR="${TMP_ROOT}/state"
PROC_LOCK_DIR="${TMP_ROOT}/proc-lock"
PROC_LOCK_FILE="${TMP_ROOT}/proc.lock"
PROC_LOCK_FORCE_MKDIR=1
WORK_DIR="${TMP_ROOT}"
DEFAULT_ADGUARD_PROC_OPTIMIZE=NO
DEFAULT_ADGUARD_PROC_PROFILE=aggressive
CONFIG_PROC_OPTIMIZE=YES
CONFIG_PROC_PROFILE=balanced
# agh_log appends the provided message to the configured log file.
agh_log() { printf '%s\n' "$*" >>"${LOG_FILE}"; }
IPV6_SERVICE=native
# nvram returns the configured IPv6 service when invoked with `get`.
nvram() { [ "${1:-}" = get ] && printf '%s\n' "${IPV6_SERVICE}"; }
RM_FAIL_STATE=0
RM_FAIL_STATE_HIT=0
PAUSE_LOCK_PUBLICATION=0
PAUSE_LOCK_ENTERED="${TMP_ROOT}/lock-publication-entered"
PAUSE_LOCK_RELEASE="${TMP_ROOT}/lock-publication-release"
# mkdir can pause the first fallback-lock owner after directory creation to exercise owner publication races.
mkdir() {
	command mkdir "$@" || return $?
	if [ "${PAUSE_LOCK_PUBLICATION}" = 1 ] && [ "$1" = "${PROC_LOCK_DIR}" ] && [ ! -e "${PAUSE_LOCK_ENTERED}" ]; then
		: >"${PAUSE_LOCK_ENTERED}"
		while [ ! -e "${PAUSE_LOCK_RELEASE}" ]; do
			command sleep 1
		done
	fi
}
# rm simulates a failure when removing the configured `rmem_max` state file, otherwise delegates to the system `rm` command.
rm() {
	if [ "${RM_FAIL_STATE}" = 1 ]; then
		case "$*" in
			*"${PROC_STATE_DIR}/rmem_max"*)
				RM_FAIL_STATE_HIT=1
				return 1
				;;
		esac
	fi
	command rm "$@"
}
printf '%s\n' boot-one >"${PROC_BOOT_ID_FILE}"

# Targets are allowlisted and requested values must be inside their numeric range.
proc_write '../kernel/pid_max' 4194304 1 4194304 && fail 'unsafe target was accepted'
proc_write tcp_rmem 4096 1 16777216 && fail 'non-allowlisted target was accepted'
proc_write rmem_max not-a-number 262144 16777216 && fail 'non-numeric value was accepted'
proc_write rmem_max 1 262144 16777216 && fail 'out-of-range value was accepted'
proc_write rmem_max 999999999 262144 16777216 && fail 'oversized value was accepted'

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
[ "$(cat "${PROC_STATE_DIR}/rmem_max")" = '524288 4194304 boot-one' ] || fail 'prior value or boot ownership not preserved'
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

# Disabling IPv6 restores every IPv6 target and releases its ownership state.
IPV6_SERVICE=
proc_optimizations || fail 'IPv6-disabled aggressive refresh failed'
[ "$(cat "${PROC_SYS_ROOT}/net/ipv6/icmp/ratelimit")" = 1000 ] || fail 'IPv6 ICMP limit was not restored when IPv6 was disabled'
[ "$(cat "${PROC_SYS_ROOT}/net/ipv6/neigh/default/gc_thresh1")" = 128 ] || fail 'IPv6 threshold 1 was not restored when IPv6 was disabled'
[ "$(cat "${PROC_SYS_ROOT}/net/ipv6/neigh/default/gc_thresh2")" = 512 ] || fail 'IPv6 threshold 2 was not restored when IPv6 was disabled'
[ "$(cat "${PROC_SYS_ROOT}/net/ipv6/neigh/default/gc_thresh3")" = 1024 ] || fail 'IPv6 threshold 3 was not restored when IPv6 was disabled'
for ipv6_state in ipv6_icmp_ratelimit ipv6_neigh_gc_thresh1 ipv6_neigh_gc_thresh2 ipv6_neigh_gc_thresh3; do
	[ ! -e "${PROC_STATE_DIR}/${ipv6_state}" ] || fail "IPv6 ownership remained for ${ipv6_state}"
done

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
printf '%s\n' '524288 4194304 boot-one' >"${PROC_STATE_DIR}/rmem_max"
proc_write rmem_max 4194304 262144 16777216 || fail 'same-boot pending application was not retried'
[ "$(cat "${PROC_SYS_ROOT}/net/core/rmem_max")" = 4194304 ] || fail 'same-boot pending application remained unapplied'
[ -f "${PROC_STATE_DIR}/rmem_max" ] || fail 'same-boot retry lost ownership state'
printf '%s\n' 4194304 >"${PROC_SYS_ROOT}/net/core/rmem_max"
proc_restore
[ "$(cat "${PROC_SYS_ROOT}/net/core/rmem_max")" = 524288 ] || fail 'interrupted application was not restored'

# An unavailable boot ID falls back to current-value ownership during restore.
mkdir -p "${PROC_STATE_DIR}"
printf '%s\n' '524288 4194304 boot-one' >"${PROC_STATE_DIR}/rmem_max"
printf '%s\n' 4194304 >"${PROC_SYS_ROOT}/net/core/rmem_max"
rm -f "${PROC_BOOT_ID_FILE}"
proc_restore_one rmem_max || fail 'restore failed when boot ID was unavailable'
[ "$(cat "${PROC_SYS_ROOT}/net/core/rmem_max")" = 524288 ] || fail 'unavailable boot ID prevented owned restoration'
[ ! -e "${PROC_STATE_DIR}/rmem_max" ] || fail 'unavailable boot ID left restored ownership state'
printf '%s\n' boot-one >"${PROC_BOOT_ID_FILE}"

# A failed procfs read retains ownership state for a later restoration attempt.
rm -f "${PROC_SYS_ROOT}/net/core/rmem_max"
mkdir "${PROC_SYS_ROOT}/net/core/rmem_max"
printf '%s\n' '524288 4194304 boot-one' >"${PROC_STATE_DIR}/rmem_max"
proc_restore_one rmem_max && fail 'restore succeeded after procfs read failure'
[ -f "${PROC_STATE_DIR}/rmem_max" ] || fail 'procfs read failure discarded ownership state'
rmdir "${PROC_SYS_ROOT}/net/core/rmem_max"
printf '%s\n' 524288 >"${PROC_SYS_ROOT}/net/core/rmem_max"

# A stale record from an earlier boot is replaced and tuning is reapplied.
printf '%s\n' 524288 >"${PROC_SYS_ROOT}/net/core/rmem_max"
mkdir -p "${PROC_STATE_DIR}"
printf '%s\n' '262144 4194304 boot-one' >"${PROC_STATE_DIR}/rmem_max"
printf '%s\n' boot-two >"${PROC_BOOT_ID_FILE}"
proc_write rmem_max 4194304 262144 16777216 || fail 'post-reboot reapplication failed'
[ "$(cat "${PROC_SYS_ROOT}/net/core/rmem_max")" = 4194304 ] || fail 'post-reboot value was not reapplied'
[ "$(cat "${PROC_STATE_DIR}/rmem_max")" = '524288 4194304 boot-two' ] || fail 'post-reboot prior value was not refreshed'

# A stale state file that cannot be removed must prevent reapplication.
printf '%s\n' 524288 >"${PROC_SYS_ROOT}/net/core/rmem_max"
printf '%s\n' '262144 4194304 boot-one' >"${PROC_STATE_DIR}/rmem_max"
RM_FAIL_STATE=1
RM_FAIL_STATE_HIT=0
proc_write rmem_max 4194304 262144 16777216 && fail 'stale-state removal failure was ignored'
[ "${RM_FAIL_STATE_HIT}" = 1 ] || fail 'stale-state removal failure path was not exercised'
[ "$(cat "${PROC_SYS_ROOT}/net/core/rmem_max")" = 524288 ] || fail 'value changed after stale-state removal failure'
[ -f "${PROC_STATE_DIR}/rmem_max" ] || fail 'failed stale-state removal lost ownership record'
RM_FAIL_STATE=0

# Uninstall must restore before removing the installation tree and retain it on failure.
UNINSTALL_FUNCTION_FILE="${TMP_ROOT}/uninstall-function"
sed -n '/^uninst_all() {$/,/^}$/p' "${ROOT_DIR}/installer" >"${UNINSTALL_FUNCTION_FILE}" || fail 'uninstall function extraction failed'
# shellcheck disable=SC1090
. "${UNINSTALL_FUNCTION_FILE}"
# run_uninstall_test creates an isolated uninstall scenario, invokes uninst_all, and records restoration, restart, and removal events. Restore and start results control simulated outcomes; helper mode controls rollback-helper usability.
run_uninstall_test() (
	TARG_DIR="${TMP_ROOT}/uninstall-$1"
	BASE_DIR="${TMP_ROOT}/base-$1"
	HOME="${TMP_ROOT}/home-$1"
	ADDON_DIR="${TMP_ROOT}/addon-$1"
	ROLLBACK_RESULT_FILE="${TMP_ROOT}/rollback-$1"
	EVENTS_FILE="${TMP_ROOT}/events-$1"
	RESTORE_RESULT="$2"
	START_RESULT="${3:-0}"
	HELPER_MODE="${4:-usable}"
	mkdir -p "${TARG_DIR}" "${BASE_DIR}" "${HOME}"
	printf '%s\n' installer >"${TARG_DIR}/installer"
	cat >"${TARG_DIR}/AdGuardHome.sh" <<'EOF'
#!/bin/sh
[ -d "${TARG_DIR}" ] || exit 9
printf '%s\n' restore >>"${EVENTS_FILE}"
exit "${RESTORE_RESULT}"
EOF
	chmod 755 "${TARG_DIR}/AdGuardHome.sh"
	if [ "${HELPER_MODE}" = unusable ]; then
		chmod 644 "${TARG_DIR}/AdGuardHome.sh"
		mkdir "${TARG_DIR}/proc-sys-state"
	fi
	export TARG_DIR EVENTS_FILE RESTORE_RESULT
	INFO=INFO ERROR=ERROR CONFIRM_STATUS=0
	PTXT() { printf '%s\n' "$*" >>"${EVENTS_FILE}"; }
	conf_value() { printf '%s\n' no; }
	agh_stop() { printf '%s\n' stop >>"${EVENTS_FILE}"; }
	agh_start() {
		printf '%s\n' start >>"${EVENTS_FILE}"
		return "${START_RESULT:-0}"
	}
	cleanup_legacy_firewall() { :; }
	yaml_nvars_delete() { :; }
	del_jffs_script() { :; }
	del_between_magic() { :; }
	nvram() { :; }
	service() { :; }
	end_op_message() { :; }
	mv() { :; }
	rm() {
		case " $* " in *" ${TARG_DIR} "*) printf '%s\n' remove >>"${EVENTS_FILE}" ;; esac
		command rm "$@"
	}
	uninst_all
)
run_uninstall_test success 0 || fail 'successful uninstall failed'
[ "$(sed -n '1p' "${TMP_ROOT}/events-success")" = stop ] || fail 'successful uninstall did not stop service first'
[ "$(sed -n '2p' "${TMP_ROOT}/events-success")" = restore ] || fail 'uninstall did not restore after stopping'
[ "$(sed -n '3p' "${TMP_ROOT}/events-success")" = remove ] || fail 'uninstall did not remove after restore'
[ ! -e "${TMP_ROOT}/uninstall-success" ] || fail 'successful uninstall retained installation path'
run_uninstall_test failure 1 && fail 'failed restoration did not abort uninstall'
[ -d "${TMP_ROOT}/uninstall-failure" ] || fail 'failed restoration removed installation path'
[ "$(sed -n '1p' "${TMP_ROOT}/events-failure")" = stop ] || fail 'failed uninstall did not stop service first'
[ "$(sed -n '2p' "${TMP_ROOT}/events-failure")" = restore ] || fail 'failed uninstall did not attempt restoration'
[ "$(sed -n '3p' "${TMP_ROOT}/events-failure")" = 'ERROR Unable to restore installer-managed kernel settings.' ] || fail 'failed restoration error was not reported'
[ "$(sed -n '4p' "${TMP_ROOT}/events-failure")" = start ] || fail 'failed restoration did not restart retained installation'
run_uninstall_test restart-failure 1 1 && fail 'restore and restart failures did not abort uninstall'
[ -d "${TMP_ROOT}/uninstall-restart-failure" ] || fail 'restart failure removed retained installation path'
[ "$(sed -n '3p' "${TMP_ROOT}/events-restart-failure")" = 'ERROR Unable to restore installer-managed kernel settings.' ] || fail 'restart failure obscured restoration error'
[ "$(sed -n '4p' "${TMP_ROOT}/events-restart-failure")" = start ] || fail 'restart failure was not exercised'
run_uninstall_test unusable-helper 0 0 unusable && fail 'unusable rollback helper did not abort uninstall'
[ -d "${TMP_ROOT}/uninstall-unusable-helper" ] || fail 'unusable rollback helper removed retained installation path'
[ "$(sed -n '2p' "${TMP_ROOT}/events-unusable-helper")" = 'ERROR Unable to restore installer-managed kernel settings.' ] || fail 'unusable rollback helper error was not reported'
[ "$(sed -n '3p' "${TMP_ROOT}/events-unusable-helper")" = start ] || fail 'unusable rollback helper did not restart retained installation'

# The mkdir fallback serializes complete proc transactions.
LOCK_EVENTS="${TMP_ROOT}/lock-events"
mkdir "${PROC_LOCK_DIR}" || fail 'could not create unpublished lock cleanup fixture'
proc_lock_mkdir_cleanup && fail 'unpublished lock cleanup unexpectedly reported valid ownership'
[ ! -d "${PROC_LOCK_DIR}" ] || fail 'unpublished lock cleanup left the lock directory behind'
_trap_line=$(sed -n '/^proc_lock_run() {$/,/^}$/p' "${SCRIPT_PATH}" | grep -n "trap 'proc_lock_mkdir_cleanup" | head -n 1 | cut -d: -f1)
_publish_line=$(sed -n '/^proc_lock_run() {$/,/^}$/p' "${SCRIPT_PATH}" | grep -n 'printf.*PROC_LOCK_DIR}/pid' | head -n 1 | cut -d: -f1)
[ -n "${_trap_line}" ] && [ -n "${_publish_line}" ] && [ "${_trap_line}" -lt "${_publish_line}" ] || fail 'proc lock cleanup trap is not armed before owner publication'
# lock_holder records lock acquisition events around a one-second delay.
lock_holder() {
	printf '%s\n' first-start >>"${LOCK_EVENTS}"
	command sleep 1
	printf '%s\n' first-end >>"${LOCK_EVENTS}"
}
# lock_waiter records the waiter's execution in the lock event log.
lock_waiter() { printf '%s\n' second >>"${LOCK_EVENTS}"; }
PAUSE_LOCK_PUBLICATION=1
export PAUSE_LOCK_PUBLICATION PAUSE_LOCK_ENTERED PAUSE_LOCK_RELEASE
proc_lock_run lock_holder &
lock_pid="$!"
BACKGROUND_PID="${lock_pid}"
publication_waits=0
while [ ! -e "${PAUSE_LOCK_ENTERED}" ] && [ "${publication_waits}" -lt 5 ]; do
	command sleep 1
	publication_waits="$((publication_waits + 1))"
done
[ -e "${PAUSE_LOCK_ENTERED}" ] || fail 'fallback lock owner did not pause before publication'
proc_lock_run lock_waiter &
waiter_pid="$!"
command sleep 1
kill -0 "${lock_pid}" 2>/dev/null || fail 'paused fallback lock owner was reaped before publication'
kill -0 "${waiter_pid}" 2>/dev/null || fail 'fallback lock contender exited while owner publication was paused'
: >"${PAUSE_LOCK_RELEASE}"
wait "${lock_pid}" || fail 'paused fallback lock owner failed after publication resumed'
BACKGROUND_PID=""
wait "${waiter_pid}" || fail 'fallback lock contender failed after owner publication'
[ "$(cat "${LOCK_EVENTS}")" = "$(printf '%s\n' first-start first-end second)" ] || fail 'fallback lock contender overlapped paused owner publication'
PAUSE_LOCK_PUBLICATION=0
rm -f "${LOCK_EVENTS}" "${PAUSE_LOCK_ENTERED}" "${PAUSE_LOCK_RELEASE}"
mkdir "${PROC_LOCK_DIR}" || fail 'could not create stale identity lock fixture'
printf '%s %s\n' "$$" 0 >"${PROC_LOCK_DIR}/pid" || fail 'could not publish stale identity lock fixture'
proc_lock_run lock_waiter || fail 'reused-PID lock identity was not reclaimed'
[ "$(cat "${LOCK_EVENTS}")" = second ] || fail 'reused-PID lock reclaim did not run the waiter'
rm -f "${LOCK_EVENTS}"
proc_lock_run lock_holder &
lock_pid="$!"
BACKGROUND_PID="${lock_pid}"
lock_waits=0
max_lock_waits=10
while [ "${lock_waits}" -lt "${max_lock_waits}" ]; do
	if [ -f "${LOCK_EVENTS}" ] && [ "$(sed -n '1p' "${LOCK_EVENTS}" 2>/dev/null)" = first-start ]; then
		break
	fi
	command sleep 1
	lock_waits=$((lock_waits + 1))
done
[ "$(sed -n '1p' "${LOCK_EVENTS}" 2>/dev/null)" = first-start ] || fail "lock holder did not start within ${max_lock_waits} seconds"
proc_lock_run lock_waiter || fail 'serialized waiter failed'
wait "${lock_pid}" || fail 'serialized holder failed'
BACKGROUND_PID=""
if kill -0 "${lock_pid}" 2>/dev/null; then
	fail 'serialized holder remained after wait'
fi
[ "${lock_waits}" -le "${max_lock_waits}" ] || fail "lock publication wait exceeded ${max_lock_waits} seconds"
[ "$(sed -n '1p' "${LOCK_EVENTS}")" = first-start ] || fail 'lock holder did not start first'
[ "$(sed -n '2p' "${LOCK_EVENTS}")" = first-end ] || fail 'lock waiter overlapped holder'
[ "$(sed -n '3p' "${LOCK_EVENTS}")" = second ] || fail 'lock waiter did not run after holder'

# Cleanup failure must not replace a guarded command's existing nonzero status.
(
	PROC_LOCK_DIR="${TMP_ROOT}/status-lock"
	# proc_lock_mkdir_cleanup simulates a cleanup failure after the guarded command completes.
	proc_lock_mkdir_cleanup() { return 1; }
	# guarded_failure returns a distinctive command failure status.
	guarded_failure() { return 7; }
	proc_lock_run guarded_failure
	[ "$?" -eq 7 ]
) || fail 'proc lock cleanup failure replaced the guarded command status'
(
	PROC_LOCK_DIR="${TMP_ROOT}/cleanup-status-lock"
	# proc_lock_mkdir_cleanup simulates a cleanup failure after a successful guarded command.
	proc_lock_mkdir_cleanup() { return 1; }
	proc_lock_run true
	[ "$?" -eq 1 ]
) || fail 'proc lock cleanup failure was ignored after a successful guarded command'

# Exercise and observe an EXIT cleanup trap independently before this test's
# own cleanup removes the workspace.
trap_marker="${TMP_ROOT}/cleanup-trap-ran"
(
	trap 'printf "%s\n" ran >"${trap_marker}"' 0
	:
) || fail 'cleanup trap probe failed'
[ -f "${trap_marker}" ] || fail 'cleanup trap did not run'

printf '%s\n' 'PASS: proc settings are validated, owned, and restored conservatively'
