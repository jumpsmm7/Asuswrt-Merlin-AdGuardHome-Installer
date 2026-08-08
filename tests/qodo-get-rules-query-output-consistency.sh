#!/bin/sh
# Regression test for the qodo-get-rules query-generation and output-format
# reference docs. These two files define the exact RuleCategory vocabulary,
# the three-line query structure, and the severity/labeling contract that the
# SKILL.md workflow (Steps 4-7) depends on. A future edit that adds, removes,
# or reorders a category in one file but not the other, or that changes the
# printed header/severity wording in only one place, would silently degrade
# retrieval quality or produce inconsistent output without any other check
# noticing.

set -u

SKILL='.agents/skills/qodo-get-rules/SKILL.md'
QUERY_GEN='.agents/skills/qodo-get-rules/references/query-generation.md'
OUTPUT_FMT='.agents/skills/qodo-get-rules/references/output-format.md'

# fail prints a failure message to stderr and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $1" >&2
	exit 1
}

for f in "${SKILL}" "${QUERY_GEN}" "${OUTPUT_FMT}"; do
	[ -f "${f}" ] || fail "expected qodo-get-rules doc not found: ${f}"
done

# --- SKILL.md must link to both reference docs it delegates to in Steps 4-6,
# so a rename of either file doesn't silently orphan the workflow step that
# points to it.
grep -Fq '(references/query-generation.md)' "${SKILL}" || fail "${SKILL}: missing a link to references/query-generation.md"
grep -Fq '(references/output-format.md)' "${SKILL}" || fail "${SKILL}: missing a link to references/output-format.md"

