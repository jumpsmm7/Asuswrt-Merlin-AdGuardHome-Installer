#!/bin/sh
# Verify real monitor stop helpers reject incomplete daemon and DNS recovery.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
CASE_FILTER="${MONITOR_STOP_CASE:-all}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/monitor-stop-postconditions.XXXXXX")" || exit 1
FUNCTIONS_FILE="${TEST_ROOT}/functions"
CALLS_FILE="${TEST_ROOT}/calls"

# cleanup removes only the fixture's exclusive directory.
cleanup() { rm -rf "${TEST_ROOT}"; }
# fail reports a regression and exits unsuccessfully.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}
trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

sed -n '/^start_monitor() {$/,/^}$/p; /^post_stop_[a-z_]*() {$/,/^}$/p; /^monotonic_seconds() {$/,/^}$/p; /^stop_adguardhome() {$/,/^}$/p; /^stop_all_monitors() {$/,/^}$/p; /^stop_monitor() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" || fail 'could not extract monitor shutdown helpers'
sed -n '/^dnsmasq_instances_ready() {$/,/^}$/p; /^dns_socket_snapshot() {$/,/^}$/p' "${SCRIPT_PATH%/*}/S99AdGuardHome" >>"${FUNCTIONS_FILE}" 2>/dev/null ||
	sed -n '/^dnsmasq_instances_ready() {$/,/^}$/p; /^dns_socket_snapshot() {$/,/^}$/p' S99AdGuardHome >>"${FUNCTIONS_FILE}" || fail 'could not extract per-instance DNS verification'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

PROCS=AdGuardHome
WORK_DIR="${TEST_ROOT}/work"
DNS_HANDOFF_DIR="${TEST_ROOT}/handoff"
DNS_HANDOFF_FILE="${DNS_HANDOFF_DIR}/active"
ADGUARDHOME_BINARY=/bin/sh
ADGUARDHOME_DNSMASQ_READY_TIMEOUT=5
CONFIG_DNSMASQ_MODE=enabled
MON_PID=12345

