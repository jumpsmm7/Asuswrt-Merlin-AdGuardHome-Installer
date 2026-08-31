#!/bin/sh
# Regression test for tools/code-quality.sh: the local/CI quality-check runner.
# Extracts the runner's helper functions (and its CLI argument parsing block)
# verbatim from the script and exercises them in isolation, so this test tracks
# the real implementation instead of a hand-copied re-implementation.

set -u

SCRIPT_PATH='tools/code-quality.sh'

# fail prints a failure message containing the specified reason to standard error and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $1" >&2
	exit 1
}

[ -f "${SCRIPT_PATH}" ] || fail "expected script not found: ${SCRIPT_PATH}"

TMP_ROOT=$(mktemp -d) || fail 'unable to create exclusive temp workspace'
trap 'rm -rf "${TMP_ROOT}"' EXIT
trap 'rm -rf "${TMP_ROOT}"; exit 1' HUP INT TERM

FUNCTIONS_FILE="${TMP_ROOT}/functions.sh"
sed -n \
	'/^cleanup() {$/,/^}$/p; /^have_cmd() {$/,/^}$/p; /^require_cmd() {$/,/^}$/p; /^configure_test_timeout() {$/,/^}$/p; /^run_test_command() {$/,/^}$/p; /^run_privileged_test_command() {$/,/^}$/p; /^run_check() {$/,/^}$/p; /^run_privileged_regression_check() {$/,/^}$/p; /^run_script_list_check() {$/,/^}$/p' \
	"${SCRIPT_PATH}" >"${FUNCTIONS_FILE}"
[ -s "${FUNCTIONS_FILE}" ] || fail 'function extraction from tools/code-quality.sh was empty (helper functions may have been renamed)'

for fn in cleanup have_cmd require_cmd configure_test_timeout run_test_command run_privileged_test_command run_check run_privileged_regression_check run_script_list_check; do
	grep -Fq "${fn}() {" "${FUNCTIONS_FILE}" || fail "extracted functions file is missing ${fn}()"
done

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"
TEST_MAX_RUNTIME_SECONDS=0
GNU_TIMEOUT="/usr/bin/timeout"

# Only the documented coreutils path may enable the GNU-specific option; a
# non-approved timeout provider must be rejected by configure_test_timeout.
GNU_TIMEOUT="${TMP_ROOT}/unapproved-timeout"
TEST_MAX_RUNTIME_SECONDS=180
printf '%s\n' '#!/bin/sh' 'printf "%s\n" "not GNU timeout"' >"${GNU_TIMEOUT}" || fail 'could not create non-GNU timeout fixture'
chmod 755 "${GNU_TIMEOUT}" || fail 'could not make non-GNU timeout fixture executable'
configure_test_timeout 2>/dev/null && fail 'unapproved timeout provider was accepted'
GNU_TIMEOUT="/usr/bin/timeout"
TEST_MAX_RUNTIME_SECONDS=180
configure_test_timeout || fail 'approved GNU timeout path was rejected'
[ "${GNU_TIMEOUT}" = /usr/bin/timeout ] || fail 'approved GNU timeout path was not retained'

# A bounded privileged regression must launch timeout as root so it can signal
# every root-owned descendant, while an unbounded local run invokes the test
# directly through sudo.
PRIVILEGED_ARGS_FILE="${TMP_ROOT}/privileged-args"
# sudo records its arguments in the privileged-arguments file.
sudo() {
	printf '%s\n' "$*" >"${PRIVILEGED_ARGS_FILE}"
}
TEST_MAX_RUNTIME_SECONDS=180
GNU_TIMEOUT=/usr/bin/timeout
run_privileged_test_command sh tests/optional-database-links.sh || fail 'bounded privileged command failed'
[ "$(cat "${PRIVILEGED_ARGS_FILE}")" = '-n /usr/bin/timeout --kill-after=10 180 sh tests/optional-database-links.sh' ] ||
	fail 'bounded timeout was not placed inside sudo'
