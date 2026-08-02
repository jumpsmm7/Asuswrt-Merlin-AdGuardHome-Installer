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
grep -Fq 'resolveReviewThread(input:{threadId:$threadId})' "${PROVIDERS}" || fail 'GitHub review-thread mutation is missing'
grep -Fq '/discussions/<discussion-id>' "${PROVIDERS}" || fail 'GitLab discussion resolution is missing'
grep -Fq '/comments/<inline-comment-id>/resolve' "${PROVIDERS}" || fail 'Bitbucket inline-comment resolution is missing'
grep -Fq '{"status": "fixed"}' "${PROVIDERS}" || fail 'Azure DevOps thread resolution is missing'
grep -Fq '"unresolved": false' "${GERRIT}" || fail 'Gerrit inline-thread resolution behavior is missing'

printf '%s\n' 'PASS: Qodo provider-specific inline thread resolution is documented and required'
