#!/bin/sh

SCRIPT_LOC="$(readlink -f "$0")"
CONF_FILE="/opt/etc/AdGuardHome/.config"
MID_SCRIPT="/jffs/addons/AdGuardHome.d/AdGuardHome.sh"
UPPER_SCRIPT="/opt/etc/init.d/S99AdGuardHome"
LOWER_SCRIPT="/opt/etc/init.d/rc.func.AdGuardHome"

NAME="$(basename "$0")[$$]"

adguardhome_run() {
	local lock_dir pid pid_file start end runtime
	lock_dir="/tmp/AdGuardHome"
	pid_file="${lock_dir}/pid"
	case "$1" in
	"")
		if [ -z "$(sed -n '2p' ${pid_file})" ] || [ ! -f "${UPPER_SCRIPT}" ]; then return 1; else return 0; fi
		;;
	*)
		if (mkdir ${lock_dir}) 2>/dev/null || { [ -e "${pid_file}" ] && [ -n "$(sed -n '2p' ${pid_file})" ]; } || { [ "$1" = "stop_adguardhome" ]; }; then
			(
				trap 'rm -rf "${lock_dir}"; exit $?' EXIT
				{ service_wait adguardhome_run; }
				rm -rf "${lock_dir}"
			) &
			pid="$!"
			{
				printf "%s\n" "${pid}" >"${pid_file}"
				start="$(date +%s)"
				{ service_wait "$1" 30; }
				end="$(date +%s)"
				runtime="$((end - start))"
				printf "%s\n" "${runtime}" >>"${pid_file}"
				logger -st "${NAME}" "$1 took ${runtime} second(s) to complete."
			}
		else
			logger -st "${NAME}" "Lock owned by $(sed -n '1p' ${pid_file}) exists; preventing duplicate runs!"
		fi
		;;
	esac
}

check_dns_environment() {
	local NVCHECK
	NVCHECK="0"
	if [ "$(nvram get dnspriv_enable)" != "0" ]; then
		{ nvram set dnspriv_enable="0"; }
		NVCHECK="$((NVCHECK + 1))"
	fi
	if [ "$(pidof stubby)" ]; then
		{ killall -q -9 stubby 2>/dev/null; }
		NVCHECK="$((NVCHECK + 1))"
	fi
	if [ "$(nvram get dhcp_dns1_x)" ] && [ "${NVCHECK}" != "0" ]; then
		{ nvram set dhcp_dns1_x=""; }
		NVCHECK="$((NVCHECK + 1))"
	fi
	if [ "$(nvram get dhcp_dns2_x)" ] && [ "${NVCHECK}" != "0" ]; then
		{ nvram set dhcp_dns2_x=""; }
		NVCHECK="$((NVCHECK + 1))"
	fi
	if [ "$(nvram get dhcpd_dns_router)" != "1" ] && [ "${NVCHECK}" != "0" ]; then
		{ nvram set dhcpd_dns_router="1"; }
		NVCHECK="$((NVCHECK + 1))"
	fi
	if [ "${NVCHECK}" != "0" ]; then
		{ nvram commit; }
		{ service restart_dnsmasq >/dev/null 2>&1; }
		{ service_wait netcheck 150; }
	fi
}

