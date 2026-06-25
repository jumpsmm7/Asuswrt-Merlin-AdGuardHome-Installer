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

sed -n '/^agh_timestamp() {$/,/^}$/p; /^agh_log() {$/,/^}$/p; /^IPSet_Has_Legacy_Mappings() {$/,/^}$/p; /^IPSet_Setup_Locked() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" || fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTION_FILE}" ] || fail 'IPSET setup functions were not found'

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

logger() {
	:
}

IPSet_Current_File() {
	printf '%s\n' "${CURRENT_FILE}"
}

IPSet_Collect_Yaml() {
	[ "${COLLECT_YAML_STATUS:-0}" -eq 0 ] || return "${COLLECT_YAML_STATUS}"
	[ -z "${LEGACY_RULES:-}" ] || printf '%s\n' "${LEGACY_RULES}"
}

IPSet_Migrate() {
	MIGRATE_CALLS="$((MIGRATE_CALLS + 1))"
	IPSET_MIGRATION_SKIPPED=""
	printf '%s\n' 'dns:' '  ipset: []' "  ipset_file: ${IPSET_FILE}" >"${YAML_FILE}"
	return 0
}

IPSet_Refresh_Locked() {
	REFRESH_CALLS="$((REFRESH_CALLS + 1))"
	if [ "${CREATE_IPSET_FILE:-0}" -eq 1 ]; then
		printf '%s\n' 'example.com/ROUTE_VPN' >"${IPSET_FILE}"
	fi
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
IPSET_USER_FILE="${TEST_DIR}/ipset.user"
CURRENT_FILE="${IPSET_FILE}"
LEGACY_RULES=old.example/old_set
MIGRATE_CALLS=0
REFRESH_CALLS=0
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

rm -f "${IPSET_FILE}"
printf '%s\n' 'dns:' '  ipset: []' >"${YAML_FILE}"
CURRENT_FILE=""
LEGACY_RULES=""
MIGRATE_CALLS=0
REFRESH_CALLS=0
REFRESH_STATUS=0
CREATE_IPSET_FILE=0
IPSet_Setup_Locked || fail 'repeated empty setup failed'
[ "${REFRESH_CALLS}" -eq 1 ] || fail 'repeated empty setup did not refresh before migration'
[ "${MIGRATE_CALLS}" -eq 0 ] || fail 'repeated empty setup restored the managed YAML reference'
grep -q 'ipset_file' "${YAML_FILE}" && fail 'repeated empty setup changed the effective empty YAML state'
assert_no_backup

MIGRATE_CALLS=0
REFRESH_CALLS=0
CREATE_IPSET_FILE=1
IPSet_Setup_Locked || fail 'setup failed when mappings reappeared'
[ "${REFRESH_CALLS}" -eq 2 ] || fail 'reappearing mappings were not refreshed before and after migration'
[ "${MIGRATE_CALLS}" -eq 1 ] || fail 'reappearing mappings did not restore managed YAML integration'
grep -q "ipset_file: ${IPSET_FILE}" "${YAML_FILE}" || fail 'managed YAML reference was not restored for new mappings'
assert_no_backup

printf '%s\n' 'PASS: setup rollback and empty-state migration behavior are correct'
