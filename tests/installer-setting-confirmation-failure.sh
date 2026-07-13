#!/bin/sh
# Verify menu setting toggles abort instead of treating confirmation EOF as No.

set -u

SCRIPT_PATH="${1:-installer}"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"

MENU_FUNCTION="$(sed -n '/^menu() {$/,/^read_input_dns() {$/p' "${SCRIPT_PATH}" | sed '$d')"
[ -n "${MENU_FUNCTION}" ] || fail 'could not extract menu function'
eval "${MENU_FUNCTION}"

INFO='Info:'
ERROR='Error:'
TARG_DIR='/tmp/unused'
AGH_FILE='/tmp/unused/AdGuardHome'
BASE_DIR='/tmp/unused'
HOME='/tmp/unused'
SCRIPT_LOC='/tmp/unused/installer'
BRANCH='test'
CHECK_LOG="${TMPDIR:-/tmp}/installer-setting-confirmation-failure.check.$$"
SERVICE_LOG="${CHECK_LOG}.service"
END_LOG="${CHECK_LOG}.end"
trap 'rm -f "${CHECK_LOG}" "${SERVICE_LOG}" "${END_LOG}"' 0 HUP INT TERM

read_yesno() {
	return 2
}
nvram() {
	[ "$1:${2:-}" = 'get:dns_local_cache' ] && printf '%s\n' '0'
}
check_dns_local() {
	printf '%s\n' "$*" >>"${CHECK_LOG}"
}
check_ipset() {
	printf '%s\n' "$*" >>"${CHECK_LOG}"
}
cli_migrate_runtime_defaults() {
	printf '%s\n' "$*" >>"${CHECK_LOG}"
}
service() {
	printf '%s\n' "$*" >>"${SERVICE_LOG}"
}
PTXT() {
	:
}
end_op_message() {
	printf '%s\n' "$1" >>"${END_LOG}"
}

for OPTION in setlocalcache setipset migrate-runtime-defaults; do
	: >"${CHECK_LOG}"
	: >"${SERVICE_LOG}"
	: >"${END_LOG}"

	menu "${OPTION}"
	STATUS=$?
	[ "${STATUS}" -eq 2 ] || fail "${OPTION} did not propagate confirmation failure status"
	[ ! -s "${CHECK_LOG}" ] || fail "${OPTION} applied a setting after confirmation failure"
	[ ! -s "${SERVICE_LOG}" ] || fail "${OPTION} restarted AdGuardHome after confirmation failure"
	[ "$(cat "${END_LOG}")" = '1' ] || fail "${OPTION} did not report an aborted operation"
done

printf '%s\n' 'PASS: setting toggles abort on confirmation failure'
