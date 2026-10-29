#!/bin/sh
# Exercise bounded OSV predecessor selection against real isolated Git repositories.

set -u
export LC_ALL=C

HELPER_PATH="${1:-.github/scripts/osv-differential-base.sh}"
WORKFLOW_PATH="${2:-.github/workflows/osv-scanner.yml}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/osv-checkout.XXXXXX")" || exit 1
trap 'rm -rf "${TEST_ROOT}"' 0
trap 'exit 1' HUP INT TERM

# fail reports the failed checkout contract and exits before another fixture runs.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

# run_git executes the real host Git without the fixture's logging wrapper.
run_git() {
	"${REAL_GIT}" "$@"
}

SCAN_PR_CONFIG="${TEST_ROOT}/scan-pr.yml"
awk '/^  scan-pr:$/ { selected = 1 } /^  scan-full:$/ { selected = 0 } selected { print }' \
	"${WORKFLOW_PATH}" >"${SCAN_PR_CONFIG}" || fail 'could not inspect differential checkout'
grep -Fq 'fetch-depth: 2' "${SCAN_PR_CONFIG}" || fail 'differential checkout must fetch only candidate and immediate parents'
if grep -Eq 'fetch-depth: 0|refs/heads/\*|refs/tags/\*' "${SCAN_PR_CONFIG}"; then
	fail 'differential checkout must not fetch all history or refs'
fi
[ -f "${HELPER_PATH}" ] || fail 'predecessor selection helper is missing'
HELPER_PATH="$(cd "$(dirname "${HELPER_PATH}")" && pwd)/$(basename "${HELPER_PATH}")" || fail 'could not locate helper'
REAL_GIT="$(command -v git)" || fail 'host Git is required'
export REAL_GIT
mkdir "${TEST_ROOT}/bin" || fail 'could not reserve command fixture'
cat >"${TEST_ROOT}/bin/git" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${OSV_GIT_LOG}"
exec "${REAL_GIT}" "$@"
EOF
chmod 700 "${TEST_ROOT}/bin/git" || fail 'could not prepare command fixture'

run_git init -q --bare "${TEST_ROOT}/origin" || fail 'could not create isolated origin'
run_git init -q "${TEST_ROOT}/source" || fail 'could not create isolated source'
run_git -C "${TEST_ROOT}/source" config user.name 'OSV regression' || fail 'could not set fixture author'
run_git -C "${TEST_ROOT}/source" config user.email 'osv-regression@example.invalid' || fail 'could not set fixture author email'
run_git -C "${TEST_ROOT}/source" checkout -qb main || fail 'could not create main fixture branch'
printf '%s\n' root >"${TEST_ROOT}/source/requirements.txt" || fail 'could not write root fixture'
run_git -C "${TEST_ROOT}/source" add requirements.txt || fail 'could not stage root fixture'
run_git -C "${TEST_ROOT}/source" commit -qm root || fail 'could not commit root fixture'
ROOT_SHA="$(run_git -C "${TEST_ROOT}/source" rev-parse HEAD)" || fail 'could not identify root fixture'
printf '%s\n' baseline >"${TEST_ROOT}/source/requirements.txt" || fail 'could not write baseline fixture'
run_git -C "${TEST_ROOT}/source" commit -qam baseline || fail 'could not commit baseline fixture'
BASE_SHA="$(run_git -C "${TEST_ROOT}/source" rev-parse HEAD)" || fail 'could not identify baseline fixture'
printf '%s\n' parent >"${TEST_ROOT}/source/requirements.txt" || fail 'could not write parent fixture'
run_git -C "${TEST_ROOT}/source" commit -qam parent || fail 'could not commit parent fixture'
PARENT_SHA="$(run_git -C "${TEST_ROOT}/source" rev-parse HEAD)" || fail 'could not identify parent fixture'
printf '%s\n' candidate >"${TEST_ROOT}/source/requirements.txt" || fail 'could not write candidate fixture'
run_git -C "${TEST_ROOT}/source" commit -qam candidate || fail 'could not commit candidate fixture'
TARGET_SHA="$(run_git -C "${TEST_ROOT}/source" rev-parse HEAD)" || fail 'could not identify candidate fixture'
run_git -C "${TEST_ROOT}/source" checkout -qb displaced "${BASE_SHA}" || fail 'could not create displaced branch'
printf '%s\n' displaced >"${TEST_ROOT}/source/requirements.txt" || fail 'could not write displaced fixture'
run_git -C "${TEST_ROOT}/source" commit -qam displaced || fail 'could not commit displaced fixture'
DISPLACED_SHA="$(run_git -C "${TEST_ROOT}/source" rev-parse HEAD)" || fail 'could not identify displaced predecessor'
run_git -C "${TEST_ROOT}/source" tag unrelated-history "${ROOT_SHA}" || fail 'could not create unrelated tag'
run_git -C "${TEST_ROOT}/source" push -q "${TEST_ROOT}/origin" main displaced refs/tags/unrelated-history || fail 'could not publish isolated source'
ZERO_SHA=0000000000000000000000000000000000000000