TEST_MAX_RUNTIME_SECONDS=0
run_privileged_test_command sh tests/optional-database-links.sh || fail 'unbounded privileged command failed'
[ "$(cat "${PRIVILEGED_ARGS_FILE}")" = '-n sh tests/optional-database-links.sh' ] ||
	fail 'unbounded privileged command did not retain direct sudo ordering'
unset -f sudo 2>/dev/null || unset sudo 2>/dev/null || true

# The writable-path and optional database-link regressions validate root-owned
# state.  Verify the runner executes both directly as root so the database
# test's foreign-owned symlink assertions cannot be skipped.  Exercise the same
# run_check dispatch used by the complete quality runner and verify output,
# status accounting, and the test command's observable side effect.
OPTIONAL_DATABASE_OUT_FILE="${TMP_ROOT}/optional-database.out"
OPTIONAL_DATABASE_FAIL_OUT_FILE="${TMP_ROOT}/optional-database-fail.out"
OPTIONAL_DATABASE_RAN_FILE="${TMP_ROOT}/optional-database.ran"
WRITABLE_PATH_RAN_FILE="${TMP_ROOT}/writable-path.ran"
GO_ENVIRONMENT_RAN_FILE="${TMP_ROOT}/go-environment.ran"
LAN_BRIDGE_DOC_RAN_FILE="${TMP_ROOT}/lan-bridge-doc.ran"
PRIVATE_IPV4_FALLBACK_RAN_FILE="${TMP_ROOT}/private-ipv4-fallback.ran"
PROCESS_SIGNALING_RAN_FILE="${TMP_ROOT}/process-signaling.ran"
EVENT_SCRIPT_TRANSACTIONS_RAN_FILE="${TMP_ROOT}/event-script-transactions.ran"
JQ_HELPER_RAN_FILE="${TMP_ROOT}/jq-helper.ran"
TZDATA_PACKAGE_INFO_RAN_FILE="${TMP_ROOT}/tzdata-package-info.ran"
SERVICE_OPT_DISAPPEARANCE_RAN_FILE="${TMP_ROOT}/service-opt-disappearance.ran"
(
	OPTIONAL_DATABASE_STATUS=0
	# id prints 0 to simulate a root user ID in privileged-command tests.
	id() {
		printf '%s\n' 0
	}
	# sh simulates regression-test commands, records their execution, and returns each test's configured status.
	sh() {
		case "$1" in
			tests/wan-nat-predicate-parity.sh)
				return 0
				;;
			tests/installer-event-script-transactions.sh)
				: >"${EVENT_SCRIPT_TRANSACTIONS_RAN_FILE}"
				return 0
				;;
			tests/update-tzdata-package-info.sh)
				: >"${TZDATA_PACKAGE_INFO_RAN_FILE}"
				return 0
				;;
			tests/service-opt-disappearance.sh)
				: >"${SERVICE_OPT_DISAPPEARANCE_RAN_FILE}"
				return 0
				;;
			tests/optional-database-links.sh)
				: >"${OPTIONAL_DATABASE_RAN_FILE}"
				if [ "${OPTIONAL_DATABASE_STATUS}" -eq 0 ]; then
					printf '%s\n' 'PASS: optional database link tests passed'
				else
					printf '%s\n' 'FAIL: simulated optional database link regression failure' >&2
				fi
				return "${OPTIONAL_DATABASE_STATUS}"
				;;
			tests/runtime-writable-path-security.sh)
				: >"${WRITABLE_PATH_RAN_FILE}"
				return 0
				;;
			tests/adguardhome-go-environment.sh)
				: >"${GO_ENVIRONMENT_RAN_FILE}"
				return 0
				;;
			tests/private-ipv4-dns-fallback-chain.sh)
				: >"${PRIVATE_IPV4_FALLBACK_RAN_FILE}"
				return 0
				;;
			tests/rc-process-signaling.sh)
				: >"${PROCESS_SIGNALING_RAN_FILE}"
				return 0
				;;
			tests/lan-bridge-discovery-doc-consistency.sh)
				: >"${LAN_BRIDGE_DOC_RAN_FILE}"
				return 0
				;;
			tests/installer-jq-helper.sh)
				: >"${JQ_HELPER_RAN_FILE}"
				return 0
				;;
		esac
		return 1
	}
	run_privileged_regression_check tests/runtime-writable-path-security.sh 'runtime writable-path security regression' || exit 1
	FAILED=0
	run_check 'AdGuardHome Go runtime environment regression' sh tests/adguardhome-go-environment.sh || exit 1
	[ "${FAILED}" -eq 0 ] || exit 1
	run_check 'Private IPv4 DNS fallback chain regression' sh tests/private-ipv4-dns-fallback-chain.sh || exit 1
	[ "${FAILED}" -eq 0 ] || exit 1
	run_check 'AdGuardHome process signaling regression' sh tests/rc-process-signaling.sh || exit 1
	[ "${FAILED}" -eq 0 ] || exit 1
	run_check 'LAN bridge discovery documentation consistency regression' sh tests/lan-bridge-discovery-doc-consistency.sh || exit 1
	[ "${FAILED}" -eq 0 ] || exit 1
	run_check 'Installer jq dependency regression' sh tests/installer-jq-helper.sh || exit 1
	[ "${FAILED}" -eq 0 ] || exit 1
	run_check 'Installer event-script transaction regression' sh tests/installer-event-script-transactions.sh || exit 1
	[ "${FAILED}" -eq 0 ] || exit 1
	run_check 'tzdata package conversion regression' sh tests/update-tzdata-package-info.sh || exit 1
	[ "${FAILED}" -eq 0 ] || exit 1
	run_check 'AdGuardHome Entware mount disappearance regression' sh tests/service-opt-disappearance.sh || exit 1
	[ "${FAILED}" -eq 0 ] || exit 1
	run_check 'AdGuardHome optional database link regression' run_privileged_regression_check tests/optional-database-links.sh 'optional database link regression' >"${OPTIONAL_DATABASE_OUT_FILE}" 2>&1
	[ "$?" -eq 0 ] || exit 1
	[ "${FAILED}" -eq 0 ] || exit 1
	OPTIONAL_DATABASE_STATUS=1
	FAILED=0
	run_check 'AdGuardHome optional database link regression' run_privileged_regression_check tests/optional-database-links.sh 'optional database link regression' >"${OPTIONAL_DATABASE_FAIL_OUT_FILE}" 2>&1
	[ "$?" -eq 0 ] || exit 1
	[ "${FAILED}" -eq 1 ] || exit 1
) || fail 'root privileged regression dispatch status accounting failed'
[ -f "${WRITABLE_PATH_RAN_FILE}" ] || fail 'writable-path security regression command was not invoked'
[ -f "${GO_ENVIRONMENT_RAN_FILE}" ] || fail 'Go runtime environment regression command was not invoked'
[ -f "${PRIVATE_IPV4_FALLBACK_RAN_FILE}" ] || fail 'private IPv4 fallback regression command was not invoked'
[ -f "${PROCESS_SIGNALING_RAN_FILE}" ] || fail 'process signaling regression command was not invoked'
[ -f "${LAN_BRIDGE_DOC_RAN_FILE}" ] || fail 'LAN bridge documentation regression command was not invoked'
[ -f "${JQ_HELPER_RAN_FILE}" ] || fail 'installer jq helper regression command was not invoked'
[ -f "${EVENT_SCRIPT_TRANSACTIONS_RAN_FILE}" ] || fail 'installer event-script transaction regression command was not invoked'
[ -f "${TZDATA_PACKAGE_INFO_RAN_FILE}" ] || fail 'tzdata package conversion regression command was not invoked'
[ -f "${SERVICE_OPT_DISAPPEARANCE_RAN_FILE}" ] || fail 'Entware mount disappearance regression command was not invoked'
[ -f "${OPTIONAL_DATABASE_RAN_FILE}" ] || fail 'optional database-link regression command was not invoked'
grep -Fq 'PASS: optional database link tests passed' "${OPTIONAL_DATABASE_OUT_FILE}" ||
	fail 'optional database-link regression output was not forwarded'
