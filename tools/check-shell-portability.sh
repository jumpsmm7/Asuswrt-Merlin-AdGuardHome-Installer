#!/bin/sh
# Check repository shell scripts for POSIX/BusyBox syntax and router command policy.

set -u

FAILED=0
SCRIPT_LIST="$(mktemp "${TMPDIR:-/tmp}/shell-portability-scripts.XXXXXX")" || exit 1
SANITIZED_FILE="$(mktemp "${TMPDIR:-/tmp}/shell-portability-sanitized.XXXXXX")" || {
	rm -f "${SCRIPT_LIST}"
	exit 1
}

# cleanup removes checker scratch files.
cleanup() {
	rm -f "${SCRIPT_LIST}" "${SANITIZED_FILE}"
	return 0
}

# report_match reports a policy violation when the sanitized shell source matches an ERE.
report_match() {
	_description="$1"
	_pattern="$2"
	_script="$3"
	if grep -En "${_pattern}" "${SANITIZED_FILE}"; then
		printf '%s\n' "Error: ${_description}: ${_script}" >&2
		FAILED=1
	fi
	return 0
}

# sanitize_shell_source removes comments, single-quoted embedded programs, and literal heredoc bodies.
sanitize_shell_source() {
	_source_file="$1"
	awk '
		BEGIN { single = 0; embedded = 0; heredoc = "" }
		{
			line = $0
			# Existing optional Entware authentication support is an approved python3 flow.
			if (line ~ /\/opt\/bin\/python3[[:space:]]+-c/ && line ~ /bcrypt/) { print ""; next }
			if (embedded) {
				if (line ~ /^[[:space:]]*'"'"'([[:space:]]|$)/) { embedded = 0; single = 0 }
				print ""
				next
			}
			if (line ~ /(^|[[:space:]])(awk|\/usr\/bin\/awk)[^#]*'"'"'[[:space:]]*$/) {
				embedded = 1
				single = 0
				print ""
				next
			}
			if (heredoc != "") {
				if (line == heredoc) heredoc = ""
				print ""
				next
			}
			out = ""
			double = 0
			escape = 0
			for (i = 1; i <= length(line); i++) {
				c = substr(line, i, 1)
				if (escape) { if (!single) out = out c; escape = 0; continue }
				if (!single && c == "\\") { out = out c; escape = 1; continue }
				if (!single && !double) {
					tail = substr(line, i)
					quote = sprintf("%c", 39)
					if (match(tail, "^<<[[:space:]]*" quote "[A-Za-z_][A-Za-z0-9_]*" quote)) {
						token = substr(tail, RSTART, RLENGTH)
						sub("^<<[[:space:]]*" quote, "", token)
						sub(quote "$", "", token)
						heredoc = token
						out = out " "
						i += RLENGTH - 1
						continue
					}
				}
				if (c == sprintf("%c", 39)) { single = !single; out = out " "; continue }
				if (!single && c == "\"") { double = !double; out = out c; continue }
				if (!single && !double && c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[[:space:]]/)) break
				if (!single) out = out c
			}
			print out
		}
	' "${_source_file}" >"${SANITIZED_FILE}"
	return $?
}

# runtime_script reports whether command dependency restrictions apply to a production router script.
runtime_script() {
	case "${1##*/}" in
		installer | AdGuardHome.sh | S99AdGuardHome | rc.func.AdGuardHome) return 0 ;;
		*) return 1 ;;
	esac
}

# check_runtime_commands rejects commands unavailable from the router runtime contract.
check_runtime_commands() {
	_script="$1"
	for _command in realpath timeout perl python; do
		if grep -En "(^[[:space:]]*|[;&|()][[:space:]]*)(/[^;&|()[:space:]]*/)?${_command}([[:space:]]|$)" "${SANITIZED_FILE}"; then
			printf '%s\n' "Error: unapproved router-runtime ${_command} dependency: ${_script}" >&2
			FAILED=1
		fi
	done
	if grep -En '(^[[:space:]]*|[;&|()][[:space:]]*)(/[^;&|()[:space:]]*/)?python3([[:space:]]|$)' "${SANITIZED_FILE}" |
		grep -Ev 'blocklist_analyzer|bcrypt|ensure_opkg_package[[:space:]]+python3|opkg[[:space:]]+install[[:space:]]+python3' >/dev/null; then
		printf '%s\n' "Error: unapproved router-runtime python3 dependency: ${_script}" >&2
		FAILED=1
	fi
	if grep -Eq '(^[[:space:]]*|[;&|()][[:space:]]*)flock([[:space:]]|$)' "${SANITIZED_FILE}" &&
		{ ! grep -q 'flock_supports_fd' "${SANITIZED_FILE}" || ! grep -Eq 'mkdir.*fallback|fallback.*mkdir|mkdir.*(LOCK|lock)|Lock_Mkdir|proc_lock_run' "${SANITIZED_FILE}"; }; then
		printf '%s\n' "Error: unconditional flock use lacks the capability probe and mkdir/PID fallback: ${_script}" >&2
		FAILED=1
	fi
	return 0
}

