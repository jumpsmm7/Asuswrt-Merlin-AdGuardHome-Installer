#!/bin/sh
# Download and publish current signed Arch Linux ARM tzdata packages.
# POSIX /bin/sh-compatible; intended for CI validation hosts.

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${0}")" && pwd)"
. "${SCRIPT_DIR}/tzdata-package-info.sh"

OUT_DIR="${1:-.}"
: "${CURL_CA_BUNDLE:?CURL_CA_BUNDLE is required}"
: "${MIRROR_HOSTS:?MIRROR_HOSTS is required}"
: "${SIGNING_KEY_FINGERPRINT:?SIGNING_KEY_FINGERPRINT is required}"
readonly HTTPS_PROTOCOLS="=https"

if [ ! -r "${CURL_CA_BUNDLE}" ]; then
	printf 'Certificate authority bundle is not readable: %s\n' "${CURL_CA_BUNDLE}" >&2
	exit 1
fi
cd "${OUT_DIR}" || exit 1

transaction_dir="${PWD}/.tzdata-update-transaction"
lock_dir="${PWD}/.tzdata-update.lock"
stage_dir=""
backup_dir="${transaction_dir}/backup"
publication_active=0
publication_complete=0
backup_retain=0

if ! mkdir "${lock_dir}" 2>/dev/null; then
	if [ -d "${lock_dir}" ] && [ ! -L "${lock_dir}" ] &&
		[ -f "${lock_dir}/pid" ] && [ ! -L "${lock_dir}/pid" ]; then
		lock_pid="$(cat "${lock_dir}/pid")"
		if ! printf '%s\n' "${lock_pid}" | grep -Eq '^[0-9]+$'; then
			lock_pid=
		fi
		if [ -n "${lock_pid}" ] && ! kill -0 "${lock_pid}" 2>/dev/null; then
			rm -rf "${lock_dir}" || exit 1
			mkdir "${lock_dir}" || exit 1
		else
			printf 'Another tzdata update or recovery is active: %s\n' "${lock_dir}" >&2
			exit 1
		fi
	else
		printf 'Unsafe tzdata update lock state: %s\n' "${lock_dir}" >&2
		exit 1
	fi
fi
printf '%s\n' "$$" >"${lock_dir}/pid" || exit 1

publication_targets_remove() {
	rm -f tzdata-*-aarch64.pkg.tar.bz2 tzdata-*-aarch64.pkg.tar.bz2.md5sum tzdata-*-aarch64.pkg.tar.bz2.sha256sum \
		tzdata-*-arm.pkg.tar.bz2 tzdata-*-arm.pkg.tar.bz2.md5sum tzdata-*-arm.pkg.tar.bz2.sha256sum \
		installer installer.md5sum installer.sha256sum
}

publication_state_valid() {
	local backup_file name presence
	[ -f "${transaction_dir}/original.list" ] || return 1
	while IFS=' ' read -r presence name; do
		case "${presence}:${name}" in
			present:tzdata-*-aarch64.pkg.tar.bz2 | present:tzdata-*-aarch64.pkg.tar.bz2.md5sum | present:tzdata-*-aarch64.pkg.tar.bz2.sha256sum | \
				present:tzdata-*-arm.pkg.tar.bz2 | present:tzdata-*-arm.pkg.tar.bz2.md5sum | present:tzdata-*-arm.pkg.tar.bz2.sha256sum | \
				present:installer | present:installer.md5sum | present:installer.sha256sum)
				[ -f "${backup_dir}/${name}" ] && [ ! -L "${backup_dir}/${name}" ] || return 1
				;;
			absent:tzdata-*-aarch64.pkg.tar.bz2 | absent:tzdata-*-aarch64.pkg.tar.bz2.md5sum | absent:tzdata-*-aarch64.pkg.tar.bz2.sha256sum | \
				absent:tzdata-*-arm.pkg.tar.bz2 | absent:tzdata-*-arm.pkg.tar.bz2.md5sum | absent:tzdata-*-arm.pkg.tar.bz2.sha256sum | \
				absent:installer | absent:installer.md5sum | absent:installer.sha256sum) continue ;;
			*) return 1 ;;
		esac
	done <"${transaction_dir}/original.list"
	for backup_file in "${backup_dir}"/*; do
		[ -e "${backup_file}" ] || continue
		[ -f "${backup_file}" ] && [ ! -L "${backup_file}" ] || return 1
		name="${backup_file##*/}"
		grep -Fqx "present ${name}" "${transaction_dir}/original.list" || return 1
	done
}