grep -Fq 'OK: AdGuardHome optional database link regression' "${OPTIONAL_DATABASE_OUT_FILE}" ||
	fail 'optional database-link regression did not report successful status'
grep -Fq 'FAIL: simulated optional database link regression failure' "${OPTIONAL_DATABASE_FAIL_OUT_FILE}" ||
	fail 'optional database-link regression failure output was not forwarded'
grep -Fq 'FAILED: AdGuardHome optional database link regression' "${OPTIONAL_DATABASE_FAIL_OUT_FILE}" ||
	fail 'optional database-link regression did not report failed status'

# Without root or passwordless sudo, the privileged helper must fail through
# run_check, set FAILED, and preserve its actionable privilege diagnostic.
OPTIONAL_DATABASE_UNPRIVILEGED_OUT_FILE="${TMP_ROOT}/optional-database-unprivileged.out"
(
	# id simulates the current user ID by printing 1000.
	id() {
		printf '%s\n' 1000
	}
	# have_cmd checks whether a command is available.
	have_cmd() {
		return 1
	}
	FAILED=0
	run_check 'AdGuardHome optional database link regression' run_privileged_regression_check tests/optional-database-links.sh 'optional database link regression' >"${OPTIONAL_DATABASE_UNPRIVILEGED_OUT_FILE}" 2>&1
	[ "${FAILED}" -eq 1 ] || exit 1
) || fail 'unprivileged optional database-link regression did not set FAILED=1'
grep -Fq 'Error: the optional database link regression requires root privileges or passwordless sudo.' "${OPTIONAL_DATABASE_UNPRIVILEGED_OUT_FILE}" ||
	fail 'unprivileged optional database-link regression omitted its privilege error'
