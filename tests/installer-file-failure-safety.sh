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

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

mkdir -p "${TMP_DIR}/target" || exit 1

awk '
	/^_quote\(\)/,/^}/
	/^PTXT\(\)/,/^}/
	/^md5_is_valid\(\)/,/^}/
	/^file_md5\(\)/,/^}/
	/^adguard_archive_is_safe\(\)/,/^}/
	/^adguard_restart_after_failed_replace\(\)/,/^}/
	/^adguard_restart_after_install_abort\(\)/,/^}/
	/^adguard_install_abort_trap_disable\(\)/,/^}/
	/^adguard_install_abort_on_signal\(\)/,/^}/
	/^adguard_install_abort_trap_enable\(\)/,/^}/
	/^adguard_restore_after_failed_replace\(\)/,/^}/
	/^adguardhome_yaml_ipset_file\(\)/,/^}/
	/^ensure_adguardhome_directory_permissions\(\)/,/^}/
	/^create_backup_archive\(\)/,/^}/
	/^install_adguard_archive\(\)/,/^}/
	/^download_file\(\)/,/^}/
	/^write_command_script\(\)/,/^}/
	/^write_conf\(\)/,/^}/
' "${REPO_DIR}/installer" >"${FUNCTIONS_FILE}"

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	BOLD=""
	NORM=""
	INFO="Info:"
	ERROR="Error:"
	WARNING="Warning:"

	ai_have_cmd() {
		[ "$1" = "md5sum" ]
	}

	http_get_file() {
		case "$1" in
			*.md5sum)
				md5sum "${TMP_DIR}/payload" | awk '{print $1}' >"$2"
				;;
			*)
				cp "${TMP_DIR}/payload" "$2"
				;;
		esac
	}

	chmod() {
		return 1
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

	tar() {
		_verbose="0"
		case "$1" in
			*tv*) _verbose="1" ;;
		esac
		if [ "${_verbose}" -eq 1 ]; then
			case "${ARCHIVE_LAYOUT}" in
				symlink)
					printf '%s\n' \
						'drwxr-xr-x root/root 0 date ./AdGuardHome/' \
						'lrwxrwxrwx root/root 0 date ./AdGuardHome/AdGuardHome -> /bin/sh'
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
				printf '%s\n' './AdGuardHome/' './AdGuardHome/AdGuardHome' './AdGuardHome/README.md'
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
			symlink)
				printf '%s\n' './AdGuardHome/' './AdGuardHome/AdGuardHome'
				;;
		esac
	}

	ARCHIVE_LAYOUT="safe"
	adguard_archive_is_safe ignored || fail "safe AdGuardHome archive layout was rejected"
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
	ARCHIVE_LAYOUT="symlink"
	if adguard_archive_is_safe ignored; then
		fail "archive with a symlinked AdGuardHome binary was accepted"
	fi
) || exit 1

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	INFO="Info:"
	ERROR="Error:"
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

	ERROR="Error:"
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

	ERROR="Error:"
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

	ERROR="Error:"
	printf '%s\n' '#!/bin/sh' >"${TMP_DIR}/event-script"

	chmod() {
		return 1
	}

	if write_command_script "${TMP_DIR}/event-script" "required command" >/dev/null 2>&1; then
		fail "write_command_script hid a chmod failure"
	fi
) || exit 1

printf '%s\n' "PASS: installer file updates preserve working copies and propagate write failures"
