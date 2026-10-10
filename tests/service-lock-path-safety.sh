#!/bin/sh
# Exercise real service-lock helpers without exposing router paths.
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${1:-${REPO_DIR}/AdGuardHome.sh}"
TEST_ROOT="${TMPDIR:-/tmp}/service-lock-path-safety.$$"
umask 077
mkdir "${TEST_ROOT}"

# fail reports a fixture failure.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}
# cleanup removes only the fixture workspace.
cleanup() {
	chmod -R u+rwx "${TEST_ROOT}" 2>/dev/null || true
	rm -rf "${TEST_ROOT}"
}
trap cleanup EXIT
trap 'cleanup; exit 1' HUP INT TERM

sed -n '/^# Run-lock helpers$/,/^# check_dns_environment/p' "${SCRIPT_PATH}" |
	sed '$d; s|/tmp/AdGuardHome|${TEST_ROOT}/manager|g; s|/tmp/adguardhome-flock-test|${TEST_ROOT}/probe|g' >"${TEST_ROOT}/functions"
sed -n '/^IPSet_Current_UID() {$/,/^}$/p; /^IPSet_Directory_Metadata() {$/,/^}$/p; /^proc_process_start_time() {$/,/^}$/p; /^proc_lock_claim_matches() {$/,/^}$/p; /^proc_lock_claim_acquire() {$/,/^}$/p; /^proc_lock_claim_release() {$/,/^}$/p' "${SCRIPT_PATH}" >>"${TEST_ROOT}/functions"
# shellcheck disable=SC1090
. "${TEST_ROOT}/functions"
# agh_log suppresses fixture diagnostics.
agh_log() { :; }
# service_wait records an acquired service operation.
service_wait() { printf '%s\n' "$1" >>"${TEST_ROOT}/actions"; }
# have_cmd uses the host command only when available.
have_cmd() { command -v "$1" >/dev/null 2>&1; }
# IPSet_Lock_Interrupt_Propagate has no enclosing transaction in this fixture.
IPSet_Lock_Interrupt_Propagate() { :; }

# The historical activity probe truncated this symlink's target.
printf '%s\n' intact >"${TEST_ROOT}/victim"
ln -s "${TEST_ROOT}/victim" "${TEST_ROOT}/manager.lock"
adguardhome_run_flock_active || true
[ "$(cat "${TEST_ROOT}/victim")" = intact ] || fail 'activity probe truncated a foreign symlink target'
adguardhome_run_flock start_adguardhome && fail 'service action accepted a legacy lock symlink'
adguardhome_run_mkdir stop_adguardhome && fail 'fallback accepted a legacy lock symlink'
[ -L "${TEST_ROOT}/manager.lock" ] || fail 'foreign legacy symlink was removed'
[ "$(cat "${TEST_ROOT}/victim")" = intact ] || fail 'service action changed a foreign target'
rm "${TEST_ROOT}/manager.lock"

# The historical capability probe truncated and removed a pre-created link.
ln -s "${TEST_ROOT}/victim" "${TEST_ROOT}/probe.$$"
flock_supports_fd || true
[ "$(cat "${TEST_ROOT}/victim")" = intact ] || fail 'capability probe truncated a foreign symlink target'
[ -L "${TEST_ROOT}/probe.$$" ] || fail 'capability probe removed a foreign symlink'
rm "${TEST_ROOT}/probe.$$"

