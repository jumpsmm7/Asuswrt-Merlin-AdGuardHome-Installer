#!/bin/sh
# Verify a running service is restarted when post-replacement setup aborts.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-post-replace-restart.$$"
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
sed -n '/^inst_AdGuardHome() {$/,/^set_timezone() {$/p' "${SCRIPT_PATH}" | sed '$d' >>"${FUNCTIONS_FILE}" ||
	fail 'could not extract installer function'
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
	ADDON_DIR="${TMP_ROOT}/addon"
	AGH_FILE="${TMP_ROOT}/target/AdGuardHome"
	BASE_DIR="${TMP_ROOT}/base"
	RURL='https://example.invalid'
	SCRIPT_LOC="${TMP_ROOT}/missing-installer"
	TARG_DIR="${TMP_ROOT}/target"
	URL_ARCH='https://example.invalid'
	INFO='Info:'
	ERROR='Error:'
	DOWNLOAD_COUNT=0
	RUNNING=1

	adguard_install_abort_trap_disable_preserve_defer() { :; }
	adguard_remote_archive() { printf '%s\n' 'AdGuardHome_test.tar.gz'; }
	adguard_remote_md5() { :; }
	adguard_remote_sha256() { :; }
	adguard_remote_url() { printf '%s\n' 'https://example.invalid/AdGuardHome_test.tar.gz'; }
	ensure_sha256sum_tool() { :; }
	download_file() {
		DOWNLOAD_COUNT="$((DOWNLOAD_COUNT + 1))"
		[ "${DOWNLOAD_COUNT}" -ne 3 ]
	}
	md5_is_valid() { return 1; }
	sha256_is_valid() { return 1; }
	agh_process_count() { printf '%s\n' "${RUNNING}"; }
	install_adguard_archive() {
		RUNNING=0
		return 0
	}
	agh_is_running() { [ "${RUNNING}" -eq 1 ]; }
	agh_start() {
		printf '%s\n' 'start' >>"${CALLS_FILE}"
		RUNNING=1
	}
	create_dir() { mkdir -p "$1"; }
	cleanup_legacy_firewall() { :; }
	nvram() { :; }
	rm() { :; }
	ln() { :; }
	end_op_message() {
		printf '%s\n' "end:$*" >>"${CALLS_FILE}"
	}
	PTXT() { :; }
	ptxt_phase() { PTXT "$1"; }
	ptxt_step() { PTXT "$1"; }
	ptxt_ok() { PTXT "$1"; }
	ptxt_warn() { PTXT "$1"; }
	ptxt_fail() { PTXT "$1"; }

	if inst_AdGuardHome update release; then
		fail 'installer reported success after a service-file download failed'
	fi
) || fail 'post-replacement restart regression subprocess failed'

EXPECTED="$(printf '%s\n' 'start' 'end:1 update')"
ACTUAL="$(cat "${CALLS_FILE}")"
[ "${ACTUAL}" = "${EXPECTED}" ] || fail "installer did not restart the stopped service before aborting: ${ACTUAL}"

printf '%s\n' 'PASS: post-replacement failure restarts the previously running service'
