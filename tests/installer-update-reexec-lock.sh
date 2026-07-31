#!/bin/sh
# Verify installer update re-exec preserves every NVRAM transaction lock mode.

set -u

INSTALLER_PATH="${1:-installer}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/installer-update-reexec-lock.XXXXXX")" || exit 1
FUNCTIONS_FILE="${TEST_ROOT}/functions"

# fail prints a failure message to standard error and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}
# cleanup removes the temporary test directory and its contents.
cleanup() { rm -rf "${TEST_ROOT}"; }
trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

sed -n '/^nvram_transaction_recover_startup() {$/,/^installer_lan_domain_set() {$/p' "${INSTALLER_PATH}" |
	sed '/^installer_lan_domain_set() {$/d' >"${FUNCTIONS_FILE}" || fail 'could not extract transaction lock helpers'
sed -n '/^installer_update_reexec() {$/,/^install_wan_event_scripts() {$/p' "${INSTALLER_PATH}" |
	sed '$d' >>"${FUNCTIONS_FILE}" || fail 'could not extract installer re-exec helper'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

BASE_DIR="${TEST_ROOT}/base"
mkdir -p "${BASE_DIR}" || fail 'could not create installer base directory'
# file_md5 outputs the placeholder MD5 checksum `new`.
file_md5() { printf '%s\n' new; }
ptxt_ok() { :; }

for lock_mode in flock symlink mkdir; do
	case "${lock_mode}" in
		flock)
			[ -x /usr/bin/flock ] || continue
			;;
		symlink) # nvram_transaction_lock_flock_supports_fd determines whether file-descriptor-based flock locking is available.
			nvram_transaction_lock_flock_supports_fd() { return 1; } ;;
		mkdir)
			# nvram_transaction_lock_flock_supports_fd determines whether file-descriptor-based flock locking is available.
			nvram_transaction_lock_flock_supports_fd() { return 1; }
			# nvram_transaction_lock_symlink_acquire reports that symlink lock acquisition is unavailable.
			nvram_transaction_lock_symlink_acquire() { return 2; }
			;;
	esac
	(
		nvram_transaction_lock_acquire || fail "could not acquire ${lock_mode} transaction lock"
		[ "${NVRAM_TRANSACTION_LOCK_MODE:-}" = "${lock_mode}" ] || fail "did not acquire ${lock_mode} transaction lock"
		LOCK_OWNER="$(nvram_transaction_lock_owner_current)" || fail "could not determine ${lock_mode} transaction lock identity"
		export LOCK_OWNER
		TARG_DIR="${TEST_ROOT}/${lock_mode}"
		BRANCH=testing
		mkdir -p "${TARG_DIR}" || fail "could not create ${lock_mode} re-exec target"
		mkdir -p "${BASE_DIR}/.AdGuardHome.nvram/dns-preparation" || fail "could not create ${lock_mode} live DNS snapshot"
		: >"${BASE_DIR}/.AdGuardHome.nvram/dns-preparation/dirty" || fail "could not mark ${lock_mode} DNS snapshot dirty"
		cat >"${TARG_DIR}/installer" <<EOF_TARGET
#!/bin/sh
[ "\${AI_REEXECED_INSTALLER:-}" = "1" ] || exit 1
[ "\${NVRAM_TRANSACTION_LOCK_MODE:-}" = "${lock_mode}" ] || exit 1
. "${FUNCTIONS_FILE}" || exit 1
BASE_DIR="${BASE_DIR}"
nvram_transaction_lock_owner_current() { printf '%s\n' "\${LOCK_OWNER}"; }
nvram_transaction_recover_pending() { : >"${TEST_ROOT}/${lock_mode}.recovered"; return 1; }
nvram_transaction_recover_startup || exit 1
[ ! -e "${TEST_ROOT}/${lock_mode}.recovered" ] || exit 1
[ -f "${BASE_DIR}/.AdGuardHome.nvram/dns-preparation/dirty" ] || exit 1
nvram_transaction_lock_owned || exit 1
case "${lock_mode}" in
	flock) [ "\$(readlink /proc/\$\$/fd/8 2>/dev/null)" = "${BASE_DIR}/.AdGuardHome.nvram.lock" ] || exit 1 ;;
	symlink) [ "\$(readlink "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink" 2>/dev/null)" = "\${LOCK_OWNER}" ] || exit 1 ;;
	mkdir) [ "\$(cat "${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid" 2>/dev/null)" = "\${LOCK_OWNER}" ] || exit 1 ;;
esac
printf '%s\n' preserved >"${TEST_ROOT}/${lock_mode}.result"
EOF_TARGET
		chmod 755 "${TARG_DIR}/installer" || fail "could not make ${lock_mode} re-exec target executable"
		installer_update_reexec update old
		exit 1
	) || fail "installer re-exec did not preserve ${lock_mode} transaction lock"
	[ "$(cat "${TEST_ROOT}/${lock_mode}.result" 2>/dev/null)" = preserved ] || fail "${lock_mode} re-exec target did not run"
	rm -rf "${BASE_DIR}/.AdGuardHome.nvram.lock.d"
	rm -f "${BASE_DIR}/.AdGuardHome.nvram.lock.symlink"
	rm -rf "${BASE_DIR}/.AdGuardHome.nvram/dns-preparation"
done

printf '%s\n' 'PASS: installer update re-exec preserves live NVRAM transactions and locks'
