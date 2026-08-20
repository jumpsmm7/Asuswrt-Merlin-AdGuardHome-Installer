#!/bin/sh
# Verify installer downloads use certificate verification before any insecure fallback.
set -u

INSTALLER="${1:-installer}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/installer-secure-download.XXXXXX")" || exit 1
FUNCTIONS_FILE="${TMP_ROOT}/functions"
CALLS_FILE="${TMP_ROOT}/calls"
WARN_FILE="${TMP_ROOT}/warnings"

cleanup() { rm -rf "${TMP_ROOT}"; }
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}
trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

sed -n '/^http_get_file() {$/,/^}$/p' "${INSTALLER}" >"${FUNCTIONS_FILE}" || fail 'could not extract http_get_file'
[ -s "${FUNCTIONS_FILE}" ] || fail 'http_get_file extraction was empty'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

ptxt_warn() { printf '%s\n' "$*" >>"${WARN_FILE}"; }
curl_common_args() { :; }
curl_insecure_arg() { printf '%s' ' -k'; }
wget_common_args() { :; }
wget_insecure_arg() { printf '%s' ' --no-check-certificate'; }
wget_has_option() { [ "$1" = '--server-response' ]; }

DOWNLOADER='curl'
SECURE_STATUS=0
ai_have_cmd() { [ "$1" = "${DOWNLOADER}" ]; }

curl() {
	printf '%s\n' "curl $*" >>"${CALLS_FILE}"
	_out=''
	_next=0
	for _arg in "$@"; do
		if [ "${_next}" -eq 1 ]; then
			_out="${_arg}"
			_next=0
			continue
		fi
		[ "${_arg}" = '-o' ] && _next=1
	done
	case " $* " in
		*' -k '*)
			printf '%s\n' fallback >"${_out}"
			return 0
			;;
	esac
	[ "${SECURE_STATUS}" -eq 0 ] && {
		printf '%s\n' secure >"${_out}"
		return 0
	}
	printf '%s\n' partial >"${_out}"
	return "${SECURE_STATUS}"
}

wget() {
	printf '%s\n' "wget $*" >>"${CALLS_FILE}"
	_out=''
	_next=0
	for _arg in "$@"; do
		if [ "${_next}" -eq 1 ]; then
			_out="${_arg}"
			_next=0
			continue
		fi
		[ "${_arg}" = '-O' ] && _next=1
	done
	case " $* " in
		*' --no-check-certificate '*)
			printf '%s\n' fallback >"${_out}"
			return 0
			;;
	esac
	[ "${SECURE_STATUS}" -eq 0 ] && {
		printf '%s\n' secure >"${_out}"
		return 0
	}
	printf '%s\n' partial >"${_out}"
	return "${SECURE_STATUS}"
}

: >"${CALLS_FILE}"
: >"${WARN_FILE}"
SECURE_STATUS=0
http_get_file 'https://example.invalid/component' "${TMP_ROOT}/out" '' insecure || fail 'secure curl request failed'
[ "$(wc -l <"${CALLS_FILE}")" -eq 1 ] || fail 'secure curl success retried unnecessarily'
! grep -q ' -k ' "${CALLS_FILE}" || fail 'secure curl success used -k'
[ "$(cat "${TMP_ROOT}/out")" = secure ] || fail 'secure curl output was not published'

: >"${CALLS_FILE}"
: >"${WARN_FILE}"
SECURE_STATUS=60
http_get_file 'https://example.invalid/component' "${TMP_ROOT}/out" '' insecure || fail 'curl insecure fallback did not recover certificate failure'
[ "$(wc -l <"${CALLS_FILE}")" -eq 2 ] || fail 'curl fallback did not make exactly two attempts'
! sed -n '1p' "${CALLS_FILE}" | grep -q ' -k ' || fail 'first curl attempt disabled certificate verification'
sed -n '2p' "${CALLS_FILE}" | grep -q ' -k ' || fail 'second curl attempt did not use -k fallback'
grep -q 'certificate verification disabled' "${WARN_FILE}" || fail 'curl insecure fallback was not logged'
[ "$(cat "${TMP_ROOT}/out")" = fallback ] || fail 'curl insecure fallback did not publish fallback output'

: >"${CALLS_FILE}"
if http_get_file 'http://example.invalid/component' "${TMP_ROOT}/out" '' insecure; then
	fail 'plain HTTP failure incorrectly used insecure fallback'
fi
[ "$(wc -l <"${CALLS_FILE}")" -eq 1 ] || fail 'plain HTTP failure retried with insecure mode'

DOWNLOADER='wget'
: >"${CALLS_FILE}"
: >"${WARN_FILE}"
SECURE_STATUS=0
http_get_file 'https://example.invalid/component' "${TMP_ROOT}/out" '' insecure || fail 'secure wget request failed'
[ "$(wc -l <"${CALLS_FILE}")" -eq 1 ] || fail 'secure wget success retried unnecessarily'
! grep -q -e '--no-check-certificate' "${CALLS_FILE}" || fail 'secure wget success disabled certificate verification'

: >"${CALLS_FILE}"
: >"${WARN_FILE}"
SECURE_STATUS=5
http_get_file 'https://example.invalid/component' "${TMP_ROOT}/out" '' insecure || fail 'wget insecure fallback did not recover certificate failure'
[ "$(wc -l <"${CALLS_FILE}")" -eq 2 ] || fail 'wget fallback did not make exactly two attempts'
! sed -n '1p' "${CALLS_FILE}" | grep -q -e '--no-check-certificate' || fail 'first wget attempt disabled certificate verification'
sed -n '2p' "${CALLS_FILE}" | grep -q -e '--no-check-certificate' || fail 'second wget attempt did not use certificate fallback'
grep -q 'certificate verification disabled' "${WARN_FILE}" || fail 'wget insecure fallback was not logged'
[ "$(cat "${TMP_ROOT}/out")" = fallback ] || fail 'wget insecure fallback did not publish fallback output'

printf '%s\n' 'PASS: installer secure-first transport fallback'
