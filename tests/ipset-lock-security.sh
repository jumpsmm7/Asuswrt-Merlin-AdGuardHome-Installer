#!/bin/sh
# Verify IPSET locking uses an ownership-validated private runtime directory.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
TEST_ROOT="${TMPDIR:-/tmp}/ipset-lock-security.$$"
FUNCTION_FILE="${TEST_ROOT}/functions"
TARGET_FILE="${TEST_ROOT}/target"
INTERRUPT_TEST_FILE="${TEST_ROOT}/interrupt-test.sh"
TRAP_TEST_FILE="${TEST_ROOT}/trap-test.sh"
HAS_FLOCK=0

cleanup() {
	chmod 700 "${TEST_ROOT}/foreign" 2>/dev/null || true
	rm -rf "${TEST_ROOT}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

mkdir -m 700 "${TEST_ROOT}" || fail 'could not create test directory'
if which flock >/dev/null 2>&1 && (exec 9>"${TEST_ROOT}/flock-probe" && flock -n 9); then
	HAS_FLOCK=1
fi
rm -f "${TEST_ROOT}/flock-probe"
sed -n '/^agh_timestamp() {$/,/^}$/p; /^agh_log() {$/,/^}$/p; /^adguard_restart_dnsmasq_if_managed() {$/,/^}$/p; /^IPSet_Current_UID() {$/,/^}$/p; /^IPSet_Directory_Metadata() {$/,/^}$/p; /^IPSet_Dnsmasq_Restart_After_Unlock() {$/,/^}$/p; /^IPSet_Lock() {$/,/^}$/p; /^IPSet_Lock_Flock() {$/,/^}$/p; /^IPSet_Lock_Flock_Cleanup() {$/,/^}$/p; /^IPSet_Lock_Mkdir() {$/,/^}$/p; /^IPSet_Lock_Mkdir_Cleanup() {$/,/^}$/p; /^IPSet_Lock_Mkdir_Reap_Stale() {$/,/^}$/p; /^IPSet_Restore_Traps() {$/,/^}$/p; /^IPSet_Runtime_Prepare() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" || fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTION_FILE}" ] || fail 'IPSET lock functions were not found'
if ! grep -Eq '^IPSET_RUNTIME_DIR=.*AdGuardHome-ipset' "${SCRIPT_PATH}"; then
	fail 'the private IPSET runtime directory default is not defined'
fi
if grep -Eq 'IPSET_LOCK_ROOT|/tmp/AdGuardHome-ipset' "${SCRIPT_PATH}"; then
	fail 'legacy IPSET lock paths remain in the installer'
fi
if ! grep -Fq 'IPSet_Lock_Interrupt_Cleanup; IPSet_Lock_Flock_Cleanup; IPSet_Dnsmasq_Restart_After_Unlock; IPSet_Restore_Traps' "${SCRIPT_PATH}"; then
	fail 'flock interrupt cleanup does not restore AdGuardHome before releasing the lock'
fi
if ! grep -Fq 'IPSet_Lock_Interrupt_Cleanup; IPSet_Lock_Mkdir_Cleanup "${LOCK_DIR}"; IPSet_Dnsmasq_Restart_After_Unlock; IPSet_Restore_Traps' "${SCRIPT_PATH}"; then
	fail 'fallback interrupt cleanup does not restore AdGuardHome before releasing the lock'
fi
if ! grep -Fq 'if have_cmd flock && flock_supports_fd; then' "${SCRIPT_PATH}"; then
	fail 'IPSET locking does not prefer compatible flock with mkdir as fallback'
fi

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

adguard_dnsmasq_managed() {
	return 0
}

id() {
	fail 'IPSET lock code called unavailable id command'
}

stat() {
	fail 'IPSET lock code called unavailable stat command'
}

have_cmd() {
	[ "${USE_FLOCK:-0}" -eq 1 ] && [ "$1" = flock ]
}

flock_supports_fd() {
	[ "${FLOCK_FD_SUPPORTED:-1}" -eq 1 ]
}

logger() {
	:
}

service() {
	[ "$1" = restart_dnsmasq ] || fail "unexpected service call: $*"
	case "${USE_FLOCK:-0}" in
		1)
			if (exec 9>"${IPSET_RUNTIME_DIR}/flock" && flock -n 9); then :; else
				fail 'dnsmasq restarted before the flock was released'
			fi
			;;
		*)
			[ ! -d "${IPSET_RUNTIME_DIR}/mkdir" ] || fail 'dnsmasq restarted before the mkdir lock was released'
			;;
	esac
	printf '%s\n' restart_dnsmasq >"${TEST_ROOT}/dnsmasq-restarted"
}

