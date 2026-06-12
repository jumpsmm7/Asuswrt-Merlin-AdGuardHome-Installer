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
YAML_ERR="${TMP_ROOT}/AdGuardHome.yaml.error"
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
	case "$1:${2:-}" in
		get:dns_local_cache) printf '%s\n' '1' ;;
	esac
}
check_dns_filter() { :; }
check_dns_local() { :; }
check_ipset() { return 1; }
check_AdGuardHome_yaml() {
	[ "${ALLOW_YAML_VALIDATION:-0}" -eq 1 ] || fail 'setup continued to YAML validation after the IPSET preference save failed'
}
read_input_port() {
	[ "${ALLOW_INITIAL_CONFIG:-0}" -eq 1 ] || fail 'setup continued to initial configuration after the IPSET preference save failed'
	WEB_PORT=3000
}
read_input_dns() {
	if [ -z "${BOOTSTRAP1:-}" ]; then BOOTSTRAP1=9.9.9.9; else BOOTSTRAP2=8.8.8.8; fi
}
AdGuardHome_authen() { :; }
write_conf() { :; }
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

for ANSWER in yes no; do
	LOG="${TMP_ROOT}/install.${ANSWER}.log"
	RESTART_LOG="${LOG}.restart"
	END_LOG="${LOG}.end"
	: >"${LOG}"
	: >"${RESTART_LOG}"
	: >"${END_LOG}"

	read_yesno() {
		[ "${ANSWER}" = yes ]
	}

	if setup_AdGuardHome '' install; then
		fail "installation setup succeeded after the ${ANSWER} IPSET preference failed to save"
	fi

	grep -q 'Unable to save the AdGuardHome IPSET integration setting' "${LOG}" || fail "setup did not explain the ${ANSWER} preference save failure in install mode"
	grep -q 'Setup was aborted' "${LOG}" || fail "setup did not report that install mode was aborted"
done

for SELECTION in 2 3; do
	for ANSWER in yes no; do
		LOG="${TMP_ROOT}/reconfig.${SELECTION}.${ANSWER}.restore.log"
		RESTART_LOG="${LOG}.restart"
		END_LOG="${LOG}.end"
		: >"${LOG}"
		: >"${RESTART_LOG}"
		: >"${END_LOG}"
		printf '%s\n' 'working configuration' >"${YAML_FILE}"
		printf '%s\n' 'original configuration' >"${YAML_ORI}"
		rm -f "${YAML_BAK}"
		ALLOW_YAML_VALIDATION=1
		if [ "${SELECTION}" = 3 ]; then ALLOW_INITIAL_CONFIG=1; else ALLOW_INITIAL_CONFIG=0; fi
		BOOTSTRAP1=
		BOOTSTRAP2=

		read_input_num() {
			CHOSEN="${SELECTION}"
		}
		read_yesno() {
			[ "${ANSWER}" = yes ]
		}

		if setup_AdGuardHome reconfig reconfig; then
			fail "reconfiguration selection ${SELECTION} succeeded after the ${ANSWER} IPSET preference failed to save"
		fi
		[ "$(cat "${YAML_FILE}")" = 'working configuration' ] || fail "reconfiguration selection ${SELECTION} did not restore the previous YAML after the ${ANSWER} preference failed to save"
		[ ! -e "${YAML_BAK}" ] || fail "reconfiguration selection ${SELECTION} left the YAML backup behind after restoring it"
		[ ! -s "${RESTART_LOG}" ] || fail "reconfiguration selection ${SELECTION} restarted AdGuardHome after the ${ANSWER} IPSET preference failed to save"
	done
done

check_ipset() {
	printf '%s\n' "$1" >>"${IPSET_SAVE_LOG}"
	printf '%s\n' 'ADGUARD_IPSET=CHANGED' >"${CONF_FILE}"
}

for ANSWER in yes no; do
	LOG="${TMP_ROOT}/reconfig.validation.${ANSWER}.log"
	RESTART_LOG="${LOG}.restart"
	END_LOG="${LOG}.end"
	IPSET_SAVE_LOG="${LOG}.ipset-save"
	: >"${LOG}"
	: >"${RESTART_LOG}"
	: >"${END_LOG}"
	: >"${IPSET_SAVE_LOG}"
	printf '%s\n' 'working configuration' >"${YAML_FILE}"
	printf '%s\n' 'invalid replacement configuration' >"${YAML_ORI}"
	printf '%s\n' 'ADGUARD_IPSET=YES' >"${CONF_FILE}"
	rm -f "${YAML_BAK}"
	YAML_CHECKS=0

	read_input_num() {
		CHOSEN=2
	}
	read_yesno() {
		[ "${ANSWER}" = yes ]
	}
	check_AdGuardHome_yaml() {
		YAML_CHECKS="$((YAML_CHECKS + 1))"
		if [ "${YAML_CHECKS}" -eq 2 ]; then
			rm -f "${YAML_FILE}"
			return 1
		fi
	}

	if setup_AdGuardHome reconfig reconfig; then
		fail "reconfiguration succeeded after replacement YAML validation failed for the ${ANSWER} IPSET selection"
	fi
	[ ! -s "${IPSET_SAVE_LOG}" ] || fail "reconfiguration saved the ${ANSWER} IPSET selection before replacement YAML validation succeeded"
	[ "$(cat "${CONF_FILE}")" = 'ADGUARD_IPSET=YES' ] || fail "reconfiguration changed the previous IPSET preference after replacement YAML validation failed"
	[ "$(cat "${YAML_FILE}")" = 'working configuration' ] || fail "reconfiguration did not restore the previous YAML after replacement validation failed"
	[ ! -e "${YAML_BAK}" ] || fail "reconfiguration left the YAML backup behind after replacement validation failed"
	[ ! -s "${RESTART_LOG}" ] || fail "reconfiguration restarted AdGuardHome after replacement YAML validation failed"
done

printf '%s\n' 'PASS: setup defers the IPSET preference until reconfiguration validation succeeds'
