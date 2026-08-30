#!/bin/sh
# Verify CLI LAN-mode install and migration paths do not regress to WAN DNS/netcheck defaults.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-cli-lan-mode.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions"
CONF_FILE="${TMP_ROOT}/.config"
WRITES_FILE="${TMP_ROOT}/writes"
LOG_FILE="${TMP_ROOT}/log"
YAML_FILE="${TMP_ROOT}/AdGuardHome.yaml"

# cleanup removes the temporary workspace used by the test script.
cleanup() {
	rm -rf "${TMP_ROOT}"
}

# fail prints a failure message to standard error and exits with status 1.
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
grep -q 'Refusing install DNS/NVRAM rewrite without --allow-dns-nvram' "${SCRIPT_PATH}" ||
	fail 'CLI install must still require DNS/NVRAM permission for WAN rewrites'
consent_line="$(grep -n 'Refusing install DNS/NVRAM rewrite without --allow-dns-nvram' "${SCRIPT_PATH}" | tail -n 1 | cut -d: -f1)"
cleanup_line="$(sed -n '/^[[:space:]]*install)$/,/^[[:space:]]*;;$/p' "${SCRIPT_PATH}" | grep -n '^[[:space:]]*cleanup$' | head -n 1 | cut -d: -f1)"
[ -n "${consent_line}" ] && [ -n "${cleanup_line}" ] ||
	fail 'could not locate CLI install consent and cleanup ordering'
install_line="$(grep -n '^[[:space:]]*install)$' "${SCRIPT_PATH}" | tail -n 1 | cut -d: -f1)"
cleanup_line="$((install_line + cleanup_line - 1))"
[ "${consent_line}" -lt "${cleanup_line}" ] ||
	fail 'CLI install must require WAN DNS/NVRAM consent before cleanup changes router state'
grep -q 'install_mode="${ADGUARD_INSTALL_MODE}"' "${SCRIPT_PATH}" ||
	fail 'runtime migration must use the confirmed detected install mode'
grep -q '^[[:space:]]*check_dns_environment 0 || return 1$' "${SCRIPT_PATH}" ||
	fail 'CLI installer must propagate WAN DNS environment preparation failures'
grep -q '^[[:space:]]*check_dns_environment 0 || exit 1$' "${SCRIPT_PATH}" ||
	fail 'interactive installer must propagate WAN DNS environment preparation failures'
grep -q 'LAN mode selected; cleared legacy firewall/IPTABLES state and skipping firewall/IPTABLES management' "${SCRIPT_PATH}" ||
	fail 'LAN-mode install must report legacy firewall cleanup before skipped firewall/IPTABLES management'
grep -q 'LAN mode selected; no legacy firewall/IPTABLES state requires cleanup' "${SCRIPT_PATH}" ||
	fail 'LAN-mode install must report when legacy firewall cleanup is unnecessary'
awk '
	/^[[:space:]]*lan\)$/ { in_lan = 1 }
	in_lan && /if legacy_firewall_cleanup_needed; then/ { guarded = 1 }
	guarded && /if ! cleanup_legacy_firewall; then/ { cleanup = 1; exit }
	END { exit(guarded && cleanup ? 0 : 1) }
' "${SCRIPT_PATH}" || fail 'LAN-mode cleanup failure handling must run only when legacy firewall state exists'
grep -q 'cleanup_legacy_firewall' "${SCRIPT_PATH}" ||
	fail 'uninstall/WAN/LAN transition cleanup must still remove legacy firewall integration'
grep -q 'cli_migrate_runtime_default ADGUARD_NETCHECK_MODE legacy "${netcheck_target}"' "${SCRIPT_PATH}" ||
	fail 'runtime migration must use the install-mode netcheck target'
grep -q 'cli_write_quoted_conf ADGUARD_NETCHECK_MODE "${netcheck_target}"' "${SCRIPT_PATH}" ||
	fail 'runtime migration writeback must use the install-mode netcheck target'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

adguardhome_yaml_ipset_file() {
	return 0
}

# adguardhome_yaml_remove_ipset_file is a no-op placeholder for removing an IP set file.
adguardhome_yaml_remove_ipset_file() {
	return 0
}

# write_conf appends a quoted key-value configuration entry to the writes file.
write_conf() {
	printf '%s="%s"\n' "$1" "$2" >>"${WRITES_FILE}"
}

INFO='Info:'
WARNING='Warning:'
ERROR='Error:'
ADGUARD_INSTALL_MODE_DETECTION='wan'

# adguard_install_mode_confirmed confirms that the detected installation mode is either `wan` or `lan`.
adguard_install_mode_confirmed() {
	case "${ADGUARD_INSTALL_MODE_DETECTION:-unknown}" in
		wan | lan) return 0 ;;
	esac
	return 1
}

# adguard_install_mode_detect determines the installation mode and succeeds.
adguard_install_mode_detect() {
	ADGUARD_INSTALL_MODE="${ADGUARD_INSTALL_MODE_DETECTION}"
	return 0
}

