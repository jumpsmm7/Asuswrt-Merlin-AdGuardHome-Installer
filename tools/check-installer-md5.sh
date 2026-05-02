#!/bin/sh
# Validate installer.md5 against the current installer file.
# BusyBox/ash-compatible.

set -u

INSTALLER_FILE="${1:-installer}"
MD5_FILE="${2:-installer.md5}"

if [ ! -f "${INSTALLER_FILE}" ]; then
	printf '%s\n' "Error: ${INSTALLER_FILE} not found." >&2
	exit 1
fi

if [ ! -f "${MD5_FILE}" ]; then
	printf '%s\n' "Error: ${MD5_FILE} not found." >&2
	exit 1
fi

EXPECTED="$(awk '{print $1; exit}' "${MD5_FILE}")"

if command -v md5sum >/dev/null 2>&1; then
	ACTUAL="$(md5sum "${INSTALLER_FILE}" | awk '{print $1; exit}')"
elif command -v openssl >/dev/null 2>&1; then
	ACTUAL="$(openssl dgst -md5 "${INSTALLER_FILE}" | awk '{print $NF; exit}')"
else
	printf '%s\n' 'Error: md5sum or openssl is required.' >&2
	exit 1
fi

if [ -z "${EXPECTED}" ] || [ -z "${ACTUAL}" ]; then
	printf '%s\n' 'Error: checksum value is empty.' >&2
	exit 1
fi

if [ "${EXPECTED}" != "${ACTUAL}" ]; then
	printf '%s\n' "installer.md5 mismatch."
	printf '%s\n' "Expected: ${EXPECTED}"
	printf '%s\n' "Actual:   ${ACTUAL}"
	exit 1
fi

printf '%s\n' "installer.md5 matches installer: ${ACTUAL}"
