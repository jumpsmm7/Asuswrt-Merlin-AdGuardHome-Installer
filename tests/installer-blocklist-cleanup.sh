#!/bin/sh
# Verify blocklist cleanup helpers parse only analyzer unused IDs and YAML filters entries.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-blocklist-cleanup.$$"
export TMP_ROOT
FUNCTIONS_FILE="${TMP_ROOT}/functions"

cleanup() {
	rm -rf "${TMP_ROOT}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"
grep -q 'Do you want Entware to install python3 now?' "${SCRIPT_PATH}" ||
	fail 'installer does not offer to install Entware python3 when missing'
grep -q 'Do you want to remove all matching unused blocklists?' "${SCRIPT_PATH}" ||
	fail 'installer does not offer all-at-once blocklist cleanup'
grep -q 'Remove blocklist ${list_label} from AdGuardHome.yaml?' "${SCRIPT_PATH}" ||
	fail 'installer does not offer one-by-one blocklist cleanup'
mkdir -p "${TMP_ROOT}" || fail 'could not create test directory'

sed -n \
	-e '/^PTXT() {$/,/^}/p' \
	-e '/^ptxt_phase() {$/,/^}/p' \
	-e '/^ptxt_step() {$/,/^}/p' \
	-e '/^ptxt_ok() {$/,/^}/p' \
	-e '/^ptxt_warn() {$/,/^}/p' \
	-e '/^ptxt_fail() {$/,/^}/p' \
	-e '/^rollback_result_write() {$/,/^}/p' \
	-e '/^rollback_result_summary() {$/,/^}/p' \
	-e '/^rollback_result_notice() {$/,/^}/p' \
	-e '/^adguardhome_owner_account() {$/,/^}/p' \
	-e '/^adguardhome_yaml_secure_file() {$/,/^}/p' \
	-e '/^blocklist_analyzer_pause() {$/,/^}/p' \
	-e '/^blocklist_analyzer_ids() {$/,/^}/p' \
	-e '/^run_blocklist_analyzer() {$/,/^}/p' \
	-e '/^blocklist_yaml_candidates() {$/,/^}/p' \
	"${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" ||
	fail 'could not extract blocklist helper functions'
sed -n '/^select_unused_blocklists_for_removal() {$/,/^remove_unused_blocklists_from_yaml() {$/p' "${SCRIPT_PATH}" | sed '$d' >>"${FUNCTIONS_FILE}" ||
	fail 'could not extract blocklist selection function'
sed -n '/^remove_unused_blocklists_from_yaml() {$/,/^cleanup_unused_blocklists() {$/p' "${SCRIPT_PATH}" | sed '$d' >>"${FUNCTIONS_FILE}" ||
	fail 'could not extract blocklist removal function'
sed -n '/^cleanup_unused_blocklists() {$/,/^########################Modified Version/p' "${SCRIPT_PATH}" | sed '$d' >>"${FUNCTIONS_FILE}" ||
	fail 'could not extract blocklist cleanup function'
sed -n '/^menu() {$/,/^read_input_dns() {$/p' "${SCRIPT_PATH}" | sed '$d' >>"${FUNCTIONS_FILE}" ||
	fail 'could not extract menu dispatch function'
sed -n '/^menu_action_allowed() {$/,/^cli_action_requires_install_mode() {$/p' "${SCRIPT_PATH}" | sed '$d' >>"${FUNCTIONS_FILE}" ||
	fail 'could not extract CLI menu routing functions'
[ -s "${FUNCTIONS_FILE}" ] || fail 'blocklist helper extraction was empty'
sed 's#/opt/bin/python3#${PYTHON3_BIN:-/opt/bin/python3}#g' "${FUNCTIONS_FILE}" >"${FUNCTIONS_FILE}.tmp" ||
	fail 'could not make Entware python3 path mockable'
mv "${FUNCTIONS_FILE}.tmp" "${FUNCTIONS_FILE}" || fail 'could not update extracted blocklist helpers'
for helper in adguardhome_owner_account adguardhome_yaml_secure_file; do
	grep -Fq "${helper}() {" "${FUNCTIONS_FILE}" || fail "blocklist helper extraction is missing ${helper}"
done

grep -Fq '"9" | "blocklists" | "unusedblocklists")' "${SCRIPT_PATH}" ||
	fail 'menu dispatch no longer routes all blocklist cleanup aliases'
grep -Fq 'if [ -z "${2:-}" ] && single_arg_menu_action "${1:-}"; then' "${SCRIPT_PATH}" ||
	fail 'redirected single-argument CLI actions no longer enter menu dispatch'
grep -Fq 'menu "$2"' "${SCRIPT_PATH}" ||
	fail 'branch-qualified CLI actions no longer enter menu dispatch'

# run_cleanup_pause_case runs cleanup with mocked dependencies and checks its status.
# Arguments: case name, interactive flag (yes/no), analyzer status, expected status,
# and optional dispatch kind (direct/menu/cli).
# Captures output and end-operation calls in per-case files under TMP_ROOT.
run_cleanup_pause_case() {
	case_name="$1"
	interactive="$2"
	analyzer_status="$3"
	expected_status="$4"
	dispatch_kind="${5:-direct}"
	output_file="${TMP_ROOT}/pause-${case_name}.out"
	call_file="${TMP_ROOT}/pause-${case_name}.calls"
	(
		# shellcheck disable=SC1090
		. "${FUNCTIONS_FILE}"
		INPUT='Input:'
		INFO='Info:'
		WARNING='Warning:'
		ERROR='Error:'
		TARG_DIR="${TMP_ROOT}/${case_name}"
		mkdir -p "${TARG_DIR}" || exit 1
		AGH_FILE="${TARG_DIR}/AdGuardHome"
		: >"${AGH_FILE}" || exit 1
		BLOCKLIST_ANALYZER_SHA256='test-checksum'
		# PTXT prints plain text, honoring -n so pause prompt ordering is observable.
		PTXT() {
			if [ "${1:-}" = "-n" ]; then
				shift
				printf '%s' "$*"
			else
				printf '%s\n' "$*"
			fi
		}
		# ptxt_warn forwards warning text to the captured output without formatting.
		ptxt_warn() { PTXT "$*"; }
		# stty simulates terminal detection using the case's interactive flag.
		stty() { [ "${interactive}" = "yes" ]; }
		# read simulates BusyBox ash timed-read support while leaving the test
		# runner's POSIX shell free to consume the supplied Enter key normally.
		read() {
			read_timeout=''
			read_name=''
			while [ "$#" -gt 0 ]; do
				case "$1" in
					-t)
						shift
						read_timeout="${1:-}"
						;;
					*) read_name="$1" ;;
				esac
				shift
			done
			[ "${TIMED_READ_SUPPORTED:-yes}" = "yes" ] || return 2
			printf 'read-timeout:%s\n' "${read_timeout}" >>"${call_file}"
			command read -r "${read_name}"
		}
		# install_blocklist_analyzer simulates successful installation without downloads.
		install_blocklist_analyzer() {
			printf '%s\n' 'cleanup-entered' >>"${call_file}"
			return 0
		}
		# run_blocklist_analyzer emits a diagnostic and returns the configured status,
		# creating the expected temporary files on success.
		run_blocklist_analyzer() {
			PTXT 'analyzer result or diagnostic'
			if [ "${analyzer_status}" -eq 0 ]; then
				BLOCKLIST_ANALYZER_IDS_FILE="${TARG_DIR}/ids"
				BLOCKLIST_ANALYZER_OUTPUT_FILE="${TARG_DIR}/output"
				: >"${BLOCKLIST_ANALYZER_IDS_FILE}"
				: >"${BLOCKLIST_ANALYZER_OUTPUT_FILE}"
			fi
			return "${analyzer_status}"
		}
		# select_unused_blocklists_for_removal creates a selection file and succeeds.
		select_unused_blocklists_for_removal() {
			BLOCKLIST_ANALYZER_SELECTED_IDS_FILE="${TARG_DIR}/selected"
			: >"${BLOCKLIST_ANALYZER_SELECTED_IDS_FILE}"
			return 0
		}
		# remove_unused_blocklists_from_yaml reports success without editing YAML.
		remove_unused_blocklists_from_yaml() {
			PTXT 'cleanup succeeded'
			return 0
		}
		# end_op_message records its status argument and emits an ordering marker.
		end_op_message() {
			printf 'end:%s\n' "$1" >>"${call_file}"
			PTXT "end:$1"
		}
		case "${dispatch_kind}" in
			direct) cleanup_unused_blocklists ;;
			menu) menu unusedblocklists ;;
			cli)
				single_arg_menu_action unusedblocklists || exit 1
				menu unusedblocklists
				;;
			*) exit 1 ;;
		esac
		status="$?"
		[ "${status}" -eq "${expected_status}" ] || exit 1
	) >"${output_file}" 2>&1
}

