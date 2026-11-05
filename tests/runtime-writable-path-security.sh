#!/bin/sh
# Regression coverage for temporary-path ownership and exclusive creation.

set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TEST_ROOT="${TMPDIR:-/tmp}/runtime-writable-path-security.$$"
FUNCTIONS_FILE="${TEST_ROOT}/functions.sh"
RC_FUNCTIONS_FILE="${TEST_ROOT}/rc-functions.sh"
INSTALLER_FUNCTIONS_FILE="${TEST_ROOT}/installer-functions.sh"

# fail reports a test failure to standard error and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

# cleanup restores permissions under the test root and removes the temporary test directory.
cleanup() {
	chmod -R u+rwx "${TEST_ROOT}" 2>/dev/null || true
	rm -rf "${TEST_ROOT}"
}

# Keep the later failure stub visible to ShellCheck without changing the normal
# mkfifo provides a controllable wrapper around the system `mkfifo` utility for testing creation failures.
mkfifo() {
	[ "${MKFIFO_FAIL:-0}" = "0" ] || return 1
	"${TEST_NATIVE_MKFIFO}" "$@"
}

trap cleanup EXIT
trap 'cleanup; exit 1' HUP INT TERM
TEST_NATIVE_MKFIFO="$(which mkfifo)" || fail 'real mkfifo is unavailable'
umask 077
mkdir "${TEST_ROOT}"

for script in installer AdGuardHome.sh S99AdGuardHome rc.func.AdGuardHome; do
	grep -q '^umask 077$' "${REPO_DIR}/${script}" || fail "${script} does not establish a restrictive umask"
done

sed -n \
	'/^dns_handoff_path_has_owner_mode() {$/,/^}$/p; /^dns_guard_fifo_is_private() {$/,/^}$/p; /^remove_dns_guard_fifo() {$/,/^}$/p; /^dns_guard_open_wait_fd() {$/,/^}$/p; /^initialize_dns_guard_wait() {$/,/^}$/p' \
	"${REPO_DIR}/S99AdGuardHome" >"${FUNCTIONS_FILE}"
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

sed -n \
	'/^service_state_file() {$/,/^}$/p; /^service_state_dir_ready() {$/,/^}$/p; /^service_state_dir_is_private() {$/,/^}$/p; /^service_state_file_is_private() {$/,/^}$/p; /^service_state_file_migrate_legacy() {$/,/^}$/p; /^service_mark_transition() {$/,/^}$/p; /^service_transition_state() {$/,/^}$/p; /^service_clear_transition() {$/,/^}$/p' \
	"${REPO_DIR}/rc.func.AdGuardHome" >"${RC_FUNCTIONS_FILE}"
# shellcheck disable=SC1090
. "${RC_FUNCTIONS_FILE}"

STATE_FILE="${TEST_ROOT}/service/service-state"
# service_state_file prints the path of the service state file.
service_state_file() {
	printf '%s\n' "${STATE_FILE}"
}
service_mark_transition starting
[ "$(service_transition_state)" = "starting" ] || fail 'staged transition state was not published'
service_clear_transition
[ ! -e "${STATE_FILE}" ] && [ ! -L "${STATE_FILE}" ] || fail 'validated transition state was not cleared'
printf '%s\n' stopping >"${STATE_FILE}"
chmod 644 "${STATE_FILE}"
[ "$(service_transition_state)" = "stopping" ] || fail 'legacy transition state was not migrated'
[ "$(ls -ld "${STATE_FILE}" | cut -c2-10)" = 'rw-------' ] || fail 'legacy transition mode was not restricted'
service_clear_transition stopping
[ ! -e "${STATE_FILE}" ] || fail 'migrated transition state was not cleared'
printf '%s\n' stopping >"${TEST_ROOT}/foreign-state"
ln -s "${TEST_ROOT}/foreign-state" "${STATE_FILE}"
service_clear_transition
[ -L "${STATE_FILE}" ] || fail 'foreign transition symlink was removed'
rm "${STATE_FILE}"

sed -n \
	'/^cleanup_api_files() {$/,/^}$/p; /^metadata_workspace_create() {$/,/^}$/p; /^metadata_workspace_is_private() {$/,/^}$/p' \
	"${REPO_DIR}/installer" >"${INSTALLER_FUNCTIONS_FILE}"
