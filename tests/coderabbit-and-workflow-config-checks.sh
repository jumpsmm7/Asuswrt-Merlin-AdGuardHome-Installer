#!/bin/sh
# Regression test for .coderabbit.yaml and .github/workflows/code-quality.yml.
# Neither file is shell code, so shellcheck/shfmt never look at them; this is
# the only guard against YAML-breaking tab indentation and against the
# checked-in review/CI configuration silently drifting away from the files
# and scripts it is supposed to cover.

set -u

CODERABBIT='.coderabbit.yaml'
WORKFLOW='.github/workflows/code-quality.yml'

fail() {
	printf '%s\n' "FAIL: $1" >&2
	exit 1
}

for f in "${CODERABBIT}" "${WORKFLOW}"; do
	[ -f "${f}" ] || fail "expected config file not found: ${f}"
done

# --- Neither file may contain literal tab characters: YAML block scalars and
# GitHub Actions both treat tabs as invalid/undefined indentation, and a tab
# introduced by an editor would not be caught by any shell-focused linter.
TAB=$(printf '\t')
for f in "${CODERABBIT}" "${WORKFLOW}"; do
	if grep -Fq "${TAB}" "${f}"; then
		fail "${f}: contains literal tab character(s); YAML/workflow indentation must use spaces"
	fi
done

# --- .coderabbit.yaml must declare its expected top-level sections. A typo
# introduced while editing one section (e.g. accidentally re-indenting
# 'reviews:' under 'chat:') would otherwise only be caught by CodeRabbit's own
# schema validation at review time, not by any repository check.
for key in language early_access reviews chat knowledge_base; do
	grep -Eq "^${key}:" "${CODERABBIT}" || fail "${CODERABBIT}: missing expected top-level key '${key}:'"
done

# --- The literal (non-glob) path_instructions entry for the installer must
# keep pointing at a file that actually exists, so a future rename of the
# installer script doesn't silently drop it from targeted review guidance.
grep -Fq 'path: "installer"' "${CODERABBIT}" || fail "${CODERABBIT}: expected a literal path_instructions entry for \"installer\""
[ -f 'installer' ] || fail "installer file referenced by ${CODERABBIT} does not exist"

# --- Generated checksum artifacts must stay excluded from review, matching
# the repository's convention that checksums are CI-generated, not authored.
grep -Fq '"!**/*.md5sum"' "${CODERABBIT}" || fail "${CODERABBIT}: expected path_filters to exclude **/*.md5sum"
grep -Fq '"!**/*.sha256sum"' "${CODERABBIT}" || fail "${CODERABBIT}: expected path_filters to exclude **/*.sha256sum"

# --- The workflow must declare least-privilege permissions at the top level
# (contents: read only), matching the .coderabbit.yaml workflow guidance that
# forbids broader-than-necessary permissions.
grep -Eq '^permissions:' "${WORKFLOW}" || fail "${WORKFLOW}: missing top-level 'permissions:' block"
awk '
	/^permissions:/ { inperm = 1; next }
	inperm && /^[a-zA-Z]/ { exit }
	inperm && /contents:[[:space:]]*read/ { found = 1 }
	END { exit !found }
' "${WORKFLOW}" || fail "${WORKFLOW}: expected least-privilege 'contents: read' under the top-level permissions block"

# --- The workflow's own 'run: sh tools/code-quality.sh' invocation must point
# at a script that actually exists and is itself the orchestrator that runs
# the full regression suite; a rename of that script would otherwise leave CI
# silently green while running nothing.
grep -Fq 'sh tools/code-quality.sh' "${WORKFLOW}" || fail "${WORKFLOW}: expected the quality job to run 'sh tools/code-quality.sh'"
[ -f 'tools/code-quality.sh' ] || fail "tools/code-quality.sh referenced by ${WORKFLOW} does not exist"

# --- The workflow must run on pull_request and push to guard both the PR and
# the branch it merges into; dropping either trigger would silently reduce
# coverage without any other check noticing.
grep -Eq '^[[:space:]]*pull_request:' "${WORKFLOW}" || fail "${WORKFLOW}: expected an 'on: pull_request' trigger"
grep -Eq '^[[:space:]]*push:' "${WORKFLOW}" || fail "${WORKFLOW}: expected an 'on: push' trigger"

printf '%s\n' 'PASS: .coderabbit.yaml and code-quality.yml keep required structure and stay pointed at real files'