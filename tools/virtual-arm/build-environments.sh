#!/bin/sh
# Build disposable native ARM guests using pinned sources and isolated Docker tools.

set -eu
export LC_ALL=C
export KBUILD_BUILD_USER=agh-validation KBUILD_BUILD_HOST=qemu
export KBUILD_BUILD_TIMESTAMP='2025-09-30 00:00:00 UTC'

# fail reports an infrastructure error without publishing acceptance metadata.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

SOURCE_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd) || exit 1
case "${1:-}" in
	armv5)
		ARCH=armv5
		KERNEL_ARCH=arm
		COMPILER=arm-linux-gnueabi-
		DEB_ARCH=armel
		# Keep the armv5 archive/package ABI contract while modeling the
		# older RT-AC68U's ARMv7 Cortex-A9 without a hard-float user ABI.
		ISA_FLAGS='-march=armv5te -mfloat-abi=soft'
		;;
	armv7)
		ARCH=armv7
		KERNEL_ARCH=arm
		COMPILER=arm-linux-gnueabihf-
		DEB_ARCH=armhf
		ISA_FLAGS='-march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=hard'
		;;
	armv8)
		ARCH=armv8
		KERNEL_ARCH=arm64
		COMPILER=aarch64-linux-gnu-
		DEB_ARCH=arm64
		ISA_FLAGS='-march=armv8-a'
		;;
	*) fail 'usage: build-environments.sh armv5|armv7|armv8 CACHE_DIR' ;;
esac
[ -n "${2:-}" ] || fail 'CACHE_DIR is required'
mkdir -p "$2" || fail 'could not create cache directory'
CACHE_DIR=$(CDPATH= cd -- "$2" && pwd) || exit 1
TARGET="${CACHE_DIR}/${ARCH}"
IMAGE="${AGH_VIRTUAL_ARM_IMAGE:-agh-virtual-arm-builder:v1}"
JOBS="${AGH_VIRTUAL_ARM_BUILD_JOBS:-2}"
case "${JOBS}" in '' | *[!0-9]* | 0) fail 'build parallelism must be a positive integer' ;; esac

if [ "${AGH_VIRTUAL_ARM_BUILD_INSIDE:-0}" != 1 ]; then
	which docker >/dev/null 2>&1 || fail 'Docker is required to build native guests'
	which curl >/dev/null 2>&1 || fail 'curl is required to fetch pinned sources'
	docker build -t "${IMAGE}" "${SOURCE_DIR}"
	mkdir -p "${CACHE_DIR}/sources"
	for source_file in linux-6.1.157.tar.gz busybox-1.25.1.tar.gz; do
		expected=$(awk -v name="${source_file}" '$2 == name { print $1 }' "${SOURCE_DIR}/sources.sha256")
		[ -n "${expected}" ] || fail "missing pinned source checksum: ${source_file}"
		if [ -f "${CACHE_DIR}/sources/${source_file}" ] &&
			[ "$(sha256sum "${CACHE_DIR}/sources/${source_file}" | awk '{print $1}')" = "${expected}" ]; then
			continue
		fi
		case "${source_file}" in
			linux-*) source_url='https://codeload.github.com/gregkh/linux/tar.gz/refs/tags/v6.1.157' ;;
			busybox-*) source_url='https://codeload.github.com/mirror/busybox/tar.gz/refs/tags/1_25_1' ;;
		esac
		temporary="${CACHE_DIR}/sources/${source_file}.$$.new"
		curl --fail --location --retry 3 --max-time 600 "${source_url}" -o "${temporary}" || {
			rm -f "${temporary}"
			fail "could not fetch ${source_file}"
		}
		if [ "$(sha256sum "${temporary}" | awk '{print $1}')" != "${expected}" ]; then
			rm -f "${temporary}"
			fail "checksum mismatch for ${source_file}"
		fi
		mv -f "${temporary}" "${CACHE_DIR}/sources/${source_file}"
	done
	exec docker run --rm --init --network none --cap-drop ALL --security-opt no-new-privileges \
		--user "$(id -u):$(id -g)" --read-only --tmpfs /tmp:rw,nosuid,nodev \
		-e AGH_VIRTUAL_ARM_BUILD_INSIDE=1 -e "AGH_VIRTUAL_ARM_BUILD_JOBS=${JOBS}" \
		-v "${SOURCE_DIR}:/src:ro" -v "${CACHE_DIR}:/cache:rw" "${IMAGE}" \
		sh /src/build-environments.sh "${ARCH}" /cache