# --- The RuleCategory vocabulary declared inline in SKILL.md's Step 4 query
# template must be the same ordered list as the Category bullet list in
# query-generation.md, since both feed the same embedding-based search.
# Extract each independently rather than hardcoding the list here, so this
# test tracks the real content instead of a hand-copied duplicate.
SKILL_CATEGORY_LINE=$(grep -m1 '^Category: {one of:' "${SKILL}")
[ -n "${SKILL_CATEGORY_LINE}" ] || fail "${SKILL}: could not find the 'Category: {one of: ...}' template line"
SKILL_CATEGORIES=$(printf '%s\n' "${SKILL_CATEGORY_LINE}" |
	sed -e 's/^Category: {one of: //' -e 's/}$//' |
	tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
[ -n "${SKILL_CATEGORIES}" ] || fail "${SKILL}: parsed an empty category list from the Step 4 template"

QUERY_GEN_CATEGORIES=$(awk '
	/^- \*\*Category\*\*:/ { incat = 1; next }
	incat && /^  - `[A-Za-z]+` / { print; next }
	incat && /^- \*\*/ { exit }
' "${QUERY_GEN}" | sed -E 's/^  - `([A-Za-z]+)`.*/\1/')
[ -n "${QUERY_GEN_CATEGORIES}" ] || fail "${QUERY_GEN}: could not extract any Category bullet entries"

[ "${SKILL_CATEGORIES}" = "${QUERY_GEN_CATEGORIES}" ] || fail "category vocabulary differs between ${SKILL} and ${QUERY_GEN}:
--- ${SKILL} ---
${SKILL_CATEGORIES}
--- ${QUERY_GEN} ---
${QUERY_GEN_CATEGORIES}"

# --- Sanity check on the extraction itself: guard against a future edit that
# empties or trivially shortens either list without the comparison above
# noticing (e.g. both files losing all but one shared category).
CATEGORY_COUNT=$(printf '%s\n' "${SKILL_CATEGORIES}" | grep -c '.')
[ "${CATEGORY_COUNT}" -eq 10 ] || fail "expected exactly 10 categories in the Step 4 template, found ${CATEGORY_COUNT}: ${SKILL_CATEGORIES}"
for expected in Security Correctness Quality Reliability Performance Testability Compliance Accessibility Observability Architecture; do
	printf '%s\n' "${SKILL_CATEGORIES}" | grep -Fxq "${expected}" || fail "expected category '${expected}' missing from the Step 4 template"
done

# --- The three-line structured query format (Name/Category/Content, in that
# exact order) must be documented identically in both SKILL.md's Step 4 and
# query-generation.md's embedding-vector illustration, since the embedding
# model depends on this exact field order.
for f in "${SKILL}" "${QUERY_GEN}"; do
	FIELD_ORDER=$(grep -oE '^(Name|Category|Content):' "${f}" | head -n3 | tr '\n' ',')
	[ "${FIELD_ORDER}" = 'Name:,Category:,Content:,' ] || fail "${f}: expected the first three-line template to declare Name:, Category:, then Content:, got: ${FIELD_ORDER}"
done

# --- TOP_K's documented default of 20 must agree between SKILL.md's Step 5
# and query-generation.md's worked example; a drift here would make one doc's
# guidance silently wrong relative to the other.
grep -Fq 'default: 20' "${SKILL}" || fail "${SKILL}: expected Step 5 to document the TOP_K default as 20"
grep -Fq 'top_k=20 each' "${QUERY_GEN}" || fail "${QUERY_GEN}: expected the worked example to call the search endpoint with top_k=20 each"

# --- Both queries per assignment (topic + cross-cutting) must be described
# consistently as a pair of exactly two queries in both files.
grep -Fq 'two structured search queries' "${SKILL}" || fail "${SKILL}: expected Step 4 to require generating two structured search queries"
grep -Fq 'Generate **two queries**' "${QUERY_GEN}" || fail "${QUERY_GEN}: expected the Multi-Query Strategy section to require exactly two queries"

# --- The "Qodo Rules Loaded" header text must be present, byte-identical,
# both in the workflow instructions in SKILL.md and the literal template in
# output-format.md, since a human reads the printed header to confirm rules
# were actually retrieved for the current task.
HEADER='📋 Qodo Rules Loaded'
[ -n "${HEADER}" ] || fail 'internal test error: HEADER constant is empty'
grep -Fq "${HEADER}" "${SKILL}" || fail "${SKILL}: missing the '${HEADER}' header text"
grep -Fq "${HEADER}" "${OUTPUT_FMT}" || fail "${OUTPUT_FMT}: missing the '${HEADER}' header text"

# --- The three severities referenced by SKILL.md's Step 7 enforcement table
# must match the exact set output-format.md declares as valid {SEVERITY}
# values, so a rule with a severity the output formatter doesn't recognize
# can never be silently misrendered.
# Extract each independently rather than hardcoding the list here, so this
# test tracks the real content instead of a hand-copied duplicate.
SKILL_SEVERITIES=$(grep -oE '^\| \*\*[A-Z]+\*\* \|' "${SKILL}" |
	sed -E 's/^\| \*\*([A-Z]+)\*\* \|$/\1/' | sort)
[ -n "${SKILL_SEVERITIES}" ] || fail "${SKILL}: could not extract any severities from the Step 7 enforcement table"

OUTPUT_FMT_SEVERITIES=$(grep 'is one of:' "${OUTPUT_FMT}" |
	tr ',' '\n' | sed 's/.*`\([A-Z]*\)`.*/\1/' | grep -E '^[A-Z]+$' | sort)
[ -n "${OUTPUT_FMT_SEVERITIES}" ] || fail "${OUTPUT_FMT}: could not extract any severities from the 'is one of:' line"

[ "${SKILL_SEVERITIES}" = "${OUTPUT_FMT_SEVERITIES}" ] || fail "severity vocabulary differs between ${SKILL} and ${OUTPUT_FMT}:
--- ${SKILL} ---
${SKILL_SEVERITIES}
--- ${OUTPUT_FMT} ---
${OUTPUT_FMT_SEVERITIES}"

# --- The per-rule output line format must be the literal bold-name +
# bracketed-severity + colon-content pattern shown in output-format.md, so a
# future reformat can't silently drop the severity label rules are enforced
# by.
grep -Fq -- '- **{name}** [{SEVERITY}]: {content}' "${OUTPUT_FMT}" || fail "${OUTPUT_FMT}: missing the literal per-rule output line template"

# --- An empty rules list must never be treated as an error in either doc.
grep -Fq 'empty result is valid' "${OUTPUT_FMT}" || fail "${OUTPUT_FMT}: missing the 'empty result is valid' guidance"
grep -Fq 'Crashing on empty results' "${SKILL}" || fail "${SKILL}: missing the 'Crashing on empty results' common-mistake entry"

printf '%s\n' 'PASS: qodo-get-rules query-generation and output-format docs stay consistent with SKILL.md'
