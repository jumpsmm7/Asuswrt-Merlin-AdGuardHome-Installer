#!/bin/sh
# Regression test for .coderabbit.yaml and the code-quality workflows.
# These files are not shell code, so shellcheck/shfmt never look at them; this is
# the only guard against YAML-breaking tab indentation and against the
# checked-in review/CI configuration silently drifting away from the files
# and scripts it is supposed to cover.

set -u

CODERABBIT='.coderabbit.yaml'
CODEX_PROMPT='.github/prompts/codex-code-improvement.md'
WORKFLOW='.github/workflows/code-quality.yml'
REVIEW_WORKFLOW='.github/workflows/code-quality-review.yml'
SHELL_VALIDATION_WORKFLOW='.github/workflows/shell-validation.yml'
TZDATA_WORKFLOW='.github/workflows/update-tzdata.yml'
LOCAL_QUALITY_RUNNER='tools/code-quality.sh'
LOCAL_QUALITY_TEST='tests/code-quality-checks.sh'
CACHE_WORKFLOW='.github/workflows/cache-adguardhome-static.yml'
SCORECARD_WORKFLOW='.github/workflows/scorecard.yml'
SONAR_REWRITE='.github/scripts/fix-sonar-shell-parse.py'
SEMGREP='.semgrep.yml'
SONAR='sonar-project.properties'
STATIC_DOWNLOADER='tools/download-adguardhome-static.sh'
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

# review_checker_is_enforced verifies that the review workflow runs the local quality checker in the local-quality job without suppressing failures.
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

for f in "${CODERABBIT}" "${CODEX_PROMPT}" "${WORKFLOW}" "${REVIEW_WORKFLOW}" "${SHELL_VALIDATION_WORKFLOW}" "${TZDATA_WORKFLOW}" "${CACHE_WORKFLOW}" "${SCORECARD_WORKFLOW}" "${SONAR_REWRITE}" "${SEMGREP}" "${SONAR}" "${STATIC_DOWNLOADER}"; do
	[ -f "${f}" ] || fail "expected config file not found: ${f}"
done

# --- Neither file may contain literal tab characters: YAML block scalars and
# GitHub Actions both treat tabs as invalid/undefined indentation, and a tab
# introduced by an editor would not be caught by any shell-focused linter.
TAB=$(printf '\t')
for f in "${CODERABBIT}" "${CODEX_PROMPT}" "${WORKFLOW}" "${REVIEW_WORKFLOW}" "${SHELL_VALIDATION_WORKFLOW}" "${TZDATA_WORKFLOW}" "${SCORECARD_WORKFLOW}"; do
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

# --- BusyBox review guidance must live in the shared path block so it applies
# to both *.sh files and every extensionless runtime script in the inventory.
SHARED_INSTRUCTIONS="${TMP_ROOT}/shared-instructions"
awk '
	/^    - path: "\*\*\/\*"$/ { in_shared = 1; next }
	in_shared && /^    - path:/ { exit }
	in_shared { print }
' "${CODERABBIT}" >"${SHARED_INSTRUCTIONS}" || fail "could not extract shared CodeRabbit instructions"
[ -s "${SHARED_INSTRUCTIONS}" ] || fail "${CODERABBIT}: shared path instructions are empty"
for expected in \
	'`set -o pipefail`' \
	'`${var//...}`' \
	'`read -a`' \
	'GNU-only `sed`, `find`, `xargs`, `date`, or `grep` flags' \
	'`local NAME="$(command)"`' \
	'`sleep N` and `sleep Ns`' \
	'attacker-influenced PATH' \
	'New unconditional `flock` acquisition' \
	'New runtime dependencies on Python, Perl, `realpath`, or `timeout`'; do
	grep -Fq "${expected}" "${SHARED_INSTRUCTIONS}" || fail "${CODERABBIT}: shared path scope is missing targeted review guidance: ${expected}"
done
for runtime_script in installer S99AdGuardHome rc.func.AdGuardHome; do
	grep -Fq "\`${runtime_script}\`" "${SHARED_INSTRUCTIONS}" ||
		fail "${CODERABBIT}: shared shell guidance does not name extensionless runtime script ${runtime_script}"
done
grep -Fq 'Do not require absolute' "${SHARED_INSTRUCTIONS}" ||
	fail "${CODERABBIT}: command-path guidance would create noisy absolute-path findings"
grep -Fq '`.md5sum` and `.sha256sum` sidecars' "${SHARED_INSTRUCTIONS}" ||
	fail "${CODERABBIT}: shared review guidance must check both runtime artifact checksum formats"
