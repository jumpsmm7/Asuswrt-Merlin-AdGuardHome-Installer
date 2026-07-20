#!/bin/sh
# Verify installation aborts before configuration and startup when timezone setup fails.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-timezone-failure.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions"
CALLS_FILE="${TMP_ROOT}/calls"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

cleanup() {
	rm -rf "${TMP_ROOT}"
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"
mkdir -p "${TMP_ROOT}/base" "${TMP_ROOT}/target" "${TMP_ROOT}/addon" || fail 'could not create test directories'
sed -n '/^adguard_restart_after_install_abort() {$/,/^}/p' "${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" ||
	fail 'could not extract restart helper'
sed -n '/^adguard_migrate_detected_install_mode() {$/,/^}/p' "${SCRIPT_PATH}" >>"${FUNCTIONS_FILE}" ||
	fail 'could not extract install-mode migration helper'
sed -n '/^finalize_pending_mode_migration() {$/,/^}/p; /^rollback_pending_mode_migration() {$/,/^}/p' "${SCRIPT_PATH}" >>"${FUNCTIONS_FILE}" ||
	fail 'could not extract pending mode-migration helpers'
sed -n '/^install_wan_event_scripts() {$/,/^set_timezone() {$/p' "${SCRIPT_PATH}" | sed '$d' >>"${FUNCTIONS_FILE}" || fail 'could not extract installer functions'
[ -s "${FUNCTIONS_FILE}" ] || fail 'installer function extraction was empty'

cat >"${TMP_ROOT}/target/AdGuardHome" <<'EOF_AGH'
#!/bin/sh
printf '%s\n' 'AdGuard Home, version test'
EOF_AGH
chmod 755 "${TMP_ROOT}/target/AdGuardHome" || fail 'could not create test AdGuardHome executable'
: >"${CALLS_FILE}"

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	ADGUARD_ARCH='test'
	ADGUARD_INSTALL_MODE='wan'
	ADDON_DIR="${TMP_ROOT}/addon"
	AGH_FILE="${TMP_ROOT}/target/AdGuardHome"
	BASE_DIR="${TMP_ROOT}/base"
	RURL='https://example.invalid'
	SCRIPT_LOC="${TMP_ROOT}/missing-installer"
	TARG_DIR="${TMP_ROOT}/target"
	URL_ARCH='https://example.invalid'
	INFO='Info:'
	ERROR='Error:'

	adguard_install_abort_trap_disable_preserve_defer() { :; }
	adguard_remote_archive() { printf '%s\n' 'AdGuardHome_test.tar.gz'; }
	adguard_remote_md5() { :; }
	adguard_remote_sha256() { :; }
	adguard_remote_url() { printf '%s\n' 'https://example.invalid/AdGuardHome_test.tar.gz'; }
	ensure_sha256sum_tool() { :; }
	download_file() { return 0; }
	md5_is_valid() { return 1; }
	sha256_is_valid() { return 1; }
	agh_process_count() { printf '%s\n' '0'; }
	install_adguard_archive() { return 0; }
	create_dir() { mkdir -p "$1"; }
	cleanup_legacy_firewall() { :; }
	yaml_nvars_delete() { :; }
	del_between_magic() { :; }
	# del_jffs_script removes the JFFS script.
	del_jffs_script() { :; }
	# write_manager_script creates or updates the manager script.
	write_manager_script() { :; }
	# write_command_script writes a command script.
	write_command_script() { :; }
	# write_conf is a no-op stub used to satisfy installer dependencies during regression testing.
	write_conf() { :; }
	# nvram does nothing and returns success.
	nvram() { :; }
	# grep always returns failure.
	grep() { return 1; }
	# tar is a no-op stub that suppresses archive command execution.
	tar() { :; }
	chown() { :; }
	rm() { :; }
	ln() { :; }
	set_timezone() {
		printf '%s\n' 'timezone' >>"${CALLS_FILE}"
		return 1
	}
	setup_AdGuardHome() {
		printf '%s\n' 'setup' >>"${CALLS_FILE}"
		return 0
	}
	agh_complete_startup() {
		printf '%s\n' 'startup' >>"${CALLS_FILE}"
		return 0
	}
	end_op_message() {
		printf '%s\n' "end:$*" >>"${CALLS_FILE}"
		return 0
	}
	PTXT() { :; }
	ptxt_phase() { PTXT "$1"; }
	ptxt_step() { PTXT "$1"; }
	ptxt_ok() { PTXT "$1"; }
	ptxt_warn() { PTXT "$1"; }
	ptxt_fail() { PTXT "$1"; }

	if inst_AdGuardHome install release; then
		fail 'installer reported success after timezone setup failed'
	fi
) || fail 'timezone failure regression subprocess failed'

EXPECTED="$(printf '%s\n' 'timezone' 'end:1 install')"
ACTUAL="$(cat "${CALLS_FILE}")"
[ "${ACTUAL}" = "${EXPECTED}" ] || fail "installer continued after timezone failure: ${ACTUAL}"

printf '%s\n' 'PASS: timezone setup failure aborts installation before configuration and startup'
