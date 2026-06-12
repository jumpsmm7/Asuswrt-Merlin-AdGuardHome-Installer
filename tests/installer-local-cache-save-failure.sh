#!/bin/sh
# Verify option 6 reports failure when the local-cache preference cannot be saved.

set -u

SCRIPT_PATH="${1:-installer}"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"

CHECK_DNS_LOCAL_FUNCTION="$(sed -n '/^check_dns_local() {$/,/^}$/p' "${SCRIPT_PATH}")"
MENU_FUNCTION="$(sed -n '/^menu() {$/,/^read_input_dns() {$/p' "${SCRIPT_PATH}" | sed '$d')"

[ -n "${CHECK_DNS_LOCAL_FUNCTION}" ] || fail 'could not extract check_dns_local function'
[ -n "${MENU_FUNCTION}" ] || fail 'could not extract menu function'

eval "${CHECK_DNS_LOCAL_FUNCTION}"
eval "${MENU_FUNCTION}"

INFO='Info:'
ERROR='Error:'
TARG_DIR='/tmp/unused'
AGH_FILE='/tmp/unused/AdGuardHome'
BASE_DIR='/tmp/unused'
HOME='/tmp/unused'
SCRIPT_LOC='/tmp/unused/installer'
BRANCH='test'

for ANSWER in yes no; do
	LOG="${TMPDIR:-/tmp}/installer-local-cache-save-failure.${ANSWER}.$$"
	END_LOG="${LOG}.end"
	: >"${LOG}"
	: >"${END_LOG}"

	nvram() {
		[ "$1:${2:-}" = 'get:dns_local_cache' ] && printf '%s\n' '0'
	}
	read_yesno() {
		[ "${ANSWER}" = 'yes' ]
	}
	write_conf() {
		return 1
	}
	PTXT() {
		printf '%s\n' "$*" >>"${LOG}"
	}
	end_op_message() {
		printf '%s\n' "$1" >>"${END_LOG}"
	}

	if menu setlocalcache; then
		fail "option 6 succeeded after the ${ANSWER} preference failed to save"
	fi
	[ "$(cat "${END_LOG}")" = '1' ] || fail "option 6 did not report an aborted operation after the ${ANSWER} preference failed to save"
	grep -q 'Unable to save the AdGuardHome local cache setting' "${LOG}" || fail "option 6 did not explain the ${ANSWER} preference save failure"
	if grep -q 'please reboot the router' "${LOG}"; then
		fail "option 6 recommended a reboot after the ${ANSWER} preference failed to save"
	fi

	rm -f "${LOG}" "${END_LOG}"
done

printf '%s\n' 'PASS: option 6 stops when the local-cache preference cannot be saved'
