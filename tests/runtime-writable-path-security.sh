#!/bin/sh
# Regression coverage for temporary-path ownership and exclusive creation.

set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TEST_ROOT="${TMPDIR:-/tmp}/runtime-writable-path-security.$$"
FUNCTIONS_FILE="${TEST_ROOT}/functions.sh"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

cleanup() {
	chmod -R u+rwx "${TEST_ROOT}" 2>/dev/null || true
	rm -rf "${TEST_ROOT}"
}

trap cleanup EXIT HUP INT TERM
umask 077
mkdir "${TEST_ROOT}"

for script in installer AdGuardHome.sh S99AdGuardHome rc.func.AdGuardHome; do
	grep -q '^umask 077$' "${REPO_DIR}/${script}" || fail "${script} does not establish a restrictive umask"
done

sed -n \
	'/^dns_handoff_path_has_owner_mode() {$/,/^}$/p; /^dns_guard_fifo_is_private() {$/,/^}$/p; /^remove_dns_guard_fifo() {$/,/^}$/p; /^initialize_dns_guard_wait() {$/,/^}$/p' \
	"${REPO_DIR}/S99AdGuardHome" >"${FUNCTIONS_FILE}"
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

DNS_GUARD_READY_DIR="${TEST_ROOT}/guard"
mkdir "${DNS_GUARD_READY_DIR}"
chmod 700 "${DNS_GUARD_READY_DIR}"

# A pre-created symlink must neither be followed nor removed.
victim="${TEST_ROOT}/victim"
printf '%s\n' intact >"${victim}"
ln -s "${victim}" "${DNS_GUARD_READY_DIR}/wait"
initialize_dns_guard_wait && fail 'pre-created FIFO symlink was accepted'
[ -L "${DNS_GUARD_READY_DIR}/wait" ] || fail 'foreign symlink was removed'
[ "$(cat "${victim}")" = intact ] || fail 'symlink target was modified'
rm "${DNS_GUARD_READY_DIR}/wait"

# Wrong types and multiply linked FIFOs are foreign state.
mkdir "${DNS_GUARD_READY_DIR}/wait"
initialize_dns_guard_wait && fail 'pre-created directory was accepted as a FIFO'
[ -d "${DNS_GUARD_READY_DIR}/wait" ] || fail 'foreign directory was removed'
rmdir "${DNS_GUARD_READY_DIR}/wait"
mkfifo "${DNS_GUARD_READY_DIR}/wait"
ln "${DNS_GUARD_READY_DIR}/wait" "${DNS_GUARD_READY_DIR}/wait.link"
dns_guard_fifo_is_private && fail 'multiply linked FIFO was accepted'
rm "${DNS_GUARD_READY_DIR}/wait" "${DNS_GUARD_READY_DIR}/wait.link"

# A foreign owner is rejected (run only where the test process may chown).
mkfifo "${DNS_GUARD_READY_DIR}/wait"
if chown 1 "${DNS_GUARD_READY_DIR}/wait" 2>/dev/null; then
	dns_guard_fifo_is_private && fail 'foreign-owned FIFO was accepted'
	chown 0 "${DNS_GUARD_READY_DIR}/wait"
fi
rm "${DNS_GUARD_READY_DIR}/wait"

# PID reuse protection is represented by PID plus process start time, not PID
# alone, for every reclaimable handoff owner record.
grep -q 'dns_handoff_process_start_time "${_dns_handoff_lock_pid}"' "${REPO_DIR}/S99AdGuardHome" ||
	fail 'handoff lock does not verify process start time'
grep -q '\[ "${_dns_handoff_current_start_time}" = "${_dns_handoff_marker_start_time}" \]' "${REPO_DIR}/S99AdGuardHome" ||
	fail 'handoff marker does not reject PID reuse'

# Interrupted cleanup must route through ownership/type validation rather than a
# raw unlink.  This also protects a replacement planted before the trap runs.
grep -q "remove_dns_guard_fifo || true; remove_current_dns_guard_readiness" "${REPO_DIR}/S99AdGuardHome" ||
	fail 'guard signal cleanup bypasses validated FIFO cleanup'

# Simulate a read-only filesystem by forcing the creation primitive to fail.
# The operation must fail without publishing or deleting another path.
mkfifo() { return 1; }
initialize_dns_guard_wait && fail 'FIFO creation failure was ignored'
[ ! -e "${DNS_GUARD_READY_DIR}/wait" ] || fail 'failed creation left a path behind'

printf '%s\n' 'PASS: runtime writable paths reject unsafe entries and clean up conservatively'
