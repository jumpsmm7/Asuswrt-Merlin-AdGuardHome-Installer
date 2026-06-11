#!/bin/sh
# Verify YAML null scalars leave dns.ipset_file unset without hiding quoted paths.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
FUNCTION_FILE="${TMPDIR:-/tmp}/ipset-current-file-function.$$"
YAML_FIXTURE="${TMPDIR:-/tmp}/ipset-current-file-config.$$"

cleanup() {
	rm -f "${FUNCTION_FILE}" "${YAML_FIXTURE}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

sed -n '/^IPSet_Current_File() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" || fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTION_FILE}" ] || fail 'IPSet_Current_File was not found'

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"
YAML_FILE="${YAML_FIXTURE}"

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

assert_current_file '~' ''
assert_current_file 'null' ''
assert_current_file 'Null # unset' ''
assert_current_file 'NULL' ''
assert_current_file '"null"' 'null'
assert_current_file "'~'" '~'
assert_current_file '/opt/etc/AdGuardHome/ipset.conf # managed' '/opt/etc/AdGuardHome/ipset.conf'

printf '%s\n' 'PASS: IPSet_Current_File handles YAML null scalars as unset'
