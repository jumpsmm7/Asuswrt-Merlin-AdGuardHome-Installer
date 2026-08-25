#!/bin/sh
# Download and publish current signed Arch Linux ARM tzdata packages.
# POSIX /bin/sh-compatible; intended for CI validation hosts.

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${0}")" && pwd)"
. "${SCRIPT_DIR}/tzdata-package-info.sh"

OUT_DIR="${1:-.}"
: "${CURL_CA_BUNDLE:?CURL_CA_BUNDLE is required}"
: "${MIRROR_HOSTS:?MIRROR_HOSTS is required}"
: "${PYTHON3:?PYTHON3 is required}"
: "${SIGNING_KEY_FINGERPRINT:?SIGNING_KEY_FINGERPRINT is required}"

if [ ! -r "${CURL_CA_BUNDLE}" ]; then
	printf 'Certificate authority bundle is not readable: %s\n' "${CURL_CA_BUNDLE}" >&2
	exit 1
fi
if [ "${PYTHON3}" != /usr/bin/python3 ] || [ ! -x "${PYTHON3}" ]; then
	printf 'Trusted Python 3 interpreter is unavailable: %s\n' "${PYTHON3}" >&2
	exit 1
fi

cd "${OUT_DIR}" || exit 1

stage_dir="$(mktemp -d)"
trap 'rm -rf "${stage_dir}"' 0
export GNUPGHOME="${stage_dir}/gnupg"
mkdir -m 700 "${GNUPGHOME}"

gpg --batch --keyserver hkps://keyserver.ubuntu.com \
	--keyserver-options timeout=30 \
	--recv-keys "${SIGNING_KEY_FINGERPRINT}"
imported_fingerprint="$(gpg --batch --with-colons --fingerprint "${SIGNING_KEY_FINGERPRINT}" |
	awk -F: '$1 == "fpr" { print $10; exit }')"
if [ "${imported_fingerprint}" != "${SIGNING_KEY_FINGERPRINT}" ]; then
	printf 'Unexpected Arch Linux ARM signing-key fingerprint: %s\n' "${imported_fingerprint}" >&2
	exit 1
fi

verify_signature() {
	local signed_file signature_file valid_signature
	signed_file="$1"
	signature_file="$2"
	valid_signature="$(gpg --batch --status-fd 1 --verify "${signature_file}" "${signed_file}" 2>/dev/null |
		awk -v fingerprint="${SIGNING_KEY_FINGERPRINT}" \
			'$1 == "[GNUPG:]" && $2 == "VALIDSIG" && ($3 == fingerprint || $NF == fingerprint) { print $3; exit }')"
	if [ -z "${valid_signature}" ]; then
		printf 'Signature verification failed for %s\n' "${signed_file}" >&2
		return 1
	fi
}

download_verified_pair() {
	local max_time mirror_host mirror_url output_file protocol redirect_protocols relative_path signature_file
	relative_path="$1"
	output_file="$2"
	max_time="$3"
	signature_file="${output_file}.sig"

	# MIRROR_HOSTS is a trusted, whitespace-separated workflow setting. Try all
	# TLS endpoints before the signed HTTP fallback, and authenticate every pair
	# before consuming it.
	for protocol in https http; do
		redirect_protocols="=${protocol}"
		[ "${protocol}" != http ] || redirect_protocols='=http,https'
		for mirror_host in ${MIRROR_HOSTS}; do
			mirror_url="${protocol}://${mirror_host}"
			rm -f "${output_file}" "${signature_file}"
			printf 'Downloading %s from %s\n' "${relative_path}" "${mirror_url}"
			if curl --fail --location --silent --show-error \
				--cacert "${CURL_CA_BUNDLE}" \
				--proto "=${protocol}" --proto-redir "${redirect_protocols}" \
				--connect-timeout 15 --max-time "${max_time}" \
				"${mirror_url}/${relative_path}" --output "${output_file}" &&
				curl --fail --location --silent --show-error \
					--cacert "${CURL_CA_BUNDLE}" \
					--proto "=${protocol}" --proto-redir "${redirect_protocols}" \
					--connect-timeout 15 --max-time 120 \
					"${mirror_url}/${relative_path}.sig" --output "${signature_file}" &&
				verify_signature "${output_file}" "${signature_file}"; then
				return 0
			fi
			printf 'Mirror failed verification or download: %s\n' "${mirror_url}" >&2
		done
	done

	rm -f "${output_file}" "${signature_file}"
	printf 'No mirror supplied a verified copy of %s\n' "${relative_path}" >&2
	return 1
}

