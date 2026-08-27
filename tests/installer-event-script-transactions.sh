#!/bin/sh
# Verify installer init, services, and firewall hook updates restore prior state on failure.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_DIR="${TMPDIR:-/tmp}/installer-event-script-transactions.$$"

cleanup() {
	rm -rf "${TMP_DIR}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"
mkdir -p "${TMP_DIR}/jffs/scripts" "${TMP_DIR}/base" || fail 'could not create transaction fixture'
sed -n '/^event_scripts_snapshot() {$/,$ { /^remove_firewall_event_scripts() {$/q; p; }' "${SCRIPT_PATH}" >"${TMP_DIR}/helpers.part" ||
	fail 'could not extract event-script transaction helpers'
sed -n '/^remove_firewall_event_scripts() {$/,/^}$/p' "${SCRIPT_PATH}" >>"${TMP_DIR}/helpers.part" ||
	fail 'could not complete firewall transaction helper extraction'
sed "s|/jffs/scripts|${TMP_DIR}/jffs/scripts|g" "${TMP_DIR}/helpers.part" >"${TMP_DIR}/helpers"
# shellcheck disable=SC1091
. "${TMP_DIR}/helpers"

BASE_DIR="${TMP_DIR}/base"

printf '%s\n' 'original init' >"${TMP_DIR}/jffs/scripts/init-start"
write_manager_script() {
	printf '%s\n' 'changed init' >"$1"
	return 1
}
if add_init_event_scripts; then
	fail 'init hook publication failure was hidden'
fi
grep -qx 'original init' "${TMP_DIR}/jffs/scripts/init-start" || fail 'init hook was not restored'

printf '%s\n' 'original services-stop' >"${TMP_DIR}/jffs/scripts/services-stop"
printf '%s\n' 'original service-event-end' >"${TMP_DIR}/jffs/scripts/service-event-end"
del_between_magic() { return 0; }
write_manager_script() {
	printf '%s\n' 'changed services-stop' >"$1"
}
write_command_script() {
	printf '%s\n' 'changed service-event-end' >"$1"
	return 1
}
if add_services_event_scripts; then
	fail 'services hook publication failure was hidden'
fi
grep -qx 'original services-stop' "${TMP_DIR}/jffs/scripts/services-stop" || fail 'services-stop was not restored after add failure'
grep -qx 'original service-event-end' "${TMP_DIR}/jffs/scripts/service-event-end" || fail 'service-event-end was not restored after add failure'

remove_calls=0
del_jffs_script() {
	remove_calls="$((remove_calls + 1))"
	printf '%s\n' 'changed services-stop' >"$1"
}
del_between_magic() {
	printf '%s\n' 'changed service-event-end' >"$1"
	return 1
}
if remove_services_event_scripts; then
	fail 'services hook removal failure was hidden'
fi
[ "${remove_calls}" -eq 1 ] || fail 'services-stop removal was not attempted'
grep -qx 'original services-stop' "${TMP_DIR}/jffs/scripts/services-stop" || fail 'services-stop was not restored after remove failure'
grep -qx 'original service-event-end' "${TMP_DIR}/jffs/scripts/service-event-end" || fail 'service-event-end was not restored after remove failure'

printf '%s\n' 'original firewall' >"${TMP_DIR}/jffs/scripts/firewall-start"
write_manager_script() {
	printf '%s\n' 'changed firewall' >"$1"
	return 1
}
if add_firewall_event_scripts; then
	fail 'firewall hook publication failure was hidden'
fi
grep -qx 'original firewall' "${TMP_DIR}/jffs/scripts/firewall-start" || fail 'firewall hook was not restored'

printf '%s\n' 'PASS: installer event-script transaction regression'