publication_rollback() {
	local backup_file rollback_status restore_stage
	rollback_status=0
	if ! publication_targets_remove; then
		printf 'Rollback could not remove every partially published file.\n' >&2
		rollback_status=1
	fi
	for backup_file in "${backup_dir}"/*; do
		[ -f "${backup_file}" ] || continue
		restore_stage=".${backup_file##*/}.tzdata-restore.$$"
		if ! cp -p "${backup_file}" "${restore_stage}" || ! mv -f "${restore_stage}" "${backup_file##*/}"; then
			rm -f "${restore_stage}" || true
			printf 'Rollback could not restore %s; backups retained at %s\n' "${backup_file##*/}" "${backup_dir}" >&2
			rollback_status=1
		fi
	done
	if [ "${rollback_status}" -ne 0 ]; then
		backup_retain=1
		return 1
	fi
	publication_active=0
	return 0
}

cleanup() {
	local status
	status="$1"
	trap - 0 HUP INT TERM
	if [ "${publication_active}" -eq 1 ] && [ "${publication_complete}" -ne 1 ]; then
		publication_rollback || status=1
	fi
	[ -z "${stage_dir}" ] || rm -rf "${stage_dir}"
	if [ "${backup_retain}" -ne 1 ]; then
		if [ "${publication_complete}" -eq 1 ] || [ "${publication_active}" -eq 0 ]; then
			rm -rf "${transaction_dir}"
		fi
		rm -f "${lock_dir}/pid" || true
		rmdir "${lock_dir}" 2>/dev/null || true
	else
		printf 'Recovery data retained at %s\n' "${transaction_dir}" >&2
	fi
	exit "${status}"
}

trap 'cleanup "$?"' 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# Recover an interrupted per-file publication before downloads or new backup
# preparation.  This is restartable process-interruption recovery; without
# filesystem fsync support it does not claim power-loss durability.
if [ -e "${transaction_dir}" ] || [ -L "${transaction_dir}" ]; then
	if [ ! -d "${transaction_dir}" ] || [ -L "${transaction_dir}" ] ||
		[ ! -f "${transaction_dir}/state" ] || [ -L "${transaction_dir}/state" ]; then
		printf 'Invalid tzdata transaction state; refusing destructive recovery: %s\n' "${transaction_dir}" >&2
		backup_retain=1
		exit 1
	fi
	case "$(cat "${transaction_dir}/state")" in
		preparing) publication_complete=0 ;;
		active)
			if [ ! -d "${backup_dir}" ] || [ -L "${backup_dir}" ] || ! publication_state_valid; then
				printf 'Invalid active tzdata recovery data: %s\n' "${transaction_dir}" >&2
				backup_retain=1
				exit 1
			fi
			publication_active=1
			if ! publication_rollback; then
				printf 'Interrupted tzdata publication recovery failed: %s\n' "${transaction_dir}" >&2
				publication_active=0
				exit 1
			fi
			;;
		committed) publication_complete=1 ;;
		*)
			printf 'Invalid tzdata transaction state value: %s\n' "${transaction_dir}/state" >&2
			backup_retain=1
			exit 1
			;;
	esac
	rm -rf "${transaction_dir}" || {
		backup_retain=1
		printf 'Could not clean completed tzdata transaction: %s\n' "${transaction_dir}" >&2
		exit 1
	}
	publication_active=0
	publication_complete=0
fi

stage_dir="$(mktemp -d "${PWD}/.tzdata-update-stage.XXXXXX")"
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
	local max_time mirror_host mirror_url output_file relative_path signature_file
	relative_path="$1"
	output_file="$2"
	max_time="$3"
	signature_file="${output_file}.sig"

	# MIRROR_HOSTS is a trusted, whitespace-separated workflow setting. Try each
	# HTTPS endpoint and authenticate every package/signature pair before use.
	for mirror_host in ${MIRROR_HOSTS}; do
		mirror_url="https://${mirror_host}"
		rm -f "${output_file}" "${signature_file}"
		printf 'Downloading %s from %s\n' "${relative_path}" "${mirror_url}"
		if curl --fail --location --silent --show-error \
			--cacert "${CURL_CA_BUNDLE}" \
			--proto "${HTTPS_PROTOCOLS}" --proto-redir "${HTTPS_PROTOCOLS}" \
			--connect-timeout 15 --max-time "${max_time}" \
			"${mirror_url}/${relative_path}" --output "${output_file}" &&
			curl --fail --location --silent --show-error \
				--cacert "${CURL_CA_BUNDLE}" \
				--proto "${HTTPS_PROTOCOLS}" --proto-redir "${HTTPS_PROTOCOLS}" \
				--connect-timeout 15 --max-time 120 \
				"${mirror_url}/${relative_path}.sig" --output "${signature_file}" &&
			verify_signature "${output_file}" "${signature_file}"; then
			return 0
		fi
		printf 'Mirror failed verification or download: %s\n' "${mirror_url}" >&2
	done

	rm -f "${output_file}" "${signature_file}"
	printf 'No mirror supplied a verified copy of %s\n' "${relative_path}" >&2
	return 1
}

