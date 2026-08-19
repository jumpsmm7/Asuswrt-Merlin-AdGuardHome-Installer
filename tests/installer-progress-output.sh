#!/bin/sh
# Verify installer progress helpers preserve recognizable prefixes.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-progress-output.$$"
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

sed -n \
	-e '/^PTXT() {$/,/^}/p' \
	-e '/^ptxt_phase() {$/,/^}/p' \
	-e '/^ptxt_step() {$/,/^}/p' \
	-e '/^ptxt_ok() {$/,/^}/p' \
	-e '/^ptxt_warn() {$/,/^}/p' \
	-e '/^ptxt_fail() {$/,/^}/p' \
	"${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" ||
	fail 'could not extract progress helpers'
[ -s "${FUNCTIONS_FILE}" ] || fail 'progress helper extraction was empty'

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	INFO='Info:'
	WARNING='Warning:'
	ERROR='Error:'

	{
		ptxt_phase 'Install test'
		ptxt_step 'Download test'
		ptxt_ok 'Success test'
		ptxt_warn 'Warning test'
		ptxt_fail 'Failure test'
	} >"${TMP_ROOT}/actual"
) || fail 'progress helper subprocess failed'

cat >"${TMP_ROOT}/expected" <<'EOF_EXPECTED'
Info: ====================================================
Info: PHASE: Install test
Info: ====================================================
Info: -> Download test
Info: OK: Success test
Warning: WARN: Warning test
Error: FAIL: Failure test
EOF_EXPECTED

cmp -s "${TMP_ROOT}/expected" "${TMP_ROOT}/actual" ||
	fail "progress helper output changed: $(cat "${TMP_ROOT}/actual")"

printf '%s\n' 'PASS: installer progress output helpers preserve expected prefixes'
