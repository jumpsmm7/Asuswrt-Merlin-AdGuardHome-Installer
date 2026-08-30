#!/bin/sh
# Verify option 8 stops before restart when the IPSET preference cannot be saved.

set -u

SCRIPT_PATH="${1:-installer}"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"

IPSET_ALLOWED_FUNCTION="$(sed -n '/^adguard_ipset_allowed() {$/,/^}$/p' "${SCRIPT_PATH}")"
CHECK_IPSET_FUNCTION="$(sed -n '/^check_ipset() {$/,/^}$/p' "${SCRIPT_PATH}")"
MENU_FUNCTION="$(sed -n '/^menu() {$/,/^read_input_dns() {$/p' "${SCRIPT_PATH}" | sed '$d')"

[ -n "${IPSET_ALLOWED_FUNCTION}" ] || fail 'could not extract adguard_ipset_allowed function'
[ -n "${CHECK_IPSET_FUNCTION}" ] || fail 'could not extract check_ipset function'
[ -n "${MENU_FUNCTION}" ] || fail 'could not extract menu function'

eval "${IPSET_ALLOWED_FUNCTION}"
eval "${CHECK_IPSET_FUNCTION}"
eval "${MENU_FUNCTION}"

# check_ipset is the final persistence guard and must not accept an enable
# request unless the mode is WAN or LAN with qualifying WAN NAT state.
CHECK_IPSET_LOG="${TMPDIR:-/tmp}/installer-ipset-check-guard.$$"
trap 'rm -f "${CHECK_IPSET_LOG}"' EXIT HUP INT TERM
# write_conf writes a configuration key and value to the IPSET check log.
write_conf() {
	printf '%s=%s\n' "$1" "$2" >"${CHECK_IPSET_LOG}"
}
# wan_iptables_state_active determines whether WAN NAT is active.
wan_iptables_state_active() {
	[ "${WAN_NAT_ACTIVE:-0}" -eq 1 ]
}
ADGUARD_INSTALL_MODE='lan'
WAN_NAT_ACTIVE=0
check_ipset 1 || fail 'LAN-mode IPSET enable guard failed to persist the forced disabled state'
[ "$(cat "${CHECK_IPSET_LOG}")" = 'ADGUARD_IPSET="NO"' ] || fail 'LAN-mode check_ipset enable request did not force ADGUARD_IPSET=NO'
WAN_NAT_ACTIVE=1
check_ipset 1 || fail 'LAN double-NAT IPSET enable request failed'
[ "$(cat "${CHECK_IPSET_LOG}")" = 'ADGUARD_IPSET="YES"' ] || fail 'LAN double-NAT check_ipset enable request was not preserved'
unset ADGUARD_INSTALL_MODE
# conf_value returns a failure status.
conf_value() {
	return 1
}
check_ipset 1 || fail 'unknown-mode IPSET enable guard failed to persist the forced disabled state'
[ "$(cat "${CHECK_IPSET_LOG}")" = 'ADGUARD_IPSET="NO"' ] || fail 'unknown-mode check_ipset enable request did not force ADGUARD_IPSET=NO'
ADGUARD_INSTALL_MODE='wan'
check_ipset 1 || fail 'WAN-mode IPSET enable request failed'
[ "$(cat "${CHECK_IPSET_LOG}")" = 'ADGUARD_IPSET="YES"' ] || fail 'WAN-mode check_ipset enable request was not preserved'
WAN_NAT_ACTIVE=0
rm -f "${CHECK_IPSET_LOG}"

INFO='Info:'
ERROR='Error:'
TARG_DIR='/tmp/unused'
AGH_FILE='/tmp/unused/AdGuardHome'
BASE_DIR='/tmp/unused'
HOME='/tmp/unused'
SCRIPT_LOC='/tmp/unused/installer'
BRANCH='test'
ADGUARD_INSTALL_MODE='wan'

for ANSWER in yes no; do
	LOG="${TMPDIR:-/tmp}/installer-ipset-save-failure.${ANSWER}.$$"
	SERVICE_LOG="${LOG}.service"
	END_LOG="${LOG}.end"
	: >"${LOG}"
	: >"${SERVICE_LOG}"
	: >"${END_LOG}"

	read_yesno() {
		[ "${ANSWER}" = 'yes' ]
	}
	write_conf() {
		return 1
	}
	service() {
		printf '%s\n' "$*" >>"${SERVICE_LOG}"
	}
	PTXT() {
		printf '%s\n' "$*" >>"${LOG}"
	}
	end_op_message() {
		printf '%s\n' "$1" >>"${END_LOG}"
	}

	if menu setipset; then
		fail "option 8 succeeded after the ${ANSWER} preference failed to save"
	fi
	[ ! -s "${SERVICE_LOG}" ] || fail "option 8 restarted AdGuardHome after the ${ANSWER} preference failed to save"
	[ "$(cat "${END_LOG}")" = '1' ] || fail "option 8 did not report an aborted operation after the ${ANSWER} preference failed to save"
	grep -q 'Unable to save the AdGuardHome IPSET integration setting' "${LOG}" || fail "option 8 did not explain the ${ANSWER} preference save failure"
	grep -q 'AdGuardHome was not restarted' "${LOG}" || fail "option 8 did not explain that restart was skipped after the ${ANSWER} preference save failure"

	rm -f "${LOG}" "${SERVICE_LOG}" "${END_LOG}"
done

LOG="${TMPDIR:-/tmp}/installer-ipset-lan-mode.$$"
SERVICE_LOG="${LOG}.service"
END_LOG="${LOG}.end"
CONF_LOG="${LOG}.conf"
: >"${LOG}"
: >"${SERVICE_LOG}"
: >"${END_LOG}"
: >"${CONF_LOG}"
ADGUARD_INSTALL_MODE='lan'
# read_yesno fails the test if LAN-mode option 8 prompts for IPSET integration.
read_yesno() {
	fail 'LAN-mode option 8 should not prompt for IPSET integration'
}
# write_conf appends a configuration key-value pair to the configuration log.
write_conf() {
	printf '%s=%s\n' "$1" "$2" >>"${CONF_LOG}"
}
# service appends the provided arguments as a single line to the service log.
service() {
	printf '%s\n' "$*" >>"${SERVICE_LOG}"
}
# PTXT appends the provided text to the log file.
PTXT() {
	printf '%s\n' "$*" >>"${LOG}"
}
# end_op_message writes the operation status message to the end-operation log.
end_op_message() {
	printf '%s\n' "$1" >>"${END_LOG}"
}

if menu setipset; then
	fail 'LAN-mode option 8 succeeded instead of refusing IPSET changes'
fi
grep -q '^ADGUARD_IPSET="NO"$' "${CONF_LOG}" || fail 'LAN-mode option 8 did not persist ADGUARD_IPSET=NO'
grep -q 'IPSET integration is disabled in LAN/AP/Bridge mode' "${LOG}" || fail 'LAN-mode option 8 did not explain refusal'
[ ! -s "${SERVICE_LOG}" ] || fail 'LAN-mode option 8 restarted AdGuardHome'
[ "$(cat "${END_LOG}")" = '1' ] || fail 'LAN-mode option 8 did not report aborted operation'
rm -f "${LOG}" "${SERVICE_LOG}" "${END_LOG}" "${CONF_LOG}"

printf '%s\n' 'PASS: option 8 stops when IPSET cannot be saved and refuses LAN-mode IPSET changes'