grep -Fq 'FAILED: AdGuardHome optional database link regression' "${OPTIONAL_DATABASE_UNPRIVILEGED_OUT_FILE}" ||
	fail 'unprivileged optional database-link regression did not report failed status'

# --- have_cmd ---------------------------------------------------------------

have_cmd sh || fail 'have_cmd: expected sh to be reported as available'
if have_cmd definitely-not-a-real-command-xyz; then
	fail 'have_cmd: expected a nonexistent command to be reported as unavailable'
fi

# --- require_cmd -------------------------------------------------------------

FAILED=0
require_cmd sh || fail 'require_cmd: unexpectedly failed for an available command'
[ "${FAILED}" -eq 0 ] || fail 'require_cmd: FAILED was set for an available command'

# NOTE: these calls are made directly (not via "$(...)"), because command
# substitution runs in a subshell and would discard the FAILED mutation the
# function makes in the caller's shell.
REQUIRE_OUT_FILE="${TMP_ROOT}/require-cmd.out"
FAILED=0
require_cmd definitely-not-a-real-command-xyz >"${REQUIRE_OUT_FILE}" 2>&1
REQUIRE_RC=$?
[ "${REQUIRE_RC}" -ne 0 ] || fail 'require_cmd: expected non-zero return for a missing command'
[ "${FAILED}" -eq 1 ] || fail 'require_cmd: expected FAILED to be set to 1 for a missing command'
grep -Fq 'is required' "${REQUIRE_OUT_FILE}" || fail "require_cmd: expected an installation hint in output, got: $(cat "${REQUIRE_OUT_FILE}")"

# --- run_check ---------------------------------------------------------------

RUN_CHECK_OUT_FILE="${TMP_ROOT}/run-check.out"
FAILED=0
run_check 'a passing check' true >"${RUN_CHECK_OUT_FILE}" 2>&1
[ "${FAILED}" -eq 0 ] || fail 'run_check: FAILED was set after a passing check'
grep -Fq 'OK: a passing check' "${RUN_CHECK_OUT_FILE}" || fail "run_check: expected an OK line for a passing check, got: $(cat "${RUN_CHECK_OUT_FILE}")"

FAILED=0
run_check 'a failing check' false >"${RUN_CHECK_OUT_FILE}" 2>&1
[ "${FAILED}" -eq 1 ] || fail 'run_check: FAILED was not set after a failing check'
grep -Fq 'FAILED: a failing check' "${RUN_CHECK_OUT_FILE}" || fail "run_check: expected a FAILED line for a failing check, got: $(cat "${RUN_CHECK_OUT_FILE}")"

