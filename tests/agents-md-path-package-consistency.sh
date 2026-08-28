#!/bin/sh
# Regression test for the repository's shared AI-agent guardrails. The root
# AGENTS.md is canonical; Amazon Q mirrors it exactly, while Qodo, CodeRabbit,
# and Codex may add provider-specific review workflow details without weakening
# the shared runtime, finding-threshold, PATH, or dependency rules.

set -u

CANONICAL_AGENTS='AGENTS.md'
AMAZONQ_AGENTS='.amazonq/rules/AGENTS.md'
QODO_REVIEW='REVIEW.md'
CODERABBIT='.coderabbit.yaml'
CODEX_PROMPT='.github/prompts/codex-code-improvement.md'
INSTALLER="${1:-installer}"
AGH='AdGuardHome.sh'
S99='S99AdGuardHome'
RCFUNC='rc.func.AdGuardHome'

# fail prints a failure message to stderr and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $1" >&2
	exit 1
}

# require_text verifies that a required literal guardrail remains present.
require_text() {
	file="$1"
	text="$2"
	description="$3"
	grep -Fq -e "${text}" "${file}" || fail "${file}: missing shared guardrail: ${description}"
}

for f in "${CANONICAL_AGENTS}" "${AMAZONQ_AGENTS}" "${QODO_REVIEW}" "${CODERABBIT}" "${CODEX_PROMPT}" \
	"${INSTALLER}" "${AGH}" "${S99}" "${RCFUNC}"; do
	[ -f "${f}" ] || fail "expected file not found: ${f}"
done

# Amazon Q receives its rules from .amazonq/rules. Keep that file byte-for-byte
# identical to the canonical root guardrails so authoring/fixing behavior cannot
# silently diverge from the rules used by the other agents.
cmp -s "${CANONICAL_AGENTS}" "${AMAZONQ_AGENTS}" ||
	fail "${AMAZONQ_AGENTS} must exactly mirror ${CANONICAL_AGENTS}"

require_text "${CANONICAL_AGENTS}" \
	'This file is the canonical repository guardrail set for all coding and review agents' \
	'canonical all-agent precedence declaration'
require_text "${CANONICAL_AGENTS}" \
	'verify each proposed finding against the current code before reporting or fixing it.' \
	'current-code verification before findings'
require_text "${CANONICAL_AGENTS}" \
	'Do not fill a finding quota. If no high-confidence issue exists, report no finding.' \
	'no finding quota / high-confidence threshold'
require_text "${CANONICAL_AGENTS}" \
	'Every finding should identify the exact failure condition, the practical effect, and a minimal compatible correction.' \
	'failure condition, impact, and minimal correction requirement'
require_text "${CANONICAL_AGENTS}" \
	'Shell command arguments are separated by whitespace, **not commas**.' \
	'shell argument punctuation rule'
require_text "${CANONICAL_AGENTS}" \
	'Keep quote pairs balanced.' \
	'shell quote balancing rule'
require_text "${CANONICAL_AGENTS}" \
	'Target BusyBox version: `BusyBox v1.25.1`.' \
	'BusyBox target version'
require_text "${CANONICAL_AGENTS}" \
	'`python3` for validation helpers such as `.github/scripts/fix-sonar-shell-parse.py`.' \
	'validation-host python3 allowlist'
require_text "${CANONICAL_AGENTS}" \
	'GNU coreutils `timeout` at `/usr/bin/timeout` for bounding regression and lint commands.' \
	'validation-host GNU timeout allowlist'
require_text "${CANONICAL_AGENTS}" \
	'These commands are validation-host exceptions only.' \
	'validation prerequisites excluded from router runtime'
require_text "${CANONICAL_AGENTS}" \
	'SHA-256 preflight and runtime enforcement must use the shared functional `sha256sum_available()` probe.' \
	'shared SHA-256 functional probe contract'
require_text "${CANONICAL_AGENTS}" \
	'only run the `coreutils-sha256sum` package diagnostic when Entware is available and no supported implementation works.' \
	'conditional Entware SHA-256 package diagnostic contract'

