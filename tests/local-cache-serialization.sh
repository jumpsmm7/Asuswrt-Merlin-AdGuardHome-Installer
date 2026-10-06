#!/bin/sh
# Exercise real cross-process locks and saved preferences with simulated mounts.
set -eu
ROOT="$(mktemp -d)"
trap 'rm -rf "${ROOT}"' EXIT HUP INT TERM
MANAGER="$(pwd)/AdGuardHome.sh"
# Load declarations/defaults only, then extract the production helpers.
sed '/^case "${1:-}" in$/,$d' "${MANAGER}" >"${ROOT}/functions"
cat >"${ROOT}/worker" <<'EOF_WORKER'
#!/bin/sh
set -u
. "$1/functions"
WORK_DIR="$1"
CONF_FILE="${WORK_DIR}/config"
PROC_LOCK_FORCE_MKDIR="$2"
CONFIG_LOCAL="${4:-NO}"
NAME=cache-test
agh_log() { :; }
resolv_conf_uses_rom() { return 1; }
resolv_conf_is_tmp_mount() { [ -f "${WORK_DIR}/mounted" ]; }
adguard_local_cache_ready() { [ ! -f "${WORK_DIR}/unready" ]; }
mount() {
	printf '%s\n' mount >>"${WORK_DIR}/calls"
	# Keep the window open so two unlocked workers would both bind.
	sleep 1
	: >"${WORK_DIR}/mounted"
}
umount() {
	[ ! -f "${WORK_DIR}/unmount-fail" ] || return 1
	printf '%s\n' umount >>"${WORK_DIR}/calls"
	rm -f "${WORK_DIR}/mounted"
}
mock_lower() {
	[ ! -f "${WORK_DIR}/mounted" ] || return 1
	printf 'lower %s\n' "$1" >>"${WORK_DIR}/calls"
}
case "$3" in
	sync) adguard_local_cache_sync ;;
	cleanup) dnsmasq_resolv_conf_cleanup ;;
	restart | stop | kill)
		LOWER_SCRIPT_LOC=mock_lower
		lower_script "$3"
		;;
esac
EOF_WORKER
SHELL_BIN="$(readlink "/proc/$$/exe")"
run_worker() {
	case "${SHELL_BIN##*/}" in
		busybox*) "${SHELL_BIN}" ash "${ROOT}/worker" "${ROOT}" "$@" ;;
		*) "${SHELL_BIN}" "${ROOT}/worker" "${ROOT}" "$@" ;;
	esac
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
done
printf '%s\n' 'PASS: resolver serialization, saved preference refresh and stop/restart ordering'
