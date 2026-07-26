#!/bin/sh
# Verify every IPSET refresh dry-run path returns before persistent LAN-mode cleanup.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-cli-ipset-dry-run.$$"
FUNCTION_FILE="${TMP_ROOT}/cli-run"
CHECK_FILE="${TMP_ROOT}/check-ipset"
DRY_RUN_FILE="${TMP_ROOT}/dry-run"
DETECT_FILE="${TMP_ROOT}/detect-mode"

# cleanup removes the temporary test directory and its contents.
cleanup() {
	rm -rf "${TMP_ROOT}"
}

# fail prints a failure message to standard error and exits with status 1.
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
INSTALL_MODE_DETECTION='lan'

# PTXT appends a message to the dry-run output file.
PTXT() {
	printf '%s\n' "$*" >>"${DRY_RUN_FILE}"
}

#adguard_ipset_allowed determines whether AdGuard IPSET operations are allowed for the current installation mode.
adguard_ipset_allowed() {
	[ "${INSTALL_MODE}" = 'wan' ]
}

# adguard_install_mode_confirmed reports whether the current detection is safe for mutating mode-dependent state.
adguard_install_mode_confirmed() {
	case "${INSTALL_MODE_DETECTION}" in
		wan | lan) return 0 ;;
		*) return 1 ;;
	esac
}

# adguard_install_mode_detect records each live mode-detection attempt.
adguard_install_mode_detect() {
	printf '%s\n' "${INSTALL_MODE_DETECTION}" >>"${DETECT_FILE}"
}

# branch_is_safe always reports that the current branch is safe.
branch_is_safe() {
	return 0
}

# check_ipset records an IPSET check message in the check file.
check_ipset() {
	printf '%s\n' "$1" >>"${CHECK_FILE}"
}

# conf_value prints the configured value used by the test harness.
conf_value() {
	printf '%s\n' 'YES'
}

# ptxt_ok is a no-op placeholder for successful preview output handling.
ptxt_ok() {
	:
}

# ipset_status fails if a mode-independent status path reaches live IPSET inspection in LAN mode.
ipset_status() {
	fail 'LAN-mode IPSET status unexpectedly inspected live IPSET state'
}

# write_conf is a stub that always succeeds.
write_conf() {
	return 0
}

# run_dry_run_case executes an IPSET refresh dry-run for the specified installation mode and verifies that it reports a preview without performing persistent cleanup.
run_dry_run_case() {
	case_name="$1"
	INSTALL_MODE="$2"
	shift 2
	: >"${CHECK_FILE}"
	: >"${DRY_RUN_FILE}"
	: >"${DETECT_FILE}"

	cli_run ipset refresh "$@" || fail "${case_name}: dry-run failed"
	[ ! -s "${CHECK_FILE}" ] || fail "${case_name}: dry-run called persistent IPSET cleanup"
	[ ! -s "${DETECT_FILE}" ] || fail "${case_name}: dry-run performed live install-mode detection"
	grep -q 'Dry-run: would run IPSET refresh' "${DRY_RUN_FILE}" || fail "${case_name}: dry-run preview was not reported"
}

# run_remote_dry_run_case executes and validates an IPSET refresh pre-initialization dry-run case.
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
: >"${DETECT_FILE}"
INSTALL_MODE='lan'
INSTALL_MODE_DETECTION='lan'
if cli_run ipset refresh; then
	fail 'non-dry-run LAN refresh should still be refused'
fi
[ "$(cat "${DETECT_FILE}")" = 'lan' ] || fail 'non-dry-run LAN refresh did not confirm the current install mode'
grep -q '^0$' "${CHECK_FILE}" || fail 'non-dry-run LAN refresh did not disable stale IPSET state'

: >"${CHECK_FILE}"
: >"${DETECT_FILE}"
INSTALL_MODE='wan'
INSTALL_MODE_DETECTION='unknown'
if cli_run ipset refresh --yes; then
	fail 'unknown-mode IPSET refresh should be refused'
fi
[ "$(cat "${DETECT_FILE}")" = 'unknown' ] || fail 'unknown-mode IPSET refresh did not perform live mode detection'
[ ! -s "${CHECK_FILE}" ] || fail 'unknown-mode IPSET refresh changed IPSET state'
grep -q 'IPSET refresh requires a confirmed router install mode' "${DRY_RUN_FILE}" ||
	fail 'unknown-mode IPSET refresh did not explain the confirmation requirement'

: >"${DETECT_FILE}"
INSTALL_MODE='lan'
INSTALL_MODE_DETECTION='unknown'
cli_run ipset status || fail 'IPSET status was blocked when install-mode detection was unknown'
cli_run ipset doctor || fail 'IPSET doctor was blocked when install-mode detection was unknown'
[ ! -s "${DETECT_FILE}" ] || fail 'IPSET status or doctor unnecessarily required live mode detection'

printf '%s\n' 'PASS: IPSET refresh requires confirmed mode while dry-runs remain non-mutating'
