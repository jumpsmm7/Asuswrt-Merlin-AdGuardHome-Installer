#!/bin/sh
# Check every repository shell script for syntax and target-shell constructs.

set -u

FAILED=0
SCRIPT_LIST="${TMPDIR:-/tmp}/shell-portability-scripts.$$"

cleanup() {
	rm -f "${SCRIPT_LIST}"
}

fail_match() {
	_description="$1"
	_pattern="$2"
	_script="$3"
	if grep -En "${_pattern}" "${_script}"; then
		printf '%s\n' "Error: ${_description}: ${_script}" >&2
		FAILED=1
	fi
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

sh tools/list-shell-scripts.sh >"${SCRIPT_LIST}" || exit 1
while IFS= read -r script; do
	[ -n "${script}" ] || continue
	if ! sh -n "${script}"; then
		printf '%s\n' "Error: POSIX shell syntax check failed: ${script}" >&2
		FAILED=1
	fi
	first_line="$(sed -n '1p' "${script}" 2>/dev/null)"
	if [ "${first_line}" != '#!/bin/sh' ]; then
		printf '%s\n' "Error: shell script must use #!/bin/sh: ${script}" >&2
		FAILED=1
	fi
	[ "${script}" = "tools/check-shell-portability.sh" ] && continue
	fail_match 'Bash test syntax is not supported' '\[\[[[:space:]]' "${script}"
	fail_match 'Bash function syntax is not supported' '^[[:space:]]*function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\{' "${script}"
	fail_match 'the source keyword is not POSIX' '(^|[;&|])[[:space:]]*source[[:space:]]' "${script}"
	fail_match 'echo -e is not portable' '(^|[;&|])[[:space:]]*echo[[:space:]]+-e([[:space:]]|$)' "${script}"
	fail_match 'command -v is unavailable on the target shell; use which' '(^|&&|\|\||;)[[:space:]]*command[[:space:]]+-v[[:space:]]+' "${script}"
	fail_match 'Bash here-strings are not supported' '<<<' "${script}"
	fail_match 'Bash process substitution is not supported' '(^|[^$])(<|>)\(' "${script}"
	fail_match 'multi-digit positional parameters are unsupported by older BusyBox ash; shift first' '\$\{[1-9][0-9]+([^0-9]|$)' "${script}"
done <"${SCRIPT_LIST}"

if [ "${FAILED}" -ne 0 ]; then
	exit 1
fi
printf '%s\n' 'PASS: all repository shell scripts use supported POSIX/BusyBox syntax'