RUNTIME="${TEST_ROOT}/manager-service-lock"
rmdir "${RUNTIME}" 2>/dev/null || true
for entry in symlink dangling fifo file directory; do
	case "${entry}" in
		symlink) ln -s "${TEST_ROOT}" "${RUNTIME}" ;;
		dangling) ln -s "${TEST_ROOT}/missing" "${RUNTIME}" ;;
		fifo) mkfifo "${RUNTIME}" ;;
		file) printf '%s\n' foreign >"${RUNTIME}" ;;
		directory) mkdir -m 755 "${RUNTIME}" ;;
	esac
	before="$(ls -ldni "${RUNTIME}")"
	adguardhome_run_flock_active || fail "unsafe ${entry} runtime was reported idle"
	adguardhome_run_flock start_adguardhome && fail "unsafe ${entry} runtime was accepted"
	adguardhome_run_mkdir stop_adguardhome && fail "unsafe ${entry} fallback runtime was accepted"
	flock_supports_fd && fail "unsafe ${entry} runtime permitted a capability probe"
	[ "$(ls -ldni "${RUNTIME}")" = "${before}" ] || fail "foreign ${entry} runtime changed"
	if [ -d "${RUNTIME}" ] && [ ! -L "${RUNTIME}" ]; then rmdir "${RUNTIME}"; else rm "${RUNTIME}"; fi
done

flock_supports_fd || fail 'descriptor-capable flock was not detected'
ln -s "${TEST_ROOT}/victim" "${RUNTIME}/probe.$$"
flock_supports_fd && fail 'pre-created private probe symlink was accepted'
[ -L "${RUNTIME}/probe.$$" ] || fail 'private probe symlink was removed'
[ "$(cat "${TEST_ROOT}/victim")" = intact ] || fail 'private probe target changed'
rm "${RUNTIME}/probe.$$"
for path in flock action; do
	for entry in symlink dangling fifo file hardlink; do
		case "${entry}" in
			symlink) ln -s "${TEST_ROOT}/victim" "${RUNTIME}/${path}" ;;
			dangling) ln -s "${TEST_ROOT}/missing" "${RUNTIME}/${path}" ;;
			fifo) mkfifo "${RUNTIME}/${path}" ;;
			file)
				printf '%s\n' foreign >"${RUNTIME}/${path}"
				chmod 644 "${RUNTIME}/${path}"
				;;
			hardlink) ln "${TEST_ROOT}/victim" "${RUNTIME}/${path}" ;;
		esac
		before="$(ls -ldni "${RUNTIME}/${path}")"
		adguardhome_run_flock start_adguardhome && fail "service accepted unsafe ${path}/${entry}"
		adguardhome_run_mkdir stop_adguardhome && fail "fallback accepted unsafe ${path}/${entry}"
		[ "$(ls -ldni "${RUNTIME}/${path}")" = "${before}" ] || fail "foreign ${path}/${entry} changed"
		[ "$(cat "${TEST_ROOT}/victim")" = intact ] || fail "foreign ${path}/${entry} target changed"
		rm "${RUNTIME}/${path}"
	done
done

# Unsafe service metadata is preserved during stale recovery and activity probes.
mkdir -m 700 "${RUNTIME}/action"
ln -s "${TEST_ROOT}/victim" "${RUNTIME}/action/owner"
adguardhome_run_mkdir stop_adguardhome && fail 'unsafe owner metadata was accepted'
adguardhome_run_flock_active || fail 'unsafe owner metadata was reported idle'
[ -L "${RUNTIME}/action/owner" ] || fail 'unsafe owner metadata was removed'
rm "${RUNTIME}/action/owner"
printf '%s\n' '999999999 1' >"${RUNTIME}/action/owner"
ln -s "${TEST_ROOT}/victim" "${RUNTIME}/action/pid"
adguardhome_run_legacy_mkdir_active || fail 'unsafe PID metadata was reported idle'
adguardhome_run_mkdir stop_adguardhome && fail 'unsafe stale metadata was accepted'
[ -L "${RUNTIME}/action/pid" ] || fail 'foreign stale metadata was removed'
[ "$(cat "${TEST_ROOT}/victim")" = intact ] || fail 'foreign metadata target changed'
rm "${RUNTIME}/action/owner" "${RUNTIME}/action/pid"
rmdir "${RUNTIME}/action"

