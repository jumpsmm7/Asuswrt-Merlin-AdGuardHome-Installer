#!/bin/sh
# Verify IPSET locking rejects symlinked and foreign-owned runtime paths.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
TEST_ROOT="${TMPDIR:-/tmp}/ipset-lock-security.$$"
FUNCTION_FILE="${TEST_ROOT}/functions"
TARGET_FILE="${TEST_ROOT}/target"
SIGNAL_TEST_FILE="${TEST_ROOT}/signal-test.sh"

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
sed -n '/^IPSet_Lock() {$/,/^}$/p; /^IPSet_Lock_Flock() {$/,/^}$/p; /^IPSet_Lock_Flock_Cleanup() {$/,/^}$/p; /^IPSet_Lock_Mkdir() {$/,/^}$/p; /^IPSet_Lock_Mkdir_Cleanup() {$/,/^}$/p; /^IPSet_Lock_Interrupt_Cleanup() {$/,/^}$/p; /^IPSet_Start_Restore() {$/,/^}$/p; /^IPSet_Runtime_Prepare() {$/,/^}$/p; /^IPSet_Restore_Traps() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" || fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTION_FILE}" ] || fail 'IPSET lock functions were not found'
if grep -q '/tmp/AdGuardHome-ipset' "${SCRIPT_PATH}"; then
	fail 'legacy IPSET lock artifacts remain in writable /tmp'
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
USE_FLOCK=0

IPSET_RUNTIME_DIR="${TEST_ROOT}/runtime"
IPSet_Lock lock_action || fail 'could not acquire fallback lock in private runtime directory'
[ "$(cat "${TEST_ROOT}/called")" = called ] || fail 'locked action did not run'
[ "$(stat -c '%a' "${IPSET_RUNTIME_DIR}")" = 700 ] || fail 'runtime directory is not mode 700'
[ ! -e "${IPSET_RUNTIME_DIR}/mkdir" ] || fail 'fallback lock directory was not cleaned up'

cat >"${SIGNAL_TEST_FILE}" <<'EOF'
#!/bin/sh
set -u
. "$1"
IPSET_RUNTIME_DIR="$2"
USE_FLOCK="$3"
CALLS_FILE="$4"
NAME=AdGuardHome-test
have_cmd() { [ "${USE_FLOCK}" -eq 1 ] && [ "$1" = flock ]; }
flock_supports_fd() { return 0; }
logger() { :; }
lower_script() { printf '%s\n' "$1" >>"${CALLS_FILE}"; return 0; }
interrupt_action() {
	IPSET_START_STOPPED="1"
	kill -TERM "$$"
	sleep 1
}
IPSet_Lock interrupt_action
EOF
chmod 700 "${SIGNAL_TEST_FILE}" || fail 'could not make signal test executable'

for SIGNAL_USE_FLOCK in 0 1; do
	SIGNAL_RUNTIME="${TEST_ROOT}/signal-runtime-${SIGNAL_USE_FLOCK}"
	SIGNAL_CALLS="${TEST_ROOT}/signal-calls-${SIGNAL_USE_FLOCK}"
	if sh "${SIGNAL_TEST_FILE}" "${FUNCTION_FILE}" "${SIGNAL_RUNTIME}" "${SIGNAL_USE_FLOCK}" "${SIGNAL_CALLS}"; then
		fail "signal test unexpectedly succeeded with USE_FLOCK=${SIGNAL_USE_FLOCK}"
	fi
	[ "$(cat "${SIGNAL_CALLS}")" = start ] || fail "signal did not restore the stopped service with USE_FLOCK=${SIGNAL_USE_FLOCK}"
	[ ! -e "${SIGNAL_RUNTIME}/mkdir" ] || fail "signal left fallback lock behind with USE_FLOCK=${SIGNAL_USE_FLOCK}"
done

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
