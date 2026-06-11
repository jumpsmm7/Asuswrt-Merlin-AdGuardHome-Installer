#!/bin/sh
# Verify IPSET locking uses an ownership-validated private runtime directory.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
TEST_ROOT="${TMPDIR:-/tmp}/ipset-lock-security.$$"
FUNCTION_FILE="${TEST_ROOT}/functions"
TARGET_FILE="${TEST_ROOT}/target"
INTERRUPT_TEST_FILE="${TEST_ROOT}/interrupt-test.sh"

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
sed -n '/^IPSet_Lock() {$/,/^}$/p; /^IPSet_Lock_Flock() {$/,/^}$/p; /^IPSet_Lock_Flock_Cleanup() {$/,/^}$/p; /^IPSet_Lock_Mkdir() {$/,/^}$/p; /^IPSet_Lock_Mkdir_Cleanup() {$/,/^}$/p; /^IPSet_Restore_Traps() {$/,/^}$/p; /^IPSet_Runtime_Prepare() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" || fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTION_FILE}" ] || fail 'IPSET lock functions were not found'
if ! grep -Eq '^IPSET_RUNTIME_DIR=.*AdGuardHome-ipset' "${SCRIPT_PATH}"; then
	fail 'the private IPSET runtime directory default is not defined'
fi
if grep -Eq 'IPSET_LOCK_ROOT|/tmp/AdGuardHome-ipset' "${SCRIPT_PATH}"; then
	fail 'legacy IPSET lock paths remain in the installer'
fi
if ! grep -Fq 'IPSet_Lock_Interrupt_Cleanup; IPSet_Lock_Flock_Cleanup; IPSet_Restore_Traps' "${SCRIPT_PATH}"; then
	fail 'flock interrupt cleanup does not restore AdGuardHome before releasing the lock'
fi
if ! grep -Fq 'IPSet_Lock_Interrupt_Cleanup; IPSet_Lock_Mkdir_Cleanup "${LOCK_DIR}"; IPSet_Restore_Traps' "${SCRIPT_PATH}"; then
	fail 'fallback interrupt cleanup does not restore AdGuardHome before releasing the lock'
fi

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

have_cmd() {
	[ "${USE_FLOCK:-0}" -eq 1 ] && [ "$1" = flock ]
}

flock_supports_fd() {
	return 0
}

logger() {
	:
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

have_cmd() {
	[ "${USE_FLOCK}" -eq 1 ] && [ "$1" = flock ]
}

flock_supports_fd() {
	return 0
}

logger() {
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

run_interrupt_test() {
	LOCK_MODE="$1"
	if "${INTERRUPT_TEST_FILE}" "${FUNCTION_FILE}" "${TEST_ROOT}" "${LOCK_MODE}"; then
		fail "${LOCK_MODE} interrupt unexpectedly returned success"
	fi
	[ -f "${TEST_ROOT}/${LOCK_MODE}-interrupt-held" ] || fail "${LOCK_MODE} interrupt restored after releasing the lock"
	[ ! -d "${TEST_ROOT}/${LOCK_MODE}-interrupt-runtime/mkdir" ] || fail "${LOCK_MODE} interrupt left the fallback lock behind"
}

lock_action() {
	printf '%s\n' called >"${TEST_ROOT}/called"
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

USE_FLOCK=1
IPSET_RUNTIME_DIR="${TEST_ROOT}/flock-runtime"
IPSet_Lock lock_action || fail 'could not acquire flock in private runtime directory'
[ -f "${IPSET_RUNTIME_DIR}/flock" ] || fail 'flock file was not created in the private runtime directory'
[ ! -e "${IPSET_RUNTIME_DIR}/traps.$$" ] || fail 'flock trap-state file was not cleaned up'
USE_FLOCK=0

run_interrupt_test flock
run_interrupt_test mkdir

IPSET_RUNTIME_DIR="${TEST_ROOT}/runtime"
IPSet_Lock lock_action || fail 'could not acquire fallback lock in private runtime directory'
[ "$(cat "${TEST_ROOT}/called")" = called ] || fail 'locked action did not run'
[ "$(stat -c '%a' "${IPSET_RUNTIME_DIR}")" = 700 ] || fail 'runtime directory is not mode 700'
[ ! -e "${IPSET_RUNTIME_DIR}/mkdir" ] || fail 'fallback lock directory was not cleaned up'

if [ "$(id -u)" -eq 0 ]; then
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
if [ "$(id -u)" -eq 0 ]; then
	chown 65534 "${TEST_ROOT}/foreign" || fail 'could not assign foreign owner'
	IPSET_RUNTIME_DIR="${TEST_ROOT}/foreign"
	if IPSet_Lock lock_action; then
		fail 'accepted a foreign-owned runtime directory'
	fi
fi

printf '%s\n' 'PASS: IPSET locking uses a private, ownership-validated runtime directory'
