#!/bin/sh
# Verify optional IPSET preference failures do not abort installation or reconfiguration.

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
WARNING='Warning:'
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
	[ "${ALLOW_YAML_VALIDATION:-0}" -eq 1 ] || fail 'unexpected YAML validation'
}
read_input_port() {
	[ "${ALLOW_INITIAL_CONFIG:-0}" -eq 1 ] || fail 'unexpected initial configuration'
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

ALLOW_INITIAL_CONFIG=1
ALLOW_YAML_VALIDATION=1
for ANSWER in yes no; do
	LOG="${TMP_ROOT}/install.${ANSWER}.log"
	RESTART_LOG="${LOG}.restart"
	END_LOG="${LOG}.end"
	: >"${LOG}"
	: >"${RESTART_LOG}"
	: >"${END_LOG}"
	rm -f "${YAML_FILE}" "${YAML_ORI}" "${YAML_BAK}"
	BOOTSTRAP1=
	BOOTSTRAP2=

	read_yesno() {
		[ "${ANSWER}" = yes ]
	}

	setup_AdGuardHome '' install || fail "installation setup failed after the optional ${ANSWER} IPSET preference could not be saved"
	grep -q 'Unable to save the optional AdGuardHome IPSET integration setting' "${LOG}" || fail "setup did not warn about the ${ANSWER} preference save failure in install mode"
	grep -q 'Continuing setup with the previous or default IPSET preference' "${LOG}" || fail "setup did not continue without the ${ANSWER} IPSET preference"
	[ -f "${YAML_FILE}" ] || fail "installation did not create YAML after the ${ANSWER} IPSET preference save failure"
done

for SELECTION in 2 3; do
	for ANSWER in yes no; do
		LOG="${TMP_ROOT}/reconfig.${SELECTION}.${ANSWER}.continue.log"
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

		setup_AdGuardHome reconfig reconfig || fail "reconfiguration selection ${SELECTION} failed after the optional ${ANSWER} IPSET preference could not be saved"
		grep -q 'Unable to save the optional AdGuardHome IPSET integration setting' "${LOG}" || fail "reconfiguration did not warn about the ${ANSWER} preference save failure"
		grep -q 'Continuing reconfiguration with the previous IPSET preference' "${LOG}" || fail "reconfiguration did not preserve the previous IPSET preference"
		[ "$(cat "${RESTART_LOG}")" = restart ] || fail "reconfiguration did not restart AdGuardHome after the optional ${ANSWER} IPSET preference save failure"
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

printf '%s\n' 'PASS: optional IPSET preference failures do not block setup or reconfiguration'
