#!/bin/sh
# Verify operation-scoped configuration snapshots and their fork budget.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/adguardhome-scoped-config.XXXXXX")" || {
	printf '%s\n' 'FAIL: could not create secure test directory' >&2
	exit 1
}
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
/bin/sed -n '/^set_operation_config_defaults() {$/,/^}$/p; /^load_operation_config() {$/,/^}$/p; /^netcheck_config() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" ||
	fail 'could not extract configuration helpers'
REAL_AWK="$(which awk 2>/dev/null)" || fail 'awk not found'
/bin/sed "s|/usr/bin/awk|${TMP_ROOT}/bin/awk|" "${FUNCTIONS_FILE}" >"${FUNCTIONS_FILE}.tmp" || fail 'could not instrument awk call'
mv "${FUNCTIONS_FILE}.tmp" "${FUNCTIONS_FILE}" || fail 'could not publish instrumented helpers'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

DEFAULT_ADGUARD_NETCHECK_HOSTS='google.com github.com snbforums.com'
DEFAULT_ADGUARD_NETCHECK_DNS='127.0.0.1'
DEFAULT_ADGUARD_NETCHECK_REQUIRE_HTTP='NO'
DEFAULT_ADGUARD_NETCHECK_TIMEOUT='300'
DEFAULT_ADGUARD_NETCHECK_MODE='wan'
DEFAULT_ADGUARD_PROC_OPTIMIZE='NO'
DEFAULT_ADGUARD_PROC_PROFILE='aggressive'
NAME='scoped-config-test'
CONF_FILE="${TMP_ROOT}/.config"
export AWK_CALLS

cat >"${TMP_ROOT}/bin/awk" <<EOF
#!/bin/sh
printf '%s\n' call >>"\${AWK_CALLS}"
exec "${REAL_AWK}" "\$@"
EOF
chmod 700 "${TMP_ROOT}/bin/awk" || fail 'could not install awk counter'
PATH="${TMP_ROOT}/bin${PATH:+:${PATH}}"

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

for invalid in 'ADGUARD_INSTALL_MODE=""' 'ADGUARD_INSTALL_MODE="wan"\nADGUARD_INSTALL_MODE="lan"' 'ADGUARD_DNSMASQ_MODE =disabled' 'ADGUARD_NETCHECK_TIMEOUT="bad"' 'ADGUARD_NETCHECK_HOSTS="example.com|injected"'; do
	printf '%b\n' "${invalid}" >"${CONF_FILE}"
	if load_operation_config action >/dev/null 2>&1; then
		fail "invalid configuration was accepted: ${invalid}"
	fi
done

# Explicitly optional empty status values are treated as unset, while required
# runtime values remain subject to the invalid-value cases above.
printf '%s\n' 'ADGUARD_WEBUI_PORT=""' 'INSTALLER_BRANCH=""' >"${CONF_FILE}"
load_operation_config status || fail 'empty optional status values were rejected'
[ -z "${CONFIG_WEBUI_PORT}" ] || fail 'empty WebUI port was not treated as unset'
[ -z "${CONFIG_INSTALLER_BRANCH}" ] || fail 'empty installer branch was not treated as unset'

# Scoped reads ignore unrelated keys and still publish complete default globals.
printf '%s\n' 'ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="1"' >"${CONF_FILE}"
load_operation_config status || fail 'status rejected configuration without status keys'
[ "${CONFIG_INSTALL_MODE}" = 'wan' ] || fail 'status did not publish complete defaults'
printf '%s\n' 'ADGUARD_WEBUI_PORT="3000"' >"${CONF_FILE}"
load_operation_config stop || fail 'stop rejected configuration without stop keys'
[ "${CONFIG_DNSMASQ_MODE}" = 'auto' ] || fail 'stop did not publish complete defaults'

# Installer-supported DNS hostnames remain valid, and a valid environment
# override masks a malformed persisted value for that invocation.
printf '%s\n' 'ADGUARD_NETCHECK_DNS="dns.google"' >"${CONF_FILE}"
load_operation_config action || fail 'supported netcheck DNS hostname was rejected'
[ "${CONFIG_NETCHECK_DNS}" = 'dns.google' ] || fail 'netcheck DNS hostname was not published'
printf '%s\n' 'ADGUARD_NETCHECK_TIMEOUT="bad"' >"${CONF_FILE}"
ADGUARD_NETCHECK_TIMEOUT='30'
ADGUARD_NETCHECK_TIMEOUT_SET='x'
load_operation_config action || fail 'valid environment override did not mask malformed persisted value'
[ "$(netcheck_config ADGUARD_NETCHECK_TIMEOUT 300)" = '30' ] || fail 'validated environment override was not retained'
unset ADGUARD_NETCHECK_TIMEOUT ADGUARD_NETCHECK_TIMEOUT_SET

