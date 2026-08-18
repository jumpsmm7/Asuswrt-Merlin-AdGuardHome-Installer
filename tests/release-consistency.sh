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
	case "${_directory}" in
		armv5) _archive_arch='armv5' ;;
		armv7) _archive_arch='armv7' ;;
		armv8) _archive_arch='arm64' ;;
		*) return 1 ;;
	esac
	mkdir -p "${TMP_ROOT}/${_directory}" || return 1
	{
		printf '%s\n' '# file channel version md5 sha256'
		for _channel in stable beta edge; do
			_file="AdGuardHome_${_channel}_linux_${_archive_arch}.tar.gz"
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
CURRENT_VERSION="$(awk -F= '/^AI_VERSION=/ { gsub(/"/, "", $2); print $2; exit }' "${TMP_ROOT}/installer")"
[ -n "${CURRENT_VERSION}" ] || fail 'unable to read fixture installer version'
VERSION_PATTERN="$(printf '%s\n' "${CURRENT_VERSION}" | sed 's/\./\\./g')"

RELEASE_ROOT="${TMP_ROOT}" sh "${TMP_ROOT}/tools/check-release-consistency.sh" >/dev/null || fail 'valid fixture was rejected'

awk 'BEGIN { OFS="\t" }
	$1 !~ /^#/ && $2 == "stable" { $2 = "edge" }
	$1 !~ /^#/ && $2 == "edge" && $1 ~ /_edge_/ { $2 = "stable" }
	{ print }' "${TMP_ROOT}/armv5/checksum.txt" >"${TMP_ROOT}/armv5/checksum.txt.tmp"
mv "${TMP_ROOT}/armv5/checksum.txt.tmp" "${TMP_ROOT}/armv5/checksum.txt"
if RELEASE_ROOT="${TMP_ROOT}" sh "${TMP_ROOT}/tools/check-release-consistency.sh" >"${TMP_ROOT}/channel-name-mismatch.out" 2>&1; then
	fail 'mislabeled stable and edge archive rows were accepted'
fi
grep -q 'expected AdGuardHome_edge_linux_armv5.tar.gz, advertised AdGuardHome_stable_linux_armv5.tar.gz' \
	"${TMP_ROOT}/channel-name-mismatch.out" || fail 'mislabeled stable archive row was not diagnosed'
grep -q 'expected AdGuardHome_stable_linux_armv5.tar.gz, advertised AdGuardHome_edge_linux_armv5.tar.gz' \
	"${TMP_ROOT}/channel-name-mismatch.out" || fail 'mislabeled edge archive row was not diagnosed'
write_architecture_fixture armv5 || fail 'unable to restore armv5 fixture'

sed '/[[:space:]]stable[[:space:]]/s/version=v1\.0\.0/version=v1.0.1/' \
	"${TMP_ROOT}/armv5/checksum.txt" >"${TMP_ROOT}/armv5/checksum.txt.tmp"
mv "${TMP_ROOT}/armv5/checksum.txt.tmp" "${TMP_ROOT}/armv5/checksum.txt"
if RELEASE_ROOT="${TMP_ROOT}" sh "${TMP_ROOT}/tools/check-release-consistency.sh" >"${TMP_ROOT}/version-mismatch.out" 2>&1; then
	fail 'architecture-specific stable version mismatch was accepted'
fi
grep -q 'stable channel version differs in armv7/checksum.txt: expected v1.0.1, actual v1.0.0' \
	"${TMP_ROOT}/version-mismatch.out" || fail 'architecture-specific stable version mismatch was not diagnosed'
write_architecture_fixture armv5 || fail 'unable to restore armv5 fixture'

awk 'BEGIN { OFS = "\t" } /^#/ { print; next } { if ($2 == "stable") $2 = "edge"; else if ($2 == "edge") $2 = "stable"; print }' \
	"${TMP_ROOT}/armv7/checksum.txt" >"${TMP_ROOT}/armv7/checksum.txt.tmp"
mv "${TMP_ROOT}/armv7/checksum.txt.tmp" "${TMP_ROOT}/armv7/checksum.txt"
if RELEASE_ROOT="${TMP_ROOT}" sh "${TMP_ROOT}/tools/check-release-consistency.sh" >"${TMP_ROOT}/channel-filename-mismatch.out" 2>&1; then
	fail 'swapped stable and edge channel labels were accepted'