fi

[ -f "${SOURCE_DIR}/dns-query.c" ] || fail 'the native DNS query helper source is missing'
mkdir -p "${TARGET}"
rm -f "${TARGET}/environment.json"
SOURCE_DIGEST=$(python3 "${SOURCE_DIR}/environment.py" source-digest "${SOURCE_DIR}")
printf '%s\n' "Building ${ARCH}: ${COMPILER}gcc ${ISA_FLAGS}; inputs ${SOURCE_DIGEST}"
KERNEL_SOURCE_ID=$(awk '$2 == "linux-6.1.157.tar.gz" { print $1 }' "${SOURCE_DIR}/sources.sha256")
BUSYBOX_SOURCE_ID="$(awk '$2 == "busybox-1.25.1.tar.gz" { print $1 }' "${SOURCE_DIR}/sources.sha256"):$(sha256sum "${SOURCE_DIR}/patches/busybox-modern-glibc.patch" | awk '{ print $1 }')"
if [ ! -f "${TARGET}/kernel-source/.agh-source-id" ] ||
	[ "$(cat "${TARGET}/kernel-source/.agh-source-id")" != "${KERNEL_SOURCE_ID}" ]; then
	rm -rf "${TARGET}/kernel-source" "${TARGET}/build-kernel"
	mkdir "${TARGET}/kernel-source"
	tar -xzf "${CACHE_DIR}/sources/linux-6.1.157.tar.gz" --strip-components=1 -C "${TARGET}/kernel-source"
	printf '%s\n' "${KERNEL_SOURCE_ID}" >"${TARGET}/kernel-source/.agh-source-id"
fi
mkdir -p "${TARGET}/build-kernel"
cat "${SOURCE_DIR}/configs/kernel-common.config" "${SOURCE_DIR}/configs/kernel-${ARCH}.config" >"${TARGET}/kernel.config"
make -C "${TARGET}/kernel-source" O="${TARGET}/build-kernel" ARCH="${KERNEL_ARCH}" \
	CROSS_COMPILE="${COMPILER}" KCONFIG_ALLCONFIG="${TARGET}/kernel.config" allnoconfig
for option in MMU BINFMT_ELF BLK_DEV_INITRD RD_GZIP DEVTMPFS PROC_FS SYSFS TMPFS UNIX INET IPV6 DUMMY FILE_LOCKING FUTEX SERIAL_AMBA_PL011_CONSOLE; do
	grep -qx "CONFIG_${option}=y" "${TARGET}/build-kernel/.config" || fail "kernel dropped required CONFIG_${option}"
done
case "${ARCH}" in
	armv5)
		grep -qx 'CONFIG_ARCH_VEXPRESS=y' "${TARGET}/build-kernel/.config" || fail 'RT-AC68U ARMv7 virtual board selection was dropped'
		grep -qx 'CONFIG_CPU_V7=y' "${TARGET}/build-kernel/.config" || fail 'RT-AC68U ARMv7 CPU selection was dropped'
		grep -qx 'CONFIG_MFD_VEXPRESS_SYSREG=y' "${TARGET}/build-kernel/.config" || fail 'VExpress system-register provider was dropped'
		grep -qx 'CONFIG_CLK_SP810=y' "${TARGET}/build-kernel/.config" || fail 'VExpress SP810 clock driver was dropped'
		grep -qx 'CONFIG_CLK_VEXPRESS_OSC=y' "${TARGET}/build-kernel/.config" || fail 'VExpress oscillator clock driver was dropped'
		if grep -qx 'CONFIG_VFP=y' "${TARGET}/build-kernel/.config" ||
			grep -qx 'CONFIG_NEON=y' "${TARGET}/build-kernel/.config"; then
			fail 'RT-AC68U guest unexpectedly enabled kernel VFP or NEON'
		fi
		;;
	armv7) grep -qx 'CONFIG_ARCH_VIRT=y' "${TARGET}/build-kernel/.config" || fail 'ARMv7 virtual board selection was dropped' ;;
	armv8) grep -qx 'CONFIG_ARM64=y' "${TARGET}/build-kernel/.config" || fail 'ARMv8 CPU selection was dropped' ;;