for dispatch_kind in menu cli; do
	printf '\n' | run_cleanup_pause_case "${dispatch_kind}-success" yes 0 0 "${dispatch_kind}" ||
		fail "${dispatch_kind} successful cleanup pause regression failed"
	printf '\n' | run_cleanup_pause_case "${dispatch_kind}-no-unused" yes 2 0 "${dispatch_kind}" ||
		fail "${dispatch_kind} no-unused cleanup pause regression failed"
	printf '\n' | run_cleanup_pause_case "${dispatch_kind}-failure" yes 1 1 "${dispatch_kind}" ||
		fail "${dispatch_kind} analyzer failure pause regression failed"
	for result_kind in success no-unused failure; do
		output_file="${TMP_ROOT}/pause-${dispatch_kind}-${result_kind}.out"
		call_file="${TMP_ROOT}/pause-${dispatch_kind}-${result_kind}.calls"
		grep -q '^cleanup-entered$' "${call_file}" ||
			fail "${dispatch_kind} ${result_kind} dispatch did not enter blocklist cleanup"
		grep -q 'Press Enter to continue' "${output_file}" ||
			fail "${dispatch_kind} ${result_kind} result did not pause interactively"
		awk 'index($0, "Press Enter to continue") && index($0, "end:") && index($0, "Press Enter to continue") < index($0, "end:") { found = 1 } END { exit(found ? 0 : 1) }' "${output_file}" ||
			fail "${dispatch_kind} ${result_kind} pause did not precede end_op_message"
	done
