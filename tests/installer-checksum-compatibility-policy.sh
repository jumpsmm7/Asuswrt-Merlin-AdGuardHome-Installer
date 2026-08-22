#!/bin/sh
# Verify the installer prefers SHA-256 and uses MD5 only for intentional legacy compatibility.

set -u

INSTALLER="${1:-installer}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/installer-checksum-policy.XXXXXX")" || exit 1
FUNCTIONS_FILE="${TEST_ROOT}/functions"

# cleanup removes the exclusive test workspace.
cleanup() { rm -rf "${TEST_ROOT}"; }

# fail reports a regression failure and exits nonzero.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

sed -n \
	-e '/^md5_is_valid() {$/,/^}$/p' \
	-e '/^sha256_is_valid() {$/,/^}$/p' \
	-e '/^sha256_manifest_digest() {$/,/^}$/p' \
	-e '/^md5_manifest_digest() {$/,/^}$/p' \
	-e '/^download_file() {$/,/^}$/p' \
	"${INSTALLER}" >"${FUNCTIONS_FILE}" || fail 'could not extract checksum decision helpers'
[ -s "${FUNCTIONS_FILE}" ] || fail 'checksum decision helper extraction was empty'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

BOLD=''
NORM=''
TARGET_DIR="${TEST_ROOT}/target"
PAYLOAD_FILE="${TEST_ROOT}/payload"
WARNINGS_FILE="${TEST_ROOT}/warnings"
mkdir "${TARGET_DIR}" || fail 'could not create target directory'
printf '%s\n' 'verified payload' >"${PAYLOAD_FILE}" || fail 'could not create payload fixture'
PAYLOAD_SHA256="$(sha256sum "${PAYLOAD_FILE}" | awk '{ print $1 }')" || fail 'could not calculate fixture SHA-256'
PAYLOAD_MD5="$(md5sum "${PAYLOAD_FILE}" | awk '{ print $1 }')" || fail 'could not calculate fixture MD5'

# Minimal output helpers capture only warnings relevant to policy assertions.
PTXT() {
	if [ "${1:-}" = -n ]; then
		shift
		printf '%s' "$*"
	else
		printf '%s\n' "$*"
	fi
}
ptxt_phase() { :; }
ptxt_step() { :; }
ptxt_ok() { :; }
ptxt_fail() { :; }
ptxt_warn() { printf '%s\n' "$*" >>"${WARNINGS_FILE}"; }

# ai_have_cmd reports checksum tools as available; calculation failures are scenario-controlled below.
ai_have_cmd() { return 0; }

# reset_case restores the installed target and scenario counters.
reset_case() {
	SCENARIO="$1"
	PAYLOAD_REQUESTS=0
	SHA_REQUESTS=0
	MD5_REQUESTS=0
	FINAL_CHMOD_REQUESTS=0
	MV_REQUESTS=0
	: >"${WARNINGS_FILE}"
	printf '%s\n' 'installed target' >"${TARGET_DIR}/component" || fail "${SCENARIO}: could not reset installed target"
	command chmod 640 "${TARGET_DIR}/component" || fail "${SCENARIO}: could not reset installed target permissions"
	rm -f "${TARGET_DIR}/.component.$$" "${TARGET_DIR}/.component.$$.md5sum" "${TARGET_DIR}/.component.$$.sha256sum"
}

# http_get_file supplies scenario-specific payloads and checksum sidecars.
http_get_file() {
	case "$1" in
		*.sha256sum)
			SHA_REQUESTS="$((SHA_REQUESTS + 1))"
			case "${SCENARIO}" in
				sha_match | mv_failure) printf '%s\n' "${PAYLOAD_SHA256}" >"$2" ;;
				sha_mismatch | checksum_failure) printf '%064d\n' 0 >"$2" ;;
				sha_invalid) printf '%s\n' invalid >"$2" ;;
				sha_empty) : >"$2" ;;
				sha_calc_unavailable) printf '%s\n' "${PAYLOAD_SHA256}" >"$2" ;;
				retry_state)
					[ "${PAYLOAD_REQUESTS}" -eq 1 ] || return 1
					return 1
					;;
				*) return 1 ;;
			esac
			;;
		*.md5sum)
			MD5_REQUESTS="$((MD5_REQUESTS + 1))"
			case "${SCENARIO}" in
				sha_missing_md5 | sha_calc_unavailable) printf '%s\n' "${PAYLOAD_MD5}" >"$2" ;;
				md5_invalid) printf '%s\n' invalid >"$2" ;;
				md5_mismatch) printf '%032d\n' 0 >"$2" ;;
				checksum_calculation_failure) printf '%s\n' "${PAYLOAD_MD5}" >"$2" ;;
				retry_state)
					[ "${PAYLOAD_REQUESTS}" -eq 1 ] || return 1
					printf '%032d\n' 0 >"$2"
					;;
				*) return 1 ;;
			esac
			;;
		*)
			PAYLOAD_REQUESTS="$((PAYLOAD_REQUESTS + 1))"
			[ "${SCENARIO}" != download_failure ] || return 1
			cp "${PAYLOAD_FILE}" "$2"
			;;
	esac
}

