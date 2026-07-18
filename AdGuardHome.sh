#!/bin/sh

export LC_ALL=C
export PATH="/sbin:/bin:/usr/sbin:/usr/bin:/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin"

SCRIPT_LOC=""
ADGUARDHOME_BINARY="/opt/sbin/AdGuardHome"
CONF_FILE="/opt/etc/AdGuardHome/.config"
DNS_HANDOFF_DIR="${DNS_HANDOFF_DIR:-/tmp/AdGuardHome.dns-handoff}"
DNS_HANDOFF_FILE="${DNS_HANDOFF_FILE:-${DNS_HANDOFF_DIR}/active}"
MID_SCRIPT="/jffs/addons/AdGuardHome.d/AdGuardHome.sh"
UPPER_SCRIPT="/opt/etc/init.d/S99AdGuardHome"
LOWER_SCRIPT="/opt/etc/init.d/rc.func.AdGuardHome"
IPSET_FILE="/opt/etc/AdGuardHome/ipset.conf"
IPSET_RUNTIME_DIR="${IPSET_RUNTIME_DIR:-/opt/var/run/AdGuardHome-ipset}"
IPSET_USER_FILE="/opt/etc/AdGuardHome/ipset.user"
YAML_FILE="/opt/etc/AdGuardHome/AdGuardHome.yaml"
DEFAULT_ADGUARD_NETCHECK_HOSTS="google.com github.com snbforums.com"
DEFAULT_ADGUARD_NETCHECK_DNS="127.0.0.1"
DEFAULT_ADGUARD_NETCHECK_REQUIRE_HTTP="NO"
DEFAULT_ADGUARD_NETCHECK_TIMEOUT="300"
DEFAULT_ADGUARD_NETCHECK_MODE="wan"
DEFAULT_ADGUARD_PROC_OPTIMIZE="NO"
DEFAULT_ADGUARD_PROC_PROFILE="balanced"
INSTALLER_SCRIPT="/opt/etc/AdGuardHome/installer"
ADGUARD_NETCHECK_HOSTS_SET="${ADGUARD_NETCHECK_HOSTS:+x}"
ADGUARD_NETCHECK_DNS_SET="${ADGUARD_NETCHECK_DNS:+x}"
ADGUARD_NETCHECK_REQUIRE_HTTP_SET="${ADGUARD_NETCHECK_REQUIRE_HTTP:+x}"
ADGUARD_NETCHECK_TIMEOUT_SET="${ADGUARD_NETCHECK_TIMEOUT:+x}"
ADGUARD_NETCHECK_MODE_SET="${ADGUARD_NETCHECK_MODE:+x}"
ADGUARD_PROC_OPTIMIZE_SET="${ADGUARD_PROC_OPTIMIZE:+x}"
ADGUARD_PROC_PROFILE_SET="${ADGUARD_PROC_PROFILE:+x}"
ADGUARD_NETCHECK_HOSTS="${ADGUARD_NETCHECK_HOSTS:-${DEFAULT_ADGUARD_NETCHECK_HOSTS}}"
ADGUARD_NETCHECK_DNS="${ADGUARD_NETCHECK_DNS:-${DEFAULT_ADGUARD_NETCHECK_DNS}}"
ADGUARD_NETCHECK_REQUIRE_HTTP="${ADGUARD_NETCHECK_REQUIRE_HTTP:-${DEFAULT_ADGUARD_NETCHECK_REQUIRE_HTTP}}"
ADGUARD_NETCHECK_TIMEOUT="${ADGUARD_NETCHECK_TIMEOUT:-${DEFAULT_ADGUARD_NETCHECK_TIMEOUT}}"
ADGUARD_NETCHECK_MODE="${ADGUARD_NETCHECK_MODE:-${DEFAULT_ADGUARD_NETCHECK_MODE}}"
ADGUARD_PROC_OPTIMIZE="${ADGUARD_PROC_OPTIMIZE:-${DEFAULT_ADGUARD_PROC_OPTIMIZE}}"
ADGUARD_PROC_PROFILE="${ADGUARD_PROC_PROFILE:-${DEFAULT_ADGUARD_PROC_PROFILE}}"

NAME="${0##*/}[$$]"

# Functions are grouped by purpose; names are sorted alpha-numerically within each group.

# Core helpers

agh_timestamp() {
	date '+%Y/%m/%d %H:%M:%S'
}

agh_log() {
	local _level _func
	_level="$1"
	_func="$2"
	shift 2
	logger -st "${NAME}" "$(agh_timestamp) [${_level}] ${_func}: $*"
}

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

adguard_install_mode() {
	mode="$(conf_value ADGUARD_INSTALL_MODE 2>/dev/null)"
	case "${mode}" in
		wan | lan) printf '%s\n' "${mode}" ;;
		*) printf '%s\n' "wan" ;;
	esac
}

adguard_lan_mode() {
	[ "$(adguard_install_mode)" = "lan" ]
}

adguard_dnsmasq_running() {
	pidof dnsmasq >/dev/null 2>&1
}

adguard_dnsmasq_managed() {
	if adguard_lan_mode && ! adguard_dnsmasq_running; then
		return 1
	fi
	case "$(conf_value ADGUARD_DNSMASQ_MODE 2>/dev/null)" in
		disabled) return 1 ;;
		enabled) return 0 ;;
	esac
	adguard_dnsmasq_running
}

adguard_ipset_allowed() {
	! adguard_lan_mode
}

adguard_restart_dnsmasq_if_managed() {
	adguard_dnsmasq_managed || return 0
	service restart_dnsmasq >/dev/null 2>&1
}

have_cmd() {
	which "$1" >/dev/null 2>&1
}

canonical_path() {
	local BASE DIR LINK_INFO LINK_TARGET LINK_COUNT PATH_VALUE RESOLVED
	PATH_VALUE="$1"
	if have_cmd readlink; then
		RESOLVED="$(readlink -f "${PATH_VALUE}" 2>/dev/null)" || RESOLVED=""
		if [ -n "${RESOLVED}" ]; then
			printf '%s\n' "${RESOLVED}"
			return 0
		fi
	fi
	case "${PATH_VALUE}" in
		/*) ;;
		*) PATH_VALUE="${PWD}/${PATH_VALUE}" ;;
	esac
	LINK_COUNT=0
	while [ -L "${PATH_VALUE}" ]; do
		LINK_TARGET=""
		if have_cmd readlink; then
			LINK_TARGET="$(readlink "${PATH_VALUE}" 2>/dev/null)" || LINK_TARGET=""
		elif have_cmd ls; then
			LINK_INFO="$(ls -ld "${PATH_VALUE}" 2>/dev/null)" || LINK_INFO=""
			case "${LINK_INFO}" in
				*' -> '*) LINK_TARGET="${LINK_INFO#* -> }" ;;
			esac
		fi
		[ -n "${LINK_TARGET}" ] || return 1
		case "${LINK_TARGET}" in
			/*) PATH_VALUE="${LINK_TARGET}" ;;
			*) PATH_VALUE="${PATH_VALUE%/*}/${LINK_TARGET}" ;;
		esac
		LINK_COUNT=$((LINK_COUNT + 1))
		[ "${LINK_COUNT}" -le 40 ] || return 1
	done
	BASE="${PATH_VALUE##*/}"
	DIR="${PATH_VALUE%/*}"
	[ -n "${BASE}" ] && [ -d "${DIR}" ] || return 1
	DIR="$(cd "${DIR}" 2>/dev/null && pwd -P)" || return 1
	printf '%s/%s\n' "${DIR}" "${BASE}"
}

SCRIPT_LOC="$(canonical_path "$0")" || {
	printf '%s\n' "Unable to resolve script path: $0" >&2
	return 1 2>/dev/null || exit 1
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

manager_dependencies_available() {
	local REQUIRED_COMMAND
	# Keep optional IPSET-only tools out of this startup gate.  If an IPSET
	# helper is unavailable, IPSET setup is skipped and AdGuardHome still starts.
	for REQUIRED_COMMAND in awk date grep kill ln logger mkdir nvram pidof rm sed service sleep wc; do
		if ! have_cmd "${REQUIRED_COMMAND}"; then
			printf '%s\n' "${NAME}: required command is unavailable: ${REQUIRED_COMMAND}" >&2
			return 1
		fi
	done
	return 0
}

# Status helpers

agh_web_port() {
	local CONF_PORT YAML_PORT
	YAML_PORT="$(awk -F: '/^[[:space:]]*address:[[:space:]]*/ { print $NF; exit }' "${YAML_FILE}" 2>/dev/null | sed 's/[^0-9].*$//')"
	case "${YAML_PORT}" in
		"" | *[!0-9]*) ;;
		*) [ "${YAML_PORT}" -gt 0 ] && [ "${YAML_PORT}" -le 65535 ] && printf '%s\n' "${YAML_PORT}" && return 0 ;;
	esac
	CONF_PORT="$(conf_value ADGUARD_WEBUI_PORT 2>/dev/null)"
	case "${CONF_PORT}" in
		"" | *[!0-9]*) ;;
		*) [ "${CONF_PORT}" -gt 0 ] && [ "${CONF_PORT}" -le 65535 ] && printf '%s\n' "${CONF_PORT}" && return 0 ;;
	esac
	return 1
}

status_adguardhome_version() {
	if [ -x "${ADGUARDHOME_BINARY}" ]; then
		"${ADGUARDHOME_BINARY}" --version 2>/dev/null | head -1
	else
		printf '%s\n' "unknown"
	fi
}

status_dnsmasq_handoff_state() {
	local marker markers state
	state="inactive"
	markers=""
	for marker in /tmp/AdGuardHome.dnsmasq.handoff /tmp/AdGuardHome.dnsmasq.lock "${DNS_HANDOFF_FILE}" "${DNS_HANDOFF_DIR}/lock"; do
		if [ -e "${marker}" ]; then
			state="active/stale marker present"
			markers="${markers}${markers:+, }${marker}"
		fi
	done
	printf '%s\n' "${state}${markers:+ (${markers})}"
}

status_installer_version() {
	local version
	version="$(awk -F= '/^AI_VERSION=/ { gsub(/"/, "", $2); print $2; exit }' "${INSTALLER_SCRIPT}" 2>/dev/null)"
	printf '%s\n' "${version:-unknown}"
}

status_last_startup_result() {
	local result
	result=""
	if have_cmd logread; then
		result="$(logread 2>/dev/null |
			awk '
				/AdGuardHome/ && /state=startup/ { last = $0 }
				/AdGuardHome/ && /AdGuardHome startup completed/ { last = $0 }
				/AdGuardHome/ && /AdGuardHome startup failed/ { last = $0 }
				/AdGuardHome/ && /DNS\/WebUI readiness checks (passed|failed)/ { last = $0 }
				END { if (last != "") print last }
			')"
	fi
	printf '%s\n' "${result:-unknown (no startup marker/log entry found)}"
}

status_line() {
	printf '%s: %s\n' "$1" "${2:-unknown}"
}

status_monitor_count() {
	local count pid
	count="0"
	for pid in $(pidof AdGuardHome.sh S99AdGuardHome rc.func.AdGuardHome 2>/dev/null); do
		if awk '{ print }' "/proc/${pid}/cmdline" 2>/dev/null | grep -q 'monitor-start'; then
			count="$((count + 1))"
		fi
	done
	printf '%s\n' "${count}"
}

status_port53_ownership() {
	local dns53
	if ! have_cmd netstat; then
		printf '%s\n' "unknown (netstat unavailable)"
		return 0
	fi
	dns53="$(netstat -nlp 2>/dev/null | awk '$0 ~ /:53[[:space:]]/ { print }')"
	if [ -z "${dns53}" ]; then
		printf '%s\n' "not listening"
		return 0
	fi
	printf '%s\n' "${dns53}" | awk '
		function owner(i, field) {
			for (i = NF; i >= 1; i--) {
				field = $i
				if (field ~ /^[0-9]+\/[^[:space:]]+$/) return field
			}
			return "unknown"
		}
		$0 ~ /^(tcp)6?[[:space:]]+/ { tcp = tcp ? tcp ", " owner() : owner() }
		$0 ~ /^(udp)6?[[:space:]]+/ { udp = udp ? udp ", " owner() : owner() }
		END {
			if (tcp != "" && udp != "") print "TCP " tcp "; UDP " udp
			else if (tcp != "") print "TCP " tcp
			else if (udp != "") print "UDP " udp
			else print "unknown"
		}
	'
}

