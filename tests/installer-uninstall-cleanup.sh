#!/bin/sh
# Verify uninstall cleanup and compatibility with older installed managers.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/agh-uninstall-cleanup.XXXXXX")" || exit 1

# cleanup removes only the private regression fixture directory.
cleanup() {
	command rm -rf "${TMP_ROOT}"
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

# fail reports an uninstall regression failure.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"

grep -q '^readonly ROLLBACK_RESULT_FILE="${BASE_DIR}/\.AdGuardHome\.rollback_result"$' "${SCRIPT_PATH}" ||
	fail 'rollback result marker is not stored under BASE_DIR'

UNINSTALL_FUNCTION="$(sed -n '/^uninst_all() {$/,/^}/p' "${SCRIPT_PATH}")"
[ -n "${UNINSTALL_FUNCTION}" ] || fail 'could not extract uninst_all function'

printf '%s\n' "${UNINSTALL_FUNCTION}" | grep -q 'rm -rf .*"${ROLLBACK_RESULT_FILE}"' ||
	fail 'uninstall cleanup does not remove rollback result marker'
printf '%s\n' "${UNINSTALL_FUNCTION}" | grep -Fq 'yaml_nvars_file_action delete "#Asuswrt-Merlin AdGuardHome Installer" /jffs/scripts/dnsmasq.postconf' ||
	fail 'uninstall cleanup does not use the guarded nvars file action'

# Model the helper's home destination without changing the validation process HOME.
printf '%s\n' "${UNINSTALL_FUNCTION}" | sed 's/[$]{HOME}/${UNINSTALL_TEST_HOME}/g' >"${TMP_ROOT}/uninstall-function" || fail 'could not save uninstall helper'

# run_case executes the real uninstall helper with private state and modeled firmware calls.
run_case() (
	local case_name state_kind helper_kind expected_status case_dir state_path case_status
	case_name="$1"
	state_kind="$2"
	helper_kind="$3"
	expected_status="$4"
	case_dir="${TMP_ROOT}/${case_name}"
	TARG_DIR="${case_dir}/target"
	BASE_DIR="${case_dir}/base"
	UNINSTALL_TEST_HOME="${case_dir}/home"
	ADDON_DIR="${case_dir}/addon"
	ROLLBACK_RESULT_FILE="${BASE_DIR}/.AdGuardHome.rollback_result"
	EVENTS_FILE="${case_dir}/events"
	state_path="${TARG_DIR}/proc-sys-state"
	INFO=INFO ERROR=ERROR CONFIRM_STATUS=0
	mkdir -p "${TARG_DIR}" "${BASE_DIR}" "${UNINSTALL_TEST_HOME}" "${ADDON_DIR}" "${case_dir}/outside-state" || fail "${case_name}: directory setup failed"
	printf '%s\n' installer >"${TARG_DIR}/installer"
	printf '%s\n' retained >"${ROLLBACK_RESULT_FILE}"
	printf '%s\n' unchanged >"${case_dir}/outside-state/sentinel"
	case "${state_kind}" in
		directory)
			mkdir -m 700 "${state_path}" || fail "${case_name}: journal setup failed"
			printf '%s\n' '524288 4194304 boot-one' >"${state_path}/rmem_max"
			;;
		file) printf '%s\n' malformed >"${state_path}" ;;
		symlink) ln -s "${case_dir}/outside-state" "${state_path}" || fail "${case_name}: symlink setup failed" ;;
		broken-link) ln -s "${case_dir}/missing" "${state_path}" || fail "${case_name}: broken-link setup failed" ;;
		absent) : ;;
		*) fail "${case_name}: unknown state fixture" ;;
	esac
	if [ "${helper_kind}" != missing ]; then
		cat >"${ADDON_DIR}/AdGuardHome.sh" <<'EOF'
#!/bin/sh
printf '%s\n' helper-called >>"${EVENTS_FILE}"
case "${HELPER_KIND}" in
	legacy)
		printf '%s\n' 'Usage: /opt/etc/init.d/S99AdGuardHome (start|stop|restart|check|kill|reload)' >&2
		exit 1
		;;
	success) exit 0 ;;
	failure) exit 1 ;;
	*) exit 2 ;;
