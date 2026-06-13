#!/bin/sh

set -u

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP_DIR="${TMPDIR:-/tmp}/agh-installer-input-loops.$$"
FUNCTIONS_FILE="${TMP_DIR}/functions.sh"

cleanup() {
	rm -rf "${TMP_DIR}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

mkdir -p "${TMP_DIR}" || exit 1

awk '
	/^ipv4_is_valid\(\)/,/^}/
	/^port_is_valid\(\)/,/^}/
	/^read_input_dns\(\)/,/^}/
	/^read_input_num\(\)/,/^}/
	/^read_input_port\(\)/,/^}/
	/^read_yesno\(\)/,/^}/
' "${REPO_DIR}/installer" >"${FUNCTIONS_FILE}"

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

BOLD=""
NORM=""
INFO=""
ERROR="Error:"
INPUT="=>"
DNS_SERVER1=""

PTXT() {
	case "${1:-}" in
		-n)
			shift
			printf '%s' "$*"
			;;
		*)
			printf '%s\n' "$*"
			;;
	esac
}

ai_have_cmd() {
	[ "$1" = "netstat" ]
}

netstat() {
	printf '%s\n' 'tcp 0 0 0.0.0.0:3000 0.0.0.0:* LISTEN'
}

printf '%s\n' bad 1.1.1.1 >"${TMP_DIR}/dns.input"
read_input_dns "Default is" 9.9.9.9 <"${TMP_DIR}/dns.input" || fail "DNS input did not recover from invalid input"
[ "${BOOTSTRAP1}" = "1.1.1.1" ] || fail "DNS input selected the wrong value"

printf '%s\n' x 9 2 >"${TMP_DIR}/number.input"
read_input_num "Choose" 1 3 "" "" "" <"${TMP_DIR}/number.input" || fail "numeric input did not recover from invalid values"
[ "${CHOSEN}" = "2" ] || fail "numeric input selected the wrong value"

printf '%s\n' 2999 00003000 3001 >"${TMP_DIR}/port.input"
read_input_port "Default is" 3000 <"${TMP_DIR}/port.input" || fail "port input did not recover from invalid or occupied ports"
[ "${WEB_PORT}" = "3001" ] || fail "port input selected the wrong value"

printf '%s\n' maybe y >"${TMP_DIR}/yesno.input"
read_yesno "Continue?" <"${TMP_DIR}/yesno.input" || fail "yes/no input did not recover from invalid input"

read_yesno "Continue?" </dev/null && fail "yes/no input accepted end-of-file"
[ "$?" -eq 2 ] || fail "yes/no input did not distinguish end-of-file from No"

printf '%s\n' n >"${TMP_DIR}/no.input"
read_yesno "Continue?" <"${TMP_DIR}/no.input" && fail "yes/no input accepted No"
[ "$?" -eq 1 ] || fail "yes/no input returned the wrong status for No"

printf '%s\n' "PASS: installer input helpers retry iteratively and distinguish No from end-of-file"