status_selected_branch() {
	local branch
	branch="$(conf_value INSTALLER_BRANCH 2>/dev/null)"
	printf '%s\n' "${branch:-unknown}"
}

status_webui_address() {
	local address host port
	address="$(awk '
		/^[[:space:]]*address:[[:space:]]*/ {
			sub(/^[[:space:]]*address:[[:space:]]*/, "")
			gsub(/^"|"$/, "")
			print
			exit
		}
	' "${YAML_FILE}" 2>/dev/null)"
	port="$(agh_web_port 2>/dev/null)"
	if [ -n "${address}" ]; then
		printf '%s\n' "${address}${port:+ (port ${port})}"
		return 0
	fi
	if have_cmd nvram; then
		host="$(nvram get lan_ipaddr 2>/dev/null)"
	else
		host=""
	fi
	[ -n "${port}" ] && printf '%s\n' "${host:-router}:${port}" || printf '%s\n' "unknown"
}

status() {
	local count monitor_count monitor_state service_state
	count="$(pidof AdGuardHome 2>/dev/null | wc -w)"
	monitor_count="$(status_monitor_count)"
	if [ "${count}" -gt 0 ]; then
		service_state="running"
	else
		service_state="stopped"
	fi
	case "${monitor_count}" in
		0) monitor_state="stopped" ;;
		1) monitor_state="running (1 process)" ;;
		*) monitor_state="running (${monitor_count} processes)" ;;
	esac

	printf '%s\n' "AdGuardHome Installer Status"
	status_line "AdGuardHome service state" "${service_state}"
	status_line "Monitor process state" "${monitor_state}"
	status_line "AdGuardHome PID count" "${count}"
	status_line "Port 53 ownership" "$(status_port53_ownership)"
	status_line "AdGuardHome version" "$(status_adguardhome_version)"
	status_line "Installer version" "$(status_installer_version)"
	status_line "Selected branch" "$(status_selected_branch)"
	status_line "WebUI address/port" "$(status_webui_address)"
	status_line "dnsmasq handoff state" "$(status_dnsmasq_handoff_state)"
	status_line "Last startup result" "$(status_last_startup_result)"
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
			# Newer firmware may provide descriptor-capable flock; older releases
			# continue to use the legacy mkdir lock below.
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
			# Prefer flock when the installed implementation supports descriptor
			# locking, with mkdir retained as the compatibility fallback.
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
		agh_log info adguardhome_run_execute "state=service action=${action} reason=service_wait result=completed runtime=${runtime}"
	else
		agh_log warning adguardhome_run_execute "state=service action=${action} reason=service_wait result=timeout runtime=${runtime}"
	fi
	return "${status}"
}

adguardhome_run_flock() {
	local action lock_dir lock_file owner pid_file saved_traps status
	action="$1"
	lock_dir="/tmp/AdGuardHome"
	lock_file="${lock_dir}.lock"
	pid_file="${lock_dir}/pid"
	if adguardhome_run_legacy_mkdir_active; then
		owner="$(sed -n '1p' "${pid_file}" 2>/dev/null)"
		agh_log warning adguardhome_run_flock "state=locked action=${action} reason=active_lock result=duplicate_lock owner=${owner:-unknown}"
		return 1
	fi
	if ! mkdir -p "${lock_dir}"; then
		agh_log error adguardhome_run_flock "state=lock action=${action} reason=mkdir_failed result=create_lock_failed path=${lock_dir}"
		return 1
	fi
	exec 9>"${lock_file}" || return 1
	if [ "${action}" = "stop_adguardhome" ]; then
		if ! flock 9; then
			agh_log error adguardhome_run_flock "state=lock action=${action} reason=flock_failed result=lock_failed lock=flock"
			exec 9>&-
			return 1
		fi
	elif ! flock -n 9; then
		owner="$(sed -n '1p' "${pid_file}" 2>/dev/null)"
		agh_log warning adguardhome_run_flock "state=locked action=${action} reason=active_lock result=duplicate_lock owner=${owner:-unknown}"
		exec 9>&-
		return 1
	fi
	saved_traps="$(trap)"
	trap 'adguardhome_run_flock_cleanup "${pid_file}"; adguardhome_run_flock_restore_traps "${saved_traps}"; exit 1' HUP INT QUIT ABRT TERM TSTP
	trap 'status="$?"; adguardhome_run_flock_cleanup "${pid_file}"; adguardhome_run_flock_restore_traps "${saved_traps}"; exit "${status}"' EXIT
	rm -f "${pid_file}"
	adguardhome_run_execute "${action}" "${pid_file}" "$$"
	status="$?"
	adguardhome_run_flock_cleanup "${pid_file}"
	adguardhome_run_flock_restore_traps "${saved_traps}"
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

adguardhome_run_flock_restore_traps() {
	local saved_traps
	saved_traps="$1"
	trap - EXIT HUP INT QUIT ABRT TERM TSTP
	[ -n "${saved_traps}" ] && eval "${saved_traps}"
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
	local action lock_dir pid pid_file status
	action="$1"
	lock_dir="/tmp/AdGuardHome"
	pid_file="${lock_dir}/pid"
	if (mkdir "${lock_dir}") 2>/dev/null || { [ -e "${pid_file}" ] && [ -n "$(sed -n '2p' "${pid_file}" 2>/dev/null)" ]; } || { [ "${action}" = "stop_adguardhome" ]; }; then
		(
			trap 'rm -rf "${lock_dir}"; exit $?' EXIT
			{ service_wait adguardhome_run; }
			rm -rf "${lock_dir}"
		) &
		pid="$!"
		adguardhome_run_execute "${action}" "${pid_file}" "${pid}"
		status="$?"
		return "${status}"
	fi
	agh_log warning adguardhome_run_mkdir "state=locked action=${action} reason=active_lock result=duplicate_lock owner=$(sed -n '1p' "${pid_file}" 2>/dev/null)"
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
		if adguard_lan_mode; then
			return 1
		fi
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
			agh_log warning check_dns_environment "state=dns action=validate_mode reason=invalid_input result=invalid mode=${MODE}"
			return 0
			;;
	esac
	if [ "$NVCHECK" != "0" ]; then
		{ nvram commit; }
		if [ "${ADGUARDHOME_SKIP_DNSMASQ_RESTART:-}" != "1" ]; then
			{ adguard_restart_dnsmasq_if_managed; }
		fi
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

dns_handoff_is_active() {
	local HANDOFF_PID HANDOFF_START_TIME PATH_DETAILS PROCESS_START_TIME
	[ -d "${DNS_HANDOFF_DIR}" ] && [ ! -L "${DNS_HANDOFF_DIR}" ] || return 1
	PATH_DETAILS="$(ls -ldn "${DNS_HANDOFF_DIR}" 2>/dev/null)" || return 1
	printf '%s\n' "${PATH_DETAILS}" |
		awk 'NR == 1 {
			exit(substr($1, 1, 10) == "drwx------" && $3 == 0 ? 0 : 1)
		}' || return 1
	[ -f "${DNS_HANDOFF_FILE}" ] && [ ! -L "${DNS_HANDOFF_FILE}" ] || return 1
	PATH_DETAILS="$(ls -ldn "${DNS_HANDOFF_FILE}" 2>/dev/null)" || return 1
	printf '%s\n' "${PATH_DETAILS}" |
		awk 'NR == 1 {
			exit(substr($1, 1, 10) == "-rw-------" && $3 == 0 ? 0 : 1)
		}' || return 1
	IFS=' ' read -r HANDOFF_PID HANDOFF_START_TIME <"${DNS_HANDOFF_FILE}" || return 1
	case "${HANDOFF_PID}:${HANDOFF_START_TIME}" in
		*[!0-9:]* | *: | :*) return 1 ;;
	esac
	[ "${HANDOFF_PID}" -gt 1 ] || return 1
	kill -0 "${HANDOFF_PID}" 2>/dev/null || return 1
	awk '
		$1 == "Uid:" {
			exit($2 == 0 && $3 == 0 && $4 == 0 && $5 == 0 ? 0 : 1)
		}
		END {
			if (NR == 0) exit 1
		}
	' "/proc/${HANDOFF_PID}/status" 2>/dev/null || return 1
	PROCESS_START_TIME="$(awk '{
		sub(/^.*\) /, "")
		print $20
	}' "/proc/${HANDOFF_PID}/stat" 2>/dev/null)" || return 1
	case "${PROCESS_START_TIME}" in
		"" | *[!0-9]*) return 1 ;;
	esac
	[ "${PROCESS_START_TIME}" = "${HANDOFF_START_TIME}" ]
}

dnsmasq_resolv_conf_cleanup() {
	if { ! resolv_conf_uses_rom && resolv_conf_is_tmp_mount; }; then {
		umount /tmp/resolv.conf 2>/dev/null
	}; fi
}

dnsmasq_params() {
	local CONFIG IPV6_REVERSE NET_ADDR NET_ADDR6 LAN_IF LAN_IF_SDN NIVARS NDVARS RC_SUPPORT DHCP_IF
	if adguard_lan_mode && [ "$(conf_value ADGUARD_DNSMASQ_MODE 2>/dev/null)" = "disabled" ] && ! dns_handoff_is_active; then
		agh_log info dnsmasq "state=skip reason=lan_mode_dnsmasq_disabled"
		return 0
	fi
	dnsmasq_resolv_conf_cleanup
	case "$(pidof "${PROCS}" 2>/dev/null | wc -w)" in
		0)
			dns_handoff_is_active || return 0
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
	if { ! resolv_conf_uses_rom && [ "$(conf_value ADGUARD_LOCAL)" = "YES" ]; }; then {
		mount -o bind /rom/etc/resolv.conf /tmp/resolv.conf
	}; fi
	if ! adguard_lan_mode; then
		IPSET_REFRESH_FROM_DNSMASQ="1"
		IPSet_Refresh "${CONFIG}"
	fi
}

dnsmasq_action_handler() {
	if adguard_lan_mode && ! adguard_dnsmasq_running && ! dns_handoff_is_active; then
		case "$(conf_value ADGUARD_DNSMASQ_MODE 2>/dev/null)" in
			enabled) ;;
			*)
				dnsmasq_resolv_conf_cleanup
				agh_log info dnsmasq "state=skip reason=lan_mode_dnsmasq_not_running"
				return 0
				;;
		esac
	fi
	if [ -n "${1:-}" ]; then
		dnsmasq_params "${1}"
	else
		dnsmasq_params
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

netcheck_config() {
	local is_set value
	eval "is_set=\${$1_SET:-}"
	eval "value=\${$1:-}"
	if [ -n "${is_set}" ] && [ -n "${value}" ]; then
		printf '%s\n' "${value}"
		return 0
	fi
	value="$(conf_value "$1")"
	if [ -n "${value}" ]; then
		printf '%s\n' "${value}"
		return 0
	fi
	printf '%s\n' "$2"
}

netcheck_dns_ok() {
	local dns_server host
	dns_server="$1"
	shift
	for host in "$@"; do
		[ -n "${host}" ] || continue
		if nslookup "${host}" "${dns_server}" >/dev/null 2>&1; then
			return 0
		fi
	done
	return 1
}

netcheck_http_ok() {
	local host
	for host in "$@"; do
		[ -n "${host}" ] || continue
		if http_probe "http://${host}" >/dev/null 2>&1; then
			return 0
		fi
	done
	return 1
}

