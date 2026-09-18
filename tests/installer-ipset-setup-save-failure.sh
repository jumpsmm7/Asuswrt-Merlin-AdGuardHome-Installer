#!/bin/sh
# Verify optional IPSET preference failures do not abort installation or reconfiguration.

set -u

SCRIPT_PATH="${1:-installer}"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"

RUNTIME_DEFAULT_FUNCTIONS="$(sed -n '/^conf_value() {$/,/^md5_is_valid() {$/p' "${SCRIPT_PATH}" | sed '$d')"
INSTALL_MODE_FUNCTIONS="$(sed -n '/^ipv4_is_valid() {$/,/^preflight_action_requires_firewall_tools() {$/p' "${SCRIPT_PATH}" | sed '$d')"
LOCK_OWNER_FUNCTIONS="$(sed -n '/^nvram_transaction_lock_owned() {$/,/^nvram_transaction_lock_owner_live() {$/p' "${SCRIPT_PATH}" | sed '$d')"
SETUP_FUNCTIONS="$(sed -n '/^setup_AdGuardHome() {$/,/^setup_amtmupdate() {$/p' "${SCRIPT_PATH}" | sed '$d')"
[ -n "${RUNTIME_DEFAULT_FUNCTIONS}" ] || fail 'could not extract runtime default functions'
[ -n "${INSTALL_MODE_FUNCTIONS}" ] || fail 'could not extract install mode functions'
[ -n "${LOCK_OWNER_FUNCTIONS}" ] || fail 'could not extract transaction lock ownership functions'
[ -n "${SETUP_FUNCTIONS}" ] || fail 'could not extract setup functions'
eval "${RUNTIME_DEFAULT_FUNCTIONS}"
eval "${INSTALL_MODE_FUNCTIONS}"
eval "${LOCK_OWNER_FUNCTIONS}"
eval "${SETUP_FUNCTIONS}"

# setup_files_begin_if_needed reuses a journal already owned by this installer
# process instead of aborting LAN setup before YAML configuration begins.
(
	SETUP_FILES_JOURNALED=0
	NVRAM_TRANSACTION_LOCK_MODE="mkdir"
	BASE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/installer-ipset-existing-journal.XXXXXX")" || fail 'could not create active-journal test directory'
	trap 'rm -rf "${BASE_DIR}"' 0
	mkdir -p "${BASE_DIR}/.AdGuardHome.nvram/setup-files" || fail 'could not create active-journal fixture directory'
	mkdir -p "${BASE_DIR}/.AdGuardHome.nvram.lock.d" || fail 'could not create active lock fixture directory'
	nvram_transaction_lock_owner_current >"${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid" || fail 'could not record active lock owner'
	# nvram_transaction_setup_files_begin rejects attempts to replace the active setup journal.
	nvram_transaction_setup_files_begin() { fail 'attempted to replace the active setup journal'; }
	setup_files_begin_if_needed || fail 'could not reuse the active setup journal'
	[ "${SETUP_FILES_JOURNALED}" -eq 1 ] || fail 'active setup journal was not recorded in the current setup frame'
) || fail 'active setup journal subshell failed'

# A stale lock-mode value must not permit reuse when the current process no
# longer owns the transaction lock.
(
	SETUP_FILES_JOURNALED=0
	NVRAM_TRANSACTION_LOCK_MODE="mkdir"
	BASE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/installer-ipset-stale-journal.XXXXXX")" || fail 'could not create stale-journal test directory'
	trap 'rm -rf "${BASE_DIR}"' 0
	mkdir -p "${BASE_DIR}/.AdGuardHome.nvram/setup-files" || fail 'could not create stale-journal fixture directory'
	mkdir -p "${BASE_DIR}/.AdGuardHome.nvram.lock.d" || fail 'could not create stale lock fixture directory'
	printf '%s\n' '1:1' >"${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid" || fail 'could not record stale lock owner'
	SETUP_FILES_BEGIN_CALLED=0
	# nvram_transaction_setup_files_begin begins the NVRAM transaction for setup files and signals failure.
	nvram_transaction_setup_files_begin() {
		SETUP_FILES_BEGIN_CALLED=1
		return 1
	}
	if setup_files_begin_if_needed; then
		fail 'reused a setup journal without owning the transaction lock'
	fi
	[ "${SETUP_FILES_BEGIN_CALLED}" -eq 0 ] || fail 'attempted to replace the stale setup journal'
	[ "${SETUP_FILES_JOURNALED}" -eq 0 ] || fail 'recorded an unowned setup journal in the current setup frame'
) || fail 'stale setup journal subshell failed'

