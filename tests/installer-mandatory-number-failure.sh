#!/bin/sh

set -u

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP_DIR="${TMPDIR:-/tmp}/agh-installer-mandatory-number-failure.$$"
FUNCTIONS_FILE="${TMP_DIR}/functions.sh"

cleanup() {
	rm -rf "${TMP_DIR}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

mkdir -p "${TMP_DIR}" || exit 1

sed -n '/^choose_branch() {$/,/^}$/p' "${REPO_DIR}/installer" >"${FUNCTIONS_FILE}" ||
	fail 'could not extract choose_branch'
sed -n '/^set_timezone() {$/,/^}$/p' "${REPO_DIR}/installer" >>"${FUNCTIONS_FILE}" ||
	fail 'could not extract set_timezone'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

INFO=""
ERROR="Error:"
RURL="https://example.invalid"
CONF_FILE="${TMP_DIR}/missing.conf"
ADDON_DIR="${TMP_DIR}/addon"
CHOSEN=1
WRITE_CONF_CALLED=0
MV_CALLED=0

mkdir -p "${ADDON_DIR}"

PTXT() {
	:
}

conf_value() {
	:
}

del_conf() {
	:
}

write_conf() {
	WRITE_CONF_CALLED=1
}

read_input_num() {
	return 1
}

ensure_opkg_package() {
	return 0
}

ai_have_cmd() {
	return 0
}

download_file() {
	: >"${TMP_DIR}/tzdata-2021e-1-test.pkg.tar.bz2"
}

uname() {
	printf '%s\n' test
}

tar() {
	case "$1" in
		tjf)
			printf '%s\n' './usr/share/zoneinfo/posix/Etc/UTC'
			;;
		*)
			return 0
			;;
	esac
}

column() {
	cat
}

mv() {
	MV_CALLED=1
}

if choose_branch 1; then
	fail 'choose_branch accepted a failed mandatory numeric prompt'
fi
[ "${WRITE_CONF_CALLED}" -eq 0 ] ||
	fail 'choose_branch consumed stale CHOSEN after prompt failure'

if set_timezone; then
	fail 'set_timezone accepted a failed mandatory numeric prompt'
fi
[ "${MV_CALLED}" -eq 0 ] ||
	fail 'set_timezone consumed stale CHOSEN after prompt failure'

printf '%s\n' 'PASS: mandatory numeric prompt failures abort their callers'
