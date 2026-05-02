#!/bin/sh
# List repository shell scripts that should be checked by CI.
# BusyBox/ash-compatible and intentionally conservative.

set -u

is_shell_script() {
	_path="$1"
	_first_line="$(sed -n '1p' "${_path}" 2>/dev/null || true)"

	case "${_path}" in
		installer | *.sh | S99AdGuardHome | rc.func.AdGuardHome | */S99AdGuardHome | */rc.func.AdGuardHome)
			return 0
			;;
	esac

	case "${_first_line}" in
		'#!'*'/sh'*) return 0 ;;
		'#!'*' sh'*) return 0 ;;
		'#!'*'/ash'*) return 0 ;;
		'#!'*' ash'*) return 0 ;;
		'#!'*'/dash'*) return 0 ;;
		'#!'*' dash'*) return 0 ;;
	esac

	return 1
}

find . -type f ! -path './.git/*' ! -path './.github/*' | sort | while IFS= read -r file; do
	path="${file#./}"
	if is_shell_script "${path}"; then
		printf '%s\n' "${path}"
	fi
done