esac
EOF
		chmod 755 "${ADDON_DIR}/AdGuardHome.sh" || fail "${case_name}: helper setup failed"
	fi
	HELPER_KIND="${helper_kind}"
	export EVENTS_FILE HELPER_KIND
	# PTXT retains messages in the fixture event log.
	PTXT() { printf '%s\n' "$*" >>"${EVENTS_FILE}"; }
	# conf_value models an installation without an installer-managed LAN domain.
	conf_value() { printf '%s\n' no; }
	# agh_is_running models an initially running service.
	agh_is_running() { return 0; }
	# agh_stop records a successful service stop.
	agh_stop() { printf '%s\n' stop >>"${EVENTS_FILE}"; }
	# agh_start records recovery of the retained installation after an abort.
	agh_start() { printf '%s\n' start >>"${EVENTS_FILE}"; }
	# all_event_scripts_transaction_begin records the first event-hook mutation boundary.
	all_event_scripts_transaction_begin() { printf '%s\n' hooks >>"${EVENTS_FILE}"; }
	# all_event_scripts_transaction_commit models successful hook finalization.
	all_event_scripts_transaction_commit() { :; }
	# remove_dnsmasq_event_scripts models successful managed dnsmasq hook removal.
	remove_dnsmasq_event_scripts() { :; }
	# remove_init_event_scripts models successful managed init hook removal.
	remove_init_event_scripts() { :; }
	# remove_services_event_scripts models successful managed service hook removal.
	remove_services_event_scripts() { :; }
	# remove_firewall_event_scripts models successful managed firewall hook removal.
	remove_firewall_event_scripts() { :; }
	# cleanup_legacy_firewall models successful firmware firewall cleanup.
	cleanup_legacy_firewall() { :; }
	# yaml_nvars_file_action models the existing guarded firmware file edit.
	yaml_nvars_file_action() { :; }
	# nvram_transaction_finalize_setup_pair models successful NVRAM finalization.
	nvram_transaction_finalize_setup_pair() { :; }
	# service records the firmware dnsmasq restart without executing it.
	service() { printf '%s\n' service >>"${EVENTS_FILE}"; }
	# end_op_message records successful completion.
	end_op_message() { printf '%s\n' complete >>"${EVENTS_FILE}"; }
	# rm redirects uninstall's absolute router cleanup to owned fixture paths only.
	rm() {
		printf '%s\n' remove >>"${EVENTS_FILE}"
		command rm -rf "${TARG_DIR}" "${ROLLBACK_RESULT_FILE}" "${ADDON_DIR}"
	}
	# shellcheck disable=SC1090
	. "${TMP_ROOT}/uninstall-function"
	if uninst_all >"${case_dir}/stdout" 2>"${case_dir}/stderr"; then
		case_status=0
	else
		case_status=$?
	fi
	[ "${case_status}" -eq "${expected_status}" ] || fail "${case_name}: expected status ${expected_status}, got ${case_status}"
	[ "$(sed -n '1p' "${EVENTS_FILE}")" = stop ] || fail "${case_name}: service was not stopped first"
	[ "$(cat "${case_dir}/outside-state/sentinel")" = unchanged ] || fail "${case_name}: outside state changed"
	if [ "${expected_status}" -eq 0 ]; then
		[ -f "${UNINSTALL_TEST_HOME}/installer" ] || fail "${case_name}: installer was not preserved in the modeled home"
		[ ! -e "${TARG_DIR}" ] || fail "${case_name}: successful uninstall retained target"
		[ ! -e "${ROLLBACK_RESULT_FILE}" ] || fail "${case_name}: successful uninstall retained rollback marker"
		grep -qx complete "${EVENTS_FILE}" || fail "${case_name}: uninstall did not complete"
		! grep -qx start "${EVENTS_FILE}" || fail "${case_name}: successful uninstall restarted AdGuardHome"
	else
		[ -d "${TARG_DIR}" ] && [ -f "${ROLLBACK_RESULT_FILE}" ] || fail "${case_name}: aborted uninstall removed retained files"
		grep -qx 'ERROR Unable to restore installer-managed kernel settings.' "${EVENTS_FILE}" || fail "${case_name}: missing restoration diagnostic"
		grep -qx start "${EVENTS_FILE}" || fail "${case_name}: abort did not restart AdGuardHome"
		! grep -qx hooks "${EVENTS_FILE}" || fail "${case_name}: abort changed event hooks"
		! grep -qx remove "${EVENTS_FILE}" || fail "${case_name}: abort removed installation files"
		if [ "${state_kind}" = directory ]; then
			[ "$(cat "${state_path}/rmem_max")" = '524288 4194304 boot-one' ] || fail "${case_name}: abort changed ownership journal"
		fi
	fi
	case "${state_kind}:${helper_kind}" in
		directory:success | directory:failure | directory:legacy)
			grep -qx helper-called "${EVENTS_FILE}" || fail "${case_name}: restoration helper was not called"
			;;
		*) ! grep -qx helper-called "${EVENTS_FILE}" || fail "${case_name}: unnecessary or unsafe restoration helper call" ;;
	esac
	printf '%s\n' "PASS: ${case_name} uninstall restoration boundary"
)

run_case legacy-without-journal absent legacy 0 || exit 1
run_case missing-helper-without-journal absent missing 0 || exit 1
run_case failed-helper-without-journal absent failure 0 || exit 1
run_case journal-restore-success directory success 0 || exit 1
run_case journal-restore-failure directory failure 1 || exit 1
run_case journal-legacy-helper directory legacy 1 || exit 1
run_case journal-missing-helper directory missing 1 || exit 1
run_case malformed-journal file success 1 || exit 1
run_case symlinked-journal symlink success 1 || exit 1
run_case broken-journal-link broken-link success 1 || exit 1

printf '%s\n' 'PASS: uninstall cleanup removes rollback state and tolerates an absent dnsmasq.postconf file'
