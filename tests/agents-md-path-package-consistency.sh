#!/bin/sh
# Regression test for .amazonq/rules/AGENTS.md's factual claims about this
# repository's PATH contracts and Entware package governance. AGENTS.md is
# read by AI reviewers/agents as ground truth about the codebase; if its
# documented PATH exports or "Allowed Entware packages" list ever drifted
# from what the scripts actually do, reviewers would silently give incorrect
# guidance (e.g. flagging a legitimate opkg install as undocumented, or
# missing a real router-stock-vs-Entware-fallback ambiguity) without any
# other check noticing, since AGENTS.md is prose, not executable code.

set -u

AGENTS='.amazonq/rules/AGENTS.md'
INSTALLER="${1:-installer}"
AGH='AdGuardHome.sh'
S99='S99AdGuardHome'
RCFUNC='rc.func.AdGuardHome'

# fail prints a failure message to stderr and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $1" >&2
	exit 1
}

for f in "${AGENTS}" "${INSTALLER}" "${AGH}" "${S99}" "${RCFUNC}"; do
	[ -f "${f}" ] || fail "expected file not found: ${f}"
done

# --- PATH contract 1: the installer's inherited-PATH contract --------------
# AGENTS.md documents this exact export for the installer; it must match the
# installer's real export byte-for-byte, since the doc is what reviewers use
# to judge whether a PATH change is a regression.
INSTALLER_PATH_CONTRACT='export PATH="/sbin:/bin:/usr/sbin:/usr/bin${PATH:+:$PATH}"'
grep -Fq "${INSTALLER_PATH_CONTRACT}" "${AGENTS}" ||
	fail "${AGENTS}: missing the documented installer PATH contract: ${INSTALLER_PATH_CONTRACT}"
grep -Fq "${INSTALLER_PATH_CONTRACT}" "${INSTALLER}" ||
	fail "${INSTALLER}: does not export PATH using the contract documented in ${AGENTS}"

# --- PATH contract 2: the fixed runtime-service PATH contract ---------------
# The three runtime service scripts must all use the identical fixed PATH
# (no inherited PATH) documented in AGENTS.md.
RUNTIME_PATH_CONTRACT='export PATH="/sbin:/bin:/usr/sbin:/usr/bin:/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin"'
grep -Fq "${RUNTIME_PATH_CONTRACT}" "${AGENTS}" ||
	fail "${AGENTS}: missing the documented runtime-service PATH contract: ${RUNTIME_PATH_CONTRACT}"
for f in "${AGH}" "${S99}" "${RCFUNC}"; do
	grep -Fq "${RUNTIME_PATH_CONTRACT}" "${f}" ||
		fail "${f}: does not export PATH using the fixed runtime-service contract documented in ${AGENTS}"
done

# The installer's PATH must never itself use the fixed runtime contract (it
# must keep inheriting PATH), or the two documented contracts would collapse
# into one and the "installer inherits, services don't" guidance would be
# meaningless.
grep -Fq "${RUNTIME_PATH_CONTRACT}" "${INSTALLER}" &&
	fail "${INSTALLER}: unexpectedly also exports the fixed runtime-service PATH contract"

# --- Allowed Entware packages vs. actual installer usage -------------------
# Extract the bulleted package list under the "Allowed Entware packages"
# heading in AGENTS.md, independent of any hardcoded copy, so this test
# tracks the real doc content.
AGENTS_PACKAGES=$(awk '
	/^Allowed Entware packages currently referenced by the installer are:$/ { inlist = 1; next }
	inlist && /^\* `[A-Za-z0-9_-]+`$/ { print; next }
	inlist && NF == 0 { next }
	inlist { exit }
' "${AGENTS}" | sed -E 's/^\* `([A-Za-z0-9_-]+)`$/\1/' | sort -u)
[ -n "${AGENTS_PACKAGES}" ] || fail "${AGENTS}: could not extract any packages from the 'Allowed Entware packages' list"

# Extract every literal package name actually passed to the installer's own
# opkg-management helpers, rather than reimplementing the installer's logic.
INSTALLER_PACKAGES=$(grep -oE '(ensure_opkg_package|preflight_check_entware_package|opkg_pkg_installed) [A-Za-z0-9_-]+' "${INSTALLER}" |
	awk '{print $2}' | sort -u)
[ -n "${INSTALLER_PACKAGES}" ] || fail "${INSTALLER}: could not find any opkg-managed package references"

[ "${AGENTS_PACKAGES}" = "${INSTALLER_PACKAGES}" ] || fail "Entware package list differs between ${AGENTS} and packages actually referenced in ${INSTALLER}:
--- ${AGENTS} 'Allowed Entware packages' ---
${AGENTS_PACKAGES}
--- packages referenced in ${INSTALLER} ---
${INSTALLER_PACKAGES}"

# Sanity check on the extraction itself, so a future edit that empties both
# lists in tandem can't silently pass this comparison.
PACKAGE_COUNT=$(printf '%s\n' "${AGENTS_PACKAGES}" | grep -c '.')
[ "${PACKAGE_COUNT}" -ge 6 ] || fail "expected at least 6 allowed Entware packages, found ${PACKAGE_COUNT}: ${AGENTS_PACKAGES}"

# --- jq: router-stock binary, not an installed Entware package -------------
# AGENTS.md documents jq as a router-stock binary at a fixed path rather than
# an Entware package; the installer's own stock-path probe must agree, and jq
# must never appear in the opkg-managed package extraction above (it would
# contradict the "router-stock binary" classification).
grep -Fq '`jq`: `/usr/bin/jq`' "${AGENTS}" ||
	fail "${AGENTS}: expected jq to be documented as a router-stock binary at /usr/bin/jq"
grep -Fq '[ -x /usr/bin/jq ]' "${INSTALLER}" ||
	fail "${INSTALLER}: expected the jq preflight check to probe the router-stock path /usr/bin/jq documented in ${AGENTS}"
printf '%s\n' "${INSTALLER_PACKAGES}" | grep -Fxq 'jq' &&
	fail "${INSTALLER}: jq is opkg-managed like an Entware package, contradicting its 'router-stock binary' classification in ${AGENTS}"

printf '%s\n' 'PASS: AGENTS.md PATH contracts and Entware package governance list stay consistent with the installer and runtime scripts'