# agh_log records diagnostics for failure assertions.
agh_log() { printf '%s\n' "$*" >>"${CALLS_FILE}"; }
# adguard_monitor_pids supplies both matching monitors when requested.
adguard_monitor_pids() {
	[ "${MONITORS_PRESENT}" = 1 ] && printf '%s\n' 12345 12346
	return 0
}
# monitor_process_matches reports the fixture's monitor identities until signalled.
monitor_process_matches() {
	case "$1" in 12345) [ "${MONITOR_ONE_ACTIVE}" = 1 ] ;; 12346) [ "${MONITOR_TWO_ACTIVE}" = 1 ] ;; *) return 1 ;; esac
}
# kill simulates a graceful monitor disappearing without communicating its stop status.
kill() {
	printf '%s\n' "signal $*" >>"${CALLS_FILE}"
	case "$*" in
		'-s USR1 12345') MONITOR_ONE_ACTIVE=0 ;;
		'-s USR1 12346') MONITOR_TWO_ACTIVE=0 ;;
	esac
	[ "${DNS_VANISHES_ON_SIGNAL}" = 0 ] || DNSMASQ_RUNNING=0
	if [ "${SDN_VANISHES_ON_SIGNAL}" = 1 ]; then
		SDN_RUNNING=0 TOPOLOGY_PRESENT=0
	fi
	return 0
}
# pidof supplies daemon and dnsmasq liveness for the production postconditions.
pidof() {
	case "$1" in
		AdGuardHome) [ "${DAEMON_RUNNING}" = 1 ] && printf '%s\n' 123 ;;
		dnsmasq)
			[ "${DNSMASQ_RUNNING}" = 1 ] && printf '%s\n' 88
			[ "${SDN_RUNNING}" = 1 ] && printf '%s\n' 89
			;;
	esac
	return 0
}
# adguard_dnsmasq_running follows the simulated native daemon state.
adguard_dnsmasq_running() { [ "${DNSMASQ_RUNNING}" = 1 ]; }
# adguard_dnsmasq_managed models LAN's current transient-process dependency.
adguard_dnsmasq_managed() { [ "${CONFIG_DNSMASQ_MODE}" != disabled ] && [ "${DNSMASQ_RUNNING}" = 1 ]; }
# dnsmasq_handoff_configs returns the required topology before it can disappear.
dnsmasq_handoff_configs() {
	printf '%s\n' "${ADGUARDHOME_DNSMASQ_CONFIGS:-}"
	printf '%s\n' /etc/dnsmasq.conf
	[ "${MAIN_ONLY}" = 1 ] || [ "${TOPOLOGY_PRESENT}" = 0 ] || printf '%s\n' /etc/dnsmasq-1.conf
	return 0
}
# dnsmasq_managed_instances maps the surviving firmware instances to their configs.
dnsmasq_managed_instances() {
	if [ "${DNSMASQ_RUNNING}" = 1 ]; then
		[ "${DNS_FOREIGN}" = 1 ] && printf '%s\n' '88 10 /opt/etc/unmanaged.conf' || printf '%s\n' '88 10 /etc/dnsmasq.conf'
	fi
	[ "${SDN_RUNNING}" = 1 ] && printf '%s\n' '89 11 /etc/dnsmasq-1.conf'
	return 0
}
# netstat emits independent main/SDN listener owners.
netstat() {
	if [ "${DNSMASQ_RUNNING}" = 1 ]; then
		printf '%s\n' 'tcp 0 0 192.168.50.1:53 0.0.0.0:* LISTEN 88/dnsmasq' 'udp 0 0 192.168.50.1:53 0.0.0.0:* 88/dnsmasq'
	fi
	if [ "${SDN_RUNNING}" = 1 ]; then
		printf '%s\n' 'tcp 0 0 192.168.51.1:53 0.0.0.0:* LISTEN 89/dnsmasq' 'udp 0 0 192.168.51.1:53 0.0.0.0:* 89/dnsmasq'
	fi
}
# nvram returns the fixture's main LAN address.
nvram() { [ "${2:-}" != lan_ipaddr ] || printf '%s\n' 192.168.50.1; }
# nslookup follows local DNS readiness and does not need Internet access.
nslookup() { [ "${DNSMASQ_RUNNING}" = 1 ]; }
# resolv_conf_uses_rom reports the native routing exception.
resolv_conf_uses_rom() { [ "${RESOLVER_ROM}" = 1 ]; }
# resolv_conf_is_tmp_mount exposes the optional cache bind mount.
resolv_conf_is_tmp_mount() { [ "${RESOLVER_MOUNTED}" = 1 ]; }
# dnsmasq_resolv_conf_cleanup simulates successful or failed resolver unmounts.
dnsmasq_resolv_conf_cleanup() {
	[ "${UNMOUNT_FAILURE}" = 0 ] || return 1
	RESOLVER_MOUNTED=0
}
# adguard_local_cache_service_active exposes an active manager lock during cleanup.
adguard_local_cache_service_active() { return 0; }
# lower_script stops the daemon unless a genuine stop failure is selected.
lower_script() {
	[ "${PROCESS_STOP_FAILURE}" = 0 ] || return 1
	DAEMON_RUNNING=0
}
# service restarts required native DNS unless recovery is deliberately broken.
service() {
	printf '%s\n' "service $*" >>"${CALLS_FILE}"
	[ "${DNS_RECOVERY_FAILURE}" = 0 ] || return 1
	DNSMASQ_RUNNING=1
	[ "${SDN_RECOVERY_FAILURE}" != 0 ] || SDN_RUNNING=1
}
# remove_database_link keeps optional database cleanup outside this fixture.
remove_database_link() { :; }
# sleep skips bounded retry delays while retaining the real loop conditions.
sleep() { :; }
# adguardhome_run invokes the real direct stop to test the parent's recovery path.
adguardhome_run() {
	[ "$1" = stop_adguardhome ] || return 0
	RECOVERY_CALLS="$((RECOVERY_CALLS + 1))"
	stop_adguardhome
}

# reset_case starts two already-graceful monitors and healthy native DNS.
reset_case() {
	: >"${CALLS_FILE}"
	rm -rf "${DNS_HANDOFF_DIR}"
	MONITORS_PRESENT=1 MONITOR_ONE_ACTIVE=1 MONITOR_TWO_ACTIVE=1
	DAEMON_RUNNING=0 DNSMASQ_RUNNING=1 SDN_RUNNING=1
	RESOLVER_ROM=0 RESOLVER_MOUNTED=0 UNMOUNT_FAILURE=0
	PROCESS_STOP_FAILURE=0 DNS_RECOVERY_FAILURE=0 SDN_RECOVERY_FAILURE=0
	DNS_VANISHES_ON_SIGNAL=0 SDN_VANISHES_ON_SIGNAL=0 DNS_FOREIGN=0 RECOVERY_CALLS=0
	MAIN_ONLY=0 TOPOLOGY_PRESENT=1
	CONFIG_DNSMASQ_MODE=enabled
	unset STOP_DNSMASQ_REQUIRED STOP_DNSMASQ_CONFIGS ADGUARDHOME_DNSMASQ_CONFIGS
}