# rollback_result_write records the outcome of a rollback operation.
rollback_result_write() { :; }
rollback_result_notice() { :; }

INFO='Info:'
ERROR='Error:'
WARNING='Warning:'
TMP_ROOT="${TMPDIR:-/tmp}/installer-ipset-setup-save-failure.$$"
BASE_DIR="${TMP_ROOT}/base"
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

# nvram prints `1` for `get:dns_local_cache` requests and produces no output for other requests.
nvram() {
	case "$1:${2:-}" in
		get:dns_local_cache) printf '%s\n' '1' ;;
		get:lan_domain) printf '%s\n' '' ;;
		get:lan_gateway | get:lan_ipaddr) printf '%s\n' '192.168.1.1' ;;
		get:lan_ifname) printf '%s\n' 'br0' ;;
		get:ipv6_rtr_addr) printf '%s\n' '' ;;
		get:sw_mode) printf '%s\n' "${TEST_SW_MODE:-1}" ;;
		get:wan_ipaddr) printf '%s\n' '192.168.50.2' ;;
	esac
}
# ai_have_cmd reports that optional router commands are unavailable in this fixture.
ai_have_cmd() { return 1; }
# ipv4_is_valid accepts the LAN and private WAN addresses used by this fixture.
ipv4_is_valid() {
	case "$1" in
		192.168.1.1 | 192.168.50.2) return 0 ;;
		*) return 1 ;;
	esac
}
# check_dns_filter checks the current DNS filter settings.
check_dns_filter() { :; }
# save_dns_filter_settings creates the directory specified by its argument.
save_dns_filter_settings() { mkdir -p "$1"; }
# installer_lan_domain_set writes the specified LAN domain to NVRAM.
installer_lan_domain_set() { nvram set "lan_domain=$1"; }
# installer_lan_domain_restore preserves the installer LAN domain setting.
installer_lan_domain_restore() { :; }
# nvram_transaction_finalize_setup_pair finalizes the NVRAM setup transaction successfully.
nvram_transaction_finalize_setup_pair() { return 0; }
# nvram_transaction_setup_committed reports whether the setup commit marker exists.
nvram_transaction_setup_committed() { [ -f "${BASE_DIR}/.AdGuardHome.nvram/setup-committed" ]; }
# nvram_transaction_setup_files_begin begins the NVRAM setup-file transaction successfully.
nvram_transaction_setup_files_begin() { return 0; }
# nvram_transaction_setup_files_restore restores setup transaction files successfully in the test harness.
nvram_transaction_setup_files_restore() { return 0; }
# restore_dns_filter_settings removes the specified DNS filter settings directory and its contents.
restore_dns_filter_settings() { rm -rf "$1"; }
# check_dns_local is a test stub for the DNS locality check.
check_dns_local() { :; }
# check_ipset records an optional selection and simulates a preference-save failure.
check_ipset() {
	[ -z "${IPSET_SELECTION_LOG:-}" ] || printf '%s\n' "$1" >>"${IPSET_SELECTION_LOG}"
	return 1
}
# check_AdGuardHome_yaml verifies that YAML validation is enabled for the test harness.
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
ptxt_phase() { PTXT "$1"; }
ptxt_step() { PTXT "$1"; }
ptxt_ok() { PTXT "$1"; }
ptxt_warn() { PTXT "$1"; }
ptxt_fail() { PTXT "$1"; }
end_op_message() {
	printf '%s\n' "$1" >>"${END_LOG}"
}

