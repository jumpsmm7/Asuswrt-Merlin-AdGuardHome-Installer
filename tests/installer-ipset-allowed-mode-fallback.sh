#!/bin/sh
# Verify installer adguard_ipset_allowed falls back to persisted config when the install mode env var is unset.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-ipset-allowed-mode-fallback.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions.sh"

# fail prints a failure message to standard error and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

# cleanup removes the temporary test workspace.
cleanup() {
	rm -rf "${TMP_ROOT}"
}
trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"
mkdir -p "${TMP_ROOT}" || fail 'could not create test directory'
sed -n '/^adguard_ipset_allowed() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" ||
	fail 'could not extract adguard_ipset_allowed'
grep -q '^adguard_ipset_allowed() {$' "${FUNCTIONS_FILE}" || fail 'adguard_ipset_allowed helper is missing'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

# conf_value returns the test-configured persisted install mode for the requested key.
conf_value() {
	case "$1" in
		ADGUARD_INSTALL_MODE) printf '%s\n' "${TEST_CONF_INSTALL_MODE:-}" ;;
		*) return 1 ;;
	esac
}

unset ADGUARD_INSTALL_MODE
TEST_CONF_INSTALL_MODE='lan'
! adguard_ipset_allowed || fail 'conf_value fallback should refuse IPSET when persisted mode is lan'

unset ADGUARD_INSTALL_MODE
TEST_CONF_INSTALL_MODE='wan'
adguard_ipset_allowed || fail 'conf_value fallback should allow IPSET when persisted mode is wan'

unset ADGUARD_INSTALL_MODE
TEST_CONF_INSTALL_MODE=''
adguard_ipset_allowed || fail 'conf_value fallback should allow IPSET when no mode is persisted'

ADGUARD_INSTALL_MODE='lan'
TEST_CONF_INSTALL_MODE='wan'
! adguard_ipset_allowed || fail 'an explicit lan env var should refuse IPSET even if persisted config says wan'

ADGUARD_INSTALL_MODE='wan'
TEST_CONF_INSTALL_MODE='lan'
adguard_ipset_allowed || fail 'an explicit wan env var should allow IPSET even if persisted config says lan'

printf '%s\n' 'PASS: installer adguard_ipset_allowed honors the env var and falls back to persisted config'