netcheck_ping_ok() {
	local host
	for host in "$@"; do
		[ -n "${host}" ] || continue
		if ping -q -w3 -c1 "${host}" >/dev/null 2>&1; then
			return 0
		fi
	done
	return 1
}

netcheck_legacy() {
	local host livecheck timewait
	livecheck="0"
	timewait="0"
	until system_time_ready; do
		if [ "${timewait}" -ge "300" ]; then
			agh_log warning netcheck "state=netcheck action=wait_system_time reason=ntp_not_ready result=timeout timeout=300"
			return 1
		fi
		sleep 1s
		timewait="$((timewait + 1))"
	done
	while [ "${livecheck}" != "4" ]; do
		for host in google.com github.com snbforums.com; do
			if nslookup "${host}" 127.0.0.1 >/dev/null 2>&1; then
				return 0
			fi
			if ! ping -q -w3 -c1 "${host}" >/dev/null 2>&1; then
				continue
			fi
			if ! http_probe "http://${host}" >/dev/null 2>&1; then
				sleep 1s
				continue
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

netcheck() {
	local dns_ok dns_server hosts http_required mode ping_ok timeout waited
	mode="$(netcheck_config ADGUARD_NETCHECK_MODE "${DEFAULT_ADGUARD_NETCHECK_MODE}")"
	case "${mode}" in
		legacy | LEGACY | "")
			netcheck_legacy
			return "$?"
			;;
	esac
	dns_server="$(netcheck_config ADGUARD_NETCHECK_DNS "${DEFAULT_ADGUARD_NETCHECK_DNS}")"
	hosts="$(netcheck_config ADGUARD_NETCHECK_HOSTS "${DEFAULT_ADGUARD_NETCHECK_HOSTS}")"
	http_required="$(netcheck_config ADGUARD_NETCHECK_REQUIRE_HTTP "${DEFAULT_ADGUARD_NETCHECK_REQUIRE_HTTP}")"
	timeout="$(netcheck_config ADGUARD_NETCHECK_TIMEOUT "${DEFAULT_ADGUARD_NETCHECK_TIMEOUT}")"
	case "${timeout}" in
		"" | *[!0-9]*) timeout="300" ;;
	esac
	[ "${timeout}" -gt 0 ] || timeout="300"
	waited="0"
	until system_time_ready; do
		if [ "${waited}" -ge "${timeout}" ]; then
			agh_log warning netcheck "state=netcheck action=wait_system_time stage=time reason=ntp_not_ready result=timeout timeout=${timeout}"
			return 1
		fi
		sleep 1
		waited="$((waited + 1))"
	done
	case "${mode}" in
		lan | LAN)
			# LAN mode skips public WAN probes. Local DNS responsiveness is checked
			# separately after AdGuardHome is expected to be serving DNS.
			return 0
			;;
	esac
	# Intentionally split hosts on shell IFS so ADGUARD_NETCHECK_HOSTS stays a simple
	# space-delimited POSIX/ash setting.
	set -- ${hosts}
	if [ "$#" -eq 0 ]; then
		agh_log warning netcheck "state=netcheck action=validate_hosts stage=dns reason=no_hosts_configured result=failed"
		return 1
	fi
	dns_ok="0"
	ping_ok="0"
	if netcheck_dns_ok "${dns_server}" "$@"; then
		dns_ok="1"
	fi
	if [ "${dns_ok}" -ne 1 ] && netcheck_ping_ok "$@"; then
		ping_ok="1"
	fi
	if [ "${dns_ok}" -ne 1 ] && [ "${ping_ok}" -ne 1 ]; then
		agh_log warning netcheck "state=netcheck action=resolve_hosts stage=dns reason=lookup_failed result=failed dns=${dns_server} hosts=${hosts}"
		agh_log warning netcheck "state=netcheck action=ping_hosts stage=ping reason=ping_failed result=failed hosts=${hosts}"
		return 1
	fi
	case "${http_required}" in
		YES | yes | Yes)
			if netcheck_http_ok "$@"; then
				return 0
			fi
			agh_log warning netcheck "state=netcheck action=http_probe stage=http reason=http_failed result=failed hosts=${hosts}"
			;;
		*) return 0 ;;
	esac
	return 1
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
	[ "$(canonical_path /etc/resolv.conf 2>/dev/null)" = "/rom/etc/resolv.conf" ]
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

proc_config() {
	local is_set value
	eval "is_set=\${$1_SET:-}"
	eval "value=\${$1:-}"
	if [ -n "${is_set}" ] && [ -n "${value}" ]; then
		printf '%s\n' "${value}"
		return 0
	fi
	value="$(conf_value "$1")"
	if [ -n "${value}" ]; then
		printf '%s\n' "${value}"
		return 0
	fi
	printf '%s\n' "$2"
}

proc_optimizations() {
	local enabled profile
	enabled="$(proc_config ADGUARD_PROC_OPTIMIZE "${DEFAULT_ADGUARD_PROC_OPTIMIZE}")"
	profile="$(proc_config ADGUARD_PROC_PROFILE "${DEFAULT_ADGUARD_PROC_PROFILE}")"
	case "${enabled}" in
		YES | yes | Yes | ON | on | On | TRUE | true | True | 1) ;;
		*)
			agh_log info proc_optimizations "state=proc_optimize action=skip reason=disabled result=skipped enabled=${enabled} profile=${profile}"
			return 0
			;;
	esac

	# Profile documentation:
	# off: no proc/sysctl values are changed.
	# safe: /proc/sys/net/core/rmem_max=4194304, /proc/sys/net/core/wmem_max=1048576.
	# balanced: safe values plus /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_max_retrans=240.
	# aggressive: balanced values plus /proc/sys/kernel/pid_max=4194304,
	#   /proc/sys/vm/overcommit_memory=2, /proc/sys/vm/swappiness=60,
	#   /proc/sys/vm/overcommit_ratio=50, /proc/sys/net/ipv4/icmp_ratelimit=0,
	#   /proc/sys/net/ipv4/neigh/default/gc_thresh1=256,
	#   /proc/sys/net/ipv4/neigh/default/gc_thresh2=1024,
	#   /proc/sys/net/ipv4/neigh/default/gc_thresh3=2048, and when IPv6 is
	#   configured, /proc/sys/net/ipv6/icmp/ratelimit=0,
	#   /proc/sys/net/ipv6/neigh/default/gc_thresh1=256,
	#   /proc/sys/net/ipv6/neigh/default/gc_thresh2=1024,
	#   /proc/sys/net/ipv6/neigh/default/gc_thresh3=2048.
	case "${profile}" in
		off)
			agh_log info proc_optimizations "state=proc_optimize action=skip reason=profile_off result=skipped profile=${profile}"
			return 0
			;;
		safe | balanced | aggressive) ;;
		*)
			agh_log warning proc_optimizations "state=proc_optimize action=validate_profile reason=invalid_profile result=skipped profile=${profile}"
			return 0
			;;
	esac

	proc_write "4194304" "/proc/sys/net/core/rmem_max"
	proc_write "1048576" "/proc/sys/net/core/wmem_max"
	case "${profile}" in
		balanced | aggressive)
			proc_write "240" "/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_max_retrans"
			;;
	esac
	case "${profile}" in
		aggressive)
			proc_write "4194304" "/proc/sys/kernel/pid_max"
			proc_write "2" "/proc/sys/vm/overcommit_memory"
			proc_write "60" "/proc/sys/vm/swappiness"
			proc_write "50" "/proc/sys/vm/overcommit_ratio"
			proc_write "0" "/proc/sys/net/ipv4/icmp_ratelimit"
			proc_write "256" "/proc/sys/net/ipv4/neigh/default/gc_thresh1"
			proc_write "1024" "/proc/sys/net/ipv4/neigh/default/gc_thresh2"
			proc_write "2048" "/proc/sys/net/ipv4/neigh/default/gc_thresh3"
			if [ -n "$(nvram get ipv6_service 2>/dev/null)" ]; then
				proc_write "0" "/proc/sys/net/ipv6/icmp/ratelimit"
				proc_write "256" "/proc/sys/net/ipv6/neigh/default/gc_thresh1"
				proc_write "1024" "/proc/sys/net/ipv6/neigh/default/gc_thresh2"
				proc_write "2048" "/proc/sys/net/ipv6/neigh/default/gc_thresh3"
			fi
			;;
	esac
	return 0
}

proc_write() {
	local old_value target value
	value="$1"
	target="$2"
	if [ ! -e "${target}" ]; then
		agh_log warning proc_write "state=proc_optimize action=write target=${target} new_value=${value} reason=missing result=failed"
		return 0
	fi
	if ! IFS= read -r old_value <"${target}"; then
		old_value=""
		agh_log warning proc_write "state=proc_optimize action=read target=${target} new_value=${value} reason=read_failed result=failed"
	fi
	agh_log info proc_write "state=proc_optimize action=write target=${target} old_value=${old_value} new_value=${value}"
	if ! printf '%s' "${value}" >"${target}" 2>/dev/null; then
		agh_log warning proc_write "state=proc_optimize action=write target=${target} old_value=${old_value} new_value=${value} result=failed"
	fi
	return 0
}
netcheck_lan_dns() {
	# Ignore public DNS overrides in LAN mode; this probe is only for the
	# local AdGuardHome listener after the process has started.
	if ! netcheck_dns_ok "127.0.0.1" localhost; then
		agh_log warning netcheck_lan_dns "state=netcheck action=resolve_hosts stage=dns reason=lookup_failed result=failed mode=lan dns=127.0.0.1 hosts=localhost"
		return 1
	fi
	return 0
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
	local maxwait
	if [ -n "$2" ]; then
		maxwait="$2"
	elif [ "$1" = "netcheck" ]; then
		maxwait="$(netcheck_config ADGUARD_NETCHECK_TIMEOUT "${DEFAULT_ADGUARD_NETCHECK_TIMEOUT}")"
	else
		maxwait="300"
	fi
	case "${maxwait}" in
		"" | *[!0-9]*) maxwait="300" ;;
	esac
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
			local elapsed interval status
			elapsed="0"
			interval="10"
			status="1"
			while [ "${elapsed}" -le "${maxwait}" ]; do
				if [ "$(nvram get success_start_service)" = '1' ]; then
					SERVICE_WAIT_TERMINAL_FAILURE="0"
					"$1"
					status="$?"
					if [ "${status}" -eq 0 ] || [ "${SERVICE_WAIT_TERMINAL_FAILURE}" -eq 1 ]; then break; fi
				fi
				sleep "${interval}s"
				elapsed="$((elapsed + interval))"
			done
		}
		{
			trap - HUP INT QUIT ABRT TERM TSTP
			if [ "${SERVICE_WAIT_TERMINAL_FAILURE:-0}" -eq 1 ]; then
				return "${status}"
			elif [ "${elapsed}" -gt "${maxwait}" ]; then
				if [ "$(nvram get success_start_service 2>/dev/null)" != '1' ]; then
					agh_log warning service_wait "state=service_wait action=wait_service_ready stage=service_readiness reason=success_start_service_not_ready result=timeout timeout=${maxwait}"
				elif [ "$1" = "netcheck" ]; then
					agh_log warning service_wait "state=service_wait action=run_check stage=service_readiness reason=netcheck_failed result=timeout timeout=${maxwait}"
				fi
				return 1
			else
				return 0
			fi
		}
	) &
	local PID="$!"
	wait "${PID}"
	return "$?"
}

