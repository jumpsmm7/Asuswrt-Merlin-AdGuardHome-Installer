#!/bin/sh
# Verify sw_mode no longer hard-exits LAN-mode install paths.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-install-mode-detection.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions"

cleanup() {
	rm -rf "${TMP_ROOT}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"
mkdir -p "${TMP_ROOT}" || fail 'could not create test directory'

sed -n '/^ipv4_is_valid() {$/,/^port_is_valid() {$/p' "${SCRIPT_PATH}" | sed '$d' >"${FUNCTIONS_FILE}" ||
	fail 'could not extract install mode helpers'
[ -s "${FUNCTIONS_FILE}" ] || fail 'install mode helper extraction was empty'

grep -q '^adguard_install_mode_detect() {$' "${SCRIPT_PATH}" ||
	fail 'install mode detection helper is missing'
grep -q 'write_conf ADGUARD_INSTALL_MODE "\\"${ADGUARD_INSTALL_MODE}\\""' "${SCRIPT_PATH}" ||
	fail 'installer must persist ADGUARD_INSTALL_MODE'
grep -q 'if \[ "${ADGUARD_INSTALL_MODE}" = "wan" \] && \[ -n "${NAT_ENV}" \]' "${SCRIPT_PATH}" ||
	fail 'double-NAT warning must be gated by WAN install mode'
if grep -q '\[ "$(nvram get sw_mode)" != "1" \].*exit 1' "${SCRIPT_PATH}"; then
	fail 'installer must not hard-exit on non-router sw_mode'
fi

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

ERROR='Error:'

PTXT() {
	printf '%s\n' "$*"
}

run_case() {
	case_name="$1"
	sw_value="$2"
	lan_value="$3"
	expected_status="$4"
	expected_mode="$5"

	ADGUARD_INSTALL_MODE=""
	nvram() {
		case "${1:-}:${2:-}" in
			get:sw_mode) printf '%s\n' "${sw_value}" ;;
			get:lan_ipaddr) printf '%s\n' "${lan_value}" ;;
			*) return 1 ;;
		esac
	}

	if adguard_install_mode_detect >/dev/null 2>&1; then
		actual_status="0"
	else
		actual_status="1"
	fi

	if [ "${actual_status}" != "${expected_status}" ]; then
		fail "${case_name}: expected status ${expected_status}, got ${actual_status}"
	fi
	if [ "${ADGUARD_INSTALL_MODE:-}" != "${expected_mode}" ]; then
		fail "${case_name}: expected mode ${expected_mode}, got ${ADGUARD_INSTALL_MODE:-empty}"
	fi
}

run_case router-wan 1 192.168.50.1 0 wan
run_case repeater-lan 2 192.168.50.1 0 lan
run_case ap-lan 3 192.168.50.1 0 lan
run_case media-bridge-lan 4 192.168.50.1 0 lan
run_case unknown-non-router-lan 9 192.168.50.1 0 lan
run_case missing-sw-mode-with-lan-ip "" 192.168.50.1 0 lan
run_case missing-sw-mode-without-lan-ip "" "" 1 ""
run_case missing-sw-mode-with-invalid-lan-ip "" 999.168.50.1 1 ""

printf '%s\n' 'PASS: installer install-mode detection accepts LAN pathways'