sed -n '/^adguard_ipset_allowed() {$/,/^}$/p' "${SCRIPT_PATH}" >"${TMP_ROOT}/ipset-allowed" ||
	fail 'could not extract IPSET eligibility helper'
[ -s "${TMP_ROOT}/ipset-allowed" ] || fail 'IPSET eligibility helper was not found'
# shellcheck disable=SC1090
. "${TMP_ROOT}/ipset-allowed"
wan_iptables_state_active() {
	[ "${WAN_NAT_ACTIVE:-0}" -eq 1 ]
}

WAN_NAT_ACTIVE=1
ADGUARD_INSTALL_MODE="lan"
adguard_ipset_allowed || fail 'lan mode rejected qualifying WAN NAT state'
WAN_NAT_ACTIVE=0
for unsupported_topology in lan ap bridge; do
	ADGUARD_INSTALL_MODE="${unsupported_topology}"
	if adguard_ipset_allowed; then
		fail "${unsupported_topology} mode accepted without qualifying WAN NAT state"
	fi
done
WAN_NAT_ACTIVE=1
for unsupported_mode in ap bridge; do
	ADGUARD_INSTALL_MODE="${unsupported_mode}"
	if adguard_ipset_allowed; then
		fail "${unsupported_mode} mode bypassed the installer's supported-mode boundary"
	fi
done

# PTXT appends the provided text followed by a newline to the log file.
PTXT() {
	printf '%s\n' "$*" >>"${LOG_FILE}"
}
# ptxt_ok is a no-op logging helper.
ptxt_ok() {
	:
}
# conf_value extracts and prints the configured value for a key from the configuration file.
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
# cli_write_quoted_conf writes a configuration key and value to the captured writes file.
cli_write_quoted_conf() {
	printf '%s=%s\n' "$1" "$2" >>"${WRITES_FILE}"
}

# run_migrate_case runs a runtime migration scenario and verifies the expected netcheck mode is written.
#
# Arguments:
#   case_name        A label used in failure messages.
#   install_mode     The installation mode supplied to the migration.
# run_migrate_case verifies that runtime migration writes the expected netcheck mode for an installation mode.
#   case_name identifies the migration test case.
#   install_mode is the installation mode under test.
# run_migrate_case runs runtime-default migration for an install mode and verifies the expected netcheck mode is written.
run_migrate_case() {
	case_name="$1"
	install_mode="$2"
	expected_netcheck="$3"

	cat >"${CONF_FILE}" <<EOF_CONF || fail "${case_name}: could not write config"
ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="1"
ADGUARD_NETCHECK_MODE="legacy"
ADGUARD_IPSET="NO"
ADGUARD_PROC_OPTIMIZE="YES"
ADGUARD_PROC_PROFILE="balanced"
EOF_CONF
	: >"${WRITES_FILE}"
	: >"${LOG_FILE}"
	ADGUARD_INSTALL_MODE="${install_mode}"
	ADGUARD_INSTALL_MODE_DETECTION="${install_mode}"

	cli_migrate_runtime_defaults --yes || fail "${case_name}: migration failed"
	grep -q "^ADGUARD_NETCHECK_MODE=${expected_netcheck}$" "${WRITES_FILE}" ||
		fail "${case_name}: expected netcheck write ${expected_netcheck}"
	if grep -q '^ADGUARD_NETCHECK_MODE=wan$' "${WRITES_FILE}" && [ "${expected_netcheck}" != 'wan' ]; then
		fail "${case_name}: LAN migration wrote WAN netcheck mode"
	fi
}

run_migrate_case lan-mode lan lan
run_migrate_case wan-mode wan wan

sed -n '/^legacy_firewall_cleanup_needed() {$/,/^}$/p' "${SCRIPT_PATH}" >"${TMP_ROOT}/legacy-firewall-check" ||
	fail 'could not extract legacy firewall state check'
(
	# shellcheck disable=SC1090
	. "${TMP_ROOT}/legacy-firewall-check"
	ADDON_DIR="${TMP_ROOT}/addon"
	iptables() {
		case "${IPTABLES_TEST_STATE}" in
			legacy)
				printf '%s\n' '-N ADGUARDHOME'
				;;
			empty)
				printf '%s\n' '-P OUTPUT ACCEPT'
				;;
			error)
				return 1
				;;
		esac
	}
	IPTABLES_TEST_STATE=legacy
	legacy_firewall_cleanup_needed || fail 'legacy firewall chain was not detected'
	IPTABLES_TEST_STATE=empty
	if legacy_firewall_cleanup_needed; then
		fail 'empty firewall state incorrectly required cleanup'
	fi
	printf '%s\n' "[ -x ${ADDON_DIR}/AdGuardHome.sh ]" >"${TMP_ROOT}/firewall-start" ||
		fail 'could not create managed firewall-start hook'
	legacy_firewall_cleanup_needed "${TMP_ROOT}/firewall-start" || fail 'managed firewall-start hook was not detected'
	IPTABLES_TEST_STATE=error
	legacy_firewall_cleanup_needed || fail 'failed firewall inspection did not require cleanup'
) || exit $?

