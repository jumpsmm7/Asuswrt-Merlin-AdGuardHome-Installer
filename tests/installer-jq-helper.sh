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

# Execute the selected update menu seam with a missing parser and real jq repair.
sed -n '/^menu() {$/,/^}/p' "${SCRIPT_PATH}" >"${TMP_ROOT}/menu-functions"
rm -f "${TMP_ROOT}/bin/jq" "${ENTWARE_JQ}"
(
	. "${FUNCTIONS_FILE}"
	. "${TMP_ROOT}/menu-functions"
	INFO=INFO ERROR=ERROR
	# PTXT captures selected-menu diagnostics without terminal formatting.
	PTXT() { printf '%s\n' "$*"; }
	# ptxt_warn retains warning text while avoiding terminal formatting.
	ptxt_warn() { PTXT "$*"; }
	# ptxt_step retains progress text while avoiding terminal formatting.
	ptxt_step() { PTXT "$*"; }
	# ptxt_fail retains failure text while avoiding terminal formatting.
	ptxt_fail() { PTXT "$*"; }
	# ptxt_ok retains success text while avoiding terminal formatting.
	ptxt_ok() { PTXT "$*"; }
	# ptxt_phase retains phase text while avoiding terminal formatting.
	ptxt_phase() { PTXT "$*"; }
	# end_op_message returns the operation status without restarting the installer.
	end_op_message() { return "${1:-0}"; }
	# which forces the selected update to repair its missing PATH-resolved parser.
	which() { return 1; }
	# opkg_pkg_installed models jq-full as unregistered so the action must install it.
	opkg_pkg_installed() { return 1; }
	# ensure_opkg_package verifies the canonical jq-full flags and installs a usable fixture parser.
	ensure_opkg_package() {
		printf '%s\n' "$*" >>"${TMP_ROOT}/action-packages"
		[ "$*" = 'jq-full --force-depends --force-overwrite --force-reinstall' ] || return 1
		make_jq "${ENTWARE_JQ}" 0
	}
	# inst_AdGuardHome records update orchestration only after a usable parser has been repaired.
	inst_AdGuardHome() {
		[ "$1" = update ] && jq_available || return 1
		: >"${TMP_ROOT}/action-reached"
	}
	menu update
) >"${TMP_ROOT}/action-output" 2>&1 || fail 'selected update failed to bootstrap its missing parser'
[ -f "${TMP_ROOT}/action-reached" ] || fail 'selected update did not reach orchestration after jq repair'
[ "$(wc -l <"${TMP_ROOT}/action-packages" | tr -d ' ')" -eq 1 ] || fail 'selected update installed unrelated packages'

printf '%s\n' 'PASS: jq helpers require functional JSON parsing and jq-full installation'
