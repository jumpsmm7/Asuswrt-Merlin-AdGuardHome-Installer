#!/bin/sh
# Verify the installer MD5 helpers and legacy download verification path.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-md5-helper.$$"
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
	-e '/^md5_is_valid() {$/,/^}/p' \
	-e '/^sha256_is_valid() {$/,/^}/p' \
	-e '/^file_md5() {$/,/^}/p' \
	-e '/^sha256_manifest_digest() {$/,/^}/p' \
	-e '/^md5_manifest_digest() {$/,/^}/p' \
	-e '/^download_file() {$/,/^}/p' \
	"${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" || fail 'could not extract MD5 helper functions'
for function_name in md5_is_valid file_md5 md5_manifest_digest download_file; do
	grep -q "^${function_name}()" "${FUNCTIONS_FILE}" || fail "MD5 helper extraction is missing ${function_name}"
done

# Provide the installer's output primitive while preserving its optional -n behavior.
PTXT() {
	if [ "${1:-}" = '-n' ]; then
		shift
		printf '%s' "$*"
	else
		printf '%s\n' "$*"
	fi
}

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

ai_have_cmd() { return 1; }
file_md5 "${TMP_ROOT}/unused" >/dev/null 2>&1 && fail 'file_md5 accepted an unavailable MD5 calculator'

ai_have_cmd() { [ "$1" = md5sum ]; }
md5sum() {
	printf '%s  %s\n' 'd41d8cd98f00b204e9800998ecf8427e' "$1"
	return 1
}
file_md5 "${TMP_ROOT}/unused" >/dev/null 2>&1 && fail 'file_md5 accepted output from a failing MD5 calculator'

: >"${TMP_ROOT}/empty.md5sum"
md5_manifest_digest "${TMP_ROOT}/empty.md5sum" >/dev/null 2>&1 && fail 'empty MD5 metadata was accepted'
printf '%s\n' 'not-a-digest' >"${TMP_ROOT}/malformed.md5sum"
md5_manifest_digest "${TMP_ROOT}/malformed.md5sum" >/dev/null 2>&1 && fail 'malformed MD5 metadata was accepted'
md5_manifest_digest "${TMP_ROOT}/missing.md5sum" >/dev/null 2>&1 && fail 'a missing MD5 manifest was accepted'

run_download_case() (
	case_name="$1"
	expected_status="$2"
	target_dir="${TMP_ROOT}/${case_name}"
	mkdir -p "${target_dir}" || exit 1
	printf '%s\n' 'existing target' >"${target_dir}/payload"
	: >"${target_dir}/attempts"
	BOLD=''
	NORM=''
	ptxt_phase() { :; }
	ptxt_step() { :; }
	ptxt_ok() { :; }
	ptxt_warn() { :; }
	ptxt_fail() { :; }
	file_sha256() { return 1; }
	sha256_manifest_digest() { return 1; }
	file_md5() {
		case "$1" in
			"${target_dir}/payload") printf '%s\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' ;;
			*)
				attempt="$(wc -l <"${target_dir}/attempts" | tr -d ' ')"
				case "${case_name}:${attempt}" in
					calculator-failure:*) return 1 ;;
					stale-retry:1) printf '%s\n' 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' ;;
					*) printf '%s\n' 'cccccccccccccccccccccccccccccccc' ;;
				esac
				;;
		esac
	}
	http_get_file() {
		url="$1"
		destination="$2"
		case "${url}" in
			*.sha256sum) return 1 ;;
			*.md5sum)
				case "${case_name}" in
					missing-manifest) return 1 ;;
					empty-metadata) : >"${destination}" ;;
					malformed-metadata) printf '%s\n' 'invalid' >"${destination}" ;;
					digest-mismatch | calculator-failure) printf '%s\n' 'dddddddddddddddddddddddddddddddd' >"${destination}" ;;
					stale-retry)
						attempt="$(wc -l <"${target_dir}/attempts" | tr -d ' ')"
						if [ "${attempt}" -eq 1 ]; then
							printf '%s\n' 'dddddddddddddddddddddddddddddddd' >"${destination}"
						else
							printf '%s\n' 'cccccccccccccccccccccccccccccccc' >"${destination}"
						fi
						;;
					valid-digest) printf '%s\n' 'cccccccccccccccccccccccccccccccc' >"${destination}" ;;
				esac
				;;
			*)
				printf '%s\n' x >>"${target_dir}/attempts"
				printf '%s\n' "staged ${case_name}" >"${destination}"
				;;
		esac
	}
	if download_file "${target_dir}" 755 'https://example.invalid/payload' >/dev/null 2>&1; then
		actual_status=0
	else
		actual_status=1
	fi
	[ "${actual_status}" -eq "${expected_status}" ] || exit 1
	if [ "${expected_status}" -eq 0 ]; then
		grep -q "staged ${case_name}" "${target_dir}/payload" || exit 1
	else
		grep -q '^existing target$' "${target_dir}/payload" || exit 1
		[ ! -e "${target_dir}/.payload.$$" ] || exit 1
	fi
)

for failure_case in calculator-failure empty-metadata malformed-metadata missing-manifest digest-mismatch; do
	run_download_case "${failure_case}" 1 || fail "${failure_case} did not fail safely or preserve its target"
done
run_download_case valid-digest 0 || fail 'a valid MD5 digest was not accepted and installed'
run_download_case stale-retry 0 || fail 'stale MD5 digest state survived between download retries'

printf '%s\n' 'PASS: installer MD5 helper rejects invalid inputs, resets retry state, and preserves targets on failure'
