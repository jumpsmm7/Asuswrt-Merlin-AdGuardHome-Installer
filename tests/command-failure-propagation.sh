#!/bin/sh
# Verify helper pipelines do not hide failures from required commands.

set -u

ROOT="${TMPDIR:-/tmp}/command-failure-propagation.$$"
CHECK_FUNCTIONS="${ROOT}/check-functions"
DOWNLOAD_FUNCTIONS="${ROOT}/download-functions"
INSTALLER_FUNCTIONS="${ROOT}/installer-functions"

cleanup() {
	rm -rf "${ROOT}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
mkdir -p "${ROOT}" || fail 'could not create test directory'

sed -n '/^calc_md5() {$/,/^}$/p; /^have_cmd() {$/,/^}$/p' tools/check-md5.sh >"${CHECK_FUNCTIONS}" || fail 'could not extract checksum helpers'
sed -n '/^calc_sum() {$/,/^}$/p' tools/download-adguardhome-static.sh >"${DOWNLOAD_FUNCTIONS}" || fail 'could not extract download checksum helper'
sed -n '/^PTXT() {$/,/^}$/p; /^ai_have_cmd() {$/,/^}$/p; /^md5_is_valid() {$/,/^}$/p; /^sha256_is_valid() {$/,/^}$/p; /^file_md5() {$/,/^}$/p; /^file_sha256() {$/,/^}$/p; /^ipv4_is_private() {$/,/^}$/p; /^ipv4_is_valid() {$/,/^}$/p' installer >"${INSTALLER_FUNCTIONS}" || fail 'could not extract installer helpers'

# shellcheck disable=SC1090
. "${CHECK_FUNCTIONS}"
md5sum() {
	return 1
}
if calc_md5 "${ROOT}/missing" >/dev/null 2>&1; then
	fail 'checksum helper hid a failing md5sum command'
fi
md5sum() {
	return 0
}
if calc_md5 "${ROOT}/missing" >/dev/null 2>&1; then
	fail 'checksum helper accepted empty md5sum output'
fi

# shellcheck disable=SC1090
. "${DOWNLOAD_FUNCTIONS}"
checksum_failure() {
	return 1
}
if calc_sum checksum_failure "${ROOT}/missing" >/dev/null 2>&1; then
	fail 'download checksum helper hid a failing checksum command'
fi
checksum_empty() {
	return 0
}
if calc_sum checksum_empty "${ROOT}/missing" >/dev/null 2>&1; then
	fail 'download checksum helper accepted empty checksum output'
fi

# shellcheck disable=SC1090
. "${INSTALLER_FUNCTIONS}"
md5sum() {
	return 1
}
if file_md5 "${ROOT}/missing" >/dev/null 2>&1; then
	fail 'installer checksum helper hid a failing md5sum command'
fi
printf '%s' "abc" >"${ROOT}/sha256-input" || fail 'could not write sha256 test input'
if [ "$(file_sha256 "${ROOT}/sha256-input" 2>/dev/null)" != "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" ]; then
	fail 'installer sha256 helper did not calculate the expected checksum'
fi
mkdir -p "${ROOT}/bin" || fail 'could not create fake command directory'
cat >"${ROOT}/bin/which" <<'EOF' || fail 'could not write fake which'
#!/bin/sh
case "$1" in
	awk | busybox) printf '%s\n' "${0%/*}/$1"; exit 0 ;;
	*) exit 1 ;;
esac
EOF
cat >"${ROOT}/bin/busybox" <<'EOF' || fail 'could not write fake busybox'
#!/bin/sh
[ "$1" = "sha256sum" ] || exit 1
printf '%s  %s\n' "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" "$2"
EOF
ln -s /usr/bin/awk "${ROOT}/bin/awk" || fail 'could not link awk'
chmod 755 "${ROOT}/bin/which" "${ROOT}/bin/busybox" || fail 'could not make fake commands executable'
OLD_PATH="${PATH}"
PATH="${ROOT}/bin"
if [ "$(file_sha256 "${ROOT}/missing" 2>/dev/null)" != "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" ]; then
	PATH="${OLD_PATH}"
	fail 'installer sha256 helper did not fall back to busybox sha256sum'
fi
PATH="${OLD_PATH}"
ipv4_is_valid 192.168.1.1 || fail 'valid IPv4 address was rejected'
if ipv4_is_valid 192.168.1.999; then
	fail 'out-of-range IPv4 address was accepted'
fi
ipv4_is_private 172.16.0.1 || fail 'private IPv4 address was rejected'
if ipv4_is_private 172.15.0.1; then
	fail 'public IPv4 address was classified as private'
fi

printf '%s\n' 'PASS: command failures propagate and portable IPv4 validation is enforced'