sed -n '/^wan_iptables_state_active() {$/,/^}$/p' "${SCRIPT_PATH}" |
	sed 's#/usr/sbin/iptables#iptables#g; s#/bin/nvram#nvram#g' >"${TMP_ROOT}/wan-iptables-check" ||
	fail 'could not extract WAN IPTABLES state check'
[ -s "${TMP_ROOT}/wan-iptables-check" ] || fail 'WAN IPTABLES state check was not found'
(
	# shellcheck disable=SC1090
	. "${TMP_ROOT}/wan-iptables-check"
	# iptables prints the configured WAN NAT rule for test inspection.
	iptables() {
		printf '%s\n' "${WAN_NAT_RULE:-}"
	}
	# nvram returns predefined WAN interface names for supported get queries.
	nvram() {
		case "$1:$2" in
			get:wan0_ifname) printf '%s\n' 'eth0' ;;
			get:wan1_ifname) printf '%s\n' 'eth1' ;;
		esac
	}
	WAN_NAT_RULE='-A POSTROUTING -o eth0 -j MASQUERADE'
	wan_iptables_state_active || fail 'active WAN MASQUERADE state was not detected'
	WAN_NAT_RULE='-A POSTROUTING -o eth0 -j SNAT --to-source 192.0.2.2'
	wan_iptables_state_active || fail 'active WAN SNAT state was not detected'
	WAN_NAT_RULE='-A POSTROUTING ! -o eth0 -j MASQUERADE'
	if wan_iptables_state_active; then
		fail 'negated WAN interface NAT state was detected as active WAN state'
	fi
	WAN_NAT_RULE='-A POSTROUTING -s 192.168.50.0/24 -o eth0 -j MASQUERADE'
	wan_iptables_state_active || fail 'source-scoped WAN MASQUERADE state was not detected'
	WAN_NAT_RULE='-A POSTROUTING --source 192.168.50.0/24 -o eth0 -j SNAT --to-source 192.0.2.2'
	wan_iptables_state_active || fail 'long-form source-scoped WAN SNAT state was not detected'
	WAN_NAT_RULE='-A POSTROUTING -o eth1 -j MASQUERADE'
	wan_iptables_state_active || fail 'wan1 MASQUERADE state was not detected'
	WAN_NAT_RULE='-A POSTROUTING -o eth2 -j MASQUERADE'
	if wan_iptables_state_active; then
		fail 'non-WAN eth2 NAT state was detected as active WAN state'
	fi
	WAN_NAT_RULE='-A POSTROUTING -m comment --comment "-o eth0 -j MASQUERADE" -o eth2 -j ACCEPT'
	if wan_iptables_state_active; then
		fail 'WAN NAT markers inside a comment were detected as active WAN state'
	fi
	WAN_NAT_RULE='-A POSTROUTING -i br1 -o eth0 -j MASQUERADE'
	if wan_iptables_state_active; then
		fail 'guest-network input-interface NAT state was detected as active WAN state'
	fi
	WAN_NAT_RULE='-A POSTROUTING -o br0 -j ACCEPT'
	if wan_iptables_state_active; then
		fail 'non-NAT LAN IPTABLES state was detected as active WAN state'
	fi
	WAN_NAT_RULE='-A POSTROUTING -o tun11 -j MASQUERADE'
	if wan_iptables_state_active; then
		fail 'NAT state on a non-WAN interface was detected as active WAN state'
	fi
) || exit $?

cat >"${CONF_FILE}" <<EOF_CONF || fail 'dry-run persisted LAN: could not write config'
ADGUARD_INSTALL_MODE="lan"
ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="1"
ADGUARD_NETCHECK_MODE="legacy"
ADGUARD_IPSET="NO"
ADGUARD_PROC_OPTIMIZE="YES"
ADGUARD_PROC_PROFILE="balanced"
EOF_CONF
: >"${WRITES_FILE}"
: >"${LOG_FILE}"
ADGUARD_INSTALL_MODE_DETECTION='lan'
cli_migrate_runtime_defaults --dry-run || fail 'dry-run persisted LAN: migration preview failed'
grep -q 'ADGUARD_NETCHECK_MODE="legacy"; v2.6.0 safer value is "lan"' "${LOG_FILE}" ||
	fail 'dry-run persisted LAN: expected LAN netcheck preview'
if grep -q 'ADGUARD_NETCHECK_MODE="legacy"; v2.6.0 safer value is "wan"' "${LOG_FILE}"; then
	fail 'dry-run persisted LAN: preview regressed to WAN netcheck mode'
fi
[ ! -s "${WRITES_FILE}" ] || fail 'dry-run persisted LAN: dry-run wrote config'

printf '%s\n' 'PASS: CLI LAN mode guards DNS prep and migrates netcheck by install mode'