# shellcheck disable=SC1090
. "${INSTALLER_FUNCTIONS_FILE}"
ADGUARD_METADATA_DIR="${TEST_ROOT}/metadata"
ADGUARD_METADATA_FILE="${ADGUARD_METADATA_DIR}/channels.txt"
ADGUARD_METADATA_DIR_OWNED=0
metadata_workspace_create || fail 'private metadata workspace was not created'
[ "$(ls -ld "${ADGUARD_METADATA_DIR}" | cut -c2-10)" = 'rwx------' ] || fail 'metadata workspace mode is not private'
printf '%s\n' metadata >"${ADGUARD_METADATA_FILE}"
cleanup_api_files || fail 'owned metadata workspace cleanup failed'
[ ! -e "${ADGUARD_METADATA_DIR}" ] || fail 'owned metadata workspace was retained'
ln -s "${TEST_ROOT}/victim-metadata" "${ADGUARD_METADATA_DIR}"
metadata_workspace_create && fail 'pre-created metadata symlink was accepted'
[ -L "${ADGUARD_METADATA_DIR}" ] || fail 'foreign metadata symlink was removed'
rm "${ADGUARD_METADATA_DIR}"

DNS_GUARD_READY_DIR="${TEST_ROOT}/guard"
mkdir "${DNS_GUARD_READY_DIR}"
chmod 700 "${DNS_GUARD_READY_DIR}"
_dns_guard_wait_initialized=0
_dns_guard_wait_fifo="${DNS_GUARD_READY_DIR}/wait"

# A shell without command must retain the guard descriptor while restoring an
# existing caller descriptor, including its read position.
(
	# command models an unavailable optional shell builtin.
	command() {
		printf '%s\n' unexpected-command >>"${TEST_ROOT}/command-calls"
		return 127
	}
	printf '%s\n' before after >"${TEST_ROOT}/caller-fd4"
	exec 4<"${TEST_ROOT}/caller-fd4"
	IFS= read -r value <&4 || exit 1
	[ "${value}" = before ] || exit 1
	initialize_dns_guard_wait || exit 1
	[ "${_dns_guard_wait_initialized}" = 1 ] || exit 1
	[ ! -e "${DNS_GUARD_READY_DIR}/wait" ] || exit 1
	printf '%s\n' guard-descriptor >&3 || exit 1
	IFS= read -r value <&3 || exit 1
	[ "${value}" = guard-descriptor ] || exit 1
	IFS= read -r value <&4 || exit 1
	[ "${value}" = after ] || exit 1
	exec 3<&- 4<&-
) || fail 'guard FIFO initialization required command or damaged caller descriptors'
[ ! -e "${TEST_ROOT}/command-calls" ] || fail 'guard FIFO initialization invoked command'

# Replace the validated FIFO immediately before opening it. The real open must
# fail without terminating the shell or removing the replacement directory.
sed -n '/^dns_guard_fifo_is_private() {$/,/^}$/p' "${REPO_DIR}/S99AdGuardHome" |
	sed 's/^dns_guard_fifo_is_private()/dns_guard_fifo_is_private_real()/' >"${TEST_ROOT}/fifo-validation" ||
	fail 'could not isolate FIFO validation for the open failure'
(
	. "${TEST_ROOT}/fifo-validation"
	# command rejects any optional-builtin dependency during an open failure.
	command() {
		printf '%s\n' unexpected-command >>"${TEST_ROOT}/command-calls"
		return 127
	}
	FIFO_VALIDATIONS=0
	# dns_guard_fifo_is_private validates once, then models a foreign replacement.
	dns_guard_fifo_is_private() {
		if [ "${FIFO_VALIDATIONS}" -eq 0 ]; then
			FIFO_VALIDATIONS=1
			dns_guard_fifo_is_private_real || return 1
			rm "${_dns_guard_wait_fifo}" || return 1
			mkdir "${_dns_guard_wait_fifo}" || return 1
			return 0
		fi
		dns_guard_fifo_is_private_real
	}
	printf '%s\n' caller-preserved >"${TEST_ROOT}/caller-fd4-failure"
	exec 4<"${TEST_ROOT}/caller-fd4-failure"
	if initialize_dns_guard_wait 2>/dev/null; then exit 1; fi
	[ "${_dns_guard_wait_initialized}" = 0 ] || exit 1
	[ -d "${DNS_GUARD_READY_DIR}/wait" ] || exit 1
	IFS= read -r value <&4 || exit 1
	[ "${value}" = caller-preserved ] || exit 1
	exec 4<&-
	rmdir "${DNS_GUARD_READY_DIR}/wait" || exit 1
	printf '%s\n' survived >"${TEST_ROOT}/fifo-open-survived"
) || fail 'guard FIFO open failure was fatal or damaged caller descriptors'
[ -f "${TEST_ROOT}/fifo-open-survived" ] || fail 'guard FIFO open failure terminated its shell'
[ ! -e "${TEST_ROOT}/command-calls" ] || fail 'guard FIFO open failure invoked command'

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
MKFIFO_FAIL=1
initialize_dns_guard_wait && fail 'FIFO creation failure was ignored'
[ ! -e "${DNS_GUARD_READY_DIR}/wait" ] || fail 'failed creation left a path behind'

printf '%s\n' 'PASS: runtime writable paths reject unsafe entries and clean up conservatively'
