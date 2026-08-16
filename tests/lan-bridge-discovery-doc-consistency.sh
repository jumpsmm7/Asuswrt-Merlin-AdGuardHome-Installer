#!/bin/sh
# Verify README.md and WIKI.md claims about LAN secondary-bridge DNS discovery
# match the actual AdGuardHome.sh implementation.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
README_PATH="${2:-README.md}"
WIKI_PATH="${3:-WIKI.md}"
TMP_ROOT="${TMPDIR:-/tmp}/lan-bridge-discovery-doc-consistency.$$"
BRIDGE_FUNCTION_FILE="${TMP_ROOT}/private_ipv4_bridge_dns_options"

# cleanup removes the temporary test directory and its contents.
cleanup() {
	rm -rf "${TMP_ROOT}"
}

# fail reports a failure message to standard error and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

[ -f "${SCRIPT_PATH}" ] || fail "script not found: ${SCRIPT_PATH}"
[ -f "${README_PATH}" ] || fail "README not found: ${README_PATH}"
[ -f "${WIKI_PATH}" ] || fail "WIKI not found: ${WIKI_PATH}"
mkdir -p "${TMP_ROOT}" || fail 'could not create test directory'

sed -n '/^private_ipv4_bridge_dns_options() {$/,/^}$/p' "${SCRIPT_PATH}" >"${BRIDGE_FUNCTION_FILE}" ||
	fail 'could not extract private_ipv4_bridge_dns_options'
[ -s "${BRIDGE_FUNCTION_FILE}" ] || fail 'private_ipv4_bridge_dns_options extraction was empty'

# The unstable-address exclusion flags used by the awk filters must each be
# documented in README.md, either by the kernel flag name or its plain-English
# equivalent (e.g. "duplicate" for the dadfailed flag). WIKI.md intentionally
# summarizes this as "stable" rather than enumerating every excluded flag.
for term in tentative deprecated temporary mngtmpaddr; do
	grep -q "${term}" "${SCRIPT_PATH}" || fail "AdGuardHome.sh no longer excludes ${term} addresses"
	grep -qi "${term}" "${README_PATH}" || fail "README.md does not document the ${term} exclusion"
done
grep -q 'dadfailed' "${SCRIPT_PATH}" || fail 'AdGuardHome.sh no longer excludes dadfailed addresses'
grep -qi 'duplicate' "${README_PATH}" || fail 'README.md does not document the dadfailed (duplicate address) exclusion'
grep -qi 'stable' "${WIKI_PATH}" || fail 'WIKI.md no longer documents that only stable addresses are selected'

# README.md documents that secondary-bridge selection is not merely an RFC 1918
# prefix match, so the implementation must not gate it on a private-prefix check.
grep -q 'RFC 1918' "${README_PATH}" || fail 'README.md no longer documents the RFC 1918 disclaimer'
! grep -q 'function private_ip(' "${BRIDGE_FUNCTION_FILE}" ||
	fail 'private_ipv4_bridge_dns_options still gates secondary bridges on a private IPv4 prefix, contradicting README.md'
grep -q 'function usable_ip(' "${BRIDGE_FUNCTION_FILE}" ||
	fail 'private_ipv4_bridge_dns_options no longer uses the documented usable_ip filter'

# README.md and WIKI.md both claim discovered secondary bridge pairs are logged;
# the implementation must actually emit a bridge_discovery log event.
grep -q 'bridge_discovery' "${BRIDGE_FUNCTION_FILE}" || fail 'private_ipv4_bridge_dns_options no longer logs discovered bridge pairs'
grep -qi 'logs every selected' "${README_PATH}" || fail 'README.md no longer documents that bridge discovery is logged'
grep -qi 'logged' "${WIKI_PATH}" || fail 'WIKI.md no longer documents that bridge discovery is logged'

# README.md documents that LAN mode installs no firewall/IPTABLES rules; verify
# adguard_refresh_lan_bind_addresses (the function that writes bind hosts) does
# not itself invoke iptables.
sed -n '/^adguard_refresh_lan_bind_addresses() {$/,/^}$/p' "${SCRIPT_PATH}" >"${TMP_ROOT}/refresh_function" ||
	fail 'could not extract adguard_refresh_lan_bind_addresses'
! grep -qi 'iptables' "${TMP_ROOT}/refresh_function" ||
	fail 'adguard_refresh_lan_bind_addresses unexpectedly manages firewall rules, contradicting the documented independence of binding and firewall policy'
grep -qi 'firewall' "${README_PATH}" || fail 'README.md no longer documents the firewall/binding independence disclaimer'
grep -qi 'firewall' "${WIKI_PATH}" || fail 'WIKI.md no longer documents the firewall/binding independence disclaimer'

printf '%s\n' 'PASS: README.md and WIKI.md LAN bridge discovery documentation matches AdGuardHome.sh behavior'