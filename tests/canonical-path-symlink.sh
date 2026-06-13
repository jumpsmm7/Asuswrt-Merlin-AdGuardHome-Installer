#!/bin/sh
# Verify canonical_path resolves the final symlink without relying on readlink -f.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
FUNCTION_FILE="${TMPDIR:-/tmp}/canonical-path-function.$$"
TEST_DIR="${TMPDIR:-/tmp}/canonical-path-test.$$"

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

sed -n '/^canonical_path() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" || fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTION_FILE}" ] || fail 'canonical_path was not found'

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

mkdir -p "${TEST_DIR}/target" "${TEST_DIR}/links" || fail 'could not create test directories'
: >"${TEST_DIR}/target/database.db" || fail 'could not create target file'
ln -s '../target/database.db' "${TEST_DIR}/links/relative.db" || fail 'could not create relative symlink'
ln -s "${TEST_DIR}/links/relative.db" "${TEST_DIR}/absolute.db" || fail 'could not create absolute symlink'
EXPECTED="${TEST_DIR}/target/database.db"

have_cmd() {
	[ "$1" != 'readlink' ]
}
[ "$(canonical_path "${TEST_DIR}/absolute.db")" = "${EXPECTED}" ] || fail 'ls fallback did not resolve the final symlink chain'

have_cmd() {
	return 0
}
readlink() {
	if [ "$1" = '-f' ]; then
		return 1
	fi
	command readlink "$@"
}
[ "$(canonical_path "${TEST_DIR}/absolute.db")" = "${EXPECTED}" ] || fail 'plain readlink fallback did not resolve the final symlink chain'

printf '%s\n' 'canonical_path final-symlink regression checks passed'