discover_package_filename() {
	local architecture filename mirror_host mirror_url package_listing
	architecture="$1"
	package_listing="${stage_dir}/package-${architecture}.html"

	# Discover the filename from the same mirrors that serve the package.  The
	# public package-index pages are not a stable API and may return 404 even
	# while the repository remains available.
	for mirror_host in ${MIRROR_HOSTS}; do
		mirror_url="https://${mirror_host}"
		if ! curl --fail --location --silent --show-error \
			--cacert "${CURL_CA_BUNDLE}" \
			--proto "${HTTPS_PROTOCOLS}" --proto-redir "${HTTPS_PROTOCOLS}" \
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
			*) filename="" ;;
		esac
		printf 'No valid tzdata filename in package listing from %s\n' "${mirror_url}" >&2
	done

	printf 'Failed to discover package filename for %s from all mirrors\n' "${architecture}" >&2
	return 1
}

recompress_xz_package() {
	local decompressed_file output_file upstream_file
	upstream_file="$1"
	output_file="$2"
	decompressed_file="${output_file}.tar"

	rm -f "${decompressed_file}" "${output_file}"
	if ! xz -d -c "${upstream_file}" >"${decompressed_file}"; then
		rm -f "${decompressed_file}" "${output_file}"
		return 1
	fi
	if ! bzip2 -9 <"${decompressed_file}" >"${output_file}"; then
		rm -f "${decompressed_file}" "${output_file}"
		return 1
	fi
	rm -f "${decompressed_file}"
}

recompress_zst_package() {
	local decompressed_file output_file upstream_file
	upstream_file="$1"
	output_file="$2"
	decompressed_file="${output_file}.tar"

	rm -f "${decompressed_file}" "${output_file}"
	if ! zstd --decompress --stdout "${upstream_file}" >"${decompressed_file}"; then
		rm -f "${decompressed_file}" "${output_file}"
		return 1
	fi
	if ! bzip2 -9 <"${decompressed_file}" >"${output_file}"; then
		rm -f "${decompressed_file}" "${output_file}"
		return 1
	fi
	rm -f "${decompressed_file}"
}

# download_package downloads, validates, and repackages the timezone package for an architecture.
# The output architecture identifies the package filename and records the downloaded package version.
download_package() {
	local architecture output_arch filename
	local upstream_file package_info package_version package_arch package_arch_valid output_file
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
	if ! printf '%s\n' "${package_version}" | grep -Eq '^[A-Za-z0-9._+-]+$'; then
		return 1
	fi
	package_arch_valid=0
	case "${package_arch}:${architecture}" in
		aarch64:aarch64 | armv7h:armv7h | any:*) package_arch_valid=1 ;;
		*)
			printf 'Package architecture mismatch: %s for %s\n' "${package_arch}" "${architecture}" >&2
			return 1
			;;
	esac

	output_file="${stage_dir}/tzdata-${package_version}-${output_arch}.pkg.tar.bz2"
	case "${upstream_file}" in
		*.bz2) cp "${upstream_file}" "${output_file}" ;;
		*.xz) recompress_xz_package "${upstream_file}" "${output_file}" ;;
		*.zst) recompress_zst_package "${upstream_file}" "${output_file}" ;;
		*)
			printf 'Unsupported package compression: %s\n' "${upstream_file}" >&2
			return 1
			;;
	esac
	tar -tjf "${output_file}" >/dev/null
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

stage_package_sidecars() {
	local output_arch package_version staged_file
	output_arch="$1"
	package_version="$2"
	staged_file="${stage_dir}/tzdata-${package_version}-${output_arch}.pkg.tar.bz2"

	if [ ! -f "${staged_file}" ]; then
		printf '%s package file not found: %s\n' "${output_arch}" "${staged_file}" >&2
		return 1
	fi
	if ! tar -tjf "${staged_file}" >/dev/null; then
		printf 'Invalid bzip2 package archive: %s\n' "${staged_file}" >&2
		return 1
	fi
	if ! sh "${SCRIPT_DIR}/update-checksums.sh" "${staged_file}" ||
		[ ! -f "${staged_file}.md5sum" ] ||
		[ ! -f "${staged_file}.sha256sum" ]; then
		printf 'Failed to stage package checksums: %s\n' "${staged_file}" >&2
		return 1
	fi
}

