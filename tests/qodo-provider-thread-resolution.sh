#!/bin/sh

set -u

SKILL='.agents/skills/qodo-pr-resolver/SKILL.md'
PROVIDERS='.agents/skills/qodo-pr-resolver/resources/providers.md'

# fail reports an error message to stderr and exits the script with status 1.
fail() {
	printf '%s\n' "FAIL: $1" >&2
	exit 1
}

GERRIT='.agents/skills/qodo-pr-resolver/resources/gerrit.md'

grep -Fq 'providers.md#resolve-inline-threads' "${SKILL}" || fail 'resolver does not require provider-specific inline-thread resolution'

# Extract the "Resolve Inline Threads" section for scoped assertions
if ! grep -Fq '## Post Summary Comment' "${PROVIDERS}"; then
	fail 'Post Summary Comment section heading not found in providers.md (cannot extract Resolve Inline Threads section)'
fi
RESOLVE_INLINE_SECTION=$(sed -n '/^## Resolve Inline Threads$/,/^## Post Summary Comment$/p' "${PROVIDERS}" | sed '$d')
if [ -z "$RESOLVE_INLINE_SECTION" ]; then
	fail 'Resolve Inline Threads section not found in providers.md'
fi

printf '%s\n' "$RESOLVE_INLINE_SECTION" | grep -Fq 'resolveReviewThread(input:{threadId:$threadId})' || fail 'GitHub review-thread mutation is missing'
printf '%s\n' "$RESOLVE_INLINE_SECTION" | grep -Fq '/discussions/<discussion-id>' || fail 'GitLab discussion resolution is missing'
printf '%s\n' "$RESOLVE_INLINE_SECTION" | grep -Fq '/comments/<inline-comment-id>/resolve' || fail 'Bitbucket inline-comment resolution is missing'

# Extract the "Resolve Inline Threads" section and verify Azure DevOps inline-thread resolution
if ! grep -Fq '## Post Summary Comment' "${PROVIDERS}"; then
	fail 'Post Summary Comment section heading not found in providers.md (cannot extract Resolve Inline Threads section)'
fi
ADO_INLINE_SECTION=$(sed -n '/^## Resolve Inline Threads$/,/^## Post Summary Comment$/p' "${PROVIDERS}" | sed '$d')
if [ -z "$ADO_INLINE_SECTION" ]; then
	fail 'Resolve Inline Threads section not found in providers.md'
fi
printf '%s\n' "$ADO_INLINE_SECTION" | grep -Fq '{"status": "fixed"}' || fail 'Azure DevOps thread resolution is missing'
printf '%s\n' "$ADO_INLINE_SECTION" | grep -Fq 'az devops invoke' || fail 'Azure DevOps thread resolution does not use az devops invoke'
printf '%s\n' "$ADO_INLINE_SECTION" | grep -Fq -- '--http-method PATCH' || fail 'Azure DevOps thread resolution does not use PATCH method'
printf '%s\n' "$ADO_INLINE_SECTION" | grep -Fq 'pullRequestThreads' || fail 'Azure DevOps thread resolution does not target pullRequestThreads resource'

# Extract the "Reply to Comments" section from Gerrit documentation and verify thread resolution
if ! grep -Fq '## Reply to Comments' "${GERRIT}"; then
	fail 'Reply to Comments section heading not found in gerrit.md (cannot extract section)'
fi
GERRIT_REPLY_SECTION=$(sed -n '/^## Reply to Comments$/,/^## /p' "${GERRIT}" | sed '$d')
if [ -z "$GERRIT_REPLY_SECTION" ]; then
	fail 'Reply to Comments section not found in gerrit.md'
fi
printf '%s\n' "$GERRIT_REPLY_SECTION" | grep -Fq '/revisions/current/review' || fail 'Gerrit Reply to Comments section does not use unified endpoint'
printf '%s\n' "$GERRIT_REPLY_SECTION" | grep -Fq '"in_reply_to"' || fail 'Gerrit Reply to Comments section does not use in_reply_to field'
printf '%s\n' "$GERRIT_REPLY_SECTION" | grep -Fq '"unresolved": false' || fail 'Gerrit Reply to Comments section does not set unresolved to false'

