#!/bin/sh
# Verify tzdata transport and publication recovery without live network access.
set -u

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
SCRIPT_PATH="${1:-${ROOT_DIR}/tools/update-tzdata.sh}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tzdata-safety.XXXXXX")" || exit 1
FUNCTIONS_FILE="${TMP_ROOT}/functions"
CALLS_FILE="${TMP_ROOT}/calls"

cleanup() { rm -rf "${TMP_ROOT}"; }
fail() { printf '%s\n' "FAIL: $*" >&2; exit 1; }
trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

if grep -Eq 'for protocol in https http|http://|--proto ['"'"']?=http['"'"']?([[:space:]]|$)|--proto-redir ['"'"']?=http['"'"']?([[:space:]]|$)' "${SCRIPT_PATH}"; then
	fail 'tzdata updater retains plaintext HTTP transport'
fi
[ "$(grep -c -- "--proto '=https' --proto-redir '=https'" "${SCRIPT_PATH}")" -eq 3 ] ||
	fail 'every tzdata request must restrict requests and redirects to HTTPS'
grep -Fq "trap 'exit 129' HUP" "${SCRIPT_PATH}" || fail 'HUP publication rollback trap is missing'
grep -Fq "trap 'exit 130' INT" "${SCRIPT_PATH}" || fail 'INT publication rollback trap is missing'
grep -Fq "trap 'exit 143' TERM" "${SCRIPT_PATH}" || fail 'TERM publication rollback trap is missing'

sed -n '/^download_verified_pair() {$/,/^}$/p; /^discover_package_filename() {$/,/^}$/p; /^publication_targets_remove() {$/,/^}$/p; /^publication_rollback() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" ||
	fail 'could not extract updater helpers'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

stage_dir="${TMP_ROOT}/stage"
mkdir "${stage_dir}"
MIRROR_HOSTS='first.invalid second.invalid'
CURL_CA_BUNDLE="${TMP_ROOT}/ca.pem"
: >"${CURL_CA_BUNDLE}"
CURL_MODE=valid
curl() {
	printf '%s\n' "$*" >>"${CALLS_FILE}"
	_url=
	_out=
	_next=0
	for _arg in "$@"; do
		if [ "${_next}" -eq 1 ]; then _out="${_arg}"; _next=0; continue; fi
		[ "${_arg}" = --output ] && _next=1
		case "${_arg}" in https://*) _url="${_arg}" ;; esac
	done
	case "${_url}" in https://first.invalid/*) return 60 ;; esac
	case "${CURL_MODE}:${_url}" in
		invalid-signature:*.sig) printf '%s\n' invalid >"${_out}" ;;
		*:*'.sig') printf '%s\n' signature >"${_out}" ;;
		*:*'/core/') printf '%s\n' 'tzdata-2026c-1-aarch64.pkg.tar.bz2' >"${_out}" ;;
		*) printf '%s\n' package >"${_out}" ;;
	esac
}
verify_signature() { [ "$(cat "$2")" = signature ]; }

: >"${CALLS_FILE}"
filename="$(discover_package_filename aarch64)" || fail 'HTTPS mirror failover did not discover a package'
[ "${filename}" = 'tzdata-2026c-1-aarch64.pkg.tar.bz2' ] || fail 'unexpected discovered package filename'
[ "$(grep -c 'https://first.invalid' "${CALLS_FILE}")" -eq 1 ] || fail 'first HTTPS listing mirror was not attempted'
[ "$(grep -c 'https://second.invalid' "${CALLS_FILE}")" -eq 1 ] || fail 'second HTTPS listing mirror was not attempted'

: >"${CALLS_FILE}"
download_verified_pair 'aarch64/core/package' "${stage_dir}/package" 300 || fail 'valid HTTPS package/signature pair failed'
[ "$(cat "${stage_dir}/package")" = package ] || fail 'verified package was not retained'
if grep -E -- 'http://|--insecure|(^|[[:space:]])-k([[:space:]]|$)' "${CALLS_FILE}" >/dev/null 2>&1; then
	fail 'tzdata request used insecure transport options'
fi

CURL_MODE=invalid-signature
if download_verified_pair 'aarch64/core/package' "${stage_dir}/invalid" 300 >/dev/null 2>&1; then
	fail 'invalid package signature was accepted'
fi
[ ! -e "${stage_dir}/invalid" ] || fail 'failed signature left a package staged for publication'
CURL_MODE=valid

PUBLISH_DIR="${TMP_ROOT}/publish"
backup_dir="${TMP_ROOT}/backup"
mkdir "${PUBLISH_DIR}" "${backup_dir}"
cd "${PUBLISH_DIR}" || fail 'could not enter publication fixture'
printf '%s\n' old-aarch64 >tzdata-old-aarch64.pkg.tar.bz2
printf '%s\n' old-arm >tzdata-old-arm.pkg.tar.bz2
printf '%s\n' old-installer >installer
cp -p tzdata-old-aarch64.pkg.tar.bz2 tzdata-old-arm.pkg.tar.bz2 installer "${backup_dir}/"
printf '%s\n' new-aarch64 >tzdata-new-aarch64.pkg.tar.bz2
printf '%s\n' new-sidecar >tzdata-new-aarch64.pkg.tar.bz2.md5sum
publication_active=1
backup_retain=0
publication_rollback || fail 'publication rollback failed'
[ "$(cat tzdata-old-aarch64.pkg.tar.bz2)" = old-aarch64 ] || fail 'rollback did not restore aarch64 package'
[ "$(cat tzdata-old-arm.pkg.tar.bz2)" = old-arm ] || fail 'rollback did not restore ARM package'
[ "$(cat installer)" = old-installer ] || fail 'rollback did not restore installer'
[ ! -e tzdata-new-aarch64.pkg.tar.bz2 ] || fail 'rollback retained a newly introduced package'
[ ! -e tzdata-new-aarch64.pkg.tar.bz2.md5sum ] || fail 'rollback retained a newly introduced sidecar'

printf '%s\n' 'PASS: tzdata downloads are HTTPS-only and publication rollback restores originals'