# run_check must forward extra arguments to the command it runs, not just invoke
# it bare.
FAILED=0
run_check 'argument forwarding' test -n 'nonempty'
[ "${FAILED}" -eq 0 ] || fail 'run_check: FAILED was set even though the forwarded check should have passed'

# --- run_script_list_check ----------------------------------------------------

SCRIPT_LIST="${TMP_ROOT}/scripts.list"
LIST_ITEM_A="${TMP_ROOT}/item-a"
LIST_ITEM_B="${TMP_ROOT}/item-b"
: >"${LIST_ITEM_A}"
: >"${LIST_ITEM_B}"
printf '%s\n\n%s\n' "${LIST_ITEM_A}" "${LIST_ITEM_B}" >"${SCRIPT_LIST}"

FAILED=0
run_script_list_check 'all items pass' true
RUN_LIST_RC=$?
[ "${RUN_LIST_RC}" -eq 0 ] || fail 'run_script_list_check: expected success when every item passes'
[ "${FAILED}" -eq 0 ] || fail 'run_script_list_check: FAILED was set even though every item passed'

# When a runtime limit is configured, every per-script command must be routed
# through run_test_command so ShellCheck/shfmt cannot bypass the timeout policy.
TIMEOUT_RECORD_FILE="${TMP_ROOT}/timeout-record.log"
MOCK_TIMEOUT="${TMP_ROOT}/timeout"
cat >"${MOCK_TIMEOUT}" <<'EOF_TIMEOUT'
#!/bin/sh
printf '%s\n' "$*" >>"${TIMEOUT_RECORD_FILE}"
[ "$1" = '--kill-after=10' ] || exit 97
shift
[ "$#" -gt 0 ] || exit 97
shift
"$@"
EOF_TIMEOUT
chmod +x "${MOCK_TIMEOUT}" || fail 'run_script_list_check: could not make timeout recorder executable'
export TIMEOUT_RECORD_FILE
TEST_MAX_RUNTIME_SECONDS=37
GNU_TIMEOUT="${MOCK_TIMEOUT}"
: >"${TIMEOUT_RECORD_FILE}"
FAILED=0
run_script_list_check 'bounded items pass' true
RUN_LIST_RC=$?
[ "${RUN_LIST_RC}" -eq 0 ] || fail 'run_script_list_check: bounded per-item command unexpectedly failed'
[ "${FAILED}" -eq 0 ] || fail 'run_script_list_check: bounded per-item command set FAILED'
[ "$(wc -l <"${TIMEOUT_RECORD_FILE}")" -eq 2 ] || fail 'run_script_list_check: timeout wrapper did not run once per non-blank list entry'
grep -Fq -- "--kill-after=10 37 true ${LIST_ITEM_A}" "${TIMEOUT_RECORD_FILE}" ||
	fail 'run_script_list_check: first list item did not use the configured timeout wrapper'
grep -Fq -- "--kill-after=10 37 true ${LIST_ITEM_B}" "${TIMEOUT_RECORD_FILE}" ||
	fail 'run_script_list_check: second list item did not use the configured timeout wrapper'
TEST_MAX_RUNTIME_SECONDS=0
GNU_TIMEOUT=/usr/bin/timeout
unset TIMEOUT_RECORD_FILE

# A per-item command that records how it was invoked, so we can confirm every
# non-blank line in the list was actually visited (blank lines skipped, no
# short-circuiting on the first failure).
RECORD_FILE="${TMP_ROOT}/record.log"
: >"${RECORD_FILE}"
# record_and_fail_on_a records a list item and reports failure when it matches LIST_ITEM_A.
record_and_fail_on_a() {
	printf '%s\n' "$1" >>"${RECORD_FILE}"
	[ "$1" != "${LIST_ITEM_A}" ]
}

FAILED=0
run_script_list_check 'one item fails' record_and_fail_on_a
RUN_LIST_RC=$?
[ "${RUN_LIST_RC}" -eq 1 ] || fail 'run_script_list_check: expected failure return when an item fails'
[ "${FAILED}" -eq 1 ] || fail 'run_script_list_check: FAILED was not set when an item failed'
RECORDED_LINES=$(wc -l <"${RECORD_FILE}")
[ "${RECORDED_LINES}" -eq 2 ] || fail "run_script_list_check: expected both non-blank list entries to be visited, got ${RECORDED_LINES} record(s)"
grep -Fq "${LIST_ITEM_B}" "${RECORD_FILE}" || fail 'run_script_list_check: stopped iterating after the first failure instead of visiting every entry'

