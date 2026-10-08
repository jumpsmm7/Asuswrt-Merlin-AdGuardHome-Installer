#!/bin/sh
# Reproduce cross-process service contention using the production lock helpers.
set -eu
REPO_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${1:-${REPO_DIR}/AdGuardHome.sh}"
TEST_ROOT="${TMPDIR:-/tmp}/service-lock-serialization.$$"
umask 077
mkdir "${TEST_ROOT}"
CHILD=""
# fail reports a fixture failure.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}
# cleanup releases and joins the fixture worker before removing its files.
cleanup() {
	: >"${TEST_ROOT}/release"
	[ -z "${CHILD}" ] || wait "${CHILD}" 2>/dev/null || true
	rm -rf "${TEST_ROOT}"
}
trap cleanup EXIT
trap 'cleanup; exit 1' HUP INT TERM
sed -n '/^# Run-lock helpers$/,/^# check_dns_environment/p' "${SCRIPT_PATH}" |
	sed '$d; s|/tmp/AdGuardHome|${TEST_ROOT}/manager|g; s|/tmp/adguardhome-flock-test|${TEST_ROOT}/probe|g' >"${TEST_ROOT}/functions"
sed -n '/^IPSet_Current_UID() {$/,/^}$/p; /^IPSet_Directory_Metadata() {$/,/^}$/p; /^proc_process_start_time() {$/,/^}$/p; /^proc_lock_claim_matches() {$/,/^}$/p; /^proc_lock_claim_acquire() {$/,/^}$/p; /^proc_lock_claim_release() {$/,/^}$/p' "${SCRIPT_PATH}" >>"${TEST_ROOT}/functions"
cat >"${TEST_ROOT}/worker" <<'EOF_WORKER'
#!/bin/sh
set -u
TEST_ROOT="$1"
BACKEND="$2"
MODE="${4:-normal}"
# shellcheck disable=SC1090
. "${TEST_ROOT}/functions"
# agh_log suppresses worker diagnostics.
agh_log() { :; }
# have_cmd forces either absent, incapable or descriptor-capable flock.
have_cmd() { [ "${BACKEND}" != absent ] && command -v "$1" >/dev/null 2>&1; }
# flock simulates a command present without descriptor support.
flock() { [ "${BACKEND}" != incapable ] && command flock "$@"; }
# IPSet_Lock_Interrupt_Propagate has no enclosing transaction in this fixture.
IPSet_Lock_Interrupt_Propagate() { :; }
# mkdir pauses only after real ownership-controlled action publication.
mkdir() {
	command mkdir "$@" || return "$?"
	if [ "${MODE}" = kill-publish ] && [ "${3:-}" = "${TEST_ROOT}/manager-service-lock/action" ]; then
		: >"${TEST_ROOT}/transition-blocked"
		while [ ! -f "${TEST_ROOT}/transition-release" ]; do sleep 0.05; done
	fi
}
# rm pauses only after the real cleaner unlinks its immutable owner record.
rm() {
	command rm "$@" || return "$?"
	if { [ "${MODE}" = kill-cleanup ] && [ "${2:-}" = "${TEST_ROOT}/manager-service-lock/action/owner" ]; } ||
		{ [ "${MODE}" = kill-reap ] && [ "${2:-}" = "${TEST_ROOT}/manager-service-lock/action/pid" ]; }; then
		: >"${TEST_ROOT}/transition-blocked"
		while [ ! -f "${TEST_ROOT}/transition-release" ]; do sleep 0.05; done
	fi
}
# printf injects a real failed or interrupted staged owner-record write after
# the production noclobber redirection has created its private file.
printf() {
	if [ "$1" = '%s %s\n' ] && [ -f "${TEST_ROOT}/manager-service-lock/action/owner.new" ]; then
		case "${MODE}" in
			fail-owner) return 1 ;;
			kill-owner-writer)
				IFS= read -r writer_pid </proc/self/stat || return 1
				command printf '%s\n' "${writer_pid%% *}" >"${TEST_ROOT}/writer-pid"
				: >"${TEST_ROOT}/transition-blocked"
				while [ ! -f "${TEST_ROOT}/transition-release" ]; do sleep 0.05; done
				;;
		esac
	fi
	command printf "$@"
}
# service_wait holds startup until the parent releases it and records stop entry.
service_wait() {
	case "$1" in
		start_adguardhome)
			printf '%s\n' start-enter >>"${TEST_ROOT}/events"
			: >"${TEST_ROOT}/entered"
			while [ ! -f "${TEST_ROOT}/release" ]; do sleep 0.05; done
			printf '%s\n' start-exit >>"${TEST_ROOT}/events"
			;;
		stop_adguardhome) printf '%s\n' stop >>"${TEST_ROOT}/events" ;;
		adguardhome_run)
			while ! adguardhome_run ""; do sleep 0.05; done
			;;
	esac
}
case "$3" in
	cleanup) adguardhome_run_mkdir_cleanup "${TEST_ROOT}/manager-service-lock/action" "$4" "$5" ;;
	*) adguardhome_run "$3" ;;
