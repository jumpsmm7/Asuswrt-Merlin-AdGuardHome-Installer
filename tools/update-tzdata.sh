#!/bin/sh
# Download and publish current signed Arch Linux ARM tzdata packages.
# POSIX /bin/sh-compatible; intended for CI validation hosts.

set -eu

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

download_package() {
	local architecture output_arch database description filename
	local upstream_file package_info package_version package_arch output_file
	architecture="$1"
	output_arch="$2"
	database="${stage_dir}/core-${architecture}.db"

	download_verified_pair "${architecture}/core/core.db" "${database}" 120

	description="$(tar --wildcards -xOf "${database}" 'tzdata-*/desc')"
	filename="$(printf '%s\n' "${description}" | awk '$0 == "%FILENAME%" { getline; print; exit }')"
	case "${filename}" in
		tzdata-*.pkg.tar.bz2|tzdata-*.pkg.tar.xz|tzdata-*.pkg.tar.zst) ;;
		*)
			printf 'Unexpected tzdata filename for %s: %s\n' "${architecture}" "${filename}" >&2
			return 1
			;;
	esac
	if [ "${filename}" != "$(basename "${filename}")" ]; then
		printf 'Filename contains path separators: %s\n' "${filename}" >&2
		return 1
	fi

	upstream_file="${stage_dir}/upstream-${architecture}.${filename##*.}"
	download_verified_pair "${architecture}/core/${filename}" "${upstream_file}" 300

	if ! package_info="$(tar -xOf "${upstream_file}" ./.PKGINFO 2>/dev/null)"; then
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
		''|*[!A-Za-z0-9._+-]*) return 1 ;;
	esac
	case "${package_arch}:${architecture}" in
		aarch64:aarch64|armv7h:armv7h|any:*) ;;
		*)
			printf 'Package architecture mismatch: %s for %s\n' "${package_arch}" "${architecture}" >&2
			return 1
			;;
	esac

	output_file="${stage_dir}/tzdata-${package_version}-${output_arch}.pkg.tar.bz2"
	case "${upstream_file}" in
		*.bz2) cp "${upstream_file}" "${output_file}" ;;
		*.xz) xz --decompress --stdout "${upstream_file}" | bzip2 -9 >"${output_file}" ;;
		*.zst) zstd --decompress --stdout "${upstream_file}" | bzip2 -9 >"${output_file}" ;;
	esac
	tar -tjf "${output_file}" >/dev/null
	if ! tar -tjf "${output_file}" |
		awk '/^\.\/usr\/share\/zoneinfo\/posix\/./ && !/\/$/ { found = 1 } END { exit !found }'; then
		printf 'Package has no usable ./usr/share/zoneinfo/posix payload: %s\n' "${filename}" >&2
		return 1
	fi
	"${PYTHON3}" - "${output_file}" <<'PY'
import posixpath
import sys
import tarfile

archive = sys.argv[1]
with tarfile.open(archive, "r:bz2") as package:
    for member in package.getmembers():
        normalized_name = posixpath.normpath(member.name)
        if member.name.startswith("/") or normalized_name == ".." or normalized_name.startswith("../"):
            raise SystemExit(f"Unsafe archive member path: {member.name}")
        if member.issym() or member.islnk():
            link_path = posixpath.normpath(posixpath.join(posixpath.dirname(normalized_name), member.linkname))
            if member.linkname.startswith("/") or link_path == ".." or link_path.startswith("../"):
                raise SystemExit(f"Unsafe archive link: {member.name} -> {member.linkname}")
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

# These globs intentionally remove every superseded package and sidecar.
rm -f tzdata-*-aarch64.pkg.tar.bz2 tzdata-*-aarch64.pkg.tar.bz2.md5sum tzdata-*-aarch64.pkg.tar.bz2.sha256sum
rm -f tzdata-*-arm.pkg.tar.bz2 tzdata-*-arm.pkg.tar.bz2.md5sum tzdata-*-arm.pkg.tar.bz2.sha256sum
if [ ! -f "${stage_dir}/tzdata-${aarch64_version}-aarch64.pkg.tar.bz2" ]; then
	printf 'aarch64 package file not found\n' >&2
	exit 1
fi
if [ ! -f "${stage_dir}/tzdata-${arm_version}-arm.pkg.tar.bz2" ]; then
	printf 'arm package file not found\n' >&2
	exit 1
fi
mv "${stage_dir}/tzdata-${aarch64_version}-aarch64.pkg.tar.bz2" .
mv "${stage_dir}/tzdata-${arm_version}-arm.pkg.tar.bz2" .

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
	"tzdata-${aarch64_version}-aarch64.pkg.tar.bz2" \
	"tzdata-${arm_version}-arm.pkg.tar.bz2" \
	installer
