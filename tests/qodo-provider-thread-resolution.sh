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
if ! grep -Fq '## Resolve Inline Threads' "${PROVIDERS}"; then
	fail 'Resolve Inline Threads section heading not found in providers.md'
fi
if ! grep -Fq '## Post Summary Comment' "${PROVIDERS}"; then
	fail 'Post Summary Comment section heading not found in providers.md (cannot extract Resolve Inline Threads section)'
fi
# Verify the section boundaries appear in the expected order
RESOLVE_LINE=$(grep -Fn '## Resolve Inline Threads' "${PROVIDERS}" | head -n1 | cut -d: -f1)
SUMMARY_LINE=$(grep -Fn '## Post Summary Comment' "${PROVIDERS}" | head -n1 | cut -d: -f1)
if [ -z "$RESOLVE_LINE" ] || [ -z "$SUMMARY_LINE" ]; then
	fail 'Could not determine line numbers for section boundaries in providers.md'
fi
if [ "$RESOLVE_LINE" -ge "$SUMMARY_LINE" ]; then
	fail 'Resolve Inline Threads section does not precede Post Summary Comment section in providers.md'
fi
RESOLVE_INLINE_SECTION=$(sed -n '/^## Resolve Inline Threads$/,/^## Post Summary Comment$/p' "${PROVIDERS}" | sed '$d')
if [ -z "$RESOLVE_INLINE_SECTION" ]; then
	fail 'Resolve Inline Threads section not found in providers.md'
fi

printf '%s\n' "$RESOLVE_INLINE_SECTION" | grep -Fq 'resolveReviewThread(input:{threadId:$threadId})' || fail 'GitHub review-thread mutation is missing'
printf '%s\n' "$RESOLVE_INLINE_SECTION" | grep -Fq '/discussions/<discussion-id>' || fail 'GitLab discussion resolution is missing'
printf '%s\n' "$RESOLVE_INLINE_SECTION" | grep -Fq '/comments/<inline-comment-id>/resolve' || fail 'Bitbucket inline-comment resolution is missing'

# Extract the "Resolve Inline Threads" section and verify Azure DevOps inline-thread resolution
# (Section boundaries already verified above)
ADO_INLINE_SECTION=$(sed -n '/^## Resolve Inline Threads$/,/^## Post Summary Comment$/p' "${PROVIDERS}" | sed '$d')
if [ -z "$ADO_INLINE_SECTION" ]; then
	fail 'Resolve Inline Threads section not found in providers.md (duplicate extraction)'
fi
printf '%s\n' "$ADO_INLINE_SECTION" | grep -Fq '{"status": "fixed"}' || fail 'Azure DevOps thread resolution is missing'
printf '%s\n' "$ADO_INLINE_SECTION" | grep -Fq 'az devops invoke' || fail 'Azure DevOps thread resolution does not use az devops invoke'
printf '%s\n' "$ADO_INLINE_SECTION" | grep -Fq -- '--http-method PATCH' || fail 'Azure DevOps thread resolution does not use PATCH method'
printf '%s\n' "$ADO_INLINE_SECTION" | grep -Fq 'pullRequestThreads' || fail 'Azure DevOps thread resolution does not target pullRequestThreads resource'
printf '%s\n' "$ADO_INLINE_SECTION" | grep -Fq 'threadId="<thread-id>"' || fail 'Azure DevOps PATCH request does not include threadId parameter'

# Extract the "Reply to Comments" section from Gerrit documentation and verify thread resolution
if ! grep -Fq '## Reply to Comments' "${GERRIT}"; then
	fail 'Reply to Comments section heading not found in gerrit.md (cannot extract section)'
fi
if ! grep -Fq '## Post Summary Comment' "${GERRIT}"; then
	fail 'Post Summary Comment section heading not found in gerrit.md (cannot extract Reply to Comments section)'
fi
# Verify the section boundaries appear in the expected order
GERRIT_REPLY_LINE=$(grep -Fn '## Reply to Comments' "${GERRIT}" | head -n1 | cut -d: -f1)
GERRIT_SUMMARY_LINE=$(grep -Fn '## Post Summary Comment' "${GERRIT}" | head -n1 | cut -d: -f1)
if [ -z "$GERRIT_REPLY_LINE" ] || [ -z "$GERRIT_SUMMARY_LINE" ]; then
	fail 'Could not determine line numbers for section boundaries in gerrit.md'
fi
if [ "$GERRIT_REPLY_LINE" -ge "$GERRIT_SUMMARY_LINE" ]; then
	fail 'Reply to Comments section does not precede Post Summary Comment section in gerrit.md'
fi
GERRIT_REPLY_SECTION=$(sed -n '/^## Reply to Comments$/,/^## Post Summary Comment$/p' "${GERRIT}" | sed '$d')
if [ -z "$GERRIT_REPLY_SECTION" ]; then
	fail 'Reply to Comments section not found in gerrit.md'
fi
printf '%s\n' "$GERRIT_REPLY_SECTION" | grep -Fq '/revisions/current/review' || fail 'Gerrit Reply to Comments section does not use unified endpoint'
printf '%s\n' "$GERRIT_REPLY_SECTION" | grep -Fq '"in_reply_to"' || fail 'Gerrit Reply to Comments section does not use in_reply_to field'
printf '%s\n' "$GERRIT_REPLY_SECTION" | grep -Fq '"unresolved": false' || fail 'Gerrit Reply to Comments section does not set unresolved to false'

# Test section boundary validation with a truncated/reordered document
TEMP_PROVIDERS=$(mktemp "${TMPDIR:-/tmp}/test-providers.XXXXXX.md")
trap 'rm -f "$TEMP_PROVIDERS"' EXIT

# Test 1: Missing closing heading (truncated document)
sed -n '1,/^## Resolve Inline Threads$/p' "${PROVIDERS}" >"$TEMP_PROVIDERS"
RESOLVE_LINE=$(grep -Fn '## Resolve Inline Threads' "$TEMP_PROVIDERS" | head -n1 | cut -d: -f1)
SUMMARY_LINE=$(grep -Fn '## Post Summary Comment' "$TEMP_PROVIDERS" | head -n1 | cut -d: -f1)
if [ -n "$SUMMARY_LINE" ]; then
	fail 'Truncated document test failed: Post Summary Comment section should not exist'
fi

# Test 2: Reordered sections (closing heading appears before opening heading)
{
	sed -n '1,/^## Resolve Inline Threads$/p' "${PROVIDERS}" | sed '$d'
	sed -n '/^## Post Summary Comment$/,/^## /p' "${PROVIDERS}" | sed '$d'
	sed -n '/^## Resolve Inline Threads$/,/^## Post Summary Comment$/p' "${PROVIDERS}"
} >"$TEMP_PROVIDERS"
RESOLVE_LINE=$(grep -Fn '## Resolve Inline Threads' "$TEMP_PROVIDERS" | head -n1 | cut -d: -f1)
SUMMARY_LINE=$(grep -Fn '## Post Summary Comment' "$TEMP_PROVIDERS" | head -n1 | cut -d: -f1)
if [ -z "$RESOLVE_LINE" ] || [ -z "$SUMMARY_LINE" ]; then
	fail 'Reordered sections test setup failed: could not find both headings'
fi
if [ "$RESOLVE_LINE" -lt "$SUMMARY_LINE" ]; then
	fail 'Reordered sections test failed: first occurrence of Resolve should come after Summary in reordered document'
fi

rm -f "$TEMP_PROVIDERS"

printf '%s\n' 'PASS: Qodo provider-specific inline thread resolution is documented and required'
