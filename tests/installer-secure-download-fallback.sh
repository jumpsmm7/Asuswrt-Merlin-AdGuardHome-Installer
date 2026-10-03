#!/bin/sh
# Verify installer downloads never disable TLS certificate verification.
set -u

INSTALLER="${1:-installer}"
README_PATH="${2:-README.md}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/installer-secure-download.XXXXXX")" || exit 1
FUNCTIONS_FILE="${TMP_ROOT}/functions"
METADATA_FUNCTIONS_FILE="${TMP_ROOT}/metadata-functions"
CALLS_FILE="${TMP_ROOT}/calls"
ERROR_FILE="${TMP_ROOT}/errors"

cleanup() { rm -rf "${TMP_ROOT}"; }
fail() { printf '%s\n' "FAIL: $*" >&2; exit 1; }
trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

sed -n '/^http_get_file() {$/,/^}$/p' "${INSTALLER}" >"${FUNCTIONS_FILE}" || fail 'could not extract http_get_file'
[ -s "${FUNCTIONS_FILE}" ] || fail 'http_get_file extraction was empty'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

curl_common_args() { printf '%s' '--retry 5 --max-time 125'; }
wget_common_args() { printf '%s' '--tries=5 --timeout=25'; }
wget_has_option() { [ "$1" = '--server-response' ]; }

DOWNLOADER=curl
DOWNLOAD_STATUS=0
ai_have_cmd() { [ "$1" = "${DOWNLOADER}" ]; }

curl() {
	printf '%s\n' "curl $*" >>"${CALLS_FILE}"
	_out=
	_next=0
	for _arg in "$@"; do
		if [ "${_next}" -eq 1 ]; then _out="${_arg}"; _next=0; continue; fi
		[ "${_arg}" = -o ] && _next=1
	done
	[ -n "${_out}" ] || return 2
	if [ "${DOWNLOAD_STATUS}" -eq 0 ]; then printf '%s\n' verified >"${_out}"; return 0; fi
	printf '%s\n' 'curl: (60) certificate verification failed' >&2
	printf '%s\n' partial >"${_out}"
	return "${DOWNLOAD_STATUS}"
}

wget() {
	printf '%s\n' "wget $*" >>"${CALLS_FILE}"
	_out=
	_next=0
	for _arg in "$@"; do
		if [ "${_next}" -eq 1 ]; then _out="${_arg}"; _next=0; continue; fi
		[ "${_arg}" = -O ] && _next=1
	done
	[ -n "${_out}" ] || return 2
	if [ "${DOWNLOAD_STATUS}" -eq 0 ]; then printf '%s\n' verified >"${_out}"; return 0; fi
	printf '%s\n' 'wget: certificate verification failed' >&2
	printf '%s\n' partial >"${_out}"
	return "${DOWNLOAD_STATUS}"
}

run_success() {
	DOWNLOADER="$1"
	DOWNLOAD_STATUS=0
	: >"${CALLS_FILE}"
	http_get_file 'https://example.invalid/component' "${TMP_ROOT}/out" '' insecure 2>"${ERROR_FILE}" ||
		fail "verified ${DOWNLOADER} request failed"
	[ "$(wc -l <"${CALLS_FILE}")" -eq 1 ] || fail "${DOWNLOADER} success retried"
	[ "$(cat "${TMP_ROOT}/out")" = verified ] || fail "${DOWNLOADER} success output was not retained"
}

run_failure() {
	DOWNLOADER="$1"
	case "${DOWNLOADER}" in curl) DOWNLOAD_STATUS=60 ;; wget) DOWNLOAD_STATUS=5 ;; esac
	: >"${CALLS_FILE}"
	if http_get_file 'https://example.invalid/component' "${TMP_ROOT}/out" '' insecure 2>"${ERROR_FILE}"; then
		fail "${DOWNLOADER} certificate failure returned success"
	fi
	[ "$(wc -l <"${CALLS_FILE}")" -eq 1 ] || fail "${DOWNLOADER} certificate failure retried insecurely"
	grep -q 'certificate verification failed' "${ERROR_FILE}" || fail "${DOWNLOADER} certificate error was suppressed"
}

run_success curl
run_failure curl
run_success wget
run_failure wget

if grep -E -- '(^|[[:space:]])(-k|--insecure|--no-check-certificate)([[:space:]]|$)' "${CALLS_FILE}" >/dev/null 2>&1; then
	fail 'a downloader used a certificate-verification bypass flag'
fi
if grep -qE 'curl_insecure_arg|wget_insecure_arg|ALLOW_INSECURE|certificate verification disabled' "${INSTALLER}"; then
	fail 'installer retains certificate-verification fallback logic'
fi
if grep -E 'http_get_file .* insecure' "${INSTALLER}" >/dev/null 2>&1; then
	fail 'installer retains an insecure http_get_file caller'
fi

sed -n '/^init_adguard_metadata_defaults() {$/,/^}$/p; /^init_remote_adguard_metadata() {$/,/^}$/p; /^init_upstream_adguard_metadata() {$/,/^}$/p' "${INSTALLER}" >"${METADATA_FUNCTIONS_FILE}" ||
	fail 'could not extract metadata download helpers'
# shellcheck disable=SC1090
. "${METADATA_FUNCTIONS_FILE}"
ADGUARD_ARCH=arm64
ADGUARD_METADATA_DIR="${TMP_ROOT}/metadata"
ADGUARD_METADATA_FILE="${ADGUARD_METADATA_DIR}/checksum.txt"
ADGUARD_METADATA_DIR_OWNED=0
URL_ARCH='https://example.invalid/channel'
METADATA_CALLS_FILE="${TMP_ROOT}/metadata-calls"
: >"${METADATA_CALLS_FILE}"
metadata_workspace_create() { mkdir -p "${ADGUARD_METADATA_DIR}"; ADGUARD_METADATA_DIR_OWNED=1; }
metadata_workspace_is_private() { return 0; }
cleanup_api_files() { :; }
ptxt_phase() { :; }
ptxt_warn() { :; }
ptxt_ok() { :; }
PTXT() { :; }
sleep() { :; }
http_get_file() { printf '%s\n' "$1" >>"${METADATA_CALLS_FILE}"; return 60; }
if (init_remote_adguard_metadata); then
	fail 'metadata initialization accepted certificate-verification failures'
fi
[ "$(wc -l <"${METADATA_CALLS_FILE}")" -eq 6 ] || fail 'metadata failure did not preserve three bounded channel and upstream attempts'

grep -Fq 'never retries with `curl --insecure`/`-k` or `wget --no-check-certificate`' "${README_PATH}" ||
	fail 'download policy does not prohibit certificate-verification bypasses'

printf '%s\n' 'PASS: installer downloads retain TLS certificate verification'
