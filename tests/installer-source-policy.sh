#!/bin/sh
# Exercise the real startup source selection before ordinary writes or downloads.
set -u
INSTALLER_PATH="${1:-installer}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/installer-source-policy.XXXXXX")" || exit 1
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}
cleanup() { rm -rf "${TEST_ROOT}"; }
trap cleanup 0
trap 'exit 1' HUP INT TERM
sed -n '/^nvram_transaction_recovery_dependencies_available || exit 1$/,/^write_conf INSTALLER_BRANCH /p' "${INSTALLER_PATH}" >"${TEST_ROOT}/startup"
[ -s "${TEST_ROOT}/startup" ] || fail 'startup extraction empty'
sed -n '/^branch_is_safe() {$/,/^}/p; /^sanitize_branch() {$/,/^}/p; /^cli_installer_branch_from_args() {$/,/^}/p; /^resolve_installer_branch() {$/,/^}/p; /^cli_fresh_install_supported() {$/,/^}/p; /^installer_update_policy_from_args() {$/,/^}/p; /^installer_requested_bundle_update_allowed() {$/,/^}/p' "${INSTALLER_PATH}" >"${TEST_ROOT}/helpers"
sed -n '/^conf_value() {$/,/^}/p' "${INSTALLER_PATH}" >"${TEST_ROOT}/conf-function"
run_case() {
	case_name="$1"
	saved="$2"
	expected_status="$3"
	expected_source="$4"
	shift 4
	(
		set +u
		. "${TEST_ROOT}/helpers"
		PTXT() { printf '%s\n' "$*"; }
		ERROR=ERROR WARNING=WARNING INFO=INFO
		TARG_DIR="${TEST_ROOT}/target" AGH_FILE="${TEST_ROOT}/target/AdGuardHome"
		BLOCKLIST_ANALYZER_SHA256=present
		# Use the real configuration reader and inject failure at its awk boundary.
		. "${TEST_ROOT}/conf-function"
		CONF_FILE="${TEST_ROOT}/${case_name}.config"
		CONFIG_READ_ERROR=0
		case "${saved}" in
			__absent__) ;;
			__missing-key__) printf '%s\n' 'ADGUARD_INSTALL_MODE="wan"' >"${CONF_FILE}" ;;
			__read-error__)
				CONFIG_READ_ERROR=1
				printf '%s\n' 'INSTALLER_BRANCH="v2.6.7"' 'ADGUARD_INSTALL_MODE="wan"' >"${CONF_FILE}"
				;;
			*) printf 'INSTALLER_BRANCH="%s"\nADGUARD_INSTALL_MODE="wan"\n' "${saved}" >"${CONF_FILE}" ;;
		esac
		awk() {
			if [ "${CONFIG_READ_ERROR}" -eq 1 ]; then
				for awk_arg in "$@"; do
					if [ "${awk_arg}" = KEY=INSTALLER_BRANCH ]; then
						: >"${TEST_ROOT}/${case_name}.saved-read-failed"
						return 2
					fi
				done
			fi
			command awk "$@"
		}
		conf_has_key() { return 0; }
		write_conf() { printf '%s %s\n' "$1" "$2" >>"${TEST_ROOT}/${case_name}.writes"; }
		nvram_transaction_recovery_dependencies_available() { return 0; }
		on_installer_exit() { :; }
		adguard_committed_binary_cleanup_retry() { return 0; }
		all_event_scripts_recover_startup() { return 0; }
		nvram_transaction_recover_startup() {
			: >"${TEST_ROOT}/${case_name}.recovered"
			return 0
		}
		cli_pre_remote_dry_run() { case "$*" in *--dry-run*)
			printf '%s\n' preview
			return 0
			;;
		*) return 1 ;; esac }
		cli_pre_runtime_defaults_preview() { return 1; }
		adguard_install_mode_detect() {
			ADGUARD_INSTALL_MODE=wan
			return 0
		}
		adguard_install_mode_confirmed() { return 0; }
		amtm_update_check() { return 0; }
		installer_dependencies_available() { return 0; }
		single_arg_menu_action() { case "$1" in install | update) return 0 ;; *) return 1 ;; esac }
		. "${TEST_ROOT}/startup"
		printf 'selected=%s\n' "${BRANCH}"
	) >"${TEST_ROOT}/${case_name}.out" 2>&1
	status=$?
	[ "${status}" -eq "${expected_status}" ] || fail "${case_name}: expected ${expected_status}, got ${status}"
	[ -e "${TEST_ROOT}/${case_name}.recovered" ] || fail "${case_name}: prior recovery was bypassed"
	if [ "${saved}" = __read-error__ ]; then
		if [ "${expected_status}" -eq 0 ]; then
			[ ! -e "${TEST_ROOT}/${case_name}.saved-read-failed" ] || fail "${case_name}: explicit source read the saved ref"
		else
			[ -e "${TEST_ROOT}/${case_name}.saved-read-failed" ] || fail "${case_name}: did not exercise the saved-source read failure"
			grep -Fq 'Unable to read installer source from existing configuration' "${TEST_ROOT}/${case_name}.out" || fail "${case_name}: missing source-read diagnostic"
		fi
	fi
	if [ "${case_name}" = fresh-dryrun ]; then
		grep -Fxq preview "${TEST_ROOT}/${case_name}.out" || fail 'fresh dry-run did not remain a preview'
		[ ! -e "${TEST_ROOT}/${case_name}.writes" ] || fail 'fresh dry-run wrote preferences'
	elif [ "${expected_status}" -eq 0 ]; then
		grep -Fxq "selected=${expected_source}" "${TEST_ROOT}/${case_name}.out" || fail "${case_name}: wrong source"
	else
		[ ! -e "${TEST_ROOT}/${case_name}.writes" ] || fail "${case_name}: wrote preferences before source rejection"
	fi
}
run_case noarg-saved v2.6.7 0 v2.6.7
run_case default '' 0 master
run_case absent-config __absent__ 0 master
run_case absent-source-key __missing-key__ 0 master
run_case unreadable-source __read-error__ 1 ''
run_case unreadable-source-cli __read-error__ 1 '' update --yes
run_case explicit-cli-read-error __read-error__ 0 candidate update --installer-branch candidate --yes
run_case explicit-positional-read-error __read-error__ 0 candidate candidate update
run_case empty-positional v2.6.7 0 v2.6.7 '' update
run_case fresh-dryrun v2.6.7 0 '' install --dry-run
run_case explicit-cli v2.6.7 0 feature/test update --installer-branch feature/test --yes
run_case explicit-positional v2.6.7 0 candidate candidate update
run_case single-arg-saved v2.6.7 0 v2.6.7 install
run_case unsafe-saved ../wrong 1 ''
run_case unsafe-explicit v2.6.7 1 '' update --installer-branch ../wrong --yes
run_case unsafe-positional v2.6.7 1 '' ../wrong update
run_case duplicate-ref v2.6.7 1 '' update --installer-branch first --installer-branch second --yes
run_case missing-ref v2.6.7 1 '' update --installer-branch
run_case fresh-flagged v2.6.7 1 '' install --yes
run_case fresh-dns-consent v2.6.7 1 '' install --yes --allow-dns-nvram --installer-branch candidate
printf '%s\n' 'PASS: installer source resolves explicit, saved, default and rejects unsafe or ambiguous refs before writes'
