#!/bin/sh

SCRIPT_LOC="$(readlink -f "$0")"
CONF_FILE="/opt/etc/AdGuardHome/.config"
MID_SCRIPT="/jffs/addons/AdGuardHome.d/AdGuardHome.sh"
UPPER_SCRIPT="/opt/etc/init.d/S99AdGuardHome"
LOWER_SCRIPT="/opt/etc/init.d/rc.func.AdGuardHome"
IPSET_FILE="/jffs/addons/AdGuardHome.d/ipset.conf"
IPSET_LEGACY_MANAGED_FILE="/jffs/addons/AdGuardHome.d/ipset.dnsmasq.conf"
IPSET_MANAGED_FILE="/jffs/addons/AdGuardHome.d/ipset.sources.conf"
IPSET_SOURCE="/jffs/configs/dnsmasq.conf.add"
IPSET_X3M_SOURCE="/jffs/scripts/nat-start"
IPSET_DVR_DIR="/jffs/configs/domain_vpn_routing"
IPSET_WGM_DATABASE="/opt/etc/wireguard.d/WireGuard.db"
IPSET_WGM_DOMAIN_DIR="/opt/etc/wireguard.d/ipset.d"

NAME="$(basename "$0")[$$]"

# Functions are grouped by purpose; names are sorted alpha-numerically within each group.

# Core helpers

conf_value() {
	[ -f "${CONF_FILE}" ] || return 1
	awk -v KEY="$1" '
		index($0, KEY "=") == 1 {
			VALUE = substr($0, length(KEY) + 2)
			gsub(/^"|"$/, "", VALUE)
			print VALUE
			exit
		}
	' "${CONF_FILE}"
}

have_cmd() {
	which "$1" >/dev/null 2>&1
}

trap_state_cleanup_stale() {
	local current_start encoded_owner owner owner_start trap_dir trap_name
	for trap_dir in /tmp/AdGuardHome-traps-*; do
		[ -d "${trap_dir}" ] || continue
		owner="$(sed -n '1p' "${trap_dir}/owner" 2>/dev/null)"
		owner_start="$(sed -n '2p' "${trap_dir}/owner" 2>/dev/null)"
		case "${owner}" in
			"" | *[!0-9]*)
				trap_name="${trap_dir##*/AdGuardHome-traps-}"
				encoded_owner="${trap_name%-*}"
				encoded_owner="${encoded_owner##*.}"
				case "${encoded_owner}" in
					"" | *[!0-9]*)
						trap_state_remove "${trap_dir}/state"
						continue
						;;
				esac
				owner="${encoded_owner}"
				;;
		esac
		if ! kill -0 "${owner}" 2>/dev/null; then
			trap_state_remove "${trap_dir}/state"
			continue
		fi
		if [ -n "${owner_start}" ]; then
			current_start="$(trap_state_process_start "${owner}")"
			if [ -z "${current_start}" ] || [ "${current_start}" != "${owner_start}" ]; then
				trap_state_remove "${trap_dir}/state"
			fi
		fi
	done
}

trap_state_create() {
	local attempt owner_start scope trap_dir trap_file
	scope="$1"
	case "${scope}" in
		"" | *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-]*) return 1 ;;
	esac
	trap_state_cleanup_stale
	owner_start="$(trap_state_process_start "$$")"
	attempt="0"
	while [ "${attempt}" -lt 16 ]; do
		trap_dir="/tmp/AdGuardHome-traps-${scope}.$$-${attempt}"
		trap_file="${trap_dir}/state"
		if mkdir "${trap_dir}" 2>/dev/null; then
			if ! printf '%s\n%s\n' "$$" "${owner_start}" >"${trap_dir}/owner"; then
				trap_state_remove "${trap_file}"
				return 1
			fi
			printf '%s\n' "${trap_file}"
			return 0
		fi
		attempt="$((attempt + 1))"
	done
	return 1
}

trap_state_process_start() {
	local field pid proc_stat
	pid="$1"
	case "${pid}" in
		"" | *[!0-9]*) return 1 ;;
	esac
	IFS= read -r proc_stat <"/proc/${pid}/stat" 2>/dev/null || return 1
	proc_stat="${proc_stat##*) }"
	field="1"
	set -- ${proc_stat}
	while [ "${field}" -lt 20 ]; do
		[ "$#" -gt 0 ] || return 1
		shift
		field="$((field + 1))"
	done
	case "${1:-}" in
		"" | *[!0-9]*) return 1 ;;
	esac
	printf '%s\n' "$1"
}

trap_state_remove() {
	local trap_dir trap_file
	trap_file="$1"
	[ -n "${trap_file}" ] || return 0
	trap_dir="${trap_file%/*}"
	case "${trap_dir}" in
		/tmp/AdGuardHome-traps-*) rm -rf "${trap_dir}" ;;
	esac
}

trap_state_restore() {
	local trap_file
	trap_file="$1"
	trap - EXIT HUP INT QUIT ABRT USR1 USR2 TERM TSTP
	[ -s "${trap_file}" ] && { . "${trap_file}"; };
	trap_state_remove "${trap_file}"
}

trap_state_save() {
	local trap_file
	trap_file="$1"
	[ -n "${trap_file}" ] || return 1
	trap >"${trap_file}" || {
		trap_state_remove "${trap_file}"
		return 1
	}
}

nvram_int_gt() {
	local VALUE MIN
	VALUE="$(nvram get "$1" 2>/dev/null)"
	MIN="$2"
	case "${VALUE}" in
		"" | *[!0-9]*)
			return 1
			;;
	esac
	[ "${VALUE}" -gt "${MIN}" ]
}

# HTTP/download helpers

curl_common_args() {
	if [ -z "${CURL_COMMON_ARGS_SET:-}" ]; then
		CURL_COMMON_ARGS=""
		curl_has_option '--retry' && CURL_COMMON_ARGS="${CURL_COMMON_ARGS} --retry 5"
		curl_has_option '--connect-timeout' && CURL_COMMON_ARGS="${CURL_COMMON_ARGS} --connect-timeout 25"
		curl_has_option '--retry-delay' && CURL_COMMON_ARGS="${CURL_COMMON_ARGS} --retry-delay 5"
		curl_has_option '--max-time' && CURL_COMMON_ARGS="${CURL_COMMON_ARGS} --max-time $((5 * 25))"
		curl_has_option '--retry-connrefused' && CURL_COMMON_ARGS="${CURL_COMMON_ARGS} --retry-connrefused"
		CURL_COMMON_ARGS_SET="1"
	fi
	printf '%s' "${CURL_COMMON_ARGS}"
}

curl_has_option() {
	curl_help | grep -q -e "$1"
}

curl_help() {
	if [ -z "${CURL_HELP_CACHE_SET:-}" ]; then
		CURL_HELP_CACHE="$(curl --help all 2>&1 || curl --help 2>&1)"
		CURL_HELP_CACHE_SET="1"
	fi
	printf '%s\n' "${CURL_HELP_CACHE}"
}

