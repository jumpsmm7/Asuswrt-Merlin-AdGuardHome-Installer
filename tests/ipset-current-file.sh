#!/bin/sh
# Verify dns.ipset_file scalar parsing and migration for managed IPSET integration.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
FUNCTION_FILE="${TMPDIR:-/tmp}/ipset-current-file-function.$$"
TEST_DIR="${TMPDIR:-/tmp}/ipset-current-file-test.$$"
YAML_FIXTURE="${TEST_DIR}/AdGuardHome.yaml"

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

mkdir -p "${TEST_DIR}" || fail 'could not create test directory'
sed -n '/^agh_timestamp() {$/,/^}$/p; /^agh_log() {$/,/^}$/p; /^IPSet_Current_File() {$/,/^}$/p; /^IPSet_Migrate() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" || fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTION_FILE}" ] || fail 'IPSET scalar functions were not found'

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"
YAML_FILE="${YAML_FIXTURE}"
IPSET_FILE="${TEST_DIR}/ipset.conf"
IPSET_USER_FILE="${TEST_DIR}/ipset.user"
NAME=AdGuardHome

logger() {
	:
}

# adguard_lan_mode reports whether the installation is configured for LAN mode.
adguard_lan_mode() {
	[ "${INSTALL_MODE:-wan}" = "lan" ]
}

# IPSet_Disable_Managed records that managed IP set handling was disabled for the test.
IPSet_Disable_Managed() {
	printf '%s\n' disabled >"${TEST_DIR}/disabled"
	return 0
}

# IPSet_Collect_Yaml collects IP set configuration from the YAML file.
IPSet_Collect_Yaml() {
	return 0
}

assert_current_file() {
	_value="$1"
	_expected="$2"
	cat >"${YAML_FILE}" <<EOF_YAML
dns:
  ipset_file: ${_value}
EOF_YAML

	_actual="$(IPSet_Current_File)" || fail "parser rejected ipset_file: ${_value}"
	[ "${_actual}" = "${_expected}" ] || fail "ipset_file: ${_value} returned '${_actual}', expected '${_expected}'"
}

assert_block_file() {
	_header="$1"
	_expected="$2"
	cat >"${YAML_FILE}" <<EOF_YAML
dns:
  ipset_file: ${_header}
    ${IPSET_FILE}
EOF_YAML

	_actual="$(IPSet_Current_File)" || fail "parser rejected block scalar ${_header}"
	[ "${_actual}" = "${_expected}" ] || fail "block scalar ${_header} returned '${_actual}', expected '${_expected}'"
}

assert_current_file '~' ''
assert_current_file 'null' ''
assert_current_file 'Null # unset' ''
assert_current_file 'NULL' ''
assert_current_file '"null"' 'null'
assert_current_file "'~'" '~'
assert_current_file '/opt/etc/AdGuardHome/ipset.conf # managed' '/opt/etc/AdGuardHome/ipset.conf'
assert_block_file '>-' "${IPSET_FILE}"
assert_block_file '| # managed' "${IPSET_FILE}"
assert_block_file '>2-' "${IPSET_FILE}"
assert_block_file '|-2' "${IPSET_FILE}"

cat >"${YAML_FILE}" <<EOF_YAML
dns:
  ipset_file: >-
    ${IPSET_FILE}

  upstream_dns:
    - 1.1.1.1
EOF_YAML
_actual="$(IPSet_Current_File)" || fail 'parser rejected a block scalar with a trailing blank line'
[ "${_actual}" = "${IPSET_FILE}" ] || fail "trailing blank block scalar returned '${_actual}'"

cat >"${YAML_FILE}" <<EOF_YAML
dns:
  ipset_file: >-
    ${IPSET_FILE}
    unexpected-second-line
EOF_YAML
if IPSet_Current_File >/dev/null 2>&1; then
	fail 'multi-line ipset_file block scalar was not rejected'
fi

cat >"${YAML_FILE}" <<EOF_YAML
dns:
  ipset_file: >-
    ${IPSET_FILE}
  upstream_dns:
    - 1.1.1.1
EOF_YAML
IPSet_Migrate || fail 'migration rejected a managed block-scalar ipset_file'
_expected="$(printf '%s\n' 'dns:' '  ipset_file: '"${IPSET_FILE}" '  upstream_dns:' '    - 1.1.1.1' '  ipset: []')"
_actual="$(cat "${YAML_FILE}")"
[ "${_actual}" = "${_expected}" ] || fail "migration left block-scalar content in YAML:\n${_actual}"

INSTALL_MODE=lan
cat >"${YAML_FILE}" <<EOF_YAML
dns:
  ipset_file: ${IPSET_FILE}
EOF_YAML
rm -f "${TEST_DIR}/disabled"
IPSet_Migrate || fail 'LAN migration returned failure'
[ -f "${TEST_DIR}/disabled" ] || fail 'LAN migration did not remove managed ipset_file'
INSTALL_MODE=wan

printf '%s\n' 'PASS: IPSet_Current_File handles YAML null and block scalars safely'
