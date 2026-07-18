#!/bin/sh
# Verify RESTORE rebuilds a missing YAML without reselecting restored features.

set -u

SCRIPT_PATH="${1:-installer}"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"

grep -q 'case "${2:-reconfig}" in' "${SCRIPT_PATH}" ||
	fail 'could not find setup feature-selection case'
grep -q '"install" | "reconfig" | "RESTORE")' "${SCRIPT_PATH}" ||
	fail 'RESTORE does not share the YAML generation branch'
grep -q 'if \[ "${2:-reconfig}" != "RESTORE" \].*\[ ! -f "${YAML_FILE}" \]' "${SCRIPT_PATH}" ||
	fail 'RESTORE does not skip interactive feature selection'
grep -q 'if { \[ ! -f "${YAML_ORI}" \] && \[ ! -f "${YAML_FILE}" \]; }' "${SCRIPT_PATH}" ||
	fail 'missing restored YAML does not enter YAML generation'

printf '%s\n' 'PASS: RESTORE rebuilds missing YAML and preserves feature selections'
