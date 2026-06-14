#!/usr/bin/env bash
# Verify generated credentials are written to the staged YAML snapshot.

set -u

SCRIPT_PATH="${1:-installer}"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"

INPUT='Input:'
NORM=''
ERROR='Error:'
AUTH_FUNCTION="$(sed -n '/^AdGuardHome_authen() {$/,/^agh_check() {$/p' "${SCRIPT_PATH}" | sed '$d')"
[ -n "${AUTH_FUNCTION}" ] || fail 'could not extract authentication function'
eval "${AUTH_FUNCTION}"

TMP_ROOT="${TMPDIR:-/tmp}/installer-staged-authentication.$$"
YAML_ORI="${TMP_ROOT}/original.yaml"
YAML_STAGED="${TMP_ROOT}/staged.yaml"
PW1='secret'
PW2='secret'
USERNAME='admin'

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

AdGuardHome_authen 1 "${YAML_STAGED}" <<'EOF'
secret
secret
EOF

[ "$(cat "${YAML_ORI}")" = 'original snapshot' ] || fail 'authentication modified the published original snapshot'
grep -q '^users:$' "${YAML_STAGED}" || fail 'staged YAML is missing the users section'
grep -q '^- name: admin$' "${YAML_STAGED}" || fail 'staged YAML is missing the selected username'
grep -q '^  password: \$2a\$10\$' "${YAML_STAGED}" || fail 'staged YAML is missing the generated password hash'

printf '%s\n' 'PASS: generated credentials are written to the staged YAML snapshot'
