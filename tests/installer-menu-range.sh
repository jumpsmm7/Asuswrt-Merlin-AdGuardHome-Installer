#!/bin/sh
# Verify the installed-state menu accepts every advertised numeric option.

set -u

SCRIPT_PATH="${1:-installer}"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"

grep -q '8) Enable/Disable AdGuardHome IPSET Integration' "${SCRIPT_PATH}" || fail 'installed-state menu does not advertise option 8'

INSTALLED_RANGES="$(sed -n '/^menu() {$/,/^read_input_dns() {$/p' "${SCRIPT_PATH}" | grep 'read_input_num "Please enter the number that designates your selection:" 1 8 b' || true)"
RANGE_COUNT="$(printf '%s\n' "${INSTALLED_RANGES}" | awk 'NF { count++ } END { print count + 0 }')"

[ "${RANGE_COUNT}" -eq 2 ] || fail "expected both installed-state menu ranges to allow option 8; found ${RANGE_COUNT}"
printf '%s\n' "${INSTALLED_RANGES}" | grep -q '1 8 b q;' || fail 'installed-state menu without a backup does not allow option 8'
printf '%s\n' "${INSTALLED_RANGES}" | grep -q '1 8 b r q;' || fail 'installed-state menu with a backup does not allow option 8'

printf '%s\n' 'PASS: installed-state menu accepts advertised option 8'