done

run_cleanup_pause_case 'cli-redirected-success' no 0 0 </dev/null ||
	fail 'redirected CLI cleanup waited for input or failed'
if grep -q 'Press Enter to continue' "${TMP_ROOT}/pause-cli-redirected-success.out"; then
	fail 'redirected CLI cleanup displayed an interactive pause prompt'
fi

TIMED_READ_SUPPORTED=no run_cleanup_pause_case 'timed-read-unavailable' yes 0 0 </dev/null ||
	fail 'cleanup failed when timed read was unavailable'
grep -q 'Press Enter to continue' "${TMP_ROOT}/pause-timed-read-unavailable.out" ||
	fail 'cleanup did not display the pause prompt before an unsupported timed read returned'

if grep -q 'read-timeout:0' "${TMP_ROOT}"/pause-*.calls; then
	fail 'cleanup used a potentially blocking zero-timeout read probe'
fi

AI_ASSUME_YES=1 run_cleanup_pause_case 'assume-yes' yes 0 0 </dev/null ||
	fail 'assume-yes cleanup failed'
if grep -q 'Press Enter to continue' "${TMP_ROOT}/pause-assume-yes.out" ||
	grep -q 'read-timeout:' "${TMP_ROOT}/pause-assume-yes.calls"; then
	fail 'assume-yes cleanup prompted for or read interactive input'
fi

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	INFO='Info:'
	ERROR='Error:'
	TARG_DIR="${TMP_ROOT}/missing-inputs"
	BLOCKLIST_ANALYZER_FILE="${TARG_DIR}/blocklist_analyzer.py"
	mkdir -p "${TARG_DIR}/data" || exit 1
	PYTHON3_BIN="${TMP_ROOT}/python-missing-filters"
	cat >"${PYTHON3_BIN}" <<'EOF_PY' || exit 1
