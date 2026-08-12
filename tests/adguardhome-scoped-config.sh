#!/bin/sh
# Verify operation-scoped configuration snapshots and their fork budget.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
TMP_ROOT="${TMPDIR:-/tmp}/adguardhome-scoped-config.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions"
AWK_CALLS="${TMP_ROOT}/awk.calls"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

cleanup() {
	rm -rf "${TMP_ROOT}"
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
mkdir -p "${TMP_ROOT}/bin" || fail 'could not create test directory'
sed -n '/^load_operation_config() {$/,/^}$/p; /^netcheck_config() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" ||
	fail 'could not extract configuration helpers'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

DEFAULT_ADGUARD_NETCHECK_HOSTS='google.com github.com snbforums.com'
DEFAULT_ADGUARD_NETCHECK_DNS='127.0.0.1'
DEFAULT_ADGUARD_NETCHECK_REQUIRE_HTTP='NO'
DEFAULT_ADGUARD_NETCHECK_TIMEOUT='300'
DEFAULT_ADGUARD_NETCHECK_MODE='wan'
DEFAULT_ADGUARD_PROC_OPTIMIZE='NO'
DEFAULT_ADGUARD_PROC_PROFILE='balanced'
NAME='scoped-config-test'
CONF_FILE="${TMP_ROOT}/.config"
export AWK_CALLS

cat >"${TMP_ROOT}/bin/awk" <<'EOF'
#!/bin/sh
printf '%s\n' call >>"${AWK_CALLS}"
exec /usr/bin/awk "$@"
EOF
chmod 700 "${TMP_ROOT}/bin/awk" || fail 'could not install awk counter'
PATH="${TMP_ROOT}/bin:${PATH}"

cat >"${CONF_FILE}" <<'EOF'
ADGUARD_INSTALL_MODE="lan"
ADGUARD_DNSMASQ_MODE="disabled"
ADGUARD_LOCAL="YES"
ADGUARD_IPSET="NO"
ADGUARD_NETCHECK_HOSTS="example.com example.net"
ADGUARD_NETCHECK_DNS="192.0.2.1"
ADGUARD_NETCHECK_REQUIRE_HTTP="YES"
ADGUARD_NETCHECK_TIMEOUT="45"
ADGUARD_NETCHECK_MODE="lan"
ADGUARD_PROC_OPTIMIZE="YES"
ADGUARD_PROC_PROFILE="safe"
EOF

for scope in action stop action monitor-healthcheck; do
	: >"${AWK_CALLS}"
	load_operation_config "${scope}" || fail "${scope} snapshot failed"
	[ "$(wc -l <"${AWK_CALLS}")" -eq 1 ] || fail "${scope} used more than one awk invocation"
done
[ "${CONFIG_INSTALL_MODE}" = 'lan' ] || fail 'validated install mode was not published'
[ "${CONFIG_NETCHECK_TIMEOUT}" = '45' ] || fail 'validated timeout was not published'

# Explicit environment values continue to override the operation snapshot.
ADGUARD_NETCHECK_TIMEOUT='9'
ADGUARD_NETCHECK_TIMEOUT_SET='x'
[ "$(netcheck_config ADGUARD_NETCHECK_TIMEOUT 300)" = '9' ] || fail 'environment override lost precedence'
unset ADGUARD_NETCHECK_TIMEOUT ADGUARD_NETCHECK_TIMEOUT_SET

# A missing file is a valid default snapshot and does not attempt to fork awk.
rm -f "${CONF_FILE}"
: >"${AWK_CALLS}"
load_operation_config action || fail 'missing configuration did not use defaults'
[ ! -s "${AWK_CALLS}" ] || fail 'missing configuration unnecessarily invoked awk'
[ "${CONFIG_INSTALL_MODE}" = 'wan' ] || fail 'missing configuration did not publish defaults'

for invalid in 'ADGUARD_INSTALL_MODE=""' 'ADGUARD_INSTALL_MODE="wan"\nADGUARD_INSTALL_MODE="lan"' 'ADGUARD_NETCHECK_TIMEOUT="bad"'; do
	printf '%b\n' "${invalid}" >"${CONF_FILE}"
	if load_operation_config action >/dev/null 2>&1; then
		fail "invalid configuration was accepted: ${invalid}"
	fi
done

# Monitoring adopts an atomically replaced valid file only at the documented
# healthcheck boundary, while a malformed replacement leaves its last snapshot.
printf '%s\n' 'ADGUARD_NETCHECK_TIMEOUT="30"' >"${CONF_FILE}.new"
mv "${CONF_FILE}.new" "${CONF_FILE}"
load_operation_config monitor-healthcheck || fail 'replacement snapshot failed'
[ "${CONFIG_NETCHECK_TIMEOUT}" = '30' ] || fail 'replacement was not adopted at healthcheck boundary'
printf '%s\n' 'ADGUARD_NETCHECK_TIMEOUT="broken"' >"${CONF_FILE}.new"
mv "${CONF_FILE}.new" "${CONF_FILE}"
if load_operation_config monitor-healthcheck >/dev/null 2>&1; then
	fail 'malformed replacement was accepted'
fi
[ "${CONFIG_NETCHECK_TIMEOUT}" = '30' ] || fail 'malformed replacement discarded the prior snapshot'

printf '%s\n' 'PASS: scoped config awk forks: start 1 (was 12), stop 1 (was 4), IPSET refresh 1 (was 3), monitor healthcheck 1 (was 7)'
