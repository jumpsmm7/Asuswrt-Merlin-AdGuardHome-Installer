#!/bin/sh
# Verify every IPSET refresh dry-run path returns before persistent LAN-mode cleanup.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-cli-ipset-dry-run.$$"
FUNCTION_FILE="${TMP_ROOT}/cli-run"
CHECK_FILE="${TMP_ROOT}/check-ipset"
DRY_RUN_FILE="${TMP_ROOT}/dry-run"

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
sed -n '/^cli_dry_run() {$/,/^}$/p; /^cli_pre_remote_dry_run() {$/,/^}$/p; /^cli_run() {$/,/^}$/p' \
	"${SCRIPT_PATH}" >"${FUNCTION_FILE}" ||
	fail 'could not extract cli_run'
[ -s "${FUNCTION_FILE}" ] || fail 'cli_run extraction was empty'
grep -q '^cli_pre_remote_dry_run() {$' "${FUNCTION_FILE}" || fail 'remote dry-run helper extraction was empty'

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

INFO='Info:'
WARNING='Warning:'
ERROR='Error:'
INSTALL_MODE='lan'

PTXT() {
	printf '%s\n' "$*" >>"${DRY_RUN_FILE}"
}

adguard_ipset_allowed() {
	[ "${INSTALL_MODE}" = 'wan' ]
}

branch_is_safe() {
	return 0
}

check_ipset() {
	printf '%s\n' "$1" >>"${CHECK_FILE}"
}

conf_value() {
	printf '%s\n' 'YES'
}

ptxt_ok() {
	:
}

write_conf() {
	return 0
}

run_dry_run_case() {
	case_name="$1"
	INSTALL_MODE="$2"
	shift 2
	: >"${CHECK_FILE}"
	: >"${DRY_RUN_FILE}"

	cli_run ipset refresh "$@" || fail "${case_name}: dry-run failed"
	[ ! -s "${CHECK_FILE}" ] || fail "${case_name}: dry-run called persistent IPSET cleanup"
	grep -q 'Dry-run: would run IPSET refresh' "${DRY_RUN_FILE}" || fail "${case_name}: dry-run preview was not reported"
}

run_remote_dry_run_case() {
	case_name="$1"
	shift
	: >"${CHECK_FILE}"
	: >"${DRY_RUN_FILE}"

	cli_pre_remote_dry_run ipset refresh "$@" || fail "${case_name}: pre-initialization dry-run failed"
	[ ! -s "${CHECK_FILE}" ] || fail "${case_name}: pre-initialization dry-run called IPSET cleanup"
	grep -q 'Dry-run: would run IPSET refresh' "${DRY_RUN_FILE}" ||
		fail "${case_name}: pre-initialization preview was not reported"
}

# Exercise both accepted option positions and both install-mode decision paths.
run_dry_run_case lan-option-last lan --dry-run
run_dry_run_case lan-option-first lan --dry-run --yes
run_dry_run_case wan-option-last wan --dry-run
run_dry_run_case wan-option-first wan --dry-run --yes
run_remote_dry_run_case remote-option-last --yes --dry-run
run_remote_dry_run_case remote-option-first --dry-run --yes

: >"${CHECK_FILE}"
INSTALL_MODE='lan'
if cli_run ipset refresh; then
	fail 'non-dry-run LAN refresh should still be refused'
fi
grep -q '^0$' "${CHECK_FILE}" || fail 'non-dry-run LAN refresh did not disable stale IPSET state'

printf '%s\n' 'PASS: IPSET refresh dry-runs never persist LAN-mode cleanup'