esac
EOF_WORKER
SHELL_BIN="$(readlink "/proc/$$/exe")"
# run_worker dispatches workers under the same host or BusyBox shell as the test.
run_worker() {
	case "${SHELL_BIN##*/}" in
		busybox*) "${SHELL_BIN}" ash "${TEST_ROOT}/worker" "${TEST_ROOT}" "$@" ;;
		*) "${SHELL_BIN}" "${TEST_ROOT}/worker" "${TEST_ROOT}" "$@" ;;
	esac
}
# wait_for_file bounds the worker startup wait.
wait_for_file() {
	attempts=0
	while [ ! -f "$1" ] && [ "${attempts}" -lt 100 ]; do
		sleep 0.05
		attempts="$((attempts + 1))"
	done
	[ -f "$1" ] || fail 'service action did not enter'
}

for backend in absent incapable; do
	rm -f "${TEST_ROOT}/entered" "${TEST_ROOT}/release"
	: >"${TEST_ROOT}/events"
	run_worker "${backend}" start_adguardhome &
	CHILD="$!"
	wait_for_file "${TEST_ROOT}/entered"
	if run_worker "${backend}" stop_adguardhome; then fail "${backend} fallback stop bypassed an active startup lock"; fi
	grep -q '^stop$' "${TEST_ROOT}/events" && fail 'stop overlapped startup'
	: >"${TEST_ROOT}/release"
	wait "${CHILD}"
	CHILD=""
	run_worker "${backend}" stop_adguardhome || fail 'uncontended fallback stop failed'
	[ "$(cat "${TEST_ROOT}/events")" = "$(printf '%s\n' start-enter start-exit stop)" ] || fail 'fallback operation order changed'
done

# Completed legacy metadata and proven stale/PID-reused owners never bypass
# atomic acquisition: two contenders still admit exactly one action.
RUNTIME="${TEST_ROOT}/manager-service-lock"
for stale in dead reused; do
	rm -f "${TEST_ROOT}/entered" "${TEST_ROOT}/release"
	: >"${TEST_ROOT}/events"
	mkdir -m 700 "${RUNTIME}/action"
	case "${stale}" in dead) stale_pid=999999999 ;; reused) stale_pid="$$" ;; esac
	printf '%s\n' "${stale_pid} 1" >"${RUNTIME}/action/owner"
	printf '%s\n' "${stale_pid}" 3 >"${RUNTIME}/action/pid"
	run_worker absent start_adguardhome &
	CHILD="$!"
	wait_for_file "${TEST_ROOT}/entered"
	if run_worker absent start_adguardhome; then fail 'completed metadata admitted a second action'; fi
	if run_worker absent cleanup "${stale_pid}" 1; then fail 'stale cleanup removed a successor lock'; fi
	[ -f "${RUNTIME}/action/owner" ] || fail 'successor owner was removed'
	: >"${TEST_ROOT}/release"
	wait "${CHILD}"
	CHILD=""
	[ "$(cat "${TEST_ROOT}/events")" = "$(printf '%s\n' start-enter start-exit)" ] || fail 'stale recovery admitted duplicate actions'
done

# Unpublished or malformed ownership remains busy; neither stop nor a cleanup
# may guess that such a directory belongs to it.
mkdir -m 700 "${RUNTIME}/action"
if run_worker absent stop_adguardhome; then fail 'ownerless state was guessed stale'; fi
[ -d "${RUNTIME}/action" ] || fail 'ownerless state was removed'
printf '%s\n' malformed >"${RUNTIME}/action/owner"
if run_worker absent stop_adguardhome; then fail 'malformed owner was accepted'; fi
[ "$(cat "${RUNTIME}/action/owner")" = malformed ] || fail 'malformed state was changed'
rm "${RUNTIME}/action/owner"
rmdir "${RUNTIME}/action"

# Interrupt cleanup releases only the terminating holder's action.
rm -f "${TEST_ROOT}/entered" "${TEST_ROOT}/release"
run_worker absent start_adguardhome &
CHILD="$!"
wait_for_file "${TEST_ROOT}/entered"
owner_pid="$(sed -n '1p' "${RUNTIME}/action/pid")"
kill -TERM "${owner_pid}"
: >"${TEST_ROOT}/release"
if wait "${CHILD}"; then fail 'interrupted owner reported success'; fi
CHILD=""
[ ! -e "${RUNTIME}/action" ] || fail 'interrupted owner retained its action'
run_worker absent stop_adguardhome || fail 'stop failed after interrupted-owner cleanup'