start_adguardhome() {
	local IPSET_START_FAILURE_SAFE IPSET_START_RESTARTED IPSET_START_STOPPED LOWER_SCRIPT_STATUS
	IPSET_START_FAILURE_SAFE="0"
	IPSET_START_RESTARTED="0"
	IPSET_START_STOPPED="0"
	SERVICE_WAIT_TERMINAL_FAILURE="0"
	if adguard_lan_mode; then
		if ! IPSet_Disable_Managed; then
			agh_log error start_adguardhome "state=starting action=disable_managed_ipset result=failed reason=lan_mode_remove_failed"
			SERVICE_WAIT_TERMINAL_FAILURE="1"
			return 1
		fi
	elif ! IPSet_Setup_For_Start; then
		if [ "${IPSET_START_FAILURE_SAFE}" -ne 1 ]; then
			agh_log error start_adguardhome "state=starting action=prepare_ipset reason=stale_mapping_risk result=failed failure_safe=0"
			if [ "${IPSET_START_STOPPED}" -eq 1 ]; then
				IPSet_Start_Restore || true
			fi
			SERVICE_WAIT_TERMINAL_FAILURE="1"
			return 1
		fi
		agh_log warning start_adguardhome "state=starting action=prepare_ipset reason=optional_setup_failed result=disabled optional=1"
		if [ "${IPSET_START_STOPPED}" -eq 1 ] && IPSet_Start_Restore; then
			IPSET_START_RESTARTED="1"
		fi
	fi
	if [ "${IPSET_START_RESTARTED}" -eq 0 ]; then
		case "$(pidof "${PROCS}" 2>/dev/null | wc -w)" in
			0)
				lower_script start
				LOWER_SCRIPT_STATUS="$?"
				;;
			*)
				lower_script restart
				LOWER_SCRIPT_STATUS="$?"
				;;
		esac
		if [ "${LOWER_SCRIPT_STATUS}" -ne 0 ]; then
			SERVICE_WAIT_TERMINAL_FAILURE="1"
			return "${LOWER_SCRIPT_STATUS}"
		fi
	fi
	for db in stats.db sessions.db; do {
		if [ "$(canonical_path "/tmp/${db}" 2>/dev/null)" != "$(canonical_path "${WORK_DIR}/data/${db}" 2>/dev/null)" ]; then {
			ln -s "${WORK_DIR}/data/${db}" "/tmp/${db}" >/dev/null 2>&1
		}; fi
	}; done
	if { service_wait netcheck; }; then
		return "0"
	else
		return "1"
	fi
}

start_monitor() {
	local BINARY_UNAVAILABLE_LOGGED MONITOR_BINARY_RETRY_INTERVAL MONITOR_ELAPSED MONITOR_HEALTHCHECK_INTERVAL MONITOR_HEALTHCHECK_TIMEOUT MONITOR_RECOVERY_RETRY_INTERVAL MONITOR_SLEEP_INTERVAL MONITOR_STATE
	MONITOR_BINARY_RETRY_INTERVAL="10"
	MONITOR_HEALTHCHECK_INTERVAL="300"
	MONITOR_HEALTHCHECK_TIMEOUT="150"
	MONITOR_RECOVERY_RETRY_INTERVAL="10"
	MONITOR_SLEEP_INTERVAL="10"
	MONITOR_STATE="running"
	trap '' HUP INT QUIT ABRT TERM TSTP
	trap 'MONITOR_STATE="stop"' USR1
	trap 'MONITOR_STATE="restart"' USR2
	{ service_wait netcheck; }
	agh_log info start_monitor "state=${MONITOR_STATE} action=start_monitor reason=init result=started"
	agh_log info start_monitor "state=${MONITOR_STATE} action=configure_healthcheck reason=init result=enabled interval=${MONITOR_HEALTHCHECK_INTERVAL}"
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
			agh_log info start_monitor "state=stop action=stop_monitor reason=signal_USR1 result=stopping"
			trap - HUP INT QUIT ABRT USR1 USR2 TERM TSTP
			{ adguardhome_run stop_adguardhome; }
			break
		fi
		if [ ! -x "${ADGUARDHOME_BINARY}" ]; then
			if [ -z "${BINARY_UNAVAILABLE_LOGGED}" ]; then
				agh_log warning start_monitor "state=${MONITOR_STATE} action=check_binary reason=missing_executable result=unavailable retry=${MONITOR_BINARY_RETRY_INTERVAL}"
				BINARY_UNAVAILABLE_LOGGED="1"
			fi
			sleep "${MONITOR_BINARY_RETRY_INTERVAL}s"
			continue
		fi
		if [ -n "${BINARY_UNAVAILABLE_LOGGED}" ]; then
			agh_log info start_monitor "state=${MONITOR_STATE} action=check_binary reason=executable_restored result=available"
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
						agh_log warning start_monitor "state=running action=check_process reason=process_missing result=dead retry=${MONITOR_RECOVERY_RETRY_INTERVAL}"
						unset MONITOR_ELAPSED
						sleep "${MONITOR_RECOVERY_RETRY_INTERVAL}s"
						;;
					1)
						if [ "${MONITOR_ELAPSED}" -ge "${MONITOR_HEALTHCHECK_INTERVAL}" ]; then
							MONITOR_ELAPSED="0"
							case "$(netcheck_config ADGUARD_NETCHECK_MODE "${DEFAULT_ADGUARD_NETCHECK_MODE}")" in
								lan | LAN)
									if { ! service_wait netcheck_lan_dns "${MONITOR_HEALTHCHECK_TIMEOUT}"; }; then
										agh_log warning start_monitor "state=running action=healthcheck reason=local_dns_timeout result=not_responding timeout=${MONITOR_HEALTHCHECK_TIMEOUT}"
										unset MONITOR_ELAPSED
									fi
									;;
								*)
									if { ! service_wait netcheck "${MONITOR_HEALTHCHECK_TIMEOUT}"; }; then
										agh_log warning start_monitor "state=running action=healthcheck reason=netcheck_timeout result=not_responding timeout=${MONITOR_HEALTHCHECK_TIMEOUT}"
										unset MONITOR_ELAPSED
									fi
									;;
							esac
						else
							MONITOR_ELAPSED="$((MONITOR_ELAPSED + MONITOR_SLEEP_INTERVAL))"
						fi
						if [ -n "${MONITOR_ELAPSED}" ]; then sleep "${MONITOR_SLEEP_INTERVAL}s"; fi
						;;
					*)
						agh_log warning start_monitor "state=running action=check_process reason=duplicate_process result=multiple_instances retry=${MONITOR_RECOVERY_RETRY_INTERVAL}"
						unset MONITOR_ELAPSED
						sleep "${MONITOR_RECOVERY_RETRY_INTERVAL}s"
						;;
				esac
				;;
			"stop")
				agh_log info start_monitor "state=stop action=stop_monitor reason=signal_USR1 result=stopping"
				trap - HUP INT QUIT ABRT USR1 USR2 TERM TSTP
				{ adguardhome_run stop_adguardhome; }
				break
				;;
			"restart")
				agh_log info start_monitor "state=restart action=restart_adguardhome reason=signal_USR2 result=restarting"
				unset MONITOR_ELAPSED
				MONITOR_STATE="running"
				;;
		esac
	done
}

stop_adguardhome() {
	local STOP_STATUS
	STOP_STATUS="0"
	case "$(pidof "${PROCS}" 2>/dev/null | wc -w)" in
		0)
			:
			;;
		*)
			if ! lower_script stop && ! lower_script kill; then
				STOP_STATUS="1"
			fi
			;;
	esac
	if [ "$(pidof "${PROCS}" 2>/dev/null | wc -w)" -ne 0 ]; then
		agh_log error stop_adguardhome "state=stopping action=stop_process reason=process_still_active result=active process=${PROCS}"
		STOP_STATUS="1"
	fi
	if [ "${ADGUARDHOME_SKIP_DNSMASQ_RESTART:-}" != "1" ]; then
		if ! adguard_restart_dnsmasq_if_managed; then
			agh_log error stop_adguardhome "state=stopping action=restart_dnsmasq reason=service_restart_failed result=failed process=${PROCS}"
			STOP_STATUS="1"
		fi
	fi
	for db in stats.db sessions.db; do {
		if [ "$(canonical_path "/tmp/${db}" 2>/dev/null)" = "$(canonical_path "${WORK_DIR}/data/${db}" 2>/dev/null)" ]; then {
			rm "/tmp/${db}" >/dev/null 2>&1
		}; fi
	}; done
	if ! service_wait netcheck; then
		STOP_STATUS="1"
	fi
	return "${STOP_STATUS}"
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
	if [ -f "${TARGET}" ] || [ -L "${TARGET}" ]; then
		NOW="$(/bin/date -u '+%s' 2>/dev/null)"
		SCRIPT_TIME="$(/bin/date -u -r "${MID_SCRIPT}" '+%s' 2>/dev/null)"
		case "${NOW}:${SCRIPT_TIME}" in
			*[!0-9:]* | "":* | *:)
				return 1
				;;
		esac
		if [ "${NOW}" -lt "${SCRIPT_TIME}" ] && { ! system_time_ready; }; then
			SCRIPT_TIME_TEXT="$(/bin/date -u -r "${MID_SCRIPT}" '+%Y-%m-%d %H:%M:%S')"
			{ /bin/date -u -s "${SCRIPT_TIME_TEXT}"; }
		else
			{ touch "${MID_SCRIPT}"; }
		fi
	fi
}

# IPSET integration helpers