# lock_snapshot records names, identities and file bytes without following links.
lock_snapshot() {
	find "${RUNTIME}" -print | sort | while IFS= read -r entry; do
		ls -ldni "${entry}"
		if [ ! -L "${entry}" ] && [ -f "${entry}" ]; then md5sum "${entry}"; fi
	done
}
# assert_readonly_activity checks liveness and proves metadata is never reaped by a probe.
assert_readonly_activity() {
	local before expected status
	expected="$1"
	before="$(lock_snapshot)"
	if adguardhome_run_legacy_mkdir_active; then status=busy; else status=idle; fi
	[ "${status}" = "${expected}" ] || fail "activity probe reported ${status}, expected ${expected}: $2"
	[ "$(lock_snapshot)" = "${before}" ] || fail "activity probe changed lock metadata: $2"
}

# Dead and PID-reused owners cease blocking cache readiness, even if their
# private action/claim/transition metadata remains for the next real action.
parent_start="$(proc_process_start_time "$$")"
mkdir -m 700 "${RUNTIME}/action"
for identity in '999999999 1' "$$ 1"; do
	printf '%s\n' "${identity}" >"${RUNTIME}/action/owner"
	printf '%s\n' "${identity%% *}" >"${RUNTIME}/action/pid"
	assert_readonly_activity idle "dead or PID-reused action ${identity}"
done
printf '%s\n' '999999999 1' >"${RUNTIME}/action/owner"
printf '%s\n' 999999999 >"${RUNTIME}/action/pid"
ln -s '999999998 1' "${RUNTIME}/action.claim"
ln -s '999999998 1 999999999 1' "${RUNTIME}/action.transition"
assert_readonly_activity idle 'every recorded action and transition identity is dead'
rm "${RUNTIME}/action.claim" "${RUNTIME}/action.transition"
for marker in action.claim action.transition; do
	case "${marker}" in
		action.claim) identity="$$ ${parent_start}" ;;
		action.transition) identity="$$ ${parent_start} 999999999 1" ;;
	esac
	ln -s "${identity}" "${RUNTIME}/${marker}"
	assert_readonly_activity busy "live ${marker} mutator"
	rm "${RUNTIME}/${marker}"
done
ln -s "999999998 1 $$ ${parent_start}" "${RUNTIME}/action.transition"
assert_readonly_activity busy 'live expected transition owner'
rm "${RUNTIME}/action.transition"
ln -s '999999998 1 999999997 1' "${RUNTIME}/action.transition"
assert_readonly_activity busy 'transition does not describe the action owner'
rm "${RUNTIME}/action.transition"
printf '%s\n' "$$ ${parent_start}" >"${RUNTIME}/action/owner"
printf '%s\n' "$$" >"${RUNTIME}/action/pid"
assert_readonly_activity busy 'live immutable action owner'
# Failed start-time reads or signal permissions must not guess an existing PID dead.
(
	# proc_process_start_time models inaccessible process identity data.
	proc_process_start_time() { return 1; }
	# kill models a signal probe whose permission failure proves no liveness state.
	kill() { return 1; }
	assert_readonly_activity busy 'unreadable existing process identity'
)
for identity in malformed 999999999 '999999999 1 extra' '0 1' '999999999999 1' "0$$ ${parent_start}" "$$ 0${parent_start}"; do
	printf '%s\n' "${identity}" >"${RUNTIME}/action/owner"
	assert_readonly_activity busy "malformed owner ${identity}"
done
printf '%s\n' '999999999 1' '' >"${RUNTIME}/action/owner"
assert_readonly_activity busy 'multiline owner record'
rm "${RUNTIME}/action/owner" "${RUNTIME}/action/pid"
assert_readonly_activity busy 'ownerless action without transition evidence'
ln -s '999999999 1 999999999 1' "${RUNTIME}/action.transition"
assert_readonly_activity idle 'dead transition owns interrupted empty publication'
: >"${RUNTIME}/action/owner.new"
assert_readonly_activity idle 'dead transition owns an unpublished private staged record'
: >"${RUNTIME}/action/.unknown"
assert_readonly_activity busy 'unknown action metadata'
rm "${RUNTIME}/action/.unknown"
chmod 644 "${RUNTIME}/action/owner.new"
assert_readonly_activity busy 'unsafe staged record'
rm "${RUNTIME}/action/owner.new" "${RUNTIME}/action.transition"
rmdir "${RUNTIME}/action"
for marker in action.claim action.transition; do
	for identity in malformed 999999999 '999999999 1 extra' '0 1' '999999999999 1' "0$$ ${parent_start}" "$$ 0${parent_start}"; do
		ln -s "${identity}" "${RUNTIME}/${marker}"
		assert_readonly_activity busy "malformed ${marker} ${identity}"
		rm "${RUNTIME}/${marker}"
	done
	printf '%s\n' '999999999 1' >"${RUNTIME}/${marker}"
	assert_readonly_activity busy "regular-file ${marker}"
	rm "${RUNTIME}/${marker}"
