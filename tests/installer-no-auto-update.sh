#!/bin/sh
# Verify per-invocation update opt-out protects the installer/helper bundle.
set -u
INSTALLER_PATH="${1:-installer}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/installer-no-auto-update.XXXXXX")" || exit 1
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}
cleanup() { rm -rf "${TEST_ROOT}"; }
trap cleanup 0
trap 'exit 1' HUP INT TERM
sed -n '/^nvram_transaction_recovery_dependencies_available || exit 1$/,/^write_conf INSTALLER_BRANCH /p' "${INSTALLER_PATH}" >"${TEST_ROOT}/startup"
sed -n '/^branch_is_safe() {$/,/^}/p; /^sanitize_branch() {$/,/^}/p; /^cli_installer_branch_from_args() {$/,/^}/p; /^resolve_installer_branch() {$/,/^}/p; /^cli_fresh_install_supported() {$/,/^}/p; /^installer_update_policy_from_args() {$/,/^}/p; /^installer_bundle_update_allowed() {$/,/^}/p; /^installer_requested_bundle_update_allowed() {$/,/^}/p' "${INSTALLER_PATH}" >"${TEST_ROOT}/helpers"
mkdir "${TEST_ROOT}/target" || exit 1
: >"${TEST_ROOT}/target/AdGuardHome"
run_case() {
	case_name="$1"
	expected_status="$2"
	expected_text="$3"
	shift 3
	(
		set +u
		. "${TEST_ROOT}/helpers"
		PTXT() { printf '%s\n' "$*"; }
		ERROR=ERROR WARNING=WARNING INFO=INFO AI_NO_AUTO_UPDATE=0
		TARG_DIR="${TEST_ROOT}/target" AGH_FILE="${TEST_ROOT}/target/AdGuardHome"
		CONF_FILE="${TEST_ROOT}/${case_name}.config"
		: >"${CONF_FILE}"
		BLOCKLIST_ANALYZER_SHA256=present
		conf_value() { case "$1" in INSTALLER_BRANCH) printf '%s\n' v2.6.7 ;; ADGUARD_INSTALL_MODE) printf '%s\n' wan ;; esac }
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
		amtm_update_check() {
			if [ "${1:-}:${2:-}" = amtmupdate:check ]; then
				printf '%s\n' amtm-diagnostic
				exit 0
			fi
			return 0
		}
		installer_dependencies_available() { return 0; }
		single_arg_menu_action() { case "$1" in install | update) return 0 ;; *) return 1 ;; esac }
		status() { printf 'diagnostic-policy=%s\n' "${AI_NO_AUTO_UPDATE}"; }
		. "${TEST_ROOT}/startup"
		printf 'selected=%s policy=%s\n' "${BRANCH}" "${AI_NO_AUTO_UPDATE}"
	) >"${TEST_ROOT}/${case_name}.out" 2>&1
	status=$?
	[ "${status}" -eq "${expected_status}" ] || fail "${case_name}: expected ${expected_status}, got ${status}"
	grep -Fq "${expected_text}" "${TEST_ROOT}/${case_name}.out" || fail "${case_name}: missing ${expected_text}"
	[ -e "${TEST_ROOT}/${case_name}.recovered" ] || fail "${case_name}: prior recovery was bypassed"
	if [ "${expected_status}" -ne 0 ]; then
		[ ! -e "${TEST_ROOT}/${case_name}.writes" ] || fail "${case_name}: wrote preferences before bundle refusal"
	fi
}
run_case cli-update 1 'compatibility' update --yes --no-auto-update
run_case cli-install 1 'compatibility' install --yes --no-auto-update
run_case cli-restore 1 'compatibility' restore --file /backup.tar.gz --yes --no-auto-update
run_case opted-dryrun 1 'compatibility' update --no-auto-update --yes --dry-run
run_case prefix-menu 0 'selected=v2.6.7 policy=1' --no-auto-update
run_case prefix-source-menu 0 'selected=candidate policy=1' --no-auto-update candidate
run_case prefix-update 1 'compatibility' --no-auto-update candidate update
run_case prefix-amtm 1 'compatibility' --no-auto-update amtmupdate
run_case prefix-amtm-check 0 amtm-diagnostic --no-auto-update amtmupdate check
run_case prefix-switch 1 'compatibility' --no-auto-update candidate switchbranch
run_case prefix-single-switch 1 'compatibility' --no-auto-update switchbranch
run_case prefix-status 0 'diagnostic-policy=1' --no-auto-update status
rm -f "${TEST_ROOT}/target/AdGuardHome"
run_case partial-uninstall 0 'selected=v2.6.7 policy=1' --no-auto-update uninstall
run_case partial-positional-uninstall 0 'selected=candidate policy=1' --no-auto-update candidate uninstall
run_case fresh-menu-refused 1 'compatibility' --no-auto-update
: >"${TEST_ROOT}/target/AdGuardHome"