# All reviewers use the same priority order even if their provider-specific
# configuration contains additional checks.
for priority in \
	'1. Security regressions.' \
	'2. Service interruption, rollback, cleanup, or restore-path regressions.' \
	'3. BusyBox `ash` or POSIX `/bin/sh` compatibility failures.' \
	'4. Router-specific failures involving NVRAM, firewall, WAN, DNS, VPN, IPSET, or service state.' \
	'5. Install, upgrade, restore, or uninstall failures.' \
	'6. Performance regressions on constrained router hardware.' \
	'7. Maintainability concerns only when they can reasonably cause a defect.'; do
	require_text "${CANONICAL_AGENTS}" "${priority}" "canonical review priority ${priority}"
	require_text "${QODO_REVIEW}" "${priority}" "Qodo review priority ${priority}"
done

# Qodo's REVIEW.md remains its detailed reviewer contract, but it must preserve
# the same evidence threshold, BusyBox target, and minimal-fix posture.
require_text "${QODO_REVIEW}" \
	'Do not raise speculative findings that lack a concrete failure scenario.' \
	'Qodo concrete-failure threshold'
require_text "${QODO_REVIEW}" \
	'Do not fill a finding quota. When no high-confidence issue exists, return no finding.' \
	'Qodo no-quota threshold'
require_text "${QODO_REVIEW}" \
	'1. The exact failure condition.' \
	'Qodo exact failure-condition requirement'
require_text "${QODO_REVIEW}" \
	'3. A minimal compatible correction.' \
	'Qodo minimal correction requirement'
require_text "${QODO_REVIEW}" \
	'BusyBox v1.25.1' \
	'Qodo BusyBox target version'
require_text "${QODO_REVIEW}" \
	'Unquoted expansions that can split words or expand globs.' \
	'Qodo shell quoting review guardrail'

# CodeRabbit already supports repository-level path instructions. Require its
# global policy to keep delegating to the canonical file and to use the same
# reachable-defect/minimal-fix threshold.
require_text "${CODERABBIT}" \
	"Treat the repository's AGENTS.md as the primary engineering standard." \
	'CodeRabbit canonical AGENTS.md delegation'
require_text "${CODERABBIT}" \
	'Report only likely correctness, security, compatibility, state-safety,' \
	'CodeRabbit actionable-defect threshold'
require_text "${CODERABBIT}" \
	'Do not claim a theoretical issue without identifying a reachable' \
	'CodeRabbit reachable-path requirement'
require_text "${CODERABBIT}" \
	'Prefer a minimal fix over a broad refactor.' \
	'CodeRabbit minimal-fix requirement'
require_text "${CODERABBIT}" \
	'Review as production POSIX /bin/sh code running under BusyBox ash' \
	'CodeRabbit POSIX BusyBox runtime target'
require_text "${CODERABBIT}" \
	'v1.25.1 on Asuswrt-Merlin.' \
	'CodeRabbit BusyBox version target'

# Codex's provider-specific prompt must explicitly defer to the canonical file
# and apply the same current-code/high-confidence/minimal-fix review posture.
require_text "${CODEX_PROMPT}" \
	'Treat the repository-root `AGENTS.md` as the canonical engineering and review guardrail set.' \
	'Codex canonical AGENTS.md delegation'
require_text "${CODEX_PROMPT}" \
	'verify every proposed finding against the current code before reporting it.' \
	'Codex current-code verification requirement'
require_text "${CODEX_PROMPT}" \
	'Report only actionable findings with a concrete, reachable failure mode and practical impact.' \
	'Codex reachable-defect threshold'
require_text "${CODEX_PROMPT}" \
	'If no high-confidence issue exists, report no finding.' \
	'Codex no-quota threshold'
require_text "${CODEX_PROMPT}" \
	'Prefer a minimal compatible correction over a broad refactor or style rewrite.' \
	'Codex minimal-fix requirement'

# Keep the topology-specific installer hook behavior visible to every agent
# through the canonical guardrails (and the byte-identical Amazon Q mirror).
require_text "${CANONICAL_AGENTS}" \
	'LAN/AP/Bridge mode configures that `firewall-start` hook only when the router has active WAN-interface `SNAT` or `MASQUERADE` state' \
	'canonical LAN firewall hook topology policy'
