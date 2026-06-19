#!/bin/sh
# Verify generated credentials are written to the staged YAML snapshot.

set -u

SCRIPT_PATH="${1:-installer}"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"

sed -n '/if ! AdGuardHome_authen 1 "${YAML_ORI_NEW}" 0; then/,/PTXT "dns:"/p' "${SCRIPT_PATH}" |
	grep -q 'return 1' || fail 'initial setup caller does not abort when staged authentication input fails'

sed -n '/if ! AdGuardHome_authen 1 "${YAML_ORI_NEW}" 0; then/,/PTXT "dns:"/p' "${SCRIPT_PATH}" |
	grep -q 'check_AdGuardHome_yaml' && fail 'initial setup validates staged YAML before dns/schema content is appended'

sed -n '/schema_version: ${SCHEMA_VER}/,/Writing AdGuardHome configuration/p' "${SCRIPT_PATH}" |
	grep -q 'check_AdGuardHome_yaml "${YAML_ORI_NEW}"' || fail 'initial setup does not validate completed staged YAML before publishing'

INPUT='Input:'
NORM=''
ERROR='Error:'
INFO='Info:'
AUTH_FUNCTION="$(sed -n '/^AdGuardHome_authen() {$/,/^agh_check() {$/p' "${SCRIPT_PATH}" | sed '$d')"
[ -n "${AUTH_FUNCTION}" ] || fail 'could not extract authentication function'
eval "${AUTH_FUNCTION}"

TMP_ROOT="${TMPDIR:-/tmp}/installer-staged-authentication.$$"
YAML_ORI="${TMP_ROOT}/original.yaml"
YAML_STAGED="${TMP_ROOT}/staged.yaml"
PW1='secret'
PW2='secret'
USERNAME='admin'
YAML_FILE="${YAML_ORI}"
YAML_ERR="${YAML_FILE}.err"
AGH_FILE="${TMP_ROOT}/AdGuardHome"
CHECKED_YAML=''
CHECK_SHOULD_FAIL=0

cleanup() {
	rm -rf "${TMP_ROOT}"
}
trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

mkdir -p "${TMP_ROOT}" || fail 'could not create test directory'
printf '%s\n' 'original snapshot' >"${YAML_ORI}"
printf '%s\n' 'http:' >"${YAML_STAGED}"

PTXT() {
	printf '%s\n' "$@"
}
remove_conflicting_apache() { :; }
ensure_password_hash_tool() { return 0; }
python_bcrypt_available() { return 0; }
hash_password_python() {
	printf '%s\n' '$2a$10$012345678901234567890123456789012345678901234567890123'
}
check_AdGuardHome_yaml() {
	CHECKED_YAML="${1:-${YAML_FILE}}"
	[ -f "${CHECKED_YAML}" ] || return 1
	[ "${CHECK_SHOULD_FAIL}" -eq 0 ] || return 1
}

AdGuardHome_authen 1 "${YAML_STAGED}" <<'EOF'
secret
secret
EOF

[ "$(cat "${YAML_ORI}")" = 'original snapshot' ] || fail 'authentication modified the published original snapshot'
grep -q '^users:$' "${YAML_STAGED}" || fail 'staged YAML is missing the users section'
grep -q '^- name: admin$' "${YAML_STAGED}" || fail 'staged YAML is missing the selected username'
grep -q '^  password: \$2a\$10\$' "${YAML_STAGED}" || fail 'staged YAML is missing the generated password hash'
[ "${CHECKED_YAML}" = "${YAML_STAGED}" ] || fail 'staged YAML target was not validated'

YAML_STAGED_FAIL="${TMP_ROOT}/staged-fail.yaml"
printf '%s\n' 'http:' >"${YAML_STAGED_FAIL}"
CHECKED_YAML=''
CHECK_SHOULD_FAIL=1
if AdGuardHome_authen 1 "${YAML_STAGED_FAIL}" <<'EOF'
secret
secret
EOF
then
	fail 'authentication accepted staged YAML validation failure'
fi
[ "${CHECKED_YAML}" = "${YAML_STAGED_FAIL}" ] || fail 'failing staged YAML target was not validated'
[ "$(cat "${YAML_ORI}")" = 'original snapshot' ] || fail 'failed staged validation modified the published original snapshot'
CHECK_SHOULD_FAIL=0

YAML_STAGED_SKIP="${TMP_ROOT}/staged-skip.yaml"
printf '%s\n' 'http:' >"${YAML_STAGED_SKIP}"
CHECKED_YAML=''
CHECK_SHOULD_FAIL=1
if ! AdGuardHome_authen 1 "${YAML_STAGED_SKIP}" 0 <<'EOF'
secret
secret
EOF
then
	fail 'authentication did not allow caller-deferred staged YAML validation'
fi
[ -z "${CHECKED_YAML}" ] || fail 'deferred staged authentication validated before the caller completed YAML'
grep -q '^users:$' "${YAML_STAGED_SKIP}" || fail 'deferred staged YAML is missing the users section'
CHECK_SHOULD_FAIL=0

if AdGuardHome_authen 1 "${YAML_STAGED}" </dev/null; then
	fail 'authentication accepted closed password input'
fi

printf '%s\n' 'PASS: generated credentials are written to the staged YAML snapshot'
