#!/bin/sh
# Exercise release version, channel metadata, manifest, and stale-checksum checks.

set -u

# fail reports an error message to standard error and exits with status 1.
fail() {
	printf '%s\n' "FAIL: $1" >&2
	exit 1
}

# refresh_manifests computes MD5 and SHA-256 checksums for a file and writes them to sidecar manifest files.
refresh_manifests() {
	_target="$1"
	_md5_output="$(md5sum "${_target}")" || return 1
	printf '%s\n' "${_md5_output}" | awk 'NF { print $1; exit }' >"${_target}.md5sum"
	_sha256_output="$(sha256sum "${_target}")" || return 1
	printf '%s\n' "${_sha256_output}" | awk 'NF { print $1; exit }' >"${_target}.sha256sum"
}

# check_context runs the real checker with an explicit GitHub source/target context.
check_context() {
	GITHUB_BASE_REF="$1" GITHUB_REF="$2" \
		RELEASE_ROOT="${TMP_ROOT}" sh "${TMP_ROOT}/tools/check-release-consistency.sh"
}

# check_fixture selects an opt-in source context independently of the caller's CI target.
check_fixture() {
	check_context feat/release-fixture refs/heads/feat/release-fixture
}

# write_architecture_fixture creates release archive fixtures and checksum manifests for a supported architecture.
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
# A real fixture branch makes local-master checks exercise Git rather than a test override.
if which git >/dev/null 2>&1; then
	(
		cd "${TMP_ROOT}" || exit 1
		mkdir -p "${TMP_ROOT}/git-hooks" "${TMP_ROOT}/git-template" &&
			export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 &&
			git init -q --template="${TMP_ROOT}/git-template" &&
			git symbolic-ref HEAD refs/heads/feat/release-fixture &&
			git config user.name 'Release Test' &&
			git config user.email 'release-test@example.invalid' &&
			git config commit.gpgSign false &&
			git config tag.gpgSign false &&
			git config core.hooksPath "${TMP_ROOT}/git-hooks"
	) || fail 'unable to create opt-in Git fixture'
fi
for artifact in installer AdGuardHome.sh S99AdGuardHome rc.func.AdGuardHome; do
	cp "${artifact}" "${TMP_ROOT}/${artifact}" || fail "unable to copy ${artifact}"
	refresh_manifests "${TMP_ROOT}/${artifact}" || fail "unable to refresh manifest for ${artifact}"
done
for directory in armv5 armv7 armv8; do
	write_architecture_fixture "${directory}" || fail "unable to create ${directory} fixture"
done
if which git >/dev/null 2>&1; then
	(
		cd "${TMP_ROOT}" || exit 1
		export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
		git add . && git commit -qm 'opt-in fixture' && git branch master
	) || fail 'unable to create committed fixture branches'
fi
grep -q '^AdGuardHome_stable_linux_arm64\.tar\.gz[[:space:]]' "${TMP_ROOT}/armv8/checksum.txt" ||
	fail 'stable armv8 fixture does not advertise the arm64 archive'
CURRENT_VERSION="$(awk -F= '/^AI_VERSION=/ { gsub(/"/, "", $2); print $2; exit }' "${TMP_ROOT}/installer")"
[ -n "${CURRENT_VERSION}" ] || fail 'unable to read fixture installer version'
VERSION_PATTERN="$(printf '%s\n' "${CURRENT_VERSION}" | sed 's/\./\\./g')"

check_fixture >/dev/null || fail 'valid fixture was rejected'

# Stable and opt-in release candidates use the same exact version in both
# installer identifiers; candidate numbering must not become a stale marker.
for fixture_version in v0.0.0 v2.7.0 v12.34.56 v99.99.99 v02.7.00 v2.7.0-rc.1 v2.7.0-rc.10 v2.7.0-rc.99 v2.7.1-rc.1; do
	sed "s/${VERSION_PATTERN}/${fixture_version}/g" installer >"${TMP_ROOT}/installer"
	refresh_manifests "${TMP_ROOT}/installer" || fail 'unable to refresh version fixture manifests'
	check_fixture >"${TMP_ROOT}/candidate-version.out" 2>&1 ||
		fail "valid installer version ${fixture_version} was rejected"
done

