#!/bin/sh
# Verify installer/runtime scripts prefer stock commands and privileged startup
# is isolated from caller-controlled paths.

set -u

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

[ -f installer ] || fail "missing installer script"
installer_path_statement="$(sed -n '/^export PATH=/p' installer | sed -n '1p')"
expected_installer_path='export PATH="/sbin:/bin:/usr/sbin:/usr/bin${PATH:+:$PATH}"'
[ "${installer_path_statement}" = "${expected_installer_path}" ] ||
	fail "installer does not export its expected bootstrap PATH"

for script in AdGuardHome.sh S99AdGuardHome rc.func.AdGuardHome; do
	[ -f "${script}" ] || fail "missing runtime script: ${script}"

	path_statement="$(sed -n '/^export PATH=/p' "${script}" | sed -n '1p')"
	expected_path='export PATH="/sbin:/bin:/usr/sbin:/usr/bin:/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin"'
	[ "${path_statement}" = "${expected_path}" ] ||
		fail "${script} does not export its expected runtime PATH"

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
		*:/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin*) ;;
		*) fail "${script} does not include the Entware binary directories" ;;
	esac
done

PATH="/feedback-test-path"
export PATH="/sbin:/bin:/usr/sbin:/usr/bin${PATH:+:$PATH}"
case ":${PATH}:" in
	*:/feedback-test-path:*) ;;
	*) fail "stock path initialization discarded the caller PATH" ;;
esac

PATH=""
export PATH="/sbin:/bin:/usr/sbin:/usr/bin${PATH:+:$PATH}"
case "${PATH}" in
	*: | *::* | :*) fail "stock path initialization added an empty PATH component" ;;
esac

PATH="/feedback-test-path"
export PATH="/sbin:/bin:/usr/sbin:/usr/bin:/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin"
case ":${PATH}:" in
	*:/feedback-test-path:*) fail "privileged service startup inherited the caller PATH" ;;
esac

printf '%s\n' "PASS: runtime scripts prioritize trusted command paths"