IPSet_Collect_Dnsmasq() {
	local CONFIG
	for CONFIG in "$@" \
		/etc/dnsmasq.conf \
		/etc/dnsmasq-[0-9]*.conf \
		/jffs/configs/dnsmasq.conf.add \
		/jffs/configs/dnsmasq.d/*.conf \
		/jffs/addons/x3mRouting/*.conf \
		/jffs/configs/domain_vpn_routing/*.conf \
		/jffs/addons/wireguard/*.conf; do
		[ -f "${CONFIG}" ] || continue
		awk '
			function strip_comment(line,    ch, i, next_ch, quote) {
				quote = ""
				for (i = 1; i <= length(line); i++) {
					ch = substr(line, i, 1)
					next_ch = substr(line, i + 1, 1)
					if (quote != "") {
						if (ch == "\\" && next_ch != "") {
							i++
						} else if (ch == quote) {
							quote = ""
						}
					} else if (ch == "\"" || ch == "\047") {
						quote = ch
					} else if (ch == "#" && substr(line, i - 1, 1) == "/" && next_ch == "/") {
						continue
					} else if (ch == "#") {
						return substr(line, 1, i - 1)
					}
				}
				return line
			}
			/^[[:space:]]*#/ { next }
			/^[[:space:]]*ipset=/ {
				line = strip_comment($0)
				sub(/^[[:space:]]*ipset=/, "", line)
				sub(/[[:space:]]+$/, "", line)
				n = split(line, part, "/")
				if (n < 3 || part[n] == "") next
				domains = ""
				catch_all = 0
				for (i = 2; i < n; i++) {
					if (part[i] == "#") {
						catch_all = 1
						continue
					}
					if (part[i] == "") continue
					if (domains != "") domains = domains ","
					domains = domains part[i]
				}
				if (catch_all) print "/" part[n]
				else if (domains != "") print domains "/" part[n]
			}
		' "${CONFIG}" || return 1
	done
}

IPSet_Collect_Yaml() {
	[ -f "${YAML_FILE}" ] || return 0
	awk '
		function indentation(line,    text) {
			text = line
			sub(/[^[:space:]].*$/, "", text)
			return length(text)
		}
		function strip_comment(line,    ch, i, next_ch, previous_ch, quote) {
			quote = ""
			for (i = 1; i <= length(line); i++) {
				ch = substr(line, i, 1)
				next_ch = substr(line, i + 1, 1)
				previous_ch = substr(line, i - 1, 1)
				if (quote == "\"") {
					if (ch == "\\" && next_ch != "") {
						i++
					} else if (ch == quote) {
						quote = ""
					}
				} else if (quote == "\047") {
					if (ch == quote && next_ch == quote) {
						i++
					} else if (ch == quote) {
						quote = ""
					}
				} else if (ch == "\"" || ch == "\047") {
					quote = ch
				} else if (ch == "#" && (i == 1 || previous_ch ~ /[[:space:]]/)) {
					return substr(line, 1, i - 1)
				}
			}
			return line
		}
		function decode_quoted(value, quote,    ch, decoded, i, next_ch, rest) {
			decoded = ""
			decode_ok = 0
			for (i = 2; i <= length(value); i++) {
				ch = substr(value, i, 1)
				next_ch = substr(value, i + 1, 1)
				if (quote == "\"" && ch == "\\") {
					if (next_ch == "\"" || next_ch == "\\" || next_ch == "/" || next_ch == " ") {
						decoded = decoded next_ch
						i++
						continue
					}
					return ""
				}
				if (quote == "\047" && ch == quote && next_ch == quote) {
					decoded = decoded quote
					i++
					continue
				}
				if (ch == quote) {
					rest = substr(value, i + 1)
					if (rest !~ /^[[:space:]]*(#.*)?$/) return ""
					decode_ok = 1
					return decoded
				}
				decoded = decoded ch
			}
			return ""
		}
		function plain_is_typed(value) {
			if (value ~ /^(~|null|Null|NULL|true|True|TRUE|false|False|FALSE)$/) return 1
			if (value ~ /^[-+]?([0-9]+|0o[0-7]+|0x[0-9a-fA-F]+)$/) return 1
			if (value ~ /^[-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?$/) return 1
			if (value ~ /^[-+]?(\.inf|\.Inf|\.INF)$/ || value ~ /^(\.nan|\.NaN|\.NAN)$/) return 1
			return 0
		}
		function plain_is_collection(value,    first) {
			first = substr(value, 1, 1)
			if (first == "{" || first == "[" || first == "?") return 1
			if (value ~ /^-([[:space:]]|$)/) return 1
			if (value ~ /:([[:space:]]|$)/) return 1
			return 0
		}
		function plain_is_block_scalar(value,    first) {
			first = substr(value, 1, 1)
			return first == "|" || first == ">"
		}
		function emit(line,    first, quoted) {
			line = strip_comment(line)
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
			first = substr(line, 1, 1)
			quoted = first == "\"" || first == "\047"
			if (first ~ /^[&*!]$/) exit 1
			if (quoted) {
				line = decode_quoted(line, first)
				if (!decode_ok) exit 1
			}
			if (quoted && line == "") exit 1
			if (!quoted && (plain_is_typed(line) || plain_is_collection(line) || plain_is_block_scalar(line))) exit 1
			if (line != "") print line
		}
		function flow_reset() {
			flow_entry = ""
			flow_quote = ""
			flow_escaped_break = 0
			flow_has_entry = 0
			flow_entry_count = 0
			flow_after_comma = 0
		}
		function flow_consume(line,    ch, i, next_ch, previous_ch, rest) {
			sub(/^[[:space:]]+/, "", line)
			flow_escaped_break = 0
			for (i = 1; i <= length(line); i++) {
				ch = substr(line, i, 1)
				next_ch = substr(line, i + 1, 1)
				previous_ch = substr(line, i - 1, 1)
				if (flow_quote == "\"") {
					if (ch == "\\" && next_ch != "") {
						flow_entry = flow_entry ch next_ch
						i++
					} else if (ch == "\\") {
						flow_escaped_break = 1
					} else {
						flow_entry = flow_entry ch
					}
					if (ch == flow_quote) {
						flow_quote = ""
					}
				} else if (flow_quote == "\047") {
					flow_entry = flow_entry ch
					if (ch == flow_quote && next_ch == flow_quote) {
						flow_entry = flow_entry next_ch
						i++
					} else if (ch == flow_quote) {
						flow_quote = ""
					}
				} else if (ch == "\"" || ch == "\047") {
					flow_quote = ch
					flow_entry = flow_entry ch
					flow_has_entry = 1
				} else if (ch == "#" && (i == 1 || previous_ch ~ /[[:space:]]/)) {
					return 0
				} else if (ch == ",") {
					if (!flow_has_entry) exit 1
					emit(flow_entry)
					flow_entry = ""
					flow_has_entry = 0
					flow_entry_count++
					flow_after_comma = 1
				} else if (ch == "]") {
					rest = substr(line, i + 1)
					if (rest !~ /^[[:space:]]*(#.*)?$/) exit 1
					if (flow_has_entry) {
						emit(flow_entry)
						flow_entry_count++
					} else if (flow_after_comma && flow_entry_count == 0) {
						exit 1
					}
					flow_entry = ""
					return 1
				} else {
					flow_entry = flow_entry ch
					if (ch !~ /[[:space:]]/) flow_has_entry = 1
				}
			}
			if (!flow_escaped_break) {
				sub(/[[:space:]]+$/, "", flow_entry)
				if (flow_entry != "") flow_entry = flow_entry " "
			}
			return 0
		}
		/^(dns|\047dns\047|"dns"):[[:space:]]*(&[^][{},[:space:]]+[[:space:]]*)?(#.*)?$/ { in_dns = 1; child_indent = 0; next }
		/^(dns|\047dns\047|"dns"):/ { exit 1 }
		in_flow {
			if (flow_consume($0)) in_flow = 0
			next
		}
		in_dns && /^[^[:space:]]/ { in_dns = in_ipset = 0 }
		in_dns && /^[[:space:]]*($|#)/ { next }
		in_dns && !child_indent { child_indent = indentation($0) }
		in_dns && indentation($0) == child_indent && substr($0, child_indent + 1) ~ /^(ipset|\047ipset\047|"ipset"):[[:space:]]*(#.*)?$/ {
			in_ipset = 1
			next
		}
		in_dns && indentation($0) == child_indent && substr($0, child_indent + 1) ~ /^(ipset|\047ipset\047|"ipset"):[[:space:]]*\[/ {
			line = substr($0, child_indent + 1)
			sub(/^(ipset|\047ipset\047|"ipset"):[[:space:]]*\[/, "", line)
			flow_reset()
			if (!flow_consume(line)) in_flow = 1
			next
		}
		in_dns && indentation($0) == child_indent && substr($0, child_indent + 1) ~ /^(ipset|\047ipset\047|"ipset"):[[:space:]]*(~|null|Null|NULL)[[:space:]]*(#.*)?$/ { next }
		in_dns && indentation($0) == child_indent && substr($0, child_indent + 1) ~ /^(ipset|\047ipset\047|"ipset"):[[:space:]]*/ { exit 1 }
		in_ipset && indentation($0) >= child_indent && substr($0, indentation($0) + 1) ~ /^-([[:space:]]|$)/ {
			line = substr($0, indentation($0) + 1)
			sub(/^-[[:space:]]*/, "", line)
			value = strip_comment(line)
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
			if (value == "") exit 1
			emit(line)
			next
		}
		in_ipset { in_ipset = 0 }
		END { if (in_flow || flow_quote != "") exit 1 }
	' "${YAML_FILE}"
}