# check_script applies syntax and conservative command-position policy checks to one file.
check_script() {
	_script="$1"
	if ! sh -n "${_script}"; then
		printf '%s\n' "Error: POSIX shell syntax check failed: ${_script}" >&2
		FAILED=1
	fi
	first_line="$(sed -n '1p' "${_script}" 2>/dev/null)"
	if [ "${first_line}" != '#!/bin/sh' ]; then
		printf '%s\n' "Error: shell script must use #!/bin/sh: ${_script}" >&2
		FAILED=1
	fi
	[ "${_script}" = tools/check-shell-portability.sh ] && return 0
	sanitize_shell_source "${_script}" || { FAILED=1; return 0; }
	report_match 'Bash test syntax is not supported' '(^[[:space:]]*|[;&|()][[:space:]]*)\[\[[[:space:]]' "${_script}"
	report_match 'Bash function syntax is not supported' '^[[:space:]]*function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "${_script}"
	report_match 'the source keyword is not POSIX' '(^[[:space:]]*|[;&|()][[:space:]]*)source[[:space:]]+' "${_script}"
	report_match 'echo -e is not portable' '(^[[:space:]]*|[;&|()][[:space:]]*)echo[[:space:]]+-e([[:space:]]|$)' "${_script}"
	report_match 'command -v is unavailable; use which' '(^[[:space:]]*|[;&|()][[:space:]]*)command[[:space:]]+-v[[:space:]]+' "${_script}"
	report_match 'Bash here-strings are not supported' '<<<' "${_script}"
	report_match 'Bash process substitution is not supported' '(^|[^$])(<|>)\(' "${_script}"
	report_match 'Bash parameter replacement is not supported' '\$\{[A-Za-z_][A-Za-z0-9_]*//?[^}]+\}' "${_script}"
	report_match 'pipefail is not supported' '(^[[:space:]]*|[;&|()][[:space:]]*)set[[:space:]]+(-[^[:space:]]*[[:space:]]+|-[[:space:]]+o[[:space:]]+)pipefail([[:space:]]|$)' "${_script}"
	report_match 'mapfile is not supported' '(^[[:space:]]*|[;&|()][[:space:]]*)mapfile([[:space:]]|$)' "${_script}"
	report_match 'readarray is not supported' '(^[[:space:]]*|[;&|()][[:space:]]*)readarray([[:space:]]|$)' "${_script}"
	report_match 'read -a arrays are not supported' '(^[[:space:]]*|[;&|()][[:space:]]*)read[[:space:]]+[^;&|]*-[^;&|[:space:]]*a([[:space:]]|$)' "${_script}"
	report_match 'select is not supported' '(^[[:space:]]*|[;&|()][[:space:]]*)select[[:space:]]+[A-Za-z_]' "${_script}"
	report_match 'coproc is not supported' '(^[[:space:]]*|[;&|()][[:space:]]*)coproc([[:space:]]|$)' "${_script}"
	if runtime_script "${_script}"; then check_runtime_commands "${_script}"; fi
	return 0
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

if [ "$#" -gt 0 ]; then
	printf '%s\n' "$@" >"${SCRIPT_LIST}"
else
	sh tools/list-shell-scripts.sh >"${SCRIPT_LIST}" || exit 1
fi
while IFS= read -r script; do
	[ -n "${script}" ] || continue
	case "${script}" in
		tests/fixtures/portability/*) continue ;;
		*) check_script "${script}" ;;
	esac
done <"${SCRIPT_LIST}"

if [ "$#" -eq 0 ] && ! sh tools/check-sonar-shell-contract.sh; then FAILED=1; fi
[ "${FAILED}" -eq 0 ] || exit 1
printf '%s\n' 'PASS: all repository shell scripts use supported POSIX/BusyBox syntax and router commands'
