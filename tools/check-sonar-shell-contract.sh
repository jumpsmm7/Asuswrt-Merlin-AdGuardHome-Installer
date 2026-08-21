#!/bin/sh
# Enforce the repository-controlled Sonar shell analysis contract.

set -u

CONFIG_FILE="sonar-project.properties"
GUARDRAIL_FILE="SONAR-GUARDRAILS.md"
FAILED=0

fail() {
	local _message
	_message="$1"
	printf '%s\n' "Error: ${_message}" >&2
	FAILED=1
	return 0
}

require_text() {
	local _file _text
	_file="$1"
	_text="$2"
	if ! grep -F "${_text}" "${_file}" >/dev/null 2>&1; then
		fail "missing required Sonar contract text in ${_file}: ${_text}"
	fi
	return 0
}

for required_file in "${CONFIG_FILE}" "${GUARDRAIL_FILE}" AGENTS.md .amazonq/rules/AGENTS.md REVIEW.md; do
	if [ ! -f "${required_file}" ]; then
		fail "required Sonar contract file is missing: ${required_file}"
	fi
done

if [ "${FAILED}" -ne 0 ]; then
	exit 1
fi

require_text "${CONFIG_FILE}" 'sonar.shell.file.suffixes=.sh'
require_text "${CONFIG_FILE}" 'sonar.lang.patterns.shell=**/*.sh,installer,S99AdGuardHome,rc.func.AdGuardHome'
require_text "${CONFIG_FILE}" 'SONAR-GUARDRAILS.md and tools/check-sonar-shell-contract.sh'

sonar_exclusions="$(sed -n 's/^sonar\.exclusions=//p' "${CONFIG_FILE}")"
sonar_exclusion_entries="$(printf '%s\n' "${sonar_exclusions}" | tr ',' '\n')"
while IFS= read -r sonar_exclusion; do
	sonar_exclusion="$(printf '%s\n' "${sonar_exclusion}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
	case "${sonar_exclusion}" in
		'*' | '**' | '*/*' | '**/*')
			fail "blanket Sonar exclusion is not allowed: ${sonar_exclusion}"
			break
			;;
		*'*.sh'* | installer | */installer | S99AdGuardHome | */S99AdGuardHome | rc.func.AdGuardHome | */rc.func.AdGuardHome | AdGuardHome.sh | */AdGuardHome.sh)
			fail "router runtime shell must not be excluded from Sonar analysis: ${sonar_exclusion}"
			break
			;;
		*) : ;;
	esac
done <<EOF_SONAR_EXCLUSIONS
${sonar_exclusion_entries}
EOF_SONAR_EXCLUSIONS

if grep -E '^sonar\.issue\.ignore\.multicriteria\.[^.]+\.ruleKey=(shell|shelldre):\*$' "${CONFIG_FILE}" >/dev/null 2>&1; then
	fail 'blanket Sonar Shell rule suppressions are not allowed'
fi

require_text "${GUARDRAIL_FILE}" 'A Sonar parser diagnostic alone does not prove a defect.'
require_text "${GUARDRAIL_FILE}" 'Do not use blanket `shell:*` or `shelldre:*` issue suppressions.'
require_text AGENTS.md 'BusyBox `ash`'
require_text .amazonq/rules/AGENTS.md 'BusyBox `ash`'
require_text REVIEW.md 'BusyBox `ash`'

if [ "${FAILED}" -ne 0 ]; then
	exit 1
fi

printf '%s\n' 'PASS: Sonar shell analysis remains aligned with the BusyBox/POSIX contract'
