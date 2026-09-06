#!/bin/sh
# Confirms installer and runtime WAN NAT predicates make identical decisions.

set -u

fail() {
	printf '%s\n' "FAIL: $1" >&2
	exit 1
}

INSTALLER_PATH="${1:-installer}"
RUNTIME_PATH="${2:-AdGuardHome.sh}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/wan-nat-parity.XXXXXX")" || fail 'could not create test directory'
trap 'rm -rf "${TEST_ROOT}"' EXIT HUP INT TERM

extract_predicate() {
	awk -v source_name="$1" -v target_name="$2" '
		$0 == source_name "() {" { active = 1; sub(source_name "\\(\\)", target_name "()") }
		active { print }
		active && $0 == "}" { exit }
	' "$3" |
		sed 's|/usr/sbin/iptables|test_iptables|g; s|/bin/nvram|test_nvram|g'
}

extract_predicate wan_iptables_state_active installer_predicate "${INSTALLER_PATH}" >"${TEST_ROOT}/installer" ||
	fail 'could not extract installer predicate'
extract_predicate adguard_wan_iptables_state_active runtime_predicate "${RUNTIME_PATH}" >"${TEST_ROOT}/runtime" ||
	fail 'could not extract runtime predicate'
[ -s "${TEST_ROOT}/installer" ] && [ -s "${TEST_ROOT}/runtime" ] || fail 'WAN NAT predicate extraction was empty'
. "${TEST_ROOT}/installer"
. "${TEST_ROOT}/runtime"

test_iptables() {
	[ "$*" = '-t nat -S POSTROUTING' ] || fail "unexpected iptables query: $*"
	printf '%s\n' "${WAN_NAT_RULE:-}"
	[ "${IPTABLES_FAIL:-0}" -eq 0 ]
}

test_nvram() {
	case "$1:$2" in
		get:wan0_ifname) printf '%s\n' eth0 ;;
		get:wan1_pppoe_ifname) printf '%s\n' ppp1 ;;
	esac
}

check_case() {
	installer_status=0
	runtime_status=0
	installer_predicate || installer_status=$?
	runtime_predicate || runtime_status=$?
	[ "${installer_status}" -eq "${runtime_status}" ] ||
		fail "predicate mismatch for ${WAN_NAT_RULE:-iptables failure}"
	[ "${installer_status}" -eq "$1" ] || fail "unexpected predicate result for ${WAN_NAT_RULE:-iptables failure}"
}

WAN_NAT_RULE='-A POSTROUTING -o eth0 -j MASQUERADE'
check_case 0
WAN_NAT_RULE='-A POSTROUTING -s 192.168.50.0/24 -o ppp1 -j SNAT --to-source 192.0.2.1'
check_case 0
WAN_NAT_RULE='-A POSTROUTING --source 192.168.50.0/24 -o ppp1 -j SNAT --to-source 192.0.2.1'
check_case 0
WAN_NAT_RULE='-A POSTROUTING ! -o eth0 -j MASQUERADE'
check_case 1
WAN_NAT_RULE='-A POSTROUTING -i br1 -o eth0 -j MASQUERADE'
check_case 1
WAN_NAT_RULE='-A POSTROUTING -o br0 -j ACCEPT -m comment --comment "ignored -o eth0 -j MASQUERADE tail"'
check_case 1
WAN_NAT_RULE='-A POSTROUTING -m comment --comment "escaped \" -o eth0 -j MASQUERADE trailing" -j RETURN'
check_case 1
WAN_NAT_RULE='-A POSTROUTING -m comment --comment " -o eth0 -j MASQUERADE trailing" -j RETURN'
check_case 1
WAN_NAT_RULE='-A POSTROUTING -o tun0 -j MASQUERADE'
check_case 1
IPTABLES_FAIL=1
WAN_NAT_RULE='-A POSTROUTING -o eth0 -j MASQUERADE'
check_case 1

printf '%s\n' 'PASS: installer and runtime WAN NAT predicates remain in parity'
