#!/bin/sh
# Verify all distributed lifecycle layers fail closed or retain safe stop defaults when Entware disappears.

set -u

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd) || exit 1
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/service-opt-disappearance.XXXXXX") || exit 1
OPT_ROOT="${TEST_ROOT}/opt"
FUNCTIONS_FILE="${TEST_ROOT}/functions"
CALLS_FILE="${TEST_ROOT}/calls"

# cleanup removes the temporary test directory and its contents.
cleanup() {
	rm -rf "${TEST_ROOT}"
}

# fail reports a test failure with the specified message and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
mkdir -p "${OPT_ROOT}/bin" "${OPT_ROOT}/etc/AdGuardHome" "${OPT_ROOT}/var/run/AdGuardHome" ||
	fail 'could not create simulated Entware mount'
: >"${OPT_ROOT}/etc/opkg.conf" || fail 'could not create simulated Entware configuration'
cat >"${OPT_ROOT}/bin/opkg" <<'EOF' || fail 'could not create simulated opkg command'
#!/bin/sh
[ "${1:-}" = "--version" ]
EOF
chmod 755 "${OPT_ROOT}/bin/opkg" || fail 'could not make simulated opkg executable'

# Exercise the installer's functional Entware probe before and after the mount vanishes.
sed -n '/^entware_available() {$/,/^}$/p' "${ROOT_DIR}/installer" |
	sed "s#/opt#${OPT_ROOT}#g" >"${FUNCTIONS_FILE}" || fail 'could not extract installer Entware probe'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"
entware_available || fail 'installer rejected the available simulated Entware mount'
mv "${OPT_ROOT}" "${OPT_ROOT}.gone" || fail 'could not simulate Entware mount disappearance'
if entware_available; then
	fail 'installer accepted Entware after its mount disappeared'
fi
mv "${OPT_ROOT}.gone" "${OPT_ROOT}" || fail 'could not restore simulated Entware mount'

# Exercise S99AdGuardHome's work-directory gate across the same transition.
sed -n '/^ensure_adguardhome_work_dir_permissions() {$/,/^}$/p' "${ROOT_DIR}/S99AdGuardHome" >"${FUNCTIONS_FILE}" ||
	fail 'could not extract S99 work-directory gate'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"
WORK_DIR="${OPT_ROOT}/etc/AdGuardHome"
PROCS='AdGuardHome'
touch "${WORK_DIR}/AdGuardHome" || fail 'could not create simulated AdGuardHome binary'
chmod 755 "${WORK_DIR}/AdGuardHome" || fail 'could not make simulated AdGuardHome executable'
# logger records the supplied message in the calls file.
logger() { printf '%s\n' "$*" >>"${CALLS_FILE}"; }
# adguardhome_owner_account prints the account that owns AdGuardHome files.
adguardhome_owner_account() { printf '%s\n' root; }
#adguardhome_yaml_ipset_file prints the path to the AdGuardHome YAML IP set configuration file.
adguardhome_yaml_ipset_file() { printf '%s\n' "${WORK_DIR}/ipset.conf"; }
chown() { return 0; }
# chmod_regular_files_600 sets permissions on regular files to 600.
chmod_regular_files_600() { return 0; }
ensure_adguardhome_work_dir_permissions || fail 'S99 rejected the available work directory'
mv "${OPT_ROOT}" "${OPT_ROOT}.gone" || fail 'could not remove Entware during S99 operation'
if ensure_adguardhome_work_dir_permissions; then
	fail 'S99 accepted a vanished AdGuardHome work directory'
fi
grep -q 'Missing AdGuardHome work directory' "${CALLS_FILE}" || fail 'S99 did not report the vanished work directory'
mv "${OPT_ROOT}.gone" "${OPT_ROOT}" || fail 'could not restore Entware after S99 check'

# Exercise rc.func state publication.  Once the mount disappears and cannot be
# recreated, transition publication remains best-effort and leaves no stage.
sed -n '/^service_state_file() {$/,/^service_status_line() {$/p' "${ROOT_DIR}/rc.func.AdGuardHome" | sed '$d' |
	sed "s#/opt#${OPT_ROOT}#g" >"${FUNCTIONS_FILE}" || fail 'could not extract rc state helpers'
(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	PROC='AdGuardHome'
	# service_state_dir_is_private determines whether the service state directory has private permissions.
	service_state_dir_is_private() { return 0; }
	# service_state_file_is_private reports that the service state file is private.
	service_state_file_is_private() { return 0; }
	service_mark_transition starting
	[ -f "${OPT_ROOT}/var/run/AdGuardHome/service-state" ] || fail 'rc helper did not publish initial state'
	mv "${OPT_ROOT}" "${OPT_ROOT}.gone" || fail 'could not remove Entware during rc operation'
	# mkdir simulates a failed directory-creation command.
	mkdir() { return 1; }
	service_mark_transition stopping || fail 'rc helper propagated best-effort state failure'
	[ ! -e "${OPT_ROOT}" ] || fail 'rc helper recreated the unavailable Entware mount'
	[ ! -e "${OPT_ROOT}/var/run/AdGuardHome/service-state.$$" ] || fail 'rc helper left a live stage after mount loss'
	[ ! -e "${OPT_ROOT}.gone/var/run/AdGuardHome/service-state.$$" ] || fail 'rc helper left a stage in the renamed mount'
	mv "${OPT_ROOT}.gone" "${OPT_ROOT}" || fail 'could not restore Entware after rc check'
) || fail 'rc helper mount-disappearance checks failed'

# Exercise AdGuardHome.sh's scoped configuration snapshot.  Stop scope must use
# conservative defaults after the configuration disappears with the mount.
sed -n '/^set_operation_config_defaults() {$/,/^# adguard_install_mode prints/p' "${ROOT_DIR}/AdGuardHome.sh" | sed '$d' >"${FUNCTIONS_FILE}" ||
	fail 'could not extract manager configuration helpers'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"
CONF_FILE="${OPT_ROOT}/etc/AdGuardHome/.config"
DEFAULT_ADGUARD_NETCHECK_HOSTS='example.invalid'
DEFAULT_ADGUARD_NETCHECK_DNS='127.0.0.1'
DEFAULT_ADGUARD_NETCHECK_REQUIRE_HTTP='NO'
DEFAULT_ADGUARD_NETCHECK_TIMEOUT='300'
DEFAULT_ADGUARD_NETCHECK_MODE='wan'
DEFAULT_ADGUARD_PROC_OPTIMIZE='NO'
DEFAULT_ADGUARD_PROC_PROFILE='aggressive'
printf '%s\n' 'ADGUARD_INSTALL_MODE="lan"' 'ADGUARD_DNSMASQ_MODE="enabled"' >"${CONF_FILE}" ||
	fail 'could not create manager configuration'
load_operation_config stop || fail 'manager rejected configuration before mount loss'
[ "${CONFIG_INSTALL_MODE}:${CONFIG_DNSMASQ_MODE}" = 'lan:enabled' ] || fail 'manager did not load initial stop configuration'
mv "${OPT_ROOT}" "${OPT_ROOT}.gone" || fail 'could not remove Entware during manager operation'
load_operation_config stop || fail 'manager could not snapshot safe defaults after mount loss'
[ "${CONFIG_INSTALL_MODE}:${CONFIG_DNSMASQ_MODE}" = 'wan:auto' ] || fail 'manager did not use safe stop defaults after mount loss'

printf '%s\n' 'PASS: distributed lifecycle layers handle Entware mount disappearance'
