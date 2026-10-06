#!/bin/sh
# Exercise real cross-process locks and saved preferences with simulated mounts.
set -eu
ROOT="$(mktemp -d)"
trap 'rm -rf "${ROOT}"' EXIT HUP INT TERM
MANAGER="$(pwd)/AdGuardHome.sh"
# Load declarations/defaults only, then extract the production helpers.
sed '/^case "${1:-}" in$/,$d' "${MANAGER}" |
	sed 's|/tmp/AdGuardHome|${WORK_DIR}/manager|g' >"${ROOT}/functions"
cat >"${ROOT}/worker" <<'EOF_WORKER'
#!/bin/sh
set -u
. "$1/functions"
WORK_DIR="$1"
CONF_FILE="${WORK_DIR}/config"
PROC_LOCK_FORCE_MKDIR="$2"
CONFIG_LOCAL="${4:-NO}"
NAME=cache-test
PROCS=cache-test
# Shorten only the lock retry delays for deterministic contention fixtures.
if [ -f "${WORK_DIR}/fast-lock-retries" ]; then
	# which advertises the fast usleep stub and delegates other command lookups to the host.
	which() { [ "${1:-}" != usleep ] || return 0; command which "$@"; }
	# usleep shortens lock retry delays to 10 milliseconds on the validation host.
	usleep() { command sleep 0.01; }
fi
# pidof reports the simulated daemon running unless an unready marker exists.
pidof() { [ ! -f "${WORK_DIR}/unready" ]; }
# dns_handoff_is_active reports no DNS handoff so the fixture can isolate service locking.
dns_handoff_is_active() { return 1; }
# agh_log suppresses worker diagnostics while actions are recorded separately.
agh_log() { :; }
# resolv_conf_uses_rom selects a mutable native resolver for the mount simulation.
resolv_conf_uses_rom() { return 1; }
# resolv_conf_is_tmp_mount reads the shared mounted marker so workers observe the same resolver state.
resolv_conf_is_tmp_mount() { [ -f "${WORK_DIR}/mounted" ]; }
# adguard_local_cache_ready rejects active service operations or unready state and can block a lookup until released.
adguard_local_cache_ready() {
	adguard_local_cache_service_active && return 1
	[ ! -f "${WORK_DIR}/unready" ] || return 1
	if [ "${1:-}" != no-lookup ] && [ -f "${WORK_DIR}/block-lookup" ]; then
		: >"${WORK_DIR}/lookup-entered"
		while [ ! -f "${WORK_DIR}/lookup-release" ]; do sleep 1; done
	fi
	[ ! -f "${WORK_DIR}/unready" ]
}
# mount records activation and delays publishing the mounted marker to expose concurrent binds.
mount() {
	printf '%s\n' mount >>"${WORK_DIR}/calls"
	# Keep the window open so two unlocked workers would both bind.
	sleep 1
	: >"${WORK_DIR}/mounted"
}
# umount removes the shared mounted marker unless the fixture requests cleanup failure.
umount() {
	[ ! -f "${WORK_DIR}/unmount-fail" ] || return 1
	printf '%s\n' umount >>"${WORK_DIR}/calls"
	rm -f "${WORK_DIR}/mounted"
}
# timezone skips router timezone setup in the extracted worker runtime.
timezone() { :; }
# nvram returns a ready firmware value for service startup polling.
nvram() { printf '%s\n' 1; }
# Keep firmware readiness polling fast in the real detached run-lock fixture.
sleep() {
	case "${1:-}" in
		10s) command sleep 0.1 ;;
		*) command sleep "$@" ;;
	esac
}
# hold_resolver signals lock entry and waits for the test to release the resolver lock holder.
hold_resolver() {
	: >"${WORK_DIR}/resolver-entered"
	while [ ! -f "${WORK_DIR}/resolver-release" ]; do sleep 1; done
}
# cache_service_action signals detached service entry and waits for the release marker.
cache_service_action() {
	: >"${WORK_DIR}/detached-service-entered"
	while [ ! -f "${WORK_DIR}/detached-service-release" ]; do sleep 1; done
}
# mock_lower requires native routing before recording a service action and can invalidate an in-flight lookup.
mock_lower() {
	[ ! -f "${WORK_DIR}/mounted" ] || return 1
	printf 'lower %s\n' "$1" >>"${WORK_DIR}/calls"
	[ ! -f "${WORK_DIR}/block-lookup" ] || : >"${WORK_DIR}/unready"
}
case "$3" in
	sync) adguard_local_cache_sync ;;
	cleanup) dnsmasq_resolv_conf_cleanup ;;
	hold-resolver) adguard_local_cache_lock hold_resolver ;;
	detached-service)
		printf '%s\n' "$$" >"${WORK_DIR}/detached-service-parent"
		(
			while [ ! -f "${WORK_DIR}/detached-service-begin" ]; do sleep 1; done
			[ "${PROC_LOCK_FORCE_MKDIR}" != 1 ] || have_cmd() { return 1; }
			set +u
			adguardhome_run cache_service_action || exit 1
			: >"${WORK_DIR}/detached-service-done"
		) >/dev/null 2>&1 &
		printf '%s\n' "$!" >"${WORK_DIR}/detached-service-pid"
		;;
	hold-service)
		exec 9>"${WORK_DIR}/manager.lock"
		flock -n 9 || exit 1
		: >"${WORK_DIR}/service-entered"
		adguard_local_cache_service_active || exit 1
		# A probe must leave its caller's service lock descriptor open and locked.
		flock -n 9 || exit 1
		while [ ! -f "${WORK_DIR}/service-release" ]; do sleep 1; done
		;;
	restart | stop | kill)
		LOWER_SCRIPT_LOC=mock_lower
		lower_script "$3"
		;;
