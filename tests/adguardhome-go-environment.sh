#!/bin/sh
# Verify Go runtime environment overrides are validated and passed as single env arguments.

set -u

S99_PATH="${1:-S99AdGuardHome}"
TMP_ROOT="${TMPDIR:-/tmp}/agh-go-environment.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	rm -rf "${TMP_ROOT}"
	exit 1
}

trap 'rm -rf "${TMP_ROOT}"' 0 HUP INT TERM
mkdir -p "${TMP_ROOT}" || fail 'setup failed'
sed -n '/^agh_uint_in_range() {$/,/^}$/p; /^agh_godebug_valid() {$/,/^}$/p; /^agh_memory_limit_mib() {$/,/^}$/p; /^launch_adguardhome() {$/,/^}$/p' \
	"${S99_PATH}" >"${FUNCTIONS_FILE}" || fail 'function extraction failed'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

agh_uint_in_range 1 1 1000 || fail 'lower numeric bound rejected'
agh_uint_in_range 1000 1 1000 || fail 'upper numeric bound rejected'
for hostile_number in '' 0 1001 -1 1x '1;touch' '1 2' '1>file' '1=2'; do
	if agh_uint_in_range "${hostile_number}" 1 1000; then
		fail "hostile numeric value accepted: ${hostile_number}"
	fi
done
[ "$(agh_memory_limit_mib 32)" = 32 ] || fail 'minimum calculated memory limit rejected'
[ "$(agh_memory_limit_mib 384)" = 384 ] || fail 'maximum calculated memory limit rejected'
for bad_memory_limit in '' 0 31 385 invalid '64;command'; do
	[ "$(agh_memory_limit_mib "${bad_memory_limit}")" = 128 ] ||
		fail "invalid calculated memory limit was not reset: ${bad_memory_limit}"
done

agh_godebug_valid 'disablethp=1,http2debug=0' || fail 'valid GODEBUG rejected'
for hostile_godebug in 'disablethp=1;touch /tmp/pwned' 'disablethp=1 extra=1' \
	'disablethp=1>file' 'disablethp=$(touch)' 'disablethp=1&x=1' 'disablethp=1,,x=1' \
	'=1' 'x=' 'x=1=2'; do
	if agh_godebug_valid "${hostile_godebug}"; then
		fail "hostile GODEBUG accepted: ${hostile_godebug}"
	fi
done

ENV_LOG="${TMP_ROOT}/env.log"
COMMAND_LOG="${TMP_ROOT}/command.log"
env() {
	: >"${ENV_LOG}"
	while [ "$#" -gt 0 ]; do
		case "$1" in
			*=*) printf '%s\n' "$1" >>"${ENV_LOG}"; shift ;;
			*) break ;;
		esac
	done
	printf '%s\n' "$#" "$@" >"${COMMAND_LOG}"
}
GOGC='50;extra-command'
GOMAXPROCS='2 extra-argument'
GOMEMLIMIT='128MiB>redirect'
GODEBUG='x=1 NEW_VARIABLE=owned'
launch_adguardhome '/path with spaces/AdGuardHome' '-literal;command' 'NAME=value' '>redirect'
[ "$(wc -l <"${ENV_LOG}")" -eq 6 ] || fail 'environment assignments split into extra words'
grep -Fxq 'GOGC=50;extra-command' "${ENV_LOG}" || fail 'GOGC was not one literal assignment'
grep -Fxq 'GODEBUG=x=1 NEW_VARIABLE=owned' "${ENV_LOG}" || fail 'GODEBUG introduced another assignment'
[ "$(sed -n '1p' "${COMMAND_LOG}")" -eq 4 ] || fail 'hostile values introduced command arguments'
grep -Fxq -- '-literal;command' "${COMMAND_LOG}" || fail 'command metacharacter argument was evaluated'
grep -Fxq -- '>redirect' "${COMMAND_LOG}" || fail 'redirection argument was evaluated'
[ ! -e "${TMP_ROOT}/pwned" ] || fail 'hostile value executed a command'

printf '%s\n' 'PASS: Go runtime environment values are validated and safely launched'