cat >"${INTERRUPT_TEST_FILE}" <<'EOF'
#!/bin/sh
set -u

FUNCTION_FILE="$1"
TEST_ROOT="$2"
LOCK_MODE="$3"
IPSET_RUNTIME_DIR="${TEST_ROOT}/${LOCK_MODE}-interrupt-runtime"
NAME=AdGuardHome-test
USE_FLOCK=0
[ "${LOCK_MODE}" = flock ] && USE_FLOCK=1

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

adguard_dnsmasq_managed() {
	return 0
}

have_cmd() {
	[ "${USE_FLOCK}" -eq 1 ] && [ "$1" = flock ]
}

flock_supports_fd() {
	return 0
}

logger() {
	:
}

service() {
	:
}

IPSet_Lock_Interrupt_Cleanup() {
	case "${LOCK_MODE}" in
		flock)
			if (exec 9>"${IPSET_RUNTIME_DIR}/flock" && flock -n 9); then
				exit 1
			fi
			;;
		mkdir)
			[ -d "${IPSET_RUNTIME_DIR}/mkdir" ] || exit 1
			;;
	esac
	printf '%s\n' held >"${TEST_ROOT}/${LOCK_MODE}-interrupt-held"
}

interrupt_action() {
	kill -TERM "$$"
	sleep 1
}

IPSet_Lock interrupt_action
EOF
chmod 700 "${INTERRUPT_TEST_FILE}" || fail 'could not make interrupt test executable'

cat >"${TRAP_TEST_FILE}" <<'EOF'
#!/bin/sh
set -u

FUNCTION_FILE="$1"
TEST_ROOT="$2"
LOCK_MODE="$3"
IPSET_RUNTIME_DIR="${TEST_ROOT}/${LOCK_MODE}-trap-runtime"
NAME=AdGuardHome-test
USE_FLOCK=0
[ "${LOCK_MODE}" = flock ] && USE_FLOCK=1

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

adguard_dnsmasq_managed() {
	return 0
}

have_cmd() {
	[ "${USE_FLOCK}" -eq 1 ] && [ "$1" = flock ]
}

flock_supports_fd() {
	return 0
}

logger() {
	:
}

service() {
	:
}

fail_action() {
	return 23
}

trap 'printf "%s\n" exit >"${TEST_ROOT}/${LOCK_MODE}-caller-exit"' EXIT
trap 'printf "%s\n" term >"${TEST_ROOT}/${LOCK_MODE}-caller-term"' TERM
if IPSet_Lock fail_action; then
	exit 2
else
	STATUS="$?"
fi
[ "${STATUS}" -eq 23 ] || exit 3
kill -TERM "$$"
[ -f "${TEST_ROOT}/${LOCK_MODE}-caller-term" ] || exit 4
exit 0
EOF
chmod 700 "${TRAP_TEST_FILE}" || fail 'could not make caller trap test executable'

