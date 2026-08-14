#!/bin/sh
# Verify optional database links preserve unexpected /tmp objects.

set -u

SCRIPT_PATH="${1:-AdGuardHome.sh}"
TEST_ROOT=""
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/optional-database-links.XXXXXX")" || {
	printf '%s\n' 'FAIL: could not create private test directory' >&2
	exit 1
}
FUNCTIONS_FILE="${TEST_ROOT}/functions"
LOG_FILE="${TEST_ROOT}/log"

# cleanup removes the temporary test directory when it has been initialized.
cleanup() {
	[ -n "${TEST_ROOT}" ] && rm -rf "${TEST_ROOT}"
}

# fail reports a test failure and exits with a nonzero status.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

[ "$(id -u)" -eq 0 ] || fail 'foreign-owned database link checks require root privileges; run this test as root or with passwordless sudo'

mkdir -p "${TEST_ROOT}/tmp" "${TEST_ROOT}/work/data" || fail 'could not create test directories'
/bin/sed -n '/^canonical_path() {$/,/^}$/p; /^database_link_matches_expected() {$/,/^}$/p; /^database_link_owned_by_current_user() {$/,/^}$/p; /^database_link_object_type() {$/,/^}$/p; /^ensure_database_link() {$/,/^}$/p; /^remove_database_link() {$/,/^}$/p' \
	"${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" || fail 'could not extract database link helpers'
[ -s "${FUNCTIONS_FILE}" ] || fail 'database link helpers were not found'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

# have_cmd checks whether a command is available in the system PATH.
have_cmd() {
	which "$1" >/dev/null 2>&1
}

# agh_log records a message in the configured log file.
agh_log() {
	printf '%s\n' "$*" >>"${LOG_FILE}"
}

EXPECTED="${TEST_ROOT}/work/data/stats.db"
LINK="${TEST_ROOT}/tmp/stats.db"

# Missing paths are created even when the database itself does not exist yet.
ensure_database_link "${LINK}" "${EXPECTED}" || fail 'missing link was treated as fatal'
database_link_matches_expected "${LINK}" "${EXPECTED}" || fail 'missing link was not created correctly'

# A correct link is unchanged.
CORRECT_DETAILS="$(ls -ld "${LINK}")"
ensure_database_link "${LINK}" "${EXPECTED}" || fail 'correct link was treated as fatal'
[ "$(ls -ld "${LINK}")" = "${CORRECT_DETAILS}" ] || fail 'correct link was changed'

# A stale link is preserved and identified as a symlink.
rm "${LINK}" || fail 'could not reset correct link'
ln -s "${TEST_ROOT}/work/data/sessions.db" "${LINK}" || fail 'could not create stale link'
ensure_database_link "${LINK}" "${EXPECTED}" || fail 'stale link was treated as fatal'
[ "$(readlink "${LINK}")" = "${TEST_ROOT}/work/data/sessions.db" ] || fail 'stale link was replaced'
/bin/grep -q 'object_type=symlink' "${LOG_FILE}" || fail 'stale link warning omitted its object type'

# A broken unexpected link is also preserved.
rm "${LINK}" || fail 'could not reset stale link'
ln -s "${TEST_ROOT}/absent.db" "${LINK}" || fail 'could not create broken link'
ensure_database_link "${LINK}" "${EXPECTED}" || fail 'broken link was treated as fatal'
[ -L "${LINK}" ] && [ ! -e "${LINK}" ] || fail 'broken link was replaced or removed'

# Regular files and directories are never removed or replaced.
rm "${LINK}" || fail 'could not reset broken link'
printf '%s\n' preserve >"${LINK}" || fail 'could not create regular file'
ensure_database_link "${LINK}" "${EXPECTED}" || fail 'regular file was treated as fatal'
[ "$(cat "${LINK}")" = preserve ] || fail 'regular file was changed'
/bin/grep -q 'object_type=regular-file' "${LOG_FILE}" || fail 'regular-file warning omitted its object type'
rm "${LINK}" || fail 'could not reset regular file'
mkdir "${LINK}" || fail 'could not create directory'
ensure_database_link "${LINK}" "${EXPECTED}" || fail 'directory was treated as fatal'
[ -d "${LINK}" ] || fail 'directory was changed'
/bin/grep -q 'object_type=directory' "${LOG_FILE}" || fail 'directory warning omitted its object type'

# A permission-denied link creation is optional and logs the missing type.
rmdir "${LINK}" || fail 'could not reset directory'
# ln always fails with a nonzero status.
ln() { return 1; }
ensure_database_link "${LINK}" "${EXPECTED}" || fail 'permission-denied link creation gated startup'
[ ! -e "${LINK}" ] && [ ! -L "${LINK}" ] || fail 'permission-denied fixture unexpectedly created a link'
/bin/grep -q 'reason=link_create_failed object_type=missing' "${LOG_FILE}" || fail 'permission-denied warning omitted the object type'
unset -f ln 2>/dev/null || true

# Stop cleanup removes only an expected link.
command ln -s "${EXPECTED}" "${LINK}" || fail 'could not create cleanup link'
remove_database_link "${LINK}" "${EXPECTED}"
[ ! -L "${LINK}" ] || fail 'expected link was not removed on stop'
command ln -s "${TEST_ROOT}/absent.db" "${LINK}" || fail 'could not create foreign cleanup link'
remove_database_link "${LINK}" "${EXPECTED}"
[ -L "${LINK}" ] || fail 'unexpected link was removed on stop'

# Unresolvable foreign and expected paths must not compare as equal empty names.
rm "${LINK}" || fail 'could not reset foreign cleanup link'
command ln -s "${TEST_ROOT}/missing-parent/foreign.db" "${LINK}" || fail 'could not create unresolved foreign link'
remove_database_link "${LINK}" "${TEST_ROOT}/other-missing-parent/stats.db"
[ -L "${LINK}" ] || fail 'unresolved foreign link was removed on stop'

# A foreign-owned symlink is preserved even when it has the expected target.
rm "${LINK}" || fail 'could not reset unresolved foreign link'
command ln -s "${EXPECTED}" "${LINK}" || fail 'could not create foreign-owned link'
chown -h 65534 "${LINK}" || fail 'could not assign foreign link ownership'
ensure_database_link "${LINK}" "${EXPECTED}" || fail 'foreign-owned link was treated as fatal'
remove_database_link "${LINK}" "${EXPECTED}"
[ -L "${LINK}" ] || fail 'foreign-owned link was removed'

printf '%s\n' 'Optional database link tests passed.'
