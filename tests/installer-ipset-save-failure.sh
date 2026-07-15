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
read_yesno() {
	fail 'LAN-mode option 8 should not prompt for IPSET integration'
}
write_conf() {
	printf '%s=%s\n' "$1" "$2" >>"${CONF_LOG}"
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
	fail 'LAN-mode option 8 succeeded instead of refusing IPSET changes'
fi
grep -q '^ADGUARD_IPSET="NO"$' "${CONF_LOG}" || fail 'LAN-mode option 8 did not persist ADGUARD_IPSET=NO'
grep -q 'IPSET integration is disabled in LAN/AP/Bridge mode' "${LOG}" || fail 'LAN-mode option 8 did not explain refusal'
[ ! -s "${SERVICE_LOG}" ] || fail 'LAN-mode option 8 restarted AdGuardHome'
[ "$(cat "${END_LOG}")" = '1' ] || fail 'LAN-mode option 8 did not report aborted operation'
rm -f "${LOG}" "${SERVICE_LOG}" "${END_LOG}" "${CONF_LOG}"

printf '%s\n' 'PASS: option 8 stops when IPSET cannot be saved and refuses LAN-mode IPSET changes'