if ! grep -Fq '`.md5sum` and' "${CODEX_PROMPT}" || ! grep -Fq '`.sha256sum` updates' "${CODEX_PROMPT}"; then
	fail "${CODEX_PROMPT}: Codex guidance must check both runtime artifact checksum formats"
fi

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
grep -Fq 'sudo apt-get install -y shellcheck shfmt ripgrep dnsmasq python3 coreutils' "${REVIEW_WORKFLOW}" ||
	fail "${REVIEW_WORKFLOW}: expected the same host-side dependencies as the blocking quality workflow"
grep -Fq 'python3 --version' "${REVIEW_WORKFLOW}" ||
	fail "${REVIEW_WORKFLOW}: expected the validation-host python3 prerequisite check"
grep -Fq '/usr/bin/timeout --version' "${REVIEW_WORKFLOW}" ||
	fail "${REVIEW_WORKFLOW}: expected the approved GNU timeout prerequisite check"
[ "$(grep -Fc -- '--connect-timeout 10 --max-time 60' "${REVIEW_WORKFLOW}")" -eq 2 ] ||
	fail "${REVIEW_WORKFLOW}: both Sonar requests must have bounded request-level timeouts"
grep -Fq 'if not isinstance(payload, dict):' "${REVIEW_WORKFLOW}" ||
	fail "${REVIEW_WORKFLOW}: Sonar response validation must reject non-object payloads"
grep -Fq 'not isinstance(issues, list)' "${REVIEW_WORKFLOW}" ||
	fail "${REVIEW_WORKFLOW}: Sonar response validation must require an issues list"
grep -Fq 'type(total) is not int' "${REVIEW_WORKFLOW}" ||
	fail "${REVIEW_WORKFLOW}: Sonar response validation must require an integer total"
grep -Fq 'total < len(issues)' "${REVIEW_WORKFLOW}" ||
	fail "${REVIEW_WORKFLOW}: Sonar response validation must reject inconsistent totals"

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

# --- OpenSSF Scorecard only supports push analysis for the repository's
# default branch. Keep both push and pull-request filters off the development
# branch so a development-branch event cannot start an unsupported analysis.
[ "$(grep -Fc '    branches: [master, main]' "${SCORECARD_WORKFLOW}")" -eq 2 ] ||
	fail "${SCORECARD_WORKFLOW}: push and pull_request must target only default-branch names"
if grep -Eq '^[[:space:]]+branches:.*dev' "${SCORECARD_WORKFLOW}"; then
	fail "${SCORECARD_WORKFLOW}: development branch must not trigger OpenSSF Scorecard"
fi

# --- The Sonar parser cleanup must be idempotent. Pull-request validation must
# use the immutable head SHA with a non-persistent read-only checkout and fail
# when the parser rewrite or checksum sidecars would change the committed tree.
grep -Fq 'old_count == 1 and new_count == 0' "${SONAR_REWRITE}" ||
	fail "${SONAR_REWRITE}: expected validation of the pre-rewrite state"
grep -Fq 'old_count == 0 and new_count == 1' "${SONAR_REWRITE}" ||
	fail "${SONAR_REWRITE}: expected the already-applied rewrite state to succeed"
grep -Fq 'sh tools/update-checksums.sh AdGuardHome.sh' "${WORKFLOW}" ||
	fail "${WORKFLOW}: Sonar parser validation must regenerate AdGuardHome.sh checksums before comparison"
grep -Fq 'busybox ash tests/installer-jq-helper.sh' "${SHELL_VALIDATION_WORKFLOW}" ||
	fail "${SHELL_VALIDATION_WORKFLOW}: expected the installer jq dependency regression to run with BusyBox ash"
grep -Fq 'busybox ash tests/installer-preflight-actions.sh' "${SHELL_VALIDATION_WORKFLOW}" ||
	fail "${SHELL_VALIDATION_WORKFLOW}: expected the installer preflight action regression to run with BusyBox ash"
grep -Fq 'busybox ash tests/installer-dns-environment-failure.sh' "${SHELL_VALIDATION_WORKFLOW}" ||
	fail "${SHELL_VALIDATION_WORKFLOW}: expected the installer NVRAM transaction regression to run with BusyBox ash"
grep -Fq 'busybox ash tests/update-tzdata-package-info.sh' "${SHELL_VALIDATION_WORKFLOW}" ||
	fail "${SHELL_VALIDATION_WORKFLOW}: expected the tzdata metadata regression to run with BusyBox ash"
grep -Fq '      - tests/update-tzdata-package-info.sh' "${TZDATA_WORKFLOW}" ||
	fail "${TZDATA_WORKFLOW}: tzdata regression changes must trigger the update workflow"