stage_package_sidecars aarch64 "${aarch64_version}"
stage_package_sidecars arm "${arm_version}"

if ! grep -Eq '^[[:space:]]*TZ_DATA="tzdata-[^"]*-\$\{TZ_ARCH\}\.pkg\.tar\.bz2"$' installer; then
	printf 'Expected TZ_DATA assignment not found in installer\n' >&2
	exit 1
fi
cp -p installer "${stage_dir}/installer"
sed -i "s/TZ_DATA=\"tzdata-[^\"]*-\${TZ_ARCH}\.pkg\.tar\.bz2\"/TZ_DATA=\"tzdata-${aarch64_version}-\${TZ_ARCH}.pkg.tar.bz2\"/" "${stage_dir}/installer"
if ! grep -Fq "TZ_DATA=\"tzdata-${aarch64_version}-\${TZ_ARCH}.pkg.tar.bz2\"" "${stage_dir}/installer"; then
	printf 'Failed to update TZ_DATA in installer\n' >&2
	exit 1
fi
sh "${SCRIPT_DIR}/update-checksums.sh" "${stage_dir}/installer"

mkdir "${transaction_dir}" || exit 1
mkdir "${backup_dir}" || exit 1
printf '%s\n' preparing >"${transaction_dir}/state" || exit 1
: >"${transaction_dir}/original.list" || exit 1
for published_file in tzdata-*-aarch64.pkg.tar.bz2 tzdata-*-aarch64.pkg.tar.bz2.md5sum tzdata-*-aarch64.pkg.tar.bz2.sha256sum \
	tzdata-*-arm.pkg.tar.bz2 tzdata-*-arm.pkg.tar.bz2.md5sum tzdata-*-arm.pkg.tar.bz2.sha256sum \
	installer installer.md5sum installer.sha256sum; do
	[ -f "${published_file}" ] || continue
	cp -p "${published_file}" "${backup_dir}/${published_file##*/}" || exit 1
	printf 'present %s\n' "${published_file##*/}" >>"${transaction_dir}/original.list" || exit 1
done
for staged_file in \
	"${stage_dir}/tzdata-${aarch64_version}-aarch64.pkg.tar.bz2" \
	"${stage_dir}/tzdata-${aarch64_version}-aarch64.pkg.tar.bz2.md5sum" \
	"${stage_dir}/tzdata-${aarch64_version}-aarch64.pkg.tar.bz2.sha256sum" \
	"${stage_dir}/tzdata-${arm_version}-arm.pkg.tar.bz2" \
	"${stage_dir}/tzdata-${arm_version}-arm.pkg.tar.bz2.md5sum" \
	"${stage_dir}/tzdata-${arm_version}-arm.pkg.tar.bz2.sha256sum" \
	"${stage_dir}/installer" "${stage_dir}/installer.md5sum" "${stage_dir}/installer.sha256sum"; do
	published_file="${staged_file##*/}"
	[ -e "${published_file}" ] || printf 'absent %s\n' "${published_file}" >>"${transaction_dir}/original.list" || exit 1
done

printf '%s\n' active >"${transaction_dir}/state.tmp" || exit 1
mv -f "${transaction_dir}/state.tmp" "${transaction_dir}/state" || exit 1
publication_active=1
publication_targets_remove
for staged_file in \
	"${stage_dir}/tzdata-${aarch64_version}-aarch64.pkg.tar.bz2" \
	"${stage_dir}/tzdata-${aarch64_version}-aarch64.pkg.tar.bz2.md5sum" \
	"${stage_dir}/tzdata-${aarch64_version}-aarch64.pkg.tar.bz2.sha256sum" \
	"${stage_dir}/tzdata-${arm_version}-arm.pkg.tar.bz2" \
	"${stage_dir}/tzdata-${arm_version}-arm.pkg.tar.bz2.md5sum" \
	"${stage_dir}/tzdata-${arm_version}-arm.pkg.tar.bz2.sha256sum" \
	"${stage_dir}/installer" "${stage_dir}/installer.md5sum" "${stage_dir}/installer.sha256sum"; do
	mv -f "${staged_file}" "${staged_file##*/}" || exit 1
done
printf '%s\n' committed >"${transaction_dir}/state.tmp" || exit 1
mv -f "${transaction_dir}/state.tmp" "${transaction_dir}/state" || exit 1
publication_complete=1
publication_active=0