# A marker without a non-empty environment value does not hide the persisted key.
printf '%s\n' 'ADGUARD_NETCHECK_TIMEOUT="45"' >"${CONF_FILE}"
ADGUARD_NETCHECK_TIMEOUT=''
ADGUARD_NETCHECK_TIMEOUT_SET='x'
load_operation_config action || fail 'marker-only override rejected persisted value'
[ "${CONFIG_NETCHECK_TIMEOUT}" = '45' ] || fail 'marker-only override hid persisted value'
unset ADGUARD_NETCHECK_TIMEOUT ADGUARD_NETCHECK_TIMEOUT_SET

# Router hooks validate only the configuration keys they consume.
cat >"${CONF_FILE}" <<'EOF'
ADGUARD_INSTALL_MODE="wan"
ADGUARD_IPSET="YES"
ADGUARD_WEBUI_PORT="broken"
ADGUARD_PROC_PROFILE="broken"
EOF
load_operation_config firewall || fail 'firewall scope rejected unrelated malformed values'
[ "${CONFIG_IPSET}" = 'YES' ] || fail 'firewall scope did not load IPSET value'
cat >"${CONF_FILE}" <<'EOF'
ADGUARD_INSTALL_MODE="lan"
ADGUARD_DNSMASQ_MODE="disabled"
ADGUARD_LOCAL="YES"
ADGUARD_WEBUI_PORT="broken"
EOF
load_operation_config dnsmasq || fail 'dnsmasq scope rejected unrelated malformed values'
[ "${CONFIG_LOCAL}" = 'YES' ] || fail 'dnsmasq scope did not load local setting'

cat >"${CONF_FILE}" <<'EOF'
ADGUARD_IPSET="NO"
ADGUARD_WEBUI_PORT="broken"
INSTALLER_BRANCH="bad branch"
ADGUARD_NETCHECK_HOSTS="example.com:8080 2001:db8::1"
EOF
load_operation_config action || fail 'action scope rejected status-only values or supported host colons'
[ "${CONFIG_IPSET}" = 'NO' ] || fail 'action scope did not load IPSET value'
[ "${CONFIG_NETCHECK_HOSTS}" = 'example.com:8080 2001:db8::1' ] || fail 'action scope rejected supported host colons'

printf '%s\n' 'ADGUARD_IPSET="NO"' >"${CONF_FILE}"
load_operation_config dnsmasq || fail 'dnsmasq scope rejected IPSET setting'
[ "${CONFIG_IPSET}" = 'NO' ] || fail 'dnsmasq scope did not load disabled IPSET setting'

CONFIG_LOCAL='stale'
CONFIG_IPSET='stale'
CONFIG_NETCHECK_TIMEOUT='stale'
set_operation_config_defaults
[ "${CONFIG_LOCAL}:${CONFIG_IPSET}:${CONFIG_NETCHECK_TIMEOUT}" = 'NO:YES:300' ] || fail 'stop fallback did not initialize a complete default snapshot'

/bin/grep -q 'if ! load_operation_config action; then' "${SCRIPT_PATH}" || fail 'monitor restart does not refresh configuration'
/bin/grep -q 'if ! load_operation_config stop; then' "${SCRIPT_PATH}" || fail 'monitor stop does not refresh configuration'
/bin/grep -q 'continuing stop with conservative configuration defaults' "${SCRIPT_PATH}" || fail 'invalid configuration can still block emergency stop'
/usr/bin/awk '
	/if ! load_operation_config stop; then/ { reloaded = 1 }
	/A place to exit early if needed/ { exit !reloaded }
	END { if (!reloaded) exit 1 }
' "${SCRIPT_PATH}" || fail 'monitor stop snapshot reload occurs after the early-stop path'

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

# Repeated atomic replacements concurrent with reads always expose one complete
# inode snapshot; neither the old nor new validated value can be mixed.
printf '%s\n' 'ADGUARD_NETCHECK_TIMEOUT="30"' >"${CONF_FILE}"
(
	i=0
	while [ "${i}" -lt 20 ]; do
		printf '%s\n' 'ADGUARD_NETCHECK_TIMEOUT="30"' >"${CONF_FILE}.new" && mv "${CONF_FILE}.new" "${CONF_FILE}" || exit 1
		printf '%s\n' 'ADGUARD_NETCHECK_TIMEOUT="60"' >"${CONF_FILE}.new" && mv "${CONF_FILE}.new" "${CONF_FILE}" || exit 1
		i="$((i + 1))"
	done
) &
writer_pid="$!"
i=0
while [ "${i}" -lt 20 ]; do
	load_operation_config monitor-healthcheck || fail 'concurrent atomic replacement produced an invalid snapshot'
	case "${CONFIG_NETCHECK_TIMEOUT}" in
		30 | 60) ;;
		*) fail "concurrent replacement produced mixed value: ${CONFIG_NETCHECK_TIMEOUT}" ;;
	esac
	i="$((i + 1))"
done
wait "${writer_pid}" || fail 'concurrent atomic writer failed'

printf '%s\n' 'PASS: scoped config awk forks: start 1 (was 12), stop 1 (was 4), IPSET refresh 1 (was 3), monitor healthcheck 1 (was 7)'
