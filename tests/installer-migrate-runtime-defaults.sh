#!/bin/sh
# Verify runtime default migration reports legacy values and only writes with --yes.

set -u

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-migrate-runtime-defaults.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions"

cleanup() {
	rm -rf "${TMP_ROOT}"
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
mkdir -p "${TMP_ROOT}" || fail 'could not create test directory'

sed -n \
	'/^_quote() {$/,/^}$/p; /^PTXT() {$/,/^}$/p; /^ptxt_ok() {$/,/^}$/p; /^conf_value() {$/,/^}$/p; /^write_conf() {$/,/^}$/p; /^cli_write_quoted_conf() {$/,/^}$/p; /^cli_migrate_runtime_default() {$/,/^}$/p; /^cli_migrate_runtime_defaults() {$/,/^}$/p; /^cli_pre_runtime_defaults_preview() {$/,/^}$/p' \
	"${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" || fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTIONS_FILE}" ] || fail 'runtime migration helper extraction was empty'
grep -q '^cli_migrate_runtime_defaults() {$' "${FUNCTIONS_FILE}" || fail 'migration helper missing'
grep -q '^cli_pre_runtime_defaults_preview() {$' "${FUNCTIONS_FILE}" || fail 'migration preview short-circuit missing'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

INFO='[i]'
WARNING='[w]'
ERROR='[!]'
CONF_FILE="${TMP_ROOT}/.config"

cat >"${CONF_FILE}" <<'CONFIG'
ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="0"
ADGUARD_NETCHECK_MODE="legacy"
ADGUARD_PROC_OPTIMIZE="YES"
ADGUARD_PROC_PROFILE="aggressive"
CONFIG

before="$(cat "${CONF_FILE}")"
cli_migrate_runtime_defaults >"${TMP_ROOT}/report" || fail 'report-only migration failed'
[ "$(cat "${CONF_FILE}")" = "${before}" ] || fail 'report-only migration changed .config'
grep -q 'Legacy runtime default: ADGUARD_NETCHECK_MODE="legacy"' "${TMP_ROOT}/report" || fail 'legacy netcheck value was not reported'
grep -q 'No changes made. Re-run with --yes' "${TMP_ROOT}/report" || fail 'report-only migration did not explain --yes'

cli_migrate_runtime_defaults --dry-run >"${TMP_ROOT}/dry-run" || fail 'dry-run migration failed'
[ "$(cat "${CONF_FILE}")" = "${before}" ] || fail 'dry-run migration changed .config'
grep -q 'Dry-run: would write v2.6.0 safer runtime defaults' "${TMP_ROOT}/dry-run" || fail 'dry-run did not report planned writes'

cli_pre_runtime_defaults_preview migrate-runtime-defaults >"${TMP_ROOT}/preview-report" ||
	fail 'preview short-circuit did not run report-only migration'
[ "$(cat "${CONF_FILE}")" = "${before}" ] || fail 'preview report changed .config before startup'
cli_pre_runtime_defaults_preview migrate-runtime-defaults --dry-run >"${TMP_ROOT}/preview-dry-run" ||
	fail 'preview short-circuit did not run dry-run migration'
[ "$(cat "${CONF_FILE}")" = "${before}" ] || fail 'preview dry-run changed .config before startup'
grep -q 'Dry-run: would write v2.6.0 safer runtime defaults' "${TMP_ROOT}/preview-dry-run" ||
	fail 'preview dry-run did not report planned writes'
if cli_pre_runtime_defaults_preview migrate-runtime-defaults --yes >/dev/null; then
	fail 'preview short-circuit should not apply migrations before startup'
fi

cli_migrate_runtime_defaults --yes >"${TMP_ROOT}/apply" || fail 'apply migration failed'
grep -q '^ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="1"$' "${CONF_FILE}" || fail 'DNS port policy was not migrated'
grep -q '^ADGUARD_NETCHECK_MODE="wan"$' "${CONF_FILE}" || fail 'netcheck mode was not migrated'
grep -q '^ADGUARD_PROC_OPTIMIZE="YES"$' "${CONF_FILE}" || fail 'process optimization was not preserved'
grep -q '^ADGUARD_PROC_PROFILE="balanced"$' "${CONF_FILE}" || fail 'process profile was not migrated'

cat >"${CONF_FILE}" <<'CONFIG'
ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="0"
ADGUARD_NETCHECK_MODE="lan"
ADGUARD_PROC_OPTIMIZE="NO"
ADGUARD_PROC_PROFILE="balanced"
CONFIG

cli_migrate_runtime_defaults --yes >"${TMP_ROOT}/mixed-apply" || fail 'mixed custom apply migration failed'
grep -q '^ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="1"$' "${CONF_FILE}" || fail 'mixed DNS port policy was not migrated'
grep -q '^ADGUARD_NETCHECK_MODE="lan"$' "${CONF_FILE}" || fail 'custom netcheck mode was overwritten'
grep -q '^ADGUARD_PROC_OPTIMIZE="NO"$' "${CONF_FILE}" || fail 'custom process optimization was overwritten'
grep -q '^ADGUARD_PROC_PROFILE="balanced"$' "${CONF_FILE}" || fail 'custom process profile was overwritten'

printf '%s\n' 'PASS: runtime defaults migration reports and applies expected values'