esac
if [ "${KERNEL_ARCH}" = arm ]; then
	grep -qx 'CONFIG_COMPAT_32BIT_TIME=y' "${TARGET}/build-kernel/.config" ||
		fail '32-bit guest kernel dropped legacy time/futex syscall compatibility'
fi
make -C "${TARGET}/kernel-source" O="${TARGET}/build-kernel" ARCH="${KERNEL_ARCH}" \
	CROSS_COMPILE="${COMPILER}" -j"${JOBS}" >/dev/null
case "${ARCH}" in
	armv5)
		make -C "${TARGET}/kernel-source" O="${TARGET}/build-kernel" ARCH=arm CROSS_COMPILE="${COMPILER}" vexpress-v2p-ca9.dtb
		cp "${TARGET}/build-kernel/arch/arm/boot/zImage" "${TARGET}/kernel"
		cp "${TARGET}/build-kernel/arch/arm/boot/dts/vexpress-v2p-ca9.dtb" "${TARGET}/dtb"
		;;
	armv7) cp "${TARGET}/build-kernel/arch/arm/boot/zImage" "${TARGET}/kernel" ;;
	armv8) cp "${TARGET}/build-kernel/arch/arm64/boot/Image" "${TARGET}/kernel" ;;
esac

if [ ! -f "${TARGET}/build-busybox/.agh-source-id" ] ||
	[ "$(cat "${TARGET}/build-busybox/.agh-source-id")" != "${BUSYBOX_SOURCE_ID}" ]; then
	rm -rf "${TARGET}/build-busybox"
	mkdir "${TARGET}/build-busybox"
	tar -xzf "${CACHE_DIR}/sources/busybox-1.25.1.tar.gz" --strip-components=1 -C "${TARGET}/build-busybox"
	patch -d "${TARGET}/build-busybox" -p1 <"${SOURCE_DIR}/patches/busybox-modern-glibc.patch"
	printf '%s\n' "${BUSYBOX_SOURCE_ID}" >"${TARGET}/build-busybox/.agh-source-id"
fi
cp "${SOURCE_DIR}/configs/busybox.config" "${TARGET}/busybox.config"
printf '%s\n' "CONFIG_CROSS_COMPILER_PREFIX=\"${COMPILER}\"" \
	"CONFIG_EXTRA_CFLAGS=\"${ISA_FLAGS} -include sys/sysmacros.h\"" >>"${TARGET}/busybox.config"
make -C "${TARGET}/build-busybox" KCONFIG_ALLCONFIG="${TARGET}/busybox.config" allnoconfig
for option in BUSYBOX STATIC ASH FEATURE_SH_IS_ASH SH_MATH_SUPPORT INIT NETSTAT FEATURE_NETSTAT_PRG FEATURE_IPV6 LOGGER PIDOF MOUNT UMOUNT AWK SED SLEEP SHA256SUM FEATURE_DF_FANCY FEATURE_HUMAN_READABLE FEATURE_FANCY_SLEEP; do
	grep -qx "CONFIG_${option}=y" "${TARGET}/build-busybox/.config" || fail "BusyBox dropped required CONFIG_${option}"
