#!/bin/sh
# Enforce the repository-controlled Sonar shell analysis contract.

set -u

CONFIG_FILE="sonar-project.properties"
GUARDRAIL_FILE="SONAR-GUARDRAILS.md"
FAILED=0

fail() {
	printf '%s\n' "Error: $1" >&2
	FAILED=1
}

require_text() {
	_file="$1"
	_text="$2"
	if ! grep -F "${_text}" "${_file}" >/dev/null 2>&1; then
		fail "missing required Sonar contract text in ${_file}: ${_text}"
	fi
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
normalized_exclusions=",${sonar_exclusions},"
case "${normalized_exclusions}" in
	*'*.sh'* | *',installer,'* | *',S99AdGuardHome,'* | *',rc.func.AdGuardHome,'* | *',AdGuardHome.sh,'*)
		fail 'router runtime shell must not be excluded from Sonar analysis'
		;;
	*) : ;;
esac

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
