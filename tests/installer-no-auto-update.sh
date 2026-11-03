#!/bin/sh
# Verify per-invocation update opt-out protects the installer/helper bundle.
set -u
INSTALLER_PATH="${1:-installer}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/installer-no-auto-update.XXXXXX")" || exit 1
# fail reports a failed fixture assertion and exits the test.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}
# cleanup removes only the private fixture directory when the test exits.
cleanup() { rm -rf "${TEST_ROOT}"; }
trap cleanup 0
trap 'exit 1' HUP INT TERM
sed -n '/^nvram_transaction_recovery_dependencies_available || exit 1$/,/^write_conf INSTALLER_BRANCH /p' "${INSTALLER_PATH}" >"${TEST_ROOT}/startup"
sed -n '/^branch_is_safe() {$/,/^}/p; /^sanitize_branch() {$/,/^}/p; /^cli_installer_branch_from_args() {$/,/^}/p; /^resolve_installer_branch() {$/,/^}/p; /^cli_fresh_install_supported() {$/,/^}/p; /^installer_update_policy_from_args() {$/,/^}/p; /^installer_bundle_update_allowed() {$/,/^}/p; /^installer_requested_bundle_update_allowed() {$/,/^}/p; /^nvram_transaction_read_only_diagnostic_requested() {$/,/^}/p' "${INSTALLER_PATH}" >"${TEST_ROOT}/helpers"
mkdir "${TEST_ROOT}/target" || exit 1
: >"${TEST_ROOT}/target/AdGuardHome"
# run_case runs the real startup policy gates with supplied arguments and checks early refusal or retained policy.
run_case() {
	case_name="$1"
	expected_status="$2"
	expected_text="$3"
	shift 3
	(
		set +u
		. "${TEST_ROOT}/helpers"
		# PTXT captures installer diagnostics without terminal formatting.
		PTXT() { printf '%s\n' "$*"; }
		ERROR=ERROR WARNING=WARNING INFO=INFO AI_NO_AUTO_UPDATE=0
		TARG_DIR="${TEST_ROOT}/target" AGH_FILE="${TEST_ROOT}/target/AdGuardHome"
		CONF_FILE="${TEST_ROOT}/${case_name}.config"
		: >"${CONF_FILE}"
		BLOCKLIST_ANALYZER_SHA256=present
		# conf_value supplies saved source and install-mode values without reading router configuration.
		conf_value() {
			case "$1" in
				INSTALLER_BRANCH) printf '%s\n' v2.6.7 ;;
				ADGUARD_INSTALL_MODE) printf '%s\n' wan ;;
			esac
		}
		# conf_has_key models a complete configuration so unrelated default migration stays outside this fixture.
		conf_has_key() { return 0; }
		# write_conf records attempted preference writes for the early-refusal assertions.
		write_conf() { printf '%s %s\n' "$1" "$2" >>"${TEST_ROOT}/${case_name}.writes"; }
		# nvram_transaction_recovery_dependencies_available allows the recovery entry point without requiring router package tools.
		nvram_transaction_recovery_dependencies_available() { return 0; }
		# on_installer_exit keeps real exit cleanup outside the isolated startup fixture.
		on_installer_exit() { :; }
		# adguard_committed_binary_cleanup_retry models the absence of a pending committed-binary cleanup.
		adguard_committed_binary_cleanup_retry() { return 0; }
		# all_event_scripts_recover_startup models the absence of a retained event-hook recovery journal.
		all_event_scripts_recover_startup() { return 0; }
		# nvram_transaction_recover_startup marks recovery first and models diagnostic-safe cleanup failures.
		nvram_transaction_recover_startup() {
			: >"${TEST_ROOT}/${case_name}.recovered"
			case "${case_name}" in
				recovery-*)
					NVRAM_TRANSACTION_RECOVERY_DIAGNOSTIC_SAFE=1
					return 1
					;;
			esac
			return 0
		}
		# cli_pre_remote_dry_run models an early preview without invoking downloads or setup.
		cli_pre_remote_dry_run() {
			case "$*" in
				*--dry-run*)
					printf '%s\n' preview
					return 0
					;;
				*) return 1 ;;
			esac
		}
		# cli_pre_runtime_defaults_preview leaves unrelated runtime-default preview handling outside these cases.
		cli_pre_runtime_defaults_preview() { return 1; }
		# adguard_install_mode_detect supplies a confirmed WAN mode after the startup policy checks.
		adguard_install_mode_detect() {
			ADGUARD_INSTALL_MODE=wan
			return 0
		}
		# adguard_install_mode_confirmed models an already-confirmed install mode without firmware probing.
		adguard_install_mode_confirmed() { return 0; }
		# amtm_update_check distinguishes the AMTM diagnostic alias from a bundle-changing AMTM update.
		amtm_update_check() {
			if [ "${1:-}:${2:-}" = amtmupdate:check ]; then
				printf '%s\n' amtm-diagnostic
				exit 0
			fi
			return 0
		}
		# installer_dependencies_available keeps router command discovery outside the startup policy fixture.
		installer_dependencies_available() { return 0; }
		# single_arg_menu_action models compatibility action dispatch while exercising the real update-policy guard.
		single_arg_menu_action() {
			case "$1" in install | update) return 0 ;; *) return 1 ;; esac
		}
		# status reports the invocation policy without querying router services.
		status() { printf 'diagnostic-policy=%s\n' "${AI_NO_AUTO_UPDATE}"; }
		# doctor records an early read-only dispatch without running router diagnostics.
		doctor() { printf 'diagnostic-policy=%s\n' "${AI_NO_AUTO_UPDATE}"; }
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
	case "${case_name}" in
		diagnostic-* | recovery-*) [ ! -e "${TEST_ROOT}/${case_name}.writes" ] || fail "${case_name}: diagnostic request wrote preferences" ;;
	esac
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
run_case diagnostic-doctor 0 'diagnostic-policy=1' doctor --no-auto-update
run_case diagnostic-positional-doctor 0 'diagnostic-policy=1' candidate doctor --no-auto-update
run_case recovery-doctor 0 'diagnostic-policy=1' doctor --no-auto-update
run_case recovery-positional-doctor 0 'diagnostic-policy=1' candidate doctor --no-auto-update
run_case recovery-doctor-fix 1 'Unable to release' doctor --no-auto-update --fix
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
	nvram_transaction_read_only_diagnostic_requested doctor --no-auto-update || exit 1
	nvram_transaction_read_only_diagnostic_requested candidate doctor --no-auto-update || exit 1
	nvram_transaction_read_only_diagnostic_requested --no-auto-update doctor --no-auto-update || exit 1
	if nvram_transaction_read_only_diagnostic_requested --no-auto-update candidate doctor --fix; then exit 1; fi
	if nvram_transaction_read_only_diagnostic_requested doctor --no-auto-update --fix; then exit 1; fi
) || fail 'global prefix changed completed-recovery read-only diagnostic eligibility'