require_text "${CANONICAL_AGENTS}" \
	'configure `dnsmasq.postconf` and `dnsmasq-sdn.postconf` only when `dnsmasq` is running and `/etc/dnsmasq.conf` is present' \
	'canonical dnsmasq hook availability policy'
require_text "${CANONICAL_AGENTS}" \
	'LAN/AP/Bridge setup must continue from the informational IPSET-disabled notice into YAML configuration' \
	'canonical LAN IPSET-to-YAML continuation policy'
require_text "${CANONICAL_AGENTS}" \
	'only WAN mode or LAN/AP/Bridge mode with qualifying WAN-interface NAT may write `ADGUARD_IPSET="YES"`' \
	'canonical fail-closed IPSET enablement policy'
require_text "${CANONICAL_AGENTS}" \
	'Source selectors (`-s` or `--source`) are valid qualifiers and must not disqualify a rule' \
	'canonical source-scoped WAN NAT policy'
require_text "${CANONICAL_AGENTS}" \
	'Runtime dnsmasq updates must edit a same-filesystem staged copy' \
	'canonical staged dnsmasq publication policy'
require_text "${CANONICAL_AGENTS}" \
	'WAN, LAN, and uninstall event-hook orchestration must snapshot `dnsmasq.postconf`' \
	'canonical aggregate event-hook rollback policy'
require_text "${QODO_REVIEW}" \
	'(`-s` or `--source`) is valid and must remain eligible.' \
	'Qodo source-scoped WAN NAT review policy'
require_text "${QODO_REVIEW}" \
	'Installer WAN, LAN, and uninstall orchestration must snapshot every managed' \
	'Qodo transactional publication review policy'
require_text "${QODO_REVIEW}" \
	'dnsmasq, init, service, and firewall hook plus the managed configuration before' \
	'Qodo aggregate event-hook snapshot scope'
require_text "${CODEX_PROMPT}" \
	'Preserve the topology contract: source-scoped (`-s`/`--source`) SNAT or' \
	'Codex source-selector topology policy'
require_text "${CODEX_PROMPT}" \
	'Treat runtime dnsmasq publication and installer WAN/LAN/uninstall event-hook' \
	'Codex transactional publication review policy'
require_text "${CODEX_PROMPT}" \
	'aggregate hook/config restoration after any' \
	'Codex aggregate event-hook snapshot scope'

# --- PATH contract 1: the installer's inherited-PATH contract --------------
INSTALLER_PATH_CONTRACT='export PATH="/sbin:/bin:/usr/sbin:/usr/bin${PATH:+:$PATH}"'
require_text "${CANONICAL_AGENTS}" "${INSTALLER_PATH_CONTRACT}" 'canonical installer PATH contract'
grep -Fq "${INSTALLER_PATH_CONTRACT}" "${INSTALLER}" ||
	fail "${INSTALLER}: does not export PATH using the contract documented in ${CANONICAL_AGENTS}"
require_text "${QODO_REVIEW}" \
	'The installer preserves inherited PATH entries after the trusted router and' \
	'Qodo installer inherited-PATH contract'

# --- PATH contract 2: the fixed runtime-service PATH contract ---------------
RUNTIME_PATH_CONTRACT='export PATH="/sbin:/bin:/usr/sbin:/usr/bin:/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin"'
require_text "${CANONICAL_AGENTS}" "${RUNTIME_PATH_CONTRACT}" 'canonical runtime-service PATH contract'
require_text "${QODO_REVIEW}" "${RUNTIME_PATH_CONTRACT}" 'Qodo runtime-service PATH contract'
for f in "${AGH}" "${S99}" "${RCFUNC}"; do
	grep -Fq "${RUNTIME_PATH_CONTRACT}" "${f}" ||
		fail "${f}: does not export PATH using the fixed runtime-service contract documented in ${CANONICAL_AGENTS}"
done

grep -Fq "${RUNTIME_PATH_CONTRACT}" "${INSTALLER}" &&
	fail "${INSTALLER}: unexpectedly also exports the fixed runtime-service PATH contract"

