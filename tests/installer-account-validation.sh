#!/bin/sh
# Verify router administrator validation happens before staged YAML publication.

set -eu

SCRIPT_PATH="${1:-./installer}"
TMP_ROOT="${TMPDIR:-/tmp}/agh-account-validation.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions.sh"
trap 'rm -rf "${TMP_ROOT}"' EXIT HUP INT TERM
mkdir -p "${TMP_ROOT}/bin"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

extract_function() {
	case "$1" in
		*[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*) return 1 ;;
	esac
	sed -n "/^$1() {\$/,/^}/p" "${SCRIPT_PATH}" >>"${FUNCTIONS_FILE}"
}

extract_function adguardhome_owner_account
extract_function adguardhome_yaml_secure_file
extract_function blocklist_yaml_replace_trap_disable
extract_function blocklist_yaml_replace_trap_enable
extract_function remove_unused_blocklists_from_yaml
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
ptxt_warn() { :; }
ptxt_step() { :; }
ptxt_ok() { :; }
ptxt_fail() { :; }
rollback_result_write() { :; }
rollback_result_notice() { :; }
check_AdGuardHome_yaml() { :; }
clear_screen() { :; }
end_op_message() { :; }
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