http_probe() {
	local URL CURL_ARGS WGET_ARGS
	URL="$1"
	if have_cmd curl; then
		CURL_ARGS="$(curl_common_args)"
		curl ${CURL_ARGS} -f -sL -I -o /dev/null "${URL}"
	elif have_cmd wget; then
		WGET_ARGS="$(wget_common_args)"
		if wget_has_option '--spider'; then
			wget ${WGET_ARGS} -q --spider "${URL}"
		else
			wget ${WGET_ARGS} -q -O /dev/null "${URL}"
		fi
	else
		return 127
	fi
}

wget_common_args() {
	if [ -z "${WGET_COMMON_ARGS_SET:-}" ]; then
		WGET_COMMON_ARGS=""
		wget_has_option '--no-cache' && WGET_COMMON_ARGS="${WGET_COMMON_ARGS} --no-cache"
		wget_has_option '--no-cookies' && WGET_COMMON_ARGS="${WGET_COMMON_ARGS} --no-cookies"
		wget_has_option '--tries' && WGET_COMMON_ARGS="${WGET_COMMON_ARGS} --tries=5"
		wget_has_option '--timeout' && WGET_COMMON_ARGS="${WGET_COMMON_ARGS} --timeout=25"
		wget_has_option '--waitretry' && WGET_COMMON_ARGS="${WGET_COMMON_ARGS} --waitretry=5"
		wget_has_option '--retry-connrefused' && WGET_COMMON_ARGS="${WGET_COMMON_ARGS} --retry-connrefused"
		WGET_COMMON_ARGS_SET="1"
	fi
	printf '%s' "${WGET_COMMON_ARGS}"
}

wget_has_option() {
	wget_help | grep -q -e "$1"
}

wget_help() {
	if [ -z "${WGET_HELP_CACHE_SET:-}" ]; then
		WGET_HELP_CACHE="$(wget --help 2>&1)"
		WGET_HELP_CACHE_SET="1"
	fi
	printf '%s\n' "${WGET_HELP_CACHE}"
}

# Run-lock helpers

adguardhome_run() {
	local lock_dir owner pid_file runtime
	lock_dir="/tmp/AdGuardHome"
	pid_file="${lock_dir}/pid"
	case "$1" in
		"")
			if have_cmd flock && flock_supports_fd; then
				if adguardhome_run_flock_active; then return 1; else return 0; fi
			fi
			owner="$(sed -n '1p' "${pid_file}" 2>/dev/null)"
			runtime="$(sed -n '2p' "${pid_file}" 2>/dev/null)"
			[ -z "${runtime}" ] && return 1
			case "${owner}" in
				"" | *[!0-9]*)
					rm -f "${pid_file}"
					return 1
					;;
			esac
			if kill -0 "${owner}" 2>/dev/null; then return 0; fi
			rm -f "${pid_file}"
			return 1
			;;
		*)
			if have_cmd flock && flock_supports_fd; then
				adguardhome_run_flock "$1"
			else
				adguardhome_run_mkdir "$1"
			fi
			;;
	esac
}

adguardhome_run_execute() {
	local action end owner pid_file runtime start status
	action="$1"
	pid_file="$2"
	owner="${3:-$$}"
	printf "%s\n" "${owner}" >"${pid_file}"
	start="$(date +%s)"
	service_wait "${action}" 30
	status="$?"
	end="$(date +%s)"
	runtime="$((end - start))"
	printf "%s\n" "${runtime}" >>"${pid_file}"
	if [ "${status}" -eq 0 ]; then
		logger -st "${NAME}" "${action} took ${runtime} second(s) to complete."
	else
		logger -st "${NAME}" "Warning: ${action} did not complete within ${runtime} second(s)."
	fi
	return "${status}"
}

adguardhome_run_flock() {
	local action lock_dir lock_file owner pid_file status trap_file
	action="$1"
	lock_dir="/tmp/AdGuardHome"
	lock_file="${lock_dir}.lock"
	pid_file="${lock_dir}/pid"
	if adguardhome_run_legacy_mkdir_active; then
		owner="$(sed -n '1p' "${pid_file}" 2>/dev/null)"
		logger -st "${NAME}" "Legacy mkdir lock owned by ${owner:-unknown} exists; preventing duplicate runs!"
		return 1
	fi
	if ! mkdir -p "${lock_dir}"; then
		logger -st "${NAME}" "Unable to create ${lock_dir}; cannot run ${action}."
		return 1
	fi
	exec 9>"${lock_file}" || return 1
	if [ "${action}" = "stop_adguardhome" ]; then
		if ! flock 9; then
			logger -st "${NAME}" "Unable to acquire flock for ${action}."
			exec 9>&-
			return 1
		fi
	elif ! flock -n 9; then
		owner="$(sed -n '1p' "${pid_file}" 2>/dev/null)"
		logger -st "${NAME}" "Lock owned by ${owner:-unknown} exists; preventing duplicate runs!"
		exec 9>&-
		return 1
	fi
	trap_file="$(trap_state_create run-flock)" || {
		adguardhome_run_flock_cleanup "${pid_file}"
		return 1
	}
	# Capture traps in the current shell. Command substitution would run `trap`
	# in a subshell and return no trap state in BusyBox ash and dash.
	trap_state_save "${trap_file}" || {
		adguardhome_run_flock_cleanup "${pid_file}"
		return 1
	}
	trap 'adguardhome_run_flock_cleanup "${pid_file}"; trap_state_restore "${trap_file}"; exit 1' HUP INT QUIT ABRT TERM TSTP
	trap 'status="$?"; adguardhome_run_flock_cleanup "${pid_file}"; trap_state_restore "${trap_file}"; exit "${status}"' EXIT
	rm -f "${pid_file}"
	adguardhome_run_execute "${action}" "${pid_file}" "$$"
	status="$?"
	adguardhome_run_flock_cleanup "${pid_file}"
	trap_state_restore "${trap_file}"
	return "${status}"
}

adguardhome_run_flock_active() {
	local lock_dir lock_file status
	lock_dir="/tmp/AdGuardHome"
	lock_file="${lock_dir}.lock"
	if adguardhome_run_legacy_mkdir_active; then return 0; fi
	exec 9>"${lock_file}" || return 1
	flock -n 9 >/dev/null 2>&1
	status="$?"
	if [ "${status}" -eq 0 ]; then
		flock -u 9 >/dev/null 2>&1
		exec 9>&-
		return 1
	fi
	exec 9>&-
	return 0
}

adguardhome_run_flock_cleanup() {
	local pid_file
	pid_file="$1"
	[ -n "${pid_file}" ] && rm -f "${pid_file}"
	flock -u 9 >/dev/null 2>&1
	exec 9>&-
}

adguardhome_run_legacy_mkdir_active() {
	local lock_dir owner pid_file runtime
	lock_dir="/tmp/AdGuardHome"
	pid_file="${lock_dir}/pid"
	[ -d "${lock_dir}" ] || return 1
	runtime="$(sed -n '2p' "${pid_file}" 2>/dev/null)"
	[ -z "${runtime}" ] || return 1
	owner="$(sed -n '1p' "${pid_file}" 2>/dev/null)"
	case "${owner}" in
		"" | *[!0-9]*)
			return 1
			;;
	esac
	kill -0 "${owner}" 2>/dev/null
}

