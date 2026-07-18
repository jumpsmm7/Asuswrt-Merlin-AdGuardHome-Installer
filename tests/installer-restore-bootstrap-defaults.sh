#!/bin/sh
# Verify non-interactive RESTORE YAML rebuild bootstrap defaults are populated.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-restore-bootstrap-defaults.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions"
YAML_FILE="${TMP_ROOT}/AdGuardHome.yaml.bak"

cleanup() {
	rm -rf "${TMP_ROOT}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

extract_simple_function() {
	_function_name="$1"
	awk -v name="${_function_name}" '
		$0 == name "() {" { copying = 1 }
		copying { print }
		copying && $0 == "}" { exit }
	' "${SCRIPT_PATH}" >>"${FUNCTIONS_FILE}" || return 1
}

extract_restore_defaults_function() {
	awk '
		$0 == "setup_restore_bootstrap_defaults() {" { copying = 1 }
		copying && $0 == "setup_AdGuardHome_impl() {" { exit }
		copying { print }
	' "${SCRIPT_PATH}" >>"${FUNCTIONS_FILE}" || return 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"
mkdir -p "${TMP_ROOT}" || fail 'could not create test directory'
: >"${FUNCTIONS_FILE}"
extract_simple_function ipv4_is_valid || fail 'could not extract IPv4 validator'
extract_restore_defaults_function || fail 'could not extract RESTORE bootstrap helper'
[ -s "${FUNCTIONS_FILE}" ] || fail 'helper extraction was empty'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

PTXT() { printf '%s\n' "$*"; }

cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write restored YAML with bootstrap values'
dns:
  upstream_dns:
    - 9.9.9.9
  bootstrap_dns:
    - '1.1.1.1'
    - "8.8.4.4"
  fallback_dns:
    - 4.4.4.4
EOF_YAML
setup_restore_bootstrap_defaults "${YAML_FILE}"
[ "${BOOTSTRAP1}" = '1.1.1.1' ] || fail 'did not preserve first restored bootstrap DNS'
[ "${BOOTSTRAP2}" = '8.8.4.4' ] || fail 'did not preserve second restored bootstrap DNS'
[ "${DNS_SERVER1}" = "${BOOTSTRAP1}" ] || fail 'did not set DNS_SERVER1 from restored bootstrap DNS'

cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write restored YAML without valid bootstrap pair'
dns:
  bootstrap_dns:
    - '999.1.1.1'
EOF_YAML
setup_restore_bootstrap_defaults "${YAML_FILE}"
[ "${BOOTSTRAP1}" = '9.9.9.9' ] || fail 'did not default invalid first bootstrap DNS'
[ "${BOOTSTRAP2}" = '8.8.8.8' ] || fail 'did not default missing second bootstrap DNS'

rm -f "${YAML_FILE}"
setup_restore_bootstrap_defaults "${YAML_FILE}"
[ "${BOOTSTRAP1}" = '9.9.9.9' ] || fail 'did not default first bootstrap DNS when backup YAML is missing'
[ "${BOOTSTRAP2}" = '8.8.8.8' ] || fail 'did not default second bootstrap DNS when backup YAML is missing'

printf '%s\n' 'PASS: RESTORE bootstrap defaults cover restored, invalid, and missing YAML paths'
