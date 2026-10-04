#!/bin/sh
# Verify jq dependency probing and jq-full installation behavior.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-jq-helper.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions"
ENTWARE_JQ="${TMP_ROOT}/opt/bin/jq"

cleanup() { rm -rf "${TMP_ROOT}"; }
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}
trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

mkdir -p "${TMP_ROOT}/bin" "${TMP_ROOT}/opt/bin" || fail 'could not create test directories'
sed -n \
	-e '/^jq_executable_usable() {$/,/^}/p' \
	-e '/^jq_available() {$/,/^}/p' \
	-e '/^ensure_jq_tool() {$/,/^}/p' \
	"${SCRIPT_PATH}" | sed "s|/opt/bin/jq|${ENTWARE_JQ}|g" >"${FUNCTIONS_FILE}" ||
	fail 'could not extract jq helpers'
[ -s "${FUNCTIONS_FILE}" ] || fail 'jq helper extraction was empty'

make_jq() {
	path="$1"
	status="$2"
	cat >"${path}" <<EOF
#!/bin/sh
cat >/dev/null
exit ${status}
EOF
	chmod 755 "${path}" || return 1
}

run_case() {
	case_name="$1"
	resolved_status="$2"
	entware_status="$3"
	install_status="$4"
	post_install_status="$5"
	expected_status="$6"
	package_registered="${7:-0}"
	case_root="${TMP_ROOT}/${case_name}"
	mkdir -p "${case_root}" || return 1
	rm -f "${TMP_ROOT}/bin/jq" "${ENTWARE_JQ}"
	[ "${resolved_status}" = missing ] || make_jq "${TMP_ROOT}/bin/jq" "${resolved_status}"
	[ "${entware_status}" = missing ] || make_jq "${ENTWARE_JQ}" "${entware_status}"
	(
		# shellcheck disable=SC1090
		. "${FUNCTIONS_FILE}"
		PTXT() { printf '%s\n' "$*"; }
		ptxt_warn() { PTXT "$*"; }
		ptxt_step() { PTXT "$*"; }
		ptxt_fail() { PTXT "$*"; }
		ptxt_ok() { PTXT "$*"; }
		INFO=INFO
		which() {
			[ "$1" = jq ] || return 1
			[ -x "${TMP_ROOT}/bin/jq" ] || return 1
			printf '%s\n' "${TMP_ROOT}/bin/jq"
		}
		opkg_pkg_installed() {
			[ "$1" = jq-full ] && [ "${package_registered}" -eq 1 ]
		}
		opkg_clean_env() {
			[ "$#" -eq 5 ] || return 1
			[ "$1" = install ] || return 1
			[ "$2" = jq-full ] || return 1
			[ "$3" = --force-depends ] || return 1
			[ "$4" = --force-overwrite ] || return 1
			[ "$5" = --force-reinstall ] || return 1
			[ "${install_status}" -eq 0 ] || return 1
			make_jq "${ENTWARE_JQ}" "${post_install_status}"
		}
		ensure_opkg_package() {
			[ "$#" -eq 4 ] || return 1
			[ "$1" = jq-full ] || return 1
			[ "$2" = --force-depends ] || return 1
			[ "$3" = --force-overwrite ] || return 1
			[ "$4" = --force-reinstall ] || return 1
			[ "${install_status}" -eq 0 ] || return 1
			make_jq "${ENTWARE_JQ}" "${post_install_status}"
		}
		ensure_jq_tool >"${case_root}/output" 2>&1
	) && actual_status=0 || actual_status=$?
	[ "${actual_status}" -eq "${expected_status}" ] ||
		fail "${case_name}: expected status ${expected_status}, got ${actual_status}"
}

run_case stock-ok 0 missing 1 1 0
run_case entware-ok missing 0 1 1 0
run_case broken-present 1 missing 1 1 1
run_case install-ok missing missing 0 0 0
run_case install-failed missing missing 1 0 1
run_case install-unusable missing missing 0 1 1
run_case repair-installed-unusable missing 1 0 0 0 1

printf '%s\n' 'PASS: jq helpers require functional JSON parsing and jq-full installation'