grep -Fq '      - tools/tzdata-package-info.sh' "${TZDATA_WORKFLOW}" ||
	fail "${TZDATA_WORKFLOW}: tzdata helper changes must trigger the update workflow"
grep -Fq '        run: sh tests/update-tzdata-package-info.sh' "${TZDATA_WORKFLOW}" ||
	fail "${TZDATA_WORKFLOW}: expected the tzdata metadata regression before package publication"
grep -Fq "run_check 'tzdata package metadata regression' sh tests/update-tzdata-package-info.sh" "${LOCAL_QUALITY_RUNNER}" ||
	fail "${LOCAL_QUALITY_RUNNER}: expected the tzdata metadata regression in the local and CI quality matrix"
grep -Fq "run_check 'Installer jq dependency regression' sh tests/installer-jq-helper.sh" "${LOCAL_QUALITY_RUNNER}" ||
	fail "${LOCAL_QUALITY_RUNNER}: expected the installer jq dependency regression in the local quality matrix"
grep -Fq 'tests/installer-jq-helper.sh)' "${LOCAL_QUALITY_TEST}" ||
	fail "${LOCAL_QUALITY_TEST}: expected mock dispatch for the installer jq dependency regression"
grep -Fq "run_check 'Installer jq dependency regression' sh tests/installer-jq-helper.sh" "${LOCAL_QUALITY_TEST}" ||
	fail "${LOCAL_QUALITY_TEST}: expected the installer jq dependency regression dispatch to be exercised"
grep -Fq '[ -f "${JQ_HELPER_RAN_FILE}" ]' "${LOCAL_QUALITY_TEST}" ||
	fail "${LOCAL_QUALITY_TEST}: expected an observable assertion that the installer jq regression ran"
grep -Fq 'ref: ${{ github.event.pull_request.head.sha }}' "${WORKFLOW}" ||
	fail "${WORKFLOW}: Sonar parser validation must check the immutable pull-request head SHA"
grep -Fq 'persist-credentials: false' "${WORKFLOW}" ||
	fail "${WORKFLOW}: Sonar parser validation must not persist checkout credentials"
if grep -Fq 'contents: write' "${WORKFLOW}"; then
	fail "${WORKFLOW}: pull-request quality workflow must not grant contents write permission"
fi
if grep -Fq 'git push origin HEAD:v2.6.5' "${WORKFLOW}"; then
	fail "${WORKFLOW}: pull-request quality workflow must not publish branch changes"
fi
grep -Fq 'git diff --exit-code -- AdGuardHome.sh AdGuardHome.sh.md5sum AdGuardHome.sh.sha256sum' "${WORKFLOW}" ||
	fail "${WORKFLOW}: Sonar parser validation must fail when generated artifacts differ"

# --- Static archive publication creates both sidecars itself. The cache job
# stages complete architecture directories so archive and digest changes stay
# in the same commit without a redundant second checksum pass.
grep -Fq '_md5_file="${_archive_file}.md5sum"' "${STATIC_DOWNLOADER}" ||
	fail "${STATIC_DOWNLOADER}: static archive publisher no longer derives its MD5 sidecar"
grep -Fq '_sha256_file="${_archive_file}.sha256sum"' "${STATIC_DOWNLOADER}" ||
	fail "${STATIC_DOWNLOADER}: static archive publisher no longer derives its SHA-256 sidecar"
grep -Fq 'git add -- armv8 armv7 armv5' "${CACHE_WORKFLOW}" ||
	fail "${CACHE_WORKFLOW}: static archive job must stage complete architecture directories"

# --- Security policy must catch insecure downloader bypass options even when
# curl or wget is invoked through an absolute trusted router path.
grep -Fq '(?:/[^ \t\n]*/)?curl' "${SEMGREP}" ||
	fail "${SEMGREP}: insecure curl rule no longer covers absolute executable paths"
grep -Fq '(?:/[^ \t\n]*/)?wget' "${SEMGREP}" ||
	fail "${SEMGREP}: insecure wget rule no longer covers absolute executable paths"

# --- Sonar must assign all extensionless production shell entrypoints to its
# Shell analyzer in addition to normal *.sh files.
grep -Fqx 'sonar.lang.patterns.shell=**/*.sh,installer,S99AdGuardHome,rc.func.AdGuardHome' "${SONAR}" ||
	fail "${SONAR}: Shell language patterns no longer include all extensionless runtime entrypoints"

printf '%s\n' 'PASS: .coderabbit.yaml and code-quality workflows keep required structure and execute real checks'
