#!/bin/sh
# Verify startup acquires the IPSET lock before stopping AdGuardHome and restores it on failure.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
FUNCTION_FILE="${TMPDIR:-/tmp}/start-adguardhome-function.$$"
SERVICE_WAIT_FILE="${TMPDIR:-/tmp}/service-wait-function.$$"
CALLS_FILE="${TMPDIR:-/tmp}/start-adguardhome-calls.$$"

cleanup() {
	rm -f "${FUNCTION_FILE}" "${SERVICE_WAIT_FILE}" "${CALLS_FILE}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

assert_single_function() {
	FUNCTION_NAME="$1"
	FUNCTION_COUNT="$(awk -v signature="${FUNCTION_NAME}() {" '$0 == signature { count++ } END { print count + 0 }' "${SCRIPT_PATH}")" || fail "could not inspect ${FUNCTION_NAME}"
	[ "${FUNCTION_COUNT}" -eq 1 ] || fail "expected one ${FUNCTION_NAME} definition, found ${FUNCTION_COUNT}"
}

# assert_startup_uses_lock_first_setup verifies that startup has one LAN cleanup gate, one WAN-only lock-first setup call, and no legacy IPSET setup call.
assert_startup_uses_lock_first_setup() {
	STARTUP_SETUP_CALLS="$(awk '
		/^start_adguardhome\(\) \{$/ { in_start = 1; next }
		in_start && /^}$/ { exit }
		in_start && /^[[:space:]]*if adguard_lan_mode; then$/ { lan_gate++ }
		in_start && /^[[:space:]]*elif ! IPSet_Setup_For_Start; then$/ { lock_first++ }
		in_start && /^[[:space:]]*if ! IPSet_Setup;/ { legacy++ }
		END { print lan_gate + 0, lock_first + 0, legacy + 0 }
	' "${SCRIPT_PATH}")" || fail 'could not inspect the startup IPSET setup call'
	[ "${STARTUP_SETUP_CALLS}" = '1 1 0' ] || fail "expected one outer LAN cleanup gate, one WAN-only lock-first setup call, and no legacy setup call, found ${STARTUP_SETUP_CALLS}"
}

# assert_optional_ipset_tools_do_not_gate_startup verifies that optional IPSET-only tools are excluded from the manager startup dependency gate.
assert_optional_ipset_tools_do_not_gate_startup() {
	DEPENDENCY_LINE="$(sed -n '/^manager_dependencies_available() {$/,/^}$/p' "${SCRIPT_PATH}" | grep 'for REQUIRED_COMMAND in')"
	case " ${DEPENDENCY_LINE} " in
		*' chmod '* | *' cmp '* | *' cp '* | *' ls '* | *' mv '*)
			fail 'manager startup dependency gate includes optional IPSET-only tools'
			;;
	esac
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

assert_single_function IPSet_Disable_Managed_For_Start_Locked
assert_single_function IPSet_Enabled
assert_single_function IPSet_Dnsmasq_Restart_After_Unlock
assert_single_function IPSet_Lock_Interrupt_Cleanup
assert_single_function IPSet_Start_Restore
assert_single_function IPSet_Start_While_Locked
assert_single_function IPSet_Setup_For_Start
assert_single_function IPSet_Setup_For_Start_Locked
assert_startup_uses_lock_first_setup
assert_optional_ipset_tools_do_not_gate_startup

sed -n '/^agh_timestamp() {$/,/^}$/p; /^agh_log() {$/,/^}$/p; /^adguard_restart_dnsmasq_if_managed() {$/,/^}$/p; /^start_adguardhome() {$/,/^}$/p; /^IPSet_Enabled() {$/,/^}$/p; /^IPSet_Disable_Managed_For_Start_Locked() {$/,/^}$/p; /^IPSet_Dnsmasq_Restart_After_Unlock() {$/,/^}$/p; /^IPSet_Lock_Interrupt_Cleanup() {$/,/^}$/p; /^IPSet_Start_Restore() {$/,/^}$/p; /^IPSet_Start_While_Locked() {$/,/^}$/p; /^IPSet_Setup_For_Start() {$/,/^}$/p; /^IPSet_Setup_For_Start_Locked() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" || fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTION_FILE}" ] || fail 'startup lifecycle functions were not found'
sed -n '/^service_wait() {$/,/^}$/p' "${SCRIPT_PATH}" >"${SERVICE_WAIT_FILE}" || fail "could not read ${SCRIPT_PATH}"
[ -s "${SERVICE_WAIT_FILE}" ] || fail 'service-wait function was not found'

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

# adguard_dnsmasq_managed reports whether dnsmasq is managed by AdGuard Home.
adguard_dnsmasq_managed() {
	return "${DNSMASQ_MANAGED_STATUS:-0}"
}

# conf_value reports whether IPSET configuration is enabled.
conf_value() {
	[ "${IPSET_CONFIG:-YES}" = "NO" ] && printf '%s\n' NO || printf '%s\n' YES
}

# adguard_lan_mode determines whether AdGuard Home is configured for LAN mode.
adguard_lan_mode() {
	[ "${INSTALL_MODE:-wan}" = "lan" ]
}

# adguard_refresh_lan_bind_addresses returns the configured LAN bind-address refresh status.
adguard_refresh_lan_bind_addresses() {
	return "${LAN_BIND_REFRESH_STATUS:-0}"
}

# adguard_ipset_allowed reports whether IPSET integration is allowed outside LAN mode.
adguard_ipset_allowed() {
	! adguard_lan_mode
}

# IPSet_Supported records the IPSET support check and returns its configured status.
IPSet_Supported() {
	printf '%s\n' IPSet_Supported >>"${CALLS_FILE}"
	IPSET_LEGACY_VERSION="${LEGACY_VERSION:-}"
	return "${SUPPORTED_STATUS}"
}

IPSet_Disable_Managed() {
	printf '%s\n' IPSet_Disable_Managed >>"${CALLS_FILE}"
	return "${DISABLE_STATUS}"
}

IPSet_Setup() {
	printf '%s\n' IPSet_Setup >>"${CALLS_FILE}"
	return "${IPSET_STATUS}"
}

IPSet_Lock() {
	printf '%s\n' 'IPSet_Lock acquired' >>"${CALLS_FILE}"
	[ "${LOCK_STATUS}" -eq 0 ] || return "${LOCK_STATUS}"
	if [ "${RUNNING_AFTER_LOCK:-${RUNNING}}" -eq 1 ]; then
		RUNNING="1"
	else
		RUNNING="0"
	fi
	IPSET_TEST_LOCK_HELD="1"
	"$@"
	STATUS="$?"
	IPSET_TEST_LOCK_HELD="0"
	printf '%s\n' 'IPSet_Lock released' >>"${CALLS_FILE}"
	IPSet_Dnsmasq_Restart_After_Unlock
	if [ "${INTERRUPT_AFTER_UNLOCK}" -eq 1 ]; then
		printf '%s\n' 'interrupt after lock release' >>"${CALLS_FILE}"
		[ "${IPSET_START_STOPPED}" -eq 0 ] || fail 'post-lock interrupt found AdGuardHome stopped'
		IPSet_Lock_Interrupt_Cleanup
	fi
	return "${STATUS}"
}

IPSet_Setup_Locked() {
	printf '%s\n' IPSet_Setup_Locked >>"${CALLS_FILE}"
	return "${IPSET_STATUS}"
}

logger() {
	:
}

service() {
	printf '%s\n' "service $1" >>"${CALLS_FILE}"
}

# lower_script simulates stop, start, and restart operations using the configured test statuses.
lower_script() {
	printf '%s\n' "lower_script $1" >>"${CALLS_FILE}"
	case "$1" in
		stop)
			if [ "${INTERRUPT_ON_STOP}" -eq 1 ]; then
				IPSet_Lock_Interrupt_Cleanup
				return 1
			fi
			return "${STOP_STATUS}"
			;;
		start)
			if [ "${IPSET_TEST_LOCK_HELD:-0}" -eq 1 ] && [ "${ADGUARDHOME_SKIP_DNSMASQ_RESTART:-}" != "1" ]; then
				fail 'locked AdGuardHome start did not suppress the dnsmasq restart hook'
			fi
			if [ "${DNSMASQ_UNMANAGED_AFTER_START:-0}" -eq 1 ]; then
				DNSMASQ_MANAGED_STATUS=1
			fi
			return "${START_STATUS}"
			;;
		restart)
			return "${START_STATUS}"
			;;
	esac
	return 0
}

