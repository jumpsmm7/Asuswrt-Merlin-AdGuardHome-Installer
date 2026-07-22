#!/bin/sh
# Verify installer file updates preserve working files and report write failures.

set -u

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP_DIR="${TMPDIR:-/tmp}/agh-installer-file-failure-safety.$$"
FUNCTIONS_FILE="${TMP_DIR}/functions.sh"

cleanup() {
	rm -rf "${TMP_DIR}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

assert_rollback_result_marker() {
	_marker_file="$1"
	_context="$2"
	_result="$3"
	_detail="$4"
	_label="$5"
	[ -f "${_marker_file}" ] ||
		fail "${_label} did not write a rollback result"
	grep -q "^context=${_context}\$" "${_marker_file}" ||
		fail "${_label} wrote the wrong rollback context"
	grep -q "^result=${_result}\$" "${_marker_file}" ||
		fail "${_label} wrote the wrong rollback result"
	grep -q "^detail=${_detail}\$" "${_marker_file}" ||
		fail "${_label} wrote the wrong rollback detail"
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

mkdir -p "${TMP_DIR}/target" || exit 1

for installer_command in status doctor; do
	unsafe_dir="${TMP_DIR}/inherited-${installer_command}"
	unsafe_setup_file="${unsafe_dir}/wrapper-setup.yaml"
	unsafe_blocklist_file="${unsafe_dir}/wrapper-blocklist.yaml"
	mkdir -p "${unsafe_dir}" || exit 1
	printf '%s\n' setup >"${unsafe_setup_file}" || exit 1
	printf '%s\n' blocklist >"${unsafe_blocklist_file}" || exit 1
	SETUP_YAML_TMP_FILE="${unsafe_setup_file}" \
		BLOCKLIST_YAML_TMP_FILE="${unsafe_blocklist_file}" \
		sh "${REPO_DIR}/installer" "${installer_command}" >/dev/null 2>&1 || true
	[ -e "${unsafe_setup_file}" ] ||
		fail "${installer_command} removed an inherited setup YAML path"
	[ -e "${unsafe_blocklist_file}" ] ||
		fail "${installer_command} removed an inherited blocklist YAML path"
done

awk '
	/^_quote\(\)/,/^}/
	/^PTXT\(\)/,/^}/
	/^ptxt_phase\(\)/,/^}/
	/^ptxt_step\(\)/,/^}/
	/^ptxt_ok\(\)/,/^}/
	/^ptxt_warn\(\)/,/^}/
	/^ptxt_fail\(\)/,/^}/
	/^installer_cleanup_tmp_file\(\)/,/^}/
	/^on_installer_exit\(\)/,/^}/
	/^rollback_result_write\(\)/,/^}/
	/^rollback_result_summary\(\)/,/^}/
	/^rollback_result_notice\(\)/,/^}/
	/^conf_value\(\)/,/^}/
	/^md5_is_valid\(\)/,/^}/
	/^file_md5\(\)/,/^}/
	/^md5_manifest_digest\(\)/,/^}/
	/^sha256_is_valid\(\)/,/^}/
	/^sha256_manifest_digest\(\)/,/^}/
	/^adguard_archive_is_safe\(\)/,/^}/
	/^adguard_restart_after_failed_replace\(\)/,/^}/
	/^adguard_restart_after_install_abort\(\)/,/^}/
	/^adguard_install_abort_trap_disable\(\)/,/^}/
	/^adguard_install_abort_trap_disable_preserve_defer\(\)/,/^}/
	/^adguard_install_abort_on_signal\(\)/,/^}/
	/^adguard_install_abort_trap_enable\(\)/,/^}/
	/^adguard_restore_abort_trap_enable\(\)/,/^}/
	/^adguard_restore_after_failed_directory_restore\(\)/,/^}/
	/^adguard_restore_after_failed_replace\(\)/,/^}/
	/^finalize_pending_mode_migration\(\)/,/^}/
	/^adguardhome_yaml_ipset_file\(\)/,/^}/
	/^adguardhome_yaml_remove_ipset_file\(\)/,/^}/
	/^adguard_enforce_lan_ipset_disabled\(\)/,/^}/
	/^chmod_adguardhome_data_files_600\(\)/,/^}/
	/^ensure_adguardhome_directory_permissions\(\)/,/^}/
	/^create_backup_archive\(\)/,/^}/
	/^install_adguard_archive\(\)/,/^}/
	/^backup_restore\(\)/,/^}/
	/^create_dir\(\)/,/^}/
	/^download_file\(\)/,/^}/
	/^write_command_script\(\)/,/^}/
	/^write_conf\(\)/,/^}/
' "${REPO_DIR}/installer" >"${FUNCTIONS_FILE}"
printf 'ROLLBACK_RESULT_FILE="%s/rollback-result"\n' "${TMP_DIR}" >>"${FUNCTIONS_FILE}"

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	AGH_FILE="${TMP_DIR}/exit-cleanup/AdGuardHome"
	YAML_FILE="${AGH_FILE}.yaml"
	YAML_ORI="${TMP_DIR}/exit-cleanup/.AdGuardHome.yaml.ori"
	SETUP_YAML_TMP_FILE="${YAML_ORI}.new.$$"
	BLOCKLIST_YAML_TMP_FILE="${YAML_FILE}.blocklists.$$.tmp"
	ROLLBACK_RESULT_FILE="${TMP_DIR}/exit-cleanup/rollback-result"
	mkdir -p "${TMP_DIR}/exit-cleanup" || exit 1
	printf '%s\n' setup >"${SETUP_YAML_TMP_FILE}" || exit 1
	printf '%s\n' blocklist >"${BLOCKLIST_YAML_TMP_FILE}" || exit 1
	printf '%s\n' \
		'time=2026-07-12 00:00:00' \
		'context=package install' \
		'result=rollback unavailable' \
		'detail=archive validation failed before changes' >"${ROLLBACK_RESULT_FILE}" || exit 1
	cleanup_api_files() {
		return 0
	}
	check_dns_environment() {
		return 0
	}
	on_installer_exit
	[ ! -e "${SETUP_YAML_TMP_FILE}" ] ||
		fail "installer exit cleanup left setup YAML temp file"
	[ ! -e "${BLOCKLIST_YAML_TMP_FILE}" ] ||
		fail "installer exit cleanup left blocklist YAML temp file"
	grep -q '^result=rollback unavailable$' "${ROLLBACK_RESULT_FILE}" ||
		fail "installer exit cleanup changed the rollback marker"
) || exit 1

