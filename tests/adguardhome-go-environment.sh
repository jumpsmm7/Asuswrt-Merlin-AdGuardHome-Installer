#!/bin/sh
# Verify Go runtime environment overrides are validated and passed as single env arguments.

set -u

S99_PATH="${1:-S99AdGuardHome}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/agh-go-environment.XXXXXX")" || {
	printf '%s\n' 'FAIL: could not create exclusive test workspace' >&2
	exit 1
}
FUNCTIONS_FILE="${TMP_ROOT}/functions"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	rm -rf "${TMP_ROOT}"
	exit 1
}

trap 'rm -rf "${TMP_ROOT}"' 0 HUP INT TERM
sed -n '/^agh_uint_in_range() {$/,/^}$/p; /^agh_godebug_valid() {$/,/^}$/p; /^agh_memory_limit_mib() {$/,/^}$/p; /^launch_adguardhome() {$/,/^}$/p' \
	"${S99_PATH}" >"${FUNCTIONS_FILE}" || fail 'function extraction failed'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

LEGACY_ASSIGNMENTS="${TMP_ROOT}/legacy-assignments"
sed -n '/^PREARGS=/p; /^ARGS=/p' "${S99_PATH}" >"${LEGACY_ASSIGNMENTS}" || fail 'legacy assignment extraction failed'
[ "$(wc -l <"${LEGACY_ASSIGNMENTS}")" -eq 2 ] || fail 'legacy launch compatibility assignments are missing'
GOGC=50
GOMAXPROCS=2
GOMEMLIMIT=128MiB
GODEBUG=netdns=go+2
WORK_DIR=/opt/etc/AdGuardHome
PID_FILE=/opt/var/run/AdGuardHome.pid
LOG_FILE=syslog
# shellcheck disable=SC1090
. "${LEGACY_ASSIGNMENTS}"
[ "${PREARGS}" = 'env TZ=/etc/localtime GOGC=50 GOMAXPROCS=2 GOMEMLIMIT=128MiB QUIC_GO_DISABLE_ECN=true GODEBUG=netdns=go+2' ] ||
	fail 'legacy PREARGS does not retain validated Go environment assignments'
[ "${ARGS}" = '-s run -c /opt/etc/AdGuardHome/AdGuardHome.yaml -w /opt/etc/AdGuardHome --pidfile /opt/var/run/AdGuardHome.pid --no-check-update -l syslog' ] ||
	fail 'legacy ARGS does not retain required service paths'

GOMAXPROCS_INIT="${TMP_ROOT}/gomaxprocs-init"
sed -n '/^GOMAXPROCS="${ADGUARDHOME_GOMAXPROCS:-${DEFAULT_GOMAXPROCS}}"$/,/^agh_uint_in_range "${GOMAXPROCS}" 1 64/p' \
	"${S99_PATH}" >"${GOMAXPROCS_INIT}" || fail 'GOMAXPROCS initialization extraction failed'
[ "$(wc -l <"${GOMAXPROCS_INIT}")" -eq 2 ] || fail 'GOMAXPROCS initialization changed unexpectedly'
for invalid_gomaxprocs in 0 -1 invalid; do
	(
		DEFAULT_GOMAXPROCS=2
		ADGUARDHOME_GOMAXPROCS="${invalid_gomaxprocs}"
		# shellcheck disable=SC1090
		. "${GOMAXPROCS_INIT}"
		[ "${GOMAXPROCS}" = "${DEFAULT_GOMAXPROCS}" ]
	) || fail "invalid GOMAXPROCS did not retain the detected default: ${invalid_gomaxprocs}"
done

GOGC_INIT="${TMP_ROOT}/gogc-init"
sed -n '/^GOGC="${ADGUARDHOME_GOGC:-50}"$/,/^esac$/p' "${S99_PATH}" >"${GOGC_INIT}" ||
	fail 'GOGC initialization extraction failed'
(
	ADGUARDHOME_GOGC=off
	# shellcheck disable=SC1090
	. "${GOGC_INIT}"
	[ "${GOGC}" = off ]
) || fail 'documented GOGC=off override was not preserved'
(
	ADGUARDHOME_GOGC=0
	# shellcheck disable=SC1090
	. "${GOGC_INIT}"
	[ "${GOGC}" = 0 ]
) || fail 'documented GOGC=0 override was not preserved'
(
	ADGUARDHOME_GOGC=invalid
	# shellcheck disable=SC1090
	. "${GOGC_INIT}"
	[ "${GOGC}" = 50 ]
) || fail 'invalid GOGC override did not use the safe default'
(
	ADGUARDHOME_GOGC=200
	# shellcheck disable=SC1090
	. "${GOGC_INIT}"
	[ "${GOGC}" = 200 ]
) || fail 'valid numeric GOGC override was not preserved'
(
	ADGUARDHOME_GOGC=1000
	# shellcheck disable=SC1090
	. "${GOGC_INIT}"
	[ "${GOGC}" = 1000 ]
) || fail 'upper-bound GOGC override was not preserved'
(
	ADGUARDHOME_GOGC=1001
	# shellcheck disable=SC1090
	. "${GOGC_INIT}"
	[ "${GOGC}" = 50 ]
) || fail 'out-of-range GOGC override did not use the safe default'

for valid_gomaxprocs in 1 8 64; do
	(
		DEFAULT_GOMAXPROCS=2
		ADGUARDHOME_GOMAXPROCS="${valid_gomaxprocs}"
		# shellcheck disable=SC1090
		. "${GOMAXPROCS_INIT}"
		[ "${GOMAXPROCS}" = "${valid_gomaxprocs}" ]
	) || fail "valid GOMAXPROCS override was not preserved: ${valid_gomaxprocs}"
