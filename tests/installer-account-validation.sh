#!/bin/sh
# Verify router administrator validation happens before staged YAML publication.

set -eu

SCRIPT_PATH="${1:-./installer}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/agh-account-validation.XXXXXX")" || exit 1
FUNCTIONS_FILE="${TMP_ROOT}/functions.sh"
trap 'rm -rf "${TMP_ROOT}"' EXIT HUP INT TERM
mkdir "${TMP_ROOT}/bin"

# fail reports a failure message to standard error and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

# extract_function extracts a named shell function from the configured script into the functions file.
extract_function() {
	case "$1" in
		*[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*) return 1 ;;
	esac
	_extracted="${TMP_ROOT}/$1.function"
	sed -n "/^$1() {\$/,/^}/p" "${SCRIPT_PATH}" >"${_extracted}" || return 1
	[ -s "${_extracted}" ] || return 1
	cat "${_extracted}" >>"${FUNCTIONS_FILE}"
}

extract_function adguardhome_owner_account
extract_function adguardhome_yaml_secure_file
extract_function blocklist_yaml_replace_trap_disable
extract_function blocklist_yaml_replace_trap_enable
extract_function remove_unused_blocklists_from_yaml
grep -q '^adguardhome_owner_account() {$' "${FUNCTIONS_FILE}" || fail 'adguardhome_owner_account extraction failed'
sed 's#/bin/nvram#nvram#g; s#/usr/bin/awk#awk#g' "${FUNCTIONS_FILE}" >"${FUNCTIONS_FILE}.test" || fail 'could not isolate stock account commands'
mv "${FUNCTIONS_FILE}.test" "${FUNCTIONS_FILE}" || fail 'could not update isolated account helpers'
. "${FUNCTIONS_FILE}"

cat >"${TMP_ROOT}/bin/nvram" <<'EOF_NVRAM'
#!/bin/sh
printf '%s\n' "${TEST_ACCOUNT:-}"
EOF_NVRAM
chmod 755 "${TMP_ROOT}/bin/nvram"
PATH="${TMP_ROOT}/bin:${PATH}"
export PATH TEST_ACCOUNT

for TEST_ACCOUNT in '-admin' 'admin:root' 'admin/name' 'admin name' 'admin;touch' "admin	name" '1001'; do
	if adguardhome_owner_account >/dev/null 2>&1; then
		fail "accepted malformed NVRAM username: ${TEST_ACCOUNT}"
	fi
done

TEST_ACCOUNT="root"
[ "$(adguardhome_owner_account)" = root ] || fail 'did not resolve the stock root account'
TEST_ACCOUNT=""
[ "$(adguardhome_owner_account)" = root ] || fail 'did not use root for an absent router administrator'

YAML_FILE="${TMP_ROOT}/AdGuardHome.yaml"
cat >"${YAML_FILE}" <<'EOF_YAML'
filters:
  - enabled: true
    url: https://example.invalid/list.txt
    name: test
    id: 1
schema_version: 27
EOF_YAML
cp "${YAML_FILE}" "${YAML_FILE}.expected"
printf '%s\n' 1 >"${TMP_ROOT}/ids"
PTXT() { :; }
# ptxt_warn is a no-op warning handler.
ptxt_warn() { :; }
# ptxt_step provides a no-op step hook.
ptxt_step() { :; }
# ptxt_ok performs a successful no-op.
ptxt_ok() { :; }
# ptxt_fail provides a no-op replacement for the failure-reporting function.
ptxt_fail() { :; }
# rollback_result_write is a no-op stub used during testing.
rollback_result_write() { :; }
# rollback_result_notice is a placeholder for reporting rollback results.
rollback_result_notice() { :; }
# check_AdGuardHome_yaml verifies the AdGuard Home YAML configuration.
check_AdGuardHome_yaml() { :; }
# clear_screen intentionally performs no action.
clear_screen() { :; }
# end_op_message performs no operation.
end_op_message() { :; }
# blocklist_yaml_candidates provides a placeholder for blocklist YAML candidate handling.
blocklist_yaml_candidates() { :; }
chown() { return 1; }

TEST_ACCOUNT="root"
if remove_unused_blocklists_from_yaml "${TMP_ROOT}/ids" >/dev/null 2>&1; then
	fail 'published staged YAML after ownership validation failed'
fi
cmp -s "${YAML_FILE}.expected" "${YAML_FILE}" || fail 'ownership failure replaced the active YAML'

SERVICE_PATH="$(dirname "${SCRIPT_PATH}")/S99AdGuardHome"
: >"${TMP_ROOT}/service-functions.sh"
sed -n '/^adguardhome_owner_account() {$/,/^}/p' "${SERVICE_PATH}" >"${TMP_ROOT}/service-functions.sh"
[ -s "${TMP_ROOT}/service-functions.sh" ] || fail 'service adguardhome_owner_account extraction failed'
sed 's#/bin/nvram#nvram#g; s#/usr/bin/awk#awk#g' "${TMP_ROOT}/service-functions.sh" >"${TMP_ROOT}/service-functions.test" || fail 'could not isolate service stock account commands'
mv "${TMP_ROOT}/service-functions.test" "${TMP_ROOT}/service-functions.sh" || fail 'could not update isolated service account helper'
. "${TMP_ROOT}/service-functions.sh"
for TEST_ACCOUNT in '-admin' 'admin:root' 'admin/name' 'admin name' 'admin$(touch bad)' '1001'; do
	if adguardhome_owner_account >/dev/null 2>&1; then
		fail "service helper accepted malformed NVRAM username: ${TEST_ACCOUNT}"
	fi
done
TEST_ACCOUNT="root"
[ "$(adguardhome_owner_account)" = root ] || fail 'service helper did not resolve the stock root account'

printf '%s\n' 'PASS: malformed accounts are rejected before staged YAML publication'
