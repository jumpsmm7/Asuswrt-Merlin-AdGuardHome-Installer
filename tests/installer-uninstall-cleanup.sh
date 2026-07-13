#!/bin/sh
# Verify uninstall removes rollback result marker stored outside the target tree.

set -u

SCRIPT_PATH="${1:-installer}"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"

grep -q '^readonly ROLLBACK_RESULT_FILE="${BASE_DIR}/\.AdGuardHome\.rollback_result"$' "${SCRIPT_PATH}" ||
	fail 'rollback result marker is not stored under BASE_DIR'

UNINSTALL_FUNCTION="$(sed -n '/^uninst_all() {$/,/^}/p' "${SCRIPT_PATH}")"
[ -n "${UNINSTALL_FUNCTION}" ] || fail 'could not extract uninst_all function'

printf '%s\n' "${UNINSTALL_FUNCTION}" | grep -q 'rm -rf .*"${ROLLBACK_RESULT_FILE}"' ||
	fail 'uninstall cleanup does not remove rollback result marker'

printf '%s\n' 'PASS: uninstall cleanup removes rollback result marker'