dnsmasq_params() {
	local CONFIG COUNT iCOUNT dCOUNT iVARS IVARS dVARS DVARS NIVARS NDVARS NET_ADDR NET_ADDR6 LAN_IF i
	CONFIG="/etc/dnsmasq.conf"
	if { ! readlink -f /etc/resolv.conf | grep -qE ^'/rom/etc/resolv.conf' && df -h | grep -qoE '/tmp/resolv.conf'; }; then { umount /tmp/resolv.conf 2>/dev/null; }; fi
	if [ -n "$(pidof "${PROCS}")" ]; then
		LAN_IF="$(nvram get lan_ifname)"
		[ -n "${LAN_IF}" ] && NET_ADDR="$(ip -o -4 addr list "${LAN_IF}" | awk 'NR==1{ split($4, ip_addr, "/"); print ip_addr[1] }')" || NET_ADDR="$(nvram get lan_ipaddr)"
		[ -n "${LAN_IF}" ] && NET_ADDR6="$(ip -o -6 addr list "${LAN_IF}" scope global | awk 'NR==1{ split($4, ip_addr, "/"); print ip_addr[1] }')" || NET_ADDR6="$(nvram get ipv6_rtr_addr)"
		{
			sed -i "/^port=.*$/d" "${CONFIG}"
   			sed -i "/^dhcp-option=lan,6.*$/d" "${CONFIG}"
			printf "%s\n" "port=553" "local=/$(printf "%s\n" "${NET_ADDR}" | awk 'BEGIN{FS="."}{print $2"."$1".in-addr.arpa"}')/" "local=/10.in-addr.arpa/" "local=//" "dhcp-option=lan,6,0.0.0.0" >>"${CONFIG}"
		}
		if [ -n "${NET_ADDR6}" ]; then { printf "%s\n" "local=/$(printf "%s\n" "${NET_ADDR6}" | sed 's/.$//' | awk -F: '{for(i=1;i<=NF;i++)x=x""sprintf (":%4s", $i);gsub(/ /,"0",x);print x}' | cut -c 2- | cut -c 1-20 | sed 's/://g;s/^.*$/\n&\n/;tx;:x;s/\(\n.\)\(.*\)\(.\n\)/\3\2\1/;tx;s/\n//g;s/\(.\)/\1./g;s/$/ip6.arpa/')/" >>"${CONFIG}"; }; fi
		if [ -n "$(route | grep "br" | grep -v "br0" | grep -oE '\b^(((10|127)(\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)){3})|(((172\.(1[6-9]|2[0-9]|3[0-1]))|(192\.168))(\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)){2}))\b' | awk '{print $1}' | sed -e 's/[0-9]$/1/' | sed -e ':a; N; $!ba;s/\n/ /g')" ]; then
			iCOUNT="1"
			for iVARS in $(route | grep "br" | grep -v "br0" | grep -E '\b^(((10|127)(\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)){3})|(((172\.(1[6-9]|2[0-9]|3[0-1]))|(192\.168))(\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)){2}))\b' | awk '{print $8}' | sed -e ':a; N; $!ba;s/\n/ /g'); do
				[ "${iCOUNT}" = "1" ] && COUNT="${iCOUNT}" && IVARS="${iVARS}"
				[ "${iCOUNT}" != "1" ] && COUNT="${COUNT} ${iCOUNT}" && IVARS="${IVARS} ${iVARS}"
				iCOUNT="$((iCOUNT + 1))"
			done
			dCOUNT="1"
			for dVARS in $(route | grep "br" | grep -v "br0" | grep -oE '\b^(((10|127)(\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)){3})|(((172\.(1[6-9]|2[0-9]|3[0-1]))|(192\.168))(\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)){2}))\b' | awk '{print $1}' | sed -e 's/[0-9]$/1/' | sed -e ':a; N; $!ba;s/\n/ /g'); do
				[ "${dCOUNT}" = "1" ] && DVARS="${dVARS}"
				[ "${dCOUNT}" != "1" ] && DVARS="${DVARS} ${dVARS}"
				dCOUNT="$((dCOUNT + 1))"
			done
			for i in ${COUNT}; do
				NIVARS="$(printf "%s\n" "${IVARS}" | cut -d' ' -f"${i}")"
				NDVARS="$(printf "%s\n" "${DVARS}" | cut -d' ' -f"${i}")"
				printf "%s\n" "dhcp-option=${NIVARS},6,${NDVARS}" >>"${CONFIG}"
			done
		fi
		if { ! readlink -f /etc/resolv.conf | grep -qE ^'/rom/etc/resolv.conf' && awk -F'=' '/ADGUARD_LOCAL/ {print $2}' "${CONF_FILE}" | sed -e 's/^"//' -e 's/"$//' | grep -qE ^'YES'; }; then { mount -o bind /rom/etc/resolv.conf /tmp/resolv.conf; }; fi
	fi
}