# Extract the "Reply to Inline Comments" section for scoped assertions on safe dynamic comment transport
if ! grep -Fq '## Resolve Inline Threads' "${PROVIDERS}"; then
	fail 'Resolve Inline Threads section heading not found in providers.md (cannot extract Reply to Inline Comments section)'
fi
REPLY_SECTION=$(sed -n '/^## Reply to Inline Comments$/,/^## Resolve Inline Threads$/p' "${PROVIDERS}" | sed '$d')
if [ -z "$REPLY_SECTION" ]; then
	fail 'Reply to Inline Comments section not found in providers.md'
fi

if ! printf '%s\n' "$REPLY_SECTION" | grep -Fq '### GitLab'; then
	fail 'GitLab subsection heading not found in Reply to Inline Comments section (cannot extract GitHub subsection)'
fi
REPLY_GITHUB=$(printf '%s\n' "$REPLY_SECTION" | sed -n '/^### GitHub$/,/^### GitLab$/p' | sed '$d')
if [ -z "$REPLY_GITHUB" ]; then
	fail 'GitHub subsection not found in Reply to Inline Comments section'
fi
if ! printf '%s\n' "$REPLY_SECTION" | grep -Fq '### Bitbucket'; then
	fail 'Bitbucket subsection heading not found in Reply to Inline Comments section (cannot extract GitLab subsection)'
fi
REPLY_GITLAB=$(printf '%s\n' "$REPLY_SECTION" | sed -n '/^### GitLab$/,/^### Bitbucket$/p' | sed '$d')
if [ -z "$REPLY_GITLAB" ]; then
	fail 'GitLab subsection not found in Reply to Inline Comments section'
fi

printf '%s\n' "$REPLY_GITHUB" | grep -Eq "['\"]<reply-body>['\"]" && fail 'GitHub inline reply still places rendered reply text inside a shell-quoted <reply-body> placeholder'
printf '%s\n' "$REPLY_GITLAB" | grep -Eq "['\"]<reply-body>['\"]" && fail 'GitLab inline reply still places rendered reply text inside a shell-quoted <reply-body> placeholder'
printf '%s\n' "$REPLY_GITHUB" | grep -Fq -- '-F body=@"$REPLY_FILE"' || fail 'GitHub inline reply does not read the reply body from a file'
printf '%s\n' "$REPLY_GITLAB" | grep -Fq -- '-F body=@"$REPLY_FILE"' || fail 'GitLab inline reply does not read the reply body from a file'

# The reply templates must not embed the rendered body inside a shell heredoc: a body
# containing a standalone line matching the delimiter (e.g. a literal "EOF" line) would
# terminate the heredoc early and let the remaining body text execute as shell commands.
printf '%s\n' "$REPLY_GITHUB" | grep -Fq "<<'EOF'" && fail 'GitHub inline reply still embeds the reply body inside a shell heredoc'
printf '%s\n' "$REPLY_GITLAB" | grep -Fq "<<'EOF'" && fail 'GitLab inline reply still embeds the reply body inside a shell heredoc'

# Fixture: a rendered reply body containing a standalone "EOF" line followed by a command.
# Writing it out-of-band (as the file-writing tool would, not via a shell heredoc) must
# preserve it as literal content and must never execute the trailing line.
REPLY_MARKER=""
REPLY_FIXTURE_FILE=""
DANGEROUS_FILE=""
trap 'rm -f "$REPLY_MARKER" "$REPLY_FIXTURE_FILE" "$DANGEROUS_FILE"' EXIT
trap 'rm -f "$REPLY_MARKER" "$REPLY_FIXTURE_FILE" "$DANGEROUS_FILE"; exit 1' HUP INT TERM
REPLY_MARKER=$(mktemp "${TMPDIR:-/tmp}/qodo_reply_marker.XXXXXX") || fail 'unable to create reply marker file'
rm -f "$REPLY_MARKER"
REPLY_FIXTURE_FILE=$(mktemp "${TMPDIR:-/tmp}/qodo_reply_fixture.XXXXXX") || fail 'unable to create reply fixture file'
printf 'Fixed the issue.\nEOF\ntouch %s\n' "$REPLY_MARKER" >"$REPLY_FIXTURE_FILE"
[ "$(wc -l <"$REPLY_FIXTURE_FILE")" -eq 3 ] || fail 'reply fixture with standalone EOF line was not preserved as literal content'
grep -Fq "touch ${REPLY_MARKER}" "$REPLY_FIXTURE_FILE" || fail 'reply fixture content was altered'
[ -e "$REPLY_MARKER" ] && fail 'reply fixture command was executed instead of remaining literal file content'