IPSet_Current_File() {
	[ -f "${YAML_FILE}" ] || return 0
	awk '
		function indentation(line,    text) { text = line; sub(/[^[:space:]].*$/, "", text); return length(text) }
		function scalar(value,    ch, decoded, i, next_ch, quote, rest) {
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
			quote = substr(value, 1, 1)
			if (quote != "\"" && quote != "\047") {
				sub(/[[:space:]]+#.*$/, "", value)
				gsub(/[[:space:]]+$/, "", value)
				if (value ~ /^(~|null|Null|NULL)$/) return ""
				return value
			}
			decoded = ""
			for (i = 2; i <= length(value); i++) {
				ch = substr(value, i, 1)
				next_ch = substr(value, i + 1, 1)
				if (quote == "\"" && ch == "\\") {
					if (next_ch == "\"" || next_ch == "\\" || next_ch == "/" || next_ch == " ") {
						decoded = decoded next_ch
						i++
						continue
					}
					exit 1
				}
				if (quote == "\047" && ch == quote && next_ch == quote) {
					decoded = decoded quote
					i++
					continue
				}
				if (ch == quote) {
					rest = substr(value, i + 1)
					if (rest !~ /^[[:space:]]*(#.*)?$/) exit 1
					return decoded
				}
				decoded = decoded ch
			}
			exit 1
		}
		function block_start(value,    indicators) {
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
			sub(/[[:space:]]+#.*$/, "", value)
			gsub(/[[:space:]]+$/, "", value)
			if (value !~ /^[|>]([1-9][+-]?|[+-][1-9]?)?$/) return 0
			indicators = substr(value, 2)
			block_explicit_indent = 0
			if (indicators ~ /[1-9]/) {
				gsub(/[^1-9]/, "", indicators)
				block_explicit_indent = indicators + 0
			}
			block_lines = block_leading_blank = 0
			block_value = ""
			in_block = 1
			return 1
		}
		function block_fail() { in_block = 0; exit 1 }
		function block_finish() {
			in_block = 0
			if (block_lines > 1 || (block_lines && block_leading_blank)) exit 1
			print block_value
			exit
		}
		/^(dns|\047dns\047|"dns"):[[:space:]]*(&[^][{},[:space:]]+[[:space:]]*)?(#.*)?$/ { in_dns = 1; next }
		/^(dns|\047dns\047|"dns"):/ { exit 1 }
		in_block {
			if ($0 ~ /^[[:space:]]*$/) {
				if (!block_lines) block_leading_blank = 1
				next
			}
			line_indent = indentation($0)
			if (line_indent <= child_indent) block_finish()
			content_indent = block_explicit_indent ? child_indent + block_explicit_indent : line_indent
			if (line_indent < content_indent) block_fail()
			block_lines++
			if (block_lines > 1) block_fail()
			block_value = substr($0, content_indent + 1)
			next
		}
		in_dns && /^[^[:space:]]/ { exit }
		in_dns && /^[[:space:]]*($|#)/ { next }
		in_dns && !child_indent { child_indent = indentation($0) }
		in_dns && indentation($0) == child_indent && substr($0, child_indent + 1) ~ /^(ipset_file|\047ipset_file\047|"ipset_file"):[[:space:]]*/ {
			value = substr($0, child_indent + 1)
			sub(/^(ipset_file|\047ipset_file\047|"ipset_file"):[[:space:]]*/, "", value)
			if (block_start(value)) next
			print scalar(value)
			exit
		}
		END { if (in_block) block_finish() }
	' "${YAML_FILE}"
}

IPSet_Dnsmasq_Restart_After_Unlock() {
	[ "${IPSET_DNSMASQ_RESTART_PENDING:-0}" -eq 1 ] || return 0
	IPSET_DNSMASQ_RESTART_PENDING="0"
	[ "${ADGUARDHOME_SKIP_DNSMASQ_RESTART:-}" != "1" ] || return 0
	service restart_dnsmasq >/dev/null 2>&1
}

IPSet_Current_UID() {
	awk '
		$1 == "Uid:" && $3 ~ /^[0-9][0-9]*$/ {
			print $3
			FOUND = 1
			exit
		}
		END { if (!FOUND) exit 1 }
	' /proc/self/status 2>/dev/null
}

IPSet_Directory_Metadata() {
	[ ! -L "$1" ] && [ -d "$1" ] || return 1
	LC_ALL=C ls -ldn "$1" 2>/dev/null | awk '
		NR == 1 && substr($1, 1, 1) == "d" && $3 ~ /^[0-9][0-9]*$/ {
			print $3, substr($1, 2, 9)
			FOUND = 1
			exit
		}
		END { if (!FOUND) exit 1 }
	'
}

IPSet_Lock_Interrupt_Cleanup() {
	if [ "${IPSET_START_STOPPED:-0}" -eq 1 ]; then
		IPSet_Start_Restore || true
	fi
}

IPSet_Start_Restore() {
	IPSET_START_STOPPED="0"
	if IPSet_Start_While_Locked; then
		agh_log info IPSet_Start_Restore "state=rollback action=restore_adguardhome reason=ipset_setup_rollback result=restored"
		return 0
	fi
	agh_log error IPSet_Start_Restore "state=rollback action=restore_adguardhome reason=ipset_setup_rollback result=failed"
	return 1
}

IPSet_Start_While_Locked() {
	local DNSMASQ_RESTART_SKIP STATUS
	DNSMASQ_RESTART_SKIP="${ADGUARDHOME_SKIP_DNSMASQ_RESTART:-}"
	if adguard_dnsmasq_managed; then
		IPSET_DNSMASQ_RESTART_PENDING="1"
	else
		IPSET_DNSMASQ_RESTART_PENDING="0"
	fi
	ADGUARDHOME_SKIP_DNSMASQ_RESTART="1"
	lower_script start
	STATUS="$?"
	ADGUARDHOME_SKIP_DNSMASQ_RESTART="${DNSMASQ_RESTART_SKIP}"
	return "${STATUS}"
}

IPSet_Lock() {
	local STATUS
	IPSet_Runtime_Prepare || return 1
	# Prefer flock on firmware that supports descriptor locking.  The private,
	# ownership-validated mkdir lock remains the fallback for older firmware.
	if have_cmd flock && flock_supports_fd; then
		IPSet_Lock_Flock "$@"
	else
		IPSet_Lock_Mkdir "$@"
	fi
	STATUS="$?"
	IPSet_Dnsmasq_Restart_After_Unlock
	return "${STATUS}"
}

IPSet_Lock_Flock() {
	local SAVED_TRAPS STATUS TRAP_LINE TRAP_STATE_FILE
	TRAP_STATE_FILE="${IPSET_RUNTIME_DIR}/traps.$$"
	trap >"${TRAP_STATE_FILE}" || return 1
	SAVED_TRAPS=""
	while IFS= read -r TRAP_LINE || [ -n "${TRAP_LINE}" ]; do
		SAVED_TRAPS="${SAVED_TRAPS}${SAVED_TRAPS:+
}${TRAP_LINE}"
	done <"${TRAP_STATE_FILE}"
	rm -f "${TRAP_STATE_FILE}"
	exec 8>"${IPSET_RUNTIME_DIR}/flock" || return 1
	if ! flock 8; then
		agh_log error IPSet_Lock_Flock "state=lock action=acquire_lock reason=flock_failed result=failed lock=flock"
		exec 8>&-
		return 1
	fi
	# Restore a stopped service while this lock is still held; only then release it.
	trap 'IPSet_Lock_Interrupt_Cleanup; IPSet_Lock_Flock_Cleanup; IPSet_Dnsmasq_Restart_After_Unlock; IPSet_Restore_Traps "${SAVED_TRAPS}"; exit 1' HUP INT QUIT ABRT TERM TSTP
	trap 'STATUS="$?"; IPSet_Lock_Flock_Cleanup; IPSet_Restore_Traps "${SAVED_TRAPS}"; exit "${STATUS}"' EXIT
	"$@"
	STATUS="$?"
	IPSet_Lock_Flock_Cleanup
	IPSet_Restore_Traps "${SAVED_TRAPS}"
	return "${STATUS}"
}

IPSet_Lock_Flock_Cleanup() {
	flock -u 8 >/dev/null 2>&1
	exec 8>&-
}

IPSet_Lock_Mkdir() {
	local ATTEMPTS LOCK_DIR LOCK_METADATA LOCK_OWNER OWNER OWNERLESS_ATTEMPTS SAVED_TRAPS STATUS TRAP_LINE TRAP_STATE_FILE
	LOCK_DIR="${IPSET_RUNTIME_DIR}/mkdir"
	LOCK_OWNER="$(IPSet_Current_UID)" || return 1
	ATTEMPTS="0"
	OWNERLESS_ATTEMPTS="0"
	while ! mkdir -m 700 "${LOCK_DIR}" 2>/dev/null; do
		if [ -L "${LOCK_DIR}" ] || [ ! -d "${LOCK_DIR}" ]; then
			agh_log error IPSet_Lock_Mkdir "state=lock action=validate_lock reason=unsafe_path result=failed lock=mkdir"
			return 1
		fi
		LOCK_METADATA="$(IPSet_Directory_Metadata "${LOCK_DIR}")" || return 1
		if [ "${LOCK_METADATA%% *}" != "${LOCK_OWNER}" ]; then
			agh_log error IPSet_Lock_Mkdir "state=lock action=validate_lock reason=untrusted_owner result=failed lock=mkdir"
			return 1
		fi
		OWNER="$(sed -n '1p' "${LOCK_DIR}/pid" 2>/dev/null)"
		case "${OWNER}" in
			"" | *[!0-9]*)
				# Allow the lock owner time to publish its PID after mkdir succeeds.
				OWNERLESS_ATTEMPTS="$((OWNERLESS_ATTEMPTS + 1))"
				if [ "${OWNERLESS_ATTEMPTS}" -ge 5 ] && IPSet_Lock_Mkdir_Reap_Stale "${LOCK_DIR}" "${OWNER}"; then
					continue
				fi
				;;
			*)
				OWNERLESS_ATTEMPTS="0"
				if ! kill -0 "${OWNER}" 2>/dev/null && IPSet_Lock_Mkdir_Reap_Stale "${LOCK_DIR}" "${OWNER}"; then
					continue
				fi
				;;
		esac
		ATTEMPTS="$((ATTEMPTS + 1))"
		if [ "${ATTEMPTS}" -ge 30 ]; then
			agh_log error IPSet_Lock_Mkdir "state=lock action=acquire_lock reason=timeout result=failed lock=mkdir attempts=${ATTEMPTS}"
			return 1
		fi
		sleep 1
	done
	printf '%s\n' "$$" >"${LOCK_DIR}/pid"
	TRAP_STATE_FILE="${LOCK_DIR}/traps"
	if ! trap >"${TRAP_STATE_FILE}"; then
		IPSet_Lock_Mkdir_Cleanup "${LOCK_DIR}"
		return 1
	fi
	SAVED_TRAPS=""
	while IFS= read -r TRAP_LINE || [ -n "${TRAP_LINE}" ]; do
		SAVED_TRAPS="${SAVED_TRAPS}${SAVED_TRAPS:+
}${TRAP_LINE}"
	done <"${TRAP_STATE_FILE}"
	rm -f "${TRAP_STATE_FILE}"
	# Keep the fallback lock through restoration for the same lifecycle guarantee.
	trap 'IPSet_Lock_Interrupt_Cleanup; IPSet_Lock_Mkdir_Cleanup "${LOCK_DIR}"; IPSet_Dnsmasq_Restart_After_Unlock; IPSet_Restore_Traps "${SAVED_TRAPS}"; exit 1' HUP INT QUIT ABRT TERM TSTP
	trap 'STATUS="$?"; IPSet_Lock_Mkdir_Cleanup "${LOCK_DIR}"; IPSet_Restore_Traps "${SAVED_TRAPS}"; exit "${STATUS}"' EXIT
	"$@"
	STATUS="$?"
	IPSet_Lock_Mkdir_Cleanup "${LOCK_DIR}"
	IPSet_Restore_Traps "${SAVED_TRAPS}"
	return "${STATUS}"
}

IPSet_Lock_Mkdir_Cleanup() {
	[ -n "$1" ] && rm -rf "$1"
}

IPSet_Lock_Mkdir_Reap_Stale() {
	local CURRENT_OWNER LOCK_DIR LOCK_METADATA LOCK_OWNER OBSERVED_OWNER REAP_DIR
	LOCK_DIR="$1"
	OBSERVED_OWNER="$2"
	REAP_DIR="${LOCK_DIR}/reap"
	LOCK_OWNER="$(IPSet_Current_UID)" || return 1

	# Only one waiter may revalidate and remove a stale lock.  A waiter that
	# reaches a replacement lock creates its marker there and must revalidate
	# the replacement's owner before it can remove anything.
	mkdir -m 700 "${REAP_DIR}" 2>/dev/null || return 1
	LOCK_METADATA="$(IPSet_Directory_Metadata "${LOCK_DIR}")" || {
		rmdir "${REAP_DIR}" 2>/dev/null
		return 1
	}
	if [ "${LOCK_METADATA%% *}" != "${LOCK_OWNER}" ]; then
		rmdir "${REAP_DIR}" 2>/dev/null
		return 1
	fi

	CURRENT_OWNER="$(sed -n '1p' "${LOCK_DIR}/pid" 2>/dev/null)"
	if [ "${CURRENT_OWNER}" != "${OBSERVED_OWNER}" ]; then
		rmdir "${REAP_DIR}" 2>/dev/null
		return 1
	fi
	case "${CURRENT_OWNER}" in
		"" | *[!0-9]*) ;;
		*)
			if kill -0 "${CURRENT_OWNER}" 2>/dev/null; then
				rmdir "${REAP_DIR}" 2>/dev/null
				return 1
			fi
			;;
	esac
	rm -rf "${LOCK_DIR}"
}