adguardhome_run_mkdir() {
	local action lock_dir pid pid_file status trap_file
	action="$1"
	lock_dir="/tmp/AdGuardHome"
	pid_file="${lock_dir}/pid"
	if (mkdir "${lock_dir}") 2>/dev/null || { [ -e "${pid_file}" ] && [ -n "$(sed -n '2p' "${pid_file}" 2>/dev/null)" ]; } || { [ "${action}" = "stop_adguardhome" ]; }; then
		(
			trap_file="$(trap_state_create run-mkdir)" || {
				rm -rf "${lock_dir}"
				exit 1
			}
			trap_state_save "${trap_file}" || {
				rm -rf "${lock_dir}"
				exit 1
			}
			trap 'status="$?"; rm -rf "${lock_dir}"; trap_state_restore "${trap_file}"; exit "${status}"' EXIT
			{ service_wait adguardhome_run; }
			rm -rf "${lock_dir}"
		) &
		pid="$!"
		adguardhome_run_execute "${action}" "${pid_file}" "${pid}"
		status="$?"
		return "${status}"
	fi
	logger -st "${NAME}" "Lock owned by $(sed -n '1p' "${pid_file}" 2>/dev/null) exists; preventing duplicate runs!"
	return 1
}

flock_supports_fd() {
	local TEST_LOCK status
	TEST_LOCK="/tmp/adguardhome-flock-test.$$"
	(
		: >"${TEST_LOCK}" || exit 1
		exec 8>"${TEST_LOCK}" || exit 1
		flock -n 8 >/dev/null 2>&1
	)
	status="$?"
	rm -f "${TEST_LOCK}"
	return "${status}"
}

# DNS and network helpers

check_dns_environment() {
	local MODE NVCHECK
	dns_env_set_nvram() {
		local key expected cur changed
		key="$1"
		expected="$2"
		cur="$(nvram get "${key}" 2>/dev/null)"
		if [ "${cur}" = "${expected}" ]; then
			return 1
		fi
		nvram set "${key}=${expected}"
		changed="1"
		return 0
	}
	dns_env_apply_profile() {
		local changed
		changed="0"
		if dns_env_set_nvram "dnspriv_enable" "0"; then changed="$((changed + 1))"; fi
		if dns_env_set_nvram "dhcpd_dns_router" "1"; then changed="$((changed + 1))"; fi
		if dns_env_set_nvram "dhcp_dns1_x" ""; then changed="$((changed + 1))"; fi
		if dns_env_set_nvram "dhcp_dns2_x" ""; then changed="$((changed + 1))"; fi
		if [ "${changed}" != "0" ]; then return 0; else return 1; fi
	}
	dns_env_restore_profile() {
		local changed key cur old
		changed="0"
		for key in dnspriv_enable dhcpd_dns_router dhcp_dns1_x dhcp_dns2_x; do
			cur="$(nvram get "${key}" 2>/dev/null)"
			case "${key}" in
				dnspriv_enable) old="${_OLD_dnspriv_enable}" ;;
				dhcpd_dns_router) old="${_OLD_dhcpd_dns_router}" ;;
				dhcp_dns1_x) old="${_OLD_dhcp_dns1_x}" ;;
				dhcp_dns2_x) old="${_OLD_dhcp_dns2_x}" ;;
			esac
			if [ "${cur}" != "${old}" ]; then
				nvram set "${key}=${old}"
				changed="$((changed + 1))"
			fi
		done
		if [ "${changed}" != "0" ]; then return 0; else return 1; fi
	}
	MODE="$1"
	NVCHECK="0"
	case "${MODE}" in
		running)
			# Save original values only once.
			if [ "${_DNS_NVRAM_SAVED:-0}" != "1" ]; then
				save_dns_nvram_environment
			fi
			if [ "$(pidof stubby | wc -w)" -gt "0" ]; then
				{ killall -q -9 stubby 2>/dev/null; }
				NVCHECK="$((NVCHECK + 1))"
			fi
			if dns_env_apply_profile; then NVCHECK="$((NVCHECK + 1))"; fi
			;;
		stop)
			# Do not restore if we never saved anything.
			if [ "${_DNS_NVRAM_SAVED:-0}" != "1" ]; then
				return 0
			fi
			if dns_env_restore_profile; then NVCHECK="$((NVCHECK + 1))"; fi
			;;
		*)
			logger -st "${NAME:-dns-manager}" "Invalid DNS environment mode: ${MODE}"
			return 0
			;;
	esac
	if [ "$NVCHECK" != "0" ]; then
		{ nvram commit; }
		{ service restart_dnsmasq >/dev/null 2>&1; }
		{ service_wait netcheck 150; }
	fi
	return 0
}

dnsmasq_delete_matching() {
	local CONFIG PATTERN SED_SCRIPT
	CONFIG="$1"
	shift
	SED_SCRIPT=""
	for PATTERN in "$@"; do
		SED_SCRIPT="${SED_SCRIPT}/^${PATTERN}.*$/d;"
	done
	[ -n "${SED_SCRIPT}" ] || return 0
	sed -i "${SED_SCRIPT}" "${CONFIG}"
}