# Defensive guards must precede dependency work and helper downloads at real seams.
sed -n '/^menu() {$/,/^}/p; /^check_version() {$/,/^}/p; /^inst_AdGuardHome() {$/,/^}/p; /^backup_restore() {$/,/^}/p' "${INSTALLER_PATH}" >"${TEST_ROOT}/operations"
for operation in update switchbranch restore orchestration version; do
	(
		. "${TEST_ROOT}/helpers"
		. "${TEST_ROOT}/operations"
		AI_NO_AUTO_UPDATE=1 INFO=INFO ERROR=ERROR AI_VERSION=test
		ADGUARD_ARCH=linux_armv7
		# PTXT captures installer diagnostics without terminal formatting.
		PTXT() { printf '%s\n' "$*"; }
		# ptxt_phase suppresses progress formatting that is unrelated to policy refusal.
		ptxt_phase() { :; }
		# ptxt_step suppresses progress formatting that is unrelated to policy refusal.
		ptxt_step() { :; }
		# ptxt_ok suppresses success formatting that is unrelated to policy refusal.
		ptxt_ok() { :; }
		# end_op_message records a requested menu return without relaunching the fixture.
		end_op_message() {
			: >"${TEST_ROOT}/${operation}.menu-return"
			return 1
		}
		# ensure_jq_tool records any parser bootstrap attempted before bundle refusal.
		ensure_jq_tool() {
			: >"${TEST_ROOT}/unexpected"
			return 1
		}
		# ensure_sha256sum_tool records any checksum-tool bootstrap attempted before bundle refusal.
		ensure_sha256sum_tool() {
			: >"${TEST_ROOT}/unexpected"
			return 1
		}
		# choose_branch records any AdGuardHome channel selection attempted before bundle refusal.
		choose_branch() {
			: >"${TEST_ROOT}/unexpected"
			return 1
		}
		# read_yesno records any confirmation prompt attempted before bundle refusal.
		read_yesno() {
			: >"${TEST_ROOT}/unexpected"
			return 1
		}
		# http_get_file records any metadata or component download attempted before bundle refusal.
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
	case "${operation}" in
		update | switchbranch | restore) [ -e "${TEST_ROOT}/${operation}.menu-return" ] || fail "${operation}: refused menu choice did not return to the menu" ;;
	esac
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
	# PTXT suppresses menu banners while the relaunch target and policy are checked.
	PTXT() { :; }
	# nvram_transaction_lock_reaper_release_active models successful reaper cleanup before the menu relaunch.
	nvram_transaction_lock_reaper_release_active() { return 0; }
	# nvram_transaction_lock_release models successful lock release without touching router lock state.
	nvram_transaction_lock_release() { return 0; }
	# sleep skips the interactive delay during the menu relaunch proof.
	sleep() { :; }
	# clear_screen avoids terminal control operations during the menu relaunch proof.
	clear_screen() { :; }
	end_op_message 0 backup
) >"${TEST_ROOT}/relaunch.out" 2>&1 || fail 'policy-aware menu relaunch failed'
grep -Fxq current-policy-preserved "${TEST_ROOT}/relaunch.out" || fail 'menu relaunch selected an older installer without opt-out support'

# Successful opt-out uninstall must not relaunch a moved or empty installation.
(
	. "${TEST_ROOT}/relaunch-function"
	AI_NO_AUTO_UPDATE=1 CLI_MODE=0 ADGUARD_DEFER_END_OP=0
	SCRIPT_LOC="${TEST_ROOT}/missing-uninstalled-installer"
	TARG_DIR="${TEST_ROOT}/removed-target"
	ROLLBACK_RESULT_FILE="${TEST_ROOT}/no-rollback"
	INFO=INFO ERROR=ERROR
	# PTXT discards terminal output while checking successful uninstall completion.
	PTXT() { :; }
	# nvram_transaction_lock_reaper_release_active models a completed uninstall cleanup.
	nvram_transaction_lock_reaper_release_active() { return 0; }
	end_op_message 0 uninstall
) >"${TEST_ROOT}/uninstall-end.out" 2>&1 || fail 'completed opt-out uninstall was reported as a relaunch failure'

printf '%s\n' 'PASS: update opt-out preserves source, recovery and coherent bundle refusal across CLI and menus'