run_interrupt_test() {
	LOCK_MODE="$1"
	if "${INTERRUPT_TEST_FILE}" "${FUNCTION_FILE}" "${TEST_ROOT}" "${LOCK_MODE}"; then
		fail "${LOCK_MODE} interrupt unexpectedly returned success"
	fi
	[ -f "${TEST_ROOT}/${LOCK_MODE}-interrupt-held" ] || fail "${LOCK_MODE} interrupt restored after releasing the lock"
	[ ! -d "${TEST_ROOT}/${LOCK_MODE}-interrupt-runtime/mkdir" ] || fail "${LOCK_MODE} interrupt left the fallback lock behind"
}

run_trap_test() {
	LOCK_MODE="$1"
	"${TRAP_TEST_FILE}" "${FUNCTION_FILE}" "${TEST_ROOT}" "${LOCK_MODE}" || fail "${LOCK_MODE} did not preserve caller traps and callback status"
	[ "$(cat "${TEST_ROOT}/${LOCK_MODE}-caller-term" 2>/dev/null)" = term ] || fail "${LOCK_MODE} did not restore the caller TERM trap"
	[ "$(cat "${TEST_ROOT}/${LOCK_MODE}-caller-exit" 2>/dev/null)" = exit ] || fail "${LOCK_MODE} did not restore the caller EXIT trap"
}

lock_action() {
	printf '%s\n' called >"${TEST_ROOT}/called"
}

lock_dnsmasq_action() {
	IPSET_DNSMASQ_RESTART_PENDING="1"
}

printf '%s\n' unchanged >"${TARGET_FILE}"
ln -s "${TARGET_FILE}" "${TEST_ROOT}/runtime-link" || fail 'could not create runtime symlink'
NAME=AdGuardHome-test
IPSET_RUNTIME_DIR="${TEST_ROOT}/runtime-link"
if IPSet_Lock lock_action; then
	fail 'accepted a symlinked runtime directory'
fi
[ "$(cat "${TARGET_FILE}")" = unchanged ] || fail 'symlink target was modified'
[ ! -e "${TEST_ROOT}/called" ] || fail 'action ran with unsafe runtime path'

mkdir -m 755 "${TEST_ROOT}/public-runtime" || fail 'could not create public runtime directory'
IPSET_RUNTIME_DIR="${TEST_ROOT}/public-runtime"
if IPSet_Lock lock_action; then
	fail 'accepted a runtime directory that was not mode 700'
fi

if [ "${HAS_FLOCK}" -eq 1 ]; then
	USE_FLOCK=1
	IPSET_RUNTIME_DIR="${TEST_ROOT}/flock-runtime"
	IPSet_Lock lock_action || fail 'could not acquire flock in private runtime directory'
	[ -f "${IPSET_RUNTIME_DIR}/flock" ] || fail 'flock file was not created in the private runtime directory'
	[ ! -e "${IPSET_RUNTIME_DIR}/traps.$$" ] || fail 'flock trap-state file was not cleaned up'
	rm -f "${TEST_ROOT}/dnsmasq-restarted"
	IPSet_Lock lock_dnsmasq_action || fail 'could not defer dnsmasq restart with flock'
	[ -f "${TEST_ROOT}/dnsmasq-restarted" ] || fail 'flock path did not restart dnsmasq after unlock'
	run_interrupt_test flock
	run_trap_test flock
fi
USE_FLOCK=0

run_interrupt_test mkdir
run_trap_test mkdir

# An installed flock without descriptor-lock support must use mkdir instead.
USE_FLOCK=1
FLOCK_FD_SUPPORTED=0
IPSET_RUNTIME_DIR="${TEST_ROOT}/incompatible-flock-runtime"
rm -f "${TEST_ROOT}/called"
IPSet_Lock lock_action || fail 'did not fall back when flock lacks descriptor locking'
[ "$(cat "${TEST_ROOT}/called")" = called ] || fail 'fallback action did not run for incompatible flock'
[ ! -e "${IPSET_RUNTIME_DIR}/flock" ] || fail 'incompatible flock backend was selected'
[ ! -d "${IPSET_RUNTIME_DIR}/mkdir" ] || fail 'incompatible-flock fallback lock was not cleaned up'
FLOCK_FD_SUPPORTED=1
USE_FLOCK=0

