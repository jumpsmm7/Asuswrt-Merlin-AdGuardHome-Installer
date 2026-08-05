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

	# When a 'triggers:' list is declared, it must contain at least one
	# non-blank '- ' item and no blank entries mixed in.
	if grep -Eq '^triggers:[[:space:]]*$' "${FRONTMATTER}"; then
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

	# There must be actual skill content after the closing '---', not just an
	# empty file with a dangling frontmatter block.
	body_lines=$(sed -n "$((close_line + 1)),\$p" "${skill_md}" | grep -c '[^[:space:]]')
	[ "${body_lines}" -gt 0 ] || fail "${skill_md}: no content found after the frontmatter block"

	rm -f "${FRONTMATTER}"
done

[ "${CHECKED}" -gt 0 ] || fail "no SKILL.md files found under ${SKILLS_DIR}"

printf '%s\n' "PASS: all ${CHECKED} SKILL.md file(s) under ${SKILLS_DIR} have well-formed frontmatter"
