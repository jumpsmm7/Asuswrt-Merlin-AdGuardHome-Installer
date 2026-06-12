#!/bin/sh
# Verify installation and reconfiguration stop when the IPSET preference cannot be saved.

set -u

SCRIPT_PATH="${1:-installer}"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"

SETUP_FUNCTIONS="$(sed -n '/^setup_AdGuardHome() {$/,/^setup_amtmupdate() {$/p' "${SCRIPT_PATH}" | sed '$d')"
[ -n "${SETUP_FUNCTIONS}" ] || fail 'could not extract setup functions'
eval "${SETUP_FUNCTIONS}"

INFO='Info:'
ERROR='Error:'
TMP_ROOT="${TMPDIR:-/tmp}/installer-ipset-setup-save-failure.$$"
TARG_DIR="${TMP_ROOT}/target"
AGH_FILE="${TARG_DIR}/AdGuardHome"
YAML_FILE="${TMP_ROOT}/AdGuardHome.yaml"
YAML_ORI="${TMP_ROOT}/AdGuardHome.yaml.original"
YAML_BAK="${TMP_ROOT}/AdGuardHome.yaml.backup"
CONF_FILE="${TMP_ROOT}/.config"
mkdir -p "${TARG_DIR}"
cat >"${AGH_FILE}" <<'SCRIPT'
#!/bin/sh
printf '%s\n' 'AdGuard Home, version test Schema version: 27'
SCRIPT
chmod 755 "${AGH_FILE}"

cleanup() {
	rm -rf "${TMP_ROOT}"
}
trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

nvram() {
	case "$1:$2" in
		get:dns_local_cache) printf '%s\n' '1' ;;
	esac
}
check_dns_filter() { :; }
check_dns_local() { :; }
check_ipset() { return 1; }
check_AdGuardHome_yaml() {
	fail 'setup continued to YAML validation after the IPSET preference save failed'
}
read_input_port() {
	fail 'setup continued to initial configuration after the IPSET preference save failed'
}
agh_restart() {
	printf '%s\n' restart >>"${RESTART_LOG}"
}
agh_start_error() { :; }
PTXT() {
	printf '%s\n' "$*" >>"${LOG}"
}
end_op_message() {
	printf '%s\n' "$1" >>"${END_LOG}"
}

for MODE in install reconfig; do
	for ANSWER in yes no; do
		LOG="${TMP_ROOT}/${MODE}.${ANSWER}.log"
		RESTART_LOG="${LOG}.restart"
		END_LOG="${LOG}.end"
		: >"${LOG}"
		: >"${RESTART_LOG}"
		: >"${END_LOG}"

		read_yesno() {
			[ "${ANSWER}" = yes ]
		}

		if [ "${MODE}" = reconfig ]; then
			if setup_AdGuardHome reconfig reconfig; then
				fail "reconfiguration succeeded after the ${ANSWER} IPSET preference failed to save"
			fi
			[ ! -s "${RESTART_LOG}" ] || fail "reconfiguration restarted AdGuardHome after the ${ANSWER} IPSET preference failed to save"
			[ "$(cat "${END_LOG}")" = '1' ] || fail "reconfiguration did not report an aborted operation after the ${ANSWER} IPSET preference failed to save"
		else
			if setup_AdGuardHome '' install; then
				fail "installation setup succeeded after the ${ANSWER} IPSET preference failed to save"
			fi
		fi

		grep -q 'Unable to save the AdGuardHome IPSET integration setting' "${LOG}" || fail "setup did not explain the ${ANSWER} preference save failure in ${MODE} mode"
		grep -q 'Setup was aborted' "${LOG}" || fail "setup did not report that ${MODE} mode was aborted"
	done
done

printf '%s\n' 'PASS: setup stops when the IPSET preference cannot be saved'