pidof() {
	[ "${RUNNING}" -eq 1 ] && printf '%s\n' 1234
	return 0
}

readlink() {
	[ "$1" = '-f' ] || fail "unexpected readlink arguments: $*"
	printf '/mock/%s\n' "${2##*/}"
}

ln() {
	fail "database-link setup escaped the test double: $*"
}

# Stop successful starts before the function enters its router-only health-check path.
service_wait() {
	SERVICE_WAIT_CALLED="1"
	return 1
}

run_test() {
	DESCRIPTION="$1"
	RUNNING="$2"
	SUPPORTED_STATUS="$3"
	LOCK_STATUS="$4"
	STOP_STATUS="$5"
	IPSET_STATUS="$6"
	START_STATUS="$7"
	EXPECTED_STATUS="$8"
	EXPECTED="$9"
	SERVICE_WAIT_CALLED="0"
	: >"${CALLS_FILE}"

	if start_adguardhome; then
		ACTUAL_STATUS=0
	else
		ACTUAL_STATUS=$?
	fi
	[ "${ACTUAL_STATUS}" -eq "${EXPECTED_STATUS}" ] || fail "${DESCRIPTION}: returned ${ACTUAL_STATUS}, expected ${EXPECTED_STATUS}"

	ACTUAL="$(cat "${CALLS_FILE}")"
	[ "${ACTUAL}" = "${EXPECTED}" ] || fail "${DESCRIPTION}: unexpected lifecycle: ${ACTUAL}"
}