# prepare_checkout reproduces the workflow's shallow candidate-only checkout.
prepare_checkout() {
	CASE_DIR="${TEST_ROOT}/$1"
	CASE_TARGET="$2"
	mkdir "${CASE_DIR}" || fail 'could not reserve isolated checkout'
	run_git -C "${CASE_DIR}" init -q || fail 'could not initialize candidate checkout'
	run_git -C "${CASE_DIR}" remote add origin "file://${TEST_ROOT}/origin" || fail 'could not set isolated origin'
	run_git -C "${CASE_DIR}" fetch -q --no-tags --depth=2 origin "${CASE_TARGET}" || fail 'could not fetch candidate shallowly'
	run_git -C "${CASE_DIR}" checkout -q --detach FETCH_HEAD || fail 'could not check out candidate'
	: >"${CASE_DIR}/output"
	: >"${CASE_DIR}/git.log"
}

# select_base invokes the production selector while recording its actual Git calls.
select_base() {
	(
		cd "${CASE_DIR}" || exit 1
		PATH="${TEST_ROOT}/bin:${PATH}" OSV_GIT_LOG="${CASE_DIR}/git.log" \
			GITHUB_SHA="${CASE_TARGET}" GITHUB_EVENT_NAME="$1" BASE_REVISION="$2" \
			GITHUB_OUTPUT="${CASE_DIR}/output" sh "${HELPER_PATH}"
	) >"${CASE_DIR}/selection.log" 2>&1
}

# check_selection verifies snapshot identity, explicit reporting mode, and bounded fetching.
check_selection() {
	grep -qx 'scan_ready=true' "${CASE_DIR}/output" || fail 'successful selection did not enable vulnerability reporting'
	grep -qx "baseline_available=$1" "${CASE_DIR}/output" || fail 'incorrect predecessor availability'
	grep -qx "base_sha=$2" "${CASE_DIR}/output" || fail 'selected the wrong predecessor'
	[ "$(run_git -C "${CASE_DIR}" rev-parse HEAD)" = "${CASE_TARGET}" ] || fail 'selector changed the candidate checkout'
	[ -z "$(run_git -C "${CASE_DIR}" for-each-ref --format='%(refname)' refs/tags refs/remotes)" ] || fail 'selector fetched unrelated refs'
	if grep '^fetch ' "${CASE_DIR}/git.log" | grep -Ev '^fetch --no-tags --depth=1 origin [0-9a-f]{40}$' >/dev/null; then
		fail 'selector fetched unbounded history or a nonexact ref'
	fi
}

for event in pull_request push; do
	prepare_checkout "${event}" "${TARGET_SHA}"
	select_base "${event}" "${BASE_SHA}" || fail "${event} selection failed"
	check_selection true "${BASE_SHA}"
	grep -qx "fetch --no-tags --depth=1 origin ${BASE_SHA}" "${CASE_DIR}/git.log" || fail "${event} did not fetch only its exact predecessor"
	[ "$(run_git -C "${CASE_DIR}" rev-list --all --count "${TARGET_SHA}" "${BASE_SHA}")" -le 3 ] || fail 'selection imported historical ancestry'
