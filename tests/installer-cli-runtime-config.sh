#!/bin/sh
# Verify non-interactive runtime configuration helpers persist safe .config values.

set -u

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-cli-runtime-config.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions"

cleanup() {
	rm -rf "${TMP_ROOT}"
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
mkdir -p "${TMP_ROOT}" || fail 'could not create test directory'

sed -n \
	'/^_quote() {$/,/^}$/p; /^PTXT() {$/,/^}$/p; /^ptxt_ok() {$/,/^}$/p; /^branch_is_safe() {$/,/^}$/p; /^conf_value() {$/,/^}$/p; /^write_conf() {$/,/^}$/p; /^cli_bool_value() {$/,/^}$/p; /^cli_adguard_branch_is_valid() {$/,/^}$/p; /^cli_simple_value_is_safe() {$/,/^}$/p; /^cli_host_list_is_safe() {$/,/^}$/p; /^cli_write_quoted_conf() {$/,/^}$/p; /^cli_netcheck_config_values() {$/,/^}$/p; /^cli_dns_port_policy() {$/,/^}$/p; /^cli_migrate_runtime_default() {$/,/^}$/p; /^cli_migrate_runtime_defaults() {$/,/^}$/p; /^cli_installer_branch_from_args() {$/,/^}$/p; /^cli_write_adguard_branch() {$/,/^}$/p; /^cli_run() {$/,/^}$/p' \
	"${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" || fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTIONS_FILE}" ] || fail 'CLI helper extraction was empty'
grep -q '^cli_netcheck_config_values() {$' "${FUNCTIONS_FILE}" || fail 'netcheck config helper missing'
grep -q '^cli_dns_port_policy() {$' "${FUNCTIONS_FILE}" || fail 'DNS port policy helper missing'
grep -q '^cli_migrate_runtime_defaults() {$' "${FUNCTIONS_FILE}" || fail 'runtime migration helper missing'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

INFO='[i]'
ERROR='[!]'
WARNING='[w]'
CONF_FILE="${TMP_ROOT}/.config"

cli_require_yes() {
	return 0
}

cli_enable_assume_yes() {
	return 0
}

menu() {
	printf '%s\n' "$1" >"${TMP_ROOT}/menu-action"
	return "${MENU_STATUS:-0}"
}

cli_run netcheck --installer-branch dev --mode wan --hosts 'google.com github.com' --dns 127.0.0.1 --require-http yes --timeout 120 >/dev/null ||
	fail 'netcheck CLI helper failed'
grep -q '^INSTALLER_BRANCH="dev"$' "${CONF_FILE}" || fail 'installer branch was not persisted'
grep -q '^ADGUARD_NETCHECK_MODE="wan"$' "${CONF_FILE}" || fail 'netcheck mode was not persisted'
grep -q '^ADGUARD_NETCHECK_HOSTS="google.com github.com"$' "${CONF_FILE}" || fail 'netcheck hosts were not persisted'
grep -q '^ADGUARD_NETCHECK_DNS="127.0.0.1"$' "${CONF_FILE}" || fail 'netcheck DNS was not persisted'
grep -q '^ADGUARD_NETCHECK_REQUIRE_HTTP="YES"$' "${CONF_FILE}" || fail 'netcheck HTTP requirement was not normalized and persisted'
grep -q '^ADGUARD_NETCHECK_TIMEOUT="120"$' "${CONF_FILE}" || fail 'netcheck timeout was not persisted'

if cli_run netcheck --mode wan --hosts 'good.com;rm'; then
	fail 'netcheck CLI accepted unsafe host characters'
fi
if cli_run netcheck --mode wan --timeout 0; then
	fail 'netcheck CLI accepted a zero timeout'
fi

cli_run dns-port-policy --policy refuse-unknown >/dev/null || fail 'DNS port refusal policy failed'
grep -q '^ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="1"$' "${CONF_FILE}" || fail 'refuse-unknown policy was not persisted'
cli_run dns-port-policy --policy legacy >/dev/null || fail 'DNS port legacy policy failed'
grep -q '^ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="0"$' "${CONF_FILE}" || fail 'legacy DNS port policy was not persisted'
write_conf ADGUARD_PROC_PROFILE '"aggressive"' || fail 'could not seed legacy performance profile'
cli_run migrate-runtime-defaults --dry-run >/dev/null || fail 'migration dry-run failed'
grep -q '^ADGUARD_NETCHECK_MODE="wan"$' "${CONF_FILE}" || fail 'migration dry-run changed netcheck mode'
cli_run migrate-runtime-defaults --yes >/dev/null || fail 'migration CLI failed'
grep -q '^ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="1"$' "${CONF_FILE}" || fail 'migration did not persist refuse-unknown policy'
grep -q '^ADGUARD_NETCHECK_MODE="wan"$' "${CONF_FILE}" || fail 'migration did not persist netcheck mode'
grep -q '^ADGUARD_PROC_PROFILE="balanced"$' "${CONF_FILE}" || fail 'migration did not persist balanced performance profile'

cli_adguard_branch_is_valid edge || fail 'edge AdGuardHome branch should be valid'
if cli_adguard_branch_is_valid master; then
	fail 'master must not be accepted as an AdGuardHome branch'
fi
[ "$(cli_installer_branch_from_args install --installer-branch feature/test --adguardhome-branch beta)" = 'feature/test' ] ||
	fail 'installer branch parser did not distinguish installer and AdGuardHome branches'

write_conf ADGUARD_BRANCH '"release"' || fail 'could not seed release branch'
unset ADGUARD_BRANCH_CHANGED
cli_run update --adguardhome-branch beta --yes >/dev/null || fail 'update with AdGuardHome branch failed'
grep -q '^ADGUARD_BRANCH="beta"$' "${CONF_FILE}" || fail 'CLI update branch was not persisted'
[ "${ADGUARD_BRANCH_CHANGED:-0}" = "1" ] || fail 'CLI update branch switch was not marked as changed'
[ "$(cat "${TMP_ROOT}/menu-action")" = 'update' ] || fail 'CLI update did not dispatch the update menu action'

MENU_STATUS=2
cli_run update --yes >/dev/null
STATUS=$?
[ "${STATUS}" -eq 1 ] || fail 'CLI update exposed operational status 2 as a usage error'
MENU_STATUS=0

unset ADGUARD_BRANCH_CHANGED
cli_run update --adguardhome-branch beta --yes >/dev/null || fail 'same-branch update failed'
[ "${ADGUARD_BRANCH_CHANGED:-0}" = "0" ] || fail 'same-branch CLI update should not be marked as changed'

printf '%s\n' 'PASS: installer CLI runtime configuration helpers persist expected values'
