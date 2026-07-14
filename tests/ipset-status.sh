#!/bin/sh
# Verify read-only installer IPSET status reports managed files and set families.

set -u

SCRIPT_PATH="${1:-installer}"
FUNCTION_FILE="${TMPDIR:-/tmp}/ipset-status-functions.$$"
TEST_DIR="${TMPDIR:-/tmp}/ipset-status-test.$$"
OUTPUT_FILE="${TMPDIR:-/tmp}/ipset-status-output.$$"

cleanup() {
	rm -f "${FUNCTION_FILE}" "${OUTPUT_FILE}"
	rm -rf "${TEST_DIR}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

sed -n '/^ai_have_cmd() {$/,/^}$/p; /^adguardhome_yaml_ipset_file() {$/,/^}$/p; /^ipset_status_path() {$/,/^}$/p; /^ipset_status_sets() {$/,/^}$/p; /^ipset_status_set_family() {$/,/^}$/p; /^ipset_status_report_set() {$/,/^}$/p; /^ipset_status() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" || fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTION_FILE}" ] || fail 'IPSET status functions were not found'

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

INFO="Info:"
WARNING="Warning:"

PTXT() {
	printf '%s\n' "$*"
}

CONF_IPSET_VALUE="YES"
HAVE_IPSET="1"

conf_value() {
	case "$1" in
		ADGUARD_IPSET) printf '%s\n' "${CONF_IPSET_VALUE}" ;;
		*) return 1 ;;
	esac
}

ai_have_cmd() {
	[ "$1" = ipset ] && [ "${HAVE_IPSET}" = "1" ]
}

IPSET_LIST_LOG="${TEST_DIR}/ipset-list.log"

ipset() {
	[ "$1" = list ] || fail "unexpected ipset action: $*"
	printf '%s\n' "$2" >>"${IPSET_LIST_LOG}"
	case "$2" in
		VPN4) printf '%s\n' 'Name: VPN4' 'Header: family inet hashsize 1024 maxelem 65536' ;;
		VPN6) printf '%s\n' 'Name: VPN6' 'Header: family inet6 hashsize 1024 maxelem 65536' ;;
		BAD4) printf '%s\n' 'Name: BAD4' 'Header: family inet6 hashsize 1024 maxelem 65536' ;;
		BAD6) printf '%s\n' 'Name: BAD6' 'Header: family inet hashsize 1024 maxelem 65536' ;;
		UNKNOWN) printf '%s\n' 'Name: UNKNOWN' 'Header: family custom hashsize 1024 maxelem 65536' ;;
		*) return 1 ;;
	esac
}

mkdir -p "${TEST_DIR}" || fail 'could not create test directory'
TARG_DIR="${TEST_DIR}"
YAML_FILE="${TEST_DIR}/AdGuardHome.yaml"
cat >"${YAML_FILE}" <<EOF_YAML
dns:
  ipset_file: ${TEST_DIR}/ipset.conf
EOF_YAML
cat >"${TEST_DIR}/ipset.user" <<EOF_USER
example.com/VPN4,VPN6
bad.example/BAD4,BAD6
missing.example/MISSING4,MISSING6
streaming.example/VPN4,BAD6
unknown.example/UNKNOWN
EOF_USER
printf '%s\n' 'generated.example/VPN4,VPN6' >"${TEST_DIR}/ipset.conf"

ipset_status >"${OUTPUT_FILE}" || fail 'ipset status failed'

