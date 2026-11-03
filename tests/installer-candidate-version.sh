#!/bin/sh
# Verify exact installer stable/candidate version parsing without executing source.

set -u

INSTALLER_PATH="${1:-installer}"
TEST_ROOT="${TMPDIR:-/tmp}/installer-candidate-version.$$"

# fail reports a version contract failure and terminates the isolated fixture.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}
# cleanup removes only this fixture's temporary files.
cleanup() { rm -rf "${TEST_ROOT}"; }
trap cleanup 0
trap 'exit 1' HUP INT TERM
mkdir -p "${TEST_ROOT}" || fail 'could not create version fixture'
sed -n '/^installer_version_value() {$/,/^}/p' "${INSTALLER_PATH}" >"${TEST_ROOT}/helpers" || fail 'could not read installer'
grep -q '^installer_version_value() {$' "${TEST_ROOT}/helpers" || fail 'exact candidate version reader is missing'
# shellcheck disable=SC1090
. "${TEST_ROOT}/helpers"

for version in v2.6.7 v2.7.0 v2.7.0-rc.1 v2.7.0-rc.99 v02.7.00; do
	printf '%s\n' '#!/bin/sh' "AI_VERSION=\"${version}\"" 'exit 77' >"${TEST_ROOT}/candidate file"
	actual="$(installer_version_value "${TEST_ROOT}/candidate file")" || fail "valid version refused: ${version}"
	[ "${actual}" = "${version#v}" ] || fail "version identity changed: ${version} -> ${actual}"
done
for version in '' v2.7 v2.7.0.1 v2.7.0-rc v2.7.0-rc.0 v2.7.0-rc.01 v2.7.0-rc.100 v2.7.0-beta.1 v2.7.0-rc.1junk v2.7.0-rc.1+meta v2.7.0junk v222.7.0 2.7.0; do
	printf '%s\n' "AI_VERSION=\"${version}\"" >"${TEST_ROOT}/candidate file"
	if installer_version_value "${TEST_ROOT}/candidate file" >"${TEST_ROOT}/invalid" 2>/dev/null; then
		fail "invalid version accepted: ${version}"
	fi
	[ ! -s "${TEST_ROOT}/invalid" ] || fail 'invalid version emitted a usable identity'
done
printf '%s\n' 'AI_VERSION="v2.7.0-rc.1"' 'AI_VERSION="v2.7.0"' >"${TEST_ROOT}/candidate file"
if installer_version_value "${TEST_ROOT}/candidate file" >/dev/null 2>&1; then fail 'duplicate installer identities accepted'; fi
printf '%s\n' 'AI_VERSION="v2.7.0-rc.1"; touch SHOULD_NOT_EXIST' >"${TEST_ROOT}/candidate file"
if installer_version_value "${TEST_ROOT}/candidate file" >/dev/null 2>&1; then fail 'trailing source commands accepted as a version'; fi
[ ! -e SHOULD_NOT_EXIST ] || fail 'version reader executed source text'
if installer_version_value "${TEST_ROOT}/missing" >/dev/null 2>&1; then fail 'missing source accepted'; fi
printf '%s\n' 'PASS: stable/candidate identity remains exact; invalid, duplicate and executable text refused'
