#!/bin/sh
# Verify read-only installer IPSET status reports managed files and set-family mismatches.

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

conf_value() {
	case "$1" in
		ADGUARD_IPSET) printf '%s\n' YES ;;
		*) return 1 ;;
	esac
}

ai_have_cmd() {
	[ "$1" = ipset ]
}

ipset() {
	[ "$1" = list ] || fail "unexpected ipset action: $*"
	case "$2" in
		VPN4) printf '%s\n' 'Name: VPN4' 'Header: family inet hashsize 1024 maxelem 65536' ;;
		VPN6) printf '%s\n' 'Name: VPN6' 'Header: family inet6 hashsize 1024 maxelem 65536' ;;
		BAD4) printf '%s\n' 'Name: BAD4' 'Header: family inet6 hashsize 1024 maxelem 65536' ;;
		BAD6) printf '%s\n' 'Name: BAD6' 'Header: family inet hashsize 1024 maxelem 65536' ;;
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
EOF_USER
printf '%s\n' 'generated.example/VPN4,VPN6' >"${TEST_DIR}/ipset.conf"

ipset_status >"${OUTPUT_FILE}" || fail 'ipset status failed'

grep -q 'IPSET integration enabled: YES' "${OUTPUT_FILE}" || fail 'enabled state was not reported'
grep -q 'AdGuardHome.yaml managed dns.ipset_file: YES' "${OUTPUT_FILE}" || fail 'managed YAML ipset_file was not reported'
grep -q "IPSET file exists: ${TEST_DIR}/ipset.user" "${OUTPUT_FILE}" || fail 'ipset.user existence was not reported'
grep -q "IPSET file exists: ${TEST_DIR}/ipset.conf" "${OUTPUT_FILE}" || fail 'ipset.conf existence was not reported'
grep -q 'IPv4 set exists: VPN4 (family inet)' "${OUTPUT_FILE}" || fail 'IPv4 set existence was not reported'
grep -q 'IPv6 set exists: VPN6 (family inet6)' "${OUTPUT_FILE}" || fail 'IPv6 set existence was not reported'
grep -q 'IPv4 set family mismatch likely: BAD4 (family inet6)' "${OUTPUT_FILE}" || fail 'IPv4 family mismatch was not reported'
grep -q 'IPv6 set family mismatch likely: BAD6 (family inet)' "${OUTPUT_FILE}" || fail 'IPv6 family mismatch was not reported'
grep -q 'IPv4 set missing: MISSING4' "${OUTPUT_FILE}" || fail 'missing IPv4 set was not reported'
grep -q 'IPv6 set missing: MISSING6' "${OUTPUT_FILE}" || fail 'missing IPv6 set was not reported'

printf '%s\n' 'PASS: installer ipset status reports managed files, set existence, and family mismatches'