#!/bin/sh
printf '%s\n' 'python should not run without filters' >"${TMP_ROOT}/python-called"
exit 0
EOF_PY
	chmod 755 "${PYTHON3_BIN}" || exit 1
	if run_blocklist_analyzer >"${TMP_ROOT}/missing-filters.out" 2>&1; then
		exit 1
	fi
	[ ! -e "${TMP_ROOT}/python-called" ] || exit 1
) || fail 'blocklist analyzer accepted missing filter directory'
grep -q 'filter files are missing' "${TMP_ROOT}/missing-filters.out" ||
	fail 'missing filter directory did not produce a clear failure'

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	INFO='Info:'
	ERROR='Error:'
	TARG_DIR="${TMP_ROOT}/non-txt-filters"
	BLOCKLIST_ANALYZER_FILE="${TARG_DIR}/blocklist_analyzer.py"
	mkdir -p "${TARG_DIR}/data/filters" || exit 1
	printf '%s\n' 'not a filter' >"${TARG_DIR}/data/filters/README" || exit 1
	printf '%s\n' '{"version":1}' >"${TARG_DIR}/data/querylog.json" || exit 1
	PYTHON3_BIN="${TMP_ROOT}/python-non-txt"
	cat >"${PYTHON3_BIN}" <<'EOF_PY' || exit 1
#!/bin/sh
printf '%s\n' 'python should not run without txt filters' >"${TMP_ROOT}/python-called-non-txt"
exit 0
EOF_PY
	chmod 755 "${PYTHON3_BIN}" || exit 1
	if run_blocklist_analyzer >"${TMP_ROOT}/non-txt-filters.out" 2>&1; then
		exit 1
	fi
	[ ! -e "${TMP_ROOT}/python-called-non-txt" ] || exit 1
) || fail 'blocklist analyzer accepted non-txt filter files'
grep -q 'contains no filter files' "${TMP_ROOT}/non-txt-filters.out" ||
	fail 'non-txt filter directory did not produce a clear failure'

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	INFO='Info:'
	ERROR='Error:'
	TARG_DIR="${TMP_ROOT}/missing-querylog"
	BLOCKLIST_ANALYZER_FILE="${TARG_DIR}/blocklist_analyzer.py"
	mkdir -p "${TARG_DIR}/data/filters" || exit 1
	printf '%s\n' 'filter data' >"${TARG_DIR}/data/filters/1.txt" || exit 1
	PYTHON3_BIN="${TMP_ROOT}/python-querylog"
	cat >"${PYTHON3_BIN}" <<'EOF_PY' || exit 1
#!/bin/sh
printf '%s\n' 'python should not run without querylog' >"${TMP_ROOT}/python-called-querylog"
exit 0
EOF_PY
	chmod 755 "${PYTHON3_BIN}" || exit 1
	if run_blocklist_analyzer >"${TMP_ROOT}/missing-querylog.out" 2>&1; then
		exit 1
	fi
	[ ! -e "${TMP_ROOT}/python-called-querylog" ] || exit 1
) || fail 'blocklist analyzer accepted missing query log'
grep -q 'query log is missing or empty' "${TMP_ROOT}/missing-querylog.out" ||
	fail 'missing query log did not produce a clear failure'

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	INFO='Info:'
	ERROR='Error:'
	TARG_DIR="${TMP_ROOT}/ready-inputs"
	BLOCKLIST_ANALYZER_FILE="${TARG_DIR}/blocklist_analyzer.py"
	mkdir -p "${TARG_DIR}/data/filters" || exit 1
	printf '%s\n' 'filter data' >"${TARG_DIR}/data/filters/1.txt" || exit 1
	printf '%s\n' '{"version":1}' >"${TARG_DIR}/data/querylog.json" || exit 1
	PYTHON3_BIN="${TMP_ROOT}/python-ready"
	cat >"${PYTHON3_BIN}" <<'EOF_PY' || exit 1
#!/bin/sh
printf '%s\n' 'python ran with required inputs' >"${TMP_ROOT}/python-called-ready"
printf '%s\n' 'UNUSED BLOCKLISTS (0)'
exit 0
EOF_PY
	chmod 755 "${PYTHON3_BIN}" || exit 1
	run_blocklist_analyzer >"${TMP_ROOT}/ready-inputs.out" 2>&1
	status="$?"
	[ "${status}" -eq 2 ] || exit 1
	[ -e "${TMP_ROOT}/python-called-ready" ] || exit 1
) || fail 'blocklist analyzer did not run with required inputs present'

cat >"${TMP_ROOT}/analyzer.out" <<'EOF_ANALYZER'
USED BLOCKLISTS (1)
-------------------
123.txt  some used list

 UNUSED BLOCKLISTS (3)