run_service_wait_terminal_test() {
	: >"${CALLS_FILE}"
	(
		# shellcheck disable=SC1090
		. "${SERVICE_WAIT_FILE}"
		timezone() { :; }
		nvram() { printf '%s\n' 1; }
		terminal_failure() {
			printf '%s\n' called >>"${CALLS_FILE}"
			SERVICE_WAIT_TERMINAL_FAILURE="1"
			return 1
		}
		service_wait terminal_failure 30
	)
	STATUS="$?"
	[ "${STATUS}" -eq 1 ] || fail "service_wait returned ${STATUS}, expected terminal failure"
	[ "$(wc -l <"${CALLS_FILE}")" -eq 1 ] || fail 'service_wait retried a terminal failure'
}

run_interrupt_cleanup_test() {
	DESCRIPTION="$1"
	START_STATUS="$2"
	IPSET_START_STOPPED="1"
	: >"${CALLS_FILE}"

	IPSet_Lock_Interrupt_Cleanup
	[ "${IPSET_START_STOPPED}" -eq 0 ] || fail "${DESCRIPTION}: left restoration armed"
	ACTUAL="$(cat "${CALLS_FILE}")"
	[ "${ACTUAL}" = 'lower_script start' ] || fail "${DESCRIPTION}: unexpected lifecycle: ${ACTUAL}"
}

PROCS=AdGuardHome
NAME=AdGuardHome
WORK_DIR=/tmp/adguardhome-test
INTERRUPT_ON_STOP=0
INTERRUPT_AFTER_UNLOCK=0
DISABLE_STATUS=0
DNSMASQ_MANAGED_STATUS=0
DNSMASQ_UNMANAGED_AFTER_START=0

run_service_wait_terminal_test

INSTALL_MODE=lan
LAN_BIND_REFRESH_STATUS=1
run_test 'LAN mode preserves service startup when dynamic bind refresh fails' 0 0 0 0 0 0 1 'IPSet_Disable_Managed
lower_script start'
[ "${SERVICE_WAIT_TERMINAL_FAILURE}" -eq 0 ] || fail 'LAN bind refresh failure was incorrectly reported as terminal service failure'
[ "${SERVICE_WAIT_CALLED}" -eq 1 ] || fail 'LAN bind refresh failure prevented the independent service health check'
LAN_BIND_REFRESH_STATUS=0
run_test 'LAN mode cleans managed IPSET before startup without setup helper' 0 0 0 0 0 0 1 'IPSet_Disable_Managed
lower_script start'
[ "${SERVICE_WAIT_TERMINAL_FAILURE}" -eq 0 ] || fail 'LAN startup cleanup was incorrectly marked terminal'
[ "${SERVICE_WAIT_CALLED}" -eq 1 ] || fail 'LAN startup cleanup did not continue to the health check'
DISABLE_STATUS=1
: >"${CALLS_FILE}"
if IPSet_Setup_For_Start; then
	fail 'LAN setup helper treated failed cleanup as non-fatal'
