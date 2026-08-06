#!/bin/sh
# Regression test verifying every .agents/skills/*/SKILL.md file has
# well-formed YAML frontmatter: a closed '---' block, a 'name' field that
# matches its own directory (so an agent loading skills by directory name
# resolves the intended skill), a non-empty 'description', and, when present,
# a non-empty 'triggers' list with no blank entries. Malformed frontmatter is
# silently ignored by most skill loaders, so this only fails loudly here.

set -u

fail() {
	printf '%s\n' "FAIL: $1" >&2
	exit 1
}

SKILLS_DIR='.agents/skills'
[ -d "${SKILLS_DIR}" ] || fail "expected skills directory not found: ${SKILLS_DIR}"

TMP_ROOT=$(mktemp -d) || fail 'unable to create exclusive temp workspace'
trap 'rm -rf "${TMP_ROOT}"' EXIT
trap 'rm -rf "${TMP_ROOT}"; exit 1' HUP INT TERM

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
FRONTMATTER="${TMP_ROOT}/frontmatter.$$"
sed -n "2,4p" "${TEST_SKILL_DIR}/SKILL.md" >"${FRONTMATTER}"
if grep -Eq '^triggers:' "${FRONTMATTER}"; then
	triggers_line=$(grep -E '^triggers:' "${FRONTMATTER}")
	if printf '%s\n' "${triggers_line}" | grep -Eq '^triggers:[[:space:]]*\[\][[:space:]]*$'; then
		: # Expected: empty inline list detected
	else
		fail "regression: empty inline triggers list was not detected"
	fi
else
	fail "regression: triggers field not found in test fixture"
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
sed -n "2,4p" "${TEST_SKILL_DIR}/SKILL.md" >"${FRONTMATTER}"
if grep -Eq '^triggers:' "${FRONTMATTER}"; then
	triggers_line=$(grep -E '^triggers:' "${FRONTMATTER}")
	if printf '%s\n' "${triggers_line}" | grep -Eq '^triggers:[[:space:]]*\['; then
		fail "regression: scalar triggers value was misidentified as inline list"
	elif ! printf '%s\n' "${triggers_line}" | grep -Eq '^triggers:[[:space:]]*$'; then
		: # Expected: scalar value detected
	else
		fail "regression: scalar triggers value was not detected"
	fi
else
	fail "regression: triggers field not found in test fixture"
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
sed -n "2,4p" "${TEST_SKILL_DIR}/SKILL.md" >"${FRONTMATTER}"
if grep -Eq '^triggers:' "${FRONTMATTER}"; then
	triggers_line=$(grep -E '^triggers:' "${FRONTMATTER}")
	# Should detect as inline list (starts with [)
	if printf '%s\n' "${triggers_line}" | grep -Eq '^triggers:[[:space:]]*\['; then
		# Should fail validation due to missing closing bracket
		if printf '%s\n' "${triggers_line}" | grep -Eq '^triggers:[[:space:]]*\[[^]]*\][[:space:]]*$'; then
			fail "regression: unterminated inline triggers list was accepted"
		else
			: # Expected: unterminated list rejected
		fi
	else
		fail "regression: unterminated inline triggers list was not detected as inline format"
	fi
else
	fail "regression: triggers field not found in test fixture"
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
sed -n "2,4p" "${TEST_SKILL_DIR}/SKILL.md" >"${FRONTMATTER}"
if grep -Eq '^triggers:' "${FRONTMATTER}"; then
	triggers_line=$(grep -E '^triggers:' "${FRONTMATTER}")
	if printf '%s\n' "${triggers_line}" | grep -Eq '^triggers:[[:space:]]*\['; then
		if printf '%s\n' "${triggers_line}" | grep -Eq '^triggers:[[:space:]]*\[[[:space:]]*[^][:space:]]'; then
			: # Expected: valid inline list accepted
		else
			fail "regression: valid inline triggers list was rejected"
		fi
	else
		fail "regression: inline triggers list was not detected"
	fi