---------------------
1769441874.txt  https://example.invalid/a.txt
200.txt         https://example.invalid/b.txt
999.txt         stale cache entry

OTHER SECTION
-------------
999.txt should not be parsed
EOF_ANALYZER

cat >"${TMP_ROOT}/ids.expected" <<'EOF_IDS'
1769441874
200
999
EOF_IDS

cat >"${TMP_ROOT}/AdGuardHome.yaml" <<'EOF_YAML'
users:
  - name: admin
    id: 1769441874
filters:
  - enabled: true
    url: https://example.invalid/a.txt
    name: List A
    id: 1769441874
  - enabled: true
    url: https://example.invalid/keep.txt
    name: Keep List
    id: 300
  - enabled: false
    url: https://example.invalid/b.txt
    name: List B
    id: 200
querylog:
  ignored:
    - id: 200
EOF_YAML

cat >"${TMP_ROOT}/candidates.expected" <<'EOF_CANDIDATES'
1769441874|List A|https://example.invalid/a.txt
200|List B|https://example.invalid/b.txt
EOF_CANDIDATES

mkdir -p "${TMP_ROOT}/data/filters" || fail 'could not create filter cache fixture'
printf '%s\n' 'configured filter cache' >"${TMP_ROOT}/data/filters/1769441874.txt" || fail 'could not create configured cache fixture'
printf '%s\n' 'stale filter cache' >"${TMP_ROOT}/data/filters/999.txt" || fail 'could not create stale cache fixture'

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	INFO='Info:'
	WARNING='Warning:'
	YAML_FILE="${TMP_ROOT}/AdGuardHome.yaml"
	TARG_DIR="${TMP_ROOT}"
	# read_yesno records each mixed-result prompt and returns 1 to decline removal.
	read_yesno() {
		printf '%s\n' "$1" >>"${TMP_ROOT}/prompts.actual"
		return 1
	}
	blocklist_analyzer_ids "${TMP_ROOT}/analyzer.out" >"${TMP_ROOT}/ids.actual"
	blocklist_yaml_candidates "${TMP_ROOT}/ids.actual" "${TMP_ROOT}/AdGuardHome.yaml" >"${TMP_ROOT}/candidates.actual"
	select_unused_blocklists_for_removal "${TMP_ROOT}/ids.actual" >"${TMP_ROOT}/selection.actual" 2>&1 || true
) || fail 'blocklist helper subprocess failed'

cmp -s "${TMP_ROOT}/ids.expected" "${TMP_ROOT}/ids.actual" ||
	fail "unused ID parsing changed: $(cat "${TMP_ROOT}/ids.actual")"
cmp -s "${TMP_ROOT}/candidates.expected" "${TMP_ROOT}/candidates.actual" ||
	fail "YAML filter candidate parsing changed: $(cat "${TMP_ROOT}/candidates.actual")"
grep -q 'Remove blocklist List A from AdGuardHome.yaml?' "${TMP_ROOT}/prompts.actual" ||
	fail 'one-by-one prompt does not include the first blocklist name'
grep -q 'Remove blocklist List B from AdGuardHome.yaml?' "${TMP_ROOT}/prompts.actual" ||
	fail 'one-by-one prompt does not include the second blocklist name'
if grep -q '999' "${TMP_ROOT}/prompts.actual"; then
	fail 'mixed configured/ghost result prompted for the stale cache ID'
fi
grep -q 'Stale or historical filter-cache IDs' "${TMP_ROOT}/selection.actual" ||
	fail 'mixed configured/ghost result did not report stale cache IDs separately'
grep -q 'no current YAML blocklist to remove' "${TMP_ROOT}/selection.actual" ||
	fail 'stale cache notice did not explain that no YAML blocklist can be removed'
[ -f "${TMP_ROOT}/data/filters/999.txt" ] || fail 'mixed result automatically deleted the stale cache file'

