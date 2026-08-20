#!/bin/sh
# Verify calc_sum validates output from the supported checksum command names.

set -u

SCRIPT_PATH="${1:-tools/download-adguardhome-static.sh}"
TEST_ROOT="${TMPDIR:-/tmp}/static-checksum-output-validation.$$"
FUNCTION_FILE="${TEST_ROOT}/functions"
FAKE_BIN="${TEST_ROOT}/bin"
FAKE_SUM_LOG="${TEST_ROOT}/sum-calls"
INPUT_FILE="${TEST_ROOT}/input"
ORIGINAL_PATH="${PATH}"

cleanup() {
	PATH="${ORIGINAL_PATH}"
	export PATH
	rm -rf "${TEST_ROOT}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
mkdir -p "${FAKE_BIN}" || fail 'could not create checksum fixture directory'
printf '%s\n' payload >"${INPUT_FILE}" || fail 'could not create checksum fixture input'

sed -n '/^calc_sum() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" ||
	fail "could not read calc_sum from ${SCRIPT_PATH}"
[ -s "${FUNCTION_FILE}" ] || fail 'calc_sum helper was not found'

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"
type calc_sum >/dev/null 2>&1 || fail 'calc_sum helper extraction failed'

cat >"${FAKE_BIN}/checksum-fixture" <<'EOF_FIXTURE'
#!/bin/sh
printf '%s %s\n' "${0##*/}" "${FAKE_SUM_CASE:-unset}" >>"${FAKE_SUM_LOG}"
case "${FAKE_SUM_CASE:-}" in
	md5-valid)
		printf '%s  %s\n' '0123456789abcdef0123456789abcdef' "$1"
		;;
	md5-nonhex)
		printf '%s  %s\n' '0123456789abcdef0123456789abcdeg' "$1"
		;;
	md5-short)
		printf '%s  %s\n' '0123456789abcdef0123456789abcde' "$1"
		;;
	md5-long)
		printf '%s  %s\n' '0123456789abcdef0123456789abcdef0' "$1"
		;;
	sha256-valid)
		printf '%s  %s\n' '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' "$1"
		;;
	sha256-nonhex)
		printf '%s  %s\n' '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdeg' "$1"
		;;
	sha256-short)
		printf '%s  %s\n' '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcde' "$1"
		;;
	sha256-long)
		printf '%s  %s\n' '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0' "$1"
		;;
	command-failure)
		exit 7
		;;
	*)
		exit 8
		;;
esac
EOF_FIXTURE
chmod 755 "${FAKE_BIN}/checksum-fixture" || fail 'could not make checksum fixture executable'
ln "${FAKE_BIN}/checksum-fixture" "${FAKE_BIN}/md5sum" || fail 'could not create md5sum fixture'
ln "${FAKE_BIN}/checksum-fixture" "${FAKE_BIN}/sha256sum" || fail 'could not create sha256sum fixture'
ln "${FAKE_BIN}/checksum-fixture" "${FAKE_BIN}/fake-sum" || fail 'could not create unsupported checksum fixture'

PATH="${FAKE_BIN}:${PATH}"
export PATH FAKE_SUM_LOG
: >"${FAKE_SUM_LOG}"

assert_accepts() {
	_case="$1"
	_command="$2"
	_expected="$3"
	FAKE_SUM_CASE="${_case}"
	export FAKE_SUM_CASE
	_actual="$(calc_sum "${_command}" "${INPUT_FILE}")" ||
		fail "calc_sum rejected valid ${_case} output"
	[ "${_actual}" = "${_expected}" ] ||
		fail "calc_sum changed valid ${_case} output"
	grep -q "^${_command} ${_case}$" "${FAKE_SUM_LOG}" ||
		fail "${_case} did not execute the supported ${_command} fixture"
}

assert_rejects() {
	_case="$1"
	_command="$2"
	FAKE_SUM_CASE="${_case}"
	export FAKE_SUM_CASE
	_before="$(wc -l <"${FAKE_SUM_LOG}")"
	if calc_sum "${_command}" "${INPUT_FILE}" >/dev/null 2>&1; then
		fail "calc_sum accepted invalid ${_case} output from ${_command}"
	fi
	_after="$(wc -l <"${FAKE_SUM_LOG}")"
	[ "${_after}" -eq "$((_before + 1))" ] ||
		fail "${_case} did not execute exactly one ${_command} fixture"
	grep -q "^${_command} ${_case}$" "${FAKE_SUM_LOG}" ||
		fail "${_case} rejection did not exercise ${_command} output validation"
}

MD5_VALID='0123456789abcdef0123456789abcdef'
SHA256_VALID='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'

assert_accepts md5-valid md5sum "${MD5_VALID}"
assert_accepts sha256-valid sha256sum "${SHA256_VALID}"

for _case in md5-nonhex md5-short md5-long command-failure; do
	assert_rejects "${_case}" md5sum
done
for _case in sha256-nonhex sha256-short sha256-long command-failure; do
	assert_rejects "${_case}" sha256sum
done

# Separately prove calc_sum still rejects an unsupported command identity even
# when that executable emits an otherwise valid MD5-shaped digest.
FAKE_SUM_CASE=md5-valid
export FAKE_SUM_CASE
_before="$(wc -l <"${FAKE_SUM_LOG}")"
if calc_sum fake-sum "${INPUT_FILE}" >/dev/null 2>&1; then
	fail 'calc_sum accepted an unsupported checksum command identity'
fi
_after="$(wc -l <"${FAKE_SUM_LOG}")"
[ "${_after}" -eq "$((_before + 1))" ] || fail 'unsupported command fixture did not execute'
grep -q '^fake-sum md5-valid$' "${FAKE_SUM_LOG}" ||
	fail 'unsupported command rejection was not tested independently of command execution'

printf '%s\n' 'PASS: calc_sum validates supported checksum command output by identity, length, content, and exit status'
