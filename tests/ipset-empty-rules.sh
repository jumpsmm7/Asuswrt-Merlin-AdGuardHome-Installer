#!/bin/sh
# Verify empty managed IPSET data disables the YAML integration without failing setup.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
FUNCTION_FILE="${TMPDIR:-/tmp}/ipset-empty-functions.$$"
TEST_DIR="${TMPDIR:-/tmp}/ipset-empty-test.$$"

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

sed -n '/^IPSet_Refresh_Locked() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" || fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTION_FILE}" ] || fail 'IPSet_Refresh_Locked was not found'

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

IPSet_Current_File() {
	printf '%s\n' "${CURRENT_FILE:-}"
}

IPSet_Collect_Dnsmasq() {
	[ -z "${DNSMASQ_RULES:-}" ] || printf '%s\n' "${DNSMASQ_RULES}"
}

IPSet_Disable_Managed() {
	DISABLE_CALLS="$((DISABLE_CALLS + 1))"
	return 0
}

logger() {
	:
}

mkdir -p "${TEST_DIR}" || fail 'could not create test directory'
IPSET_FILE="${TEST_DIR}/ipset.conf"
IPSET_USER_FILE="${TEST_DIR}/ipset.user"
IPSET_REFRESH_CONFIG=""
NAME=AdGuardHome
CURRENT_FILE=""
DISABLE_CALLS=0
IPSET_REFRESH_CHANGED=""

IPSet_Refresh_Locked || fail 'empty refresh failed'
[ "${DISABLE_CALLS}" -eq 1 ] || fail 'empty refresh did not disable managed YAML'
[ "${IPSET_REFRESH_CHANGED}" = 1 ] || fail 'empty refresh did not request a service restart'
[ ! -e "${IPSET_FILE}" ] || fail 'empty generated IPSET file was retained'

printf '%s\n' 'example.com/ROUTE_VPN' >"${IPSET_USER_FILE}"
DISABLE_CALLS=0
IPSET_REFRESH_CHANGED=""
IPSet_Refresh_Locked || fail 'rule refresh failed'
[ "${DISABLE_CALLS}" -eq 0 ] || fail 'non-empty refresh disabled managed YAML'
[ "${IPSET_REFRESH_CHANGED}" = 1 ] || fail 'non-empty refresh did not report a changed file'
grep -q '^example.com/ROUTE_VPN$' "${IPSET_FILE}" || fail 'generated IPSET rule is missing'

printf '%s\n' 'PASS: empty IPSET data disables managed integration and valid rules remain enabled'
