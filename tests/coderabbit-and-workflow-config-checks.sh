#!/bin/sh
# Regression test for .coderabbit.yaml and the code-quality workflows.
# These files are not shell code, so shellcheck/shfmt never look at them; this is
# the only guard against YAML-breaking tab indentation and against the
# checked-in review/CI configuration silently drifting away from the files
# and scripts it is supposed to cover.

set -u

CODERABBIT='.coderabbit.yaml'
WORKFLOW='.github/workflows/code-quality.yml'
REVIEW_WORKFLOW='.github/workflows/code-quality-review.yml'
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/workflow-config-checks.XXXXXX")" || {
	printf '%s\n' 'FAIL: could not create workflow regression workspace' >&2
	exit 1
}

# fail reports a failure message to standard error and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $1" >&2
	exit 1
}

trap 'rm -rf "${TMP_ROOT}"' 0
trap 'rm -rf "${TMP_ROOT}"; exit 1' HUP INT TERM

# review_checker_is_enforced verifies that the shared checker runs directly and
# that neither its step nor its local-quality job suppresses a failure.
review_checker_is_enforced() {
	_review_workflow="$1"
	grep -Fxq '        run: sh tools/code-quality.sh' "${_review_workflow}" || return 1
	grep -Fq 'run: sh tools/code-quality.sh || true' "${_review_workflow}" && return 1
	awk '
		/^  local-quality:$/ { in_job = 1; saw_job = 1; next }
		in_job && /^  [a-zA-Z0-9_-]+:$/ { in_job = 0; in_checker_step = 0 }
		in_job && /^    continue-on-error:[[:space:]]*true([[:space:]]|$)/ { exit 1 }
		in_job && /^      - name: Run local code quality checks$/ { in_checker_step = 1; saw_checker_step = 1; next }
		in_checker_step && /^      - name:/ { in_checker_step = 0 }
		in_checker_step && /^        continue-on-error:[[:space:]]*true([[:space:]]|$)/ { exit 1 }
		in_checker_step && /^        run: sh tools\/code-quality\.sh$/ { saw_checker_command = 1 }
		END { if (!saw_job || !saw_checker_step || !saw_checker_command) exit 1 }
	' "${_review_workflow}"
}

for f in "${CODERABBIT}" "${WORKFLOW}" "${REVIEW_WORKFLOW}"; do
	[ -f "${f}" ] || fail "expected config file not found: ${f}"
done

# --- Neither file may contain literal tab characters: YAML block scalars and
# GitHub Actions both treat tabs as invalid/undefined indentation, and a tab
# introduced by an editor would not be caught by any shell-focused linter.
TAB=$(printf '\t')
for f in "${CODERABBIT}" "${WORKFLOW}" "${REVIEW_WORKFLOW}"; do
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
	inperm && /^[[:space:]]+[a-zA-Z_-]+:/ { count++ }
	END { exit !(found && count == 1) }
' "${WORKFLOW}" || fail "${WORKFLOW}: expected least-privilege 'contents: read' under the top-level permissions block"

# --- The workflow's own 'run: sh tools/code-quality.sh' invocation must point
# at a script that actually exists and is itself the orchestrator that runs
# the full regression suite; a rename of that script would otherwise leave CI
# silently green while running nothing.
grep -Fq 'sh tools/code-quality.sh' "${WORKFLOW}" || fail "${WORKFLOW}: expected the quality job to run 'sh tools/code-quality.sh'"
[ -f 'tools/code-quality.sh' ] || fail "tools/code-quality.sh referenced by ${WORKFLOW} does not exist"

# --- The advisory review workflow must exercise the same orchestrator and
# allow its status to fail the job. Keeping a second, best-effort list of
# linters or forcing exit 0 can hide a broken regression pathway.
review_checker_is_enforced "${REVIEW_WORKFLOW}" ||
	fail "${REVIEW_WORKFLOW}: shared checker failures must propagate from the review job"
if grep -Eq 'shellcheck .*\|\| true|shfmt .*\|\| true|exit 0' "${REVIEW_WORKFLOW}"; then
	fail "${REVIEW_WORKFLOW}: quality failures must propagate to the review job"
fi
grep -Fq 'sudo apt-get install -y shellcheck shfmt ripgrep dnsmasq' "${REVIEW_WORKFLOW}" ||
	fail "${REVIEW_WORKFLOW}: expected the same host-side dependencies as the blocking quality workflow"

# Each supported suppression form must independently make the validator fail.
sed 's@run: sh tools/code-quality.sh$@run: sh tools/code-quality.sh || true@' "${REVIEW_WORKFLOW}" >"${TMP_ROOT}/checker-or-true.yml" ||
	fail 'could not create checker || true workflow fixture'
if review_checker_is_enforced "${TMP_ROOT}/checker-or-true.yml"; then
	fail 'review workflow validation accepted || true on the shared checker'
fi
awk '{
	print
	if ($0 == "      - name: Run local code quality checks") print "        continue-on-error: true"
}' "${REVIEW_WORKFLOW}" >"${TMP_ROOT}/checker-continue-on-error.yml" ||
	fail 'could not create checker continue-on-error workflow fixture'
if review_checker_is_enforced "${TMP_ROOT}/checker-continue-on-error.yml"; then
	fail 'review workflow validation accepted continue-on-error on the checker step'
fi
awk '{
	print
	if ($0 == "  local-quality:") print "    continue-on-error: true"
}' "${REVIEW_WORKFLOW}" >"${TMP_ROOT}/job-continue-on-error.yml" ||
	fail 'could not create job continue-on-error workflow fixture'
if review_checker_is_enforced "${TMP_ROOT}/job-continue-on-error.yml"; then
	fail 'review workflow validation accepted continue-on-error on the checker job'
fi
sed 's/^  local-quality:$/  renamed-quality:/' "${REVIEW_WORKFLOW}" >"${TMP_ROOT}/misplaced-checker.yml" ||
	fail 'could not create misplaced checker workflow fixture'
if review_checker_is_enforced "${TMP_ROOT}/misplaced-checker.yml"; then
	fail 'review workflow validation accepted the shared checker outside the required job'
fi

# --- The workflow must run on pull_request and push to guard both the PR and
# the branch it merges into; dropping either trigger would silently reduce
# coverage without any other check noticing.
grep -Eq '^[[:space:]]*pull_request:' "${WORKFLOW}" || fail "${WORKFLOW}: expected an 'on: pull_request' trigger"
grep -Eq '^[[:space:]]*push:' "${WORKFLOW}" || fail "${WORKFLOW}: expected an 'on: push' trigger"

printf '%s\n' 'PASS: .coderabbit.yaml and code-quality workflows keep required structure and execute real checks'