IPSet_Migrate() {
	local CURRENT_FILE TEMP_FILE USER_TEMP_FILE
	IPSET_MIGRATION_SKIPPED=""
	if adguard_lan_mode; then
		if ! IPSet_Disable_Managed; then
			agh_log warning IPSet_Migrate "state=migration action=disable_managed_ipset result=skipped reason=lan_mode_remove_failed"
		fi
		return 0
	fi
	[ -f "${YAML_FILE}" ] || return 0
	if ! CURRENT_FILE="$(IPSet_Current_File)"; then
		return 1
	fi
	if [ -n "${CURRENT_FILE}" ] && [ "${CURRENT_FILE}" != "${IPSET_FILE}" ]; then
		agh_log info IPSet_Migrate "state=migration action=migrate_ipset result=skipped reason=existing_file file=${CURRENT_FILE}"
		IPSET_MIGRATION_SKIPPED="1"
		return 0
	fi
	TEMP_FILE="${IPSET_USER_FILE}.tmp.$$"
	: >"${TEMP_FILE}" || return 1
	if [ -f "${IPSET_USER_FILE}" ] && ! cat "${IPSET_USER_FILE}" >>"${TEMP_FILE}"; then
		rm -f "${TEMP_FILE}"
		return 1
	fi
	if ! IPSet_Collect_Yaml >>"${TEMP_FILE}"; then
		rm -f "${TEMP_FILE}"
		return 1
	fi
	USER_TEMP_FILE="${IPSET_USER_FILE}.new.$$"
	if ! awk 'NF && !seen[$0]++' "${TEMP_FILE}" >"${USER_TEMP_FILE}"; then
		rm -f "${TEMP_FILE}" "${USER_TEMP_FILE}"
		return 1
	fi
	rm -f "${TEMP_FILE}"
	chmod 644 "${USER_TEMP_FILE}" || {
		rm -f "${USER_TEMP_FILE}"
		return 1
	}
	if [ ! -f "${IPSET_USER_FILE}" ] || ! cmp -s "${IPSET_USER_FILE}" "${USER_TEMP_FILE}"; then
		mv "${USER_TEMP_FILE}" "${IPSET_USER_FILE}" || {
			rm -f "${USER_TEMP_FILE}"
			return 1
		}
	else
		rm -f "${USER_TEMP_FILE}"
	fi
	TEMP_FILE="${YAML_FILE}.ipset.$$"
	awk -v ipset_file="${IPSET_FILE}" '
		function indentation(line,    text) {
			text = line
			sub(/[^[:space:]].*$/, "", text)
			return length(text)
		}
		function flow_reset() {
			flow_quote = ""
			flow_has_entry = 0
			flow_entry_count = 0
			flow_after_comma = 0
		}
		function flow_closed(line,    ch, i, next_ch, previous_ch, rest) {
			for (i = 1; i <= length(line); i++) {
				ch = substr(line, i, 1)
				next_ch = substr(line, i + 1, 1)
				previous_ch = substr(line, i - 1, 1)
				if (flow_quote == "\"") {
					if (ch == "\\" && next_ch != "") i++
					else if (ch == flow_quote) flow_quote = ""
				} else if (flow_quote == "\047") {
					if (ch == flow_quote && next_ch == flow_quote) i++
					else if (ch == flow_quote) flow_quote = ""
				} else if (ch == "\"" || ch == "\047") {
					flow_quote = ch
					flow_has_entry = 1
				} else if (ch == "#" && (i == 1 || previous_ch ~ /[[:space:]]/)) {
					return 0
				} else if (ch == ",") {
					if (!flow_has_entry) exit 1
					flow_has_entry = 0
					flow_entry_count++
					flow_after_comma = 1
				} else if (ch == "]") {
					rest = substr(line, i + 1)
					if (rest !~ /^[[:space:]]*(#.*)?$/) exit 1
					if (flow_has_entry) flow_entry_count++
					else if (flow_after_comma && flow_entry_count == 0) exit 1
					return 1
				} else if (ch !~ /[[:space:]]/) {
					flow_has_entry = 1
				}
			}
			return 0
		}
		function add_ipset(    prefix) {
			prefix = child_prefix
			if (prefix == "") prefix = "  "
			if (!wrote_ipset) print prefix "ipset: []"
			if (!wrote_file) print prefix "ipset_file: " ipset_file
			wrote_ipset = wrote_file = 1
		}
		/^(dns|\047dns\047|"dns"):[[:space:]]*(&[^][{},[:space:]]+[[:space:]]*)?(#.*)?$/ {
			in_dns = 1
			found_dns = 1
			child_indent = 0
			child_prefix = ""
			print
			next
		}
		/^(dns|\047dns\047|"dns"):/ { exit 1 }
		skip_flow {
			if (flow_closed($0)) skip_flow = 0
			next
		}
		in_dns && /^[^[:space:]]/ {
			add_ipset()
			in_dns = skip_ipset = 0
		}
		in_dns && !child_indent && $0 !~ /^[[:space:]]*($|#)/ {
			child_indent = indentation($0)
			child_prefix = substr($0, 1, child_indent)
		}
		skip_ipset && ($0 ~ /^[[:space:]]*($|#)/ || indentation($0) > child_indent || (indentation($0) == child_indent && substr($0, child_indent + 1) ~ /^-([[:space:]]|$)/)) { next }
		skip_ipset { skip_ipset = 0 }
		skip_ipset_file && ($0 ~ /^[[:space:]]*$/ || indentation($0) > child_indent) { next }
		skip_ipset_file { skip_ipset_file = 0 }
		in_dns && indentation($0) == child_indent && substr($0, child_indent + 1) ~ /^(ipset|\047ipset\047|"ipset"):[[:space:]]*(#.*)?$/ {
			if (!wrote_ipset) print child_prefix "ipset: []"
			wrote_ipset = 1
			skip_ipset = 1
			next
		}
		in_dns && indentation($0) == child_indent && substr($0, child_indent + 1) ~ /^(ipset|\047ipset\047|"ipset"):[[:space:]]*\[/ {
			if (!wrote_ipset) print child_prefix "ipset: []"
			wrote_ipset = 1
			line = substr($0, child_indent + 1)
			sub(/^(ipset|\047ipset\047|"ipset"):[[:space:]]*\[/, "", line)
			flow_reset()
			if (!flow_closed(line)) skip_flow = 1
			next
		}
		in_dns && indentation($0) == child_indent && substr($0, child_indent + 1) ~ /^(ipset|\047ipset\047|"ipset"):[[:space:]]*(~|null|Null|NULL)[[:space:]]*(#.*)?$/ {
			if (!wrote_ipset) print child_prefix "ipset: []"
			wrote_ipset = 1
			next
		}
		in_dns && indentation($0) == child_indent && substr($0, child_indent + 1) ~ /^(ipset|\047ipset\047|"ipset"):[[:space:]]*/ {
			wrote_ipset = 1
			print
			next
		}
		in_dns && indentation($0) == child_indent && substr($0, child_indent + 1) ~ /^(ipset_file|\047ipset_file\047|"ipset_file"):[[:space:]]*/ {
			line = substr($0, child_indent + 1)
			sub(/^(ipset_file|\047ipset_file\047|"ipset_file"):[[:space:]]*/, "", line)
			if (line ~ /^[|>]([1-9][+-]?|[+-][1-9]?)?[[:space:]]*(#.*)?$/) skip_ipset_file = 1
			if (!wrote_file) print child_prefix "ipset_file: " ipset_file
			wrote_file = 1
			next
		}
		{ print }
		END {
			if (skip_flow || flow_quote != "") exit 1
			if (in_dns) add_ipset()
		}
	' "${YAML_FILE}" >"${TEMP_FILE}" || {
		rm -f "${TEMP_FILE}"
		return 1
	}

	if ! cmp -s "${YAML_FILE}" "${TEMP_FILE}"; then
		chmod 600 "${TEMP_FILE}" || {
			rm -f "${TEMP_FILE}"
			return 1
		}
		mv "${TEMP_FILE}" "${YAML_FILE}" || {
			rm -f "${TEMP_FILE}"
			return 1
		}
	else
		rm -f "${TEMP_FILE}"
	fi
}

IPSet_Disable_Managed() {
	local CURRENT_FILE TEMP_FILE
	IPSET_DISABLE_CHANGED=""
	[ -f "${YAML_FILE}" ] || return 0
	if ! CURRENT_FILE="$(IPSet_Current_File)"; then
		return 1
	fi
	if [ "${CURRENT_FILE}" != "${IPSET_FILE}" ]; then
		return 0
	fi
	TEMP_FILE="${YAML_FILE}.ipset-legacy.$$"
	cp -p "${YAML_FILE}" "${TEMP_FILE}" || {
		rm -f "${TEMP_FILE}"
		return 1
	}
	if ! awk '
		function indentation(line,    text) {
			text = line
			sub(/[^[:space:]].*$/, "", text)
			return length(text)
		}
		/^(dns|\047dns\047|"dns"):[[:space:]]*(&[^][{},[:space:]]+[[:space:]]*)?(#.*)?$/ {
			in_dns = 1
			child_indent = 0
			print
			next
		}
		/^(dns|\047dns\047|"dns"):/ { exit 1 }
		in_dns && /^[^[:space:]]/ { in_dns = skip_file = 0 }
		in_dns && !child_indent && $0 !~ /^[[:space:]]*($|#)/ { child_indent = indentation($0) }
		skip_file && ($0 ~ /^[[:space:]]*$/ || indentation($0) > child_indent) { next }
		skip_file { skip_file = 0 }
		in_dns && indentation($0) == child_indent && substr($0, child_indent + 1) ~ /^(ipset_file|\047ipset_file\047|"ipset_file"):[[:space:]]*/ {
			line = substr($0, child_indent + 1)
			sub(/^(ipset_file|\047ipset_file\047|"ipset_file"):[[:space:]]*/, "", line)
			if (line ~ /^[|>]([1-9][+-]?|[+-][1-9]?)?[[:space:]]*(#.*)?$/) skip_file = 1
			next
		}
		{ print }
	' "${YAML_FILE}" >"${TEMP_FILE}"; then
		rm -f "${TEMP_FILE}"
		return 1
	fi
	mv "${TEMP_FILE}" "${YAML_FILE}" || {
		rm -f "${TEMP_FILE}"
		return 1
	}
	IPSET_DISABLE_CHANGED="1"
	agh_log info IPSet_Disable_Managed "state=configuration action=disable_managed_ipset result=disabled reason=unsupported_version"
}

IPSet_Disable_Managed_For_Start_Locked() {
	local WAS_RUNNING
	WAS_RUNNING="0"
	if [ "$(pidof "${PROCS}" 2>/dev/null | wc -w)" -gt 0 ]; then
		WAS_RUNNING="1"
	fi
	if [ "${WAS_RUNNING}" -eq 1 ]; then
		IPSET_START_STOPPED="1"
		if ! lower_script stop; then
			IPSET_START_STOPPED="0"
			return 1
		fi
	fi
	if ! IPSet_Disable_Managed; then
		if [ "${IPSET_START_STOPPED}" -eq 1 ] && IPSet_Start_Restore; then
			IPSET_START_RESTARTED="1"
		fi
		return 1
	fi
	if [ "${IPSET_START_STOPPED}" -eq 1 ]; then
		if ! IPSet_Start_While_Locked; then
			IPSET_START_STOPPED="0"
			return 1
		fi
		IPSET_START_STOPPED="0"
		IPSET_START_RESTARTED="1"
	fi
	return 0
}

IPSet_Enabled() {
	adguard_ipset_allowed || return 1
	[ "$(conf_value ADGUARD_IPSET)" != "NO" ]
}

IPSet_Refresh() {
	local DNSMASQ_RESTART_SKIP RESTART_STATUS
	if adguard_lan_mode; then
		agh_log info IPSet_Refresh "state=refresh action=refresh_ipset result=skipped reason=lan_mode"
		return 0
	fi
	IPSet_Enabled || return 0
	IPSet_Supported || return 0
	IPSET_REFRESH_CHANGED=""
	IPSET_REFRESH_CONFIG="${1:-}"
	IPSet_Lock IPSet_Setup_Locked || return 1
	if [ "${IPSET_REFRESH_CHANGED}" = "1" ] && [ "$(pidof "${PROCS}" 2>/dev/null | wc -w)" -gt 0 ]; then
		agh_log info IPSet_Refresh "state=refresh action=restart_adguardhome reason=ipset_refresh result=restarting"
		DNSMASQ_RESTART_SKIP="${ADGUARDHOME_SKIP_DNSMASQ_RESTART:-}"
		if [ "${IPSET_REFRESH_FROM_DNSMASQ:-}" = "1" ]; then
			ADGUARDHOME_SKIP_DNSMASQ_RESTART="1"
		fi
		lower_script restart
		RESTART_STATUS="$?"
		ADGUARDHOME_SKIP_DNSMASQ_RESTART="${DNSMASQ_RESTART_SKIP}"
		return "${RESTART_STATUS}"
	fi
}

IPSet_Refresh_Locked() {
	local CURRENT_FILE IPSET_FILE_EXISTED RAW_TEMP_FILE TEMP_FILE
	if ! CURRENT_FILE="$(IPSet_Current_File)"; then
		return 1
	fi
	if [ -n "${CURRENT_FILE}" ] && [ "${CURRENT_FILE}" != "${IPSET_FILE}" ]; then
		agh_log info IPSet_Refresh_Locked "state=refresh action=refresh_ipset result=skipped reason=existing_file file=${CURRENT_FILE}"
		return 0
	fi
	RAW_TEMP_FILE="${IPSET_FILE}.raw.$$"
	TEMP_FILE="${IPSET_FILE}.tmp.$$"
	: >"${RAW_TEMP_FILE}" || return 1
	printf '%s\n' '# Managed by Asuswrt-Merlin AdGuardHome Installer.' >>"${RAW_TEMP_FILE}" || {
		rm -f "${RAW_TEMP_FILE}"
		return 1
	}
	printf '%s\n' '# Put persistent custom rules in ipset.user.' >>"${RAW_TEMP_FILE}" || {
		rm -f "${RAW_TEMP_FILE}"
		return 1
	}
	if [ -f "${IPSET_USER_FILE}" ] && ! cat "${IPSET_USER_FILE}" >>"${RAW_TEMP_FILE}"; then
		rm -f "${RAW_TEMP_FILE}"
		return 1
	fi
	if [ -n "${IPSET_REFRESH_CONFIG:-}" ]; then
		IPSet_Collect_Dnsmasq "${IPSET_REFRESH_CONFIG}" >>"${RAW_TEMP_FILE}" || {
			rm -f "${RAW_TEMP_FILE}"
			return 1
		}
	else
		IPSet_Collect_Dnsmasq >>"${RAW_TEMP_FILE}" || {
			rm -f "${RAW_TEMP_FILE}"
			return 1
		}
	fi
	if ! awk 'NF && !seen[$0]++' "${RAW_TEMP_FILE}" >"${TEMP_FILE}"; then
		rm -f "${RAW_TEMP_FILE}" "${TEMP_FILE}"
		return 1
	fi
	rm -f "${RAW_TEMP_FILE}"
	if ! awk '!/^[[:space:]]*(#|$)/ { found = 1; exit } END { exit !found }' "${TEMP_FILE}"; then
		rm -f "${RAW_TEMP_FILE}" "${TEMP_FILE}"
		IPSET_FILE_EXISTED=""
		[ -e "${IPSET_FILE}" ] && IPSET_FILE_EXISTED="1"
		if ! IPSet_Disable_Managed; then
			return 1
		fi
		if ! rm -f "${IPSET_FILE}"; then
			return 1
		fi
		if [ "${IPSET_FILE_EXISTED}" = "1" ] || [ "${IPSET_DISABLE_CHANGED:-}" = "1" ]; then
			IPSET_REFRESH_CHANGED="1"
		fi
		agh_log info IPSet_Refresh_Locked "state=refresh action=refresh_ipset result=disabled reason=no_mappings"
		return 0
	fi
	if ! cmp -s "${IPSET_FILE}" "${TEMP_FILE}"; then
		chmod 644 "${TEMP_FILE}" || {
			rm -f "${TEMP_FILE}"
			return 1
		}
		mv "${TEMP_FILE}" "${IPSET_FILE}" || {
			rm -f "${TEMP_FILE}"
			return 1
		}
		IPSET_REFRESH_CHANGED="1"
		agh_log info IPSet_Refresh_Locked "state=refresh action=refresh_ipset reason=config_changed result=refreshed"
	else
		rm -f "${TEMP_FILE}"
	fi
}

IPSet_Restore_Traps() {
	local SAVED_TRAPS
	SAVED_TRAPS="$1"
	trap - EXIT HUP INT QUIT ABRT TERM TSTP
	[ -n "${SAVED_TRAPS}" ] && eval "${SAVED_TRAPS}"
	return 0
}

IPSet_Runtime_Prepare() {
	local METADATA MODE OWNER RUNTIME_OWNER
	OWNER="$(IPSet_Current_UID)" || return 1
	if ! mkdir -m 700 "${IPSET_RUNTIME_DIR}" 2>/dev/null; then
		if [ -L "${IPSET_RUNTIME_DIR}" ] || [ ! -d "${IPSET_RUNTIME_DIR}" ]; then
			agh_log error IPSet_Runtime_Prepare "state=runtime action=prepare_runtime reason=unsafe_path result=failed path=${IPSET_RUNTIME_DIR}"
			return 1
		fi
		METADATA="$(IPSet_Directory_Metadata "${IPSET_RUNTIME_DIR}")" || return 1
		RUNTIME_OWNER="${METADATA%% *}"
		MODE="${METADATA#* }"
		if [ "${RUNTIME_OWNER}" != "${OWNER}" ]; then
			agh_log error IPSet_Runtime_Prepare "state=runtime action=prepare_runtime reason=untrusted_owner result=failed path=${IPSET_RUNTIME_DIR}"
			return 1
		fi
		if [ "${MODE}" != "rwx------" ]; then
			agh_log error IPSet_Runtime_Prepare "state=runtime action=prepare_runtime reason=not_private result=failed path=${IPSET_RUNTIME_DIR}"
			return 1
		fi
	fi
}

IPSet_Setup() {
	IPSet_Enabled || return 0
	IPSet_Supported || return 0
	IPSET_REFRESH_CONFIG=""
	IPSet_Lock IPSet_Setup_Locked
}

IPSet_Setup_For_Start() {
	if adguard_lan_mode; then
		if ! IPSet_Disable_Managed; then
			agh_log error IPSet_Setup_For_Start "state=starting action=disable_managed_ipset result=failed reason=lan_mode_remove_failed"
			return 1
		fi
		return 0
	fi
	if ! IPSet_Enabled; then
		IPSet_Lock IPSet_Disable_Managed_For_Start_Locked
		return $?
	fi
	if ! IPSet_Supported; then
		[ "${IPSET_LEGACY_VERSION:-}" = "1" ] || return 0
		IPSet_Lock IPSet_Disable_Managed_For_Start_Locked
		return $?
	fi
	IPSET_REFRESH_CONFIG=""
	IPSet_Lock IPSet_Setup_For_Start_Locked
}

IPSet_Setup_For_Start_Locked() {
	local WAS_RUNNING
	WAS_RUNNING="0"
	if [ "$(pidof "${PROCS}" 2>/dev/null | wc -w)" -gt 0 ]; then
		WAS_RUNNING="1"
	fi
	if [ "${WAS_RUNNING}" -eq 1 ]; then
		IPSET_START_STOPPED="1"
		if ! lower_script stop; then
			IPSET_START_STOPPED="0"
			return 1
		fi
	fi
	if ! IPSet_Setup_Locked; then
		if ! IPSet_Disable_Managed; then
			if [ "${IPSET_START_STOPPED}" -eq 1 ] && IPSet_Start_Restore; then
				IPSET_START_RESTARTED="1"
			fi
			return 1
		fi
		IPSET_START_FAILURE_SAFE="1"
		if [ "${IPSET_START_STOPPED}" -eq 1 ] && IPSet_Start_Restore; then
			IPSET_START_RESTARTED="1"
		fi
		return 1
	fi
	IPSET_START_FAILURE_SAFE="1"
	if [ "${IPSET_START_STOPPED}" -eq 1 ]; then
		if ! IPSet_Start_While_Locked; then
			IPSET_START_STOPPED="0"
			return 1
		fi
		IPSET_START_STOPPED="0"
		IPSET_START_RESTARTED="1"
	fi
	return 0
}

IPSet_Has_Legacy_Mappings() {
	local LEGACY_TEMP_FILE LEGACY_STATUS
	LEGACY_TEMP_FILE="${IPSET_USER_FILE}.legacy.$$"
	if ! IPSet_Collect_Yaml >"${LEGACY_TEMP_FILE}"; then
		rm -f "${LEGACY_TEMP_FILE}"
		return 2
	fi
	if [ -s "${LEGACY_TEMP_FILE}" ]; then
		LEGACY_STATUS=0
	else
		LEGACY_STATUS=1
	fi
	rm -f "${LEGACY_TEMP_FILE}"
	return "${LEGACY_STATUS}"
}

IPSet_Setup_Locked() {
	local CURRENT_FILE LEGACY_STATUS MIGRATION_BACKUP_FILE REFRESH_STATUS
	MIGRATION_BACKUP_FILE=""
	if [ -f "${YAML_FILE}" ]; then
		MIGRATION_BACKUP_FILE="${YAML_FILE}.ipset-setup.$$"
		cp -p "${YAML_FILE}" "${MIGRATION_BACKUP_FILE}" || {
			rm -f "${MIGRATION_BACKUP_FILE}"
			return 1
		}
	fi
	if ! CURRENT_FILE="$(IPSet_Current_File)"; then
		[ -z "${MIGRATION_BACKUP_FILE}" ] || rm -f "${MIGRATION_BACKUP_FILE}"
		return 1
	fi
	if [ -z "${CURRENT_FILE}" ] && [ ! -e "${IPSET_FILE}" ]; then
		LEGACY_STATUS=0
		IPSet_Has_Legacy_Mappings || LEGACY_STATUS="$?"
		if [ "${LEGACY_STATUS}" -gt 1 ]; then
			[ -z "${MIGRATION_BACKUP_FILE}" ] || rm -f "${MIGRATION_BACKUP_FILE}"
			return 1
		fi
		if [ "${LEGACY_STATUS}" -eq 1 ]; then
			if ! IPSet_Refresh_Locked; then
				[ -z "${MIGRATION_BACKUP_FILE}" ] || rm -f "${MIGRATION_BACKUP_FILE}"
				return 1
			fi
			if [ ! -e "${IPSET_FILE}" ]; then
				[ -z "${MIGRATION_BACKUP_FILE}" ] || rm -f "${MIGRATION_BACKUP_FILE}"
				return 0
			fi
		fi
	fi
	if ! IPSet_Migrate; then
		[ -z "${MIGRATION_BACKUP_FILE}" ] || rm -f "${MIGRATION_BACKUP_FILE}"
		return 1
	fi
	if [ "${IPSET_MIGRATION_SKIPPED}" = "1" ]; then
		[ -z "${MIGRATION_BACKUP_FILE}" ] || rm -f "${MIGRATION_BACKUP_FILE}"
		return 0
	fi
	IPSet_Refresh_Locked
	REFRESH_STATUS="$?"
	if [ "${REFRESH_STATUS}" -eq 0 ]; then
		[ -z "${MIGRATION_BACKUP_FILE}" ] || rm -f "${MIGRATION_BACKUP_FILE}"
		return 0
	fi
	if [ -n "${MIGRATION_BACKUP_FILE}" ]; then
		if ! mv "${MIGRATION_BACKUP_FILE}" "${YAML_FILE}"; then
			agh_log error IPSet_Setup_Locked "state=rollback action=restore_config reason=ipset_refresh_failure result=failed backup=${MIGRATION_BACKUP_FILE}"
			return 1
		fi
		agh_log info IPSet_Setup_Locked "state=rollback action=restore_config reason=ipset_refresh_failure result=restored"
	fi
	return "${REFRESH_STATUS}"
}

IPSet_Supported() {
	local VERSION_CLASS VERSION_OUTPUT
	IPSET_LEGACY_VERSION=""
	if [ ! -x "${ADGUARDHOME_BINARY}" ]; then
		agh_log warning IPSet_Supported "state=compatibility action=check_version result=skipped reason=binary_unavailable"
		return 1
	fi
	VERSION_OUTPUT="$("${ADGUARDHOME_BINARY}" --version 2>/dev/null)" || {
		agh_log warning IPSet_Supported "state=compatibility action=check_version result=skipped reason=query_failed"
		return 1
	}
	VERSION_CLASS="$(printf '%s\n' "${VERSION_OUTPUT}" | awk '
		{
			for (i = 1; i <= NF; i++) {
				version = $i
				sub(/^v/, "", version)
				if (version !~ /^[0-9]+\.[0-9]+\.[0-9]+/) continue
				split(version, parts, ".")
				major = parts[1] + 0
				minor = parts[2] + 0
				patch = parts[3] + 0
				if ((major > 0) || (minor > 107) || (minor == 107 && patch >= 48)) print "supported"
				else print "legacy"
				exit
			}
		}
	')"
	case "${VERSION_CLASS}" in
		supported)
			return 0
			;;
		legacy)
			IPSET_LEGACY_VERSION="1"
			agh_log info IPSet_Supported "state=compatibility action=check_version result=skipped reason=unsupported_version minimum=v0.107.48"
			return 1
			;;
	esac
	agh_log warning IPSet_Supported "state=compatibility action=check_version result=skipped reason=parse_failed"
	return 1
}

if [ "${1:-}" = "status" ]; then
	status
	exit "$?"
fi

manager_dependencies_available || return 1 2>/dev/null || exit 1
if [ -f "${UPPER_SCRIPT}" ]; then UPPER_SCRIPT_LOC=". ${UPPER_SCRIPT}"; fi
if [ -f "${LOWER_SCRIPT}" ]; then LOWER_SCRIPT_LOC=". ${LOWER_SCRIPT}"; fi
if { [ "$2" != "x" ] && printf "%s" "$1" | /bin/grep -qE "^((start|stop|restart|kill|reload)$)"; }; then {
	service "${1}"_AdGuardHome >/dev/null 2>&1
	exit
}; fi
if [ "$1" = "init-start" ] && [ ! -f "${UPPER_SCRIPT}" ]; then { service_wait adguardhome_run; }; fi
if [ -f "${UPPER_SCRIPT}" ]; then { if { [ "$(canonical_path "${UPPER_SCRIPT}" 2>/dev/null)" != "${SCRIPT_LOC}" ] || [ "$0" != "${UPPER_SCRIPT}" ]; }; then {
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
	"dnsmasq" | "dnsmasq-sdn")
		dnsmasq_action_handler "${2:-}"
		;;
	"firewall")
		IPSet_Refresh
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
