#!/bin/sh
# PID 1 prepares kernel-backed guest state before running the selected scenarios.
export LC_ALL=C
export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin

mount -t proc proc /proc || exit 1
mount -t sysfs sysfs /sys || exit 1
mount -t devtmpfs devtmpfs /dev || exit 1
mkdir -p /dev/pts /tmp /jffs /opt /rom /run
mount -t devpts devpts /dev/pts || exit 1
mount -t tmpfs -o mode=1777 tmpfs /tmp || exit 1
# Model Entware storage on a separate, bounded ephemeral mount.
mount -t tmpfs -o mode=0755,size=96m tmpfs /opt || exit 1
# The modeled ROM resolver uses block accounting understood by stock df.
mount -t tmpfs -o mode=0755,size=1m tmpfs /rom || exit 1
mount --bind /repo /repo || exit 1
mount -o remount,bind,ro /repo || exit 1
/usr/sbin/ip link set lo up || exit 1
# shellcheck disable=SC1091
. /etc/agh-virtual-arm.conf
printf '%s\n' "${ARCHITECTURE}" >/run/virtual-arm-guest || exit 1

# BusyBox init reaps daemon/monitor children orphaned by lifecycle scenarios.
exec /bin/busybox init