# SIGKILL in real publication/cleanup windows retains enough transition
# evidence to reclaim an empty owned directory while unknown state stays busy.
for phase in kill-publish kill-cleanup kill-reap kill-owner-writer; do
	rm -f "${TEST_ROOT}/entered" "${TEST_ROOT}/release" "${TEST_ROOT}/transition-blocked" "${TEST_ROOT}/transition-release"
	if [ "${phase}" = kill-reap ]; then
		mkdir -m 700 "${RUNTIME}/action"
		printf '%s\n' '999999999 1' >"${RUNTIME}/action/owner"
		printf '%s\n' 999999999 3 >"${RUNTIME}/action/pid"
	fi
	run_worker absent start_adguardhome "${phase}" &
	CHILD="$!"
	if [ "${phase}" = kill-cleanup ]; then
		wait_for_file "${TEST_ROOT}/entered"
		: >"${TEST_ROOT}/release"
	fi
	wait_for_file "${TEST_ROOT}/transition-blocked"
	identity="$(readlink "${RUNTIME}/action.claim")"
	owner_pid="${identity%% *}"
	kill -KILL "${owner_pid}"
	if [ "${phase}" = kill-owner-writer ]; then kill -KILL "$(cat "${TEST_ROOT}/writer-pid")"; fi
	if wait "${CHILD}"; then fail 'killed transition owner reported success'; fi
	CHILD=""
	[ -L "${RUNTIME}/action.transition" ] || fail 'interrupted transition lost ownership evidence'
	run_worker absent stop_adguardhome || fail "${phase} prevented stale transition recovery"
	[ ! -e "${RUNTIME}/action" ] && [ ! -L "${RUNTIME}/action.claim" ] && [ ! -L "${RUNTIME}/action.transition" ] || fail 'recovered transition artifacts remained'
done
if run_worker absent stop_adguardhome fail-owner; then fail 'failed owner publication reported success'; fi
run_worker absent stop_adguardhome || fail 'failed staged owner publication prevented recovery'
[ ! -e "${RUNTIME}/action" ] && [ ! -L "${RUNTIME}/action.transition" ] || fail 'failed owner publication left artifacts'

# A live or unverified publication claim returns busy immediately without a
# sleep/retry and without erasing another process's identity.
parent_start="$(awk '{ print $22 }' "/proc/$$/stat")"
for identity in "$$ ${parent_start}" malformed; do
	ln -s "${identity}" "${RUNTIME}/action.claim"
	if run_worker absent stop_adguardhome; then fail 'contended publication claim admitted an action'; fi
	[ "$(readlink "${RUNTIME}/action.claim")" = "${identity}" ] || fail 'foreign publication claim changed'
	rm "${RUNTIME}/action.claim"
done

# Historical descriptor locks were 0644 after firmware readiness changed the
# umask; probing these artifacts must be read-only and permit safe upgrades.
mkdir -m 755 "${TEST_ROOT}/manager"
(
	umask 022
	: >"${TEST_ROOT}/manager.lock"
)
legacy_inode="$(ls -id "${TEST_ROOT}/manager.lock" | awk '{ print $1 }')"
run_worker descriptor stop_adguardhome || fail 'safe historical descriptor artifact blocked upgrade'
[ "$(ls -id "${TEST_ROOT}/manager.lock" | awk '{ print $1 }')" = "${legacy_inode}" ] || fail 'legacy descriptor inode changed'
[ "$(ls -ld "${TEST_ROOT}/manager.lock" | cut -c2-10)" = rw-r--r-- ] || fail 'legacy descriptor permissions changed'
rm "${TEST_ROOT}/manager.lock"
# Without a descriptor artifact, the empty old directory may be an unpublished
# mkdir holder. It must block both backends until that holder completes.
if run_worker absent stop_adguardhome; then fail 'unpublished legacy mkdir admitted fallback stop'; fi
if run_worker descriptor stop_adguardhome; then fail 'unpublished legacy mkdir admitted descriptor stop'; fi
[ -d "${TEST_ROOT}/manager" ] || fail 'legacy unpublished holder was removed'
rmdir "${TEST_ROOT}/manager"

# Descriptor contention also keeps a stable inode and orders a waiting stop.
rm -f "${TEST_ROOT}/entered" "${TEST_ROOT}/release"
: >"${TEST_ROOT}/events"
run_worker descriptor start_adguardhome &
CHILD="$!"
wait_for_file "${TEST_ROOT}/entered"
run_worker descriptor stop_adguardhome &
STOP_CHILD="$!"
sleep 0.1
grep -q '^stop$' "${TEST_ROOT}/events" && fail 'descriptor stop overlapped startup'
: >"${TEST_ROOT}/release"
wait "${CHILD}"
CHILD=""
wait "${STOP_CHILD}" || fail 'waiting descriptor stop failed'
[ "$(cat "${TEST_ROOT}/events")" = "$(printf '%s\n' start-enter start-exit stop)" ] || fail 'descriptor operation order changed'
printf '%s\n' 'PASS: absent, incapable and descriptor-capable flock serialize service actions'