# run_case exercises one independent incomplete shutdown condition.
run_case() {
	case_name="$1"
	[ "${CASE_FILTER}" = all ] || [ "${CASE_FILTER}" = "${case_name}" ] || return 0
	reset_case
	case "${case_name}" in
		graceful-daemon) DAEMON_RUNNING=1 PROCESS_STOP_FAILURE=1 ;;
		graceful-resolver) RESOLVER_MOUNTED=1 UNMOUNT_FAILURE=1 ;;
		graceful-handoff)
			mkdir "${DNS_HANDOFF_DIR}"
			: >"${DNS_HANDOFF_FILE}"
			;;
		graceful-main-dns) DNS_VANISHES_ON_SIGNAL=1 DNS_RECOVERY_FAILURE=1 ;;
		graceful-sdn-dns) SDN_RUNNING=0 SDN_RECOVERY_FAILURE=1 ;;
		graceful-sdn-vanished) SDN_VANISHES_ON_SIGNAL=1 SDN_RECOVERY_FAILURE=1 ;;
		graceful-sdn-remembered) MAIN_ONLY=1 SDN_RUNNING=0 SDN_RECOVERY_FAILURE=1 ADGUARDHOME_DNSMASQ_CONFIGS=/etc/dnsmasq-1.conf ;;
		graceful-foreign-dns) DNS_FOREIGN=1 MAIN_ONLY=1 SDN_RUNNING=0 ;;
		recovered-daemon) DAEMON_RUNNING=1 ;;
		healthy | unmanaged | missing-monitors | repeated-stop) ;;
		*) fail "unknown fixture ${case_name}" ;;
	esac
	case "${case_name}" in
		unmanaged) CONFIG_DNSMASQ_MODE=disabled DNSMASQ_RUNNING=0 SDN_RUNNING=0 ;;
		missing-monitors) MONITORS_PRESENT=0 ;;
	esac
	case "${case_name}" in
		graceful-*)
			if stop_all_monitors; then fail "${case_name} reported successful shutdown"; fi
			[ "${RECOVERY_CALLS}" -eq 1 ] || fail "${case_name} did not attempt exactly one final recovery"
			;;
		*)
			stop_all_monitors || fail "${case_name} failed a recoverable shutdown"
			case "${case_name}" in
				recovered-daemon | missing-monitors) [ "${RECOVERY_CALLS}" -eq 1 ] || fail "${case_name} did not recover once" ;;
				healthy | unmanaged | repeated-stop) [ "${RECOVERY_CALLS}" -eq 0 ] || fail "${case_name} repeated healthy recovery" ;;
			esac
			[ "${case_name}" != repeated-stop ] || stop_all_monitors || fail 'repeated stop failed'
			;;
	esac
	[ "${MONITOR_ONE_ACTIVE}:${MONITOR_TWO_ACTIVE}" = 0:0 ] || [ "${MONITORS_PRESENT}" = 0 ] || fail "${case_name} left another monitor active"
	if [ "${case_name}" = unmanaged ]; then
		! grep -q '^service restart_dnsmasq$' "${CALLS_FILE}" || fail 'unmanaged LAN stop restarted native DNS'
	fi
}

for stop_case in graceful-daemon graceful-resolver graceful-handoff graceful-main-dns graceful-sdn-dns graceful-sdn-vanished graceful-sdn-remembered graceful-foreign-dns recovered-daemon healthy unmanaged missing-monitors repeated-stop; do
	run_case "${stop_case}"
done

