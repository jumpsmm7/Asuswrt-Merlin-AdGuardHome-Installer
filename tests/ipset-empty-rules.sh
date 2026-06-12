#!/bin/sh
# Verify empty managed IPSET data disables the YAML integration without failing setup.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
FUNCTION_FILE="${TMPDIR:-/tmp}/ipset-empty-functions.$$"
TEST_DIR="${TMPDIR:-/tmp}/ipset-empty-test.$$"

cleanup() {
	rm -f "${FUNCTION_FILE}"
	rm -rf "${TEST_DIR}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

sed -n '/^IPSet_Refresh_Locked() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTION_FILE}" || fail "could not read ${SCRIPT_PATH}"
[ -s "${FUNCTION_FILE}" ] || fail 'IPSet_Refresh_Locked was not found'

# shellcheck disable=SC1090
. "${FUNCTION_FILE}"

IPSet_Current_File() {
	printf '%s\n' "${CURRENT_FILE:-}"
}

IPSet_Collect_Dnsmasq() {
	[ -z "${DNSMASQ_RULES:-}" ] || printf '%s\n' "${DNSMASQ_RULES}"
}

IPSet_Disable_Managed() {
	DISABLE_CALLS="$((DISABLE_CALLS + 1))"
	IPSET_DISABLE_CHANGED="${DISABLE_CHANGED:-}"
	return "${DISABLE_STATUS:-0}"
}

logger() {
	:
}

rm() {
	case " $* " in
		*" ${IPSET_FILE:-unset} "*)
			[ "${REMOVE_STATUS:-0}" -eq 0 ] || return "${REMOVE_STATUS}"
			;;
	esac
	command rm "$@"
}

mkdir -p "${TEST_DIR}" || fail 'could not create test directory'
IPSET_FILE="${TEST_DIR}/ipset.conf"
IPSET_USER_FILE="${TEST_DIR}/ipset.user"
IPSET_REFRESH_CONFIG=""
NAME=AdGuardHome
CURRENT_FILE=""
DISABLE_CALLS=0
DISABLE_STATUS=1
IPSET_REFRESH_CHANGED=""
printf '%s\n' 'existing.example/EXISTING_SET' >"${IPSET_FILE}"

if IPSet_Refresh_Locked; then
	fail 'empty refresh succeeded when managed YAML could not be disabled'
fi
[ "${DISABLE_CALLS}" -eq 1 ] || fail 'failed empty refresh did not try to disable managed YAML'
grep -q '^existing.example/EXISTING_SET$' "${IPSET_FILE}" || fail 'failed YAML disable removed the existing managed IPSET file'
[ -z "${IPSET_REFRESH_CHANGED}" ] || fail 'failed empty refresh reported a changed file'

DISABLE_CALLS=0
DISABLE_STATUS=0
DISABLE_CHANGED=1
REMOVE_STATUS=1
if IPSet_Refresh_Locked; then
	fail 'empty refresh succeeded when the stale managed IPSET file could not be removed'
fi
[ "${DISABLE_CALLS}" -eq 1 ] || fail 'failed file removal did not disable managed YAML first'
grep -q '^existing.example/EXISTING_SET$' "${IPSET_FILE}" || fail 'failed file removal did not preserve the stale managed IPSET file'
[ -z "${IPSET_REFRESH_CHANGED}" ] || fail 'failed file removal reported a changed file'

DISABLE_CALLS=0
REMOVE_STATUS=0
IPSet_Refresh_Locked || fail 'empty refresh failed'
[ "${DISABLE_CALLS}" -eq 1 ] || fail 'empty refresh did not disable managed YAML'
[ "${IPSET_REFRESH_CHANGED}" = 1 ] || fail 'empty refresh did not request a service restart'
[ ! -e "${IPSET_FILE}" ] || fail 'empty generated IPSET file was retained'

DISABLE_CALLS=0
DISABLE_CHANGED=""
IPSET_REFRESH_CHANGED=""
IPSet_Refresh_Locked || fail 'unchanged empty refresh failed'
[ "${DISABLE_CALLS}" -eq 1 ] || fail 'unchanged empty refresh did not check managed YAML'
[ -z "${IPSET_REFRESH_CHANGED}" ] || fail 'unchanged empty refresh requested a service restart'

DISABLE_CALLS=0
DISABLE_CHANGED=1
IPSET_REFRESH_CHANGED=""
IPSet_Refresh_Locked || fail 'YAML-only empty refresh failed'
[ "${IPSET_REFRESH_CHANGED}" = 1 ] || fail 'YAML-only empty refresh did not request a service restart'

printf '%s\n' 'example.com/ROUTE_VPN' >"${IPSET_USER_FILE}"
DISABLE_CALLS=0
IPSET_REFRESH_CHANGED=""
IPSet_Refresh_Locked || fail 'rule refresh failed'
[ "${DISABLE_CALLS}" -eq 0 ] || fail 'non-empty refresh disabled managed YAML'
[ "${IPSET_REFRESH_CHANGED}" = 1 ] || fail 'non-empty refresh did not report a changed file'
grep -q '^example.com/ROUTE_VPN$' "${IPSET_FILE}" || fail 'generated IPSET rule is missing'

printf '%s\n' 'PASS: empty IPSET data disables managed integration and valid rules remain enabled'