discover_package_filename() {
	local architecture filename mirror_host mirror_url package_listing protocol redirect_protocols
	architecture="$1"
	package_listing="${stage_dir}/package-${architecture}.html"

	# Discover the filename from the same mirrors that serve the package.  The
	# public package-index pages are not a stable API and may return 404 even
	# while the repository remains available.
	for protocol in https http; do
		redirect_protocols="=${protocol}"
		[ "${protocol}" != http ] || redirect_protocols='=http,https'
		for mirror_host in ${MIRROR_HOSTS}; do
			mirror_url="${protocol}://${mirror_host}"
			if ! curl --fail --location --silent --show-error \
				--cacert "${CURL_CA_BUNDLE}" \
				--proto "=${protocol}" --proto-redir "${redirect_protocols}" \
				--connect-timeout 15 --max-time 120 \
				"${mirror_url}/${architecture}/core/" --output "${package_listing}"; then
				printf 'Failed to download package listing from %s\n' "${mirror_url}" >&2
				continue
			fi
			filename="$(grep -Eo "tzdata-[A-Za-z0-9._+-]+-(any|${architecture})\\.pkg\\.tar\\.(bz2|xz|zst)" "${package_listing}" |
				head -n 1)"
			case "${filename}" in
				tzdata-*-any.pkg.tar.bz2 | tzdata-*-any.pkg.tar.xz | tzdata-*-any.pkg.tar.zst | tzdata-*-${architecture}.pkg.tar.bz2 | tzdata-*-${architecture}.pkg.tar.xz | tzdata-*-${architecture}.pkg.tar.zst)
					printf '%s\n' "${filename}"
					return 0
					;;
			esac
			printf 'No valid tzdata filename in package listing from %s\n' "${mirror_url}" >&2
		done
	done

	printf 'Failed to discover package filename for %s from all mirrors\n' "${architecture}" >&2
	return 1
}

download_package() {
	local architecture output_arch filename
	local upstream_file package_info package_version package_arch output_file
	architecture="$1"
	output_arch="$2"
	if ! filename="$(discover_package_filename "${architecture}")" || [ -z "${filename}" ]; then
		printf 'Failed to discover package filename for %s\n' "${architecture}" >&2
		return 1
	fi
	if [ "${filename}" != "$(basename "${filename}")" ]; then
		printf 'Filename contains path separators: %s\n' "${filename}" >&2
		return 1
	fi

	upstream_file="${stage_dir}/upstream-${architecture}.${filename##*.}"
	download_verified_pair "${architecture}/core/${filename}" "${upstream_file}" 300

	if ! package_info="$(extract_package_info "${upstream_file}")"; then
		printf 'Failed to extract .PKGINFO from %s\n' "${upstream_file}" >&2
		return 1
	fi
	package_version="$(printf '%s\n' "${package_info}" | awk -F ' = ' '$1 == "pkgver" { print $2; exit }')"
	package_arch="$(printf '%s\n' "${package_info}" | awk -F ' = ' '$1 == "arch" { print $2; exit }')"
	if [ -z "${package_version}" ] || [ -z "${package_arch}" ]; then
		printf 'Failed to extract version or architecture from .PKGINFO\n' >&2
		return 1
	fi
	case "${package_version}" in
		'' | *[!A-Za-z0-9._+-]*) return 1 ;;
	esac
	case "${package_arch}:${architecture}" in
		aarch64:aarch64 | armv7h:armv7h | any:*) ;;
		*)
			printf 'Package architecture mismatch: %s for %s\n' "${package_arch}" "${architecture}" >&2
			return 1
			;;
	esac

	output_file="${stage_dir}/tzdata-${package_version}-${output_arch}.pkg.tar.bz2"
	case "${upstream_file}" in
		*.bz2) cp "${upstream_file}" "${output_file}" ;;
		*.xz) xz -dc "${upstream_file}" | bzip2 -9 >"${output_file}" ;;
		*.zst) zstd --decompress --stdout "${upstream_file}" | bzip2 -9 >"${output_file}" ;;
	esac
	tar -tjf "${output_file}" >/dev/null
	"${PYTHON3}" - "${output_file}" <<'PY'
