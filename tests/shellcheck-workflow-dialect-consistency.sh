#!/bin/sh
# Regression test for the ShellCheck dialect contract shared between
# .shellcheckrc, .github/workflows/shell-validation.yml, and
# tools/code-quality.sh. .shellcheckrc declares `shell=bash` as ShellCheck's
# fallback dialect (needed because BusyBox ash lacks a ShellCheck profile of
# its own), but every actual invocation in this repository must explicitly
# override that default with `-s sh` so scripts are linted against the POSIX
# sh subset the router runtime actually supports. A future edit that dropped
# the `-s sh` override in only one of the two invocation sites, changed the
# shfmt dialect in only one place, or let a job claim broader permissions
# than `contents: read`, would silently weaken CI without any other check
# noticing.

set -u

SHELLCHECKRC='.shellcheckrc'
WORKFLOW='.github/workflows/shell-validation.yml'
CODE_QUALITY='tools/code-quality.sh'

# fail prints a failure message to stderr and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $1" >&2
	exit 1
}

for f in "${SHELLCHECKRC}" "${WORKFLOW}" "${CODE_QUALITY}"; do
	[ -f "${f}" ] || fail "expected file not found: ${f}"
done

# --- .shellcheckrc structure --------------------------------------------

grep -Fq "$(printf '\t')" "${SHELLCHECKRC}" && fail "${SHELLCHECKRC}: contains a literal tab character"

[ "$(grep -c '^shell=bash$' "${SHELLCHECKRC}")" -eq 1 ] ||
	fail "${SHELLCHECKRC}: expected exactly one 'shell=bash' fallback-dialect line"

# Every non-comment, non-blank line must be either the shell= default or a
# well-formed disable=SC#### directive, so an accidental typo or stray option
# can't silently do nothing.
BAD_LINES=$(grep -vE '^(#.*|shell=bash|disable=SC[0-9]{4}|)$' "${SHELLCHECKRC}")
[ -z "${BAD_LINES}" ] || fail "${SHELLCHECKRC}: unexpected line(s) that are neither a comment, 'shell=bash', nor a 'disable=SC####' directive:
${BAD_LINES}"

DISABLE_LINES=$(grep -c '^disable=SC[0-9]\{4\}$' "${SHELLCHECKRC}")
[ "${DISABLE_LINES}" -gt 0 ] || fail "${SHELLCHECKRC}: expected at least one 'disable=SC####' directive"

DISABLE_CODES_SORTED=$(grep '^disable=SC[0-9]\{4\}$' "${SHELLCHECKRC}" | sort)
DISABLE_CODES_UNIQUE=$(printf '%s\n' "${DISABLE_CODES_SORTED}" | sort -u)
[ "${DISABLE_CODES_SORTED}" = "${DISABLE_CODES_UNIQUE}" ] ||
	fail "${SHELLCHECKRC}: contains duplicate disable=SC#### directives"

grep -Fq 'BusyBox ash' "${SHELLCHECKRC}" ||
	fail "${SHELLCHECKRC}: missing the BusyBox ash rationale comment explaining the shell=bash fallback"

# --- shell-validation.yml structure --------------------------------------

grep -Fq "$(printf '\t')" "${WORKFLOW}" && fail "${WORKFLOW}: contains a literal tab character"

# Least-privilege permissions must be declared exactly once (top level); a
# job that added its own permissions: block could silently escalate beyond
# contents: read.
[ "$(grep -c 'permissions:' "${WORKFLOW}")" -eq 1 ] ||
	fail "${WORKFLOW}: expected exactly one 'permissions:' block (top-level, least-privilege)"
grep -Fq 'contents: read' "${WORKFLOW}" || fail "${WORKFLOW}: missing 'contents: read' least-privilege permission"

for job in '  posix-syntax:' '  shellcheck:' '  checksums:' '  shfmt:'; do
	grep -Fq "${job}" "${WORKFLOW}" || fail "${WORKFLOW}: missing expected job declaration '${job}'"
done

