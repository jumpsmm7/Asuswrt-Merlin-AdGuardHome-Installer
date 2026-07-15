#!/bin/sh
# Verify CLI LAN-mode install and migration paths do not regress to WAN DNS/netcheck defaults.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-cli-lan-mode.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions"
CONF_FILE="${TMP_ROOT}/.config"
WRITES_FILE="${TMP_ROOT}/writes"

cleanup() {
	rm -rf "${TMP_ROOT}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"
mkdir -p "${TMP_ROOT}" || fail 'could not create test directory'

sed -n '/^cli_migrate_runtime_default() {$/,/^cli_installer_branch_from_args() {$/p' "${SCRIPT_PATH}" | sed '$d' >"${FUNCTIONS_FILE}" ||
	fail 'could not extract runtime migration helpers'
[ -s "${FUNCTIONS_FILE}" ] || fail 'runtime migration helper extraction was empty'

grep -q 'if \[ "${ADGUARD_INSTALL_MODE}" = "wan" \]; then' "${SCRIPT_PATH}" ||
	fail 'CLI install DNS preparation must be gated by WAN install mode'
grep -q '^[[:space:]]*check_dns_environment 0$' "${SCRIPT_PATH}" ||
	fail 'installer must still call DNS environment preparation for WAN paths'
grep -q 'cli_migrate_runtime_default ADGUARD_NETCHECK_MODE legacy "${netcheck_target}"' "${SCRIPT_PATH}" ||
	fail 'runtime migration must use the install-mode netcheck target'
grep -q 'cli_write_quoted_conf ADGUARD_NETCHECK_MODE "${netcheck_target}"' "${SCRIPT_PATH}" ||
	fail 'runtime migration writeback must use the install-mode netcheck target'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

INFO='Info:'
WARNING='Warning:'
ERROR='Error:'

PTXT() {
	:
}
ptxt_ok() {
	:
}
conf_value() {
	awk -v KEY="$1" '
		index($0, KEY "=") == 1 {
			VALUE = substr($0, length(KEY) + 2)
			gsub(/^"|"$/, "", VALUE)
			print VALUE
			exit
		}
	' "${CONF_FILE}"
}
cli_write_quoted_conf() {
	printf '%s=%s\n' "$1" "$2" >>"${WRITES_FILE}"
}

run_migrate_case() {
	case_name="$1"
	install_mode="$2"
	expected_netcheck="$3"

	cat >"${CONF_FILE}" <<EOF_CONF || fail "${case_name}: could not write config"
ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="1"
ADGUARD_NETCHECK_MODE="legacy"
ADGUARD_PROC_OPTIMIZE="YES"
ADGUARD_PROC_PROFILE="balanced"
EOF_CONF
	: >"${WRITES_FILE}"
	ADGUARD_INSTALL_MODE="${install_mode}"

	cli_migrate_runtime_defaults --yes || fail "${case_name}: migration failed"
	grep -q "^ADGUARD_NETCHECK_MODE=${expected_netcheck}$" "${WRITES_FILE}" ||
		fail "${case_name}: expected netcheck write ${expected_netcheck}"
	if grep -q '^ADGUARD_NETCHECK_MODE=wan$' "${WRITES_FILE}" && [ "${expected_netcheck}" != 'wan' ]; then
		fail "${case_name}: LAN migration wrote WAN netcheck mode"
	fi
}

run_migrate_case lan-mode lan lan
run_migrate_case wan-mode wan wan
run_migrate_case unknown-mode unknown wan

printf '%s\n' 'PASS: CLI LAN mode guards DNS prep and migrates netcheck by install mode'