done
(
	DEFAULT_GOMAXPROCS=2
	ADGUARDHOME_GOMAXPROCS=65
	# shellcheck disable=SC1090
	. "${GOMAXPROCS_INIT}"
	[ "${GOMAXPROCS}" = "${DEFAULT_GOMAXPROCS}" ]
) || fail 'out-of-range GOMAXPROCS override did not retain the detected default'

agh_uint_in_range 1 1 1000 || fail 'lower numeric bound rejected'
agh_uint_in_range 1000 1 1000 || fail 'upper numeric bound rejected'
for hostile_number in '' 0 1001 -1 1x '1;touch' '1 2' '1>file' '1=2'; do
	if agh_uint_in_range "${hostile_number}" 1 1000; then
		fail "hostile numeric value accepted: ${hostile_number}"
	fi
done
agh_uint_in_range 5 5 5 || fail 'value equal to both bounds was rejected'
if agh_uint_in_range 4 5 5; then
	fail 'value below equal bounds was accepted'
fi
if agh_uint_in_range 6 5 5; then
	fail 'value above equal bounds was accepted'
fi
[ "$(agh_memory_limit_mib 1)" = 1 ] || fail 'small calculated memory limit rejected'
[ "$(agh_memory_limit_mib 0)" = 1 ] || fail 'zero calculated memory limit was not clamped to 1 MiB'
[ "$(agh_memory_limit_mib 31)" = 31 ] || fail 'calculated memory limit below 32 MiB was increased'
[ "$(agh_memory_limit_mib 384)" = 384 ] || fail 'maximum calculated memory limit rejected'
[ "$(agh_memory_limit_mib 385)" = 384 ] || fail 'oversized calculated memory limit was not capped'
[ "$(agh_memory_limit_mib 1000000)" = 384 ] || fail 'large calculated memory limit was not capped'
for bad_memory_limit in '' invalid '64;command'; do
	[ "$(agh_memory_limit_mib "${bad_memory_limit}")" = 128 ] ||
		fail "invalid calculated memory limit was not reset: ${bad_memory_limit}"
done

agh_godebug_valid 'disablethp=1,http2debug=0,netdns=go+2' || fail 'valid GODEBUG rejected'
agh_godebug_valid '' || fail 'empty GODEBUG was rejected'
agh_godebug_valid 'x=abc-1.2+3' || fail 'single entry with a hyphen and plus in the value was rejected'
for hostile_godebug in 'disablethp=1;touch /tmp/pwned' 'disablethp=1 extra=1' \
	'disablethp=1>file' 'disablethp=$(touch)' 'disablethp=1&x=1' 'disablethp=1,,x=1' \
	'=1' 'x=' 'x=1=2' ',x=1' 'x=1,'; do
	if agh_godebug_valid "${hostile_godebug}"; then
		fail "hostile GODEBUG accepted: ${hostile_godebug}"
	fi
done

ENV_LOG="${TMP_ROOT}/env.log"
COMMAND_LOG="${TMP_ROOT}/command.log"
PID_LOG="${TMP_ROOT}/pid.log"
mkdir "${TMP_ROOT}/bin" || fail 'could not create fake command directory'
cat >"${TMP_ROOT}/bin/env" <<'EOF'
#!/bin/sh
: >"${ENV_LOG}"
while [ "$#" -gt 0 ]; do
	case "$1" in
		*=*) printf '%s\n' "$1" >>"${ENV_LOG}"; shift ;;
		*) break ;;
	esac
done
printf '%s\n' "$#" "$@" >"${COMMAND_LOG}"
printf '%s\n' "$$" >"${PID_LOG}"
EOF
chmod 755 "${TMP_ROOT}/bin/env" || fail 'could not make fake env executable'
PATH="${TMP_ROOT}/bin:${PATH}"
export PATH ENV_LOG COMMAND_LOG PID_LOG
GOGC='50;extra-command'
GOMAXPROCS='2 extra-argument'
GOMEMLIMIT='128MiB>redirect'
GODEBUG='x=1 NEW_VARIABLE=owned'
PROC='/path with spaces/AdGuardHome'
WORK_DIR="${TMP_ROOT}/work dir;command"
PID_FILE="${TMP_ROOT}/pid file>redirect"
LOG_FILE='NAME=value'
launch_adguardhome &
launch_pid="$!"
wait "${launch_pid}" || fail 'launcher failed'
[ "$(cat "${PID_LOG}")" = "${launch_pid}" ] || fail 'launcher PID did not become the env process PID'
[ "$(wc -l <"${ENV_LOG}")" -eq 6 ] || fail 'environment assignments split into extra words'
grep -Fxq 'GOGC=50;extra-command' "${ENV_LOG}" || fail 'GOGC was not one literal assignment'
grep -Fxq 'GODEBUG=x=1 NEW_VARIABLE=owned' "${ENV_LOG}" || fail 'GODEBUG introduced another assignment'
[ "$(sed -n '1p' "${COMMAND_LOG}")" -eq 12 ] || fail 'hostile values introduced command arguments'
grep -Fxq -- '/path with spaces/AdGuardHome' "${COMMAND_LOG}" || fail 'process path was split'
grep -Fxq -- "${WORK_DIR}/AdGuardHome.yaml" "${COMMAND_LOG}" || fail 'configuration path was split or evaluated'
grep -Fxq -- "${PID_FILE}" "${COMMAND_LOG}" || fail 'redirection metacharacter was evaluated'
grep -Fxq -- 'NAME=value' "${COMMAND_LOG}" || fail 'log value introduced an environment assignment'
[ ! -e "${TMP_ROOT}/pwned" ] || fail 'hostile value executed a command'

printf '%s\n' 'PASS: Go runtime environment values are validated and safely launched'
