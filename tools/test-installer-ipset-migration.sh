#!/bin/sh
# Exercise the installer IPSet migration without requiring an Asuswrt router.

set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_DIR="${TMPDIR:-/tmp}/installer-ipset-test.$$"

cleanup() {
	rm -rf "${TEST_DIR}"
}

fail() {
	printf '%s\n' "FAILED: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

mkdir -p "${TEST_DIR}/addon" "${TEST_DIR}/agh"
awk '
	/^import_adguardhome_ipset\(\)/ { copy = 1 }
	/^setup_AdGuardHome\(\)/ { copy = 0 }
	copy { print }
' "${REPO_DIR}/installer" >"${TEST_DIR}/functions.sh"

# The extracted functions use installer globals and output helpers supplied here.
WARNING="Warning:"
PTXT() {
	printf '%s\n' "$*" >&2
}
ADDON_DIR="${TEST_DIR}/addon"
TARG_DIR="${TEST_DIR}/agh"
AGH_FILE="${TARG_DIR}/AdGuardHome"
YAML_FILE="${TARG_DIR}/AdGuardHome.yaml"
YAML_ORI="${TARG_DIR}/.AdGuardHome.yaml.ori"
IPSET_FILE="${ADDON_DIR}/ipset.conf"
export ADDON_DIR TARG_DIR AGH_FILE YAML_FILE YAML_ORI IPSET_FILE WARNING

# shellcheck source=/dev/null
. "${TEST_DIR}/functions.sh"

cat >"${AGH_FILE}" <<'EOF_AGH'
#!/bin/sh
exit "${AGH_CHECK_STATUS:-0}"
EOF_AGH
chmod +x "${AGH_FILE}"

cat >"${TARG_DIR}/legacy-ipset.conf" <<'EOF_LEGACY'
# Existing file-based mappings.
file.example/FileSet
shared.example/SharedSet
EOF_LEGACY
cat >"${IPSET_FILE}" <<'EOF_MANAGED'
managed.example/ManagedSet
EOF_MANAGED
cat >"${YAML_FILE}" <<'EOF_YAML'
dns:
  port: 53
  ipset:
    - inline.example/InlineSet
    - "shared.example/SharedSet" # duplicate
  ipset_file: legacy-ipset.conf
  upstream_dns:
    - 1.1.1.1
EOF_YAML
cat >"${YAML_ORI}" <<'EOF_ORIGINAL'
dns:
  port: 53
  ipset: ['flow.example/FlowSet']
EOF_ORIGINAL

setup_adguardhome_ipset || fail "valid migration returned an error"
cat >"${TEST_DIR}/expected-ipset.conf" <<'EOF_EXPECTED'
file.example/FileSet
flow.example/FlowSet
inline.example/InlineSet
managed.example/ManagedSet
shared.example/SharedSet
EOF_EXPECTED
cmp "${TEST_DIR}/expected-ipset.conf" "${IPSET_FILE}" || fail "mappings were not merged and deduplicated"
awk -v expected="${IPSET_FILE}" '$1 == "ipset_file:" && $2 == expected { found = 1 } END { exit(found ? 0 : 1) }' \
	"${YAML_FILE}" || fail "live YAML does not reference the managed file"
awk -v expected="${IPSET_FILE}" '$1 == "ipset_file:" && $2 == expected { found = 1 } END { exit(found ? 0 : 1) }' \
	"${YAML_ORI}" || fail "original YAML does not reference the managed file"

cp "${IPSET_FILE}" "${TEST_DIR}/ipset.before"
cp "${YAML_FILE}" "${TEST_DIR}/yaml.before"
cat >"${YAML_ORI}" <<'EOF_MISSING'
dns:
  port: 53
  ipset_file: missing-ipset.conf
EOF_MISSING
cp "${YAML_ORI}" "${TEST_DIR}/original.before"
if setup_adguardhome_ipset; then
	fail "migration succeeded with an unreadable legacy file"
fi
cmp "${TEST_DIR}/yaml.before" "${YAML_FILE}" || fail "later import failure rewrote the live YAML"
cmp "${TEST_DIR}/original.before" "${YAML_ORI}" || fail "failed migration rewrote the original YAML"
cmp "${TEST_DIR}/ipset.before" "${IPSET_FILE}" || fail "later import failure rewrote the managed mappings"

cat >"${YAML_ORI}" <<'EOF_ORIGINAL'
dns:
  port: 53
  ipset: ['original.example/OriginalSet']
EOF_ORIGINAL
cp "${YAML_FILE}" "${TEST_DIR}/yaml.before"
cp "${YAML_ORI}" "${TEST_DIR}/original.before"
AGH_CHECK_STATUS=1
export AGH_CHECK_STATUS
if setup_adguardhome_ipset; then
	fail "migration succeeded when AdGuardHome rejected the staged configuration"
fi
unset AGH_CHECK_STATUS
cmp "${TEST_DIR}/yaml.before" "${YAML_FILE}" || fail "validation failure rewrote the live YAML"
cmp "${TEST_DIR}/original.before" "${YAML_ORI}" || fail "validation failure rewrote the original YAML"
cmp "${TEST_DIR}/ipset.before" "${IPSET_FILE}" || fail "validation failure rewrote the managed mappings"

printf '%s\n' "OK: installer IPSet migration"