cat >"${TMP_ROOT}/ghost.ids" <<'EOF_GHOST_IDS'
999
EOF_GHOST_IDS
: >"${TMP_ROOT}/ghost.prompts"
(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	INPUT='Input:'
	INFO='Info:'
	WARNING='Warning:'
	YAML_FILE="${TMP_ROOT}/AdGuardHome.yaml"
	TARG_DIR="${TMP_ROOT}"
	# read_yesno records unexpected orphan-only prompts and returns 1 to decline.
	read_yesno() {
		printf '%s\n' "$1" >>"${TMP_ROOT}/ghost.prompts"
		return 1
	}
	select_unused_blocklists_for_removal "${TMP_ROOT}/ghost.ids" >"${TMP_ROOT}/ghost.out" 2>&1
	[ "$?" -eq 3 ] || exit 1
) || fail 'all-ghost selection did not return the successful no-configured result'
grep -q 'No configured unused blocklists were found' "${TMP_ROOT}/ghost.out" ||
	fail 'all-ghost result did not report that no configured unused blocklists were found'
[ ! -s "${TMP_ROOT}/ghost.prompts" ] || fail 'all-ghost result displayed a removal prompt'
[ -f "${TMP_ROOT}/data/filters/999.txt" ] || fail 'all-ghost result automatically deleted the stale cache file'

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	INPUT='Input:'
	INFO='Info:'
	WARNING='Warning:'
	YAML_FILE="${TMP_ROOT}/AdGuardHome.yaml"
	TARG_DIR="${TMP_ROOT}"
	# read_yesno returns input-failure status 2 to test selection error propagation.
	read_yesno() { return 2; }
	if select_unused_blocklists_for_removal "${TMP_ROOT}/ids.actual" >/dev/null 2>&1; then
		exit 1
	else
		[ "$?" -eq 2 ] || exit 1
	fi
) || fail 'confirmation input failure did not retain its failure status'

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	INPUT='Input:'
	INFO='Info:'
	WARNING='Warning:'
	YAML_FILE="${TMP_ROOT}/AdGuardHome.yaml"
	TARG_DIR="${TMP_ROOT}"
	cp "${TMP_ROOT}/ids.actual" "${TMP_ROOT}/confirmation.ids" || exit 1
	BLOCKLIST_ANALYZER_IDS_FILE="${TMP_ROOT}/confirmation.ids"
	BLOCKLIST_ANALYZER_OUTPUT_FILE="${TMP_ROOT}/confirmation-analyzer.out"
	: >"${BLOCKLIST_ANALYZER_OUTPUT_FILE}"
	# install_blocklist_analyzer simulates successful installation without downloads.
	install_blocklist_analyzer() { return 0; }
	# run_blocklist_analyzer succeeds using the prepared confirmation ID fixture.
	run_blocklist_analyzer() { return 0; }
	# read_yesno returns input-failure status 2 to test cleanup error handling.
	read_yesno() { return 2; }
	# blocklist_analyzer_pause suppresses interactive waiting in this test.
	blocklist_analyzer_pause() { :; }
	# end_op_message prints its status argument for the failure assertion.
	end_op_message() { printf '%s\n' "end:$1"; }
	if cleanup_unused_blocklists >"${TMP_ROOT}/confirmation-cleanup.out" 2>&1; then
		exit 1
	else
		[ "$?" -eq 1 ] || exit 1
	fi
) || fail 'confirmation input failure did not fail cleanup'
grep -q '^end:1$' "${TMP_ROOT}/confirmation-cleanup.out" ||
	fail 'confirmation input failure did not report cleanup failure'

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	INPUT='Input:'
	INFO='Info:'
	WARNING='Warning:'
	YAML_FILE="${TMP_ROOT}/AdGuardHome.yaml"
	TARG_DIR="${TMP_ROOT}"
	BLOCKLIST_ANALYZER_IDS_FILE="${TMP_ROOT}/ghost.ids"
	BLOCKLIST_ANALYZER_OUTPUT_FILE="${TMP_ROOT}/ghost-analyzer.out"
	: >"${BLOCKLIST_ANALYZER_OUTPUT_FILE}"
	# install_blocklist_analyzer simulates successful installation for this fixture.
	install_blocklist_analyzer() { return 0; }
	# run_blocklist_analyzer succeeds using the pre-created orphan-only ID file.
	run_blocklist_analyzer() { return 0; }
	# read_yesno fails the subprocess if orphan-only cleanup requests confirmation.
	read_yesno() { exit 1; }
	# blocklist_analyzer_pause skips interactive waiting in this cleanup status test.
	blocklist_analyzer_pause() { :; }
	# end_op_message prints its status argument for the successful-completion assertion.
	end_op_message() { printf '%s\n' "end:$1"; }
	cleanup_unused_blocklists >"${TMP_ROOT}/ghost-cleanup.out" 2>&1
) || fail 'all-ghost cleanup did not exit successfully'
grep -q '^end:0$' "${TMP_ROOT}/ghost-cleanup.out" || fail 'all-ghost cleanup did not report successful completion'
[ -f "${TMP_ROOT}/data/filters/999.txt" ] || fail 'all-ghost cleanup automatically deleted the stale cache file'