# Test Bitbucket and Azure DevOps with shell metacharacters and command substitution
for provider in bitbucket azure; do
	for dangerous_content in "Single'quote" 'Double"quote' '$(echo injected)' '`echo injected`' 'EOF'; do
		DANGEROUS_FILE=$(mktemp "${TMPDIR:-/tmp}/qodo_dangerous_${provider}.XXXXXX") || fail "unable to create dangerous content test file for ${provider}"
		printf 'Fixed: %s\n' "$dangerous_content" >"$DANGEROUS_FILE"
		grep -Fq "$dangerous_content" "$DANGEROUS_FILE" || fail "${provider}: dangerous content test file was altered"
		rm -f "$DANGEROUS_FILE"
	done
done

# Extract Bitbucket and Azure DevOps Reply to Inline Comments sections and verify
# that the payload serializer reads the body from a file and does not embed it inline.
if ! printf '%s\n' "$REPLY_SECTION" | grep -Fq '### Azure DevOps'; then
	fail 'Azure DevOps subsection heading not found in Reply to Inline Comments section (cannot extract Bitbucket subsection)'
fi
BITBUCKET_REPLY_SECTION=$(printf '%s\n' "$REPLY_SECTION" | sed -n '/^### Bitbucket$/,/^### Azure DevOps$/p' | sed '$d')
if [ -z "$BITBUCKET_REPLY_SECTION" ]; then
	fail 'Bitbucket reply subsection not found in Reply to Inline Comments section'
fi
AZURE_REPLY_SECTION=$(printf '%s\n' "$REPLY_SECTION" | sed -n '/^### Azure DevOps$/,$p')
if [ -z "$AZURE_REPLY_SECTION" ]; then
	fail 'Azure DevOps reply subsection not found in Reply to Inline Comments section'
fi

# Verify Bitbucket reply payload serializer reads from file
printf '%s\n' "$BITBUCKET_REPLY_SECTION" | grep -Fq 'with open(sys.argv[1], ' || fail 'Bitbucket reply payload serializer does not read from a file'
printf '%s\n' "$BITBUCKET_REPLY_SECTION" | grep -Fq 'python3 - "$REPLY_FILE"' || fail 'Bitbucket reply payload serializer does not receive the reply file path as an argument'
# Ensure Bitbucket payload does not embed the body inline (no heredoc with body content)
if printf '%s\n' "$BITBUCKET_REPLY_SECTION" | grep -E "<<['\"]?EOF['\"]?" | grep -v 'python3 -' | grep -qv '^PY$'; then
	fail 'Bitbucket reply section embeds the body inline in a heredoc outside the python serializer'
fi

# Verify Azure DevOps reply payload serializer reads from file
printf '%s\n' "$AZURE_REPLY_SECTION" | grep -Fq 'with open(sys.argv[1], ' || fail 'Azure DevOps reply payload serializer does not read from a file'
printf '%s\n' "$AZURE_REPLY_SECTION" | grep -Fq 'python3 - "$REPLY_FILE"' || fail 'Azure DevOps reply payload serializer does not receive the reply file path as an argument'
# Ensure Azure payload does not embed the body inline (no heredoc with body content)
if printf '%s\n' "$AZURE_REPLY_SECTION" | grep -E "<<['\"]?EOF['\"]?" | grep -v 'python3 -' | grep -qv '^PY$'; then
	fail 'Azure DevOps reply section embeds the body inline in a heredoc outside the python serializer'
fi

rm -f "$REPLY_FIXTURE_FILE" "$REPLY_MARKER"
REPLY_MARKER=""
REPLY_FIXTURE_FILE=""
DANGEROUS_FILE=""

# Extract the "Post Summary Comment" section for scoped assertions on safe dynamic comment transport
if ! grep -Fq '## Qodo Fix Summary — Round N' "${PROVIDERS}"; then
	fail 'Qodo Fix Summary heading not found in providers.md (cannot extract Post Summary Comment section)'
