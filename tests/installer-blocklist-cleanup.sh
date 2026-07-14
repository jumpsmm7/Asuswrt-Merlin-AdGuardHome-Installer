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
	-e '/^blocklist_analyzer_ids() {$/,/^}/p' \
	-e '/^run_blocklist_analyzer() {$/,/^}/p' \
	-e '/^blocklist_yaml_candidates() {$/,/^}/p' \
	"${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" ||
	fail 'could not extract blocklist helper functions'
sed -n '/^select_unused_blocklists_for_removal() {$/,/^remove_unused_blocklists_from_yaml() {$/p' "${SCRIPT_PATH}" | sed '$d' >>"${FUNCTIONS_FILE}" ||
	fail 'could not extract blocklist selection function'
sed -n '/^remove_unused_blocklists_from_yaml() {$/,/^cleanup_unused_blocklists() {$/p' "${SCRIPT_PATH}" | sed '$d' >>"${FUNCTIONS_FILE}" ||
	fail 'could not extract blocklist removal function'
[ -s "${FUNCTIONS_FILE}" ] || fail 'blocklist helper extraction was empty'
sed 's#/opt/bin/python3#${PYTHON3_BIN:-/opt/bin/python3}#g' "${FUNCTIONS_FILE}" >"${FUNCTIONS_FILE}.tmp" ||
	fail 'could not make Entware python3 path mockable'
mv "${FUNCTIONS_FILE}.tmp" "${FUNCTIONS_FILE}" || fail 'could not update extracted blocklist helpers'

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

 UNUSED BLOCKLISTS (2)
---------------------
1769441874.txt  https://example.invalid/a.txt
200.txt         https://example.invalid/b.txt

OTHER SECTION
-------------
999.txt should not be parsed
EOF_ANALYZER

cat >"${TMP_ROOT}/ids.expected" <<'EOF_IDS'
1769441874
200
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

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	INFO='Info:'
	WARNING='Warning:'
	YAML_FILE="${TMP_ROOT}/AdGuardHome.yaml"
	TARG_DIR="${TMP_ROOT}"
	read_yesno() {
		printf '%s\n' "$1" >>"${TMP_ROOT}/prompts.actual"
		return 1
	}
	blocklist_analyzer_ids "${TMP_ROOT}/analyzer.out" >"${TMP_ROOT}/ids.actual"
	blocklist_yaml_candidates "${TMP_ROOT}/ids.actual" "${TMP_ROOT}/AdGuardHome.yaml" >"${TMP_ROOT}/candidates.actual"
	select_unused_blocklists_for_removal "${TMP_ROOT}/ids.actual" >/dev/null 2>&1 || true
) || fail 'blocklist helper subprocess failed'

cmp -s "${TMP_ROOT}/ids.expected" "${TMP_ROOT}/ids.actual" ||
	fail "unused ID parsing changed: $(cat "${TMP_ROOT}/ids.actual")"
cmp -s "${TMP_ROOT}/candidates.expected" "${TMP_ROOT}/candidates.actual" ||
	fail "YAML filter candidate parsing changed: $(cat "${TMP_ROOT}/candidates.actual")"
grep -q 'Remove blocklist List A from AdGuardHome.yaml?' "${TMP_ROOT}/prompts.actual" ||
	fail 'one-by-one prompt does not include the first blocklist name'
grep -q 'Remove blocklist List B from AdGuardHome.yaml?' "${TMP_ROOT}/prompts.actual" ||
	fail 'one-by-one prompt does not include the second blocklist name'

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
