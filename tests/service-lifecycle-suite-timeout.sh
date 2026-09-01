#!/bin/sh
# Regression test for the service lifecycle suite watchdog timeout calculation.

set -u

SCRIPT_PATH='tests/service-lifecycle-integration.sh'

# fail prints a failure message containing the specified reason and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $1" >&2
	exit 1
}

TMP_ROOT=$(mktemp -d) || fail 'unable to create exclusive temp workspace'
trap 'rm -rf "${TMP_ROOT}"' EXIT
trap 'rm -rf "${TMP_ROOT}"; exit 1' HUP INT TERM

FUNCTIONS_FILE="${TMP_ROOT}/functions.sh"
sed -n '/^suite_timeout_seconds() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" ||
	fail 'could not extract suite timeout helper'
[ -s "${FUNCTIONS_FILE}" ] || fail 'suite timeout helper extraction was empty'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

STUB_DECLARED_CASE_COUNT=28
OUTER_TIMEOUT_SECONDS=5160
suite_timeout=$(suite_timeout_seconds "${STUB_DECLARED_CASE_COUNT}" 180 "${OUTER_TIMEOUT_SECONDS}") ||
	fail '180-second per-case timeout was rejected'
[ "${suite_timeout}" -eq 5134 ] ||
	fail "suite timeout did not include the three-second per-case allowance: ${suite_timeout}"
[ "${suite_timeout}" -ne 5106 ] ||
	fail 'suite timeout used only a two-second per-case allowance'

if suite_timeout_seconds "${STUB_DECLARED_CASE_COUNT}" 181 "${OUTER_TIMEOUT_SECONDS}" >/dev/null; then
	fail '181-second per-case timeout exceeded the outer limit without rejection'
fi

printf '%s\n' 'PASS: service lifecycle suite timeout calculation is bounded'
