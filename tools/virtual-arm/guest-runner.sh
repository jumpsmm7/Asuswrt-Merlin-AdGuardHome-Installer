#!/bin/sh
# Execute each declared scenario with native ARM tools and emit token-bound results.
set -u
export LC_ALL=C
export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin
# shellcheck disable=SC1091
. /etc/agh-virtual-arm.conf

# marker keeps trusted result records distinguishable from scenario diagnostics.
marker() {
	printf 'AGH_VM\t%s\t' "${RUN_TOKEN}"
	printf '%s\t' "$@"
	printf '\n'
}

cd /repo || exit 1
# smoke_tool rejects native loader/ISA/tool failures before reporting a healthy boot.
smoke_tool() {
	local name result
	name="$1"
	shift
	"$@" >/tmp/agh-native-tool.log 2>&1
	result="$?"
	if [ "${result}" -ne 0 ]; then
		cat /tmp/agh-native-tool.log
		marker ERROR "${name}" "${result}"
		exit 1
	fi
	printf 'NATIVE_TOOL\t%s\t%s\n' "${name}" "$(sed -n '1p' /tmp/agh-native-tool.log)"
}
smoke_tool busybox /bin/busybox
# BusyBox 1.25.1 has the POSIX -P form but not the optional -h formatter.
smoke_tool df /bin/df -P
smoke_tool sleep /bin/sleep 0s
if /bin/sleep 0.5 >/tmp/agh-native-tool.log 2>&1; then
	marker ERROR fractional-sleep-accepted 0
	exit 1
fi
smoke_tool jq /usr/bin/jq --version
smoke_tool curl /usr/sbin/curl --version
smoke_tool dnsmasq /usr/sbin/dnsmasq --version
smoke_tool ip /usr/sbin/ip -Version
smoke_tool flock /usr/bin/flock --version
smoke_tool timeout /usr/bin/timeout --version
smoke_tool gawk /usr/bin/gawk --version
smoke_tool openssl /usr/sbin/openssl version
rm -f /tmp/agh-native-tool.log
# Verify the CPU contract from inside the real ARM kernel before any fixture
# can report success.  The armv5 product archive is intentionally exercised
# as an older ARMv7 software-float target, not as an ARMv5 CPU target.
CPU_FEATURES="$(awk -F: '$1 ~ /^Features[[:space:]]*$/ { print $2 }' /proc/cpuinfo)"
case "${ARCHITECTURE}" in
	armv5)
		[ "$(uname -m)" = armv7l ] || {
			marker ERROR cpu-architecture 1
			exit 1
		}
		[ -n "${CPU_FEATURES}" ] || {
			marker ERROR cpu-features-missing 1
			exit 1
		}
		if printf '%s\n' "${CPU_FEATURES}" | grep -Eq '(^|[[:space:]])(vfp[^[:space:]]*|neon)([[:space:]]|$)'; then
			marker ERROR software-float-cpu-exposes-fpu 1
			exit 1
		fi
		;;
	armv7)
		case " ${CPU_FEATURES} " in
			*' vfp'*' neon '* | *' neon '*' vfp'*) ;;
			*)
				marker ERROR hard-float-cpu-missing-fpu 1
				exit 1
				;;
		esac
		;;
esac
BUSYBOX_VERSION="$(/bin/busybox 2>&1 | sed -n '1s/^BusyBox \([^ ]*\).*/\1/p')"
# Record the guest kernel's native feature line.  The RT-AC68U-class armv5
# environment must prove that VFP/NEON are absent, not merely compile its
# userland with a soft-float ABI.
CPU_FEATURES="$(awk -F: '$1 ~ /^[[:space:]]*Features[[:space:]]*$/ { print $2; exit }' /proc/cpuinfo | tr -s ' ' | sed 's/^ *//; s/ *$//')"
marker BOOT "${ARCHITECTURE}" "$(uname -m)" "$(uname -r)" "${BUSYBOX_VERSION}" "${ENVIRONMENT_DIGEST}" "${CPU_FEATURES:-none}"
FAILED=0
TAB="$(printf '\t')"
while IFS="${TAB}" read -r feature scenario test_path; do
	[ -n "${feature}" ] || continue
	START="$(date +%s)"
	marker START "${feature}" "${scenario}"
	LOG="/tmp/agh-virtual-${scenario}.log"
	if [ "${test_path}" = tests/virtual-arm-native.sh ]; then
		/usr/bin/timeout --signal=TERM --kill-after=10 "${SCENARIO_TIMEOUT_SECONDS}" /bin/sh "${test_path}" "${ARCHITECTURE}" >"${LOG}" 2>&1
		RESULT="$?"
	else
		/usr/bin/timeout --signal=TERM --kill-after=10 "${SCENARIO_TIMEOUT_SECONDS}" /bin/sh "${test_path}" >"${LOG}" 2>&1
		RESULT="$?"
	fi
	cat "${LOG}"
	rm -f "${LOG}"
	[ "${RESULT}" -eq 0 ] || FAILED=1
	marker END "${feature}" "${scenario}" "${RESULT}" "$(($(date +%s) - START))"
done </etc/agh-virtual-arm-selection.tsv
marker DONE "${FAILED}"
sync
reboot -f
# Stay in PID 1 if the virtual board has no reboot handler; the host stops on DONE.
while :; do sleep 60; done
