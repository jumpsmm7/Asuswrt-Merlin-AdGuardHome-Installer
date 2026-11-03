#!/bin/sh
# Run the pinned validation-host scanner without masking incomplete scans as clean results.

set -u
export LC_ALL=C
OSV_IMAGE='ghcr.io/google/osv-scanner-action@sha256:48406c58197201fe55e56615ad9d414f85063da320e204d0b0ed460fb3908dba'

# fail stops before publishing readiness for an incomplete or failed scan.
fail() {
	printf '%s\n' "Error: $*" >&2
	exit 1
}

[ "$#" -eq 1 ] || fail 'expected prepare or one fixed result filename'
[ -n "${GITHUB_OUTPUT:-}" ] || fail 'GitHub output path is unavailable'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)" || fail 'could not locate scan tools'

if [ "$1" = prepare ]; then
	TOOLS_DIR="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/osv-tools.XXXXXX")" || fail 'could not reserve private tool directory'
	trap 'rm -rf "${TOOLS_DIR}"' 0
	trap 'exit 1' HUP INT TERM
	cp "${SCRIPT_DIR}/run-osv-scan.sh" "${SCRIPT_DIR}/check-osv-results.py" "${TOOLS_DIR}/" || fail 'could not preserve current scan tools'
	# Pull separately: Docker progress must never be confused with scanner error diagnostics.
	docker pull "${OSV_IMAGE}" || fail 'could not pull the pinned scanner image'
	printf 'tool_directory=%s\n' "${TOOLS_DIR}" >>"${GITHUB_OUTPUT}" || fail 'could not publish tool directory'
	trap - 0 HUP INT TERM
	exit 0
fi

RESULT_FILE="$1"
case "${RESULT_FILE}" in
	old-results.json | new-results.json | results.json) ;;
	*) fail 'unexpected result filename' ;;
esac
[ -f "${SCRIPT_DIR}/check-osv-results.py" ] || fail 'result validator is unavailable'
if [ -e "${RESULT_FILE}" ] || [ -L "${RESULT_FILE}" ]; then
	[ -f "${RESULT_FILE}" ] && [ ! -L "${RESULT_FILE}" ] || fail 'unsafe previous result path'
	rm -f "${RESULT_FILE}" || fail 'could not remove stale scan result'
fi
SCAN_DIR="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/osv-scan.XXXXXX")" || fail 'could not reserve private scan directory'
SCAN_COMPLETE=0
RESULT_STAGE=''

# cleanup removes partial output while retaining the private diagnostic logs for inspection.
cleanup() {
	rm -f "${SCAN_DIR}/results.json"
	[ -z "${RESULT_STAGE}" ] || rm -f "${RESULT_STAGE}"
	[ "${SCAN_COMPLETE}" = 1 ] || rm -f "${RESULT_FILE}"
}

trap cleanup 0
trap 'exit 1' HUP INT TERM
REPOSITORY_DIR="$(pwd -P)" || fail 'could not locate source checkout'
printf '%s\n' "OSV scanner logs: ${SCAN_DIR}"
SCAN_STATUS=0
docker run --rm --pull=never \
	--volume "${REPOSITORY_DIR}:/source:ro" --volume "${SCAN_DIR}:/osv-output" \
	--workdir /source --entrypoint /root/osv-scanner "${OSV_IMAGE}" \
	scan source --allow-no-lockfiles --verbosity=error --format=json \
	--output-file=/osv-output/results.json -r /source \
	>"${SCAN_DIR}/stdout.log" 2>"${SCAN_DIR}/stderr.log" || SCAN_STATUS="$?"
cat "${SCAN_DIR}/stdout.log" || fail 'could not read scanner output'
cat "${SCAN_DIR}/stderr.log" >&2 || fail 'could not read scanner diagnostics'
case "${SCAN_STATUS}" in
	0 | 1) ;;
	*) fail "scanner did not complete: exit ${SCAN_STATUS}" ;;
esac
# At the pinned version, --verbosity=error sends only error-level diagnostics to stderr.
# Exit 1 can represent vulnerabilities plus an extraction error, so status alone is insufficient.
[ ! -s "${SCAN_DIR}/stderr.log" ] || fail 'scanner reported an error or incomplete extraction'
(cd "${SCAN_DIR}" && python3 "${SCRIPT_DIR}/check-osv-results.py" results.json) || fail 'scanner did not produce valid results'
RESULT_STAGE="$(mktemp "./.${RESULT_FILE}.XXXXXX")" || fail 'could not reserve result publication stage'
cp "${SCAN_DIR}/results.json" "${RESULT_STAGE}" || fail 'could not stage validated scan result'
mv -f "${RESULT_STAGE}" "${RESULT_FILE}" || fail 'could not publish validated scan result'
RESULT_STAGE=''
printf 'scanner_exit_code=%s\nready=true\n' "${SCAN_STATUS}" >>"${GITHUB_OUTPUT}" || fail 'could not publish scan readiness'
SCAN_COMPLETE=1