# file_sha256 returns the real fixture digest unless SHA-256 calculation is unavailable.
file_sha256() {
	case "${SCENARIO}" in
		sha_calc_unavailable) return 1 ;;
	esac
	printf '%s' "${PAYLOAD_SHA256}"
}

# file_md5 returns the real fixture digest unless all checksum calculation is unavailable.
file_md5() {
	case "${SCENARIO}" in
		checksum_calculation_failure) return 1 ;;
	esac
	md5sum "$1" | awk '{ printf "%s", $1 }'
}

# chmod records publication permission changes and injects a staged chmod failure when requested.
chmod() {
	if [ "$1" = 600 ]; then
		[ "${SCENARIO}" != chmod_failure ] || return 1
	else
		FINAL_CHMOD_REQUESTS="$((FINAL_CHMOD_REQUESTS + 1))"
	fi
	return 0
}

# mv records publication and injects an atomic replacement failure when requested.
mv() {
	MV_REQUESTS="$((MV_REQUESTS + 1))"
	[ "${SCENARIO}" != mv_failure ] || return 1
	command mv "$@"
}

# assert_target_preserved verifies failures did not replace or chmod the installed target or retain staging files.
assert_target_preserved() {
	[ "$(cat "${TARGET_DIR}/component")" = 'installed target' ] || fail "${SCENARIO}: existing target was replaced"
	[ "$(ls -ld "${TARGET_DIR}/component" | cut -c1-10)" = '-rw-r-----' ] || fail "${SCENARIO}: existing target permissions changed"
	[ ! -e "${TARGET_DIR}/.component.$$" ] || fail "${SCENARIO}: staged payload remained"
}

# expect_failure requires download verification/publication to fail without changing the installed target.
expect_failure() {
	reset_case "$1"
	if download_file "${TARGET_DIR}" 755 'https://example.invalid/component' >/dev/null 2>&1; then
		fail "${SCENARIO}: download unexpectedly succeeded"
	fi
	assert_target_preserved
}

reset_case sha_match
download_file "${TARGET_DIR}" 755 'https://example.invalid/component' >/dev/null 2>&1 || fail 'matching SHA-256 was rejected'
[ "${MD5_REQUESTS}" -eq 0 ] || fail 'matching SHA-256 requested MD5 metadata'
[ "$(cat "${TARGET_DIR}/component")" = 'verified payload' ] || fail 'matching SHA-256 did not publish the payload'

for failure_case in sha_mismatch sha_invalid sha_empty; do
	expect_failure "${failure_case}"
	[ "${MD5_REQUESTS}" -eq 0 ] || fail "${failure_case}: invalid SHA-256 downgraded to MD5"
done

for fallback_case in sha_missing_md5 sha_calc_unavailable; do
	reset_case "${fallback_case}"
	download_file "${TARGET_DIR}" 755 'https://example.invalid/component' >/dev/null 2>&1 || fail "${fallback_case}: compatible MD5 fallback was rejected"
	[ "${MD5_REQUESTS}" -gt 0 ] || fail "${fallback_case}: MD5 metadata was not requested"
	[ "$(cat "${TARGET_DIR}/component")" = 'verified payload' ] || fail "${fallback_case}: compatible MD5 fallback did not publish the payload"
	grep -q 'intentional legacy-compatible MD5 verification path' "${WARNINGS_FILE}" || fail "${fallback_case}: compatibility warning was not emitted"
done

for failure_case in md5_invalid md5_mismatch both_sidecars_missing checksum_calculation_failure download_failure chmod_failure checksum_failure mv_failure; do
	expect_failure "${failure_case}"
done
expect_failure retry_state
[ "${PAYLOAD_REQUESTS}" -eq 3 ] || fail 'retry state scenario did not exhaust bounded retries'

printf '%s\n' 'PASS: installer checksum compatibility policy preserves SHA-256 preference and bounded MD5 fallback'