# Candidate refs remain opt-in; every real master context must reject them,
# while the identical fixtures with a stable version must pass.
for fixture_version in v2.7.0-rc.1 v2.7.0; do
	sed "s/${VERSION_PATTERN}/${fixture_version}/g" installer >"${TMP_ROOT}/installer"
	refresh_manifests "${TMP_ROOT}/installer" || fail 'unable to refresh master-context manifests'
	for source_context in pull-request push merge-queue local-master; do
		context_status=0
		case "${source_context}" in
			pull-request)
				check_context master refs/pull/123/merge >"${TMP_ROOT}/master-context.out" 2>&1 || context_status=$?
				;;
			push)
				check_context '' refs/heads/master >"${TMP_ROOT}/master-context.out" 2>&1 || context_status=$?
				;;
			merge-queue)
				check_context '' refs/heads/gh-readonly-queue/master/pr-123-example >"${TMP_ROOT}/master-context.out" 2>&1 || context_status=$?
				;;
			local-master)
				if ! which git >/dev/null 2>&1; then
					printf '%s\n' 'SKIP: local-master release fixture requires git'
					continue
				fi
				git -C "${TMP_ROOT}" checkout -q master || fail 'unable to select real master fixture branch'
				check_fixture >"${TMP_ROOT}/master-context.out" 2>&1 || context_status=$?
				git -C "${TMP_ROOT}" checkout -q feat/release-fixture || fail 'unable to restore opt-in fixture branch'
				;;
		esac
		case "${fixture_version}" in
			*-rc.*)
				[ "${context_status}" -ne 0 ] || fail "candidate was accepted for ${source_context} master context"
				grep -q 'release-candidate AI_VERSION cannot be published on master' "${TMP_ROOT}/master-context.out" ||
					fail "candidate master context ${source_context} was not diagnosed"
				;;
			*) [ "${context_status}" -eq 0 ] || fail "stable version was rejected for ${source_context} master context" ;;
		esac
	done
done
sed "s/${VERSION_PATTERN}/v2.7.0-rc.1/g" installer >"${TMP_ROOT}/installer"
refresh_manifests "${TMP_ROOT}/installer" || fail 'unable to refresh opt-in ref manifests'
for opt_in_ref in refs/heads/feat/release-fixture refs/tags/v2.7.0-rc.1; do
	check_context '' "${opt_in_ref}" >/dev/null || fail "opt-in candidate ref ${opt_in_ref} was rejected"
done
if which git >/dev/null 2>&1; then
	git -C "${TMP_ROOT}" checkout -q --detach || fail 'unable to detach opt-in commit fixture'
	check_context '' '' >/dev/null || fail 'detached opt-in candidate commit was rejected'
	git -C "${TMP_ROOT}" checkout -q feat/release-fixture || fail 'unable to restore opt-in fixture branch'
fi

# Use the published v2.6.7 Git blob when available to establish why master
# cannot advertise an RC to installations using its numeric-only update parser.
if which git >/dev/null 2>&1 && git cat-file -e 047ce167685f6de8db86519557b865e9f23e98f3:installer 2>/dev/null; then
	LEGACY_PARSER="$(git show 047ce167685f6de8db86519557b865e9f23e98f3:installer |
		awk -F "'" '/RMNSTALL=.*awk -F=/ { print $2; exit }')"
	[ -n "${LEGACY_PARSER}" ] || fail 'unable to extract published v2.6.7 remote-version parser'
	[ "$(printf '%s\n' 'AI_VERSION="v2.7.0"' | awk -F= "${LEGACY_PARSER}")" = 2.7.0 ] ||
		fail 'published v2.6.7 parser did not accept the stable control'
	[ -z "$(printf '%s\n' 'AI_VERSION="v2.7.0-rc.1"' | awk -F= "${LEGACY_PARSER}")" ] ||
		fail 'published v2.6.7 parser unexpectedly accepted an RC'
else
	printf '%s\n' 'SKIP: published v2.6.7 parser fixture requires its local Git blob'
fi

for fixture_version in v2.7 v2.7.0.1 2.7.0 V2.7.0 v100.2.3 v2.100.3 v2.7.100 v2.x.0 v2.7.-1 \
	v2.7.0-rc v2.7.0-rc. v2.7.0-rc.0 v2.7.0-rc.01 v2.7.0-rc.-1 v2.7.0-rc.1.1 \
	v2.7.0-rc.100 v2.7.0-rc.1junk v2.7.0-RC.1 v2.7.0-beta.1 v2.7.0+build; do
	sed "s/${VERSION_PATTERN}/${fixture_version}/g" installer >"${TMP_ROOT}/installer"
	refresh_manifests "${TMP_ROOT}/installer" || fail 'unable to refresh malformed version manifests'
	if check_fixture >"${TMP_ROOT}/candidate-version.out" 2>&1; then
		fail "malformed installer version ${fixture_version} was accepted"
	fi
	grep -q 'AI_VERSION is missing or invalid' "${TMP_ROOT}/candidate-version.out" ||
		fail "malformed installer version ${fixture_version} was not diagnosed"