# SHA-256 and MD5 must both match when SHA-256 is available.  MD5 alone may
# authorize the staged file only when SHA-256 metadata or calculation is unavailable.
for checksum_case in sha_unavailable empty malformed mismatch hash_failure stale_retry missing_md5 empty_md5 malformed_md5 md5_mismatch md5_hash_failure both_valid; do
(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	BOLD=''
	NORM=''
	INFO='Info:'
	ERROR='Error:'
	WARNING='Warning:'
	attempt=0
	final_chmod=0
	printf '%s\n' 'old working copy' >"${TMP_DIR}/target/component"
	printf '%s\n' 'new downloaded copy' >"${TMP_DIR}/payload"
	PAYLOAD_SHA256="$(sha256sum "${TMP_DIR}/payload" | awk '{print $1}')"
	PAYLOAD_MD5="$(md5sum "${TMP_DIR}/payload" | awk '{print $1}')"
	ai_have_cmd() { [ "$1" = md5sum ]; }
	http_get_file() {
		case "$1" in
			*.sha256sum)
				case "${checksum_case}" in
					sha_unavailable) return 1 ;;
					empty) : >"$2" ;;
					malformed) printf '%s\n' invalid >"$2" ;;
					mismatch) printf '%064d\n' 0 >"$2" ;;
					stale_retry)
						[ "${attempt}" -eq 1 ] || return 1
						printf '%064d\n' 0 >"$2"
						;;
					hash_failure | both_valid) printf '%s\n' "${PAYLOAD_SHA256}" >"$2" ;;
					*) printf '%s\n' "${PAYLOAD_SHA256}" >"$2" ;;
				esac
				;;
			*.md5sum)
				case "${checksum_case}" in
					missing_md5) return 1 ;;
					empty_md5) : >"$2" ;;
					malformed_md5) printf '%s\n' invalid >"$2" ;;
					md5_mismatch) printf '%032d\n' 0 >"$2" ;;
					*) printf '%s\n' "${PAYLOAD_MD5}" >"$2" ;;
				esac
				;;
			*) attempt="$((attempt + 1))"; cp "${TMP_DIR}/payload" "$2" ;;
		esac
	}
	file_sha256() {
		[ "${checksum_case}" != hash_failure ] || return 1
		printf '%s' "${PAYLOAD_SHA256}"
	}
	if [ "${checksum_case}" = md5_hash_failure ]; then
		file_md5() { return 1; }
	fi
	chmod() {
		if [ "$1" = 755 ]; then final_chmod=1; fi
		return 0
	}
	case "${checksum_case}" in
		sha_unavailable | hash_failure | stale_retry | both_valid)
			download_file "${TMP_DIR}/target" 755 "https://example.invalid/component" >"${TMP_DIR}/${checksum_case}.out" 2>&1 ||
				fail "download_file rejected ${checksum_case} verification"
			[ "$(sed -n '1p' "${TMP_DIR}/target/component")" = 'new downloaded copy' ] ||
				fail "${checksum_case} did not publish the verified target"
			[ "${final_chmod}" -eq 1 ] || fail "${checksum_case} did not apply final permissions"
			;;
		*)
			if download_file "${TMP_DIR}/target" 755 "https://example.invalid/component" >"${TMP_DIR}/${checksum_case}.out" 2>&1; then
				fail "download_file accepted ${checksum_case} checksum metadata"
			fi
			[ "$(sed -n '1p' "${TMP_DIR}/target/component")" = 'old working copy' ] ||
				fail "${checksum_case} replaced the existing target"
			[ "${final_chmod}" -eq 0 ] ||
				fail "${checksum_case} applied executable permissions before verification"
			;;
	esac
	[ ! -e "${TMP_DIR}/target/.component.$$" ] ||
		fail "${checksum_case} retained a staged artifact"
	if [ "${checksum_case}" = stale_retry ] && [ "${attempt}" -ne 2 ]; then
		fail "retry did not discard the prior SHA-256 digest"
	fi
) || exit 1
done

grep -q 'falling back to MD5 verification' "${TMP_DIR}/sha_unavailable.out" || fail 'SHA-256 metadata fallback was not logged'
grep -q 'empty or invalid' "${TMP_DIR}/empty.out" || fail 'empty metadata cause was not logged'
grep -q 'empty or invalid' "${TMP_DIR}/malformed.out" || fail 'malformed metadata cause was not logged'
grep -q 'checksum mismatch' "${TMP_DIR}/mismatch.out" || fail 'checksum mismatch cause was not logged'
grep -q 'calculation is unavailable' "${TMP_DIR}/hash_failure.out" || fail 'digest calculation fallback was not logged'
grep -q 'MD5 metadata is missing or unavailable' "${TMP_DIR}/missing_md5.out" || fail 'missing MD5 metadata cause was not logged'
grep -q 'MD5 metadata is empty or invalid' "${TMP_DIR}/empty_md5.out" || fail 'empty MD5 metadata cause was not logged'
grep -q 'MD5 metadata is empty or invalid' "${TMP_DIR}/malformed_md5.out" || fail 'malformed MD5 metadata cause was not logged'
grep -q 'MD5 checksum mismatch' "${TMP_DIR}/md5_mismatch.out" || fail 'MD5 mismatch cause was not logged'
grep -q 'MD5 digest calculation failed' "${TMP_DIR}/md5_hash_failure.out" || fail 'MD5 calculation failure was not logged'

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	CALLS_FILE="${TMP_DIR}/exit-migration-recovery.calls"
	AGH_FILE="${TMP_DIR}/exit-migration-recovery/AdGuardHome"
	YAML_FILE="${AGH_FILE}.yaml"
	YAML_ORI="${TMP_DIR}/exit-migration-recovery/.AdGuardHome.yaml.ori"
	MODE_MIGRATION_YAML_FILE_BACKUP="${TMP_DIR}/exit-migration-recovery/yaml.backup"
	ADGUARD_INSTALL_WAS_RUNNING="1"
	mkdir -p "${TMP_DIR}/exit-migration-recovery" || exit 1
	rollback_pending_mode_migration() {
		printf '%s\n' rollback >>"${CALLS_FILE}"
		MODE_MIGRATION_YAML_FILE_BACKUP=""
		return 0
	}
	adguard_restart_after_install_abort() {
		printf '%s\n' "restart $1" >>"${CALLS_FILE}"
	}
	cleanup_api_files() {
		return 0
	}
	check_dns_environment() {
		return 0
	}
	on_installer_exit
	[ "$(sed -n '1p' "${CALLS_FILE}")" = rollback ] ||
		fail "installer exit cleanup did not retry pending mode migration rollback"
	[ "$(sed -n '2p' "${CALLS_FILE}")" = 'restart 1' ] ||
		fail "installer exit cleanup did not restart the previously running service after rollback"
) || exit 1

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	AGH_FILE="${TMP_DIR}/unsafe-env/AdGuardHome"
	YAML_FILE="${AGH_FILE}.yaml"
	YAML_ORI="${TMP_DIR}/unsafe-env/.AdGuardHome.yaml.ori"
	SETUP_YAML_TMP_FILE="${TMP_DIR}/unsafe-env/wrapper-setup.yaml"
	BLOCKLIST_YAML_TMP_FILE="${TMP_DIR}/unsafe-env/wrapper-blocklist.yaml"
	mkdir -p "${TMP_DIR}/unsafe-env" || exit 1
	printf '%s\n' setup >"${SETUP_YAML_TMP_FILE}" || exit 1
	printf '%s\n' blocklist >"${BLOCKLIST_YAML_TMP_FILE}" || exit 1
	cleanup_api_files() {
		return 0
	}
	check_dns_environment() {
		return 0
	}
	on_installer_exit
	[ -e "${SETUP_YAML_TMP_FILE}" ] ||
		fail "installer exit cleanup removed an unowned setup YAML path"
	[ -e "${BLOCKLIST_YAML_TMP_FILE}" ] ||
		fail "installer exit cleanup removed an unowned blocklist YAML path"
) || exit 1

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	BOLD=""
	NORM=""
	INFO="Info:"
	ERROR="Error:"
	WARNING="Warning:"

	ai_have_cmd() {
		case "$1" in
			md5sum | sha256sum) return 0 ;;
		esac
		return 1
	}

	http_get_file() {
		case "$1" in
			*.md5sum)
				md5sum "${TMP_DIR}/payload" | awk '{print $1}' >"$2"
				;;
			*.sha256sum)
				sha256sum "${TMP_DIR}/payload" | awk '{print $1}' >"$2"
				;;
			*)
				cp "${TMP_DIR}/payload" "$2"
				;;
		esac
	}

	chmod() {
		[ "$1" = 600 ]
	}

	printf '%s\n' "old working copy" >"${TMP_DIR}/target/component"
	printf '%s\n' "new downloaded copy" >"${TMP_DIR}/payload"

	if download_file "${TMP_DIR}/target" 755 "https://example.invalid/component" >/dev/null 2>&1; then
		fail "download_file accepted a chmod failure"
	fi
	[ "$(sed -n '1p' "${TMP_DIR}/target/component")" = "old working copy" ] ||
		fail "download_file replaced the working copy before chmod succeeded"
) || exit 1

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	INFO="Info:"
	ERROR="Error:"
	WARNING="Warning:"
	ADGUARD_DEFER_END_OP="1"
	ADGUARD_INSTALL_WAS_RUNNING="1"
	ADGUARD_RESTORE_ACTIVE="1"
	ADGUARD_RESTORE_ROLLBACK_DIR="${TMP_DIR}/rollback"
	ADGUARD_RESTORE_STAGE_DIR="${TMP_DIR}/stage"
	ADGUARD_RESTORE_TARG_DIR="${TMP_DIR}/target"
	ADGUARD_RESTORE_TARGET_INSTALLED="1"
	START_CALLED="0"

	agh_is_running() {
		return 1
	}

	agh_start() {
		START_CALLED="1"
		return 0
	}

	PTXT() {
		return 0
	}

	if ! adguard_restart_after_install_abort 1; then
		fail "restart-after-abort failed while deferred restore cleanup was active"
	fi
	[ "${START_CALLED}" = "1" ] ||
		fail "restart-after-abort did not try to restart AdGuardHome"
	[ "${ADGUARD_DEFER_END_OP:-0}" = "1" ] ||
		fail "restart-after-abort cleared deferred end_op_message state"
	[ "${ADGUARD_INSTALL_WAS_RUNNING:-0}" = "1" ] ||
		fail "restart-after-abort cleared restore restart state"
	[ "${ADGUARD_RESTORE_ACTIVE:-0}" = "1" ] ||
		fail "restart-after-abort cleared active restore cleanup state"
	[ "${ADGUARD_RESTORE_ROLLBACK_DIR:-}" = "${TMP_DIR}/rollback" ] ||
		fail "restart-after-abort cleared restore rollback directory"
	[ "${ADGUARD_RESTORE_TARGET_INSTALLED:-0}" = "1" ] ||
		fail "restart-after-abort cleared restored target state"
) || exit 1

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	INFO="Info:"
	ERROR="Error:"
	WARNING="Warning:"
	BASE_DIR="${TMP_DIR}/atomic-install"
	TARG_DIR="${BASE_DIR}/target"
	AGH_FILE="${TARG_DIR}/AdGuardHome"
	YAML_FILE="${AGH_FILE}.yaml"
	ARCHIVE_FILE="${BASE_DIR}/AdGuardHome.tar.gz"
	PUBLISHED_DURING_REPLACE="0"
	mkdir -p "${BASE_DIR}/archive/AdGuardHome" "${TARG_DIR}" || exit 1
	cat >"${BASE_DIR}/archive/AdGuardHome/AdGuardHome" <<'EOF'
