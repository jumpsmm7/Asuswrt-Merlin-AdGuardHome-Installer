#!/bin/sh
# Verify a failed initial IPSET refresh restores the pre-migration YAML.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
FUNCTION_FILE="${TMPDIR:-/tmp}/ipset-setup-function.$$"
TEST_DIR="${TMPDIR:-/tmp}/ipset-setup-test.$$"

cleanup() {
	rm -f "${FUNCTION_FILE}"
	rm -rf "${TEST_DIR}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

sed -n '/^IPSet_Setup_Locked() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" || fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTION_FILE}" ] || fail 'IPSet_Setup_Locked was not found'

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

logger() {
	:
}

IPSet_Migrate() {
	IPSET_MIGRATION_SKIPPED=""
	printf '%s\n' 'dns:' '  ipset: []' "  ipset_file: ${IPSET_FILE}" >"${YAML_FILE}"
	return 0
}

IPSet_Refresh_Locked() {
	return "${REFRESH_STATUS}"
}

assert_no_backup() {
	set -- "${YAML_FILE}.ipset-setup."*
	[ ! -e "$1" ] || fail "setup backup was not removed: $1"
}

mkdir -p "${TEST_DIR}" || fail 'could not create test directory'
YAML_FILE="${TEST_DIR}/AdGuardHome.yaml"
IPSET_FILE="${TEST_DIR}/ipset.conf"
NAME=AdGuardHome
ORIGINAL_YAML='dns:
  ipset:
    - old.example/old_set'

printf '%s\n' "${ORIGINAL_YAML}" >"${YAML_FILE}"
REFRESH_STATUS=7
IPSet_Setup_Locked
SETUP_STATUS="$?"
[ "${SETUP_STATUS}" -eq "${REFRESH_STATUS}" ] || fail "setup returned ${SETUP_STATUS} instead of refresh status ${REFRESH_STATUS}"
ACTUAL_YAML="$(cat "${YAML_FILE}")"
[ "${ACTUAL_YAML}" = "${ORIGINAL_YAML}" ] || fail 'failed refresh did not restore the original YAML'
assert_no_backup

printf '%s\n' "${ORIGINAL_YAML}" >"${YAML_FILE}"
REFRESH_STATUS=0
IPSet_Setup_Locked || fail 'setup failed when migration and refresh succeeded'
EXPECTED_YAML="$(printf '%s\n' 'dns:' '  ipset: []' "  ipset_file: ${IPSET_FILE}")"
ACTUAL_YAML="$(cat "${YAML_FILE}")"
[ "${ACTUAL_YAML}" = "${EXPECTED_YAML}" ] || fail 'successful setup unexpectedly restored the original YAML'
assert_no_backup

printf '%s\n' 'PASS: failed initial IPSET refresh restores the pre-migration YAML'
