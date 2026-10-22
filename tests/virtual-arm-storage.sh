#!/bin/sh
# Exercise actual full/read-only filesystems with the service staging helpers.

set -u
export LC_ALL=C

REPO_ROOT="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="/tmp/agh-isolated-storage.$$"
MOUNTED=0

# fail reports the storage boundary that failed and lets owned cleanup run.
fail() {
	printf '%s\n' "FAIL: isolated storage: $*" >&2
	exit 1
}
# cleanup unmounts only this test's private filesystem before removing its files.
cleanup() {
	if [ "${MOUNTED}" = 1 ]; then
		umount "${TEST_ROOT}/storage" || return 1
		MOUNTED=0
	fi
	rm -rf "${TEST_ROOT}"
}

[ "$(id -u)" = 0 ] && { [ -f /run/virtual-arm-guest ] || [ -f /.dockerenv ]; } ||
	fail 'requires an isolated root ARM guest or privileged test container'
[ ! -e "${TEST_ROOT}" ] && [ ! -L "${TEST_ROOT}" ] || fail 'private fixture path already exists'
(umask 077 && mkdir -p "${TEST_ROOT}/storage" "${TEST_ROOT}/base") || fail 'could not create private fixture'
trap cleanup 0
trap 'exit 1' HUP INT TERM
sed -n \
	-e '/^adguard_service_bundle_cleanup() {$/,/^}/p' \
	-e '/^adguard_service_bundle_stage() {$/,/^}/p' \
	-e '/^adguard_service_publish_cleanup() {$/,/^}/p' \
	-e '/^adguard_service_publish_file() {$/,/^}/p' \
	"${REPO_ROOT}/installer" >"${TEST_ROOT}/helpers" || fail 'could not extract service helpers'
grep -q '^adguard_service_bundle_stage() {$' "${TEST_ROOT}/helpers" || fail 'service staging helper is missing'
awk '
	/^support_export[a-z_]*\(\) \{$/ { copying=1 }
	copying { print }
	copying && /^}$/ { copying=0 }
' "${REPO_ROOT}/installer" >>"${TEST_ROOT}/helpers" || fail 'could not extract diagnostic helpers'
grep -q '^support_export() {$' "${TEST_ROOT}/helpers" || fail 'support export helper is missing'
# shellcheck disable=SC1090
. "${TEST_ROOT}/helpers"

ERROR=Error:
INFO=Info:
RURL=https://fixture.invalid/source
ADGUARD_SERVICE_STAGE_DIR=''
ADGUARD_SERVICE_STAGE_OWNED=0
ADGUARD_SERVICE_PUBLISH_DIR=''
ADGUARD_SERVICE_PUBLISH_OWNED=0
# PTXT records only fixture diagnostics, with no real firmware calls.
PTXT() { printf '%s\n' "$*"; }
# ptxt_step preserves meaningful installer staging diagnostics.
ptxt_step() { PTXT "$*"; }
# ptxt_ok records completion of a modeled network-transfer boundary.
ptxt_ok() { PTXT "$*"; }
# download_file models the already-tested download/verification boundary using a
# real copy, so full/read-only storage still fails in the kernel.
download_file() {
	printf '%s\n' transfer >>"${TEST_ROOT}/network.calls" || return 1
	cp "${TEST_ROOT}/payload" "$1/${3##*/}"
}
printf '%s\n' 'verified service payload for real filesystem writes' >"${TEST_ROOT}/payload" || fail 'could not create transfer payload'

for storage_fault in full readonly; do
	mount -t tmpfs -o size=256k,mode=0700 tmpfs "${TEST_ROOT}/storage" || fail 'could not mount isolated tmpfs'
	MOUNTED=1
	printf '%s\n' 'working service payload' >"${TEST_ROOT}/storage/AdGuardHome.sh" || fail 'could not create working target'
	before="$(sha256sum "${TEST_ROOT}/storage/AdGuardHome.sh" | awk '{ print $1 }')"
	case "${storage_fault}" in
		full)
			dd if=/dev/zero of="${TEST_ROOT}/storage/fill" bs=1024 count=256 >/dev/null 2>&1 && fail 'storage fill unexpectedly fit'
			[ "$(df -Pk "${TEST_ROOT}/storage" | awk 'NR == 2 { print $4 }')" = 0 ] || fail 'fixture is not actually full'
			;;
		readonly)
			mount -o remount,ro "${TEST_ROOT}/storage" || fail 'could not remount fixture read-only'
			if (printf '%s\n' probe >"${TEST_ROOT}/storage/write-probe") 2>/dev/null; then fail 'fixture is not actually read-only'; fi
			;;
	esac
	BASE_DIR="${TEST_ROOT}/base"
	TARG_DIR="${TEST_ROOT}/storage"
	ADDON_DIR="${TEST_ROOT}/storage"
	ADGUARD_SERVICE_STAGE_DIR="${BASE_DIR}/.AdGuardHome.services.$$"
	(umask 077 && mkdir "${ADGUARD_SERVICE_STAGE_DIR}") || fail 'could not create verified staging directory'
	ADGUARD_SERVICE_STAGE_OWNED=1
	cp "${TEST_ROOT}/payload" "${ADGUARD_SERVICE_STAGE_DIR}/AdGuardHome.sh" || fail 'could not stage verified payload'
	if adguard_service_publish_file "${ADDON_DIR}" AdGuardHome.sh 755; then fail "${storage_fault}: failed publication reported success"; fi
	[ "$(sha256sum "${ADDON_DIR}/AdGuardHome.sh" | awk '{ print $1 }')" = "${before}" ] || fail "${storage_fault}: working service changed"
	adguard_service_publish_cleanup || fail "${storage_fault}: private publication cleanup failed"
	adguard_service_bundle_cleanup || fail 'could not clear healthy source staging'
	BASE_DIR="${TEST_ROOT}/storage"
	if adguard_service_bundle_stage; then fail "${storage_fault}: prefetch onto unusable storage reported success"; fi
	[ "$(sha256sum "${ADDON_DIR}/AdGuardHome.sh" | awk '{ print $1 }')" = "${before}" ] || fail "${storage_fault}: rejected prefetch changed live service"
	[ "${ADGUARD_SERVICE_STAGE_OWNED:-0}" = 0 ] || fail "${storage_fault}: rejected prefetch retained an owned stage"
	if support_export --output "${TEST_ROOT}/storage/support.txt"; then fail "${storage_fault}: support export onto unusable storage reported success"; fi
	[ ! -e "${TEST_ROOT}/storage/support.txt" ] || fail "${storage_fault}: failed support export published a partial report"
	[ "$(sha256sum "${ADDON_DIR}/AdGuardHome.sh" | awk '{ print $1 }')" = "${before}" ] || fail "${storage_fault}: failed support export changed the working service"
	umount "${TEST_ROOT}/storage" || fail 'could not release isolated filesystem'
	MOUNTED=0
	printf '%s\n' "PASS: actual ${storage_fault} kernel filesystem refuses service staging/publication and support export; working service preserved"
done
printf '%s\n' "PASS: isolated storage architecture=$(uname -m); network transfer modeled; filesystem writes and mount faults execute in the kernel"