dnsmasq_params() {
	local CONFIG IPV6_REVERSE NET_ADDR NET_ADDR6 LAN_IF LAN_IF_SDN NIVARS NDVARS RC_SUPPORT DHCP_IF
	if ! resolv_conf_uses_rom && resolv_conf_is_tmp_mount; then
		umount /tmp/resolv.conf 2>/dev/null
	fi
	IPSet_Sync_Restart
	case "$(pidof "${PROCS}" 2>/dev/null | wc -w)" in
		0)
			return 0
			;;
		*)
			:
			;;
	esac
	RC_SUPPORT="$(nvram get rc_support 2>/dev/null)"
	LAN_IF="$(nvram get lan_ifname 2>/dev/null)"
	case "${1:-}" in
		"")
			CONFIG="/etc/dnsmasq.conf"
			DHCP_IF="lan"
			if [ -n "${LAN_IF}" ]; then
				NET_ADDR="$(interface_ipv4_addr "${LAN_IF}")"
				NET_ADDR6="$(interface_ipv6_addr "${LAN_IF}")"
			fi
			[ -n "${NET_ADDR}" ] || NET_ADDR="$(nvram get lan_ipaddr 2>/dev/null)"
			[ -n "${NET_ADDR6}" ] || NET_ADDR6="$(nvram get ipv6_rtr_addr 2>/dev/null)"
			[ -n "${NET_ADDR}" ] || return 0
			;;

		*)
			case "${RC_SUPPORT}" in
				*mtlancfg*)
					:
					;;
				*)
					return 0
					;;
			esac
			CONFIG="/etc/dnsmasq-${1}.conf"
			if [ -n "${LAN_IF}" ]; then
				LAN_IF_SDN="$(sdn_bridge_for_index "$1" | grep -vxF "${LAN_IF}")"
			else
				LAN_IF_SDN="$(sdn_bridge_for_index "$1")"
			fi
			[ -n "${LAN_IF_SDN}" ] || return 0
			DHCP_IF="${LAN_IF_SDN}"
			NET_ADDR="$(interface_ipv4_addr "${LAN_IF_SDN}")"
			NET_ADDR6="$(interface_ipv6_addr "${LAN_IF_SDN}")"
			[ -n "${NET_ADDR}" ] || return 0
			;;
	esac
	dnsmasq_delete_matching \
		"${CONFIG}" \
		"add-subnet=" \
		"port=" \
		"add-mac" \
		"dhcp-option=${DHCP_IF},6"
	printf "%s\n" \
		"dhcp-option=${DHCP_IF},6,${NET_ADDR}" \
		"local=/$(ipv4_reverse_zone "${NET_ADDR}")/" \
		"local=/10.in-addr.arpa/" \
		"local=//" \
		"port=553" \
		"add-mac" >>"${CONFIG}"
	if [ -n "${NET_ADDR6}" ]; then
		IPV6_REVERSE="$(ipv6_reverse_zone "${NET_ADDR6}")"
		printf "%s\n" \
			"add-subnet=32,128" \
			"local=/${IPV6_REVERSE}/" >>"${CONFIG}"
	else
		printf "%s\n" "add-subnet=32" >>"${CONFIG}"
	fi
	case "${1:-}:${RC_SUPPORT}" in
		:*mtlancfg*)
			:
			;;
		:*)
			private_ipv4_bridge_dns_options_with_fallbacks | while read -r NIVARS NDVARS; do
				[ -n "${NIVARS}" ] && [ -n "${NDVARS}" ] || continue
				printf "%s\n" "dhcp-option=${NIVARS},6,${NDVARS}" >>"${CONFIG}"
			done
			;;
	esac
	if ! resolv_conf_uses_rom && [ "$(conf_value ADGUARD_LOCAL)" = "YES" ]; then
		mount -o bind /rom/etc/resolv.conf /tmp/resolv.conf
	fi
}

interface_ipv4_addr() {
	local IFACE
	IFACE="$1"
	[ -n "${IFACE}" ] || return 1
	have_cmd ip || return 1
	ip -o -4 addr list "${IFACE}" 2>/dev/null | awk 'NR==1{ split($4, ip_addr, "/"); print ip_addr[1]; exit }'
}

interface_ipv6_addr() {
	local IFACE
	IFACE="$1"
	[ -n "${IFACE}" ] || return 1
	have_cmd ip || return 1
	ip -o -6 addr list "${IFACE}" scope global 2>/dev/null | awk 'NR==1{ split($4, ip_addr, "/"); print ip_addr[1]; exit }'
}

ipv4_reverse_zone() {
	printf "%s\n" "$1" | awk 'BEGIN{FS="."}{print $2"."$1".in-addr.arpa"}'
}

ipv6_reverse_zone() {
	printf "%s\n" "$1" | sed 's/.$//' | awk -F: '{for(i=1;i<=NF;i++)x=x""sprintf (":%4s", $i);gsub(/ /,"0",x);print x}' | cut -c 2- | cut -c 1-20 | sed 's/://g;s/^.*$/\n&\n/;tx;:x;s/\(\n.\)\(.*\)\(.\n\)/\3\2\1/;tx;s/\n//g;s/\(.\)/\1./g;s/$/ip6.arpa/'
}

netcheck() {
	local livecheck="0" i timewait
	timewait="0"
	until system_time_ready; do
		if [ "${timewait}" -ge "300" ]; then
			logger -st "${NAME}" "Warning: timed out waiting for system time readiness."
			return 1
		fi
		sleep 1s
		timewait="$((timewait + 1))"
	done
	while [ "${livecheck}" != "4" ]; do
		for i in google.com github.com snbforums.com; do
			if { ! nslookup "${i}" 127.0.0.1 >/dev/null 2>&1; } && { ping -q -w3 -c1 "${i}" >/dev/null 2>&1; }; then
				if ! http_probe "http://${i}" >/dev/null 2>&1; then
					sleep 1s
					continue
				fi
			fi
			return 0
		done
		livecheck="$((livecheck + 1))"
		if [ "${livecheck}" != "4" ]; then
			sleep 10s
			continue
		fi
		return 1
	done
}

private_ipv4_bridge_dns_options() {
	if have_cmd ip; then
		ip -o -4 addr show scope global 2>/dev/null | awk '
			function private_ip(ip) {
				return ip ~ /^(10|127)\./ || ip ~ /^192\.168\./ || ip ~ /^172\.(1[6-9]|2[0-9]|3[0-1])\./
			}
			$2 ~ /^br/ && $2 != "br0" {
				for (i = 1; i <= NF; i++) {
					if ($i == "inet") {
						split($(i + 1), ip_addr, "/")
						if (private_ip(ip_addr[1]) && !seen[$2]++) { print $2 " " ip_addr[1] }
					}
				}
			}
		'
		return
	fi
	return 1
}

private_ipv4_bridge_dns_options_with_fallbacks() {
	local OPTIONS
	OPTIONS="$(private_ipv4_bridge_dns_options)"
	if [ -z "${OPTIONS}" ]; then
		OPTIONS="$(private_ipv4_route_dns_options)"
	fi
	if [ -z "${OPTIONS}" ]; then
		OPTIONS="$(private_ipv4_legacy_route_dns_options)"
	fi
	printf "%s\n" "${OPTIONS}"
}

private_ipv4_legacy_route_dns_options() {
	have_cmd route || return 1
	route 2>/dev/null | awk '
		function private_ip(ip) {
			return ip ~ /^(10|127)\./ || ip ~ /^192\.168\./ || ip ~ /^172\.(1[6-9]|2[0-9]|3[0-1])\./
		}
		function router_ip(ip) {
			split(ip, octets, ".")
			if (octets[1] != "" && octets[2] != "" && octets[3] != "") { return octets[1] "." octets[2] "." octets[3] ".1" }
			return ""
		}
		{
			iface = $NF
			if (iface ~ /^br/ && iface != "br0" && private_ip($1) && !seen[iface]++) {
				dns_ip = router_ip($1)
				if (dns_ip != "") { print iface " " dns_ip }
			}
		}
	'
}

private_ipv4_route_dns_options() {
	if have_cmd ip; then
		ip route show 2>/dev/null | awk '
			function private_ip(ip) {
				return ip ~ /^(10|127)\./ || ip ~ /^192\.168\./ || ip ~ /^172\.(1[6-9]|2[0-9]|3[0-1])\./
			}
			function router_ip(ip) {
				split(ip, octets, ".")
				if (octets[1] != "" && octets[2] != "" && octets[3] != "") { return octets[1] "." octets[2] "." octets[3] ".1" }
				return ""
			}
			{
				iface = ""
				src = ""
				split($1, dst_parts, "/")
				dst = dst_parts[1]
				for (i = 1; i <= NF; i++) {
					if ($i == "dev") { iface = $(i + 1) }
					if ($i == "src") { src = $(i + 1) }
				}
				if (iface ~ /^br/ && iface != "br0" && private_ip(dst) && !seen[iface]++) {
					if (!private_ip(src)) { src = router_ip(dst) }
					if (src != "") { print iface " " src }
				}
			}
		'
		return
	fi
	return 1
}

