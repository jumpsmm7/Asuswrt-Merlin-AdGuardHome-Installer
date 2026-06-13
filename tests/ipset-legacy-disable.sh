#!/bin/sh
# Verify legacy AdGuardHome versions no longer receive the managed ipset_file setting.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
FUNCTION_FILE="${TMPDIR:-/tmp}/ipset-legacy-functions.$$"
TEST_DIR="${TMPDIR:-/tmp}/ipset-legacy-test.$$"

cleanup() {
	rm -f "${FUNCTION_FILE}"
	rm -rf "${TEST_DIR}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

sed -n '/^IPSet_Current_File() {$/,/^}$/p; /^IPSet_Disable_Managed() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" || fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTION_FILE}" ] || fail 'legacy IPSET functions were not found'

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

logger() {
	:
}

mkdir -p "${TEST_DIR}" || fail 'could not create test directory'
YAML_FILE="${TEST_DIR}/AdGuardHome.yaml"
IPSET_FILE="${TEST_DIR}/ipset.conf"
NAME=AdGuardHome

cat >"${YAML_FILE}" <<EOF_YAML
http:
  address: 0.0.0.0:80
dns: &dns_defaults
  bind_hosts:
    - 0.0.0.0
  ipset: []
  ipset_file: ${IPSET_FILE}
filters: []
EOF_YAML
chmod 600 "${YAML_FILE}" || fail 'could not set restrictive YAML mode'
IPSet_Disable_Managed || fail 'could not disable a managed scalar path'
[ "${IPSET_DISABLE_CHANGED:-}" = 1 ] || fail 'managed scalar removal was not reported as changed'
[ "$(LC_ALL=C ls -ld "${YAML_FILE}" 2>/dev/null | awk 'NR == 1 {print substr($1, 2, 9)}')" = "rw-------" ] || fail 'YAML permissions were not preserved'
! grep -Eq '^[[:space:]]*ipset_file:' "${YAML_FILE}" || fail 'managed scalar path was retained'
grep -Eq '^dns: &dns_defaults$' "${YAML_FILE}" || fail 'annotated DNS header was not preserved'
grep -Eq '^[[:space:]]*ipset: \[\]$' "${YAML_FILE}" || fail 'inline IPSET setting was not preserved'

cat >"${YAML_FILE}" <<EOF_YAML
dns:
  ipset: []
  ipset_file: >-
    ${IPSET_FILE}
  cache_size: 4096
EOF_YAML
IPSet_Disable_Managed || fail 'could not disable a managed block-scalar path'
! grep -Eq 'ipset_file|^[[:space:]]+ipset\.conf$' "${YAML_FILE}" || fail 'managed block scalar was retained'
grep -Eq '^[[:space:]]*cache_size: 4096$' "${YAML_FILE}" || fail 'field after block scalar was removed'

cat >"${YAML_FILE}" <<'EOF_YAML'
dns:
  ipset:
    - example.org/router
  ipset_file: /custom/ipset.conf
EOF_YAML
cp "${YAML_FILE}" "${YAML_FILE}.expected" || fail 'could not preserve custom-path fixture'
IPSet_Disable_Managed || fail 'custom external path was rejected'
[ -z "${IPSET_DISABLE_CHANGED:-}" ] || fail 'unchanged custom path was reported as changed'
cmp -s "${YAML_FILE}" "${YAML_FILE}.expected" || fail 'custom external path was modified'

printf '%s\n' 'PASS: legacy setup disables only the managed ipset_file and preserves YAML metadata'
