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
grep -q 'if \[ "${ADGUARD_FORCE_SETUP_YAML:-0}" = "1" \].*\[ -f "${YAML_FILE}" \].*\[ -f "${YAML_ORI}" \]' "${SCRIPT_PATH}" ||
	fail 'RESTORE does not enter mode-dependent YAML synchronization when requested'
grep -q 'setup_sync_mode_dependent_yaml_and_snapshot' "${SCRIPT_PATH}" ||
	fail 'RESTORE does not synchronize both restored YAML pathways'
grep -A6 'case "${restored_mode}" in' "${SCRIPT_PATH}" | grep -q 'write_conf ADGUARD_NETCHECK_MODE.*lan' ||
	fail 'WAN-to-LAN restore does not reset the restored WAN netcheck mode'
grep -q 'setup_sync_mode_dependent_yaml "${yaml_file_stage}"' "${SCRIPT_PATH}" &&
	grep -q 'setup_sync_mode_dependent_yaml "${yaml_ori_stage}"' "${SCRIPT_PATH}" ||
	fail 'RESTORE does not stage both restored YAML pathways before publication'
grep -q 'adguardhome_yaml_remove_ipset_file "${yaml_file_stage}"' "${SCRIPT_PATH}" &&
	grep -q 'adguardhome_yaml_remove_ipset_file "${yaml_ori_stage}"' "${SCRIPT_PATH}" ||
	fail 'RESTORE does not clear inline and file-based IPSET settings from both LAN YAML pathways'
grep -q 'mv -f "${yaml_file_rollback}" "${YAML_FILE}"' "${SCRIPT_PATH}" ||
	fail 'RESTORE does not roll back the working YAML when snapshot publication fails'

printf '%s\n' 'PASS: RESTORE rejects missing YAML, preserves feature selections, and atomically synchronizes mode-dependent YAML'
