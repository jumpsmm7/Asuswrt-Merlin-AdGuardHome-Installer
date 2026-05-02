#!/bin/sh
# Check generated router-side installer code for known Asuswrt shell incompatibilities.
# BusyBox/ash-compatible.

set -u

TARGET_FILE="${1:-installer}"
FAILED=0
TMP_PREFIX="/tmp/router-compat.$$"

cleanup() {
	rm -f "${TMP_PREFIX}.command-v" "${TMP_PREFIX}.md5" "${TMP_PREFIX}.rmrf"
}
trap cleanup EXIT HUP INT TERM

if [ ! -f "${TARGET_FILE}" ]; then
	printf '%s\n' "Error: ${TARGET_FILE} not found" >&2
	exit 1
fi

if grep -n 'command -v ' "${TARGET_FILE}" >"${TMP_PREFIX}.command-v" 2>/dev/null; then
	printf '%s\n' "Error: ${TARGET_FILE} contains command -v, which is not available on target Asuswrt shells:" >&2
	cat "${TMP_PREFIX}.command-v" >&2
	FAILED=1
fi

if grep -n 'installer\.md5\>' "${TARGET_FILE}" >"${TMP_PREFIX}.md5" 2>/dev/null; then
	printf '%s\n' "Error: ${TARGET_FILE} references installer.md5 instead of installer.md5sum:" >&2
	cat "${TMP_PREFIX}.md5" >&2
	FAILED=1
fi

if grep -n 'rm -rf[[:space:]].*\$\$' "${TARGET_FILE}" >"${TMP_PREFIX}.rmrf" 2>/dev/null; then
	printf '%s\n' "Error: ${TARGET_FILE} uses rm -rf against a process-id temporary path:" >&2
	cat "${TMP_PREFIX}.rmrf" >&2
	FAILED=1
fi

if [ "${FAILED}" -ne 0 ]; then
	exit 1
fi

printf '%s\n' "OK: ${TARGET_FILE} passed router compatibility guard checks."
