#!/bin/sh
# Verify DNS guard readiness falls back from usleep to a bounded integer sleep.
set -u

S99_PATH="${1:-S99AdGuardHome}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/s99-usleep-fallback.XXXXXX")" || exit 1
FUNCTIONS_FILE="${TMP_ROOT}/functions"
CALLS_FILE="${TMP_ROOT}/calls"

cleanup() {
	if [ -n "${ADGUARDHOME_DNS_GUARD_PID:-}" ]; then
		command kill "${ADGUARDHOME_DNS_GUARD_PID}" 2>/dev/null || true
		wait "${ADGUARDHOME_DNS_GUARD_PID}" 2>/dev/null || true
	fi
	rm -rf "${TMP_ROOT}"
}
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}
trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

sed -n '/^dns_retry_limit() {$/,/^}$/p; /^launch_dns_port_guard() {$/,/^}$/p' "${S99_PATH}" >"${FUNCTIONS_FILE}" || fail 'could not extract DNS guard helpers'
[ -s "${FUNCTIONS_FILE}" ] || fail 'DNS guard helper extraction was empty'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

DNS_HANDOFF_DIR="${TMP_ROOT}/handoff"
mkdir -p "${DNS_HANDOFF_DIR}" || fail 'could not create handoff directory'
USLEEP_AVAILABLE=0

dns_handoff_set_current_identity() {
	DNS_HANDOFF_CURRENT_PID="$$"
	DNS_HANDOFF_CURRENT_START_TIME="1"
}
dns_handoff_path_has_owner_mode() { return 0; }
dns_guard_readiness_matches_identity() { return 1; }
dns_handoff_marker_matches_identity() { return 0; }
remove_current_dns_guard_readiness() { rm -rf "${DNS_GUARD_READY_DIR}"; }
start_dns_port_guard() {
	trap 'exit 0' HUP INT TERM
	while :; do command sleep 1; done
}
stop_dns_port_guard() {
	if [ -n "${ADGUARDHOME_DNS_GUARD_PID:-}" ]; then
		command kill "${ADGUARDHOME_DNS_GUARD_PID}" 2>/dev/null || true
		wait "${ADGUARDHOME_DNS_GUARD_PID}" 2>/dev/null || true
		ADGUARDHOME_DNS_GUARD_PID=""
	fi
}
which() {
	[ "$1" = usleep ] && [ "${USLEEP_AVAILABLE}" -eq 1 ] && printf '%s\n' "${TMP_ROOT}/usleep"
}
sleep() { printf '%s\n' "sleep $*" >>"${CALLS_FILE}"; }
printf '%s\n' '#!/bin/sh' 'printf "%s\n" "usleep $*" >>"$USLEEP_CALLS_FILE"' >"${TMP_ROOT}/usleep" || fail 'could not create usleep shim'
chmod 755 "${TMP_ROOT}/usleep" || fail 'could not chmod usleep shim'
PATH="${TMP_ROOT}:${PATH}"
export PATH
USLEEP_CALLS_FILE="${CALLS_FILE}"
export USLEEP_CALLS_FILE

: >"${CALLS_FILE}"
USLEEP_AVAILABLE=0
ADGUARDHOME_DNS_GUARD_READY_RETRIES=20
if launch_dns_port_guard; then fail 'unready guard unexpectedly succeeded without usleep'; fi
[ "$(grep -c '^sleep 1$' "${CALLS_FILE}")" -eq 1 ] || fail 'missing-usleep fallback did not scale 20 100ms attempts to one 1s delay between two checks'
! grep -q '^usleep ' "${CALLS_FILE}" || fail 'missing-usleep fallback still invoked usleep'

: >"${CALLS_FILE}"
USLEEP_AVAILABLE=1
ADGUARDHOME_DNS_GUARD_READY_RETRIES=2
if launch_dns_port_guard; then fail 'unready guard unexpectedly succeeded with usleep'; fi
[ "$(grep -c '^usleep 100000$' "${CALLS_FILE}")" -eq 1 ] || fail 'available usleep path did not preserve 100000 microsecond polling'
! grep -q '^sleep 1$' "${CALLS_FILE}" || fail 'available usleep path used integer sleep fallback'

printf '%s\n' 'PASS: S99 DNS guard usleep fallback'