sed -n '/^nvram_transaction_read_only_diagnostic_requested() {$/,/^}/p' "${INSTALLER_PATH}" >"${TEST_ROOT}/diagnostic-function"
(
	. "${TEST_ROOT}/diagnostic-function"
	nvram_transaction_read_only_diagnostic_requested --no-auto-update candidate status || exit 1
	nvram_transaction_read_only_diagnostic_requested --no-auto-update candidate doctor || exit 1
	if nvram_transaction_read_only_diagnostic_requested --no-auto-update candidate doctor --fix; then exit 1; fi
) || fail 'global prefix changed completed-recovery read-only diagnostic eligibility'

# Defensive guards must precede dependency work and helper downloads at real seams.
sed -n '/^menu() {$/,/^}/p; /^check_version() {$/,/^}/p; /^inst_AdGuardHome() {$/,/^}/p; /^backup_restore() {$/,/^}/p' "${INSTALLER_PATH}" >"${TEST_ROOT}/operations"
for operation in update switchbranch restore orchestration version; do
	(
		. "${TEST_ROOT}/helpers"
		. "${TEST_ROOT}/operations"
		AI_NO_AUTO_UPDATE=1 INFO=INFO ERROR=ERROR AI_VERSION=test
		ADGUARD_ARCH=linux_armv7
		PTXT() { printf '%s\n' "$*"; }
		ptxt_phase() { :; }
		ptxt_step() { :; }
		ptxt_ok() { :; }
		end_op_message() { return 1; }
		ensure_jq_tool() {
			: >"${TEST_ROOT}/unexpected"
			return 1
		}
		ensure_sha256sum_tool() {
			: >"${TEST_ROOT}/unexpected"
			return 1
		}
		choose_branch() {
			: >"${TEST_ROOT}/unexpected"
			return 1
		}
		read_yesno() {
			: >"${TEST_ROOT}/unexpected"
			return 1
		}
		http_get_file() {
			: >"${TEST_ROOT}/unexpected"
			return 1
		}
		case "${operation}" in
			orchestration)
				inst_AdGuardHome update
				[ "$?" -eq 1 ]
				;;
			version) check_version ;;
			*)
				menu "${operation}"
				[ "$?" -eq 1 ]
				;;
		esac
	) >"${TEST_ROOT}/${operation}.out" 2>&1 || fail "${operation}: bundle guard failed"
	[ ! -e "${TEST_ROOT}/unexpected" ] || fail "${operation}: dependent work ran before bundle refusal"
done
# Menu relaunch must retain this policy-aware installer rather than an old installed script.
sed -n '/^end_op_message() {$/,/^}/p' "${INSTALLER_PATH}" >"${TEST_ROOT}/relaunch-function"
cat >"${TEST_ROOT}/target/installer" <<'EOF_OLD'
#!/bin/sh
printf '%s\n' old-installer
EOF_OLD
cat >"${TEST_ROOT}/current-installer" <<'EOF_CURRENT'
#!/bin/sh
[ "${1:-}" = --no-auto-update ] && [ "${2:-}" = candidate ] || exit 1
[ "${AI_NO_AUTO_UPDATE:-}" = 1 ] || exit 1
printf '%s\n' current-policy-preserved
EOF_CURRENT
(
	. "${TEST_ROOT}/relaunch-function"
	AI_NO_AUTO_UPDATE=1
	export AI_NO_AUTO_UPDATE
	SCRIPT_LOC="${TEST_ROOT}/current-installer"
	TARG_DIR="${TEST_ROOT}/target"
	ROLLBACK_RESULT_FILE="${TEST_ROOT}/no-rollback"
	BRANCH=candidate INFO=INFO ERROR=ERROR
	PTXT() { :; }
	nvram_transaction_lock_reaper_release_active() { return 0; }
	nvram_transaction_lock_release() { return 0; }
	sleep() { :; }
	clear_screen() { :; }
	end_op_message 0 backup
) >"${TEST_ROOT}/relaunch.out" 2>&1 || fail 'policy-aware menu relaunch failed'
grep -Fxq current-policy-preserved "${TEST_ROOT}/relaunch.out" || fail 'menu relaunch selected an older installer without opt-out support'

printf '%s\n' 'PASS: update opt-out preserves source, recovery and coherent bundle refusal across CLI and menus'