resolv_conf_is_tmp_mount() {
	df -h | grep -qoE '/tmp/resolv.conf'
}

resolv_conf_uses_rom() {
	readlink -f /etc/resolv.conf | grep -qE '^/rom/etc/resolv.conf'
}

save_dns_nvram_environment() {
	local VAR VALUE
	for VAR in dnspriv_enable dhcpd_dns_router dhcp_dns1_x dhcp_dns2_x; do
		VALUE="$(nvram get "${VAR}" 2>/dev/null)"
		case "${VAR}" in
			dnspriv_enable) _OLD_dnspriv_enable="${VALUE}" ;;
			dhcpd_dns_router) _OLD_dhcpd_dns_router="${VALUE}" ;;
			dhcp_dns1_x) _OLD_dhcp_dns1_x="${VALUE}" ;;
			dhcp_dns2_x) _OLD_dhcp_dns2_x="${VALUE}" ;;
		esac
	done
	export _OLD_dnspriv_enable _OLD_dhcpd_dns_router _OLD_dhcp_dns1_x _OLD_dhcp_dns2_x
	_DNS_NVRAM_SAVED="1"
	export _DNS_NVRAM_SAVED
}

sdn_bridge_for_index() {
	get_mtlan | awk -v idx="$1" '
		/^[[:space:]]*\|-enable:/ {
			enabled = ""
			bridge = ""
		}
		/^[[:space:]]*\|-enable:/ {
			start = index($0, "[")
			endpos = index($0, "]")
			if (start > 0 && endpos > start) { enabled = substr($0, start + 1, endpos - start - 1) }
		}
		/^[[:space:]]*\|-br_ifname:/ {
			start = index($0, "[")
			endpos = index($0, "]")
			if (start > 0 && endpos > start) { bridge = substr($0, start + 1, endpos - start - 1) }
		}
		/^[[:space:]]*\|-sdn_idx:/ {
			start = index($0, "[")
			endpos = index($0, "]")
			if (start > 0 && endpos > start) {
				sdn = substr($0, start + 1, endpos - start - 1)
				if (sdn == idx && enabled == "1") {
					print bridge
					exit
				}
			}
		}
		'
}

system_time_ready() {
	local now script_time year
	nvram_int_gt ntp_ready 0 || return 1
	year="$(/bin/date -u +"%Y" 2>/dev/null)"
	case "${year}" in
		"" | *[!0-9]*) ;;
		*) [ "${year}" -gt "1970" ] && return 0 ;;
	esac
	now="$(/bin/date -u '+%s' 2>/dev/null)"
	script_time="$(/bin/date -u -r "${MID_SCRIPT}" '+%s' 2>/dev/null)"
	case "${now}:${script_time}" in
		*[!0-9:]* | "":* | *:) return 1 ;;
	esac
	[ "${now}" -ge "${script_time}" ]
}

# Process tuning helpers

proc_optimizations() {
	{ proc_write "4194304" "/proc/sys/kernel/pid_max"; }                                 # Ensure max PID coverage
	{ proc_write "2" "/proc/sys/vm/overcommit_memory"; }                                 # Ensure ratio algorithm checks properly work including swap.
	{ proc_write "60" "/proc/sys/vm/swappiness"; }                                       # Ensure swappiness is set for more readily usability.
	{ proc_write "50" "/proc/sys/vm/overcommit_ratio"; }                                 # Ensure a proper overcommit policy is available.
	{ proc_write "4194304" "/proc/sys/net/core/rmem_max"; }                              # Ensure UDP receive buffer set to 4M.
	{ proc_write "1048576" "/proc/sys/net/core/wmem_max"; }                              # Ensure 1M for wmem_max.
	{ proc_write "0" "/proc/sys/net/ipv4/icmp_ratelimit"; }                              # Ensure Control over MTRS
	{ proc_write "240" "/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_max_retrans"; } # Lower conntrack tcp_timeout_max_retrans from 300 to 240
	{ proc_write "256" "/proc/sys/net/ipv4/neigh/default/gc_thresh1"; }                  # Increase ARP cache sizes and GC thresholds
	{ proc_write "1024" "/proc/sys/net/ipv4/neigh/default/gc_thresh2"; }                 # Increase ARP cache sizes and GC thresholds
	{ proc_write "2048" "/proc/sys/net/ipv4/neigh/default/gc_thresh3"; }                 # Increase ARP cache sizes and GC thresholds
	if [ -n "$(nvram get ipv6_service)" ]; then                                          # IPV6 proc variants
		{ proc_write "0" "/proc/sys/net/ipv6/icmp/ratelimit"; }
		{ proc_write "256" "/proc/sys/net/ipv6/neigh/default/gc_thresh1"; }
		{ proc_write "1024" "/proc/sys/net/ipv6/neigh/default/gc_thresh2"; }
		{ proc_write "2048" "/proc/sys/net/ipv6/neigh/default/gc_thresh3"; }
	fi
}

proc_write() {
	local TARGET VALUE
	VALUE="$1"
	TARGET="$2"
	{ [ -e "${TARGET}" ] || return 0; }
	{ [ -w "${TARGET}" ] || return 0; }
	{ printf "%s" "${VALUE}" >"${TARGET}"; }
}

# Service lifecycle helpers

lower_script() {
	case "$1" in
		*)
			${LOWER_SCRIPT_LOC} "$1" "${NAME}"
			;;
	esac
}

service_wait() {
	umask 022
	local maxwait trap_file
	[ -z "$2" ] && maxwait="300" || maxwait="$2"
	(
		trap_file="$(trap_state_create service-wait)" || exit 1
		trap_state_save "${trap_file}" || exit 1
		trap 'status="$?"; trap_state_restore "${trap_file}"; exit "${status}"' EXIT
		{
			timezone
			cd '/'
			trap '' HUP INT QUIT ABRT TERM TSTP
		}
		{
			exec 0<'/dev/null'
			exec 1>'/dev/null'
			exec 2>'/dev/null'
		}
		{
			local elapsed interval
			elapsed="0"
			interval="10"
			while [ "${elapsed}" -le "${maxwait}" ]; do
				if [ "$(nvram get success_start_service)" = '1' ] && { "$1"; }; then break; fi
				sleep "${interval}s"
				elapsed="$((elapsed + interval))"
			done
		}
		{
			trap_state_restore "${trap_file}"
			if [ "${elapsed}" -gt "${maxwait}" ]; then return 1; else return 0; fi
		}
	) &
	local PID="$!"
	wait "${PID}"
	return "$?"
}

