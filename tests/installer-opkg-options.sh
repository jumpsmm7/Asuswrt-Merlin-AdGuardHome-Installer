#!/bin/sh
# Verify canonical Entware install options and forced-reinstall behavior.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-opkg-options.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions"
CALL_FILE="${TMP_ROOT}/opkg-call"
CANONICAL_OPTIONS='--force-depends --force-overwrite --force-reinstall'

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

sed -n '/^ensure_opkg_package() {$/,/^sha256sum_available() {$/p' "${SCRIPT_PATH}" | sed '$d' >"${FUNCTIONS_FILE}" ||
	fail 'could not extract ensure_opkg_package'
[ -s "${FUNCTIONS_FILE}" ] || fail 'ensure_opkg_package extraction was empty'

run_case() {
	case_name="$1"
	installed_status="$2"
	expected_status="$3"
	expected_call="$4"
	shift 4
	rm -f "${CALL_FILE}"
	(
		# shellcheck disable=SC1090
		. "${FUNCTIONS_FILE}"
		opkg_pkg_installed() {
			[ "${installed_status}" -eq 1 ]
		}
		opkg_clean_env() {
			printf '%s\n' "$*" >"${CALL_FILE}"
			installed_status=1
		}
		ensure_opkg_package "$@"
	) && actual_status=0 || actual_status=$?
	[ "${actual_status}" -eq "${expected_status}" ] ||
		fail "${case_name}: expected status ${expected_status}, got ${actual_status}"
	if [ -n "${expected_call}" ]; then
		[ -f "${CALL_FILE}" ] || fail "${case_name}: opkg install was not called"
		[ "$(cat "${CALL_FILE}")" = "${expected_call}" ] ||
			fail "${case_name}: unexpected opkg call: $(cat "${CALL_FILE}")"
	elif [ -e "${CALL_FILE}" ]; then
		fail "${case_name}: opkg install should have been skipped"
	fi
}

run_case installed-skip 1 0 '' jq-full
run_case installed-force-reinstall 1 0 "install jq-full ${CANONICAL_OPTIONS}" jq-full \
	--force-depends --force-overwrite --force-reinstall
run_case missing-install 0 0 "install column ${CANONICAL_OPTIONS}" column \
	--force-depends --force-overwrite --force-reinstall
run_case unsupported-option 0 1 '' jq-full --force-unsupported

if grep -E '^[[:space:]]*ensure_opkg_package[[:space:]]+[A-Za-z0-9_.+-]+' "${SCRIPT_PATH}" |
	grep -Ev -- '--force-depends --force-overwrite --force-reinstall([[:space:]]|$)' >/dev/null; then
	fail 'an ensure_opkg_package call is missing canonical Entware install options'
fi

grep -Fq 'opkg_clean_env install jq-full --force-depends --force-overwrite --force-reinstall' "${SCRIPT_PATH}" ||
	fail 'jq-full repair does not use canonical Entware install options'
grep -Fq 'install_hint="${2:-opkg install ${pkg} --force-depends --force-overwrite --force-reinstall}"' "${SCRIPT_PATH}" ||
	fail 'default preflight hint does not use canonical Entware install options'

printf '%s\n' 'PASS: Entware installs consistently support canonical force options'
