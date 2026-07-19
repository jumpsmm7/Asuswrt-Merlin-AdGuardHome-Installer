#!/bin/sh
# Verify RESTORE preserves feature choices and rejects backups without YAML.

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
grep -q '\[ ! -f "${RESTORE_TARG_DIR}/AdGuardHome.yaml" \].*\[ ! -f "${RESTORE_TARG_DIR}/.AdGuardHome.yaml.ori" \]' "${SCRIPT_PATH}" ||
	fail 'restore validation accepts a backup without either YAML file'

printf '%s\n' 'PASS: RESTORE rejects missing YAML and preserves feature selections'