cat >"${TMP_ROOT}/ids.selected" <<'EOF_SELECTED'
1769441874
EOF_SELECTED

cat >"${TMP_ROOT}/AdGuardHome.yaml.restore" <<'EOF_RESTORE'
filters:
  - enabled: true
    url: https://example.invalid/a.txt
    name: List A
    id: 1769441874
  - enabled: true
    url: https://example.invalid/keep.txt
    name: Keep List
    id: 300
EOF_RESTORE

cp "${TMP_ROOT}/AdGuardHome.yaml.restore" "${TMP_ROOT}/AdGuardHome.yaml" ||
	fail 'could not reset YAML for restore regression'

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	INFO='Info:'
	WARNING='Warning:'
	ERROR='Error:'
	YAML_FILE="${TMP_ROOT}/AdGuardHome.yaml"
	TARG_DIR="${TMP_ROOT}"
	ROLLBACK_RESULT_FILE="${TMP_ROOT}/blocklist-rollback-result"
	REAL_MV="$(which mv)" || exit 1
	rm -f "${ROLLBACK_RESULT_FILE}" || exit 1
	mv() {
		case "$*" in
			*"${YAML_FILE}.blocklists."*".tmp ${YAML_FILE}") return 1 ;;
		esac
		"${REAL_MV}" "$@"
	}
	check_AdGuardHome_yaml() {
		return 0
	}
	agh_restart() {
		return 0
	}
	adguard_service_status_after_action() {
		return 0
	}
	if remove_unused_blocklists_from_yaml "${TMP_ROOT}/ids.selected" >/dev/null 2>&1; then
		exit 1
	fi
	grep -q '^context=blocklist yaml replacement$' "${ROLLBACK_RESULT_FILE}" || exit 1
	grep -q '^result=replace-failed$' "${ROLLBACK_RESULT_FILE}" || exit 1
	grep -q "^detail=${YAML_FILE}\$" "${ROLLBACK_RESULT_FILE}" || exit 1
) || fail 'blocklist YAML replacement failure did not preserve the specific rollback marker'

cp "${TMP_ROOT}/AdGuardHome.yaml.restore" "${TMP_ROOT}/AdGuardHome.yaml" ||
	fail 'could not reset YAML after replacement marker regression'

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	INFO='Info:'
	WARNING='Warning:'
	ERROR='Error:'
	YAML_FILE="${TMP_ROOT}/AdGuardHome.yaml"
	YAML_ERR="${YAML_FILE}.err"
	ROLLBACK_RESULT_FILE="${TMP_ROOT}/blocklist-restore-rollback-result"
	ptxt_phase() { PTXT "$@"; }
	ptxt_step() { PTXT "$@"; }
	ptxt_fail() { PTXT "$@"; }
	check_AdGuardHome_yaml() {
		mv "${YAML_FILE}" "${YAML_ERR}"
		return 1
	}
	cp() {
		case "$2" in
			"${YAML_FILE}") return 1 ;;
			*) command cp "$@" ;;
		esac
	}
	if remove_unused_blocklists_from_yaml "${TMP_ROOT}/ids.selected" >"${TMP_ROOT}/restore-fallback.out" 2>&1; then
		exit 1
	fi
	exit 0
) || fail 'blocklist restore fallback subprocess failed'

cmp -s "${TMP_ROOT}/AdGuardHome.yaml.restore" "${TMP_ROOT}/AdGuardHome.yaml" ||
	fail 'backup was not moved back when restore copy failed'
grep -q 'Validation failed; restored' "${TMP_ROOT}/restore-fallback.out" ||
	fail 'restore fallback success was not reported'

printf '%s\n' 'PASS: blocklist cleanup helpers parse unused IDs and filter candidates safely'