lower_script() {
	case "$1" in
	*)
		${LOWER_SCRIPT_LOC} "$1" "${NAME}"
		;;
	esac
}

netcheck() {
	local livecheck="0" i
        until { [ "$(/bin/date -u +"%Y")" -gt "1970" ] || [ "$(/bin/date -u '+%s')" -ge "$(/bin/date -u -r "${MID_SCRIPT}" '+%s')" ]; } && [ "$(nvram get ntp_ready)" -gt 0 ]; do sleep 1s; done
	while [ "${livecheck}" != "4" ]; do
		for i in google.com github.com snbforums.com; do
			if { ! nslookup "${i}" 127.0.0.1 >/dev/null 2>&1; } && { ping -q -w3 -c1 "${i}" >/dev/null 2>&1; }; then
				if { ! curl --retry 3 --connect-timeout 3 --retry-delay 1 --max-time $((3 * 5)) --retry-all-errors -Is "http://${i}" | head -n 1 >/dev/null 2>&1; } || { ! wget --no-cache --no-cookies --timeout=3 --waitretry=3 --tries=3 --retry-connrefused -q --spider "http://${i}" >/dev/null 2>&1; }; then
					sleep 1s
					continue
				fi
				return 0
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

proc_optimizations() {
	{ printf "4194304" >/proc/sys/kernel/pid_max; }                                 # Ensure max PID coverage
	{ printf "2" >/proc/sys/vm/overcommit_memory; }                                 # Ensure ratio algorithm checks properly work including swap.
	{ printf "60" >/proc/sys/vm/swappiness; }                                       # Ensure swappiness is set for more readily usability.
	{ printf "50" >/proc/sys/vm/overcommit_ratio; }                                 # Ensure a proper overcommit policy is available.
	{ printf "4194304" >/proc/sys/net/core/rmem_max; }                              # Ensure UDP receive buffer set to 4M.
	{ printf "1048576" >/proc/sys/net/core/wmem_max; }                              # Ensure 1M for wmem_max.
	{ printf "0" >/proc/sys/net/ipv4/icmp_ratelimit; }                              # Ensure Control over MTRS
	{ printf "256" >/proc/sys/net/ipv4/neigh/default/gc_thresh1; }                  # Increase ARP cache sizes and GC thresholds
	{ printf "1024" >/proc/sys/net/ipv4/neigh/default/gc_thresh2; }                 # Increase ARP cache sizes and GC thresholds
	{ printf "2048" >/proc/sys/net/ipv4/neigh/default/gc_thresh3; }                 # Increase ARP cache sizes and GC thresholds
	{ printf "240" >/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_max_retrans; } # Lower conntrack tcp_timeout_max_retrans from 300 to 240
	if [ -n "$(nvram get ipv6_service)" ]; then                                     #IPV6 proc variants
		{ printf "0" >/proc/sys/net/ipv6/icmp/ratelimit; }
		{ printf "256" >/proc/sys/net/ipv6/neigh/default/gc_thresh1; }
		{ printf "1024" >/proc/sys/net/ipv6/neigh/default/gc_thresh2; }
		{ printf "2048" >/proc/sys/net/ipv6/neigh/default/gc_thresh3; }
	fi
}

service_wait() {
	umask 022
	local OPT
	[ -z "$2" ] && OPT="10" || OPT="$2"
	(
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
			local maxwait i
			maxwait="300"
			i="0"
			while [ "${i}" -le "${maxwait}" ]; do
				if [ "$(nvram get success_start_service)" = '1' ] && { "$1"; }; then break; fi
				sleep 10s
				i="$((i + OPT))"
			done
		}
		{
			trap - HUP INT QUIT ABRT TERM TSTP
			if [ "${i}" -gt "${maxwait}" ]; then return 1; else return 0; fi
		}
	) &
	local PID="$!"
	wait "${PID}"
	return "$?"
}