fi
[ "$(cat "${CALLS_FILE}")" = 'IPSet_Disable_Managed' ] || fail 'LAN setup helper did not attempt managed cleanup'
run_test 'LAN mode aborts when managed IPSET cleanup fails without setup helper' 0 0 0 0 0 0 1 'IPSet_Disable_Managed'
[ "${SERVICE_WAIT_TERMINAL_FAILURE}" -eq 1 ] || fail 'LAN failed startup cleanup was not marked terminal'
[ "${SERVICE_WAIT_CALLED}" -eq 0 ] || fail 'LAN failed startup cleanup continued to the health check'
DISABLE_STATUS=0
INSTALL_MODE=wan

run_test 'setup failure while stopped continues startup' 0 0 0 0 1 0 1 'IPSet_Supported
IPSet_Lock acquired
IPSet_Setup_Locked
IPSet_Disable_Managed
IPSet_Lock released
lower_script start'
[ "${SERVICE_WAIT_TERMINAL_FAILURE}" -eq 0 ] || fail 'stopped IPSET setup failure was incorrectly marked terminal'
[ "${SERVICE_WAIT_CALLED}" -eq 1 ] || fail 'stopped IPSET setup failure did not continue to the health check'
DISABLE_STATUS=1
run_test 'setup failure aborts when stale mappings cannot be disabled' 0 0 0 0 1 0 1 'IPSet_Supported
IPSet_Lock acquired
IPSet_Setup_Locked
IPSet_Disable_Managed
IPSet_Lock released'
[ "${SERVICE_WAIT_TERMINAL_FAILURE}" -eq 1 ] || fail 'unsafe disable failure was not marked terminal'
[ "${SERVICE_WAIT_CALLED}" -eq 0 ] || fail 'unsafe disable failure reached the health check'
DISABLE_STATUS=0
RUNNING_AFTER_LOCK=1
run_test 'service started while waiting for lock is stopped before setup' 0 0 0 0 0 0 1 'IPSet_Supported
IPSet_Lock acquired
lower_script stop
IPSet_Setup_Locked
lower_script start
IPSet_Lock released
service restart_dnsmasq'
unset RUNNING_AFTER_LOCK
run_test 'setup failure restores running service and continues startup' 1 0 0 0 1 0 1 'IPSet_Supported
IPSet_Lock acquired
lower_script stop
IPSet_Setup_Locked
IPSet_Disable_Managed
lower_script start
IPSet_Lock released
service restart_dnsmasq'
[ "${SERVICE_WAIT_TERMINAL_FAILURE}" -eq 0 ] || fail 'restored IPSET setup failure was incorrectly marked terminal'
[ "${SERVICE_WAIT_CALLED}" -eq 1 ] || fail 'restored IPSET setup failure did not continue to the health check'
run_test 'failed restoration remains an error' 1 0 0 0 1 1 1 'IPSet_Supported
IPSet_Lock acquired
lower_script stop
IPSet_Setup_Locked
IPSet_Disable_Managed
lower_script start
IPSet_Lock released
service restart_dnsmasq
lower_script restart'
run_test 'lock contention aborts startup rather than retaining stale mappings' 1 0 7 0 0 0 1 'IPSet_Supported
IPSet_Lock acquired'
[ "${SERVICE_WAIT_TERMINAL_FAILURE}" -eq 1 ] || fail 'unsafe lock failure was not marked terminal'
[ "${SERVICE_WAIT_CALLED}" -eq 0 ] || fail 'unsafe lock failure reached the health check'
run_test 'IPSET stop failure aborts startup rather than retaining stale mappings' 1 0 0 1 0 0 1 'IPSet_Supported
IPSet_Lock acquired
lower_script stop
IPSet_Lock released'
[ "${SERVICE_WAIT_TERMINAL_FAILURE}" -eq 1 ] || fail 'unsafe stop failure was not marked terminal'
[ "${SERVICE_WAIT_CALLED}" -eq 0 ] || fail 'unsafe stop failure reached the health check'
INTERRUPT_ON_STOP=1
run_test 'interrupt during stop restores running service and aborts startup' 1 0 0 0 0 0 1 'IPSet_Supported
IPSet_Lock acquired
lower_script stop
lower_script start
IPSet_Lock released
service restart_dnsmasq'
[ "${SERVICE_WAIT_TERMINAL_FAILURE}" -eq 1 ] || fail 'interrupted setup was not marked terminal'
[ "${SERVICE_WAIT_CALLED}" -eq 0 ] || fail 'interrupted setup reached the health check'
INTERRUPT_ON_STOP=0
run_test 'unsupported integration restarts a running service' 1 1 0 0 0 0 1 'IPSet_Supported
lower_script restart'
run_test 'unsupported integration starts a stopped service' 0 1 0 0 0 0 1 'IPSet_Supported
lower_script start'
run_test 'lower-script restart failure aborts before health check' 1 1 0 0 0 7 7 'IPSet_Supported
lower_script restart'
[ "${SERVICE_WAIT_TERMINAL_FAILURE}" -eq 1 ] || fail 'lower-script restart failure was not marked terminal'
[ "${SERVICE_WAIT_CALLED}" -eq 0 ] || fail 'lower-script restart failure reached the health check'
run_test 'lower-script start failure aborts before health check' 0 1 0 0 0 8 8 'IPSet_Supported
lower_script start'
[ "${SERVICE_WAIT_TERMINAL_FAILURE}" -eq 1 ] || fail 'lower-script start failure was not marked terminal'
[ "${SERVICE_WAIT_CALLED}" -eq 0 ] || fail 'lower-script start failure reached the health check'
LEGACY_VERSION=1
run_test 'legacy integration is disabled before restarting a running service' 1 1 0 0 0 0 1 'IPSet_Supported
IPSet_Lock acquired
lower_script stop
IPSet_Disable_Managed
lower_script start
IPSet_Lock released
service restart_dnsmasq'
run_test 'legacy integration is disabled before starting a stopped service' 0 1 0 0 0 0 1 'IPSet_Supported
IPSet_Lock acquired
IPSet_Disable_Managed
IPSet_Lock released
lower_script start'
LEGACY_VERSION=""
IPSET_CONFIG=NO
run_test 'disabled integration removes managed settings before startup' 0 0 0 0 0 0 1 'IPSet_Lock acquired
IPSet_Disable_Managed
IPSet_Lock released
lower_script start'
IPSET_CONFIG=YES