import posixpath
import sys
import tarfile

archive = sys.argv[1]
with tarfile.open(archive, "r:bz2") as package:
    has_posix_timezone = False
    for member in package.getmembers():
        normalized_name = posixpath.normpath(member.name)
        if member.name.startswith("/") or normalized_name == ".." or normalized_name.startswith("../"):
            raise SystemExit(f"Unsafe archive member path: {member.name}")
        if member.isfile() and normalized_name.startswith("usr/share/zoneinfo/posix/"):
            has_posix_timezone = True
        if member.issym() or member.islnk():
            link_path = posixpath.normpath(posixpath.join(posixpath.dirname(normalized_name), member.linkname))
            if member.linkname.startswith("/") or link_path == ".." or link_path.startswith("../"):
                raise SystemExit(f"Unsafe archive link: {member.name} -> {member.linkname}")
    if not has_posix_timezone:
        raise SystemExit(f"Package has no usable POSIX timezone payload: {archive}")
PY
	printf '%s\n' "${package_version}" >"${stage_dir}/version-${output_arch}"
}

download_package aarch64 aarch64
download_package armv7h arm

aarch64_version="$(cat "${stage_dir}/version-aarch64")"
arm_version="$(cat "${stage_dir}/version-arm")"
if [ "${aarch64_version}" != "${arm_version}" ]; then
	printf 'tzdata versions differ: aarch64=%s arm=%s\n' "${aarch64_version}" "${arm_version}" >&2
	exit 1
fi

publish_package() {
	local output_arch package_version published_file staged_file
	output_arch="$1"
	package_version="$2"
	published_file="tzdata-${package_version}-${output_arch}.pkg.tar.bz2"
	staged_file="${stage_dir}/${published_file}"

	if [ ! -f "${staged_file}" ]; then
		printf '%s package file not found: %s\n' "${output_arch}" "${staged_file}" >&2
		return 1
	fi
	if ! tar -tjf "${staged_file}" >/dev/null; then
		printf 'Invalid bzip2 package archive: %s\n' "${staged_file}" >&2
		return 1
	fi
	mv "${staged_file}" "${published_file}"
	if [ ! -f "${published_file}" ]; then
		printf 'Failed to publish package file: %s\n' "${published_file}" >&2
		return 1
	fi
	if ! sh tools/update-checksums.sh "${published_file}" ||
		[ ! -f "${published_file}.md5sum" ] ||
		[ ! -f "${published_file}.sha256sum" ]; then
		printf 'Failed to publish package checksums: %s\n' "${published_file}" >&2
		rm -f "${published_file}" "${published_file}.md5sum" "${published_file}.sha256sum"
		return 1
	fi
}

# These globs intentionally remove every superseded package and sidecar.
rm -f tzdata-*-aarch64.pkg.tar.bz2 tzdata-*-aarch64.pkg.tar.bz2.md5sum tzdata-*-aarch64.pkg.tar.bz2.sha256sum
rm -f tzdata-*-arm.pkg.tar.bz2 tzdata-*-arm.pkg.tar.bz2.md5sum tzdata-*-arm.pkg.tar.bz2.sha256sum
publish_package aarch64 "${aarch64_version}"
publish_package arm "${arm_version}"

if ! grep -Eq '^[[:space:]]*TZ_DATA="tzdata-[^"]*-\$\{TZ_ARCH\}\.pkg\.tar\.bz2"$' installer; then
	printf 'Expected TZ_DATA assignment not found in installer\n' >&2
	exit 1
fi
sed -i "s/TZ_DATA=\"tzdata-[^\"]*-\${TZ_ARCH}\.pkg\.tar\.bz2\"/TZ_DATA=\"tzdata-${aarch64_version}-\${TZ_ARCH}.pkg.tar.bz2\"/" installer
if ! grep -Fq "TZ_DATA=\"tzdata-${aarch64_version}-\${TZ_ARCH}.pkg.tar.bz2\"" installer; then
	printf 'Failed to update TZ_DATA in installer\n' >&2
	exit 1
fi
sh tools/update-checksums.sh \
	installer