# --- Allowed Entware packages vs. actual installer usage -------------------
AGENTS_PACKAGES=$(awk '
	/^Allowed Entware packages currently referenced by the installer are:$/ { inlist = 1; next }
	inlist && /^\* `[A-Za-z0-9_-]+`$/ { print; next }
	inlist && NF == 0 { next }
	inlist { exit }
' "${CANONICAL_AGENTS}" | sed -E 's/^\* `([A-Za-z0-9_-]+)`$/\1/' | sort -u)
[ -n "${AGENTS_PACKAGES}" ] || fail "${CANONICAL_AGENTS}: could not extract any packages from the allowed Entware package list"

INSTALLER_PACKAGES=$(grep -oE '(ensure_opkg_package|preflight_check_entware_package|opkg_pkg_installed) [A-Za-z0-9_-]+' "${INSTALLER}" |
	awk '{print $2}' | sort -u)
[ -n "${INSTALLER_PACKAGES}" ] || fail "${INSTALLER}: could not find any opkg-managed package references"

[ "${AGENTS_PACKAGES}" = "${INSTALLER_PACKAGES}" ] || fail "Entware package list differs between ${CANONICAL_AGENTS} and packages actually referenced in ${INSTALLER}:
--- ${CANONICAL_AGENTS} 'Allowed Entware packages' ---
${AGENTS_PACKAGES}
--- packages referenced in ${INSTALLER} ---
${INSTALLER_PACKAGES}"

PACKAGE_COUNT=$(printf '%s\n' "${AGENTS_PACKAGES}" | grep -c '.')
[ "${PACKAGE_COUNT}" -ge 6 ] || fail "expected at least 6 allowed Entware packages, found ${PACKAGE_COUNT}: ${AGENTS_PACKAGES}"

# REVIEW.md duplicates the package list for Qodo, so require it to remain in
# lockstep with the canonical list rather than merely containing a few names.
QODO_PACKAGES=$(awk '
	/^Allowed Entware packages currently referenced by the installer are:$/ { inlist = 1; next }
	inlist && /^\* `[A-Za-z0-9_-]+`$/ { print; next }
	inlist && NF == 0 { next }
	inlist { exit }
' "${QODO_REVIEW}" | sed -E 's/^\* `([A-Za-z0-9_-]+)`$/\1/' | sort -u)
[ "${QODO_PACKAGES}" = "${AGENTS_PACKAGES}" ] ||
	fail "${QODO_REVIEW}: allowed Entware package list drifted from ${CANONICAL_AGENTS}"

ENTWARE_OPTION_CONTRACT='--force-depends --force-overwrite --force-reinstall'
require_text "${CANONICAL_AGENTS}" "${ENTWARE_OPTION_CONTRACT}" 'canonical Entware install option contract'
require_text "${AMAZONQ_AGENTS}" "${ENTWARE_OPTION_CONTRACT}" 'Amazon Q Entware install option contract'
require_text "${QODO_REVIEW}" "${ENTWARE_OPTION_CONTRACT}" 'Qodo Entware install option contract'
require_text '.coderabbit.yaml' "${ENTWARE_OPTION_CONTRACT}" 'CodeRabbit Entware install option contract'
require_text '.github/prompts/codex-code-improvement.md' "${ENTWARE_OPTION_CONTRACT}" 'Codex Entware install option contract'

# --- jq: router-stock binary, not an installed Entware package -------------
require_text "${CANONICAL_AGENTS}" '`jq`: `/usr/bin/jq`' 'jq router-stock path'
grep -Fq 'jq_path="$(which jq 2>/dev/null)"' "${INSTALLER}" ||
	fail "${INSTALLER}: expected the jq preflight check to honor the documented stock-first installer PATH"
grep -Fq 'jq_executable_usable "${jq_path}"' "${INSTALLER}" ||
	fail "${INSTALLER}: expected the jq preflight check to functionally probe the PATH-resolved jq"
printf '%s\n' "${INSTALLER_PACKAGES}" | grep -Fxq 'jq' &&
	fail "${INSTALLER}: jq is opkg-managed like an Entware package, contradicting its router-stock classification"

printf '%s\n' 'PASS: shared agent guardrails, PATH contracts, and Entware package governance remain aligned across Codex, Amazon Q, CodeRabbit, and Qodo'
