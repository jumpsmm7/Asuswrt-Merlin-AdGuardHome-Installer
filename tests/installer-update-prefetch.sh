#!/bin/sh
# Exercise real update/restore orchestration when router DNS depends on AdGuard Home.
set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-update-prefetch.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions"
# fail reports a failed ordering assertion and stops the fixture.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}
# cleanup removes this regression's private archives and scenario files.
cleanup() { rm -rf "${TMP_ROOT}"; }
trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
mkdir -p "${TMP_ROOT}/remote/AdGuardHome/data" || exit 1
awk '
	/^install_wan_event_scripts\(\) \{/,/^set_timezone\(\) \{/ { if ($0 !~ /^set_timezone\(/) print; next }
	/^download_file\(\)/,/^}/
	/^installer_version_value\(\)/,/^}/
	/^install_adguard_archive\(\)/,/^}/
	/^backup_restore\(\)/,/^}/
	/^adguard_install_abort_on_signal\(\)/,/^}/
	/^adguard_install_abort_trap_enable\(\)/,/^}/
	/^adguard_install_signal_traps_disable\(\)/,/^}/
	/^ensure_sha256sum_tool\(\)/,/^}/
	/^ensure_opkg_package\(\)/,/^}/
	/^adguard_archive_is_safe\(\)/,/^}/
	/^md5_is_valid\(\)/,/^}/
	/^sha256_is_valid\(\)/,/^}/
	/^md5_manifest_digest\(\)/,/^}/
	/^sha256_manifest_digest\(\)/,/^}/
' "${SCRIPT_PATH}" >"${FUNCTIONS_FILE}"
sed -n '/^set_timezone() {$/,/^}/p; /^filter_timezone_members() {$/,/^}/p; /^format_timezone_menu() {$/,/^}/p' "${SCRIPT_PATH}" >>"${FUNCTIONS_FILE}"
cat >"${TMP_ROOT}/remote/AdGuardHome/AdGuardHome" <<'EOF_BINARY'
#!/bin/sh
printf '%s\n' 'AdGuard Home version new'
EOF_BINARY
chmod 755 "${TMP_ROOT}/remote/AdGuardHome/AdGuardHome"
printf '%s\n' 'schema_version: 27' >"${TMP_ROOT}/remote/AdGuardHome/AdGuardHome.yaml"
tar -czf "${TMP_ROOT}/remote/AdGuardHome_test.tar.gz" -C "${TMP_ROOT}/remote" AdGuardHome
printf '%s\n' '#!/bin/sh' 'AI_VERSION="v2.6.7"' >"${TMP_ROOT}/remote/installer"
for component in AdGuardHome.sh S99AdGuardHome rc.func.AdGuardHome; do
	printf '%s\n' '#!/bin/sh' "# new ${component}" >"${TMP_ROOT}/remote/${component}"
done
TZ_ARCH="$(uname -m)"
case "${TZ_ARCH}" in aarch64 | arm64) TZ_ARCH=aarch64 ;; armv7l) TZ_ARCH=arm ;; esac
TZ_DATA="tzdata-2026e-1-${TZ_ARCH}.pkg.tar.bz2"
mkdir -p "${TMP_ROOT}/remote/timezone/usr/share/zoneinfo/posix" /opt/bin || fail 'could not create timezone fixture'
printf '%s\n' 'fixture timezone' >"${TMP_ROOT}/remote/timezone/usr/share/zoneinfo/posix/UTC"
tar -cjf "${TMP_ROOT}/remote/${TZ_DATA}" -C "${TMP_ROOT}/remote/timezone" usr || fail 'could not create timezone archive'
printf '%s\n' '#!/bin/sh' 'cat' >/opt/bin/column
chmod 755 /opt/bin/column || fail 'could not create modeled Entware column'