# --- cleanup -------------------------------------------------------------------

SCRIPT_LIST="${TMP_ROOT}/to-remove"
: >"${SCRIPT_LIST}"
cleanup
[ ! -e "${SCRIPT_LIST}" ] || fail 'cleanup: did not remove the script list temp file'

# cleanup must be a no-op (not an error) when SCRIPT_LIST is unset/empty or
# already gone.
SCRIPT_LIST=""
cleanup || fail 'cleanup: unexpectedly failed with an empty SCRIPT_LIST'
SCRIPT_LIST="${TMP_ROOT}/already-gone"
cleanup || fail 'cleanup: unexpectedly failed when the script list file did not exist'

# --- CLI argument parsing (--fix / no-arg / invalid) --------------------------

ARG_SNIPPET="${TMP_ROOT}/arg-parse.sh"
sed -n '/^case "\${1:-}" in$/,/^esac$/p' "${SCRIPT_PATH}" >"${ARG_SNIPPET}"
[ -s "${ARG_SNIPPET}" ] || fail 'could not extract the CLI argument-parsing case block from tools/code-quality.sh'

# run_arg_parse executes the extracted argument-parsing block with the specified argument and prints the resulting FIX value.
run_arg_parse() {
	# Runs the extracted case block in a subshell with $1 set as given (or unset
	# entirely when passed the empty string), then prints the resulting FIX value.
	(
		FIX=0
		if [ -n "$1" ]; then
			set -- "$1"
		else
			set --
		fi
		# shellcheck disable=SC1090
		. "${ARG_SNIPPET}"
		printf 'FIX=%s\n' "${FIX}"
	)
}

[ "$(run_arg_parse '')" = 'FIX=0' ] || fail 'argument parsing: expected FIX=0 when no argument is given'
[ "$(run_arg_parse '--fix')" = 'FIX=1' ] || fail 'argument parsing: expected FIX=1 for --fix'

ARG_PARSE_OUT=$(run_arg_parse '--bogus' 2>&1)
ARG_PARSE_RC=$?
[ "${ARG_PARSE_RC}" -eq 2 ] || fail "argument parsing: expected exit code 2 for an unrecognized argument, got ${ARG_PARSE_RC}"
printf '%s\n' "${ARG_PARSE_OUT}" | grep -Fq 'Usage:' || fail "argument parsing: expected a usage message for an unrecognized argument, got: ${ARG_PARSE_OUT}"

# --- Orphaned test coverage --------------------------------------------------
# Every tests/*.sh regression script must be wired into a run_check call in
# tools/code-quality.sh. A new test file that isn't referenced here would
# silently receive zero CI coverage.
for t in tests/*.sh; do
	# This matrix is run with BusyBox ash by shell-validation.yml and composes
	# component regressions already registered individually below.
	[ "${t}" = 'tests/service-lifecycle-integration.sh' ] && continue
	grep -Fq "${t}" "${SCRIPT_PATH}" ||
		fail "${t} is not referenced by any run_check in ${SCRIPT_PATH}; new test files must be wired in or they get zero CI coverage"
done

grep -Fq "run_check 'tzdata package conversion regression' sh tests/update-tzdata-package-info.sh" "${SCRIPT_PATH}" ||
	fail 'tzdata package conversion regression is not registered in tools/code-quality.sh'

grep -Fq "run_long_check 'AdGuardHome service lifecycle integration regression' \"\${SERVICE_LIFECYCLE_MAX_RUNTIME_SECONDS}\" run_privileged_regression_check tests/service-lifecycle-integration.sh 'service lifecycle integration regression'" "${SCRIPT_PATH}" ||
	fail 'service lifecycle integration regression does not use its dedicated timeout and privileged test helper'

printf '%s\n' 'PASS: tools/code-quality.sh helper functions and argument parsing behave as documented'
