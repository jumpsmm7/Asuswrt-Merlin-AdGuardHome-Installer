#!/bin/sh
# Select an exact OSV comparison snapshot without downloading repository history.
# This validation-host helper leaves checkout to the following workflow step.

set -u
export LC_ALL=C

# fail refuses an invalid workflow setup before enabling either reporting path.
fail() {
	printf '%s\n' "Error: $*" >&2
	exit 1
}

# commit_sha_valid accepts only the complete hexadecimal object IDs supplied by GitHub.
commit_sha_valid() {
	[ "${#1}" -eq 40 ] || return 1
	case "$1" in
		*[!0-9a-f]*) return 1 ;;
		*) return 0 ;;
	esac
}

candidate_sha="${GITHUB_SHA:-}"
base_revision="${BASE_REVISION:-}"
baseline_available=false
zero_sha=0000000000000000000000000000000000000000

commit_sha_valid "${candidate_sha}" && [ "${candidate_sha}" != "${zero_sha}" ] || fail 'candidate must be an exact commit SHA'
[ -n "${GITHUB_OUTPUT:-}" ] || fail 'GitHub output path is unavailable'
case "${GITHUB_EVENT_NAME:-}" in
	pull_request)
		commit_sha_valid "${base_revision}" && [ "${base_revision}" != "${zero_sha}" ] || fail 'pull request base must be an exact commit SHA'
		;;
	push)
		commit_sha_valid "${base_revision}" || fail 'push predecessor must be an exact commit SHA'
		;;
	*) fail 'unsupported differential scan event' ;;
esac

git rev-parse --verify "${candidate_sha}^{commit}" >/dev/null 2>&1 || fail 'candidate commit is unavailable'
checked_out_sha="$(git rev-parse --verify HEAD)" || fail 'candidate checkout is unavailable'
[ "${checked_out_sha}" = "${candidate_sha}" ] || fail 'checkout does not match the candidate commit'
git remote get-url origin >/dev/null 2>&1 || fail 'repository origin is unavailable'

if [ "${base_revision}" = "${zero_sha}" ]; then
	# A new branch has no before SHA. Depth two supplies the first parent;
	# a root commit has no predecessor and must receive a full report.
	base_revision="$(git rev-parse --verify "${candidate_sha}^" 2>/dev/null)" || base_revision=''
fi

if [ -n "${base_revision}" ]; then
	commit_sha_valid "${base_revision}" || fail 'resolved predecessor is not an exact commit SHA'
	if ! git rev-parse --verify "${base_revision}^{commit}" >/dev/null 2>&1; then
		# Fetch a single snapshot, never every branch, tag, or historical archive.
		git fetch --no-tags --depth=1 origin "${base_revision}" ||
			printf '%s\n' "OSV predecessor ${base_revision} could not be fetched; selecting a full vulnerability report."
	fi
	if git rev-parse --verify "${base_revision}^{commit}" >/dev/null 2>&1; then
		baseline_available=true
	else
		base_revision=''
	fi
fi

if [ "${baseline_available}" = false ]; then
	printf '%s\n' 'OSV has no available predecessor; the candidate will receive a full vulnerability report.'
fi

# scan_ready means snapshot selection succeeded. Missing baselines still take
# the fail-on-vulnerability full reporting path; no report is silently skipped.
printf 'baseline_available=%s\nbase_sha=%s\nscan_ready=true\n' \
	"${baseline_available}" "${base_revision}" >>"${GITHUB_OUTPUT}" || fail 'could not publish snapshot selection'