IPSET_RUNTIME_DIR="${TEST_ROOT}/runtime"
IPSet_Lock lock_action || fail 'could not acquire fallback lock in private runtime directory'
[ "$(cat "${TEST_ROOT}/called")" = called ] || fail 'locked action did not run'
[ "$(IPSet_Directory_Metadata "${IPSET_RUNTIME_DIR}")" = "$(IPSet_Current_UID) rwx------" ] || fail 'runtime directory is not mode 700'
[ ! -e "${IPSET_RUNTIME_DIR}/mkdir" ] || fail 'fallback lock directory was not cleaned up'
rm -f "${TEST_ROOT}/dnsmasq-restarted"
IPSet_Lock lock_dnsmasq_action || fail 'could not defer dnsmasq restart with the fallback lock'
[ -f "${TEST_ROOT}/dnsmasq-restarted" ] || fail 'fallback path did not restart dnsmasq after unlock'

# A waiter that observed an old dead PID must not remove a replacement lock.
mkdir -m 700 "${IPSET_RUNTIME_DIR}/mkdir" || fail 'could not create replacement fallback lock'
printf '%s\n' "$$" >"${IPSET_RUNTIME_DIR}/mkdir/pid"
if IPSet_Lock_Mkdir_Reap_Stale "${IPSET_RUNTIME_DIR}/mkdir" 999999; then
	fail 'removed a replacement fallback lock'
fi
[ -d "${IPSET_RUNTIME_DIR}/mkdir" ] || fail 'replacement fallback lock was deleted'
[ "$(cat "${IPSET_RUNTIME_DIR}/mkdir/pid")" = "$$" ] || fail 'replacement fallback lock owner changed'
[ ! -e "${IPSET_RUNTIME_DIR}/mkdir/reap" ] || fail 'replacement fallback lock retained the reaper marker'
rm -rf "${IPSET_RUNTIME_DIR}/mkdir"

mkdir -m 700 "${IPSET_RUNTIME_DIR}/mkdir" || fail 'could not create stale fallback lock'
printf '%s\n' 999999 >"${IPSET_RUNTIME_DIR}/mkdir/pid"
IPSet_Lock_Mkdir_Reap_Stale "${IPSET_RUNTIME_DIR}/mkdir" 999999 || fail 'could not reap an unchanged stale fallback lock'
[ ! -e "${IPSET_RUNTIME_DIR}/mkdir" ] || fail 'unchanged stale fallback lock was not removed'

if [ "$(IPSet_Current_UID)" -eq 0 ]; then
	mkdir -m 700 "${IPSET_RUNTIME_DIR}/mkdir" || fail 'could not create foreign-owner fallback lock'
	printf '%s\n' 1 >"${IPSET_RUNTIME_DIR}/mkdir/pid"
	chown -R 65534 "${IPSET_RUNTIME_DIR}/mkdir" || fail 'could not assign fallback lock foreign owner'
	rm -f "${TEST_ROOT}/called"
	if IPSet_Lock lock_action; then
		fail 'accepted a foreign-owned fallback lock directory'
	fi
	[ ! -e "${TEST_ROOT}/called" ] || fail 'action ran with foreign-owned fallback lock'
	rm -rf "${IPSET_RUNTIME_DIR}/mkdir"
fi

mkdir -m 700 "${TEST_ROOT}/foreign" || fail 'could not create foreign-owner test directory'
if [ "$(IPSet_Current_UID)" -eq 0 ]; then
	chown 65534 "${TEST_ROOT}/foreign" || fail 'could not assign foreign owner'
	IPSET_RUNTIME_DIR="${TEST_ROOT}/foreign"
	if IPSet_Lock lock_action; then
		fail 'accepted a foreign-owned runtime directory'
	fi
fi

printf '%s\n' 'PASS: IPSET locking uses a private, ownership-validated runtime directory'
