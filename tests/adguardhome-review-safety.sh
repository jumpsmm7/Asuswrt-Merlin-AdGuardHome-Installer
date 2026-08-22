#!/bin/sh
# Verify reviewed runtime safety and portability contracts remain enforced.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"

# fail reports a failed contract and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

[ -f "${SCRIPT_PATH}" ] || fail "runtime script not found: ${SCRIPT_PATH}"

if grep -Eq '(^|[^0-9])(exec[[:space:]]+200|flock[[:space:]]+200|200[<>])' "${SCRIPT_PATH}"; then
	fail 'runtime script reserves hard-coded file descriptor 200'
fi
if grep -Eq -- '--insecure|(^|[[:space:]])-k([[:space:]]|$)' "${SCRIPT_PATH}"; then
	fail 'runtime script disables TLS certificate verification'
fi
if grep -Eq 'grep[[:space:]]+-[^[:space:]]*P' "${SCRIPT_PATH}"; then
	fail 'runtime script requires unsupported BusyBox grep Perl expressions'
fi
if grep -Fq '*.{md5sum,sha256sum}' "${SCRIPT_PATH}"; then
	fail 'runtime script uses non-POSIX brace expansion for checksum cleanup'
fi
if grep -Fq 'agh_validate_lan_bridge' "${SCRIPT_PATH}"; then
	fail 'runtime script relies on the obsolete LAN bridge validation variable'
fi

grep -Fq 'LAN_IF="$(nvram get lan_ifname 2>/dev/null)"' "${SCRIPT_PATH}" ||
	fail 'LAN bind refresh does not discover the configured LAN interface'
grep -Fq 'LAN_ADDR="$(interface_ipv4_addr "${LAN_IF}")"' "${SCRIPT_PATH}" ||
	fail 'LAN bind refresh does not validate an address assigned to the LAN interface'

printf '%s\n' 'PASS: AdGuardHome runtime review safety contracts are enforced'