done

prepare_checkout force_push "${TARGET_SHA}"
select_base push "${DISPLACED_SHA}" || fail 'force-push predecessor selection failed'
check_selection true "${DISPLACED_SHA}"

prepare_checkout new_branch "${TARGET_SHA}"
select_base push "${ZERO_SHA}" || fail 'new branch predecessor selection failed'
check_selection true "${PARENT_SHA}"
if grep -q '^fetch ' "${CASE_DIR}/git.log"; then
	fail 'new branch unnecessarily fetched its already present parent'
fi

prepare_checkout root_commit "${ROOT_SHA}"
select_base push "${ZERO_SHA}" || fail 'root commit selection failed'
check_selection false ''
grep -q 'full vulnerability report' "${CASE_DIR}/selection.log" || fail 'root commit fallback was not explicit'

prepare_checkout missing_predecessor "${TARGET_SHA}"
select_base push ffffffffffffffffffffffffffffffffffffffff || fail 'missing predecessor should select full reporting'
check_selection false ''
grep -q 'full vulnerability report' "${CASE_DIR}/selection.log" || fail 'missing predecessor silently skipped vulnerability reporting'

case_number=0
for unsafe_revision in main origin/main --upload-pack=anything 0000000000000000000000000000000000000000 'abcdef0123456789abcdef0123456789abcdef0123^'; do
	case_number=$((case_number + 1))
	prepare_checkout "unsafe-${case_number}" "${TARGET_SHA}"
	if select_base pull_request "${unsafe_revision}"; then
		fail 'unsafe or nonexact predecessor was accepted'
	fi
	[ ! -s "${CASE_DIR}/output" ] || fail 'invalid selection enabled reporting'
	if grep -q '^fetch ' "${CASE_DIR}/git.log"; then
		fail 'invalid predecessor reached git fetch'
	fi
done

prepare_checkout unsupported_event "${TARGET_SHA}"
if select_base workflow_dispatch "${BASE_SHA}"; then
	fail 'unsupported differential event was accepted'
fi
[ ! -s "${CASE_DIR}/output" ] || fail 'unsupported event enabled reporting'

case_number=0
for invalid_candidate in "${ZERO_SHA}" --upload-pack=anything eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee "${BASE_SHA}"; do
	case_number=$((case_number + 1))
	prepare_checkout "invalid-candidate-${case_number}" "${TARGET_SHA}"
	CASE_TARGET="${invalid_candidate}"
	if select_base push "${BASE_SHA}"; then
		fail 'invalid, missing, or incorrectly checked out candidate was accepted'
	fi
	[ ! -s "${CASE_DIR}/output" ] || fail 'invalid candidate enabled reporting'
	if grep -q '^fetch ' "${CASE_DIR}/git.log"; then
		fail 'invalid candidate reached git fetch'
	fi
done

prepare_checkout missing_origin "${TARGET_SHA}"
run_git -C "${CASE_DIR}" remote remove origin || fail 'could not isolate missing-origin fault'
if select_base push "${BASE_SHA}"; then
	fail 'missing origin silently selected full reporting'
fi
[ ! -s "${CASE_DIR}/output" ] || fail 'missing origin enabled reporting'

prepare_checkout missing_repository "${TARGET_SHA}"
rm -rf "${CASE_DIR}/.git" || fail 'could not isolate missing-repository fault'
if select_base push "${BASE_SHA}"; then
	fail 'missing repository silently selected full reporting'
fi
[ ! -s "${CASE_DIR}/output" ] || fail 'missing repository enabled reporting'

prepare_checkout output_failure "${TARGET_SHA}"
rm "${CASE_DIR}/output" && mkdir "${CASE_DIR}/output" || fail 'could not isolate output-write fault'
if select_base push "${PARENT_SHA}"; then
	fail 'selection succeeded without publishing workflow outputs'
fi

printf '%s\n' 'PASS: bounded exact OSV baselines and explicit full-report fallbacks preserve vulnerability reporting'
