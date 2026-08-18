#!/bin/sh
# Exercise release banner, manifest, legacy-version, and stale-checksum checks.

set -u

fail() {
	printf '%s\n' "FAIL: $1" >&2
	exit 1
}

TMP_ROOT="$(mktemp -d)" || fail 'unable to create temporary workspace'
trap 'rm -rf "${TMP_ROOT}"' EXIT
trap 'rm -rf "${TMP_ROOT}"; exit 1' HUP INT TERM

mkdir -p "${TMP_ROOT}/tools" || fail 'unable to create fixture directory'
cp tools/check-release-consistency.sh "${TMP_ROOT}/tools/" || fail 'unable to copy release check'
for artifact in installer AdGuardHome.sh S99AdGuardHome rc.func.AdGuardHome; do
	cp "${artifact}" "${TMP_ROOT}/${artifact}" || fail "unable to copy ${artifact}"
done
# The repository updater is intentionally not part of the fixture; create manifests directly.
for artifact in installer AdGuardHome.sh S99AdGuardHome rc.func.AdGuardHome; do
	md5sum "${TMP_ROOT}/${artifact}" | awk 'NF { print $1; exit }' >"${TMP_ROOT}/${artifact}.md5sum"
	sha256sum "${TMP_ROOT}/${artifact}" | awk 'NF { print $1; exit }' >"${TMP_ROOT}/${artifact}.sha256sum"
done
mkdir -p "${TMP_ROOT}/armv5" || fail 'unable to create archive fixture'
cp armv5/AdGuardHome_stable_linux_armv5.tar.gz* "${TMP_ROOT}/armv5/" || fail 'unable to copy archive fixture'
{
	printf '%s\tstable\tversion=test\t' AdGuardHome_stable_linux_armv5.tar.gz
	md5sum "${TMP_ROOT}/armv5/AdGuardHome_stable_linux_armv5.tar.gz" | awk '{ print $1 }'
	printf '\t'
	sha256sum "${TMP_ROOT}/armv5/AdGuardHome_stable_linux_armv5.tar.gz" | awk '{ print $1 }'
} >"${TMP_ROOT}/armv5/checksum.txt"
for directory in armv7 armv8; do
	mkdir -p "${TMP_ROOT}/${directory}"
	: >"${TMP_ROOT}/${directory}/checksum.txt"
done

RELEASE_ROOT="${TMP_ROOT}" sh "${TMP_ROOT}/tools/check-release-consistency.sh" >/dev/null || fail 'valid fixture was rejected'

sed 's/\([[:space:]]\)[0-9a-f]\{32\}\([[:space:]]\)/\1deadbeefdeadbeefdeadbeefdeadbeef\2/' "${TMP_ROOT}/armv5/checksum.txt" >"${TMP_ROOT}/armv5/checksum.tmp"
mv "${TMP_ROOT}/armv5/checksum.tmp" "${TMP_ROOT}/armv5/checksum.txt"
if RELEASE_ROOT="${TMP_ROOT}" sh "${TMP_ROOT}/tools/check-release-consistency.sh" >/dev/null 2>&1; then
	fail 'stale aggregate checksum was accepted'
fi

# Restore the known-good aggregate metadata for the remaining checks.
{
	printf '%s\tstable\tversion=test\t' AdGuardHome_stable_linux_armv5.tar.gz
	md5sum "${TMP_ROOT}/armv5/AdGuardHome_stable_linux_armv5.tar.gz" | awk '{print $1}'
	printf '\t'
	sha256sum "${TMP_ROOT}/armv5/AdGuardHome_stable_linux_armv5.tar.gz" | awk '{print $1}'
} >"${TMP_ROOT}/armv5/checksum.txt"

sed 's/AI_VERSION="v2.6.5"/AI_VERSION="v9.9.9"/' "${TMP_ROOT}/installer" >"${TMP_ROOT}/installer.tmp"
mv "${TMP_ROOT}/installer.tmp" "${TMP_ROOT}/installer"
if RELEASE_ROOT="${TMP_ROOT}" sh "${TMP_ROOT}/tools/check-release-consistency.sh" >/dev/null 2>&1; then
	fail 'banner/version mismatch was accepted'
fi
cp installer "${TMP_ROOT}/installer"

rm -f "${TMP_ROOT}/AdGuardHome.sh.sha256sum"
if RELEASE_ROOT="${TMP_ROOT}" sh "${TMP_ROOT}/tools/check-release-consistency.sh" >/dev/null 2>&1; then
	fail 'missing manifest was accepted'
fi
sha256sum "${TMP_ROOT}/AdGuardHome.sh" | awk 'NF { print $1; exit }' >"${TMP_ROOT}/AdGuardHome.sh.sha256sum"

(
	cd "${TMP_ROOT}" || exit 1
	git init -q &&
		git config user.name 'Release Test' &&
		git config user.email 'release-test@example.invalid' &&
		git add . &&
		git commit -qm baseline &&
		git commit --allow-empty -qm candidate
) || fail 'unable to create stale-manifest Git fixture'
printf '%s\n' '# changed' >>"${TMP_ROOT}/AdGuardHome.sh"
if RELEASE_ROOT="${TMP_ROOT}" sh "${TMP_ROOT}/tools/check-release-consistency.sh" >"${TMP_ROOT}/stale.out" 2>&1; then
	fail 'artifact/manifest mismatch was accepted'
fi
grep -q 'changed distributed file has an unchanged stale checksum' "${TMP_ROOT}/stale.out" ||
	fail 'unchanged stale manifest was not diagnosed'

printf '%s\n' 'PASS: release consistency failures are detected'
