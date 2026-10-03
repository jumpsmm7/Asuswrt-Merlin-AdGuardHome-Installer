#!/bin/sh
# Verify installer version checks bypass stale, independently cached artifacts.

set -u

SCRIPT_PATH="${1:-installer}"
TEST_ROOT="${TMPDIR:-/tmp}/installer-version-cache-busting.$$"
FUNCTIONS_FILE="${TEST_ROOT}/functions"

cleanup() {
	rm -rf "${TEST_ROOT}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
mkdir -p "${TEST_ROOT}" || fail 'could not create test directory'

sed -n '/^http_url_with_cache_token() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" ||
	fail "could not read cache-token helper from ${SCRIPT_PATH}"
[ -s "${FUNCTIONS_FILE}" ] || fail 'cache-token helper was not found'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

[ "$(http_url_with_cache_token 'https://example.invalid/installer' '123-0')" = 'https://example.invalid/installer?installer_check=123-0' ] ||
	fail 'cache token was not added to a URL without a query'
[ "$(http_url_with_cache_token 'https://example.invalid/installer?ref=test' '123-1')" = 'https://example.invalid/installer?ref=test&installer_check=123-1' ] ||
	fail 'cache token did not preserve an existing query'

CHECK_VERSION_BODY="$(sed -n '/^check_version() {$/,/^setup_AdGuardHome() {$/p' "${SCRIPT_PATH}")"
printf '%s\n' "${CHECK_VERSION_BODY}" | grep -q 'REMOTE_CACHE_TOKEN="\$\$-${varcnt}"' ||
	fail 'version check does not change its cache token between retry attempts'
printf '%s\n' "${CHECK_VERSION_BODY}" | grep -q 'http_url_with_cache_token "${RURL}/installer" "${REMOTE_CACHE_TOKEN}"' ||
	fail 'version check does not cache-bust the installer payload'
printf '%s\n' "${CHECK_VERSION_BODY}" | grep -q 'http_url_with_cache_token "${RURL}/installer.md5sum" "${REMOTE_CACHE_TOKEN}"' ||
	fail 'version check does not cache-bust the installer checksum sidecar'

printf '%s\n' 'PASS: installer version checks bypass stale payload and checksum caches'