start_adguardhome() {
	if [ -z "$(pidof "${PROCS}")" ]; then { lower_script start; }; else { lower_script restart; }; fi
	for db in stats.db sessions.db; do { if [ ! "$(readlink -f "/tmp/${db}")" = "$(readlink -f "${WORK_DIR}/data/${db}")" ]; then { ln -s "${WORK_DIR}/data/${db}" "/tmp/${db}" >/dev/null 2>&1; }; fi; }; done
	if [ -n "$(pidof "${PROCS}")" ] && { service_wait netcheck 300; }; then return "0"; else return "1"; fi
}

start_monitor() {
	trap '' HUP INT QUIT ABRT TERM TSTP
	trap 'EXIT="1"' USR1
	trap 'EXIT="2"' USR2
	{ service_wait netcheck; }
	local COUNT EXIT
	EXIT="0"
	logger -st "${NAME}" "Starting Monitor!"
	while true; do
		if [ -f "/opt/sbin/AdGuardHome" ]; then
			case ${EXIT} in
			"0")
				timezone
				case "${COUNT}" in
				"")
					COUNT="0"
					{ adguardhome_run start_adguardhome; }
					;;
				esac
				case "$(pidof "${PROCS}")" in
				"")
					logger -st "${NAME}" "Warning: ${PROCS} is dead; Monitor will start it!"
					unset COUNT
					;;
				*)
					case "${COUNT}" in
					"30" | "60" | "90")
						if [ "${COUNT}" = "90" ]; then COUNT="0"; else COUNT="$((COUNT + 1))"; fi
						if { ! service_wait netcheck 150; }; then
							logger -st "${NAME}" "Warning: ${PROCS} is not responding; Monitor will re-start it!"
							unset COUNT
						fi
						;;
					*)
						COUNT="$((COUNT + 1))"
						;;
					esac
					if [ -n "${COUNT}" ]; then sleep 10s; fi
					;;
				esac
				;;
			"1")
				logger -st "${NAME}" "Stopping Monitor!"
				trap - HUP INT QUIT ABRT USR1 USR2 TERM TSTP
				{ adguardhome_run stop_adguardhome; }
				break
				;;
			"2")
				logger -st "${NAME}" "Monitor is restarting AdGuardHome!"
				unset COUNT
				EXIT="0"
				;;
			esac
		fi
	done
}

stop_adguardhome() {
	if [ -n "$(pidof "${PROCS}")" ]; then { lower_script stop || lower_script kill; }; fi
	{ service restart_dnsmasq >/dev/null 2>&1; }
	for db in stats.db sessions.db; do { if [ "$(readlink -f "/tmp/${db}")" = "$(readlink -f "${WORK_DIR}/data/${db}")" ]; then { rm "/tmp/${db}" >/dev/null 2>&1; }; fi; }; done
	if [ -z "$(pidof "${PROCS}")" ] && { service_wait netcheck 300; }; then return 0; else return 1; fi
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
	local TIMEZONE TARGET
	TIMEZONE="/jffs/addons/AdGuardHome.d/localtime"
	TARGET="/etc/localtime"
	if { [ ! -f "${TARGET}" ] && [ -f "${TIMEZONE}" ]; }; then { ln -sf "${TIMEZONE}" "${TARGET}"; }; fi
	if [ -f "${TARGET}" ] || [ "$(readlink "${TARGET}")" ]; then { if [ "$(/bin/date -u '+%s')" -le "$(/bin/date -u -r "${MID_SCRIPT}" '+%s')" ]; then { /bin/date -u -s "$(/bin/date -u -r "${MID_SCRIPT}" '+%Y-%m-%d %H:%M:%S')"; }; else { touch "${MID_SCRIPT}"; }; fi; }; fi
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
	{ "${SCRIPT_LOC}" init-start >/dev/null 2>&1; }
	;;
"stop" | "kill")
	{ "${SCRIPT_LOC}" services-stop >/dev/null 2>&1; }
	;;
"dnsmasq")
	dnsmasq_params
	;;
"init-start" | "services-stop")
	timezone
	case "$1" in
	"init-start")
		proc_optimizations
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
check_dns_environment