start_adguardhome() {
	case "$(pidof "${PROCS}" 2>/dev/null | wc -w)" in
		0)
			lower_script start
			;;
		*)
			lower_script restart
			;;
	esac
	for db in stats.db sessions.db; do {
		if [ ! "$(readlink -f "/tmp/${db}")" = "$(readlink -f "${WORK_DIR}/data/${db}")" ]; then {
			ln -s "${WORK_DIR}/data/${db}" "/tmp/${db}" >/dev/null 2>&1
		}; fi
	}; done
	if { service_wait netcheck 300; }; then
		return "0"
	else
		return "1"
	fi
}

start_monitor() {
	local BINARY_UNAVAILABLE_LOGGED MONITOR_BINARY_RETRY_INTERVAL MONITOR_ELAPSED MONITOR_HEALTHCHECK_INTERVAL MONITOR_HEALTHCHECK_TIMEOUT MONITOR_SLEEP_INTERVAL MONITOR_STATE TRAP_FILE
	MONITOR_BINARY_RETRY_INTERVAL="10"
	MONITOR_HEALTHCHECK_INTERVAL="300"
	MONITOR_HEALTHCHECK_TIMEOUT="150"
	MONITOR_SLEEP_INTERVAL="10"
	MONITOR_STATE="running"
	TRAP_FILE="$(trap_state_create monitor)" || return 1
	trap_state_save "${TRAP_FILE}" || return 1
	trap 'status="$?"; trap_state_restore "${TRAP_FILE}"; exit "${status}"' EXIT
	trap '' HUP INT QUIT ABRT TERM TSTP
	trap 'MONITOR_STATE="stop"' USR1
	trap 'MONITOR_STATE="restart"' USR2
	{ service_wait netcheck; }
	logger -st "${NAME}" "Starting Monitor!"
	logger -st "${NAME}" "Monitor health checks will run every ${MONITOR_HEALTHCHECK_INTERVAL} second(s)."
	while true; do
		case "${MONITOR_STATE}" in
			"running" | "stop")
				check_dns_environment "${MONITOR_STATE}"
				;;
			"restart")
				check_dns_environment "running"
				;;
		esac
		if [ "${MONITOR_STATE}" = "stop" ]; then # A place to exit early if needed, or if binary becomes unavailable before service-stop.
			logger -st "${NAME}" "Stopping Monitor!"
			trap_state_restore "${TRAP_FILE}"
			{ adguardhome_run stop_adguardhome; }
			break
		fi
		if [ ! -x "/opt/sbin/AdGuardHome" ]; then
			if [ -z "${BINARY_UNAVAILABLE_LOGGED}" ]; then
				logger -st "${NAME}" "Warning: AdGuardHome binary is unavailable; Monitor will wait."
				BINARY_UNAVAILABLE_LOGGED="1"
			fi
			sleep "${MONITOR_BINARY_RETRY_INTERVAL}s"
			continue
		fi
		if [ -n "${BINARY_UNAVAILABLE_LOGGED}" ]; then
			logger -st "${NAME}" "AdGuardHome binary is available and executable; Monitor will resume."
			unset BINARY_UNAVAILABLE_LOGGED MONITOR_ELAPSED
		fi
		case ${MONITOR_STATE} in
			"running")
				timezone
				case "${MONITOR_ELAPSED}" in
					"")
						MONITOR_ELAPSED="0"
						{ adguardhome_run start_adguardhome; }
						;;
				esac
				case "$(pidof "${PROCS}" 2>/dev/null | wc -w)" in
					0)
						logger -st "${NAME}" "Warning: ${PROCS} is dead; Monitor will start it!"
						unset MONITOR_ELAPSED
						;;
					1)
						if [ "${MONITOR_ELAPSED}" -ge "${MONITOR_HEALTHCHECK_INTERVAL}" ]; then
							MONITOR_ELAPSED="0"
							if { ! service_wait netcheck "${MONITOR_HEALTHCHECK_TIMEOUT}"; }; then
								logger -st "${NAME}" "Warning: ${PROCS} is not responding; Monitor will re-start it!"
								unset MONITOR_ELAPSED
							fi
						else
							MONITOR_ELAPSED="$((MONITOR_ELAPSED + MONITOR_SLEEP_INTERVAL))"
						fi
						if [ -n "${MONITOR_ELAPSED}" ]; then sleep "${MONITOR_SLEEP_INTERVAL}s"; fi
						;;
					*)
						logger -st "${NAME}" "Warning: multiple ${PROCS} instances detected; Monitor will re-start it!"
						unset MONITOR_ELAPSED
						;;
				esac
				;;
			"stop")
				logger -st "${NAME}" "Stopping Monitor!"
				trap_state_restore "${TRAP_FILE}"
				{ adguardhome_run stop_adguardhome; }
				break
				;;
			"restart")
				logger -st "${NAME}" "Monitor is restarting AdGuardHome!"
				unset MONITOR_ELAPSED
				MONITOR_STATE="running"
				;;
		esac
	done
}

stop_adguardhome() {
	case "$(pidof "${PROCS}" 2>/dev/null | wc -w)" in
		0)
			:
			;;
		*)
			lower_script stop || lower_script kill
			;;
	esac
	service restart_dnsmasq >/dev/null 2>&1
	for db in stats.db sessions.db; do {
		if [ "$(readlink -f "/tmp/${db}")" = "$(readlink -f "${WORK_DIR}/data/${db}")" ]; then {
			rm "/tmp/${db}" >/dev/null 2>&1
		}; fi
	}; done
	if { service_wait netcheck 300; }; then
		return 0
	else
		return 1
	fi
}

stop_monitor() {
	local SIGNAL
	case "$1" in
		"${MON_PID}")
			SIGNAL="USR2"
			;;
		"$$")
			if [ -n "${MON_PID}" ]; then SIGNAL="USR1"; else { adguardhome_run stop_adguardhome; }; fi
			;;
	esac
	[ -n "${SIGNAL}" ] && { kill -s "${SIGNAL}" "${MON_PID}" 2>/dev/null; }
}

timezone() {
	local NOW SCRIPT_TIME SCRIPT_TIME_TEXT TARGET TIMEZONE
	TIMEZONE="/jffs/addons/AdGuardHome.d/localtime"
	TARGET="/etc/localtime"
	if { [ ! -f "${TARGET}" ] && [ -f "${TIMEZONE}" ]; }; then { ln -sf "${TIMEZONE}" "${TARGET}"; }; fi
	if [ -f "${TARGET}" ] || [ -n "$(readlink "${TARGET}")" ]; then
		NOW="$(/bin/date -u '+%s' 2>/dev/null)"
		SCRIPT_TIME="$(/bin/date -u -r "${MID_SCRIPT}" '+%s' 2>/dev/null)"
		case "${NOW}:${SCRIPT_TIME}" in
			*[!0-9:]* | "":* | *:)
				return 1
				;;
		esac
		if [ "${NOW}" -lt "${SCRIPT_TIME}" ]; then
			SCRIPT_TIME_TEXT="$(/bin/date -u -r "${MID_SCRIPT}" '+%Y-%m-%d %H:%M:%S')"
			{ /bin/date -u -s "${SCRIPT_TIME_TEXT}"; }
		else
			{ touch "${MID_SCRIPT}"; }
		fi
	fi
}