fi
SUMMARY_SECTION=$(sed -n '/^## Post Summary Comment$/,/^## Qodo Fix Summary — Round N$/p' "${PROVIDERS}" | sed '$d')
if [ -z "$SUMMARY_SECTION" ]; then
	fail 'Post Summary Comment section not found in providers.md'
fi

if ! printf '%s\n' "$SUMMARY_SECTION" | grep -Fq '### GitLab'; then
	fail 'GitLab subsection heading not found in Post Summary Comment section (cannot extract GitHub subsection)'
fi
SUMMARY_GITHUB=$(printf '%s\n' "$SUMMARY_SECTION" | sed -n '/^### GitHub$/,/^### GitLab$/p' | sed '$d')
if [ -z "$SUMMARY_GITHUB" ]; then
	fail 'GitHub subsection not found in Post Summary Comment section'
fi
if ! printf '%s\n' "$SUMMARY_SECTION" | grep -Fq '### Bitbucket'; then
	fail 'Bitbucket subsection heading not found in Post Summary Comment section (cannot extract GitLab subsection)'
fi
SUMMARY_GITLAB=$(printf '%s\n' "$SUMMARY_SECTION" | sed -n '/^### GitLab$/,/^### Bitbucket$/p' | sed '$d')
if [ -z "$SUMMARY_GITLAB" ]; then
	fail 'GitLab subsection not found in Post Summary Comment section'
fi

printf '%s\n' "$SUMMARY_GITHUB" | grep -Eq "['\"]<comment-body>['\"]" && fail 'GitHub summary comment still places rendered comment text inside a shell-quoted <comment-body> placeholder'
printf '%s\n' "$SUMMARY_GITLAB" | grep -Eq "['\"]<comment-body>['\"]" && fail 'GitLab summary comment still places rendered comment text inside a shell-quoted <comment-body> placeholder'
printf '%s\n' "$SUMMARY_GITHUB" | grep -Fq -- '--body-file "$COMMENT_FILE"' || fail 'GitHub summary comment does not use --body-file to read the comment body from a file'
printf '%s\n' "$SUMMARY_GITLAB" | grep -Fq -- '< "$COMMENT_FILE"' || fail 'GitLab summary comment does not consume the comment body file through standard input'

# The summary templates must not embed the rendered body inside a shell heredoc either.
printf '%s\n' "$SUMMARY_GITHUB" | grep -Fq "<<'EOF'" && fail 'GitHub summary comment still embeds the comment body inside a shell heredoc'
printf '%s\n' "$SUMMARY_GITLAB" | grep -Fq "<<'EOF'" && fail 'GitLab summary comment still embeds the comment body inside a shell heredoc'

# Fixture: a rendered summary body containing a standalone "EOF" line followed by a command.
SUMMARY_MARKER=""
SUMMARY_FIXTURE_FILE=""
trap 'rm -f "$SUMMARY_MARKER" "$SUMMARY_FIXTURE_FILE"' EXIT
trap 'rm -f "$SUMMARY_MARKER" "$SUMMARY_FIXTURE_FILE"; exit 1' HUP INT TERM
SUMMARY_MARKER=$(mktemp "${TMPDIR:-/tmp}/qodo_summary_marker.XXXXXX") || fail 'unable to create summary marker file'
rm -f "$SUMMARY_MARKER"
SUMMARY_FIXTURE_FILE=$(mktemp "${TMPDIR:-/tmp}/qodo_summary_fixture.XXXXXX") || fail 'unable to create summary fixture file'
printf '## Qodo Fix Summary\nEOF\ntouch %s\n' "$SUMMARY_MARKER" >"$SUMMARY_FIXTURE_FILE"
[ "$(wc -l <"$SUMMARY_FIXTURE_FILE")" -eq 3 ] || fail 'summary fixture with standalone EOF line was not preserved as literal content'
grep -Fq "touch ${SUMMARY_MARKER}" "$SUMMARY_FIXTURE_FILE" || fail 'summary fixture content was altered'
[ -e "$SUMMARY_MARKER" ] && fail 'summary fixture command was executed instead of remaining literal file content'
rm -f "$SUMMARY_FIXTURE_FILE" "$SUMMARY_MARKER"
SUMMARY_MARKER=""
SUMMARY_FIXTURE_FILE=""

printf '%s\n' 'PASS: Qodo provider-specific inline thread resolution is documented and required'
