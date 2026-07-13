#!/bin/sh
# Verify invalid YAML quarantine failures are reported as failures, not moved successes.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-yaml-validation-rollback.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions.sh"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

cleanup() {
	rm -rf "${TMP_ROOT}"
}
trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

mkdir -p "${TMP_ROOT}" || fail 'could not create test directory'
awk '
	/^PTXT\(\)/,/^}/
	/^ptxt_step\(\)/,/^}/
	/^ptxt_ok\(\)/,/^}/
	/^ptxt_warn\(\)/,/^}/
	/^rollback_result_write\(\)/,/^}/
	/^rollback_result_summary\(\)/,/^}/
	/^rollback_result_notice\(\)/,/^}/
	/^check_AdGuardHome_yaml\(\)/,/^}/
' "${SCRIPT_PATH}" >"${FUNCTIONS_FILE}"
[ -s "${FUNCTIONS_FILE}" ] || fail 'could not extract functions'

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	INFO='Info:'
	WARNING='Warning:'
	AGH_FILE="${TMP_ROOT}/AdGuardHome"
	YAML_FILE="${TMP_ROOT}/AdGuardHome.yaml"
	YAML_ERR="${TMP_ROOT}/AdGuardHome.yaml.err"
	ROLLBACK_RESULT_FILE="${TMP_ROOT}/rollback-result"

	cat >"${AGH_FILE}" <<'SCRIPT'
#!/bin/sh
exit 1
SCRIPT
	chmod 755 "${AGH_FILE}"
	printf '%s\n' 'invalid yaml' >"${YAML_FILE}"

	mv() {
		case "${2:-}" in
			"${YAML_ERR}") return 1 ;;
		esac
		command mv "$@"
	}

	if check_AdGuardHome_yaml "${YAML_FILE}"; then
		fail 'invalid YAML validation unexpectedly succeeded'
	fi
	[ -f "${YAML_FILE}" ] || fail 'failed quarantine removed the live YAML'
	[ ! -e "${YAML_ERR}" ] || fail 'failed quarantine created YAML_ERR'
	grep -q '^result=yaml-quarantine-failed$' "${ROLLBACK_RESULT_FILE}" || fail 'failed quarantine did not record yaml-quarantine-failed'
) || exit 1

printf '%s\n' 'PASS: YAML quarantine failures keep live YAML and record failure result'