run_interrupt_cleanup_test 'interrupt restores stopped service' 0
run_interrupt_cleanup_test 'failed interrupt restoration is not retried' 1

run_test 'successful setup defers dnsmasq restart until after unlock' 1 0 0 0 0 0 1 'IPSet_Supported
IPSet_Lock acquired
lower_script stop
IPSet_Setup_Locked
lower_script start
IPSet_Lock released
service restart_dnsmasq'
DNSMASQ_UNMANAGED_AFTER_START=1
run_test 'deferred restart preserves pre-stop dnsmasq management decision' 1 0 0 0 0 0 1 'IPSet_Supported
IPSet_Lock acquired
lower_script stop
IPSet_Setup_Locked
lower_script start
IPSet_Lock released
service restart_dnsmasq'
DNSMASQ_UNMANAGED_AFTER_START=0
ADGUARDHOME_SKIP_DNSMASQ_RESTART=1
run_test 'deferred restart honors caller dnsmasq restart suppression' 1 0 0 0 0 0 1 'IPSet_Supported
IPSet_Lock acquired
lower_script stop
IPSet_Setup_Locked
lower_script start
IPSet_Lock released'
unset ADGUARDHOME_SKIP_DNSMASQ_RESTART
DNSMASQ_MANAGED_STATUS=0
[ -z "${ADGUARDHOME_SKIP_DNSMASQ_RESTART:-}" ] || fail 'locked start left the dnsmasq restart guard set'
[ "${IPSET_DNSMASQ_RESTART_PENDING:-0}" -eq 0 ] || fail 'locked start left the dnsmasq restart pending'
INTERRUPT_AFTER_UNLOCK=1
run_test 'post-lock interrupt cannot strand the service' 1 0 0 0 0 0 1 'IPSet_Supported
IPSet_Lock acquired
lower_script stop
IPSet_Setup_Locked
lower_script start
IPSet_Lock released
service restart_dnsmasq
interrupt after lock release'
INTERRUPT_AFTER_UNLOCK=0
run_test 'failed locked IPSET restart falls through to normal restart' 1 0 0 0 0 1 1 'IPSet_Supported
IPSet_Lock acquired
lower_script stop
IPSet_Setup_Locked
lower_script start
IPSet_Lock released
service restart_dnsmasq
lower_script restart'

printf '%s\n' 'PASS: startup treats IPSET integration as optional and preserves lifecycle recovery'