grep -q 'IPSET integration enabled: YES' "${OUTPUT_FILE}" || fail 'enabled state was not reported'
grep -q 'AdGuardHome.yaml managed dns.ipset_file: YES' "${OUTPUT_FILE}" || fail 'managed YAML ipset_file was not reported'
grep -q "IPSET file exists: ${TEST_DIR}/ipset.user" "${OUTPUT_FILE}" || fail 'ipset.user existence was not reported'
grep -q "IPSET file exists: ${TEST_DIR}/ipset.conf" "${OUTPUT_FILE}" || fail 'ipset.conf existence was not reported'
grep -q 'IPSET set exists: VPN4 (family inet)' "${OUTPUT_FILE}" || fail 'IPv4 set existence was not reported'
grep -q 'IPSET set exists: VPN6 (family inet6)' "${OUTPUT_FILE}" || fail 'IPv6 set existence was not reported'
grep -q 'IPSET set exists: BAD4 (family inet6)' "${OUTPUT_FILE}" || fail 'inet6 set existence was not reported'
grep -q 'IPSET set exists: BAD6 (family inet)' "${OUTPUT_FILE}" || fail 'second IPv4 set existence was not reported'
grep -q 'IPv4 set-family check: VPN4 OK (family inet)' "${OUTPUT_FILE}" || fail 'IPv4 OK status was not reported'
grep -q 'IPv6 set-family check: VPN6 OK (family inet6)' "${OUTPUT_FILE}" || fail 'IPv6 OK status was not reported'
grep -q 'IPv4 set-family mismatch likely: VPN6 uses family inet6' "${OUTPUT_FILE}" || fail 'IPv4 mismatch was not reported for inet6 set'
grep -q 'IPv6 set-family mismatch likely: VPN4 uses family inet' "${OUTPUT_FILE}" || fail 'IPv6 mismatch was not reported for inet set'
grep -q 'IPSET set missing: MISSING4' "${OUTPUT_FILE}" || fail 'missing set was not reported'
grep -q 'IPSET set missing: MISSING6' "${OUTPUT_FILE}" || fail 'second missing set was not reported'
grep -q 'IPSET set exists with unknown family: UNKNOWN (family custom)' "${OUTPUT_FILE}" || fail 'unknown set family was not reported'
grep -q 'IPv4 set-family check unknown: UNKNOWN uses family custom' "${OUTPUT_FILE}" || fail 'IPv4 unknown family status was not reported'
grep -q 'IPv6 set-family check unknown: UNKNOWN uses family custom' "${OUTPUT_FILE}" || fail 'IPv6 unknown family status was not reported'
[ "$(grep -c '^VPN4$' "${IPSET_LIST_LOG}")" -eq 1 ] || fail 'duplicate VPN4 references were probed more than once'
[ "$(grep -c '^VPN6$' "${IPSET_LIST_LOG}")" -eq 1 ] || fail 'duplicate VPN6 references were probed more than once'


# Disabled integration, unmanaged YAML, missing generated file, no set references,
# and unavailable router-stock ipset should all remain read-only and diagnostic-only.
CONF_IPSET_VALUE="NO"
HAVE_IPSET="0"
rm -f "${IPSET_LIST_LOG}" "${TEST_DIR}/ipset.conf" "${TEST_DIR}/ipset.user"
cat >"${YAML_FILE}" <<EOF_UNMANAGED
dns:
  ipset_file: custom-ipset.conf
EOF_UNMANAGED

ipset_status >"${OUTPUT_FILE}" || fail 'ipset status failed for disabled unmanaged configuration'

grep -q 'IPSET integration enabled: NO' "${OUTPUT_FILE}" || fail 'disabled state was not reported'
grep -q "AdGuardHome.yaml dns.ipset_file is not installer-managed: ${TEST_DIR}/custom-ipset.conf" "${OUTPUT_FILE}" || fail 'unmanaged YAML ipset_file was not reported'
grep -q "IPSET file missing: ${TEST_DIR}/ipset.user" "${OUTPUT_FILE}" || fail 'missing ipset.user was not reported'
grep -q "IPSET file missing: ${TEST_DIR}/ipset.conf" "${OUTPUT_FILE}" || fail 'missing ipset.conf was not reported'
grep -q 'router-stock ipset command unavailable; set existence and family checks skipped.' "${OUTPUT_FILE}" || fail 'unavailable router-stock ipset was not reported'
[ ! -f "${IPSET_LIST_LOG}" ] || fail 'ipset was probed when command availability check failed'

CONF_IPSET_VALUE=""
HAVE_IPSET="1"
printf '%s\n' 'no-slash-entry' '# comment only' >"${TEST_DIR}/ipset.user"
ipset_status >"${OUTPUT_FILE}" || fail 'ipset status failed for default empty-reference configuration'
grep -q 'IPSET integration enabled: YES (default)' "${OUTPUT_FILE}" || fail 'default enabled state was not reported'
grep -q 'No IPSET set references found in installer-managed IPSET files.' "${OUTPUT_FILE}" || fail 'empty set-reference path was not reported'

printf '%s\n' 'PASS: installer ipset status reports managed files, set existence, and set families'
