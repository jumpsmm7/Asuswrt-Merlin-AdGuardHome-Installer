#!/bin/sh
# Verify option 7 stops when branch selection is canceled.

set -u

SCRIPT_PATH="${1:-installer}"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"

CHOOSE_BRANCH_FUNCTION="$(sed -n '/^choose_branch() {$/,/^}$/p' "${SCRIPT_PATH}")"
MENU_FUNCTION="$(sed -n '/^menu() {$/,/^read_input_dns() {$/p' "${SCRIPT_PATH}" | sed '$d')"

[ -n "${CHOOSE_BRANCH_FUNCTION}" ] || fail 'could not extract choose_branch function'
[ -n "${MENU_FUNCTION}" ] || fail 'could not extract menu function'

eval "${CHOOSE_BRANCH_FUNCTION}"
eval "${MENU_FUNCTION}"

INFO='Info:'
TARG_DIR='/tmp/unused'
AGH_FILE='/tmp/unused/AdGuardHome'
BASE_DIR='/tmp/unused'
HOME='/tmp/unused'
SCRIPT_LOC='/tmp/unused/installer'
BRANCH='test'
CONF_FILE="${TMPDIR:-/tmp}/installer-branch-switch-cancel.$$.conf"
LOG="${CONF_FILE}.log"
INSTALL_LOG="${CONF_FILE}.install"
END_LOG="${CONF_FILE}.end"
printf '%s\n' 'ADGUARD_BRANCH="release"' >"${CONF_FILE}"
: >"${LOG}"
: >"${INSTALL_LOG}"
: >"${END_LOG}"

PROMPT_COUNT=0
read_yesno() {
	PROMPT_COUNT=$((PROMPT_COUNT + 1))
	[ "${PROMPT_COUNT}" -eq 1 ]
}
conf_value() {
	[ "$1" = 'ADGUARD_BRANCH' ] && printf '%s\n' 'release'
}
PTXT() {
	printf '%s\n' "$*" >>"${LOG}"
}
inst_AdGuardHome() {
	printf '%s\n' "$*" >>"${INSTALL_LOG}"
}
end_op_message() {
	printf '%s\n' "$1" >>"${END_LOG}"
}

if menu switchbranch; then
	fail 'option 7 succeeded after branch selection was canceled'
fi
[ "${PROMPT_COUNT}" -eq 2 ] || fail 'option 7 did not ask for confirmation and branch selection'
[ ! -s "${INSTALL_LOG}" ] || fail 'option 7 updated AdGuardHome after branch selection was canceled'
[ "$(cat "${END_LOG}")" = '1' ] || fail 'option 7 did not report an aborted operation after branch selection was canceled'
grep -q 'continuing without changing builds' "${LOG}" || fail 'option 7 did not explain that the build was unchanged'

rm -f "${CONF_FILE}" "${LOG}" "${INSTALL_LOG}" "${END_LOG}"

printf '%s\n' 'PASS: option 7 stops when branch selection is canceled'