fi
grep -q 'expected AdGuardHome_edge_linux_armv7.tar.gz, advertised AdGuardHome_stable_linux_armv7.tar.gz' \
	"${TMP_ROOT}/channel-filename-mismatch.out" || fail 'stable archive with edge channel label was not diagnosed'
grep -q 'expected AdGuardHome_stable_linux_armv7.tar.gz, advertised AdGuardHome_edge_linux_armv7.tar.gz' \
	"${TMP_ROOT}/channel-filename-mismatch.out" || fail 'edge archive with stable channel label was not diagnosed'
write_architecture_fixture armv7 || fail 'unable to restore armv7 fixture'

sed "s/AI_VERSION=\"${VERSION_PATTERN}\"/AI_VERSION=\"v9.9.9\"/" "${TMP_ROOT}/installer" >"${TMP_ROOT}/installer.tmp"
mv "${TMP_ROOT}/installer.tmp" "${TMP_ROOT}/installer"
refresh_manifests "${TMP_ROOT}/installer"
if RELEASE_ROOT="${TMP_ROOT}" sh "${TMP_ROOT}/tools/check-release-consistency.sh" >/dev/null 2>&1; then
	fail 'banner/version mismatch was accepted'
fi
cp installer "${TMP_ROOT}/installer"
refresh_manifests "${TMP_ROOT}/installer"

MALFORMED_VERSION="${CURRENT_VERSION%.*}..${CURRENT_VERSION##*.}"
sed "s/${VERSION_PATTERN}/${MALFORMED_VERSION}/g" "${TMP_ROOT}/installer" >"${TMP_ROOT}/installer.tmp"
mv "${TMP_ROOT}/installer.tmp" "${TMP_ROOT}/installer"
refresh_manifests "${TMP_ROOT}/installer"
if RELEASE_ROOT="${TMP_ROOT}" sh "${TMP_ROOT}/tools/check-release-consistency.sh" >/dev/null 2>&1; then
	fail 'malformed dotted release version was accepted'
fi
STALE_VERSION="${CURRENT_VERSION%.*}.1"
BOUNDARY_VERSION="${STALE_VERSION}0"
sed "s/${VERSION_PATTERN}/${BOUNDARY_VERSION}/g" installer >"${TMP_ROOT}/installer"
refresh_manifests "${TMP_ROOT}/installer"
RELEASE_ROOT="${TMP_ROOT}" sh "${TMP_ROOT}/tools/check-release-consistency.sh" >/dev/null ||
	fail "${BOUNDARY_VERSION} was mistaken for the derived stale release identifier"
cp installer "${TMP_ROOT}/installer"
refresh_manifests "${TMP_ROOT}/installer"

if [ "${STALE_VERSION}" != "${CURRENT_VERSION}" ]; then
	printf '%s\n' "# stale release ${STALE_VERSION}" >>"${TMP_ROOT}/installer"
	refresh_manifests "${TMP_ROOT}/installer"
	if RELEASE_ROOT="${TMP_ROOT}" sh "${TMP_ROOT}/tools/check-release-consistency.sh" >/dev/null 2>&1; then
		fail "derived stale release ${STALE_VERSION} was accepted"
	fi
	cp installer "${TMP_ROOT}/installer"
	refresh_manifests "${TMP_ROOT}/installer"
fi

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
rm -f "${TMP_ROOT}/armv5/AdGuardHome_edge_linux_armv5.tar.gz"*
if RELEASE_ROOT="${TMP_ROOT}" sh "${TMP_ROOT}/tools/check-release-consistency.sh" >/dev/null 2>&1; then
	fail 'missing advertised archive was accepted'
fi
write_architecture_fixture armv5 || fail 'unable to restore armv5 fixture'

(
	cd "${TMP_ROOT}" || exit 1
	mkdir -p "${TMP_ROOT}/git-home" "${TMP_ROOT}/git-hooks" "${TMP_ROOT}/git-template" &&
		export HOME="${TMP_ROOT}/git-home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 &&
		git init -q --template="${TMP_ROOT}/git-template" &&
		git config user.name 'Release Test' &&
		git config user.email 'release-test@example.invalid' &&
		git config commit.gpgSign false &&
		git config tag.gpgSign false &&
		git config core.hooksPath "${TMP_ROOT}/git-hooks" &&
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