esac
EOF_WORKER
SHELL_BIN="$(readlink "/proc/$$/exe")"
# run_worker runs the requested fixture action using the current shell, including BusyBox ash dispatch.
run_worker() {
	case "${SHELL_BIN##*/}" in
		busybox*) "${SHELL_BIN}" ash "${ROOT}/worker" "${ROOT}" "$@" ;;
		*) "${SHELL_BIN}" "${ROOT}/worker" "${ROOT}" "$@" ;;
	esac
}
# wait_for_file waits up to 30 polling intervals for path $1 and fails if it never appears.
wait_for_file() {
	attempts=0
	# Allow scheduler delay for background fixtures on busy validation hosts.
	while [ ! -f "$1" ] && [ "${attempts}" -lt 30 ]; do
		sleep 1
		attempts="$((attempts + 1))"
	done
	[ -f "$1" ]
}
for fallback in 0 1; do
	: >"${ROOT}/calls"
	printf '%s\n' 'ADGUARD_LOCAL="YES"' >"${ROOT}/config"
	run_worker "${fallback}" sync &
	first=$!
	run_worker "${fallback}" sync &
	second=$!
	wait "${first}"
	wait "${second}"
	[ "$(grep -c '^mount$' "${ROOT}/calls")" -eq 1 ]
	# A stale monitor snapshot must not override a newly saved preference.
	printf '%s\n' 'ADGUARD_LOCAL="NO"' >"${ROOT}/config"
	run_worker "${fallback}" sync YES
	[ ! -e "${ROOT}/mounted" ]
	printf '%s\n' 'ADGUARD_LOCAL="YES"' >"${ROOT}/config"
	for action in restart stop kill; do
		run_worker "${fallback}" sync
		run_worker "${fallback}" "${action}"
		[ ! -e "${ROOT}/mounted" ]
	done
	# Invalid preferences recover native routing and never activate cache.
	run_worker "${fallback}" sync
	printf '%s\n' 'ADGUARD_LOCAL="YES"' 'ADGUARD_LOCAL="NO"' >"${ROOT}/config"
	if run_worker "${fallback}" sync; then exit 1; fi
	[ ! -e "${ROOT}/mounted" ]
	# Failed cleanup must prevent stopping the daemon behind cached DNS.
	: >"${ROOT}/mounted"
	: >"${ROOT}/unmount-fail"
	before="$(grep -c '^lower ' "${ROOT}/calls")"
	if run_worker "${fallback}" restart; then exit 1; fi
	[ "$(grep -c '^lower ' "${ROOT}/calls")" -eq "${before}" ]
	rm "${ROOT}/unmount-fail"
	run_worker "${fallback}" cleanup
	# Even an arbitrary live resolver lock cannot block native-routing shutdown.
	: >"${ROOT}/fast-lock-retries"
	run_worker "${fallback}" hold-resolver &
	resolver_worker=$!
	wait_for_file "${ROOT}/resolver-entered"
	# Direct callers cannot bypass a potentially committing resolver holder.
	if run_worker "${fallback}" stop; then exit 1; fi
	run_worker 0 hold-service &
	activity_worker=$!
	wait_for_file "${ROOT}/service-entered"
	run_worker "${fallback}" stop
	[ ! -f "${ROOT}/resolver-release" ]
	: >"${ROOT}/resolver-release"
	: >"${ROOT}/service-release"
	wait "${resolver_worker}"
	wait "${activity_worker}"
	rm "${ROOT}/service-entered" "${ROOT}/service-release"
	rm "${ROOT}/fast-lock-retries" "${ROOT}/resolver-entered" "${ROOT}/resolver-release"
	# A pending DNS query must not prevent stop before the query returns.
	printf '%s\n' 'ADGUARD_LOCAL="YES"' >"${ROOT}/config"
	: >"${ROOT}/block-lookup"
	run_worker "${fallback}" sync &
	query_worker=$!
	wait_for_file "${ROOT}/lookup-entered"
	run_worker "${fallback}" stop
	[ ! -f "${ROOT}/lookup-release" ]
	[ ! -f "${ROOT}/mounted" ]
	: >"${ROOT}/lookup-release"
	if wait "${query_worker}"; then exit 1; fi
	rm "${ROOT}/block-lookup" "${ROOT}/lookup-entered" "${ROOT}/lookup-release" "${ROOT}/unready"
	# Use the actual manager run lock after its launching script has exited.
	run_worker "${fallback}" detached-service
	[ ! -e "/proc/$(cat "${ROOT}/detached-service-parent")/stat" ]
	: >"${ROOT}/detached-service-begin"
	wait_for_file "${ROOT}/detached-service-entered"
	owner="$(sed -n '1p' "${ROOT}/manager/pid")"
	[ "${owner}" != "$(cat "${ROOT}/detached-service-parent")" ]
	kill -0 "${owner}"
	if run_worker "${fallback}" sync; then exit 1; fi
	[ ! -f "${ROOT}/mounted" ]
	: >"${ROOT}/detached-service-release"
	wait_for_file "${ROOT}/detached-service-done"
	# Legacy cleanup waits for the completed runtime record.
	attempts=0
	while [ -e "${ROOT}/manager/pid" ] && [ "${attempts}" -lt 5 ]; do
		sleep 1
		attempts="$((attempts + 1))"
	done
	[ ! -e "${ROOT}/manager/pid" ]
	# Start the next backend with a clean service directory (flock retains it).
	rmdir "${ROOT}/manager" 2>/dev/null || true
	rm "${ROOT}/detached-service-parent" "${ROOT}/detached-service-pid" "${ROOT}/detached-service-begin" "${ROOT}/detached-service-entered" "${ROOT}/detached-service-release" "${ROOT}/detached-service-done"
done
# Descriptor lock activity must block activation before any owner pid is published.
run_worker 0 hold-service &
service_worker=$!
wait_for_file "${ROOT}/service-entered"
if run_worker 0 sync; then exit 1; fi
[ ! -f "${ROOT}/mounted" ]
: >"${ROOT}/service-release"
wait "${service_worker}"
printf '%s\n' 'PASS: resolver serialization, saved preference refresh and stop/restart ordering'