grep -Fq 'pull_request:' "${WORKFLOW}" || fail "${WORKFLOW}: missing the pull_request trigger"
grep -Fq 'workflow_dispatch:' "${WORKFLOW}" || fail "${WORKFLOW}: missing the workflow_dispatch trigger"
grep -Fq '      - master' "${WORKFLOW}" || fail "${WORKFLOW}: missing the push trigger for the master branch"
grep -Fq "      - 'dev/**'" "${WORKFLOW}" || fail "${WORKFLOW}: missing the push trigger for dev/** branches"

grep -Fq 'tools/list-shell-scripts.sh' "${WORKFLOW}" ||
	fail "${WORKFLOW}: posix-syntax/shellcheck/shfmt jobs must enumerate scripts via tools/list-shell-scripts.sh"
grep -Fq 'tests/installer-reaper-owner-publication.sh' "${WORKFLOW}" ||
	fail "${WORKFLOW}: posix-syntax job is missing the reaper owner publication regression"

# --- Checksum target consistency within the workflow ----------------------
# The chore-commit wait step and the validation step must agree on the same
# base checksum_targets list, or the wait step could race a validation step
# checking a different set of artifacts.
CHECKSUM_BASE='checksum_targets=(installer AdGuardHome.sh S99AdGuardHome rc.func.AdGuardHome)'
[ "$(grep -Fc "${CHECKSUM_BASE}" "${WORKFLOW}")" -eq 2 ] ||
	fail "${WORKFLOW}: expected the identical base checksum_targets declaration in both the wait-for-chore-commit and validate steps"
grep -Fq 'tools/check-md5.sh' "${WORKFLOW}" || fail "${WORKFLOW}: checksums job is missing tools/check-md5.sh"
grep -Fq 'tools/check-sha256.sh' "${WORKFLOW}" || fail "${WORKFLOW}: checksums job is missing tools/check-sha256.sh"
grep -Fq 'tools/update-checksums.sh' "${WORKFLOW}" || fail "${WORKFLOW}: checksums job is missing tools/update-checksums.sh"
grep -Fq 'busybox ash tests/checksum-file-format.sh' "${WORKFLOW}" ||
	fail "${WORKFLOW}: checksums job is missing the checksum file-format regression"

# --- Dialect-override consistency between CI and local tooling ------------
# Both the CI workflow and the local code-quality runner must explicitly
# override .shellcheckrc's shell=bash default with the same flags, and use
# the same shfmt dialect flags, so a local `tools/code-quality.sh` run can't
# silently diverge from what CI enforces.
SHELLCHECK_INVOCATION='shellcheck -s sh --severity=warning'
grep -Fq "${SHELLCHECK_INVOCATION}" "${WORKFLOW}" ||
	fail "${WORKFLOW}: expected the shellcheck job to invoke '${SHELLCHECK_INVOCATION}'"
grep -Fq "${SHELLCHECK_INVOCATION}" "${CODE_QUALITY}" ||
	fail "${CODE_QUALITY}: expected the local quality runner to invoke '${SHELLCHECK_INVOCATION}'"

SHFMT_FLAGS='-ln mksh -i 0 -ci'
grep -Fq -- "${SHFMT_FLAGS}" "${WORKFLOW}" || fail "${WORKFLOW}: expected shfmt to be invoked with '${SHFMT_FLAGS}'"
grep -Fq -- "${SHFMT_FLAGS}" "${CODE_QUALITY}" || fail "${CODE_QUALITY}: expected shfmt to be invoked with '${SHFMT_FLAGS}'"

# --- Sanity check on the fixtures themselves -------------------------------
[ -n "${SHELLCHECK_INVOCATION}" ] || fail 'internal test error: SHELLCHECK_INVOCATION constant is empty'
[ -n "${SHFMT_FLAGS}" ] || fail 'internal test error: SHFMT_FLAGS constant is empty'

printf '%s\n' 'PASS: .shellcheckrc and shell-validation.yml keep the sh-dialect override, permissions, and checksum-target contracts consistent'