ALLOW_INITIAL_CONFIG=1
ALLOW_YAML_VALIDATION=1

# Exercise the complete LAN install path with a setup journal created by an
# earlier stage of the same installer process. The check_ipset boundary must
# reuse that owned journal and continue through YAML generation.
LOG="${TMP_ROOT}/install.lan-owned-journal.log"
RESTART_LOG="${LOG}.restart"
END_LOG="${LOG}.end"
IPSET_SELECTION_LOG="${LOG}.ipset-selection"
: >"${LOG}"
: >"${RESTART_LOG}"
: >"${END_LOG}"
: >"${IPSET_SELECTION_LOG}"
mkdir -p "${BASE_DIR}/.AdGuardHome.nvram/setup-files" || fail 'could not create installer-owned LAN setup journal'
mkdir -p "${BASE_DIR}/.AdGuardHome.nvram.lock.d" || fail 'could not create installer-owned LAN lock directory'
nvram_transaction_lock_owner_current >"${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid" || fail 'could not record installer-owned LAN lock owner'
NVRAM_TRANSACTION_LOCK_MODE="mkdir"
nvram_transaction_setup_files_begin() { fail 'LAN installation attempted to replace its owned setup journal'; }
TEST_SW_MODE=3
ADGUARD_INSTALL_MODE=
PREFLIGHT_INSTALL_MODE_DETECTED=0
adguard_install_mode_detect_once
[ "${ADGUARD_INSTALL_MODE}" = lan ] || fail 'non-router sw_mode was not detected as LAN/AP/bridge mode'
ADGUARD_LAN_REVERSE_UPSTREAM=192.168.1.1
BOOTSTRAP1=
BOOTSTRAP2=
setup_AdGuardHome '' install || fail 'LAN installation did not reuse its installer-owned setup journal'
[ "$(cat "${IPSET_SELECTION_LOG}")" = 0 ] || fail 'LAN installation did not keep IPSET disabled'
grep -q 'Unable to save the optional AdGuardHome IPSET integration setting' "${LOG}" || fail 'LAN installation did not exercise the optional IPSET preference failure'
grep -q 'Continuing setup with the previous or default IPSET preference' "${LOG}" || fail 'LAN installation did not continue after the optional IPSET preference failure'
[ -f "${YAML_FILE}" ] || fail 'LAN installation did not proceed into YAML generation with its owned setup journal'
if grep -q 'Unable to journal the current installer configuration before check_ipset' "${LOG}"; then
	fail 'LAN installation rejected its installer-owned setup journal before check_ipset'
fi
rm -rf "${BASE_DIR}/.AdGuardHome.nvram" "${YAML_FILE}" "${YAML_ORI}" "${YAML_BAK}"
nvram_transaction_setup_files_begin() { return 0; }
TEST_SW_MODE=1
ADGUARD_INSTALL_MODE=
PREFLIGHT_INSTALL_MODE_DETECTED=0
adguard_install_mode_detect_once
[ "${ADGUARD_INSTALL_MODE}" = wan ] || fail 'router sw_mode was not detected as WAN mode'
WAN_IPADDR="$(nvram get wan_ipaddr)"
if (PTXT() { printf '%s\n' "$1"; }; ipv4_is_private "${WAN_IPADDR}"); then NAT_ENV="${WAN_IPADDR}"; else NAT_ENV=""; fi
[ "${NAT_ENV}" = "${WAN_IPADDR}" ] || fail 'private router WAN address was not classified as double NAT'
ADGUARD_LAN_REVERSE_UPSTREAM=
IPSET_SELECTION_LOG=

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