# run_case runs real orchestration against one modeled DNS/download/publication fault.
run_case() (
	case_name="$1"
	case_root="${TMP_ROOT}/${case_name}"
	BASE_DIR="${case_root}/base"
	TARG_DIR="${BASE_DIR}/AdGuardHome"
	ADDON_DIR="${case_root}/addon"
	AGH_FILE="${TARG_DIR}/AdGuardHome"
	YAML_FILE="${AGH_FILE}.yaml"
	YAML_ORI="${TARG_DIR}/.AdGuardHome.yaml.ori"
	SCRIPT_LOC="${case_root}/absent-installer"
	CALLS_FILE="${case_root}/calls"
	RURL='https://source.invalid/pinned-commit'
	URL_ARCH='https://archive.invalid'
	ADGUARD_ARCH='test'
	ADGUARD_INSTALL_MODE='wan'
	ADGUARD_INSTALL_REPLACE_ACTIVE=0
	ADGUARD_SERVICE_STAGE_DIR=''
	ADGUARD_SERVICE_STAGE_OWNED=0
	ADGUARD_SERVICE_PUBLISH_DIR=''
	ADGUARD_SERVICE_PUBLISH_OWNED=0
	INFO='Info:' ERROR='Error:' BOLD='' NORM=''
	RUNNING=1 SERVICE_INTERRUPTED=0 TARGET_MUTATED=0 SERVICE_REFRESH_ONLY=0
	mkdir -p "${TARG_DIR}" "${ADDON_DIR}" /opt/etc/init.d /opt/sbin
	sed s/new/old/ "${TMP_ROOT}/remote/AdGuardHome/AdGuardHome" >"${AGH_FILE}"
	chmod 755 "${AGH_FILE}"
	printf '%s\n' old >"${ADDON_DIR}/AdGuardHome.sh"
	printf '%s\n' old >/opt/etc/init.d/S99AdGuardHome
	printf '%s\n' old >/opt/etc/init.d/rc.func.AdGuardHome
	: >"${CALLS_FILE}"
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	case "${case_name}" in
		stopped | fresh) RUNNING=0 ;;
		refresh) SERVICE_REFRESH_ONLY=1 ;;
		restore*) cp "${TMP_ROOT}/remote/AdGuardHome_test.tar.gz" "${BASE_DIR}/backup_AdGuardHome.tar.gz" ;;
	esac
	[ "${case_name}" != fresh ] || rm -f "${AGH_FILE}"
	# PTXT models terminal messaging without changing the update decision under test.
	PTXT() {
		if [ "${1:-}" = -n ]; then
			shift
			printf '%s' "$*"
		else
			printf '%s\n' "$*" >>"${case_root}/messages"
			printf '%s\n' "$*"
		fi
	}
	# ptxt_phase suppresses phase headings while real orchestration executes.
	ptxt_phase() { :; }
	# ptxt_step suppresses progress steps unrelated to fetch and publication ordering.
	ptxt_step() { :; }
	# ptxt_ok suppresses success decoration while assertions inspect actual outcomes.
	ptxt_ok() { :; }
	# ptxt_warn suppresses warning decoration without changing helper return status.
	ptxt_warn() { :; }
	# ptxt_fail suppresses failure decoration so explicit assertions decide the scenario result.
	ptxt_fail() { :; }
	# sha256sum_available models a router that must retain the MD5 fallback.
	sha256sum_available() { [ "${case_name}" != restore-sha-missing ]; }
	# opkg_pkg_installed models the checksum package missing in that fallback case.
	opkg_pkg_installed() { [ "${case_name}:$1" != restore-sha-missing:coreutils-sha256sum ]; }
	# opkg_clean_env records real ensure_opkg_package attempts and rejects online work after mutation.
	opkg_clean_env() {
		printf '%s\n' "opkg:$2:running=${RUNNING}:mutated=${TARGET_MUTATED}" >>"${CALLS_FILE}"
		[ "${TARGET_MUTATED}" = 0 ] || return 1
		case "${case_name}:$2" in restore-timezone-opkg-fail:column | restore-sha-missing:coreutils-sha256sum) return 1 ;; esac
	}
	# ai_have_cmd keeps the actual timezone command check against the fixture PATH.
	ai_have_cmd() { which "$1" >/dev/null 2>&1; }
	# read_input_num chooses the fixture archive's single real timezone member.
	read_input_num() { CHOSEN=1; }
	# installer_update_reexec keeps re-execution outside this in-process update-ordering fixture.
	installer_update_reexec() { :; }
	# file_md5 computes real MD5 values for the fixture artifacts and sidecars.
	file_md5() { md5sum "$1" | cut -d ' ' -f 1; }
	# file_sha256 models unavailable digest calculation while preserving real SHA checks elsewhere.
	file_sha256() {
		[ "${case_name}" != restore-sha-missing ] || return 1
		sha256sum "$1" | cut -d ' ' -f 1
	}
	# http_url_with_cache_token keeps fixture URLs deterministic while preserving their pinned source.
	http_url_with_cache_token() { printf '%s\n' "$1"; }
	# http_get_file models remote transfers and refuses network work after DNS stop or target mutation.
	http_get_file() {
		url="$1"
		name="${url##*/}"
		printf '%s\n' "fetch:${name}:running=${RUNNING}:mutated=${TARGET_MUTATED}" >>"${CALLS_FILE}"
		[ "${TARGET_MUTATED}" = 0 ] || return 1
		if [ "${SERVICE_INTERRUPTED}" = 1 ] && [ "${RUNNING}" = 0 ]; then return 1; fi
		case "${name}:${url}" in
			AdGuardHome_test.tar.gz*:"${URL_ARCH}/"* | *:"${RURL}/"*) ;;
			*) fail "${case_name}: download escaped its pinned source: ${url}" ;;
		esac
		case "${case_name}:${name}" in
			sha-mismatch:S99AdGuardHome.sha256sum)
				printf '%064d\n' 0 >"$2"
				return 0
				;;
			sha-invalid:S99AdGuardHome.sha256sum)
				printf '%s\n' invalid >"$2"
				return 0
				;;
			md5-mismatch:S99AdGuardHome.sha256sum) return 1 ;;
			md5-mismatch:S99AdGuardHome.md5sum)
				printf '%032d\n' 0 >"$2"
				return 0
				;;
			prefetch-fail:S99AdGuardHome | restore-prefetch-fail:S99AdGuardHome) return 1 ;;
			restore-timezone-fetch-fail:tzdata-*.pkg.tar.bz2) return 1 ;;
			md5:*.sha256sum) return 1 ;;
		esac
		case "${name}" in
			*.sha256sum) file_sha256 "${TMP_ROOT}/remote/${name%.sha256sum}" >"$2" ;;
			*.md5sum) file_md5 "${TMP_ROOT}/remote/${name%.md5sum}" >"$2" ;;
			*) cp "${TMP_ROOT}/remote/${name}" "$2" ;;
		esac
	}
	# adguard_remote_archive selects the local archive fixture in place of live channel metadata.
	adguard_remote_archive() { printf '%s\n' AdGuardHome_test.tar.gz; }
	# adguard_remote_url supplies the pinned fixture archive URL without querying upstream.
	adguard_remote_url() { printf '%s\n' "${URL_ARCH}/AdGuardHome_test.tar.gz"; }
	# adguard_remote_md5 supplies fixture MD5 metadata without contacting the upstream channel.
	adguard_remote_md5() { file_md5 "${TMP_ROOT}/remote/AdGuardHome_test.tar.gz"; }
	# adguard_remote_sha256 supplies fixture SHA-256 metadata without contacting the upstream channel.
	adguard_remote_sha256() { file_sha256 "${TMP_ROOT}/remote/AdGuardHome_test.tar.gz"; }
	# create_dir creates only the scenario directory requested by real orchestration.
	create_dir() { mkdir -p "$1"; }
	# ensure_adguardhome_directory_permissions leaves permission-policy repair outside the prefetch-ordering scenario.
	ensure_adguardhome_directory_permissions() { :; }
	# agh_process_count models whether the scenario starts with an active AdGuardHome service.
	agh_process_count() { printf '%s\n' "${RUNNING}"; }
	# agh_prepare_binary_replace records the DNS stop boundary used to reject subsequent transfers.
	agh_prepare_binary_replace() {
		printf '%s\n' stop >>"${CALLS_FILE}"
		RUNNING=0
		SERVICE_INTERRUPTED=1
	}
	# adguard_restore_abort_trap_enable leaves restore trap installation outside the ordering fixture.
	adguard_restore_abort_trap_enable() { :; }
	# adguard_install_abort_trap_disable avoids changing the fixture shell's own cleanup traps.
	adguard_install_abort_trap_disable() { :; }
	# adguard_install_abort_trap_disable_preserve_defer keeps deferred trap policy outside the publication-ordering scenario.
	adguard_install_abort_trap_disable_preserve_defer() { :; }
	# adguard_restart_after_install_abort models recovery of the previously running service after an abort.
	adguard_restart_after_install_abort() { RUNNING=1; }
	# adguard_committed_binary_cleanup_finalize removes the scenario backup and disarms its modeled replacement state.
	adguard_committed_binary_cleanup_finalize() {
		rm -f "$1"
		ADGUARD_INSTALL_REPLACE_ACTIVE=0
	}
	# adguard_install_mode_confirmed models an already confirmed topology so the update can reach prefetch.
	adguard_install_mode_confirmed() { return 0; }
	# adguard_enforce_lan_ipset_disabled excludes LAN IPSET preference edits from this WAN-mode fixture.
	adguard_enforce_lan_ipset_disabled() { :; }
	# adguard_migrate_detected_install_mode excludes topology migration from the artifact-ordering scenario.
	adguard_migrate_detected_install_mode() { :; }
	# configure_runtime_defaults preserves scenario settings without running unrelated default migration.
	configure_runtime_defaults() { :; }
	# cleanup_legacy_firewall keeps firmware firewall mutation outside the prefetch fixture.
	cleanup_legacy_firewall() { :; }
	# all_event_scripts_transaction_begin models a successful hook snapshot boundary without touching router hooks.
	all_event_scripts_transaction_begin() { :; }
	# all_event_scripts_transaction_commit models successful hook commit after artifact publication.
	all_event_scripts_transaction_commit() { :; }
	# all_event_scripts_transaction_detach_after_mode_rollback keeps hook-journal detachment outside the modeled topology path.
	all_event_scripts_transaction_detach_after_mode_rollback() { :; }
	# yaml_nvars_file_action suppresses unrelated shared-hook content edits during publication tests.
	yaml_nvars_file_action() { :; }
	# install_wan_event_scripts models successful WAN hook setup without installing firmware callbacks.
	install_wan_event_scripts() { :; }
	# setup_AdGuardHome excludes interactive setup while retaining real download and publication orchestration.
	setup_AdGuardHome() { :; }
	# agh_complete_startup records successful modeled service recovery after publication.
	agh_complete_startup() {
		RUNNING=1
		printf '%s\n' started >>"${CALLS_FILE}"
	}
	# finalize_dns_environment keeps persistent DNS-setting finalization outside the stop-window assertion.
	finalize_dns_environment() { :; }
	# finalize_pending_mode_migration models a completed topology transaction without changing preferences.
	finalize_pending_mode_migration() { :; }
	# conf_value models absent optional preferences without sourcing private configuration.
	conf_value() { :; }
	# rollback_result_write suppresses persistence of rollback markers outside this private scenario.
	rollback_result_write() { :; }
	# rollback_result_notice suppresses rollback terminal notices while state assertions remain active.
	rollback_result_notice() { :; }
	# end_op_message cleans owned staging and preserves the real operation's failure status.
	end_op_message() {
		[ "${ADGUARD_SERVICE_STAGE_OWNED:-0}" != 1 ] || adguard_service_bundle_cleanup
		[ "${ADGUARD_SERVICE_PUBLISH_OWNED:-0}" != 1 ] || adguard_service_publish_cleanup
		return "$1"
	}
	# cp injects a publication-copy failure while retaining all other real copies.
	cp() {
		case "${case_name}:${2:-}" in publish-copy-fail:*/.AdGuardHome.service.*/file) return 1 ;; esac
		command cp "$@"
	}
	# chmod injects a publication-mode failure while retaining other real chmod operations.
	chmod() {
		case "${case_name}:${2:-}" in publish-chmod-fail:*/.AdGuardHome.service.*/file) return 1 ;; esac
		command chmod "$@"
	}
	# ln excludes global executable-link publication from the ordering fixture.
	ln() { :; }
	# clear_screen avoids terminal control output during fixture orchestration.
	clear_screen() { :; }
	# mv injects publication-rename failure and records restore target mutation.
	mv() {
		case "${case_name}:$*" in publish-rename-fail:*'/.AdGuardHome.service.'*'/file '*) return 1 ;; esac
		if [ "${1:-}" = "${TARG_DIR}" ]; then TARGET_MUTATED=1; fi
		command mv "$@"
	}
	status=0
	if [ "${case_name}" = signal-cleanup ] || [ "${case_name}" = cleanup-retained ]; then
		adguard_service_bundle_stage || fail "${case_name}: could not stage signal fixture"
		if [ "${case_name}" = cleanup-retained ]; then
			printf '%s\n' retained >"${ADGUARD_SERVICE_STAGE_DIR}/foreign"
			if adguard_service_bundle_cleanup 2>/dev/null; then fail 'cleanup accepted a nonempty staging directory'; fi
			[ -f "${ADGUARD_SERVICE_STAGE_DIR}/foreign" ] || fail 'cleanup removed an unowned staging entry'
			[ "${ADGUARD_SERVICE_STAGE_OWNED}" = 1 ] || fail 'failed cleanup discarded ownership state'
			grep -q "retained at ${ADGUARD_SERVICE_STAGE_DIR}" "${case_root}/messages" || fail 'failed cleanup did not report its retained path'
			rm -f "${ADGUARD_SERVICE_STAGE_DIR}/foreign"
			adguard_service_bundle_cleanup || fail 'staging cleanup could not be retried'
		else
			ADGUARD_SERVICE_PUBLISH_DIR="${ADDON_DIR}/.AdGuardHome.service.$$"
			mkdir "${ADGUARD_SERVICE_PUBLISH_DIR}"
			ADGUARD_SERVICE_PUBLISH_OWNED=1
			printf '%s\n' partial >"${ADGUARD_SERVICE_PUBLISH_DIR}/file"
			RUNNING=0
			ADGUARD_INSTALL_WAS_RUNNING=1
			adguard_install_abort_on_signal || status=$?
			[ "${status}" = 2 ] || fail 'signal abort did not report interruption'
			[ "${RUNNING}" = 1 ] || fail 'signal cleanup did not recover prior service state'
		fi
		[ ! -d "${BASE_DIR}/.AdGuardHome.services.$$" ] || fail 'signal/cleanup retained removable owned service staging'
		[ ! -d "${ADDON_DIR}/.AdGuardHome.service.$$" ] || fail 'signal cleanup leaked publication staging'
		printf '%s\n' "PASS: ${case_name} preserves ownership and service recovery"
		exit 0
	fi
	# Runtime installer does not enable nounset; restore deliberately uses one argument.
	set +u
	case "${case_name}" in
		restore*) backup_restore RESTORE || status=$? ;;
		*) inst_AdGuardHome update release || status=$? ;;
	esac
	set -u
	case "${case_name}" in
		publish-copy-fail | publish-chmod-fail | publish-rename-fail)
			[ "${status}" -ne 0 ] || fail "${case_name}: failed publication accepted"
			[ "$(cat "${ADDON_DIR}/AdGuardHome.sh")" = old ] || fail "${case_name}: write failure damaged working manager"
			[ "${RUNNING}" = 1 ] || fail "${case_name}: service was not recovered"
			;;
		prefetch-fail | restore-prefetch-fail | restore-timezone-opkg-fail | restore-timezone-fetch-fail | sha-mismatch | sha-invalid | md5-mismatch)
			[ "${status}" -ne 0 ] || fail "${case_name}: failed prefetch accepted"
			! grep -q '^stop$' "${CALLS_FILE}" || fail "${case_name}: service stopped before prefetch succeeded"
			[ "${TARGET_MUTATED}" = 0 ] || fail "${case_name}: restore target changed before prefetch succeeded"
			[ "$(cat "${ADDON_DIR}/AdGuardHome.sh")" = old ] || fail "${case_name}: existing manager changed"
			grep -q old "${AGH_FILE}" || fail "${case_name}: existing binary changed"
			;;
		*)
			if [ "${status}" != 0 ]; then
				cat "${CALLS_FILE}" >&2
				fail "${case_name}: update failed when DNS became unavailable after stop"
			fi
			! grep -q '^fetch:.*:running=0:mutated=' "${CALLS_FILE}" || case "${case_name}" in stopped | fresh) : ;; *) fail "${case_name}: network fetch while stopped" ;; esac
			case "${case_name}" in restore*)
				! grep -q '^fetch:.*:mutated=1$' "${CALLS_FILE}" || fail 'restore downloaded after target mutation'
				! grep -q '^opkg:.*:mutated=1$' "${CALLS_FILE}" || fail 'restore installed an online prerequisite after target mutation'
				[ "$(cat "${ADDON_DIR}/localtime")" = 'fixture timezone' ] || fail 'restore did not prepare its timezone'
				grep -q '^opkg:column:.*:mutated=0$' "${CALLS_FILE}" || fail 'restore did not prepare Entware timezone support'
				case "${case_name}" in restore-sha-missing)
					[ "$(grep -c '^opkg:coreutils-sha256sum:' "${CALLS_FILE}")" = 1 ] || fail 'restore retried online checksum repair after mutation'
					grep -q '^fetch:installer.md5sum:' "${CALLS_FILE}" || fail 'restore lost the intentional MD5 fallback'
					;;
				esac
				;;
			esac
			for target in "${ADDON_DIR}/AdGuardHome.sh" /opt/etc/init.d/S99AdGuardHome /opt/etc/init.d/rc.func.AdGuardHome; do
				cmp "${target}" "${TMP_ROOT}/remote/${target##*/}" || fail "${case_name}: staged service file not published"
			done
			[ "$(stat -c %a "${ADDON_DIR}/AdGuardHome.sh")" = 755 ] || fail 'manager mode changed'
			[ "$(stat -c %a /opt/etc/init.d/S99AdGuardHome)" = 755 ] || fail 'init mode changed'
			[ "$(stat -c %a /opt/etc/init.d/rc.func.AdGuardHome)" = 644 ] || fail 'helper mode changed'
			;;
	esac
	[ ! -d "${BASE_DIR}/.AdGuardHome.services.$$" ] || fail "${case_name}: owned staging leaked"
	[ ! -d "${ADDON_DIR}/.AdGuardHome.service.$$" ] || fail "${case_name}: publication staging leaked"
	printf '%s\n' "PASS: ${case_name} prefetch and publication ordering"
)