#!/bin/sh
printf '%s\n' "AdGuard Home, version new"
EOF
	chmod 755 "${BASE_DIR}/archive/AdGuardHome/AdGuardHome" || exit 1
	printf '%s\n' "old binary" >"${AGH_FILE}"
	tar -czf "${ARCHIVE_FILE}" -C "${BASE_DIR}/archive" AdGuardHome || exit 1

	agh_process_count() {
		printf '%s\n' "0"
	}

	agh_prepare_binary_replace() {
		return 0
	}

	nvram() {
		printf '%s\n' "root"
	}

	chown() {
		return 0
	}

	mv() {
		if [ "$2" = "${AGH_FILE}" ] && [ -f "${AGH_FILE}" ]; then
			PUBLISHED_DURING_REPLACE="1"
		fi
		command mv "$@"
	}

	install_adguard_archive "${ARCHIVE_FILE}" >/dev/null ||
		fail "install_adguard_archive failed during atomic replacement test"
	[ "${PUBLISHED_DURING_REPLACE}" -eq 1 ] ||
		fail "installed binary was unpublished before staged replacement"
	[ "$("${AGH_FILE}" --version)" = "AdGuard Home, version new" ] ||
		fail "staged binary was not installed"
) || exit 1

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	INFO="Info:"
	ERROR="Error:"
	WARNING="Warning:"
	AGH_FILE="${TMP_DIR}/rollback/AdGuardHome"
	OLD_BINARY="${TMP_DIR}/rollback/AdGuardHome.previous"
	RESTART_CALLS="0"
	mkdir -p "${TMP_DIR}/rollback" || exit 1
	printf '%s\n' "new binary" >"${AGH_FILE}"
	printf '%s\n' "old binary" >"${OLD_BINARY}"

	agh_start() {
		RESTART_CALLS="$((RESTART_CALLS + 1))"
		return 0
	}

	adguard_restore_after_failed_replace "${OLD_BINARY}" 1 >/dev/null ||
		fail "previous binary rollback failed"
	[ "$(sed -n '1p' "${AGH_FILE}")" = "old binary" ] ||
		fail "previous binary was not restored"
	[ "${RESTART_CALLS}" -eq 1 ] || fail "restored service was not restarted"

	rm -f "${OLD_BINARY}"
	printf '%s\n' "failed fresh binary" >"${AGH_FILE}"
	RESTART_CALLS="0"
	adguard_restore_after_failed_replace "${OLD_BINARY}" 0 >/dev/null ||
		fail "fresh-install cleanup returned failure"
	[ ! -e "${AGH_FILE}" ] || fail "failed fresh-install binary was not removed"
	[ "${RESTART_CALLS}" -eq 0 ] || fail "fresh-install cleanup unexpectedly started the service"

	printf '%s\n' "new binary" >"${AGH_FILE}"
	printf '%s\n' "old binary" >"${OLD_BINARY}"
	RESTART_CALLS="0"
	DESTINATION_PRESENT_DURING_ROLLBACK="0"
	mv() {
		if [ "$1" = "${OLD_BINARY}" ] && [ "$2" = "${AGH_FILE}" ] && [ -f "${AGH_FILE}" ]; then
			DESTINATION_PRESENT_DURING_ROLLBACK="1"
		fi
		return 1
	}
	if adguard_restore_after_failed_replace "${OLD_BINARY}" 1 >/dev/null; then
		fail "failed binary restore was reported as successful"
	fi
	[ "${DESTINATION_PRESENT_DURING_ROLLBACK}" -eq 1 ] ||
		fail "failed binary was removed before rollback rename"
	[ "${RESTART_CALLS}" -eq 0 ] || fail "service restart was attempted without a restored binary"
) || exit 1

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	# tar simulates archive listing output for the configured test layout and rejects unsupported invocation options.
	tar() {
		case "$1" in
			-*) ;;
			*) return 1 ;;
		esac
		_verbose="0"
		case "$1" in
			*v*) _verbose="1" ;;
		esac
		if [ "${_verbose}" -eq 1 ]; then
			case "${ARCHIVE_LAYOUT}" in
				safe)
					printf '%s\n' \
						'drwxr-xr-x root/root 0 date ./AdGuardHome/' \
						'-rwxr-xr-x root/root 1 date ./AdGuardHome/AdGuardHome' \
						'-rw-r--r-- root/root 1 date ./AdGuardHome/AdGuardHome.yaml' \
						'drwxr-xr-x root/root 0 date ./AdGuardHome/data/'
					;;
				busybox-data-no-slash)
					printf '%s\n' \
						'drwxr-xr-x root/root 0 date ./AdGuardHome/' \
						'-rwxr-xr-x root/root 1 date ./AdGuardHome/AdGuardHome' \
						'-rw-r--r-- root/root 1 date ./AdGuardHome/AdGuardHome.yaml' \
						'drwxr-xr-x root/root 0 date ./AdGuardHome/data'
					;;
				symlink-binary)
					printf '%s\n' \
						'drwxr-xr-x root/root 0 date ./AdGuardHome/' \
						'lrwxrwxrwx root/root 0 date ./AdGuardHome/AdGuardHome -> /bin/sh'
					;;
				binary-dir)
					printf '%s\n' \
						'drwxr-xr-x root/root 0 date ./AdGuardHome/' \
						'drwxr-xr-x root/root 0 date ./AdGuardHome/AdGuardHome/'
					;;
				symlink-extra)
					printf '%s\n' \
						'drwxr-xr-x root/root 0 date ./AdGuardHome/' \
						'-rwxr-xr-x root/root 1 date ./AdGuardHome/AdGuardHome' \
						'lrwxrwxrwx root/root 0 date ./AdGuardHome/data/querylog.json -> filters/querylog.json'
					;;
				symlink-relative-parent)
					printf '%s\n' \
						'drwxr-xr-x root/root 0 date ./AdGuardHome/' \
						'-rwxr-xr-x root/root 1 date ./AdGuardHome/AdGuardHome' \
						'lrwxrwxrwx root/root 0 date ./AdGuardHome/data/querylog.json -> ../filters/querylog.json'
					;;
				symlink-outside)
					printf '%s\n' \
						'drwxr-xr-x root/root 0 date ./AdGuardHome/' \
						'-rwxr-xr-x root/root 1 date ./AdGuardHome/AdGuardHome' \
						'lrwxrwxrwx root/root 0 date ./AdGuardHome/data/querylog.json -> /jffs/scripts/services-start'
					;;
				symlink-traversal)
					printf '%s\n' \
						'drwxr-xr-x root/root 0 date ./AdGuardHome/' \
						'-rwxr-xr-x root/root 1 date ./AdGuardHome/AdGuardHome' \
						'lrwxrwxrwx root/root 0 date ./AdGuardHome/data/querylog.json -> ../../jffs/scripts/services-start'
					;;
				symlink-arrow-target)
					printf '%s\n' \
						'drwxr-xr-x root/root 0 date ./AdGuardHome/' \
						'-rwxr-xr-x root/root 1 date ./AdGuardHome/AdGuardHome' \
						'lrwxrwxrwx root/root 0 date ./AdGuardHome/data/querylog.json -> /jffs/scripts/services-start -> AdGuardHome/data/querylog.json'
					;;
				data-file)
					printf '%s\n' \
						'drwxr-xr-x root/root 0 date ./AdGuardHome/' \
						'-rwxr-xr-x root/root 1 date ./AdGuardHome/AdGuardHome' \
						'-rw-r--r-- root/root 1 date ./AdGuardHome/AdGuardHome.yaml' \
						'-rw-r--r-- root/root 1 date ./AdGuardHome/data'
					;;
				data-dir-then-file)
					printf '%s\n' \
						'drwxr-xr-x root/root 0 date ./AdGuardHome/' \
						'-rwxr-xr-x root/root 1 date ./AdGuardHome/AdGuardHome' \
						'-rw-r--r-- root/root 1 date ./AdGuardHome/AdGuardHome.yaml' \
						'drwxr-xr-x root/root 0 date ./AdGuardHome/data/' \
						'-rw-r--r-- root/root 1 date ./AdGuardHome/data'
					;;
				data-symlink)
					printf '%s\n' \
						'drwxr-xr-x root/root 0 date ./AdGuardHome/' \
						'-rwxr-xr-x root/root 1 date ./AdGuardHome/AdGuardHome' \
						'-rw-r--r-- root/root 1 date ./AdGuardHome/AdGuardHome.yaml' \
						'lrwxrwxrwx root/root 0 date ./AdGuardHome/data -> .'
					;;
				symlink-yaml)
					printf '%s\n' \
						'drwxr-xr-x root/root 0 date ./AdGuardHome/' \
						'-rwxr-xr-x root/root 1 date ./AdGuardHome/AdGuardHome' \
						'lrwxrwxrwx root/root 0 date ./AdGuardHome/AdGuardHome.yaml -> filters/config.yaml' \
						'drwxr-xr-x root/root 0 date ./AdGuardHome/data/'
					;;
				yaml-dir)
					printf '%s\n' \
						'drwxr-xr-x root/root 0 date ./AdGuardHome/' \
						'-rwxr-xr-x root/root 1 date ./AdGuardHome/AdGuardHome' \
						'drwxr-xr-x root/root 0 date ./AdGuardHome/AdGuardHome.yaml/' \
						'drwxr-xr-x root/root 0 date ./AdGuardHome/data/'
					;;
				original-only)
					printf '%s\n' \
						'drwxr-xr-x root/root 0 date ./AdGuardHome/' \
						'-rwxr-xr-x root/root 1 date ./AdGuardHome/AdGuardHome' \
						'-rw-r--r-- root/root 1 date ./AdGuardHome/.AdGuardHome.yaml.ori' \
						'drwxr-xr-x root/root 0 date ./AdGuardHome/data/'
					;;
				*)
					printf '%s\n' \
						'drwxr-xr-x root/root 0 date ./AdGuardHome/' \
						'-rwxr-xr-x root/root 1 date ./AdGuardHome/AdGuardHome'
					;;
			esac
			return 0
		fi
		case "${ARCHIVE_LAYOUT}" in
			safe)
				printf '%s\n' './AdGuardHome/' './AdGuardHome/AdGuardHome' './AdGuardHome/AdGuardHome.yaml' './AdGuardHome/data/' './AdGuardHome/README.md'
				;;
			busybox-data-no-slash)
				printf '%s\n' './AdGuardHome/' './AdGuardHome/AdGuardHome' './AdGuardHome/AdGuardHome.yaml' './AdGuardHome/data'
				;;
			original-only)
				printf '%s\n' './AdGuardHome/' './AdGuardHome/AdGuardHome' './AdGuardHome/.AdGuardHome.yaml.ori' './AdGuardHome/data/'
				;;
			missing-yaml)
				printf '%s\n' './AdGuardHome/' './AdGuardHome/AdGuardHome' './AdGuardHome/data/querylog.json'
				;;
			missing-data)
				printf '%s\n' './AdGuardHome/' './AdGuardHome/AdGuardHome' './AdGuardHome/AdGuardHome.yaml'
				;;
			data-file)
				printf '%s\n' './AdGuardHome/' './AdGuardHome/AdGuardHome' './AdGuardHome/AdGuardHome.yaml' './AdGuardHome/data'
				;;
			data-symlink)
				printf '%s\n' './AdGuardHome/' './AdGuardHome/AdGuardHome' './AdGuardHome/AdGuardHome.yaml' './AdGuardHome/data' './AdGuardHome/data/querylog.json'
				;;
			symlink-yaml)
				printf '%s\n' './AdGuardHome/' './AdGuardHome/AdGuardHome' './AdGuardHome/AdGuardHome.yaml' './AdGuardHome/data/'
				;;
			traversal)
				printf '%s\n' './AdGuardHome/AdGuardHome' './AdGuardHome/../../jffs/scripts/services-start'
				;;
			absolute)
				printf '%s\n' './AdGuardHome/AdGuardHome' '/jffs/scripts/services-start'
				;;
			missing)
				printf '%s\n' './AdGuardHome/' './AdGuardHome/README.md'
				;;
			symlink-binary | symlink-extra | symlink-relative-parent | symlink-outside | symlink-traversal | symlink-arrow-target)
				printf '%s\n' './AdGuardHome/' './AdGuardHome/AdGuardHome' './AdGuardHome/data/querylog.json'
				;;
		esac
	}

	ARCHIVE_LAYOUT="safe"
	adguard_archive_is_safe ignored || fail "safe AdGuardHome archive layout was rejected"
	adguard_archive_is_safe ignored 1 || fail "complete AdGuardHome backup layout was rejected"
	ARCHIVE_LAYOUT="busybox-data-no-slash"
	adguard_archive_is_safe ignored 1 || fail "complete BusyBox backup layout without data trailing slash was rejected"
	ARCHIVE_LAYOUT="original-only"
	adguard_archive_is_safe ignored 1 || fail "backup containing only the original YAML snapshot was rejected"
	ARCHIVE_LAYOUT="missing-yaml"
	adguard_archive_is_safe ignored || fail "install archive without restored state was rejected"
	if adguard_archive_is_safe ignored 1; then
		fail "backup archive without AdGuardHome.yaml was accepted"
	fi
	ARCHIVE_LAYOUT="missing-data"
	adguard_archive_is_safe ignored || fail "install archive without data directory was rejected"
	if adguard_archive_is_safe ignored 1; then
		fail "backup archive without data directory was accepted"
	fi
	ARCHIVE_LAYOUT="data-file"
	adguard_archive_is_safe ignored || fail "install archive with data as a file was rejected"
	if adguard_archive_is_safe ignored 1; then
		fail "backup archive with data as a file was accepted"
	fi
	ARCHIVE_LAYOUT="data-dir-then-file"
	if adguard_archive_is_safe ignored 1; then
		fail "backup archive with data directory overwritten by a file was accepted"
	fi
	ARCHIVE_LAYOUT="data-symlink"
	adguard_archive_is_safe ignored || fail "install archive with data as a symlink was rejected"
	if adguard_archive_is_safe ignored 1; then
		fail "backup archive with data as a symlink was accepted"
	fi
	ARCHIVE_LAYOUT="symlink-yaml"
	adguard_archive_is_safe ignored || fail "install archive with AdGuardHome.yaml as a symlink was rejected"
	if adguard_archive_is_safe ignored 1; then
		fail "backup archive with AdGuardHome.yaml as a symlink was accepted"
	fi
	ARCHIVE_LAYOUT="yaml-dir"
	if adguard_archive_is_safe ignored 1; then
		fail "backup archive with AdGuardHome.yaml as a directory was accepted"
	fi
	ARCHIVE_LAYOUT="traversal"
	if adguard_archive_is_safe ignored; then
		fail "archive path traversal was accepted"
	fi
	ARCHIVE_LAYOUT="absolute"
	if adguard_archive_is_safe ignored; then
		fail "absolute archive path was accepted"
	fi
	ARCHIVE_LAYOUT="missing"
	if adguard_archive_is_safe ignored; then
		fail "archive without the AdGuardHome binary was accepted"
	fi
	ARCHIVE_LAYOUT="symlink-extra"
	adguard_archive_is_safe ignored || fail "archive with a non-binary symlink was rejected"
	ARCHIVE_LAYOUT="symlink-relative-parent"
	adguard_archive_is_safe ignored || fail "archive with an in-tree parent-relative symlink was rejected"
	ARCHIVE_LAYOUT="symlink-outside"
	if adguard_archive_is_safe ignored; then
		fail "archive with an absolute symlink target outside AdGuardHome was accepted"
	fi
	ARCHIVE_LAYOUT="symlink-traversal"
	if adguard_archive_is_safe ignored; then
		fail "archive with a traversing symlink target outside AdGuardHome was accepted"
	fi
	ARCHIVE_LAYOUT="symlink-arrow-target"
	if adguard_archive_is_safe ignored; then
		fail "archive with a symlink target containing an arrow was accepted"
	fi
	ARCHIVE_LAYOUT="symlink-binary"
	if adguard_archive_is_safe ignored; then
		fail "archive with a symlinked AdGuardHome binary was accepted"
	fi
	ARCHIVE_LAYOUT="binary-dir"
	if adguard_archive_is_safe ignored; then
		fail "archive with AdGuardHome binary as a directory was accepted"
	fi
) || exit 1

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	INFO="Info:"
	ERROR="Error:"
	WARNING="Warning:"
	BASE_DIR="${TMP_DIR}/install-marker-base"
	TARG_DIR="${BASE_DIR}/AdGuardHome"
	AGH_FILE="${TARG_DIR}/AdGuardHome"
	ROLLBACK_RESULT_FILE="${BASE_DIR}/.AdGuardHome.rollback_result"
	ADGUARD_INSTALL_REPLACE_ACTIVE="0"
	ADGUARD_INSTALL_OLD_BINARY=""
	ADGUARD_INSTALL_WAS_RUNNING="0"
	ADGUARD_INSTALL_STAGE_DIR=""
	ADGUARD_RESTORE_ACTIVE="0"
	mkdir -p "${BASE_DIR}" || fail "could not prepare install marker base"

	tar() {
		case "$1" in
			-t*) printf '%s\n' './AdGuardHome/README.md' ;;
			*) return 1 ;;
		esac
	}

	chmod() {
		return 0
	}

	if install_adguard_archive "${TMP_DIR}/bad-install.tar.gz" >/dev/null 2>&1; then
		fail "install_adguard_archive accepted an unsafe archive"
	fi
	assert_rollback_result_marker "${ROLLBACK_RESULT_FILE}" "package install" "rollback unavailable" "archive validation failed before changes" "unsafe install archive"
) || exit 1

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	INFO="Info:"
	ERROR="Error:"
	WARNING="Warning:"
	BASE_DIR="${TMP_DIR}/install-extract-marker-base"
	TARG_DIR="${BASE_DIR}/AdGuardHome"
	AGH_FILE="${TARG_DIR}/AdGuardHome"
	ROLLBACK_RESULT_FILE="${BASE_DIR}/.AdGuardHome.rollback_result"
	ADGUARD_INSTALL_REPLACE_ACTIVE="0"
	ADGUARD_INSTALL_OLD_BINARY=""
	ADGUARD_INSTALL_WAS_RUNNING="0"
	ADGUARD_INSTALL_STAGE_DIR=""
	ADGUARD_RESTORE_ACTIVE="0"
	mkdir -p "${BASE_DIR}" || fail "could not prepare install extraction marker base"

	tar() {
		case "$1" in
			-tzvf) printf '%s\n' \
				'drwxr-xr-x root/root 0 date ./AdGuardHome/' \
				'-rwxr-xr-x root/root 1 date ./AdGuardHome/AdGuardHome' ;;
			-tzf) printf '%s\n' './AdGuardHome/' './AdGuardHome/AdGuardHome' ;;
			*) return 1 ;;
		esac
	}

	if install_adguard_archive "${TMP_DIR}/extract-fail.tar.gz" >/dev/null 2>&1; then
		fail "install_adguard_archive accepted a failed extraction"
	fi
	assert_rollback_result_marker "${ROLLBACK_RESULT_FILE}" "package install" "rollback unavailable" "archive extraction failed before changes" "failed install extraction"
) || exit 1

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	INFO="Info:"
	ERROR="Error:"
	WARNING="Warning:"
	BASE_DIR="${TMP_DIR}/install-binary-marker-base"
	TARG_DIR="${BASE_DIR}/AdGuardHome"
	AGH_FILE="${TARG_DIR}/AdGuardHome"
	ROLLBACK_RESULT_FILE="${BASE_DIR}/.AdGuardHome.rollback_result"
	ADGUARD_INSTALL_REPLACE_ACTIVE="0"
	ADGUARD_INSTALL_OLD_BINARY=""
	ADGUARD_INSTALL_WAS_RUNNING="0"
	ADGUARD_INSTALL_STAGE_DIR=""
	ADGUARD_RESTORE_ACTIVE="0"
	mkdir -p "${BASE_DIR}" || fail "could not prepare install binary marker base"

	tar() {
		case "$1" in
			-tzvf) printf '%s\n' \
				'drwxr-xr-x root/root 0 date ./AdGuardHome/' \
				'-rwxr-xr-x root/root 1 date ./AdGuardHome/AdGuardHome' ;;
			-tzf) printf '%s\n' './AdGuardHome/' './AdGuardHome/AdGuardHome' ;;
			*)
				mkdir -p "${BASE_DIR}/.AdGuardHome.extract.$$/AdGuardHome" || return 1
				printf '%s\n' '#!/bin/sh' 'exit 1' >"${BASE_DIR}/.AdGuardHome.extract.$$/AdGuardHome/AdGuardHome"
				return 0
				;;
		esac
	}

	if install_adguard_archive "${TMP_DIR}/bad-binary.tar.gz" >/dev/null 2>&1; then
		fail "install_adguard_archive accepted an invalid staged binary"
	fi
	assert_rollback_result_marker "${ROLLBACK_RESULT_FILE}" "package install" "rollback unavailable" "staged binary validation failed before changes" "invalid staged install binary"
) || exit 1

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	INFO="Info:"
	ERROR="Error:"
	WARNING="Warning:"
	BASE_DIR="${TMP_DIR}/restore-marker-base"
	TARG_DIR="${BASE_DIR}/AdGuardHome"
	AGH_FILE="${TARG_DIR}/AdGuardHome"
	ROLLBACK_RESULT_FILE="${BASE_DIR}/.AdGuardHome.rollback_result"
	mkdir -p "${BASE_DIR}" || fail "could not prepare restore marker base"

	end_op_message() {
		return 1
	}

	if backup_restore RESTORE >/dev/null 2>&1; then
		fail "backup_restore accepted a missing backup"
	fi
	assert_rollback_result_marker "${ROLLBACK_RESULT_FILE}" "backup restore" "rollback unavailable" "backup archive missing" "missing restore backup"
) || exit 1

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	INFO="Info:"
	ERROR="Error:"
	WARNING="Warning:"
	RESTART_CALLS="0"
	agh_start() {
		RESTART_CALLS="$((RESTART_CALLS + 1))"
		return "${RESTART_STATUS}"
	}

	RESTART_STATUS="0"
	adguard_restart_after_failed_replace 1 >/dev/null ||
		fail "restored running service was not restarted"
	[ "${RESTART_CALLS}" -eq 1 ] || fail "restored running service restart was not attempted"

	RESTART_CALLS="0"
	adguard_restart_after_failed_replace 0 >/dev/null ||
		fail "stopped service rollback returned failure"
	[ "${RESTART_CALLS}" -eq 0 ] || fail "previously stopped service was unexpectedly started"

	RESTART_STATUS="1"
	if adguard_restart_after_failed_replace 1 >/dev/null; then
		fail "failed rollback restart was reported as successful"
	fi
) || exit 1

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	INFO="Info:"
	ERROR="Error:"
	WARNING="Warning:"
	ROLLBACK_DIR="${TMP_DIR}/directory-rollback/.AdGuardHome.rollback"
	TARGET_DIR="${TMP_DIR}/directory-rollback/AdGuardHome"
	STAGE_DIR="${TMP_DIR}/directory-rollback/.AdGuardHome.restore"
	CALLS_FILE="${TMP_DIR}/directory-rollback-calls"
	mkdir -p "${ROLLBACK_DIR}" "${TARGET_DIR}" "${STAGE_DIR}" || exit 1
	printf '%s\n' "previous binary" >"${ROLLBACK_DIR}/AdGuardHome"
	printf '%s\n' "restored binary" >"${TARGET_DIR}/AdGuardHome"

	agh_is_running() {
		return 0
	}

	agh_stop() {
		printf '%s\n' stop >>"${CALLS_FILE}"
		return 0
	}

	adguard_restart_after_failed_replace() {
		printf '%s\n' "restart:$1" >>"${CALLS_FILE}"
		return 0
	}

	ADGUARD_RESTORE_ACTIVE="1"
	ADGUARD_RESTORE_ROLLBACK_DIR="${ROLLBACK_DIR}"
	ADGUARD_RESTORE_TARGET_INSTALLED="1"
	adguard_restore_after_failed_directory_restore "${ROLLBACK_DIR}" "${TARGET_DIR}" "${STAGE_DIR}" 1 1 >/dev/null ||
		fail "directory restore rollback failed"
	[ "$(sed -n '1p' "${TARGET_DIR}/AdGuardHome")" = "previous binary" ] ||
		fail "directory restore rollback did not restore the previous installation"
	[ "$(sed -n '1p' "${CALLS_FILE}")" = "stop" ] ||
		fail "directory restore rollback did not stop the restored daemon before swapping files"
	[ "$(sed -n '2p' "${CALLS_FILE}")" = "restart:1" ] ||
		fail "directory restore rollback did not restart after restoring files"
	[ "${ADGUARD_RESTORE_ACTIVE}" = "0" ] ||
		fail "directory restore rollback left restore trap state active"
	[ -z "${ADGUARD_RESTORE_ROLLBACK_DIR}" ] ||
		fail "directory restore rollback left rollback state armed"
	[ "${ADGUARD_RESTORE_TARGET_INSTALLED}" = "0" ] ||
		fail "directory restore rollback left target cleanup armed"
) || exit 1

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	INFO="Info:"
	ERROR="Error:"
	WARNING="Warning:"
	BASE_DIR="${TMP_DIR}/backup-root"
	mkdir -p "${BASE_DIR}/AdGuardHome" || exit 1
	printf '%s\n' "installed data" >"${BASE_DIR}/AdGuardHome/AdGuardHome.yaml"
	printf '%s\n' "known good backup" >"${BASE_DIR}/backup_AdGuardHome.tar.gz"

	tar() {
		return 1
	}

	if create_backup_archive >/dev/null 2>&1; then
		fail "create_backup_archive accepted a tar failure"
	fi
	[ "$(sed -n '1p' "${BASE_DIR}/backup_AdGuardHome.tar.gz")" = "known good backup" ] ||
		fail "failed backup creation destroyed the previous backup"
) || exit 1

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	INFO="Info:"
	ERROR="Error:"
	WARNING="Warning:"
	CONF_FILE="${TMP_DIR}/config"
	printf '%s\n' 'SETTING="old"' >"${CONF_FILE}"

	sed() {
		return 1
	}

	if write_conf SETTING '"new"' >/dev/null 2>&1; then
		fail "write_conf hid a sed failure"
	fi
) || exit 1

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	INFO="Info:"
	ERROR="Error:"
	WARNING="Warning:"
	printf '%s\n' '#!/bin/sh' >"${TMP_DIR}/event-script"

	chmod() {
		return 1
	}

	if write_command_script "${TMP_DIR}/event-script" "required command" >/dev/null 2>&1; then
		fail "write_command_script hid a chmod failure"
	fi
) || exit 1

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	INFO="Info:"
	ERROR="Error:"
	WARNING="Warning:"
	BASE_DIR="${TMP_DIR}/restore-root"
	TARG_DIR="${BASE_DIR}/AdGuardHome"
	AGH_FILE="${TARG_DIR}/AdGuardHome"
	ROLLBACK_RESULT_FILE="${BASE_DIR}/.AdGuardHome.rollback_result"
	mkdir -p "${TARG_DIR}" || exit 1
	printf '%s\n' "current binary" >"${AGH_FILE}"
	printf '%s\n' "not a valid backup" >"${BASE_DIR}/backup_AdGuardHome.tar.gz"

	adguard_archive_is_safe() {
		return 1
	}

	tar() {
		fail "unsafe restore archive was extracted"
	}

	if backup_restore RESTORE >/dev/null 2>&1; then
		fail "backup_restore accepted an unsafe restore archive"
	fi
	assert_rollback_result_marker "${ROLLBACK_RESULT_FILE}" "backup restore" "rollback unavailable" "unsafe backup archive refused before changes" "unsafe restore archive"
	[ "$(sed -n '1p' "${AGH_FILE}")" = "current binary" ] ||
		fail "unsafe restore archive modified the current installation"
) || exit 1

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	INFO="Info:"
	ERROR="Error:"
	WARNING="Warning:"
	BASE_DIR="${TMP_DIR}/restore-fail-root"
	TARG_DIR="${BASE_DIR}/AdGuardHome"
	AGH_FILE="${TARG_DIR}/AdGuardHome"
	ROLLBACK_RESULT_FILE="${BASE_DIR}/.AdGuardHome.rollback_result"
	mkdir -p "${TARG_DIR}" || exit 1
	printf '%s\n' "current binary" >"${AGH_FILE}"
	printf '%s\n' "safe backup placeholder" >"${BASE_DIR}/backup_AdGuardHome.tar.gz"

	adguard_archive_is_safe() {
		return 0
	}

	agh_process_count() {
		printf '%s\n' "0"
	}

	agh_is_running() {
		[ "$(agh_process_count)" -ge 1 ]
	}

	tar() {
		case "$*" in
			*" -C ${BASE_DIR}/.AdGuardHome.restore."*)
				mkdir -p "${BASE_DIR}/.AdGuardHome.restore.$$/AdGuardHome" || return 1
				printf '%s\n' "partial restore" >"${BASE_DIR}/.AdGuardHome.restore.$$/AdGuardHome/AdGuardHome"
				return 1
				;;
		esac
		return 1
	}

	if backup_restore RESTORE >/dev/null 2>&1; then
		fail "backup_restore accepted a failed staged extraction"
	fi
	assert_rollback_result_marker "${ROLLBACK_RESULT_FILE}" "backup restore" "rollback unavailable" "backup staging failed before changes" "failed staged extraction"
	[ "$(sed -n '1p' "${AGH_FILE}")" = "current binary" ] ||
		fail "failed staged restore modified the current installation"
	[ ! -d "${BASE_DIR}/.AdGuardHome.restore.$$" ] ||
		fail "failed staged restore left its staging directory behind"
) || exit 1

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	INFO="Info:"
	ERROR="Error:"
	WARNING="Warning:"
	BASE_DIR="${TMP_DIR}/restore-data-file-root"
	TARG_DIR="${BASE_DIR}/AdGuardHome"
	AGH_FILE="${TARG_DIR}/AdGuardHome"
	ROLLBACK_RESULT_FILE="${BASE_DIR}/.AdGuardHome.rollback_result"
	mkdir -p "${TARG_DIR}" || exit 1
	printf '%s\n' "current binary" >"${AGH_FILE}"
	printf '%s\n' "safe backup placeholder" >"${BASE_DIR}/backup_AdGuardHome.tar.gz"

	adguard_archive_is_safe() {
		return 0
	}

	agh_process_count() {
		printf '%s\n' "0"
	}

	tar() {
		case "$*" in
			*" -C ${BASE_DIR}/.AdGuardHome.restore."*)
				mkdir -p "${BASE_DIR}/.AdGuardHome.restore.$$/AdGuardHome" || return 1
				printf '%s\n' "restored binary" >"${BASE_DIR}/.AdGuardHome.restore.$$/AdGuardHome/AdGuardHome"
				printf '%s\n' "not a directory" >"${BASE_DIR}/.AdGuardHome.restore.$$/AdGuardHome/data"
				return 0
				;;
		esac
		return 1
	}

	create_dir() {
		mkdir -p "$1"
	}

	ensure_adguardhome_directory_permissions() {
		return 0
	}

	ln() {
		return 0
	}

	inst_AdGuardHome() {
		return 0
	}

	if backup_restore RESTORE >/dev/null 2>&1; then
		fail "backup_restore accepted staged restore data as a file"
	fi
	assert_rollback_result_marker "${ROLLBACK_RESULT_FILE}" "backup restore" "rollback unavailable" "staged backup validation failed before changes" "staged restore data file"
	[ "$(sed -n '1p' "${AGH_FILE}")" = "current binary" ] ||
		fail "staged restore with data file modified the current installation"
	[ ! -d "${BASE_DIR}/.AdGuardHome.restore.$$" ] ||
		fail "staged restore with data file left its staging directory behind"
) || exit 1

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	INFO="Info:"
	ERROR="Error:"
	WARNING="Warning:"
	BASE_DIR="${TMP_DIR}/restore-preserve-fail-root"
	TARG_DIR="${BASE_DIR}/AdGuardHome"
	AGH_FILE="${TARG_DIR}/AdGuardHome"
	ROLLBACK_RESULT_FILE="${BASE_DIR}/.AdGuardHome.rollback_result"
	mkdir -p "${TARG_DIR}" || exit 1
	printf '%s\n' "current binary" >"${AGH_FILE}"
	printf '%s\n' "safe backup placeholder" >"${BASE_DIR}/backup_AdGuardHome.tar.gz"
	REAL_MV="$(which mv)" || fail "mv is unavailable"

	adguard_archive_is_safe() {
		return 0
	}

	agh_process_count() {
		printf '%s\n' "0"
	}

	# tar extracts a simulated restored installation into the restore staging directory.
	tar() {
		case "$*" in
			*" -C ${BASE_DIR}/.AdGuardHome.restore."*)
				mkdir -p "${BASE_DIR}/.AdGuardHome.restore.$$/AdGuardHome/data" || return 1
				printf '%s\n' "restored binary" >"${BASE_DIR}/.AdGuardHome.restore.$$/AdGuardHome/AdGuardHome"
				printf '%s\n' "schema_version: 27" >"${BASE_DIR}/.AdGuardHome.restore.$$/AdGuardHome/AdGuardHome.yaml"
				return 0
				;;
		esac
		return 1
	}

	create_dir() {
		mkdir -p "$1"
	}

	mv() {
		if [ "$1" = "${TARG_DIR}" ] && [ "$2" = "${BASE_DIR}/.AdGuardHome.rollback.$$" ]; then
			return 1
		fi
		"${REAL_MV}" "$@"
	}

	if backup_restore RESTORE >/dev/null 2>&1; then
		fail "backup_restore accepted a failed current-install preservation"
	fi
	assert_rollback_result_marker "${ROLLBACK_RESULT_FILE}" "backup restore" "rollback unavailable" "could not preserve current installation" "failed current-install preservation"
	[ "$(sed -n '1p' "${AGH_FILE}")" = "current binary" ] ||
		fail "failed current-install preservation modified the current installation"
	[ ! -d "${BASE_DIR}/.AdGuardHome.restore.$$" ] ||
		fail "failed current-install preservation left its staging directory behind"
) || exit 1

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	INFO="Info:"
	ERROR="Error:"
	WARNING="Warning:"
	BASE_DIR="${TMP_DIR}/restore-swap-fail-root"
	TARG_DIR="${BASE_DIR}/AdGuardHome"
	AGH_FILE="${TARG_DIR}/AdGuardHome"
	mkdir -p "${TARG_DIR}" || exit 1
	printf '%s\n' "current binary" >"${AGH_FILE}"
	printf '%s\n' "safe backup placeholder" >"${BASE_DIR}/backup_AdGuardHome.tar.gz"
	REAL_MV="$(which mv)" || fail "mv is unavailable"

	adguard_archive_is_safe() {
		return 0
	}

	agh_process_count() {
		printf '%s\n' "0"
	}

	agh_is_running() {
		[ "$(agh_process_count)" -ge 1 ]
	}

	# tar extracts a simulated restored installation into the restore staging directory.
	tar() {
		case "$*" in
			*" -C ${BASE_DIR}/.AdGuardHome.restore."*)
				mkdir -p "${BASE_DIR}/.AdGuardHome.restore.$$/AdGuardHome/data" || return 1
				printf '%s\n' "restored binary" >"${BASE_DIR}/.AdGuardHome.restore.$$/AdGuardHome/AdGuardHome"
				printf '%s\n' "schema_version: 27" >"${BASE_DIR}/.AdGuardHome.restore.$$/AdGuardHome/AdGuardHome.yaml"
				return 0
				;;
		esac
		return 1
	}

	mv() {
		if [ "$1" = "${BASE_DIR}/.AdGuardHome.restore.$$/AdGuardHome" ] && [ "$2" = "${TARG_DIR}" ]; then
			return 1
		fi
		"${REAL_MV}" "$@"
	}

	if backup_restore RESTORE >/dev/null 2>&1; then
		fail "backup_restore accepted a failed staged install"
	fi
	[ "$(sed -n '1p' "${AGH_FILE}")" = "current binary" ] ||
		fail "failed staged install did not restore the current installation"
) || exit 1

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	INFO="Info:"
	ERROR="Error:"
	WARNING="Warning:"
	BASE_DIR="${TMP_DIR}/restore-final-fail-root"
	TARG_DIR="${BASE_DIR}/AdGuardHome"
	AGH_FILE="${TARG_DIR}/AdGuardHome"
	RESTART_CALLS="0"
	CALLS_FILE="${TMP_DIR}/restore-final-fail-calls"
	mkdir -p "${TARG_DIR}" || exit 1
	printf '%s\n' "current binary" >"${AGH_FILE}"
	printf '%s\n' "safe backup placeholder" >"${BASE_DIR}/backup_AdGuardHome.tar.gz"
	REAL_MV="$(which mv)" || fail "mv is unavailable"

	adguard_archive_is_safe() {
		return 0
	}

	agh_process_count() {
		printf '%s\n' "1"
	}

	agh_is_running() {
		[ "$(agh_process_count)" -ge 1 ]
	}

	agh_stop() {
		printf '%s\n' stop >>"${CALLS_FILE}"
		return 0
	}

	agh_start() {
		RESTART_CALLS="$((RESTART_CALLS + 1))"
		printf '%s\n' start >>"${CALLS_FILE}"
		return 0
	}

	# tar extracts a simulated restored installation into the restore staging directory.
	tar() {
		case "$*" in
			*" -C ${BASE_DIR}/.AdGuardHome.restore."*)
				mkdir -p "${BASE_DIR}/.AdGuardHome.restore.$$/AdGuardHome/data" || return 1
				printf '%s\n' "restored binary" >"${BASE_DIR}/.AdGuardHome.restore.$$/AdGuardHome/AdGuardHome"
				printf '%s\n' "schema_version: 27" >"${BASE_DIR}/.AdGuardHome.restore.$$/AdGuardHome/AdGuardHome.yaml"
				return 0
				;;
		esac
		return 1
	}

	mv() {
		"${REAL_MV}" "$@"
	}

	create_dir() {
		mkdir -p "$1"
	}

	ensure_adguardhome_directory_permissions() {
		return 0
	}

	ln() {
		return 0
	}

	rollback_pending_mode_migration() {
		return 0
	}

	inst_AdGuardHome() {
		end_op_message 1 "$1"
		return
	}

	if backup_restore RESTORE >/dev/null 2>&1; then
		fail "backup_restore accepted a failed final restore setup"
	fi
	[ "$(sed -n '1p' "${AGH_FILE}")" = "current binary" ] ||
		fail "failed final restore setup did not restore the current installation"
	[ ! -d "${BASE_DIR}/.AdGuardHome.rollback.$$" ] ||
		fail "failed final restore setup left rollback directory behind"
	[ "$(sed -n '1p' "${CALLS_FILE}")" = "stop" ] ||
		fail "failed final restore setup did not stop restored daemon before rollback"
	[ "${RESTART_CALLS}" -eq 1 ] ||
		fail "failed final restore setup did not restart the restored service"
) || exit 1

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	INFO="Info:"
	ERROR="Error:"
	WARNING="Warning:"
	BASE_DIR="${TMP_DIR}/restore-final-fail-no-current-root"
	TARG_DIR="${BASE_DIR}/AdGuardHome"
	AGH_FILE="${TARG_DIR}/AdGuardHome"
	ADGUARD_COMMAND_LINK_PATH="${BASE_DIR}/opt-sbin/AdGuardHome"
	mkdir -p "${BASE_DIR}" || exit 1
	printf '%s\n' "safe backup placeholder" >"${BASE_DIR}/backup_AdGuardHome.tar.gz"
	REAL_MV="$(which mv)" || fail "mv is unavailable"

	adguard_archive_is_safe() {
		return 0
	}

	agh_process_count() {
		printf '%s\n' "0"
	}

	agh_is_running() {
		[ "$(agh_process_count)" -ge 1 ]
	}

	# tar extracts a simulated restored installation into the restore staging directory.
	tar() {
		case "$*" in
			*" -C ${BASE_DIR}/.AdGuardHome.restore."*)
				mkdir -p "${BASE_DIR}/.AdGuardHome.restore.$$/AdGuardHome/data" || return 1
				printf '%s\n' "restored binary" >"${BASE_DIR}/.AdGuardHome.restore.$$/AdGuardHome/AdGuardHome"
				printf '%s\n' "schema_version: 27" >"${BASE_DIR}/.AdGuardHome.restore.$$/AdGuardHome/AdGuardHome.yaml"
				return 0
				;;
		esac
		return 1
	}

	mv() {
		"${REAL_MV}" "$@"
	}

	create_dir() {
		mkdir -p "$1"
	}

	ensure_adguardhome_directory_permissions() {
		return 0
	}

	ln() {
		command ln "$@"
	}

	rollback_pending_mode_migration() {
		return 0
	}

	inst_AdGuardHome() {
		end_op_message 1 "$1"
		return
	}

	if backup_restore RESTORE >/dev/null 2>&1; then
		fail "backup_restore accepted a failed final restore setup without a previous install"
	fi
	[ ! -e "${TARG_DIR}" ] ||
		fail "failed final restore setup without rollback left the restored installation active"
	[ ! -e "${ADGUARD_COMMAND_LINK_PATH}" ] ||
		fail "failed final restore setup without rollback left the command symlink behind"
	[ ! -d "${BASE_DIR}/.AdGuardHome.rollback.$$" ] ||
		fail "failed final restore setup without previous install left rollback directory behind"
) || exit 1

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	INFO="Info:"
	ERROR="Error:"
	WARNING="Warning:"
	BASE_DIR="${TMP_DIR}/restore-final-success-root"
	TARG_DIR="${BASE_DIR}/AdGuardHome"
	AGH_FILE="${TARG_DIR}/AdGuardHome"
	END_OP_CALLED="0"
	mkdir -p "${TARG_DIR}" || exit 1
	printf '%s\n' "current binary" >"${AGH_FILE}"
	printf '%s\n' "safe backup placeholder" >"${BASE_DIR}/backup_AdGuardHome.tar.gz"
	REAL_MV="$(which mv)" || fail "mv is unavailable"

	adguard_archive_is_safe() {
		return 0
	}

	agh_process_count() {
		printf '%s\n' "0"
	}

	agh_is_running() {
		[ "$(agh_process_count)" -ge 1 ]
	}

	# tar extracts a simulated restored installation into the restore staging directory.
	tar() {
		case "$*" in
			*" -C ${BASE_DIR}/.AdGuardHome.restore."*)
				mkdir -p "${BASE_DIR}/.AdGuardHome.restore.$$/AdGuardHome/data" || return 1
				printf '%s\n' "restored binary" >"${BASE_DIR}/.AdGuardHome.restore.$$/AdGuardHome/AdGuardHome"
				printf '%s\n' "schema_version: 27" >"${BASE_DIR}/.AdGuardHome.restore.$$/AdGuardHome/AdGuardHome.yaml"
				return 0
				;;
		esac
		return 1
	}

	mv() {
		"${REAL_MV}" "$@"
	}

	create_dir() {
		mkdir -p "$1"
	}

	ensure_adguardhome_directory_permissions() {
		return 0
	}

	ln() {
		return 0
	}

	inst_AdGuardHome() {
		if [ "${ADGUARD_DEFER_END_OP:-0}" != "1" ]; then
			fail "final restore setup was not run with deferred end_op_message"
		fi
		adguard_install_abort_trap_disable_preserve_defer
		if [ "${ADGUARD_DEFER_END_OP:-0}" != "1" ]; then
			fail "trap disable cleared deferred end_op_message before restore cleanup"
		fi
		if [ "${ADGUARD_RESTORE_ACTIVE:-0}" != "1" ] || [ "${ADGUARD_RESTORE_ROLLBACK_DIR:-}" != "${BASE_DIR}/.AdGuardHome.rollback.$$" ]; then
			fail "trap disable cleared restore rollback state before cleanup"
		fi
		end_op_message 0 "$1"
	}

	end_op_message() {
		if [ "${ADGUARD_DEFER_END_OP:-0}" = "1" ]; then
			return 0
		fi
		[ ! -d "${BASE_DIR}/.AdGuardHome.rollback.$$" ] ||
			fail "successful final restore setup reached end_op_message before cleanup"
		END_OP_CALLED="1"
		return 0
	}

	if ! backup_restore RESTORE >/dev/null 2>&1; then
		fail "backup_restore rejected a successful final restore setup"
	fi
	[ "${END_OP_CALLED}" = "1" ] ||
		fail "successful final restore setup did not hand off after cleanup"
	[ "$(sed -n '1p' "${AGH_FILE}")" = "restored binary" ] ||
		fail "successful final restore setup did not keep the restored installation"
) || exit 1

if sed -n '/^inst_AdGuardHome() {$/,/^set_timezone() {$/p' "${REPO_DIR}/installer" |
	awk '
		/end_op_message 1/ { saw_failure = 1; next }
		saw_failure && /^[[:space:]]*return[[:space:]]*$/ { exit 1 }
		{ saw_failure = 0 }
	'; then
	:
else
	fail "inst_AdGuardHome has a deferred failure path with a bare return"
fi

printf '%s\n' "PASS: installer file updates preserve working copies and propagate write failures"
