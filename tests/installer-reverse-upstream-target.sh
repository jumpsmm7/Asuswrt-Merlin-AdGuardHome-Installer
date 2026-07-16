#!/bin/sh
# Verify setup reverse upstream target selection for WAN and LAN installs.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-reverse-upstream-target.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions.sh"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

cleanup() {
	rm -rf "${TMP_ROOT}"
}
trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"
mkdir -p "${TMP_ROOT}" || fail 'could not create test directory'
sed -n '/^ipv4_is_valid() {$/,/^}$/p; /^setup_reverse_upstream_target() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" ||
	fail 'could not extract reverse upstream helpers'
grep -q '^setup_reverse_upstream_target() {$' "${FUNCTIONS_FILE}" || fail 'reverse upstream helper is missing'
. "${FUNCTIONS_FILE}"

ERROR='Error:'
PTXT() {
	printf '%s\n' "$@"
}
conf_value() {
	case "$1" in
		ADGUARD_LAN_REVERSE_UPSTREAM) printf '%s\n' "${TEST_CONF_LAN_REVERSE_UPSTREAM:-}" ;;
		*) return 1 ;;
	esac
}
nvram() {
	case "$1:${2:-}" in
		get:lan_gateway) printf '%s\n' "${TEST_LAN_GATEWAY:-}" ;;
		get:lan_ipaddr) printf '%s\n' "${TEST_LAN_IPADDR:-}" ;;
	esac
}

assert_target() {
	case_name="$1"
	expected="$2"
	SETUP_REVERSE_UPSTREAM='stale-value'
	if ! setup_reverse_upstream_target; then
		fail "${case_name}: helper failed"
	fi
	[ "${SETUP_REVERSE_UPSTREAM}" = "${expected}" ] ||
		fail "${case_name}: expected ${expected}, got ${SETUP_REVERSE_UPSTREAM}"
}

ADGUARD_INSTALL_MODE='wan'
ADGUARD_LAN_REVERSE_UPSTREAM=''
TEST_LAN_GATEWAY=''
TEST_LAN_IPADDR=''
TEST_CONF_LAN_REVERSE_UPSTREAM=''
assert_target 'WAN mode' '[::]:553'

ADGUARD_INSTALL_MODE='lan'
ADGUARD_LAN_REVERSE_UPSTREAM='192.168.50.1'
TEST_LAN_GATEWAY='192.168.1.1'
TEST_LAN_IPADDR='192.168.2.1'
TEST_CONF_LAN_REVERSE_UPSTREAM='192.168.60.1'
assert_target 'LAN explicit config' '192.168.50.1:53'

ADGUARD_LAN_REVERSE_UPSTREAM=''
assert_target 'LAN persisted config' '192.168.60.1:53'

TEST_CONF_LAN_REVERSE_UPSTREAM=''
TEST_LAN_GATEWAY='192.168.1.1'
TEST_LAN_IPADDR='192.168.2.1'
assert_target 'LAN gateway fallback' '192.168.1.1:53'

TEST_LAN_GATEWAY=''
TEST_LAN_IPADDR='192.168.2.1'
assert_target 'LAN ipaddr fallback' '192.168.2.1:53'

TEST_LAN_GATEWAY='not-an-ip'
TEST_LAN_IPADDR='192.168.2.1'
SETUP_REVERSE_UPSTREAM='stale-value'
if setup_reverse_upstream_target; then
	fail 'LAN invalid gateway unexpectedly fell through to lan_ipaddr'
fi
[ "${SETUP_REVERSE_UPSTREAM}" = 'not-an-ip' ] || fail 'LAN invalid gateway was not validated directly'

ADGUARD_INSTALL_MODE='invalid'
if setup_reverse_upstream_target; then
	fail 'invalid install mode unexpectedly succeeded'
fi

printf '%s\n' 'PASS: reverse upstream target selection covers WAN and LAN pathways'
