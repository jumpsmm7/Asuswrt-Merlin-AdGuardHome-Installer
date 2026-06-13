#!/bin/sh
# Verify runtime scripts prefer stock commands without discarding caller paths.

set -u

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

for script in AdGuardHome.sh S99AdGuardHome rc.func.AdGuardHome; do
	[ -f "${script}" ] || fail "missing runtime script: ${script}"

	path_statement="$(sed -n '/^export PATH=/p' "${script}" | sed -n '1p')"
	expected_path='export PATH="/sbin:/bin:/usr/sbin:/usr/bin:/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin:${PATH:-}"'
	[ "${path_statement}" = "${expected_path}" ] ||
		fail "${script} does not prepend stock paths while preserving the caller PATH"

	environment_lines="$(awk '
		NR == 1 { next }
		/^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
		{ print }
		count++ == 1 { exit }
	' "${script}")"
	expected_lines="export LC_ALL=C
${expected_path}"
	[ "${environment_lines}" = "${expected_lines}" ] ||
		fail "${script} executes code before setting its locale and PATH"
done

for script in AdGuardHome.sh S99AdGuardHome rc.func.AdGuardHome; do
	case "$(sed -n '/^export PATH=/p' "${script}" | sed -n '1p')" in
		*:/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin:*) ;;
		*) fail "${script} does not include the Entware binary directories" ;;
	esac
done

PATH="/feedback-test-path"
export PATH="/sbin:/bin:/usr/sbin:/usr/bin:${PATH:-}"
case ":${PATH}:" in
	*:/feedback-test-path:*) ;;
	*) fail "stock path initialization discarded the caller PATH" ;;
esac

printf '%s\n' "PASS: runtime scripts prioritize stock commands and preserve caller paths"