# IPSet integration helpers

IPSet_Generate() {
	{
		IPSet_Generate_Dnsmasq
		IPSet_Generate_DomainVPNRouting
		IPSet_Generate_WireGuardSessionManager
		IPSet_Generate_X3mRouting
	} | sort -u
}

IPSet_Generate_Dnsmasq() {
	[ -f "${IPSET_SOURCE}" ] || return 0
	awk '
		/^[[:space:]]*ipset=/ {
			line = $0
			sub(/^[[:space:]]*ipset=/, "", line)
			sub(/[[:space:]]*#.*/, "", line)
			gsub(/[[:space:]]/, "", line)
			n = split(line, fields, "/")
			if (n < 3 || fields[n] == "") next
			domains = ""
			for (i = 1; i < n; i++) {
				if (fields[i] == "") continue
				if (domains != "") domains = domains ","
				domains = domains fields[i]
			}
			if (domains != "") print domains "/" fields[n]
		}
	' "${IPSET_SOURCE}"
}

IPSet_Generate_DomainVPNRouting() {
	local CANDIDATE DOMAIN_FILE IPSET_NAMES POLICY SET_NAME
	have_cmd ipset || return 0
	[ -d "${IPSET_DVR_DIR}" ] || return 0
	IPSET_NAMES="$(ipset list -name 2>/dev/null)"
	[ -n "${IPSET_NAMES}" ] || return 0
	for DOMAIN_FILE in "${IPSET_DVR_DIR}"/policy_*_domainlist; do
		[ -f "${DOMAIN_FILE}" ] || continue
		POLICY="${DOMAIN_FILE##*/policy_}"
		POLICY="${POLICY%_domainlist}"
		[ -n "${POLICY}" ] || continue
		SET_NAME=""
		for CANDIDATE in \
			"DVR-${POLICY}-ipv4" \
			"DVR-${POLICY}-ipv6"; do
			if printf '%s\n' "${IPSET_NAMES}" | grep -qxF "${CANDIDATE}"; then
				if [ -n "${SET_NAME}" ]; then SET_NAME="${SET_NAME},${CANDIDATE}"; else SET_NAME="${CANDIDATE}"; fi
			fi
		done
		[ -n "${SET_NAME}" ] || continue
		awk -v sets="${SET_NAME}" '
			{
				line = $0
				sub(/[[:space:]]*#.*/, "", line)
				gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
				if (line != "") print line "/" sets
			}
		' "${DOMAIN_FILE}"
	done
}

IPSet_Generate_WireGuardSessionManager() {
	local DOMAIN_FILE SET_NAME
	have_cmd sqlite3 || return 0
	[ -f "${IPSET_WGM_DATABASE}" ] || return 0
	[ -d "${IPSET_WGM_DOMAIN_DIR}" ] || return 0
	sqlite3 "${IPSET_WGM_DATABASE}" \
		"SELECT DISTINCT ipset FROM ipset WHERE UPPER(\"use\") = 'Y' AND ipset <> '' ORDER BY ipset;" 2>/dev/null |
		while IFS= read -r SET_NAME; do
			case "${SET_NAME}" in
				"" | *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.:-]*) continue ;;
			esac
			DOMAIN_FILE="${IPSET_WGM_DOMAIN_DIR}/${SET_NAME}.domains"
			[ -f "${DOMAIN_FILE}" ] || continue
			awk -v set_name="${SET_NAME}" '
				{
					line = $0
					sub(/[[:space:]]*#.*/, "", line)
					gsub(/[[:space:]]/, "", line)
					if (line != "") print line "/" set_name
				}
			' "${DOMAIN_FILE}"
		done
}

IPSet_Generate_X3mRouting() {
	[ -f "${IPSET_X3M_SOURCE}" ] || return 0
	awk '
		function option_value(value) {
			sub(/^[^=]*=/, "", value)
			gsub(/^["\047]|["\047;]+$/, "", value)
			return value
		}
		function emit_domains(value, set_name,    count, domains, i, item) {
			value = option_value(value)
			count = split(value, item, ",")
			domains = ""
			for (i = 1; i <= count; i++) {
				if (item[i] == "") continue
				if (domains != "") domains = domains ","
				domains = domains item[i]
			}
			if (domains != "" && set_name != "") print domains "/" set_name
		}
		function emit_file(value, set_name,    domains, line, path) {
			path = option_value(value)
			domains = ""
			while ((getline line < path) > 0) {
				sub(/[[:space:]]*#.*/, "", line)
				gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
				if (line == "") continue
				if (domains != "") domains = domains ","
				domains = domains line
			}
			close(path)
			if (domains != "" && set_name != "") print domains "/" set_name
		}
		/^[[:space:]]*#/ || $0 !~ /x3mRouting/ { next }
		{
			command_field = 0
			set_name = ""
			for (i = 1; i <= NF; i++) {
				command = $i
				gsub(/^["\047]|["\047;]+$/, "", command)
				if (command ~ /(^|\/)x3mRouting(\.sh)?$/) command_field = i
				if ($i ~ /^ipset_name=/) set_name = option_value($i)
			}
			# x3mRouting 1.x/converted entries use: interface client set-name.
			if (set_name == "" && command_field > 0 && command_field + 3 <= NF) {
				set_name = $(command_field + 3)
				if (set_name ~ /=/) set_name = ""
			}
			gsub(/^["\047]|["\047;]+$/, "", set_name)
			for (i = 1; i <= NF; i++) {
				if ($i ~ /^dnsmasq=/) emit_domains($i, set_name)
				else if ($i ~ /^dnsmasq_file=/) emit_file($i, set_name)
			}
		}
	' "${IPSET_X3M_SOURCE}"
}

IPSet_Lock() {
	if have_cmd flock && flock_supports_fd; then
		IPSet_Lock_Flock "$@"
	else
		IPSet_Lock_Mkdir "$@"
	fi
}

IPSet_Lock_Flock() {
	local LOCK_FILE STATUS
	LOCK_FILE="/tmp/AdGuardHome-ipset.lock"
	(
		exec 8>"${LOCK_FILE}" || exit 1
		flock 8 || exit 1
		"$@"
	)
	STATUS="$?"
	return "${STATUS}"
}

IPSet_Lock_Mkdir() {
	local ATTEMPTS LOCK_DIR OWNER TRAP_FILE
	LOCK_DIR="/tmp/AdGuardHome-ipset"
	ATTEMPTS="0"
	while ! mkdir "${LOCK_DIR}" 2>/dev/null; do
		OWNER="$(sed -n '1p' "${LOCK_DIR}/pid" 2>/dev/null)"
		case "${OWNER}" in
			"" | *[!0-9]*) ;;
			*)
				if ! kill -0 "${OWNER}" 2>/dev/null; then
					rm -rf "${LOCK_DIR}"
					continue
				fi
				;;
		esac
		ATTEMPTS="$((ATTEMPTS + 1))"
		[ "${ATTEMPTS}" -ge 30 ] && return 1
		sleep 1
	done
	(
		TRAP_FILE="$(trap_state_create ipset-mkdir)" || {
			rm -rf "${LOCK_DIR}"
			exit 1
		}
		trap_state_save "${TRAP_FILE}" || {
			rm -rf "${LOCK_DIR}"
			exit 1
		}
		trap 'STATUS="$?"; rm -rf "${LOCK_DIR}"; trap_state_restore "${TRAP_FILE}"; exit "${STATUS}"' EXIT HUP INT QUIT ABRT TERM TSTP
		printf '%s\n' "$$" >"${LOCK_DIR}/pid"
		"$@"
	)
}