done
for banner_version in v2.7.0 v2.7.0-rc.2 v2.7.0-rc.1junk; do
	sed "s/${VERSION_PATTERN}/${banner_version}/g; s/^AI_VERSION=.*/AI_VERSION=\"v2.7.0-rc.1\"/" installer >"${TMP_ROOT}/installer"
	refresh_manifests "${TMP_ROOT}/installer" || fail 'unable to refresh candidate mismatch manifests'
	if check_fixture >/dev/null 2>&1; then
		fail "candidate AI_VERSION with banner ${banner_version} was accepted"
	fi
done
sed "s/${VERSION_PATTERN}/v2.7.0-rc.1/g" installer >"${TMP_ROOT}/installer"
printf '%s\n' 'AI_VERSION="v2.7.0-rc.1"' >>"${TMP_ROOT}/installer"
refresh_manifests "${TMP_ROOT}/installer" || fail 'unable to refresh duplicate version manifests'
if check_fixture >/dev/null 2>&1; then
	fail 'duplicate installer AI_VERSION assignments were accepted'
fi
sed "s/${VERSION_PATTERN}/v2.7.0-rc.1/g" installer >"${TMP_ROOT}/installer"
printf '%s\n' '# stale release v2.7.1' >>"${TMP_ROOT}/installer"
refresh_manifests "${TMP_ROOT}/installer" || fail 'unable to refresh candidate stale-marker manifests'
if check_fixture >"${TMP_ROOT}/candidate-stale.out" 2>&1; then
	fail 'candidate version bypassed the stable stale-release guard'
fi
grep -q 'release identifier v2.7.1 remains' "${TMP_ROOT}/candidate-stale.out" || fail 'candidate stale-release marker was not diagnosed'
cp installer "${TMP_ROOT}/installer"
refresh_manifests "${TMP_ROOT}/installer" || fail 'unable to restore installer manifests after candidate fixtures'

awk 'BEGIN { OFS="\t" }
	$1 !~ /^#/ && $2 == "stable" { $2 = "edge" }
	$1 !~ /^#/ && $2 == "edge" && $1 ~ /_edge_/ { $2 = "stable" }
	{ print }' "${TMP_ROOT}/armv5/checksum.txt" >"${TMP_ROOT}/armv5/checksum.txt.tmp"
mv "${TMP_ROOT}/armv5/checksum.txt.tmp" "${TMP_ROOT}/armv5/checksum.txt"
if check_fixture >"${TMP_ROOT}/channel-name-mismatch.out" 2>&1; then
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
if check_fixture >"${TMP_ROOT}/version-mismatch.out" 2>&1; then
	fail 'architecture-specific stable version mismatch was accepted'
fi
grep -q 'stable channel version differs in armv7/checksum.txt: expected v1.0.1, actual v1.0.0' \
	"${TMP_ROOT}/version-mismatch.out" || fail 'architecture-specific stable version mismatch was not diagnosed'
write_architecture_fixture armv5 || fail 'unable to restore armv5 fixture'

awk 'BEGIN { OFS = "\t" } /^#/ { print; next } { if ($2 == "stable") $2 = "edge"; else if ($2 == "edge") $2 = "stable"; print }' \
	"${TMP_ROOT}/armv7/checksum.txt" >"${TMP_ROOT}/armv7/checksum.txt.tmp"
mv "${TMP_ROOT}/armv7/checksum.txt.tmp" "${TMP_ROOT}/armv7/checksum.txt"
if check_fixture >"${TMP_ROOT}/channel-filename-mismatch.out" 2>&1; then
	fail 'swapped stable and edge channel labels were accepted'
fi
grep -q 'expected AdGuardHome_edge_linux_armv7.tar.gz, advertised AdGuardHome_stable_linux_armv7.tar.gz' \
	"${TMP_ROOT}/channel-filename-mismatch.out" || fail 'stable archive with edge channel label was not diagnosed'
grep -q 'expected AdGuardHome_stable_linux_armv7.tar.gz, advertised AdGuardHome_edge_linux_armv7.tar.gz' \
	"${TMP_ROOT}/channel-filename-mismatch.out" || fail 'edge archive with stable channel label was not diagnosed'
write_architecture_fixture armv7 || fail 'unable to restore armv7 fixture'

sed "s/AI_VERSION=\"${VERSION_PATTERN}\"/AI_VERSION=\"v9.9.9\"/" "${TMP_ROOT}/installer" >"${TMP_ROOT}/installer.tmp"
mv "${TMP_ROOT}/installer.tmp" "${TMP_ROOT}/installer"
refresh_manifests "${TMP_ROOT}/installer" || fail "unable to refresh installer manifest"
if check_fixture >/dev/null 2>&1; then
	fail 'banner/version mismatch was accepted'