done
make -C "${TARGET}/build-busybox" -j"${JOBS}"
rm -rf "${TARGET}/rootfs" "${TARGET}/native-unpack"
mkdir -p "${TARGET}/rootfs" "${TARGET}/native-unpack"
make -C "${TARGET}/build-busybox" CONFIG_PREFIX="${TARGET}/rootfs" install
for package in /native-packages/"${DEB_ARCH}"/*.deb; do
	dpkg-deb -x "${package}" "${TARGET}/native-unpack"
done
for lib_dir in lib usr/lib; do
	[ ! -d "${TARGET}/native-unpack/${lib_dir}" ] || cp -a "${TARGET}/native-unpack/${lib_dir}" "${TARGET}/rootfs/$(dirname "${lib_dir}")/"
done
mkdir -p "${TARGET}/rootfs/usr/bin" "${TARGET}/rootfs/usr/sbin" "${TARGET}/rootfs/sbin" \
	"${TARGET}/rootfs/etc" "${TARGET}/rootfs/dev" "${TARGET}/rootfs/proc" "${TARGET}/rootfs/sys" \
	"${TARGET}/rootfs/tmp" "${TARGET}/rootfs/opt" "${TARGET}/rootfs/jffs"

# install_native copies one explicitly selected executable, preserving stock applets.
install_native() {
	native_name="$1"
	destination="$2"
	native_path="${TARGET}/native-unpack/${native_name}"
	[ -f "${native_path}" ] && [ ! -L "${native_path}" ] || fail "missing native executable: ${native_name}"
	readelf -h "${native_path}" >/dev/null 2>&1 || fail "native executable is not ELF: ${native_name}"
	rm -f "${TARGET}/rootfs/${destination}"
	install -m 0755 "${native_path}" "${TARGET}/rootfs/${destination}"
}
install_native usr/bin/jq usr/bin/jq
install_native usr/bin/curl usr/sbin/curl
install_native usr/sbin/dnsmasq usr/sbin/dnsmasq
install_native bin/ip usr/sbin/ip
install_native usr/bin/flock usr/bin/flock
install_native usr/bin/timeout usr/bin/timeout
install_native usr/bin/gawk usr/bin/gawk
install_native usr/bin/openssl usr/sbin/openssl
ln -sf /usr/sbin/curl "${TARGET}/rootfs/usr/bin/curl"
ln -sf /usr/sbin/ip "${TARGET}/rootfs/sbin/ip"
ln -sf /usr/sbin/openssl "${TARGET}/rootfs/usr/bin/openssl"
# Intentional splitting: compiler options are fixed above, never user-provided.
# shellcheck disable=SC2086
"${COMPILER}gcc" ${ISA_FLAGS} -static -O2 -Wall -Wextra \
	"${SOURCE_DIR}/dns-query.c" -o "${TARGET}/rootfs/usr/bin/agh-dns-query"
printf '%s\n' 'root:x:0:0:root:/root:/bin/sh' >"${TARGET}/rootfs/etc/passwd"
printf '%s\n' 'root:x:0:' >"${TARGET}/rootfs/etc/group"
printf '%s\n' 'passwd: files' 'group: files' 'hosts: files dns' >"${TARGET}/rootfs/etc/nsswitch.conf"
printf '%s\n' '127.0.0.1 localhost' '::1 localhost' >"${TARGET}/rootfs/etc/hosts"
printf '%s\n' 'nameserver 127.0.0.1' >"${TARGET}/rootfs/etc/resolv.conf"
mkdir -p "${TARGET}/rootfs/etc/ssl/certs"
cp /etc/ssl/certs/ca-certificates.crt "${TARGET}/rootfs/etc/ssl/certs/ca-certificates.crt"
chmod 1777 "${TARGET}/rootfs/tmp"
python3 "${SOURCE_DIR}/check-native-libraries.py" "${TARGET}/rootfs"
[ "$(python3 "${SOURCE_DIR}/environment.py" source-digest "${SOURCE_DIR}")" = "${SOURCE_DIGEST}" ] ||
	fail 'build sources changed during compilation; retry to publish consistent provenance'
python3 "${SOURCE_DIR}/environment.py" record "${SOURCE_DIR}" "${TARGET}" \
	"${ARCH}" "${COMPILER}" "${ISA_FLAGS}" "${DEB_ARCH}"
printf '%s\n' "PASS: ${ARCH} native environment published at ${TARGET}"