done

# UID-0 validation also proves that matching type/mode alone is insufficient.
if [ "$(IPSet_Current_UID)" = 0 ]; then
	chown 1 "${RUNTIME}"
	adguardhome_run_flock start_adguardhome && fail 'foreign-owned runtime was accepted'
	flock_supports_fd && fail 'foreign-owned runtime permitted a probe'
	[ "$(ls -ldn "${RUNTIME}" | awk '{ print $3 }')" = 1 ] || fail 'foreign owner changed'
	chown 0 "${RUNTIME}"
	printf '%s\n' foreign >"${RUNTIME}/flock"
	chown 1 "${RUNTIME}/flock"
	adguardhome_run_flock start_adguardhome && fail 'foreign-owned descriptor file was accepted'
	[ "$(cat "${RUNTIME}/flock")" = foreign ] || fail 'foreign descriptor file changed'
	chown 0 "${RUNTIME}/flock"
	rm "${RUNTIME}/flock"
	for marker in action.claim action.transition; do
		ln -s '999999999 1 999999999 1' "${RUNTIME}/${marker}"
		chown -h 1 "${RUNTIME}/${marker}"
		before="$(ls -ldni "${RUNTIME}/${marker}")"
		adguardhome_run_legacy_mkdir_active || fail "foreign-owned ${marker} was reported idle"
		adguardhome_run_mkdir stop_adguardhome && fail "foreign-owned ${marker} was accepted"
		[ "$(ls -ldni "${RUNTIME}/${marker}")" = "${before}" ] || fail "foreign-owned ${marker} changed"
		rm "${RUNTIME}/${marker}"
	done
	mkdir -m 700 "${RUNTIME}/action"
	printf '%s\n' '999999999 1' >"${RUNTIME}/action/owner"
	chown 1 "${RUNTIME}/action/owner"
	adguardhome_run_mkdir stop_adguardhome && fail 'foreign-owned owner record was accepted'
	[ "$(cat "${RUNTIME}/action/owner")" = '999999999 1' ] || fail 'foreign owner record changed'
	chown 0 "${RUNTIME}/action/owner"
	printf '%s\n' foreign >"${RUNTIME}/action/pid"
	chown 1 "${RUNTIME}/action/pid"
	adguardhome_run_mkdir stop_adguardhome && fail 'foreign-owned PID metadata was accepted'
	[ "$(cat "${RUNTIME}/action/pid")" = foreign ] || fail 'foreign PID metadata changed'
	rm "${RUNTIME}/action/owner" "${RUNTIME}/action/pid"
	rmdir "${RUNTIME}/action"
fi

# Stable descriptor files remain single-link objects across completed actions.
adguardhome_run_flock start_adguardhome || fail 'safe descriptor action failed'
inode="$(ls -id "${RUNTIME}/flock" | awk '{ print $1 }')"
adguardhome_run_flock stop_adguardhome || fail 'safe descriptor stop failed'
[ "$(ls -id "${RUNTIME}/flock" | awk '{ print $1 }')" = "${inode}" ] || fail 'descriptor lock inode changed'
[ ! -e "${RUNTIME}/action" ] || fail 'owned action lock was retained'
printf '%s\n' 'PASS: service-lock paths preserve foreign objects and descriptor identity'