# Use a separate shell so TERM reaches its real PID and must run the handler
# armed by package orchestration. An EXIT trap alone does not handle TERM.
run_armed_signal_case() {
	local signal_mode signal_root signal_running signal_status stage_path
	signal_mode="$1"
	signal_root="${TMP_ROOT}/armed-signal-${signal_mode}"
	case "${signal_mode}" in fresh) signal_running=0 ;; refresh) signal_running=1 ;; esac
	mkdir -p "${signal_root}/base/AdGuardHome" "${signal_root}/addon" || fail 'could not create armed signal fixture'
	printf '%s\n' working >"${signal_root}/addon/AdGuardHome.sh"
	cat >"${signal_root}/child.sh" <<'EOF_SIGNAL'
set -u
. "$1"
BASE_DIR="$2/base"
TARG_DIR="${BASE_DIR}/AdGuardHome"
ADDON_DIR="$2/addon"
AGH_FILE="${TARG_DIR}/AdGuardHome"
SCRIPT_LOC="$2/missing-installer"
CALLS_FILE="$2/calls"
ADGUARD_ARCH=test
URL_ARCH=https://archive.invalid
RURL=https://source.invalid/pinned-commit
INFO=Info: ERROR=Error:
ADGUARD_SERVICE_STAGE_OWNED=0
ADGUARD_SERVICE_PUBLISH_OWNED=0
case "$3" in fresh) RUNNING=0 SERVICE_REFRESH_ONLY=0 ACTION=install ;; refresh) RUNNING=1 SERVICE_REFRESH_ONLY=1 ACTION=update ;; esac
# Progress helpers suppress terminal output from the real orchestration.
PTXT() { :; }
# ptxt_phase suppresses phase headings while real orchestration executes.
ptxt_phase() { :; }
# ptxt_step suppresses progress steps unrelated to fetch and publication ordering.
ptxt_step() { :; }
# ptxt_ok suppresses success decoration while assertions inspect actual outcomes.
ptxt_ok() { :; }
# ptxt_warn suppresses warning decoration without changing helper return status.
ptxt_warn() { :; }
# sha256sum_available keeps unrelated package repair outside this signal fixture.
sha256sum_available() { return 0; }
# Remote-channel helpers supply one local archive name without network requests.
adguard_remote_archive() { printf '%s\n' AdGuardHome_test.tar.gz; }
# adguard_remote_md5 leaves archive MD5 lookup outside the interrupted service-transfer case.
adguard_remote_md5() { :; }
# adguard_remote_sha256 leaves archive SHA-256 lookup outside the interrupted service-transfer case.
adguard_remote_sha256() { :; }
# adguard_remote_url leaves archive URL lookup outside the interrupted service-transfer case.
adguard_remote_url() { :; }
# agh_process_count models the public fresh and service-refresh running states.
agh_process_count() { printf '%s\n' "${RUNNING}"; }
# clear_screen avoids terminal control output during the signal handler.
clear_screen() { :; }
# adguard_restart_after_install_abort records the prior state passed by the real handler.
adguard_restart_after_install_abort() { printf '%s\n' "prior-running:$1" >>"${CALLS_FILE}"; }
# download_file interrupts the second service transfer after the first owned file exists.
download_file() {
	if [ "${3##*/}" = S99AdGuardHome ]; then
		[ "${ADGUARD_SERVICE_STAGE_OWNED}" = 1 ] && [ -f "${ADGUARD_SERVICE_STAGE_DIR}/AdGuardHome.sh" ] || exit 90
		kill -TERM "$$"
		exit 91
	fi
	printf '%s\n' verified >"$1/${3##*/}"
}
# end_op_message preserves the real signal path's owned cleanup and terminal exit.
end_op_message() {
	[ "${ADGUARD_SERVICE_STAGE_OWNED:-0}" != 1 ] || adguard_service_bundle_cleanup
	[ "${ADGUARD_SERVICE_PUBLISH_OWNED:-0}" != 1 ] || adguard_service_publish_cleanup
	printf '%s\n' "signal-status:$1" >>"${CALLS_FILE}"
	exit "$1"
}
trap '[ "${ADGUARD_SERVICE_STAGE_OWNED:-0}" != 1 ] || adguard_service_bundle_cleanup' 0
set +u
inst_AdGuardHome "${ACTION}" release
exit 92
EOF_SIGNAL
	signal_status=0
	"${TEST_SHELL:-sh}" "${signal_root}/child.sh" "${FUNCTIONS_FILE}" "${signal_root}" "${signal_mode}" || signal_status=$?
	[ "${signal_status}" = 2 ] || fail "prefetch TERM did not reach its armed recovery handler: ${signal_status}"
	grep -q '^signal-status:2$' "${signal_root}/calls" || fail 'prefetch TERM did not report interruption'
	grep -q "^prior-running:${signal_running}$" "${signal_root}/calls" || fail 'prefetch TERM lost the prior service state'
	for stage_path in "${signal_root}/base"/.AdGuardHome.services.*; do
		if [ -e "${stage_path}" ] || [ -L "${stage_path}" ]; then
			fail 'actual TERM leaked owned service staging'
		fi
	done
	[ "$(cat "${signal_root}/addon/AdGuardHome.sh")" = working ] || fail 'actual TERM changed the live service file'
	[ ! -f "${signal_root}/base/AdGuardHome/AdGuardHome" ] || fail 'actual TERM reached binary replacement'
	printf '%s\n' "PASS: actual ${signal_mode} prefetch TERM runs armed cleanup before binary replacement"
}

for scenario in running prefetch-fail sha-mismatch sha-invalid md5-mismatch stopped fresh refresh md5 restore restore-sha-missing restore-prefetch-fail restore-timezone-opkg-fail restore-timezone-fetch-fail publish-copy-fail publish-chmod-fail publish-rename-fail signal-cleanup cleanup-retained; do
	run_case "${scenario}" || exit 1
done
run_armed_signal_case fresh
run_armed_signal_case refresh
