#!/bin/sh
# Regression test verifying every .agents/skills/*/SKILL.md file has
# well-formed YAML frontmatter: a closed '---' block, a 'name' field that
# matches its own directory (so an agent loading skills by directory name
# resolves the intended skill), a non-empty 'description', and, when present,
# a non-empty 'triggers' list with no blank entries. Malformed frontmatter is
# silently ignored by most skill loaders, so this only fails loudly here.

set -u

# fail reports a failure message to standard error and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $1" >&2
	exit 1
}

SKILLS_DIR='.agents/skills'
[ -d "${SKILLS_DIR}" ] || fail "expected skills directory not found: ${SKILLS_DIR}"

TMP_ROOT=$(mktemp -d) || fail 'unable to create exclusive temp workspace'
trap 'rm -rf "${TMP_ROOT}"' EXIT
trap 'rm -rf "${TMP_ROOT}"; exit 1' HUP INT TERM

# Validate a single SKILL.md file. Returns 0 on success, 1 on validation failure.
# Does NOT call the global `fail` function - caller decides how to handle failures.
# validate_skill_md validates a SKILL.md file's frontmatter, required fields, trigger list, and body content against its expected skill name.
validate_skill_md() {
	skill_md="$1"
	expected_name="$2"

	# The frontmatter must open on line 1.
	first_line=$(sed -n '1p' "${skill_md}")
	if [ "${first_line}" != '---' ]; then
		printf '%s\n' "${skill_md}: expected line 1 to be '---', got: '${first_line}'" >&2
		return 1
	fi

	# Locate the closing '---' (first exact match after line 1).
	close_line=$(awk 'NR>1 && $0=="---" { print NR; exit }' "${skill_md}")
	if [ -z "${close_line}" ]; then
		printf '%s\n' "${skill_md}: frontmatter block is never closed with a lone '---' line" >&2
		return 1
	fi

	FRONTMATTER="${TMP_ROOT}/frontmatter.$$"
	sed -n "2,$((close_line - 1))p" "${skill_md}" >"${FRONTMATTER}"

	# 'name:' must be present exactly once and match the containing directory name exactly.
	name_count=$(grep -cE '^name:[[:space:]]*' "${FRONTMATTER}")
	if [ "${name_count}" -ne 1 ]; then
		printf '%s\n' "${skill_md}: frontmatter must have exactly one 'name' field, found ${name_count}" >&2
		rm -f "${FRONTMATTER}"
		return 1
	fi
	name_line=$(grep -E '^name:[[:space:]]*' "${FRONTMATTER}")
	actual_name=$(printf '%s\n' "${name_line}" | sed -e 's/^name:[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')
	if [ "${actual_name}" != "${expected_name}" ]; then
		printf '%s\n' "${skill_md}: frontmatter name '${actual_name}' does not match directory '${expected_name}'" >&2
		rm -f "${FRONTMATTER}"
		return 1
	fi

	# 'description:' must be present exactly once and non-empty once quotes are stripped.
	description_count=$(grep -cE '^description:[[:space:]]*' "${FRONTMATTER}")
	if [ "${description_count}" -ne 1 ]; then
		printf '%s\n' "${skill_md}: frontmatter must have exactly one 'description' field, found ${description_count}" >&2
		rm -f "${FRONTMATTER}"
		return 1
	fi
	description_line=$(grep -E '^description:[[:space:]]*' "${FRONTMATTER}")
	# Strip 'description:' prefix and trailing whitespace.
	actual_description=$(printf '%s\n' "${description_line}" | sed -e 's/^description:[[:space:]]*//' -e 's/[[:space:]]*$//')
	# If the value starts with a quote, extract quoted content; otherwise take everything up to #.
	case "${actual_description}" in
		\"*)
			# Double-quoted string: strip the surrounding quotes and any trailing inline comment
			actual_description=$(printf '%s\n' "${actual_description}" |
				sed -n 's/^"\(.*\)"[[:space:]]*\(#.*\)\{0,1\}$/\1/p')
			;;
		\'*)
			# Single-quoted string: strip the surrounding quotes and any trailing inline comment
			actual_description=$(printf '%s\n' "${actual_description}" |
				sed -n "s/^'\(.*\)'[[:space:]]*\(#.*\)\{0,1\}$/\1/p")
			;;
		*)
			# Unquoted: strip everything from # onward (inline comment), then trailing whitespace
			actual_description=$(printf '%s\n' "${actual_description}" | sed -e 's/#.*//' -e 's/[[:space:]]*$//')
			;;
	esac
	if [ -z "${actual_description}" ]; then
		printf '%s\n' "${skill_md}: 'description' field is empty" >&2
		rm -f "${FRONTMATTER}"
		return 1
	fi

	# When a 'triggers:' field is declared, validate its form and content.
	# There must be exactly one 'triggers:' field, not multiple.
	if grep -Eq '^triggers:' "${FRONTMATTER}"; then
		triggers_count=$(grep -cE '^triggers:' "${FRONTMATTER}")
		if [ "${triggers_count}" -ne 1 ]; then
			printf '%s\n' "${skill_md}: frontmatter must have at most one 'triggers' field, found ${triggers_count}" >&2
			rm -f "${FRONTMATTER}"
			return 1
		fi
		triggers_line=$(grep -E '^triggers:' "${FRONTMATTER}")

		# Check for inline empty list: triggers: []
		if printf '%s\n' "${triggers_line}" | grep -Eq '^triggers:[[:space:]]*\[\][[:space:]]*$'; then
			printf '%s\n' "${skill_md}: 'triggers:' is an empty inline list []" >&2
			rm -f "${FRONTMATTER}"
			return 1
		fi

		# Check for inline list with values: triggers: [a, b, c]
		if printf '%s\n' "${triggers_line}" | grep -Eq '^triggers:[[:space:]]*\['; then
			# Valid inline list - must have closing bracket and non-empty content
			if ! printf '%s\n' "${triggers_line}" | grep -Eq '^triggers:[[:space:]]*\[[^]]*\][[:space:]]*$'; then
				printf '%s\n' "${skill_md}: 'triggers:' inline list is unterminated or has trailing content" >&2
				rm -f "${FRONTMATTER}"
				return 1
			fi
			if ! printf '%s\n' "${triggers_line}" | grep -Eq '^triggers:[[:space:]]*\[[[:space:]]*[^][:space:]]'; then
				printf '%s\n' "${skill_md}: 'triggers:' inline list is empty or malformed" >&2
				rm -f "${FRONTMATTER}"
				return 1
			fi
			if printf '%s\n' "${triggers_line}" | grep -Eq '\[[[:space:]]*,|,[[:space:]]*,|,[[:space:]]*\]'; then
				printf '%s\n' "${skill_md}: 'triggers:' inline list contains a blank item" >&2
				rm -f "${FRONTMATTER}"
				return 1
			fi
		# Check for scalar (non-list) value: triggers: invalid
		elif ! printf '%s\n' "${triggers_line}" | grep -Eq '^triggers:[[:space:]]*$'; then
			printf '%s\n' "${skill_md}: 'triggers:' has a scalar value (expected a list)" >&2
			rm -f "${FRONTMATTER}"
			return 1
		# Block-list form: triggers: (followed by list items on subsequent lines)
		else
			trigger_count=$(awk '
				/^triggers:[[:space:]]*$/ { intriggers = 1; next }
				intriggers && /^[a-zA-Z_-]+:/ { exit }
				intriggers && /^[[:space:]]*-[[:space:]]*/ { print }
			' "${FRONTMATTER}" | wc -l | tr -d '[:space:]')
			if [ "${trigger_count}" -le 0 ]; then
				printf '%s\n' "${skill_md}: 'triggers:' declared but no list items found" >&2
				rm -f "${FRONTMATTER}"
				return 1
			fi

			blank_trigger_count=$(awk '
				/^triggers:[[:space:]]*$/ { intriggers = 1; next }
				intriggers && /^[a-zA-Z_-]+:/ { exit }
				intriggers && /^[[:space:]]*-[[:space:]]*$/ { print }
			' "${FRONTMATTER}" | wc -l | tr -d '[:space:]')
			if [ "${blank_trigger_count}" -ne 0 ]; then
				printf '%s\n' "${skill_md}: 'triggers:' contains one or more blank list items" >&2
				rm -f "${FRONTMATTER}"
				return 1
			fi
		fi
	fi

	# There must be actual skill content after the closing '---', not just an
	# empty file with a dangling frontmatter block.
	body_lines=$(sed -n "$((close_line + 1)),\$p" "${skill_md}" | grep -c '[^[:space:]]')
	if [ "${body_lines}" -le 0 ]; then
		printf '%s\n' "${skill_md}: no content found after the frontmatter block" >&2
		rm -f "${FRONTMATTER}"
		return 1
	fi

	rm -f "${FRONTMATTER}"
	return 0
}

# Regression tests for triggers validation logic
TEST_SKILLS_DIR="${TMP_ROOT}/test-skills"
mkdir -p "${TEST_SKILLS_DIR}" || fail 'could not create test skills directory'

# Test case: empty inline list should be rejected
TEST_SKILL_DIR="${TEST_SKILLS_DIR}/test-empty-inline-triggers"
mkdir -p "${TEST_SKILL_DIR}"
cat >"${TEST_SKILL_DIR}/SKILL.md" <<'EOF'
---
name: test-empty-inline-triggers
description: Test skill with empty inline triggers list
triggers: []
---
# Test Skill
Content here.
EOF
if validate_skill_md "${TEST_SKILL_DIR}/SKILL.md" "test-empty-inline-triggers"; then
	fail "regression: empty inline triggers list fixture unexpectedly passed validation"
fi

# Test case: inline list with a blank item should be rejected
TEST_SKILL_DIR="${TEST_SKILLS_DIR}/test-blank-inline-trigger"
mkdir -p "${TEST_SKILL_DIR}"
cat >"${TEST_SKILL_DIR}/SKILL.md" <<'EOF'
---
name: test-blank-inline-trigger
description: Test skill with a blank inline trigger
triggers: [foo, , bar]
---
# Test Skill
Content here.
EOF
if validate_skill_md "${TEST_SKILL_DIR}/SKILL.md" "test-blank-inline-trigger"; then
	fail "regression: blank inline trigger fixture unexpectedly passed validation"
fi

# Test case: scalar/invalid value should be rejected
TEST_SKILL_DIR="${TEST_SKILLS_DIR}/test-scalar-triggers"
mkdir -p "${TEST_SKILL_DIR}"
cat >"${TEST_SKILL_DIR}/SKILL.md" <<'EOF'
---
name: test-scalar-triggers
description: Test skill with scalar triggers value
triggers: invalid
---
# Test Skill
Content here.
EOF
if validate_skill_md "${TEST_SKILL_DIR}/SKILL.md" "test-scalar-triggers"; then
	fail "regression: scalar triggers value fixture unexpectedly passed validation"
fi

# Test case: unterminated inline list should be rejected
TEST_SKILL_DIR="${TEST_SKILLS_DIR}/test-unterminated-inline-triggers"
mkdir -p "${TEST_SKILL_DIR}"
cat >"${TEST_SKILL_DIR}/SKILL.md" <<'EOF'
---
name: test-unterminated-inline-triggers
description: Test skill with unterminated inline triggers list
triggers: [foo, bar, baz
---
# Test Skill
Content here.
EOF
if validate_skill_md "${TEST_SKILL_DIR}/SKILL.md" "test-unterminated-inline-triggers"; then
	fail "regression: unterminated inline triggers list fixture unexpectedly passed validation"
fi

# Test case: valid inline list should be accepted
TEST_SKILL_DIR="${TEST_SKILLS_DIR}/test-valid-inline-triggers"
mkdir -p "${TEST_SKILL_DIR}"
cat >"${TEST_SKILL_DIR}/SKILL.md" <<'EOF'
---
name: test-valid-inline-triggers
description: Test skill with valid inline triggers list
triggers: [foo, bar, baz]
---
# Test Skill
Content here.
EOF
if ! validate_skill_md "${TEST_SKILL_DIR}/SKILL.md" "test-valid-inline-triggers"; then
	fail "regression: valid inline triggers list fixture unexpectedly failed validation"
fi

# Test case: valid block-list should be accepted
TEST_SKILL_DIR="${TEST_SKILLS_DIR}/test-valid-block-triggers"
mkdir -p "${TEST_SKILL_DIR}"
cat >"${TEST_SKILL_DIR}/SKILL.md" <<'EOF'
---
name: test-valid-block-triggers
description: Test skill with valid block-form triggers list
triggers:
  - trigger1
  - trigger2
---
# Test Skill
Content here.
EOF
if ! validate_skill_md "${TEST_SKILL_DIR}/SKILL.md" "test-valid-block-triggers"; then
	fail "regression: valid block-form triggers list fixture unexpectedly failed validation"
fi

# Test case: description with only inline comment should be rejected
TEST_SKILL_DIR="${TEST_SKILLS_DIR}/test-description-comment-only"
mkdir -p "${TEST_SKILL_DIR}"
cat >"${TEST_SKILL_DIR}/SKILL.md" <<'EOF'
---
name: test-description-comment-only
description: # comment
---
# Test Skill
Content here.
EOF
if validate_skill_md "${TEST_SKILL_DIR}/SKILL.md" "test-description-comment-only"; then
	fail "regression: description with only inline comment fixture unexpectedly passed validation"
fi

# Test case: description with empty string and inline comment should be rejected
TEST_SKILL_DIR="${TEST_SKILLS_DIR}/test-description-empty-comment"
mkdir -p "${TEST_SKILL_DIR}"
cat >"${TEST_SKILL_DIR}/SKILL.md" <<'EOF'
---
name: test-description-empty-comment
description: "" # comment
---
# Test Skill
Content here.
EOF
if validate_skill_md "${TEST_SKILL_DIR}/SKILL.md" "test-description-empty-comment"; then
	fail "regression: description with empty string and inline comment fixture unexpectedly passed validation"
fi

# Test case: duplicate triggers fields (one valid, one invalid) should be rejected
TEST_SKILL_DIR="${TEST_SKILLS_DIR}/test-duplicate-triggers"
mkdir -p "${TEST_SKILL_DIR}"
cat >"${TEST_SKILL_DIR}/SKILL.md" <<'EOF'
---
name: test-duplicate-triggers
description: Test skill with duplicate triggers fields
triggers: [valid]
triggers: invalid
---
# Test Skill
Content here.
EOF
if validate_skill_md "${TEST_SKILL_DIR}/SKILL.md" "test-duplicate-triggers"; then
	fail "regression: duplicate triggers fields fixture unexpectedly passed validation"
fi

# Test case: valid quoted description with hash character should be accepted
TEST_SKILL_DIR="${TEST_SKILLS_DIR}/test-valid-description-with-hash"
mkdir -p "${TEST_SKILL_DIR}"
cat >"${TEST_SKILL_DIR}/SKILL.md" <<'EOF'
---
name: test-valid-description-with-hash
description: "This is a valid description with #hashtag in it"
---
# Test Skill
Content here.
EOF
if ! validate_skill_md "${TEST_SKILL_DIR}/SKILL.md" "test-valid-description-with-hash"; then
	fail "regression: valid quoted description with hash character fixture unexpectedly failed validation"
fi

# Test case: quoted description followed by an inline comment should be accepted
TEST_SKILL_DIR="${TEST_SKILLS_DIR}/test-description-quoted-inline-comment"
mkdir -p "${TEST_SKILL_DIR}"
cat >"${TEST_SKILL_DIR}/SKILL.md" <<'EOF'
---
name: test-description-quoted-inline-comment
description: "Valid text" # comment
---
# Test Skill
Content here.
EOF
if ! validate_skill_md "${TEST_SKILL_DIR}/SKILL.md" "test-description-quoted-inline-comment"; then
	fail "regression: quoted description with inline comment fixture unexpectedly failed validation"
fi

# Test case: empty single-quoted description should be rejected
TEST_SKILL_DIR="${TEST_SKILLS_DIR}/test-description-empty-single-quote"
mkdir -p "${TEST_SKILL_DIR}"
cat >"${TEST_SKILL_DIR}/SKILL.md" <<'EOF'
---
name: test-description-empty-single-quote
description: ''
---
# Test Skill
Content here.
EOF
if validate_skill_md "${TEST_SKILL_DIR}/SKILL.md" "test-description-empty-single-quote"; then
	fail "regression: empty single-quoted description fixture unexpectedly passed validation"
fi

CHECKED=0

for skill_md in "${SKILLS_DIR}"/*/SKILL.md; do
	[ -f "${skill_md}" ] || continue
	CHECKED=$((CHECKED + 1))

	skill_dir=$(dirname "${skill_md}")
	expected_name=$(basename "${skill_dir}")

	# Use the shared validation function and fail the whole script on any validation error
	if ! validate_skill_md "${skill_md}" "${expected_name}"; then
		fail "validation failed for ${skill_md}"
	fi
done

[ "${CHECKED}" -gt 0 ] || fail "no SKILL.md files found under ${SKILLS_DIR}"

printf '%s\n' "PASS: all ${CHECKED} SKILL.md file(s) under ${SKILLS_DIR} have well-formed frontmatter"