IPSet_Sync() {
	IPSet_Lock IPSet_Sync_Locked
}

IPSet_Normalize() {
	awk '
		{
			line = $0
			sub(/[[:space:]]*#.*/, "", line)
			gsub(/[[:space:]]/, "", line)
			if (line == "") next
			n = split(line, fields, "/")
			if (n != 2 || fields[1] == "" || fields[2] == "") next
			print fields[1] "/" fields[2]
		}
	' "$1" | sort -u
}

IPSet_Sync_Locked() {
	local CHANGED CURRENT_FILE CUSTOM_FILE FINAL_FILE MANAGED_FILE PREVIOUS_FILE
	MANAGED_FILE="${IPSET_MANAGED_FILE}.$$"
	CURRENT_FILE="${IPSET_FILE}.current.$$"
	CUSTOM_FILE="${IPSET_FILE}.custom.$$"
	FINAL_FILE="${IPSET_FILE}.$$"
	PREVIOUS_FILE="${IPSET_MANAGED_FILE}"
	[ -f "${PREVIOUS_FILE}" ] || PREVIOUS_FILE="${IPSET_LEGACY_MANAGED_FILE}"
	CHANGED="0"

	if ! IPSet_Generate >"${MANAGED_FILE}"; then
		rm -f "${MANAGED_FILE}" "${CURRENT_FILE}" "${CUSTOM_FILE}" "${FINAL_FILE}"
		return 1
	fi
	if [ -f "${IPSET_FILE}" ]; then
		IPSet_Normalize "${IPSET_FILE}" >"${CURRENT_FILE}"
	else
		: >"${CURRENT_FILE}"
	fi
	# On the first managed sync, mappings still supplied by an automatic source
	# are managed. All other valid entries are AdGuardHome-side additions.
	[ -f "${PREVIOUS_FILE}" ] || PREVIOUS_FILE="${MANAGED_FILE}"
	awk 'FILENAME == ARGV[1] { managed[$0] = 1; next } !managed[$0]' "${PREVIOUS_FILE}" "${CURRENT_FILE}" >"${CUSTOM_FILE}"
	cat "${CUSTOM_FILE}" "${MANAGED_FILE}" | sort -u >"${FINAL_FILE}"

	if [ ! -f "${IPSET_FILE}" ] || ! cmp -s "${FINAL_FILE}" "${IPSET_FILE}"; then
		mv "${FINAL_FILE}" "${IPSET_FILE}" || return 1
		chmod 644 "${IPSET_FILE}"
		CHANGED="1"
	else
		rm -f "${FINAL_FILE}"
	fi
	if [ ! -f "${IPSET_MANAGED_FILE}" ] || ! cmp -s "${MANAGED_FILE}" "${IPSET_MANAGED_FILE}"; then
		mv "${MANAGED_FILE}" "${IPSET_MANAGED_FILE}" || return 1
		chmod 644 "${IPSET_MANAGED_FILE}"
	else
		rm -f "${MANAGED_FILE}"
	fi
	rm -f "${IPSET_LEGACY_MANAGED_FILE}" "${CURRENT_FILE}" "${CUSTOM_FILE}"
	[ "${CHANGED}" = "1" ]
}

IPSet_Sync_Restart() {
	if IPSet_Sync && [ -n "${MON_PID}" ] && [ "$(pidof "${PROCS}" 2>/dev/null | wc -w)" -gt 0 ]; then
		kill -s USR2 "${MON_PID}" 2>/dev/null
	fi
}

if [ -f "${UPPER_SCRIPT}" ]; then UPPER_SCRIPT_LOC=". ${UPPER_SCRIPT}"; fi
if [ -f "${LOWER_SCRIPT}" ]; then LOWER_SCRIPT_LOC=". ${LOWER_SCRIPT}"; fi
if { [ "$2" != "x" ] && printf "%s" "$1" | /bin/grep -qE "^((start|stop|restart|kill|reload)$)"; }; then {
	service "${1}"_AdGuardHome >/dev/null 2>&1
	exit
}; fi
if [ "$1" = "init-start" ] && [ ! -f "${UPPER_SCRIPT}" ]; then { service_wait adguardhome_run; }; fi
if [ -f "${UPPER_SCRIPT}" ]; then { if { [ "$(readlink -f "${UPPER_SCRIPT}")" != "${SCRIPT_LOC}" ] || [ "$0" != "${UPPER_SCRIPT}" ]; }; then {
	exec "${UPPER_SCRIPT}" "$@"
	exit
}; fi; }; else { if [ -z "${PROCS}" ]; then exit; fi; }; fi
{ for PID in $(pidof "S99${PROCS}"); do if { awk '{ print }' "/proc/${PID}/cmdline" | grep -q monitor-start; } && [ "${PID}" != "$$" ]; then { MON_PID="${PID}"; }; fi; done; }

unset TZ
case "$1" in
	"monitor-start")
		if [ -n "${MON_PID}" ]; then { stop_monitor "${MON_PID}"; }; else { start_monitor & } fi
		;;
	"start" | "restart")
		{ "${SCRIPT_LOC}" service-start >/dev/null 2>&1; }
		;;
	"stop" | "kill")
		{ "${SCRIPT_LOC}" services-stop >/dev/null 2>&1; }
		;;
	"dnsmasq" | "dnsmasq-sdn")
		if [ -n "${2}" ]; then { dnsmasq_params "${2}"; }; else { dnsmasq_params; }; fi
		;;
	"ipset")
		case "${2:-}" in
			"sync") IPSet_Sync ;;
			*) IPSet_Sync_Restart ;;
		esac
		;;
	"init-start" | "service-start" | "services-stop")
		case "$1" in
			"init-start")
				IPSet_Sync
				proc_optimizations
				timezone
				{ "${SCRIPT_LOC}" monitor-start; }
				;;
			"service-start")
				IPSet_Sync
				timezone
				{ "${SCRIPT_LOC}" monitor-start; }
				;;
			"services-stop")
				{ stop_monitor "$$"; }
				;;
		esac
		;;
	*)
		{ ${LOWER_SCRIPT_LOC} "$1"; } && exit
		;;
esac
