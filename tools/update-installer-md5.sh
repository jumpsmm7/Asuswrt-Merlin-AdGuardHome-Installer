#!/bin/sh
# Update installer.md5 with the MD5 checksum of the current installer file.
# BusyBox/ash-compatible.

set -u

INSTALLER_FILE="${1:-installer}"
MD5_FILE="${2:-installer.md5}"

if [ ! -f "${INSTALLER_FILE}" ]; then
	printf '%s\n' "Error: ${INSTALLER_FILE} not found." >&2
	exit 1
fi

if command -v md5sum >/dev/null 2>&1; then
	MD5_VALUE="$(md5sum "${INSTALLER_FILE}" | awk '{print $1; exit}')"
elif command -v openssl >/dev/null 2>&1; then
	MD5_VALUE="$(openssl dgst -md5 "${INSTALLER_FILE}" | awk '{print $NF; exit}')"
else
	printf '%s\n' 'Error: md5sum or openssl is required.' >&2
	exit 1
fi

if [ -z "${MD5_VALUE}" ]; then
	printf '%s\n' 'Error: could not calculate installer checksum.' >&2
	exit 1
fi

printf '%s  %s\n' "${MD5_VALUE}" "${INSTALLER_FILE}" >"${MD5_FILE}"
printf '%s\n' "Updated ${MD5_FILE}: ${MD5_VALUE}"