else
	fail "regression: triggers field not found in test fixture"
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
sed -n "2,5p" "${TEST_SKILL_DIR}/SKILL.md" >"${FRONTMATTER}"
if grep -Eq '^triggers:[[:space:]]*$' "${FRONTMATTER}"; then
	trigger_count=$(awk '
		/^triggers:[[:space:]]*$/ { intriggers = 1; next }
		intriggers && /^[a-zA-Z_-]+:/ { exit }
		intriggers && /^[[:space:]]*-[[:space:]]*/ { print }
	' "${FRONTMATTER}" | wc -l | tr -d '[:space:]')
	[ "${trigger_count}" -gt 0 ] || fail "regression: valid block-form triggers list was rejected"
else
	fail "regression: block-form triggers not detected"
fi

rm -f "${FRONTMATTER}"

CHECKED=0

for skill_md in "${SKILLS_DIR}"/*/SKILL.md; do
	[ -f "${skill_md}" ] || continue
	CHECKED=$((CHECKED + 1))

	skill_dir=$(dirname "${skill_md}")
	expected_name=$(basename "${skill_dir}")

	# The frontmatter must open on line 1.
	first_line=$(sed -n '1p' "${skill_md}")
	[ "${first_line}" = '---' ] || fail "${skill_md}: expected line 1 to be '---', got: '${first_line}'"

	# Locate the closing '---' (first exact match after line 1).
	close_line=$(awk 'NR>1 && $0=="---" { print NR; exit }' "${skill_md}")
	[ -n "${close_line}" ] || fail "${skill_md}: frontmatter block is never closed with a lone '---' line"

	FRONTMATTER="${TMP_ROOT}/frontmatter.$$"
	sed -n "2,$((close_line - 1))p" "${skill_md}" >"${FRONTMATTER}"

	# 'name:' must be present exactly once and match the containing directory name exactly.
	name_count=$(grep -cE '^name:[[:space:]]*' "${FRONTMATTER}")
	[ "${name_count}" -eq 1 ] || fail "${skill_md}: frontmatter must have exactly one 'name' field, found ${name_count}"
	name_line=$(grep -E '^name:[[:space:]]*' "${FRONTMATTER}")
	actual_name=$(printf '%s\n' "${name_line}" | sed -e 's/^name:[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')
	[ "${actual_name}" = "${expected_name}" ] || fail "${skill_md}: frontmatter name '${actual_name}' does not match directory '${expected_name}'"

	# 'description:' must be present exactly once and non-empty once quotes are stripped.
	description_count=$(grep -cE '^description:[[:space:]]*' "${FRONTMATTER}")
	[ "${description_count}" -eq 1 ] || fail "${skill_md}: frontmatter must have exactly one 'description' field, found ${description_count}"
	description_line=$(grep -E '^description:[[:space:]]*' "${FRONTMATTER}")
	actual_description=$(printf '%s\n' "${description_line}" | sed -e 's/^description:[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')
	[ -n "${actual_description}" ] || fail "${skill_md}: 'description' field is empty"

	# When a 'triggers:' field is declared, validate its form and content.
	if grep -Eq '^triggers:' "${FRONTMATTER}"; then
		triggers_line=$(grep -E '^triggers:' "${FRONTMATTER}")

		# Check for inline empty list: triggers: []
		if printf '%s\n' "${triggers_line}" | grep -Eq '^triggers:[[:space:]]*\[\][[:space:]]*$'; then
			fail "${skill_md}: 'triggers:' is an empty inline list []"
		fi

		# Check for inline list with values: triggers: [a, b, c]
		if printf '%s\n' "${triggers_line}" | grep -Eq '^triggers:[[:space:]]*\['; then
			# Valid inline list - must have closing bracket and non-empty content
			if ! printf '%s\n' "${triggers_line}" | grep -Eq '^triggers:[[:space:]]*\[[^]]*\][[:space:]]*$'; then
				fail "${skill_md}: 'triggers:' inline list is unterminated or has trailing content"
			fi
			if ! printf '%s\n' "${triggers_line}" | grep -Eq '^triggers:[[:space:]]*\[[[:space:]]*[^][:space:]]'; then
				fail "${skill_md}: 'triggers:' inline list is empty or malformed"
			fi
		# Check for scalar (non-list) value: triggers: invalid
		elif ! printf '%s\n' "${triggers_line}" | grep -Eq '^triggers:[[:space:]]*$'; then
			fail "${skill_md}: 'triggers:' has a scalar value (expected a list)"
		# Block-list form: triggers: (followed by list items on subsequent lines)
		else
			trigger_count=$(awk '
				/^triggers:[[:space:]]*$/ { intriggers = 1; next }
				intriggers && /^[a-zA-Z_-]+:/ { exit }
				intriggers && /^[[:space:]]*-[[:space:]]*/ { print }
			' "${FRONTMATTER}" | wc -l | tr -d '[:space:]')
			[ "${trigger_count}" -gt 0 ] || fail "${skill_md}: 'triggers:' declared but no list items found"

			blank_trigger_count=$(awk '
				/^triggers:[[:space:]]*$/ { intriggers = 1; next }
				intriggers && /^[a-zA-Z_-]+:/ { exit }
				intriggers && /^[[:space:]]*-[[:space:]]*$/ { print }
			' "${FRONTMATTER}" | wc -l | tr -d '[:space:]')
			[ "${blank_trigger_count}" -eq 0 ] || fail "${skill_md}: 'triggers:' contains one or more blank list items"
		fi
	fi

	# There must be actual skill content after the closing '---', not just an
	# empty file with a dangling frontmatter block.
	body_lines=$(sed -n "$((close_line + 1)),\$p" "${skill_md}" | grep -c '[^[:space:]]')
	[ "${body_lines}" -gt 0 ] || fail "${skill_md}: no content found after the frontmatter block"

	rm -f "${FRONTMATTER}"
done

[ "${CHECKED}" -gt 0 ] || fail "no SKILL.md files found under ${SKILLS_DIR}"

printf '%s\n' "PASS: all ${CHECKED} SKILL.md file(s) under ${SKILLS_DIR} have well-formed frontmatter"
