#!/bin/sh
# Verify upgrade runtime defaults are pinned before service-file replacement paths.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-upgrade-runtime-defaults.$$"
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
sed -n '/^install_wan_event_scripts() {$/,/^set_timezone() {$/p' "${SCRIPT_PATH}" | sed '$d' >>"${FUNCTIONS_FILE}" ||
	fail 'could not extract installer functions'
[ -s "${FUNCTIONS_FILE}" ] || fail 'installer function extraction was empty'

cat >"${TMP_ROOT}/target/AdGuardHome" <<'EOF_AGH'
#!/bin/sh
printf '%s\n' 'AdGuard Home, version test'
EOF_AGH
chmod 755 "${TMP_ROOT}/target/AdGuardHome" || fail 'could not create test AdGuardHome executable'

run_update_path() {
	_mode="$1"
	_configure_result="$2"
	: >"${CALLS_FILE}"
	(
		# shellcheck disable=SC1090
		. "${FUNCTIONS_FILE}"

		ADGUARD_ARCH='test'
		ADDON_DIR="${TMP_ROOT}/addon"
		AGH_FILE="${TMP_ROOT}/target/AdGuardHome"
		BASE_DIR="${TMP_ROOT}/base"
		RURL='https://example.invalid'
		SCRIPT_LOC="${TMP_ROOT}/missing-installer"
		TARG_DIR="${TMP_ROOT}/target"
		URL_ARCH='https://example.invalid'
		INFO='Info:'
		ERROR='Error:'
		CONFIGURE_RESULT="${_configure_result}"
		RUNNING=1
		if [ "${_mode}" = "refresh" ]; then
			SERVICE_REFRESH_ONLY=1
		else
			SERVICE_REFRESH_ONLY=0
		fi

		adguard_install_abort_trap_disable_preserve_defer() { :; }
		adguard_remote_archive() { printf '%s\n' 'AdGuardHome_test.tar.gz'; }
		adguard_remote_md5() { :; }
		adguard_remote_sha256() { :; }
		adguard_remote_url() { printf '%s\n' 'https://example.invalid/AdGuardHome_test.tar.gz'; }
		ensure_sha256sum_tool() { :; }
		download_file() {
			printf '%s\n' "download:$2:$3" >>"${CALLS_FILE}"
			case "$3" in
				*/AdGuardHome_test.tar.gz) return 0 ;;
			esac
			return 1
		}
		md5_is_valid() { return 1; }
		sha256_is_valid() { return 1; }
		agh_process_count() { printf '%s\n' "${RUNNING}"; }
		install_adguard_archive() {
			printf '%s\n' 'install_archive' >>"${CALLS_FILE}"
			RUNNING=0
			return 0
		}
		agh_is_running() { [ "${RUNNING}" -eq 1 ]; }
		agh_start() {
			printf '%s\n' 'start' >>"${CALLS_FILE}"
			RUNNING=1
		}
		create_dir() {
			printf '%s\n' 'create_dir' >>"${CALLS_FILE}"
			mkdir -p "$1"
		}
		configure_runtime_defaults() {
			printf '%s\n' "configure:$1" >>"${CALLS_FILE}"
			[ "${CONFIGURE_RESULT}" = 'pass' ]
		}
		cleanup_legacy_firewall() {
			printf '%s\n' 'cleanup_legacy_firewall' >>"${CALLS_FILE}"
		}
		nvram() { :; }
		rm() { :; }
		ln() {
			printf '%s\n' 'ln' >>"${CALLS_FILE}"
			return 0
		}
		end_op_message() {
			printf '%s\n' "end:$*" >>"${CALLS_FILE}"
		}
		rollback_result_write() { :; }
		PTXT() { :; }
		ptxt_phase() { PTXT "$1"; }
		ptxt_step() { PTXT "$1"; }
		ptxt_ok() { PTXT "$1"; }
		ptxt_warn() { PTXT "$1"; }
		ptxt_fail() { PTXT "$1"; }

		if inst_AdGuardHome update release; then
			fail 'installer reported success after the forced upgrade-path failure'
		fi
	) || fail "upgrade runtime-default regression subprocess failed for ${_mode}/${_configure_result}"
}

run_update_path refresh pass
EXPECTED_REFRESH_PASS="$(printf '%s\n' \
	'create_dir' \
	'configure:upgrade' \
	'cleanup_legacy_firewall' \
	'download:755:https://example.invalid/AdGuardHome.sh' \
	'end:1 update')"
ACTUAL_REFRESH_PASS="$(cat "${CALLS_FILE}")"
[ "${ACTUAL_REFRESH_PASS}" = "${EXPECTED_REFRESH_PASS}" ] ||
	fail "service-refresh defaults were not pinned before service-file replacement path: ${ACTUAL_REFRESH_PASS}"

run_update_path refresh fail
EXPECTED_REFRESH_FAIL="$(printf '%s\n' \
	'create_dir' \
	'configure:upgrade' \
	'end:1 update')"
ACTUAL_REFRESH_FAIL="$(cat "${CALLS_FILE}")"
[ "${ACTUAL_REFRESH_FAIL}" = "${EXPECTED_REFRESH_FAIL}" ] ||
	fail "failed service-refresh default pin did not abort before cleanup/download paths: ${ACTUAL_REFRESH_FAIL}"

run_update_path package pass
EXPECTED_PACKAGE_PASS="$(printf '%s\n' \
	'download:644:https://example.invalid/AdGuardHome_test.tar.gz' \
	'install_archive' \
	'ln' \
	'create_dir' \
	'configure:upgrade' \
	'cleanup_legacy_firewall' \
	'download:755:https://example.invalid/AdGuardHome.sh' \
	'start' \
	'end:1 update')"
ACTUAL_PACKAGE_PASS="$(cat "${CALLS_FILE}")"
[ "${ACTUAL_PACKAGE_PASS}" = "${EXPECTED_PACKAGE_PASS}" ] ||
	fail "package-update defaults were not pinned before service-file replacement path: ${ACTUAL_PACKAGE_PASS}"

run_update_path package fail
EXPECTED_PACKAGE_FAIL="$(printf '%s\n' \
	'download:644:https://example.invalid/AdGuardHome_test.tar.gz' \
	'install_archive' \
	'ln' \
	'create_dir' \
	'configure:upgrade' \
	'start' \
	'end:1 update')"
ACTUAL_PACKAGE_FAIL="$(cat "${CALLS_FILE}")"
[ "${ACTUAL_PACKAGE_FAIL}" = "${EXPECTED_PACKAGE_FAIL}" ] ||
	fail "failed package-update default pin did not abort before cleanup/download paths: ${ACTUAL_PACKAGE_FAIL}"

printf '%s\n' 'PASS: upgrade runtime defaults run before service-file replacement failure paths'