fi
cp installer "${TMP_ROOT}/installer"
refresh_manifests "${TMP_ROOT}/installer" || fail "unable to refresh installer manifest"

MALFORMED_VERSION="${CURRENT_VERSION%.*}..${CURRENT_VERSION##*.}"
sed "s/${VERSION_PATTERN}/${MALFORMED_VERSION}/g" "${TMP_ROOT}/installer" >"${TMP_ROOT}/installer.tmp"
mv "${TMP_ROOT}/installer.tmp" "${TMP_ROOT}/installer"
refresh_manifests "${TMP_ROOT}/installer" || fail "unable to refresh installer manifest"
if check_fixture >/dev/null 2>&1; then
	fail 'malformed dotted release version was accepted'
fi
CURRENT_BASE_VERSION="${CURRENT_VERSION%-rc.*}"
STALE_VERSION="${CURRENT_BASE_VERSION%.*}.1"
[ "${STALE_VERSION}" != "${CURRENT_BASE_VERSION}" ] || STALE_VERSION="${CURRENT_BASE_VERSION%.*}.2"
BOUNDARY_VERSION="${STALE_VERSION}0"
sed "s/${VERSION_PATTERN}/${BOUNDARY_VERSION}/g" installer >"${TMP_ROOT}/installer"
refresh_manifests "${TMP_ROOT}/installer" || fail "unable to refresh installer manifest"
check_fixture >/dev/null ||
	fail "${BOUNDARY_VERSION} was mistaken for the derived stale release identifier"
cp installer "${TMP_ROOT}/installer"
refresh_manifests "${TMP_ROOT}/installer" || fail "unable to refresh installer manifest"

if [ "${CURRENT_BASE_VERSION%.*}.1" != "${CURRENT_BASE_VERSION}" ]; then
	printf '%s\n' "# stale release ${STALE_VERSION}" >>"${TMP_ROOT}/installer"
	refresh_manifests "${TMP_ROOT}/installer" || fail "unable to refresh installer manifest"
	if check_fixture >/dev/null 2>&1; then
		fail "derived stale release ${STALE_VERSION} was accepted"
	fi
	cp installer "${TMP_ROOT}/installer"
	refresh_manifests "${TMP_ROOT}/installer" || fail "unable to refresh installer manifest"
fi

rm -f "${TMP_ROOT}/AdGuardHome.sh.sha256sum"
if check_fixture >/dev/null 2>&1; then
	fail 'missing manifest was accepted'
fi
refresh_manifests "${TMP_ROOT}/AdGuardHome.sh" || fail "unable to refresh AdGuardHome.sh manifest"

sed '3s/[0-9a-f][0-9a-f]*$/0000000000000000000000000000000000000000000000000000000000000000/' \
	"${TMP_ROOT}/armv5/checksum.txt" >"${TMP_ROOT}/armv5/checksum.txt.tmp"
mv "${TMP_ROOT}/armv5/checksum.txt.tmp" "${TMP_ROOT}/armv5/checksum.txt"
if check_fixture >/dev/null 2>&1; then
	fail 'stale aggregate checksum was accepted'
fi
write_architecture_fixture armv5 || fail 'unable to restore armv5 fixture'

# Intentional glob expansion removes the advertised archive and both checksum sidecars.
rm -f "${TMP_ROOT}/armv5/AdGuardHome_edge_linux_armv5.tar.gz"*
if check_fixture >/dev/null 2>&1; then
	fail 'missing advertised archive was accepted'
fi
write_architecture_fixture armv5 || fail 'unable to restore armv5 fixture'

if which git >/dev/null 2>&1; then
	(
		cd "${TMP_ROOT}" || exit 1
		export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
		git add . &&
			git commit -qm baseline &&
			git commit --allow-empty -qm candidate
	) || fail 'unable to create stale-manifest Git fixture'
	chmod +x "${TMP_ROOT}/AdGuardHome.sh"
	check_fixture >/dev/null ||
		fail 'mode-only artifact change was mistaken for a stale checksum'
	printf '%s\n' '# changed' >>"${TMP_ROOT}/AdGuardHome.sh"
	if check_fixture >"${TMP_ROOT}/stale.out" 2>&1; then
		fail 'artifact/manifest mismatch was accepted'
	fi
	grep -q 'changed distributed file has an unchanged stale checksum' "${TMP_ROOT}/stale.out" ||
		fail 'unchanged stale manifest was not diagnosed'
else
	printf '%s\n' 'SKIP: stale-manifest Git fixture requires git'
fi

printf '%s\n' 'PASS: release consistency failures are detected'
