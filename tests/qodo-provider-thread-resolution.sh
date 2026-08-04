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
printf '%s\n' "$ADO_INLINE_SECTION" | grep -Fq 'threadId="<thread-id>"' || fail 'Azure DevOps PATCH request does not include threadId parameter'

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

printf '%s\n' 'PASS: Qodo provider-specific inline thread resolution is documented and required'
