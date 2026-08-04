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

REPLY_GITHUB=$(printf '%s\n' "$REPLY_SECTION" | sed -n '/^### GitHub$/,/^### GitLab$/p' | sed '$d')
REPLY_GITLAB=$(printf '%s\n' "$REPLY_SECTION" | sed -n '/^### GitLab$/,/^### Bitbucket$/p' | sed '$d')
if [ -z "$REPLY_GITHUB" ]; then
	fail 'GitHub subsection not found in Reply to Inline Comments section'
fi
if [ -z "$REPLY_GITLAB" ]; then
	fail 'GitLab subsection not found in Reply to Inline Comments section'
fi

printf '%s\n' "$REPLY_GITHUB" | grep -Eq "['\"]<reply-body>['\"]" && fail 'GitHub inline reply still places rendered reply text inside a shell-quoted <reply-body> placeholder'
printf '%s\n' "$REPLY_GITLAB" | grep -Eq "['\"]<reply-body>['\"]" && fail 'GitLab inline reply still places rendered reply text inside a shell-quoted <reply-body> placeholder'
printf '%s\n' "$REPLY_GITHUB" | grep -Fq -- '-F body=@"$REPLY_FILE"' || fail 'GitHub inline reply does not read the reply body from a file'
printf '%s\n' "$REPLY_GITLAB" | grep -Fq -- '-F body=@"$REPLY_FILE"' || fail 'GitLab inline reply does not read the reply body from a file'

# Extract the "Post Summary Comment" section for scoped assertions on safe dynamic comment transport
if ! grep -Fq '## Qodo Fix Summary — Round N' "${PROVIDERS}"; then
	fail 'Qodo Fix Summary heading not found in providers.md (cannot extract Post Summary Comment section)'
fi
SUMMARY_SECTION=$(sed -n '/^## Post Summary Comment$/,/^## Qodo Fix Summary — Round N$/p' "${PROVIDERS}" | sed '$d')
if [ -z "$SUMMARY_SECTION" ]; then
	fail 'Post Summary Comment section not found in providers.md'
fi

SUMMARY_GITHUB=$(printf '%s\n' "$SUMMARY_SECTION" | sed -n '/^### GitHub$/,/^### GitLab$/p' | sed '$d')
SUMMARY_GITLAB=$(printf '%s\n' "$SUMMARY_SECTION" | sed -n '/^### GitLab$/,/^### Bitbucket$/p' | sed '$d')
if [ -z "$SUMMARY_GITHUB" ]; then
	fail 'GitHub subsection not found in Post Summary Comment section'
fi
if [ -z "$SUMMARY_GITLAB" ]; then
	fail 'GitLab subsection not found in Post Summary Comment section'
fi

printf '%s\n' "$SUMMARY_GITHUB" | grep -Eq "['\"]<comment-body>['\"]" && fail 'GitHub summary comment still places rendered comment text inside a shell-quoted <comment-body> placeholder'
printf '%s\n' "$SUMMARY_GITLAB" | grep -Eq "['\"]<comment-body>['\"]" && fail 'GitLab summary comment still places rendered comment text inside a shell-quoted <comment-body> placeholder'
printf '%s\n' "$SUMMARY_GITHUB" | grep -Fq -- '--body-file "$COMMENT_FILE"' || fail 'GitHub summary comment does not use --body-file to read the comment body from a file'
printf '%s\n' "$SUMMARY_GITLAB" | grep -Fq -- '< "$COMMENT_FILE"' || fail 'GitLab summary comment does not consume the comment body file through standard input'

printf '%s\n' 'PASS: Qodo provider-specific inline thread resolution is documented and required'