# /jffs retains the manager after /opt and its upper helpers disappear.  Verify
# healthy native DNS using real proc/config parsing with isolated process files.
for manager_case in manager-only-healthy manager-only-sdn-failure; do
	[ "${CASE_FILTER}" = all ] || [ "${CASE_FILTER}" = "${manager_case}" ] || continue
	(
		reset_case
		unset -f dnsmasq_instances_ready dnsmasq_handoff_configs dnsmasq_managed_instances
		sed -n '/^post_stop_[a-z_]*() {$/,/^}$/p' "${SCRIPT_PATH}" |
			sed "s|/proc/|${TEST_ROOT}/proc/|g; s|/etc/dnsmasq|${TEST_ROOT}/etc/dnsmasq|g" >"${TEST_ROOT}/manager-only"
		# shellcheck disable=SC1090,SC1091
		. "${TEST_ROOT}/manager-only"
		rm -rf "${TEST_ROOT:?}/etc" "${TEST_ROOT:?}/proc"
		mkdir -p "${TEST_ROOT}/etc" "${TEST_ROOT}/proc/88" "${TEST_ROOT}/proc/89"
		: >"${TEST_ROOT}/etc/dnsmasq.conf"
		: >"${TEST_ROOT}/etc/dnsmasq-1.conf"
		for native_pid in 88 89; do
			ln -s /usr/sbin/dnsmasq "${TEST_ROOT}/proc/${native_pid}/exe"
			printf '%s\n' dnsmasq >"${TEST_ROOT}/proc/${native_pid}/comm"
			case "${native_pid}" in 88) native_config="${TEST_ROOT}/etc/dnsmasq.conf" ;; 89) native_config="${TEST_ROOT}/etc/dnsmasq-1.conf" ;; esac
			printf '%s\000%s\000%s\000' /usr/sbin/dnsmasq -C "${native_config}" >"${TEST_ROOT}/proc/${native_pid}/cmdline"
		done
		# proc_process_start_time supplies stable identities for the fake processes.
		proc_process_start_time() { printf '%s\n' 10; }
		# nvram advertises the capability needed for manager-only SDN enumeration.
		nvram() { case "${2:-}" in rc_support) printf '%s\n' mtlancfg ;; lan_ipaddr) printf '%s\n' 192.168.50.1 ;; esac }
		# sdn_bridge_for_index identifies the active isolated SDN config.
		sdn_bridge_for_index() { [ "$1" != 1 ] || printf '%s\n' br1; }
		if [ "${manager_case}" = manager-only-sdn-failure ]; then
			SDN_RUNNING=0 SDN_RECOVERY_FAILURE=1
			if stop_all_monitors; then fail 'manager-only stop ignored missing SDN DNS'; fi
		else
			stop_all_monitors || fail 'healthy manager-only main/SDN stop failed after /opt disappearance'
			[ "${RECOVERY_CALLS}" -eq 0 ] || fail 'healthy manager-only DNS was unnecessarily restarted'
		fi
	) || exit 1
done

# Both real monitor exit paths must return the direct stop failure.  Inject the
# stop request before the first state check or during the executable check.
for monitor_phase in early late; do
	[ "${CASE_FILTER}" = all ] || [ "${CASE_FILTER}" = "monitor-${monitor_phase}" ] || continue
	(
		reset_case
		DAEMON_RUNNING=1 PROCESS_STOP_FAILURE=1
		if [ "${monitor_phase}" = late ]; then
			# Deliver the asynchronous state transition just before dispatch,
			# retaining the production late shutdown branch verbatim.
			sed -n '/^start_monitor() {$/,/^}$/p' "${SCRIPT_PATH}" |
				sed '/^[[:space:]]*case ${MONITOR_STATE} in$/i\
		MONITOR_STATE="stop"' >"${TEST_ROOT}/late-monitor"
			# shellcheck disable=SC1090,SC1091
			. "${TEST_ROOT}/late-monitor"
		fi
		# adguard_local_cache_sync delivers an early stop request.
		adguard_local_cache_sync() {
			[ "${monitor_phase}" != early ] || MONITOR_STATE=stop
			return 0
		}
		# check_dns_environment leaves routing checks to the direct stop helper.
		check_dns_environment() { :; }
		# service_wait skips unrelated firmware readiness before the monitor loop.
		service_wait() { :; }
		# load_operation_config retains the fixture's enabled integration snapshot.
		load_operation_config() { :; }
		set +u
		if start_monitor; then fail "monitor-${monitor_phase} swallowed direct stop failure"; fi
		[ "${RECOVERY_CALLS}" -eq 1 ] || fail "monitor-${monitor_phase} repeated stop work"
	) || exit 1
done

printf '%s\n' 'PASS: graceful monitor stop verifies daemon, resolver, handoff, and required main/SDN DNS'
