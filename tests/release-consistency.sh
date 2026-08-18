#!/bin/sh
# Exercise release version, channel metadata, manifest, and stale-checksum checks.

set -u

fail() {
	printf '%s\n' "FAIL: $1" >&2
	exit 1
}

refresh_manifests() {
	_target="$1"
	md5sum "${_target}" | awk 'NF { print $1; exit }' >"${_target}.md5sum"
	sha256sum "${_target}" | awk 'NF { print $1; exit }' >"${_target}.sha256sum"
}

write_architecture_fixture() {
	_directory="$1"
	mkdir -p "${TMP_ROOT}/${_directory}" || return 1
	{
		printf '%s\n' '# file channel version md5 sha256'
		for _channel in stable beta edge; do
			_file="AdGuardHome_${_channel}_linux_test.tar.gz"
			printf '%s\n' "${_directory}-${_channel}" >"${TMP_ROOT}/${_directory}/${_file}" || return 1
			refresh_manifests "${TMP_ROOT}/${_directory}/${_file}" || return 1
			_md5="$(cat "${TMP_ROOT}/${_directory}/${_file}.md5sum")"
			_sha256="$(cat "${TMP_ROOT}/${_directory}/${_file}.sha256sum")"
			printf '%s\t%s\t%s\t%s\t%s\n' "${_file}" "${_channel}" 'version=v1.0.0' "${_md5}" "${_sha256}"
		done
	} >"${TMP_ROOT}/${_directory}/checksum.txt"
}

TMP_ROOT="$(mktemp -d)" || fail 'unable to create temporary workspace'
trap 'rm -rf "${TMP_ROOT}"' EXIT
trap 'rm -rf "${TMP_ROOT}"; exit 1' HUP INT TERM

mkdir -p "${TMP_ROOT}/tools" || fail 'unable to create fixture directory'
cp tools/check-release-consistency.sh "${TMP_ROOT}/tools/" || fail 'unable to copy release check'
for artifact in installer AdGuardHome.sh S99AdGuardHome rc.func.AdGuardHome; do
	cp "${artifact}" "${TMP_ROOT}/${artifact}" || fail "unable to copy ${artifact}"
	refresh_manifests "${TMP_ROOT}/${artifact}"
done
for directory in armv5 armv7 armv8; do
	write_architecture_fixture "${directory}" || fail "unable to create ${directory} fixture"
done

RELEASE_ROOT="${TMP_ROOT}" sh "${TMP_ROOT}/tools/check-release-consistency.sh" >/dev/null || fail 'valid fixture was rejected'

sed 's/AI_VERSION="v2.6.5"/AI_VERSION="v9.9.9"/' "${TMP_ROOT}/installer" >"${TMP_ROOT}/installer.tmp"
mv "${TMP_ROOT}/installer.tmp" "${TMP_ROOT}/installer"
refresh_manifests "${TMP_ROOT}/installer"
if RELEASE_ROOT="${TMP_ROOT}" sh "${TMP_ROOT}/tools/check-release-consistency.sh" >/dev/null 2>&1; then
	fail 'banner/version mismatch was accepted'
fi
cp installer "${TMP_ROOT}/installer"
refresh_manifests "${TMP_ROOT}/installer"

sed 's/v2\.6\.5/v2..6.5./g' "${TMP_ROOT}/installer" >"${TMP_ROOT}/installer.tmp"
mv "${TMP_ROOT}/installer.tmp" "${TMP_ROOT}/installer"
refresh_manifests "${TMP_ROOT}/installer"
if RELEASE_ROOT="${TMP_ROOT}" sh "${TMP_ROOT}/tools/check-release-consistency.sh" >/dev/null 2>&1; then
	fail 'malformed dotted release version was accepted'
fi
sed 's/v2\.6\.5/v2.6.10/g' installer >"${TMP_ROOT}/installer"
refresh_manifests "${TMP_ROOT}/installer"
RELEASE_ROOT="${TMP_ROOT}" sh "${TMP_ROOT}/tools/check-release-consistency.sh" >/dev/null ||
	fail 'v2.6.10 was mistaken for the legacy v2.6.1 identifier'
cp installer "${TMP_ROOT}/installer"
refresh_manifests "${TMP_ROOT}/installer"

rm -f "${TMP_ROOT}/AdGuardHome.sh.sha256sum"
if RELEASE_ROOT="${TMP_ROOT}" sh "${TMP_ROOT}/tools/check-release-consistency.sh" >/dev/null 2>&1; then
	fail 'missing manifest was accepted'
fi
refresh_manifests "${TMP_ROOT}/AdGuardHome.sh"

sed '3s/[0-9a-f][0-9a-f]*$/0000000000000000000000000000000000000000000000000000000000000000/' \
	"${TMP_ROOT}/armv5/checksum.txt" >"${TMP_ROOT}/armv5/checksum.txt.tmp"
mv "${TMP_ROOT}/armv5/checksum.txt.tmp" "${TMP_ROOT}/armv5/checksum.txt"
if RELEASE_ROOT="${TMP_ROOT}" sh "${TMP_ROOT}/tools/check-release-consistency.sh" >/dev/null 2>&1; then
	fail 'stale aggregate checksum was accepted'
fi
write_architecture_fixture armv5 || fail 'unable to restore armv5 fixture'

# Intentional glob expansion removes the advertised archive and both checksum sidecars.
rm -f "${TMP_ROOT}/armv5/AdGuardHome_edge_linux_test.tar.gz"*
if RELEASE_ROOT="${TMP_ROOT}" sh "${TMP_ROOT}/tools/check-release-consistency.sh" >/dev/null 2>&1; then
	fail 'missing advertised archive was accepted'
fi
write_architecture_fixture armv5 || fail 'unable to restore armv5 fixture'

(
	cd "${TMP_ROOT}" || exit 1
	git init -q &&
		git config user.name 'Release Test' &&
		git config user.email 'release-test@example.invalid' &&
		git add . &&
		git commit -qm baseline &&
		git commit --allow-empty -qm candidate
) || fail 'unable to create stale-manifest Git fixture'
chmod +x "${TMP_ROOT}/AdGuardHome.sh"
RELEASE_ROOT="${TMP_ROOT}" sh "${TMP_ROOT}/tools/check-release-consistency.sh" >/dev/null ||
	fail 'mode-only artifact change was mistaken for a stale checksum'
printf '%s\n' '# changed' >>"${TMP_ROOT}/AdGuardHome.sh"
if RELEASE_ROOT="${TMP_ROOT}" sh "${TMP_ROOT}/tools/check-release-consistency.sh" >"${TMP_ROOT}/stale.out" 2>&1; then
	fail 'artifact/manifest mismatch was accepted'
fi
grep -q 'changed distributed file has an unchanged stale checksum' "${TMP_ROOT}/stale.out" ||
	fail 'unchanged stale manifest was not diagnosed'

printf '%s\n' 'PASS: release consistency failures are detected'
