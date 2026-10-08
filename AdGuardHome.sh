#!/bin/sh

export LC_ALL=C
export PATH="/sbin:/bin:/usr/sbin:/usr/bin:/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin"
umask 077

SCRIPT_LOC=""
ADGUARDHOME_BINARY="/opt/sbin/AdGuardHome"
CONF_FILE="/opt/etc/AdGuardHome/.config"
WORK_DIR="${CONF_FILE%/*}"
DNS_HANDOFF_DIR="${DNS_HANDOFF_DIR:-/tmp/AdGuardHome.dns-handoff}"
DNS_HANDOFF_FILE="${DNS_HANDOFF_FILE:-${DNS_HANDOFF_DIR}/active}"
MID_SCRIPT="/jffs/addons/AdGuardHome.d/AdGuardHome.sh"
UPPER_SCRIPT="/opt/etc/init.d/S99AdGuardHome"
LOWER_SCRIPT="/opt/etc/init.d/rc.func.AdGuardHome"
IPSET_FILE="/opt/etc/AdGuardHome/ipset.conf"
IPSET_LOCK_ACTIVE="0"
IPSET_RUNTIME_DIR="${IPSET_RUNTIME_DIR:-/opt/var/run/AdGuardHome-ipset}"
IPSET_USER_FILE="/opt/etc/AdGuardHome/ipset.user"
PROC_SYS_ROOT="${PROC_SYS_ROOT:-/proc/sys}"
PROC_SWAPS_FILE="${PROC_SWAPS_FILE:-/proc/swaps}"
PROC_BOOT_ID_FILE="${PROC_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}"
PROC_STATE_DIR="${PROC_STATE_DIR:-${WORK_DIR}/proc-sys-state}"
PROC_LOCK_DIR="${PROC_LOCK_DIR:-${WORK_DIR}/proc-sys-lock}"
PROC_LOCK_FILE="${PROC_LOCK_FILE:-${WORK_DIR}/proc-sys.lock}"
YAML_FILE="/opt/etc/AdGuardHome/AdGuardHome.yaml"
DEFAULT_ADGUARD_NETCHECK_HOSTS="google.com github.com snbforums.com"
DEFAULT_ADGUARD_NETCHECK_DNS="127.0.0.1"
DEFAULT_ADGUARD_NETCHECK_REQUIRE_HTTP="NO"
DEFAULT_ADGUARD_NETCHECK_TIMEOUT="300"
DEFAULT_ADGUARD_NETCHECK_MODE="wan"
DEFAULT_ADGUARD_PROC_OPTIMIZE="NO"
DEFAULT_ADGUARD_PROC_PROFILE="aggressive"
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

# agh_log records a timestamped AdGuardHome message in the system log.
agh_log() {
	local _level _func
	_level="$1"
	_func="$2"
	shift 2
	logger -st "${NAME}" "$(agh_timestamp) [${_level}] ${_func}: $*"
}

# load_operation_config takes one immutable snapshot of the keys needed by an
# set_operation_config_defaults sets default values for the operation configuration snapshot.
set_operation_config_defaults() {
	CONFIG_INSTALL_MODE="wan"
	CONFIG_DNSMASQ_MODE="auto"
	CONFIG_LOCAL="NO"
	CONFIG_IPSET="YES"
	CONFIG_WEBUI_PORT=""
	CONFIG_INSTALLER_BRANCH=""
	CONFIG_NETCHECK_HOSTS="${DEFAULT_ADGUARD_NETCHECK_HOSTS}"
	CONFIG_NETCHECK_DNS="${DEFAULT_ADGUARD_NETCHECK_DNS}"
	CONFIG_NETCHECK_REQUIRE_HTTP="${DEFAULT_ADGUARD_NETCHECK_REQUIRE_HTTP}"
	CONFIG_NETCHECK_TIMEOUT="${DEFAULT_ADGUARD_NETCHECK_TIMEOUT}"
	CONFIG_NETCHECK_MODE="${DEFAULT_ADGUARD_NETCHECK_MODE}"
	CONFIG_PROC_OPTIMIZE="${DEFAULT_ADGUARD_PROC_OPTIMIZE}"
	CONFIG_PROC_PROFILE="${DEFAULT_ADGUARD_PROC_PROFILE}"
}

# load_operation_config loads and validates the configuration for the requested scope, applies defaults and environment overrides, and stores the resulting values in scoped CONFIG_* variables.
load_operation_config() {
	local config_dnsmasq_mode config_install_mode config_installer_branch config_ipset config_local config_netcheck_dns config_netcheck_hosts config_netcheck_mode config_netcheck_require_http config_netcheck_timeout config_proc_optimize config_proc_profile config_row config_status config_webui_port old_ifs overridden scope
	scope="$1"
	overridden=""
	[ -n "${ADGUARD_NETCHECK_HOSTS_SET:-}" ] && [ -n "${ADGUARD_NETCHECK_HOSTS:-}" ] && overridden="${overridden} ADGUARD_NETCHECK_HOSTS"
	[ -n "${ADGUARD_NETCHECK_DNS_SET:-}" ] && [ -n "${ADGUARD_NETCHECK_DNS:-}" ] && overridden="${overridden} ADGUARD_NETCHECK_DNS"
	[ -n "${ADGUARD_NETCHECK_REQUIRE_HTTP_SET:-}" ] && [ -n "${ADGUARD_NETCHECK_REQUIRE_HTTP:-}" ] && overridden="${overridden} ADGUARD_NETCHECK_REQUIRE_HTTP"
	[ -n "${ADGUARD_NETCHECK_TIMEOUT_SET:-}" ] && [ -n "${ADGUARD_NETCHECK_TIMEOUT:-}" ] && overridden="${overridden} ADGUARD_NETCHECK_TIMEOUT"
	[ -n "${ADGUARD_NETCHECK_MODE_SET:-}" ] && [ -n "${ADGUARD_NETCHECK_MODE:-}" ] && overridden="${overridden} ADGUARD_NETCHECK_MODE"
	[ -n "${ADGUARD_PROC_OPTIMIZE_SET:-}" ] && [ -n "${ADGUARD_PROC_OPTIMIZE:-}" ] && overridden="${overridden} ADGUARD_PROC_OPTIMIZE"
	[ -n "${ADGUARD_PROC_PROFILE_SET:-}" ] && [ -n "${ADGUARD_PROC_PROFILE:-}" ] && overridden="${overridden} ADGUARD_PROC_PROFILE"
	if [ -f "${CONF_FILE}" ]; then
		config_row="$(/usr/bin/awk -v OVERRIDDEN="${overridden} " -v SCOPE="${scope}" '
		BEGIN {
			sep = "|"
			key_list = "ADGUARD_INSTALL_MODE,ADGUARD_DNSMASQ_MODE,ADGUARD_LOCAL,ADGUARD_IPSET,ADGUARD_WEBUI_PORT,INSTALLER_BRANCH,ADGUARD_NETCHECK_HOSTS,ADGUARD_NETCHECK_DNS,ADGUARD_NETCHECK_REQUIRE_HTTP,ADGUARD_NETCHECK_TIMEOUT,ADGUARD_NETCHECK_MODE,ADGUARD_PROC_OPTIMIZE,ADGUARD_PROC_PROFILE"
			keys = " " key_list " "
			gsub(/,/, " ", keys)
			if (SCOPE == "status") wanted = " ADGUARD_WEBUI_PORT INSTALLER_BRANCH "
			else if (SCOPE == "stop") wanted = " ADGUARD_INSTALL_MODE ADGUARD_DNSMASQ_MODE "
			else if (SCOPE == "dnsmasq") wanted = " ADGUARD_INSTALL_MODE ADGUARD_DNSMASQ_MODE ADGUARD_LOCAL ADGUARD_IPSET "
			else if (SCOPE == "firewall") wanted = " ADGUARD_INSTALL_MODE ADGUARD_IPSET "
			else wanted = " ADGUARD_INSTALL_MODE ADGUARD_DNSMASQ_MODE ADGUARD_LOCAL ADGUARD_IPSET ADGUARD_NETCHECK_HOSTS ADGUARD_NETCHECK_DNS ADGUARD_NETCHECK_REQUIRE_HTTP ADGUARD_NETCHECK_TIMEOUT ADGUARD_NETCHECK_MODE ADGUARD_PROC_OPTIMIZE ADGUARD_PROC_PROFILE "
		}
		/^[A-Z][A-Z0-9_]*[[:space:]]+=/ {
			key = $0
			sub(/[[:space:]]+=.*/, "", key)
			if (index(wanted, " " key " ") == 0) next
			if (index(OVERRIDDEN, " " key " ") != 0) next
			exit 3
		}
		/^[A-Z][A-Z0-9_]*=/ {
			key = $0
			sub(/=.*/, "", key)
			if (index(wanted, " " key " ") == 0) next
			if (index(OVERRIDDEN, " " key " ") != 0) next
			if (++seen[key] > 1) exit 2
			value = substr($0, length(key) + 2)
			if (value ~ /^"[^"]*"$/) value = substr(value, 2, length(value) - 2)
			else if (value ~ /["[:cntrl:]]/) exit 3
			if (value == "") {
				if (key == "ADGUARD_WEBUI_PORT" || key == "INSTALLER_BRANCH") next
				exit 3
			}
			if (value ~ /[|[:cntrl:]]/) exit 3
			values[key] = value
		}
		END {
			count = split(key_list, ordered, ",")
			for (i = 1; i <= count; i++) {
				if (i > 1) printf "%s", sep
				printf "%s", (ordered[i] in values ? values[ordered[i]] : "-")
			}
			printf "\n"
		}
		' "${CONF_FILE}" 2>/dev/null)"
		config_status="$?"
		if [ "${config_status}" -ne 0 ]; then
			printf '%s\n' "${NAME}: invalid or duplicate configuration value in ${CONF_FILE}" >&2
			return 1
		fi
	else
		config_row='-|-|-|-|-|-|-|-|-|-|-|-|-'
	fi
	old_ifs="${IFS}"
	IFS='|' read -r config_install_mode config_dnsmasq_mode config_local config_ipset config_webui_port config_installer_branch config_netcheck_hosts config_netcheck_dns config_netcheck_require_http config_netcheck_timeout config_netcheck_mode config_proc_optimize config_proc_profile <<EOF
${config_row}
EOF
	IFS="${old_ifs}"

	case "${config_install_mode}" in -) config_install_mode="wan" ;; wan | lan) ;; *) return 1 ;; esac
	case "${config_dnsmasq_mode}" in -) config_dnsmasq_mode="auto" ;; auto | enabled | disabled) ;; *) return 1 ;; esac
	case "${config_local}" in -) config_local="NO" ;; YES | NO) ;; *) return 1 ;; esac
	case "${config_ipset}" in -) config_ipset="YES" ;; YES | NO) ;; *) return 1 ;; esac
	case "${config_webui_port}" in -) config_webui_port="" ;; *[!0-9]*) return 1 ;; *) [ "${config_webui_port}" -gt 0 ] && [ "${config_webui_port}" -le 65535 ] || return 1 ;; esac
	case "${config_installer_branch}" in -) config_installer_branch="" ;; *[!A-Za-z0-9._/-]*) return 1 ;; esac
	case "${config_netcheck_hosts}" in -) config_netcheck_hosts="${DEFAULT_ADGUARD_NETCHECK_HOSTS}" ;; *[!A-Za-z0-9._:[:space:]-]*) return 1 ;; esac
	case "${config_netcheck_dns}" in -) config_netcheck_dns="${DEFAULT_ADGUARD_NETCHECK_DNS}" ;; *[!A-Za-z0-9._:-]*) return 1 ;; esac
	case "${config_netcheck_require_http}" in -) config_netcheck_require_http="${DEFAULT_ADGUARD_NETCHECK_REQUIRE_HTTP}" ;; YES | NO) ;; *) return 1 ;; esac
	case "${config_netcheck_timeout}" in -) config_netcheck_timeout="${DEFAULT_ADGUARD_NETCHECK_TIMEOUT}" ;; *[!0-9]*) return 1 ;; *) [ "${config_netcheck_timeout}" -gt 0 ] || return 1 ;; esac
	case "${config_netcheck_mode}" in -) config_netcheck_mode="${DEFAULT_ADGUARD_NETCHECK_MODE}" ;; wan | lan | legacy | WAN | LAN | LEGACY) ;; *) return 1 ;; esac
	case "${config_proc_optimize}" in -) config_proc_optimize="${DEFAULT_ADGUARD_PROC_OPTIMIZE}" ;; YES | NO | yes | no | Yes | No | ON | OFF | on | off | On | Off | TRUE | FALSE | true | false | True | False | 0 | 1) ;; *) return 1 ;; esac
	case "${config_proc_profile}" in -) config_proc_profile="${DEFAULT_ADGUARD_PROC_PROFILE}" ;; off | safe | balanced | aggressive) ;; *) return 1 ;; esac
	CONFIG_INSTALL_MODE="${config_install_mode}"
	CONFIG_DNSMASQ_MODE="${config_dnsmasq_mode}"
	CONFIG_LOCAL="${config_local}"
	CONFIG_IPSET="${config_ipset}"
	CONFIG_WEBUI_PORT="${config_webui_port}"
	CONFIG_INSTALLER_BRANCH="${config_installer_branch}"
	CONFIG_NETCHECK_HOSTS="${config_netcheck_hosts}"
	CONFIG_NETCHECK_DNS="${config_netcheck_dns}"
	CONFIG_NETCHECK_REQUIRE_HTTP="${config_netcheck_require_http}"
	CONFIG_NETCHECK_TIMEOUT="${config_netcheck_timeout}"
	CONFIG_NETCHECK_MODE="${config_netcheck_mode}"
	CONFIG_PROC_OPTIMIZE="${config_proc_optimize}"
	CONFIG_PROC_PROFILE="${config_proc_profile}"
	CONFIG_SCOPE="${scope}"
}

# adguard_install_mode prints the configured AdGuardHome installation mode, defaulting to `wan` for invalid or missing values.
adguard_install_mode() {
	printf '%s\n' "${CONFIG_INSTALL_MODE:-wan}"
}

# adguard_lan_mode reports whether AdGuardHome is configured for LAN mode.
adguard_lan_mode() {
	[ "$(adguard_install_mode)" = "lan" ]
}

# adguard_dnsmasq_running reports whether a dnsmasq process is running.
adguard_dnsmasq_running() {
	pidof dnsmasq >/dev/null 2>&1
}

# adguard_dnsmasq_managed determines whether dnsmasq is managed by AdGuardHome under the current installation and configuration settings.
adguard_dnsmasq_managed() {
	if adguard_lan_mode && ! adguard_dnsmasq_running; then
		return 1
	fi
	case "${CONFIG_DNSMASQ_MODE:-auto}" in
		disabled) return 1 ;;
		enabled) return 0 ;;
	esac
	adguard_dnsmasq_running
}

# adguard_ipset_allowed allows IPSet in WAN mode or in LAN, AP, or bridge mode with qualifying WAN firewall state.
adguard_ipset_allowed() {
	case "${CONFIG_INSTALL_MODE:-}" in
		wan) return 0 ;;
		lan | ap | bridge) adguard_wan_iptables_state_active 2>/dev/null ;;
		*) return 1 ;;
	esac
}

# adguard_wan_iptables_state_active reports whether a WAN interface has an active SNAT or MASQUERADE rule.
adguard_wan_iptables_state_active() {
	local ifname key nat_rules unit
	nat_rules="$(/usr/sbin/iptables -t nat -S POSTROUTING 2>/dev/null)" || return 1
	for unit in 0 1; do
		for key in ifname gw_ifname pppoe_ifname; do
			ifname="$(/bin/nvram get "wan${unit}_${key}" 2>/dev/null)" || ifname=""
			case "${ifname}" in
				"" | *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.:-]*) continue ;;
			esac
			if printf '%s\n' "${nat_rules}" | /usr/bin/awk -v wan_if="${ifname}" '
				function comment_ends(value, i, slashes) {
					if (length(value) < 2) return 0
					if (substr(value, length(value), 1) != "\"") return 0
					for (i = length(value) - 1; i > 0 && substr(value, i, 1) == "\\"; i--) slashes++
					return slashes % 2 == 0
				}
				{
					output = target = input = negated = 0
					for (i = 1; i <= NF; i++) {
						if ($i == "--comment") { i++; if ($i ~ /^"/ && !comment_ends($i)) while (i <= NF && !comment_ends($i)) i++; continue }
						if (($i == "-i" || $i == "--in-interface") && i < NF) input = 1
						if (($i == "-o" || $i == "--out-interface") && i < NF) {
							output = ($(i + 1) == wan_if)
							negated = (i > 1 && $(i - 1) == "!")
						}
						if ($i == "-j" && i < NF && ($(i + 1) == "MASQUERADE" || $(i + 1) == "SNAT")) target = 1
					}
					if (output && target && !input && !negated) { found = 1; exit }
				}
				END { exit(found ? 0 : 1) }
			'; then
				return 0
			fi
		done
	done
	return 1
}

# adguard_restart_dnsmasq_if_managed restarts dnsmasq when it is managed by AdGuardHome.
adguard_restart_dnsmasq_if_managed() {
	adguard_dnsmasq_managed || return 0
	service restart_dnsmasq >/dev/null 2>&1
}

# database_link_matches_expected verifies that a symlink owned by the current user resolves to the expected database path.
database_link_matches_expected() {
	local EXPECTED_CANONICAL EXPECTED_PATH LINK_CANONICAL LINK_PATH
	LINK_PATH="$1"
	EXPECTED_PATH="$2"
	[ -L "${LINK_PATH}" ] || return 1
	database_link_owned_by_current_user "${LINK_PATH}" || return 1
	LINK_CANONICAL="$(canonical_path "${LINK_PATH}" 2>/dev/null)" || return 1
	[ -n "${LINK_CANONICAL}" ] || return 1
	EXPECTED_CANONICAL="$(canonical_path "${EXPECTED_PATH}" 2>/dev/null)" || return 1
	[ -n "${EXPECTED_CANONICAL}" ] || return 1
	[ "${LINK_CANONICAL}" = "${EXPECTED_CANONICAL}" ]
}

# database_link_owned_by_current_user reports whether the specified path is owned by the current user.
database_link_owned_by_current_user() {
	local CURRENT_UID LINK_UID
	CURRENT_UID="$(/usr/bin/awk '$1 == "Uid:" { print $3; exit }' /proc/self/status 2>/dev/null)" || return 1
	case "${CURRENT_UID}" in
		"" | *[!0-9]*) return 1 ;;
	esac
	LINK_UID="$(LC_ALL=C ls -ldn "$1" 2>/dev/null | /usr/bin/awk 'NR == 1 { print $3; exit }')" || return 1
	case "${LINK_UID}" in
		"" | *[!0-9]*) return 1 ;;
	esac
	[ "${LINK_UID}" = "${CURRENT_UID}" ]
}

# database_link_object_type reports the filesystem object type at the specified path, including dangling symbolic links.
database_link_object_type() {
	if [ -L "$1" ]; then
		printf '%s\n' symlink
	elif [ -f "$1" ]; then
		printf '%s\n' regular-file
	elif [ -d "$1" ]; then
		printf '%s\n' directory
	elif [ -e "$1" ]; then
		printf '%s\n' other
	else
		printf '%s\n' missing
	fi
}

# ensure_database_link creates the expected database symlink when the destination is missing, preserves unexpected objects, and treats creation failures as non-fatal.
ensure_database_link() {
	local EXPECTED_PATH LINK_PATH OBJECT_TYPE
	LINK_PATH="$1"
	EXPECTED_PATH="$2"
	if database_link_matches_expected "${LINK_PATH}" "${EXPECTED_PATH}"; then
		return 0
	fi
	OBJECT_TYPE="$(database_link_object_type "${LINK_PATH}")"
	if [ "${OBJECT_TYPE}" != missing ]; then
		agh_log warning ensure_database_link "state=starting action=create_database_link result=skipped reason=unexpected_object object_type=${OBJECT_TYPE} path=${LINK_PATH}"
		return 0
	fi
	if ! ln -s "${EXPECTED_PATH}" "${LINK_PATH}" >/dev/null 2>&1; then
		agh_log warning ensure_database_link "state=starting action=create_database_link result=failed reason=link_create_failed object_type=${OBJECT_TYPE} path=${LINK_PATH} optional=1"
	fi
	return 0
}

# remove_database_link removes the specified database link when it points to the expected target.
remove_database_link() {
	if database_link_matches_expected "$1" "$2"; then
		rm "$1" >/dev/null 2>&1 || true
	fi
}

# have_cmd checks whether the specified command is available.
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

# agh_web_port determines the configured AdGuardHome WebUI port and prints it when valid.

agh_web_port() {
	local CONF_PORT YAML_PORT
	YAML_PORT="$(awk -F: '/^[[:space:]]*address:[[:space:]]*/ { print $NF; exit }' "${YAML_FILE}" 2>/dev/null | sed 's/[^0-9].*$//')"
	case "${YAML_PORT}" in
		"" | *[!0-9]*) ;;
		*) [ "${YAML_PORT}" -gt 0 ] && [ "${YAML_PORT}" -le 65535 ] && printf '%s\n' "${YAML_PORT}" && return 0 ;;
	esac
	CONF_PORT="${CONFIG_WEBUI_PORT:-}"
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

# status_dnsmasq_handoff_state reports whether DNS handoff marker files are present and lists their paths.
status_dnsmasq_handoff_state() {
	local marker markers state
	state="inactive"
	markers=""
	for marker in /tmp/AdGuardHome.dnsmasq.handoff /tmp/AdGuardHome.dnsmasq.lock "${DNS_HANDOFF_FILE}" "${DNS_HANDOFF_DIR}/lock"; do
		if [ -e "${marker}" ] || [ -L "${marker}" ]; then
			state="active/stale marker present"
			markers="${markers}${markers:+, }${marker}"
		fi
	done
	if [ -n "${markers}" ]; then
		printf '%s\n' "${state} (${markers})"
	else
		printf '%s\n' "${state}"
	fi
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

# status_selected_branch reports the configured installer branch or `unknown` when no branch is selected.
status_selected_branch() {
	local branch
	branch="${CONFIG_INSTALLER_BRANCH:-}"
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
	case "$1" in
		"")
			if adguardhome_run_legacy_mkdir_active; then return 1; fi
			if have_cmd flock && flock_supports_fd; then
				if adguardhome_run_flock_active; then return 1; else return 0; fi
			fi
			return 0
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
	(
		umask 077
		set -C
		printf '%s\n' "${owner}" >"${pid_file}"
	) 2>/dev/null || return 1
	start="$(date +%s)"
	service_wait "${action}" 30
	status="$?"
	end="$(date +%s)"
	runtime="$((end - start))"
	adguardhome_run_file_is_private "${pid_file}" || return 1
	printf '%s\n' "${runtime}" >>"${pid_file}" || return 1
	if [ "${status}" -eq 0 ]; then
		agh_log info adguardhome_run_execute "state=service action=${action} reason=service_wait result=completed runtime=${runtime}"
	else
		agh_log warning adguardhome_run_execute "state=service action=${action} reason=service_wait result=timeout runtime=${runtime}"
	fi
	return "${status}"
}

# Service locks use one persistent private directory and never replace its
# descriptor inode. Match the effective owner, which is root on the router.
adguardhome_run_directory_is_private() {
	local metadata owner
	owner="$(IPSet_Current_UID)" || return 1
	metadata="$(IPSet_Directory_Metadata "$1")" || return 1
	[ "${metadata}" = "${owner} rwx------" ]
}

adguardhome_run_file_is_private() {
	local legacy owner
	[ ! -L "$1" ] && [ -f "$1" ] || return 1
	legacy="${2:-0}"
	owner="$(IPSet_Current_UID)" || return 1
	ls -ldn "$1" 2>/dev/null | awk -v owner="${owner}" -v legacy="${legacy}" '
		NR == 1 { exit(($1 == "-rw-------" || (legacy == 1 && $1 == "-rw-r--r--")) && $2 == 1 && $3 == owner ? 0 : 1) }
		END { if (NR == 0) exit 1 }
	'
}

adguardhome_run_link_is_private() {
	local owner
	[ -L "$1" ] || return 1
	owner="$(IPSet_Current_UID)" || return 1
	ls -ldn "$1" 2>/dev/null | awk -v owner="${owner}" '
		NR == 1 { exit(substr($1, 1, 1) == "l" && $2 == 1 && $3 == owner ? 0 : 1) }
		END { if (NR == 0) exit 1 }
	'
}

adguardhome_run_runtime_prepare() {
	local lock_dir
	lock_dir="/tmp/AdGuardHome-service-lock"
	if ! mkdir -m 700 "${lock_dir}" 2>/dev/null; then
		adguardhome_run_directory_is_private "${lock_dir}" || return 1
	fi
	if [ -e "${lock_dir}/flock" ] || [ -L "${lock_dir}/flock" ]; then
		adguardhome_run_file_is_private "${lock_dir}/flock" || return 1
	fi
}

# Existing files may be reused only after validation; noclobber protects first
# creation, and append opens preserve content as well as the shared lock inode.
adguardhome_run_flock_prepare() {
	local lock_file
	lock_file="/tmp/AdGuardHome-service-lock/flock"
	adguardhome_run_runtime_prepare || return 1
	if [ ! -e "${lock_file}" ] && [ ! -L "${lock_file}" ]; then
		(
			umask 077
			set -C
			: >"${lock_file}"
		) 2>/dev/null || true
	fi
	adguardhome_run_file_is_private "${lock_file}"
}

# The owner record is immutable until cleanup; PID plus start time rejects PID
# reuse and makes repeated cleanup unable to remove a successor's lock.
adguardhome_run_owner_matches() {
	local record
	adguardhome_run_directory_is_private "$1" || return 1
	adguardhome_run_file_is_private "$1/owner" || return 1
	IFS= read -r record <"$1/owner" || return 1
	[ "${record}" = "$2 $3" ]
}

# A transition is published only after proving creation/cleanup ownership. It
# distinguishes an interrupted empty action from an unverified ownerless path.
adguardhome_run_transition_begin() {
	local record start
	start="$(proc_process_start_time "${PROC_LOCK_PID}")" || return 1
	record="${PROC_LOCK_PID} ${start} $2 $3"
	if ln -s "${record}" "$1.transition" 2>/dev/null; then return 0; fi
	adguardhome_run_link_is_private "$1.transition" && [ "$(readlink "$1.transition" 2>/dev/null)" = "${record}" ]
}

adguardhome_run_transition_clear() {
	local expected_owner expected_start record start
	[ -e "$1.transition" ] || [ -L "$1.transition" ] || return 0
	start="$(proc_process_start_time "${PROC_LOCK_PID}")" || return 1
	adguardhome_run_link_is_private "$1.transition" || return 1
	record="$(readlink "$1.transition" 2>/dev/null)" || return 1
	case "${record}" in "${PROC_LOCK_PID} ${start} "*) : ;; *) return 1 ;; esac
	record="${record#"${PROC_LOCK_PID} ${start} "}"
	expected_owner="${record%% *}"
	expected_start="${record#* }"
	case "${expected_owner}" in "" | *[!0-9]*) return 1 ;; esac
	case "${expected_start}" in "" | *[!0-9]*) return 1 ;; esac
	rm -f "$1.transition"
}

adguardhome_run_transition_recover() {
	local current_start expected_owner expected_start lock_dir owner owner_start record
	lock_dir="$1"
	[ -e "${lock_dir}.transition" ] || [ -L "${lock_dir}.transition" ] || return 0
	adguardhome_run_link_is_private "${lock_dir}.transition" || return 1
	record="$(readlink "${lock_dir}.transition" 2>/dev/null)" || return 1
	owner="${record%% *}"
	record="${record#* }"
	owner_start="${record%% *}"
	record="${record#* }"
	expected_owner="${record%% *}"
	expected_start="${record#* }"
	case "${owner}" in "" | *[!0-9]*) return 1 ;; esac
	case "${owner_start}" in "" | *[!0-9]*) return 1 ;; esac
	case "${expected_owner}" in "" | *[!0-9]*) return 1 ;; esac
	case "${expected_start}" in "" | *[!0-9]*) return 1 ;; esac
	current_start="$(proc_process_start_time "${owner}" 2>/dev/null)"
	if [ "${current_start}" = "${owner_start}" ] || { [ -z "${current_start}" ] && kill -0 "${owner}" 2>/dev/null; }; then return 1; fi
	if [ -e "${lock_dir}" ] || [ -L "${lock_dir}" ]; then
		adguardhome_run_directory_is_private "${lock_dir}" || return 1
		if [ -e "${lock_dir}/owner" ] || [ -L "${lock_dir}/owner" ]; then
			adguardhome_run_owner_matches "${lock_dir}" "${expected_owner}" "${expected_start}" || return 1
		else
			# A killed owner writer may leave an unpublished staged record.
			if [ -e "${lock_dir}/owner.new" ] || [ -L "${lock_dir}/owner.new" ]; then
				[ "${expected_owner} ${expected_start}" = "${owner} ${owner_start}" ] || return 1
				adguardhome_run_file_is_private "${lock_dir}/owner.new" || return 1
				rm -f "${lock_dir}/owner.new" || return 1
			fi
			# Only an empty directory can be an interrupted publication/cleanup.
			rmdir "${lock_dir}" 2>/dev/null || return 1
		fi
	fi
	rm -f "${lock_dir}.transition"
}

adguardhome_run_mkdir_cleanup() {
	local claim_pid claim_start PROC_LOCK_DIR PROC_LOCK_PID status
	PROC_LOCK_DIR="$1"
	IFS= read -r claim_pid </proc/self/stat || return 1
	PROC_LOCK_PID="${claim_pid%% *}"
	claim_start="$(proc_process_start_time "${PROC_LOCK_PID}")" || return 1
	if [ -e "${PROC_LOCK_DIR}.claim" ] || [ -L "${PROC_LOCK_DIR}.claim" ]; then adguardhome_run_link_is_private "${PROC_LOCK_DIR}.claim" || return 1; fi
	proc_lock_claim_matches "${PROC_LOCK_PID}" "${claim_start}" || proc_lock_claim_acquire "${claim_start}" 1 || return 1
	adguardhome_run_mkdir_cleanup_claimed "$@"
	status="$?"
	if [ "${status}" -eq 0 ] || { [ ! -e "$1" ] && [ ! -L "$1" ]; }; then adguardhome_run_transition_clear "$1" || status=1; fi
	proc_lock_claim_release "${claim_start}" || status=1
	return "${status}"
}

# Publication and cleanup share the existing PID/start-time claim, so a killed
# cleaner leaves recoverable ownership instead of an unowned permanent marker.
adguardhome_run_mkdir_cleanup_claimed() {
	local lock_dir owner owner_start
	lock_dir="$1"
	owner="$2"
	owner_start="$3"
	adguardhome_run_owner_matches "${lock_dir}" "${owner}" "${owner_start}" || return 1
	if [ -e "${lock_dir}/pid" ] || [ -L "${lock_dir}/pid" ]; then adguardhome_run_file_is_private "${lock_dir}/pid" || return 1; fi
	adguardhome_run_transition_begin "${lock_dir}" "${owner}" "${owner_start}" || return 1
	if [ -e "${lock_dir}/pid" ] || [ -L "${lock_dir}/pid" ]; then
		if ! adguardhome_run_file_is_private "${lock_dir}/pid" || ! rm -f "${lock_dir}/pid"; then
			return 1
		fi
	fi
	rm -f "${lock_dir}/owner" || return 1
	rmdir "${lock_dir}"
}

# The caller holds the publication claim while revalidating immutable identity;
# unknown/live state remains untouched and only one stale reaper can publish.
adguardhome_run_mkdir_reap_stale() {
	local current_start lock_dir owner owner_start
	lock_dir="$1"
	owner="$2"
	owner_start="$3"
	adguardhome_run_owner_matches "${lock_dir}" "${owner}" "${owner_start}" || return 1
	current_start="$(proc_process_start_time "${owner}" 2>/dev/null)"
	if [ "${current_start}" = "${owner_start}" ] || { [ -z "${current_start}" ] && kill -0 "${owner}" 2>/dev/null; }; then
		return 1
	fi
	if [ -e "${lock_dir}/pid" ] || [ -L "${lock_dir}/pid" ]; then adguardhome_run_file_is_private "${lock_dir}/pid" || return 1; fi
	adguardhome_run_transition_begin "${lock_dir}" "${owner}" "${owner_start}" || return 1
	if [ -e "${lock_dir}/pid" ] || [ -L "${lock_dir}/pid" ]; then
		if ! adguardhome_run_file_is_private "${lock_dir}/pid" || ! rm -f "${lock_dir}/pid"; then
			return 1
		fi
	fi
	rm -f "${lock_dir}/owner" || return 1
	rmdir "${lock_dir}" || return 1
	adguardhome_run_transition_clear "${lock_dir}"
}

adguardhome_run_mkdir_acquire() {
	local PROC_LOCK_DIR PROC_LOCK_PID status
	PROC_LOCK_DIR="$1"
	PROC_LOCK_PID="$2"
	proc_lock_claim_acquire "$3" 1 || return 1
	adguardhome_run_mkdir_acquire_claimed "$@"
	status="$?"
	if [ "${status}" -eq 0 ] || { [ ! -e "$1" ] && [ ! -L "$1" ]; }; then adguardhome_run_transition_clear "$1" || status=1; fi
	proc_lock_claim_release "$3" || status=1
	return "${status}"
}

adguardhome_run_mkdir_acquire_claimed() {
	local current_start lock_dir record stale_owner stale_start
	lock_dir="$1"
	adguardhome_run_transition_recover "${lock_dir}" || return 1
	if [ -e "${lock_dir}" ] || [ -L "${lock_dir}" ]; then
		adguardhome_run_directory_is_private "${lock_dir}" || return 1
		adguardhome_run_file_is_private "${lock_dir}/owner" || return 1
		IFS=' ' read -r stale_owner stale_start record <"${lock_dir}/owner" || return 1
		[ -z "${record}" ] || return 1
		case "${stale_owner}" in "" | *[!0-9]*) return 1 ;; esac
		case "${stale_start}" in "" | *[!0-9]*) return 1 ;; esac
		current_start="$(proc_process_start_time "${stale_owner}" 2>/dev/null)"
		if [ "${current_start}" = "${stale_start}" ] || { [ -z "${current_start}" ] && kill -0 "${stale_owner}" 2>/dev/null; }; then return 1; fi
		adguardhome_run_mkdir_reap_stale "${lock_dir}" "${stale_owner}" "${stale_start}" || return 1
	fi
	adguardhome_run_transition_begin "${lock_dir}" "$2" "$3" || return 1
	mkdir -m 700 "${lock_dir}" 2>/dev/null || return 1
	if ! (
		umask 077
		set -C
		printf '%s %s\n' "$2" "$3" >"${lock_dir}/owner.new"
	) 2>/dev/null; then
		if [ -e "${lock_dir}/owner.new" ] || [ -L "${lock_dir}/owner.new" ]; then
			adguardhome_run_file_is_private "${lock_dir}/owner.new" && rm -f "${lock_dir}/owner.new"
		fi
		rmdir "${lock_dir}" 2>/dev/null
		return 1
	fi
	adguardhome_run_file_is_private "${lock_dir}/owner.new" || return 1
	mv "${lock_dir}/owner.new" "${lock_dir}/owner"
}

# adguardhome_run_flock serializes service operations with a file lock, allowing stop operations to wait and rejecting duplicate concurrent actions.
adguardhome_run_flock() {
	local action lock_dir lock_file owner owner_start pid_file saved_traps status
	action="$1"
	lock_dir="/tmp/AdGuardHome-service-lock/action"
	lock_file="/tmp/AdGuardHome-service-lock/flock"
	pid_file="${lock_dir}/pid"
	if adguardhome_run_legacy_lock_active; then
		owner="$(sed -n '1p' "${pid_file}" 2>/dev/null)"
		agh_log warning adguardhome_run_flock "state=locked action=${action} reason=active_lock result=duplicate_lock owner=${owner:-unknown}"
		return 1
	fi
	if ! adguardhome_run_flock_prepare; then
		agh_log error adguardhome_run_flock "state=lock action=${action} reason=mkdir_failed result=create_lock_failed path=${lock_dir}"
		return 1
	fi
	exec 9>>"${lock_file}" || return 1
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
	IFS= read -r owner </proc/self/stat || {
		exec 9>&-
		return 1
	}
	owner="${owner%% *}"
	owner_start="$(proc_process_start_time "${owner}")" || {
		exec 9>&-
		return 1
	}
	if adguardhome_run_legacy_lock_active || ! adguardhome_run_mkdir_acquire "${lock_dir}" "${owner}" "${owner_start}"; then
		flock -u 9 >/dev/null 2>&1
		exec 9>&-
		return 1
	fi
	saved_traps="$(trap)"
	trap 'if [ "${ROLLBACK_ACTIVE:-0}" = "1" ]; then TRANSACTION_SIGNAL_PENDING="1"; else adguardhome_run_flock_cleanup "${pid_file}" "${owner}" "${owner_start}"; adguardhome_run_flock_restore_traps "${saved_traps}"; IPSet_Lock_Interrupt_Propagate; exit 1; fi' HUP INT QUIT ABRT TERM TSTP
	trap 'status="$?"; adguardhome_run_flock_cleanup "${pid_file}" "${owner}" "${owner_start}"; adguardhome_run_flock_restore_traps "${saved_traps}"; exit "${status}"' EXIT
	adguardhome_run_execute "${action}" "${pid_file}" "${owner}"
	status="$?"
	adguardhome_run_flock_cleanup "${pid_file}" "${owner}" "${owner_start}" || status=1
	adguardhome_run_flock_restore_traps "${saved_traps}"
	return "${status}"
}

adguardhome_run_flock_active() {
	local lock_dir lock_file status
	lock_dir="/tmp/AdGuardHome-service-lock"
	lock_file="${lock_dir}/flock"
	if adguardhome_run_legacy_mkdir_active; then return 0; fi
	adguardhome_run_flock_prepare || return 0
	exec 9>>"${lock_file}" || return 0
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
	local pid_file status
	pid_file="$1"
	status=0
	adguardhome_run_mkdir_cleanup "${pid_file%/pid}" "$2" "$3" || status=1
	flock -u 9 >/dev/null 2>&1
	exec 9>&-
	return "${status}"
}

adguardhome_run_flock_restore_traps() {
	local saved_traps
	saved_traps="$1"
	trap - EXIT HUP INT QUIT ABRT TERM TSTP
	[ -n "${saved_traps}" ] && eval "${saved_traps}"
}

adguardhome_run_legacy_mkdir_active() {
	local lock_dir
	lock_dir="/tmp/AdGuardHome-service-lock"
	if [ -e "${lock_dir}" ] || [ -L "${lock_dir}" ]; then
		adguardhome_run_directory_is_private "${lock_dir}" || return 0
		if [ -e "${lock_dir}/flock" ] || [ -L "${lock_dir}/flock" ]; then
			adguardhome_run_file_is_private "${lock_dir}/flock" || return 0
		fi
		if [ -e "${lock_dir}/action" ] || [ -L "${lock_dir}/action" ]; then return 0; fi
		if [ -e "${lock_dir}/action.claim" ] || [ -L "${lock_dir}/action.claim" ] || [ -e "${lock_dir}/action.transition" ] || [ -L "${lock_dir}/action.transition" ]; then return 0; fi
	fi
	adguardhome_run_legacy_lock_active
}

# Upgrade compatibility is read-only: a live legacy holder or any unsafe entry
# blocks a new action, including the window before old flock publishes its PID.
adguardhome_run_legacy_lock_active() {
	local lock_dir owner pid_file runtime
	lock_dir="/tmp/AdGuardHome"
	pid_file="${lock_dir}/pid"
	if [ -e "${lock_dir}" ] || [ -L "${lock_dir}" ]; then
		[ ! -L "${lock_dir}" ] && [ -d "${lock_dir}" ] || return 0
		owner="$(IPSet_Current_UID)" || return 0
		ls -ldn "${lock_dir}" 2>/dev/null | awk -v owner="${owner}" '
			NR == 1 { exit($3 == owner && ($1 == "drwx------" || $1 == "drwxr-xr-x") ? 0 : 1) }
			END { if (NR == 0) exit 1 }
		' || return 0
		if [ -e "${pid_file}" ] || [ -L "${pid_file}" ]; then
			adguardhome_run_file_is_private "${pid_file}" 1 || return 0
			runtime="$(sed -n '2p' "${pid_file}" 2>/dev/null)"
			owner="$(sed -n '1p' "${pid_file}" 2>/dev/null)"
			case "${owner}" in "" | *[!0-9]*) return 0 ;; esac
			if [ -z "${runtime}" ] && kill -0 "${owner}" 2>/dev/null; then return 0; fi
		elif [ ! -e "${lock_dir}.lock" ] && [ ! -L "${lock_dir}.lock" ]; then
			# Legacy mkdir acquires the directory before publishing its PID.
			# Unlike a completed descriptor action, it removes the directory.
			return 0
		fi
	fi
	if [ -e "${lock_dir}.lock" ] || [ -L "${lock_dir}.lock" ]; then
		adguardhome_run_file_is_private "${lock_dir}.lock" 1 || return 0
		have_cmd flock || return 0
		(exec 7<"${lock_dir}.lock" && flock -n 7) >/dev/null 2>&1 || return 0
	fi
	return 1
}

adguardhome_run_mkdir() {
	local action lock_dir owner owner_start pid_file saved_traps status
	action="$1"
	lock_dir="/tmp/AdGuardHome-service-lock/action"
	pid_file="${lock_dir}/pid"
	adguardhome_run_runtime_prepare || return 1
	adguardhome_run_legacy_lock_active && return 1
	IFS= read -r owner </proc/self/stat || return 1
	owner="${owner%% *}"
	owner_start="$(proc_process_start_time "${owner}")" || return 1
	if ! adguardhome_run_mkdir_acquire "${lock_dir}" "${owner}" "${owner_start}"; then
		agh_log warning adguardhome_run_mkdir "state=locked action=${action} reason=active_lock result=duplicate_lock"
		return 1
	fi
	saved_traps="$(trap)"
	trap 'if [ "${ROLLBACK_ACTIVE:-0}" = "1" ]; then TRANSACTION_SIGNAL_PENDING="1"; else adguardhome_run_mkdir_cleanup "${lock_dir}" "${owner}" "${owner_start}"; adguardhome_run_flock_restore_traps "${saved_traps}"; IPSet_Lock_Interrupt_Propagate; exit 1; fi' HUP INT QUIT ABRT TERM TSTP
	trap 'status="$?"; adguardhome_run_mkdir_cleanup "${lock_dir}" "${owner}" "${owner_start}"; adguardhome_run_flock_restore_traps "${saved_traps}"; exit "${status}"' EXIT
	adguardhome_run_execute "${action}" "${pid_file}" "${owner}"
	status="$?"
	adguardhome_run_mkdir_cleanup "${lock_dir}" "${owner}" "${owner_start}" || status=1
	adguardhome_run_flock_restore_traps "${saved_traps}"
	return "${status}"
}

flock_supports_fd() {
	local TEST_LOCK status
	TEST_LOCK="/tmp/AdGuardHome-service-lock/probe.$$"
	adguardhome_run_runtime_prepare || return 1
	(
		umask 077
		set -C
		: >"${TEST_LOCK}" || exit 1
		trap 'rm -f "/tmp/AdGuardHome-service-lock/probe.$$"' EXIT
		adguardhome_run_file_is_private "${TEST_LOCK}" || exit 1
		exec 8>>"${TEST_LOCK}" || exit 1
		flock -n 8 >/dev/null 2>&1
	)
	status="$?"
	return "${status}"
}

# check_dns_environment applies or restores DNS-related NVRAM settings in WAN mode; LAN-mode running requests make no changes.
# @param MODE The lifecycle state: `running` applies the WAN AdGuard-managed DNS profile, while `stop` restores saved settings.

check_dns_environment() {
	local MODE NVCHECK
	# dns_env_set_nvram updates an NVRAM variable when its current value differs from the expected value.
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
	# dns_env_apply_profile applies the AdGuard-managed DNS profile and returns success when any DNS setting changes.
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
			if adguard_lan_mode; then
				return 0
			fi
			if [ "$(pidof stubby | wc -w)" -gt "0" ]; then
				{ killall -q -9 stubby 2>/dev/null; }
				NVCHECK="$((NVCHECK + 1))"
			fi
			# Save original values only once.
			if [ "${_DNS_NVRAM_SAVED:-0}" != "1" ]; then
				save_dns_nvram_environment
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

# dns_handoff_is_active verifies that the DNS handoff belongs to a running process with matching ownership and start time.
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

# dnsmasq_resolv_conf_cleanup removes the temporary `/tmp/resolv.conf` mount when `/etc/resolv.conf` does not use the ROM-backed file.
dnsmasq_resolv_conf_cleanup() {
	adguard_local_cache_lock dnsmasq_resolv_conf_cleanup_locked
}

# Reuse the bounded flock/mkdir implementation with a separate resolver lock.
# It executes in a subshell, keeping refreshed configuration local to this action.
adguard_local_cache_lock() {
	local PROC_LOCK_DIR="${WORK_DIR}/local-cache-lock" PROC_LOCK_FILE="${WORK_DIR}/local-cache.lock"
	proc_lock_run "$@"
}

# dnsmasq_resolv_conf_cleanup_locked restores native resolver routing when needed.
# The caller holds the resolver lock; an unmount failure is returned to the caller.
dnsmasq_resolv_conf_cleanup_locked() {
	if { ! resolv_conf_uses_rom && resolv_conf_is_tmp_mount; }; then {
		umount /tmp/resolv.conf 2>/dev/null
	}; fi
}

# Probe in a subshell so checking descriptor locks cannot replace the caller's fd 9.
adguard_local_cache_service_active() {
	(
		adguardhome_run_legacy_mkdir_active && exit 0
		if have_cmd flock && flock_supports_fd; then
			adguardhome_run_flock_active
		else
			exit 1
		fi
	)
}

# Router resolver switching is optional and follows DNS readiness, never postconf.
adguard_local_cache_ready() {
	local ADGUARDHOME_DNSMASQ_CONFIGS config index capability
	ADGUARDHOME_DNSMASQ_CONFIGS=""
	dns_handoff_is_active && return 1
	# A manager start/stop operation must finish before routing through AGH.
	adguard_local_cache_service_active && return 1
	adguardhome_owns_dns "$(adguardhome_dns_bind_scope)" || return 1
	# The absolute name bypasses libc's /etc/hosts shortcut in older nslookup.
	# ROM resolver routing uses loopback, so verify the actual loopback path.
	if [ "${1:-}" != no-lookup ]; then
		nslookup localhost. 127.0.0.1 >/dev/null 2>&1 || return 1
	fi
	if agh_dnsmasq_managed; then
		[ -f /etc/dnsmasq.conf ] || return 1
		ADGUARDHOME_DNSMASQ_CONFIGS="/etc/dnsmasq.conf"
		capability="$(nvram get rc_support 2>/dev/null)"
		case " ${capability} " in
			*" mtlancfg "*)
				# Intentional pathname expansion enumerates firmware SDN configs.
				for config in /etc/dnsmasq-[0-9]*.conf; do
					[ -f "${config}" ] || continue
					index="${config#/etc/dnsmasq-}"
					index="${index%.conf}"
					case "${index}" in "" | *[!0-9]*) continue ;; esac
					[ -n "$(sdn_bridge_for_index "${index}")" ] || continue
					ADGUARDHOME_DNSMASQ_CONFIGS="${ADGUARDHOME_DNSMASQ_CONFIGS} ${config}"
				done
				;;
		esac
	fi
	dnsmasq_instances_ready 553
}

# adguard_local_cache_sync reconciles the saved Local Cache preference and routing.
# Optional $1=verify forces a full readiness probe even for an active cache.
# Blocking DNS probes run outside the resolver lock; failed readiness restores
# native routing and returns nonzero, while activation rechecks under the lock.
adguard_local_cache_sync() {
	local status
	# DNS queries may wait for a timeout; never keep shutdown's resolver lock
	# while probing. Status 2 requests a full readiness check outside the lock.
	if adguard_local_cache_lock adguard_local_cache_sync_locked "${1:-check}"; then
		return 0
	else
		status="$?"
	fi
	[ "${status}" -eq 2 ] || return "${status}"
	if ! adguard_local_cache_ready; then
		dnsmasq_resolv_conf_cleanup || return 1
		return 1
	fi
	adguard_local_cache_lock adguard_local_cache_sync_locked activate
}

# adguard_local_cache_sync_locked reloads preferences and updates the resolver
# while the caller holds the resolver lock. $1 is check (default), verify, or
# activate. Returns 0 on success, 2 to request an unlocked readiness probe, and
# 1 on configuration, readiness, mount, or cleanup failure.
adguard_local_cache_sync_locked() {
	# Read the saved preference inside the lock: monitor snapshots may be old.
	if ! load_operation_config dnsmasq; then
		dnsmasq_resolv_conf_cleanup_locked || return 1
		return 1
	fi
	if [ "${CONFIG_LOCAL:-NO}" != YES ]; then
		dnsmasq_resolv_conf_cleanup_locked
		return "$?"
	fi
	# A ROM-backed resolver is already firmware-managed and cannot be switched.
	resolv_conf_uses_rom && return 0
	if dns_handoff_is_active || adguard_local_cache_service_active; then
		dnsmasq_resolv_conf_cleanup_locked || return 1
		return 1
	fi
	if resolv_conf_is_tmp_mount; then
		# Activation verified listeners. Between lifecycle changes, a cheap
		# process check avoids repeating socket/SDN inventories every 10 seconds.
		if ! pidof "${PROCS}" >/dev/null 2>&1; then
			dnsmasq_resolv_conf_cleanup_locked || return 1
			return 1
		fi
		[ "${1:-check}" != verify ] || return 2
		return 0
	fi
	[ "${1:-check}" = activate ] || return 2
	# Recheck listeners and service state before committing, without a DNS query.
	adguard_local_cache_ready no-lookup || return 1
	# Readiness may enumerate several SDNs; observe a stop that began meanwhile.
	if dns_handoff_is_active || adguard_local_cache_service_active; then return 1; fi
	if ! mount -o bind /rom/etc/resolv.conf /tmp/resolv.conf; then
		agh_log warning adguard_local_cache_sync "state=cache action=bind_resolver result=failed native_resolver_retained=1"
		return 1
	fi
	# Recheck after the switch; a concurrent restart must leave native routing.
	if ! adguard_local_cache_ready no-lookup; then
		dnsmasq_resolv_conf_cleanup_locked || return 1
		return 1
	fi
	return 0
}

# dnsmasq_ipset_state_cleanup_stage_path removes one ownership-validated private snapshot stage.
dnsmasq_ipset_state_cleanup_stage_path() {
	local CURRENT_UID PATH_METADATA SNAPSHOT_STAGE STAGE_MODE STAGE_OWNER
	SNAPSHOT_STAGE="$1"
	[ -d "${SNAPSHOT_STAGE}" ] && [ ! -L "${SNAPSHOT_STAGE}" ] || return 1
	CURRENT_UID="$(IPSet_Current_UID)" || return 1
	PATH_METADATA="$(IPSet_Directory_Metadata "${SNAPSHOT_STAGE}")" || return 1
	IFS=' ' read -r STAGE_OWNER STAGE_MODE <<EOF
${PATH_METADATA}
EOF
	[ "${STAGE_OWNER}" = "${CURRENT_UID}" ] && [ "${STAGE_MODE}" = "rwx------" ] || return 1
	[ -d "${SNAPSHOT_STAGE}" ] && [ ! -L "${SNAPSHOT_STAGE}" ] || return 1
	PATH_METADATA="$(IPSet_Directory_Metadata "${SNAPSHOT_STAGE}")" || return 1
	IFS=' ' read -r STAGE_OWNER STAGE_MODE <<EOF
${PATH_METADATA}
EOF
	[ "${STAGE_OWNER}" = "${CURRENT_UID}" ] && [ "${STAGE_MODE}" = "rwx------" ] || return 1
	rm -rf "${SNAPSHOT_STAGE}" || return 1
	[ ! -e "${SNAPSHOT_STAGE}" ] && [ ! -L "${SNAPSHOT_STAGE}" ]
}

# dnsmasq_ipset_state_cleanup_stage removes the current process's private snapshot stage when it exists.
dnsmasq_ipset_state_cleanup_stage() {
	local SNAPSHOT_STAGE
	SNAPSHOT_STAGE="${WORK_DIR}/.AdGuardHome.dnsmasq-stage.$$"
	[ -e "${SNAPSHOT_STAGE}" ] || [ -L "${SNAPSHOT_STAGE}" ] || return 0
	dnsmasq_ipset_state_cleanup_stage_path "${SNAPSHOT_STAGE}"
}

# dnsmasq_ipset_state_cleanup_stages removes every validated orphaned private snapshot stage while the transaction lock is held.
dnsmasq_ipset_state_cleanup_stages() {
	local SNAPSHOT_NAME SNAPSHOT_STAGE SNAPSHOT_SUFFIX
	for SNAPSHOT_STAGE in "${WORK_DIR}"/.AdGuardHome.dnsmasq-stage.*; do
		[ -e "${SNAPSHOT_STAGE}" ] || [ -L "${SNAPSHOT_STAGE}" ] || continue
		SNAPSHOT_NAME="${SNAPSHOT_STAGE##*/}"
		case "${SNAPSHOT_NAME}" in
			.AdGuardHome.dnsmasq-stage.*) SNAPSHOT_SUFFIX="${SNAPSHOT_NAME#.AdGuardHome.dnsmasq-stage.}" ;;
			*) return 1 ;;
		esac
		case "${SNAPSHOT_SUFFIX}" in
			"" | *[!0-9]*) return 1 ;;
		esac
		dnsmasq_ipset_state_cleanup_stage_path "${SNAPSHOT_STAGE}" || return 1
	done
}

# dnsmasq_ipset_state_snapshot saves the managed IPSet file and YAML configuration in an atomically published cleanup-only snapshot.
dnsmasq_ipset_state_snapshot() {
	local SNAPSHOT_DIR SNAPSHOT_STAGE
	SNAPSHOT_DIR="$1"
	SNAPSHOT_STAGE="${WORK_DIR}/.AdGuardHome.dnsmasq-stage.$$"
	[ ! -e "${SNAPSHOT_DIR}" ] && [ ! -L "${SNAPSHOT_DIR}" ] || return 1
	[ ! -e "${SNAPSHOT_STAGE}" ] && [ ! -L "${SNAPSHOT_STAGE}" ] || return 1
	mkdir -m 700 "${SNAPSHOT_STAGE}" || return 1
	if [ -e "${IPSET_FILE}" ]; then
		cp -p "${IPSET_FILE}" "${SNAPSHOT_STAGE}/ipset" || {
			rm -rf "${SNAPSHOT_STAGE}"
			return 1
		}
	else
		: >"${SNAPSHOT_STAGE}/ipset.absent" || {
			rm -rf "${SNAPSHOT_STAGE}"
			return 1
		}
	fi
	if [ -e "${YAML_FILE}" ]; then
		cp -p "${YAML_FILE}" "${SNAPSHOT_STAGE}/yaml" || {
			rm -rf "${SNAPSHOT_STAGE}"
			return 1
		}
	else
		: >"${SNAPSHOT_STAGE}/yaml.absent" || {
			rm -rf "${SNAPSHOT_STAGE}"
			return 1
		}
	fi
	printf '%s\n' '1:2' >"${SNAPSHOT_STAGE}/snapshot.version" || {
		rm -rf "${SNAPSHOT_STAGE}"
		return 1
	}
	: >"${SNAPSHOT_STAGE}/cleanup.only" || {
		rm -rf "${SNAPSHOT_STAGE}"
		return 1
	}
	mv "${SNAPSHOT_STAGE}" "${SNAPSHOT_DIR}" || {
		rm -rf "${SNAPSHOT_STAGE}"
		return 1
	}
}

# dnsmasq_ipset_state_mark_cleanup records that a committed or restored snapshot needs cleanup without making it eligible for rollback.
dnsmasq_ipset_state_mark_cleanup() {
	local SNAPSHOT_DIR
	SNAPSHOT_DIR="$1"
	[ -d "${SNAPSHOT_DIR}" ] && [ ! -L "${SNAPSHOT_DIR}" ] || return 1
	if [ -e "${SNAPSHOT_DIR}/restore.pending" ]; then
		[ -f "${SNAPSHOT_DIR}/restore.pending" ] && [ ! -L "${SNAPSHOT_DIR}/restore.pending" ] || return 1
		[ ! -e "${SNAPSHOT_DIR}/cleanup.pending" ] && [ ! -L "${SNAPSHOT_DIR}/cleanup.pending" ] || return 1
		mv "${SNAPSHOT_DIR}/restore.pending" "${SNAPSHOT_DIR}/cleanup.pending" || return 1
	elif [ -e "${SNAPSHOT_DIR}/cleanup.pending" ]; then
		[ -f "${SNAPSHOT_DIR}/cleanup.pending" ] && [ ! -L "${SNAPSHOT_DIR}/cleanup.pending" ] || return 1
	else
		return 1
	fi
}

# dnsmasq_ipset_snapshot_version_valid accepts only the exact newline-terminated snapshot version record.
dnsmasq_ipset_snapshot_version_valid() {
	local SNAPSHOT_VERSION SNAPSHOT_VERSION_EXTRA VERSION_FILE
	VERSION_FILE="$1"
	[ -f "${VERSION_FILE}" ] && [ ! -L "${VERSION_FILE}" ] || return 1
	{
		IFS= read -r SNAPSHOT_VERSION || return 1
		SNAPSHOT_VERSION_EXTRA=""
		if IFS= read -r SNAPSHOT_VERSION_EXTRA || [ -n "${SNAPSHOT_VERSION_EXTRA}" ]; then
			return 1
		fi
	} <"${VERSION_FILE}"
	[ "${SNAPSHOT_VERSION}" = "1:2" ]
}

# dnsmasq_ipset_state_mark_cleanup_only marks a versioned snapshot that has not mutated live state for cleanup only.
dnsmasq_ipset_state_mark_cleanup_only() {
	local CLEANUP_ONLY_STAGE SNAPSHOT_DIR
	SNAPSHOT_DIR="$1"
	[ -d "${SNAPSHOT_DIR}" ] && [ ! -L "${SNAPSHOT_DIR}" ] || return 1
	dnsmasq_ipset_snapshot_version_valid "${SNAPSHOT_DIR}/snapshot.version" || return 1
	[ ! -e "${SNAPSHOT_DIR}/config.pending" ] || { [ -f "${SNAPSHOT_DIR}/config.pending" ] && [ ! -L "${SNAPSHOT_DIR}/config.pending" ]; } || return 1
	[ ! -e "${SNAPSHOT_DIR}/config.restored" ] && [ ! -L "${SNAPSHOT_DIR}/config.restored" ] || return 1
	if [ ! -e "${SNAPSHOT_DIR}/cleanup.only" ]; then
		CLEANUP_ONLY_STAGE="${SNAPSHOT_DIR}/cleanup.only.$$"
		: >"${CLEANUP_ONLY_STAGE}" || return 1
		mv "${CLEANUP_ONLY_STAGE}" "${SNAPSHOT_DIR}/cleanup.only" || {
			rm -f "${CLEANUP_ONLY_STAGE}"
			return 1
		}
	else
		[ -f "${SNAPSHOT_DIR}/cleanup.only" ] && [ ! -L "${SNAPSHOT_DIR}/cleanup.only" ] || return 1
	fi
	rm -f "${SNAPSHOT_DIR}/restore.pending" || return 1
	[ ! -e "${SNAPSHOT_DIR}/restore.pending" ] && [ ! -L "${SNAPSHOT_DIR}/restore.pending" ]
}

# dnsmasq_ipset_state_finalize_cleanup removes a cleanup snapshot and recreates its durable marker when removal is partial.
dnsmasq_ipset_state_finalize_cleanup() {
	local CLEANUP_MARKER SNAPSHOT_DIR
	SNAPSHOT_DIR="$1"
	CLEANUP_MARKER="$2"
	case "${CLEANUP_MARKER}" in cleanup.only | cleanup.pending) ;; *) return 1 ;; esac
	if rm -rf "${SNAPSHOT_DIR}"; then
		return 0
	fi
	[ ! -e "${SNAPSHOT_DIR}" ] && [ ! -L "${SNAPSHOT_DIR}" ] && return 0
	[ -d "${SNAPSHOT_DIR}" ] && [ ! -L "${SNAPSHOT_DIR}" ] || return 1
	if [ "${CLEANUP_MARKER}" = "cleanup.only" ]; then
		printf '%s\n' '1:2' >"${SNAPSHOT_DIR}/snapshot.version" || return 1
	fi
	: >"${SNAPSHOT_DIR}/${CLEANUP_MARKER}" || return 1
	return 1
}

# dnsmasq_ipset_state_recover_pending restores rollback-pending snapshots and removes cleanup-pending committed snapshots.
dnsmasq_ipset_state_recover_pending() {
	local CONFIG_BACKUP_RECOVERY CONFIG_FILE_RECOVERY CONFIG_RESTORE_STAGE SNAPSHOT_DIR SNAPSHOT_NAME SNAPSHOT_VERSION
	for SNAPSHOT_DIR in "${WORK_DIR}"/.AdGuardHome.dnsmasq-ipset.*; do
		[ -d "${SNAPSHOT_DIR}" ] || continue
		[ ! -L "${SNAPSHOT_DIR}" ] || return 1
		SNAPSHOT_NAME="${SNAPSHOT_DIR##*/}"
		case "${SNAPSHOT_NAME}" in
			.AdGuardHome.dnsmasq-ipset.*) ;;
			*) return 1 ;;
		esac
		SNAPSHOT_VERSION=""
		if [ -e "${SNAPSHOT_DIR}/snapshot.version" ] || [ -L "${SNAPSHOT_DIR}/snapshot.version" ]; then
			dnsmasq_ipset_snapshot_version_valid "${SNAPSHOT_DIR}/snapshot.version" || return 1
			SNAPSHOT_VERSION="1:2"
		fi
		[ ! -L "${SNAPSHOT_DIR}/config.pending" ] || return 1
		[ ! -L "${SNAPSHOT_DIR}/config.restored" ] || return 1
		if [ -e "${SNAPSHOT_DIR}/cleanup.only" ] || [ -L "${SNAPSHOT_DIR}/cleanup.only" ]; then
			[ "${SNAPSHOT_VERSION}" = "1:2" ] || return 1
			[ -f "${SNAPSHOT_DIR}/cleanup.only" ] && [ ! -L "${SNAPSHOT_DIR}/cleanup.only" ] || return 1
			[ ! -e "${SNAPSHOT_DIR}/config.pending" ] || { [ -f "${SNAPSHOT_DIR}/config.pending" ] && [ ! -L "${SNAPSHOT_DIR}/config.pending" ]; } || return 1
			[ ! -e "${SNAPSHOT_DIR}/config.restored" ] || return 1
			[ ! -e "${SNAPSHOT_DIR}/cleanup.pending" ] || { [ -f "${SNAPSHOT_DIR}/cleanup.pending" ] && [ ! -L "${SNAPSHOT_DIR}/cleanup.pending" ]; } || return 1
			[ ! -e "${SNAPSHOT_DIR}/restore.pending" ] || { [ -f "${SNAPSHOT_DIR}/restore.pending" ] && [ ! -L "${SNAPSHOT_DIR}/restore.pending" ]; } || return 1
			if [ -e "${SNAPSHOT_DIR}/config.pending" ] &&
				{ [ -e "${SNAPSHOT_DIR}/cleanup.pending" ] || [ -e "${SNAPSHOT_DIR}/restore.pending" ]; }; then
				return 1
			fi
			if ! dnsmasq_ipset_state_finalize_cleanup "${SNAPSHOT_DIR}" cleanup.only; then
				agh_log error dnsmasq_params "state=recovery action=cleanup_snapshot result=failed snapshot=${SNAPSHOT_DIR}"
				return 1
			fi
			continue
		fi
		if [ -e "${SNAPSHOT_DIR}/cleanup.pending" ]; then
			[ -f "${SNAPSHOT_DIR}/cleanup.pending" ] && [ ! -L "${SNAPSHOT_DIR}/cleanup.pending" ] || return 1
			[ ! -e "${SNAPSHOT_DIR}/restore.pending" ] && [ ! -L "${SNAPSHOT_DIR}/restore.pending" ] || return 1
			if ! dnsmasq_ipset_state_finalize_cleanup "${SNAPSHOT_DIR}" cleanup.pending; then
				agh_log error dnsmasq_params "state=recovery action=cleanup_snapshot result=failed snapshot=${SNAPSHOT_DIR}"
				return 1
			fi
			continue
		fi
		if [ ! -e "${SNAPSHOT_DIR}/restore.pending" ]; then
			agh_log error dnsmasq_params "state=recovery action=validate_snapshot result=failed reason=missing_marker snapshot=${SNAPSHOT_DIR}"
			return 1
		fi
		[ -f "${SNAPSHOT_DIR}/restore.pending" ] && [ ! -L "${SNAPSHOT_DIR}/restore.pending" ] || return 1
		if [ "${SNAPSHOT_VERSION}" = "1:2" ] && [ ! -e "${SNAPSHOT_DIR}/config.pending" ] &&
			[ ! -e "${SNAPSHOT_DIR}/config.restored" ]; then
			return 1
		fi
		if [ -e "${SNAPSHOT_DIR}/config.pending" ] || [ -e "${SNAPSHOT_DIR}/config.restored" ]; then
			[ ! -e "${SNAPSHOT_DIR}/config.pending" ] || { [ -f "${SNAPSHOT_DIR}/config.pending" ] && [ ! -L "${SNAPSHOT_DIR}/config.pending" ]; } || return 1
			[ ! -e "${SNAPSHOT_DIR}/config.restored" ] || { [ -f "${SNAPSHOT_DIR}/config.restored" ] && [ ! -L "${SNAPSHOT_DIR}/config.restored" ]; } || return 1
			[ ! -e "${SNAPSHOT_DIR}/config.pending" ] || [ ! -e "${SNAPSHOT_DIR}/config.restored" ] || return 1
			if [ -e "${SNAPSHOT_DIR}/config.pending" ]; then
				{
					IFS= read -r CONFIG_BACKUP_RECOVERY
					IFS= read -r CONFIG_FILE_RECOVERY
				} <"${SNAPSHOT_DIR}/config.pending" || return 1
			else
				{
					IFS= read -r CONFIG_BACKUP_RECOVERY
					IFS= read -r CONFIG_FILE_RECOVERY
				} <"${SNAPSHOT_DIR}/config.restored" || return 1
			fi
			case "${CONFIG_BACKUP_RECOVERY}" in /*) ;; *) return 1 ;; esac
			case "${CONFIG_FILE_RECOVERY}" in /*) ;; *) return 1 ;; esac
			if [ -e "${SNAPSHOT_DIR}/config.pending" ]; then
				[ -f "${CONFIG_BACKUP_RECOVERY}" ] && [ ! -L "${CONFIG_BACKUP_RECOVERY}" ] || return 1
				CONFIG_RESTORE_STAGE="${CONFIG_FILE_RECOVERY}.adguard-restore.$$"
				cp -p "${CONFIG_BACKUP_RECOVERY}" "${CONFIG_RESTORE_STAGE}" || return 1
				if ! mv "${CONFIG_RESTORE_STAGE}" "${CONFIG_FILE_RECOVERY}"; then
					rm -f "${CONFIG_RESTORE_STAGE}"
					agh_log error dnsmasq_params "state=recovery action=restore_dnsmasq result=failed config=${CONFIG_FILE_RECOVERY} snapshot=${SNAPSHOT_DIR}"
					return 1
				fi
				mv "${SNAPSHOT_DIR}/config.pending" "${SNAPSHOT_DIR}/config.restored" || return 1
			fi
			rm -f "${CONFIG_BACKUP_RECOVERY}" || return 1
		fi
		if { [ -f "${SNAPSHOT_DIR}/ipset" ] && [ ! -L "${SNAPSHOT_DIR}/ipset" ]; }; then
			[ ! -e "${SNAPSHOT_DIR}/ipset.absent" ] || return 1
		else
			[ -f "${SNAPSHOT_DIR}/ipset.absent" ] && [ ! -L "${SNAPSHOT_DIR}/ipset.absent" ] || return 1
		fi
		if { [ -f "${SNAPSHOT_DIR}/yaml" ] && [ ! -L "${SNAPSHOT_DIR}/yaml" ]; }; then
			[ ! -e "${SNAPSHOT_DIR}/yaml.absent" ] || return 1
		else
			[ -f "${SNAPSHOT_DIR}/yaml.absent" ] && [ ! -L "${SNAPSHOT_DIR}/yaml.absent" ] || return 1
		fi
		if dnsmasq_ipset_state_restore "${SNAPSHOT_DIR}"; then
			dnsmasq_ipset_state_finalize_cleanup "${SNAPSHOT_DIR}" cleanup.pending || return 1
		else
			agh_log error dnsmasq_params "state=recovery action=restore_ipset result=failed snapshot=${SNAPSHOT_DIR}"
			return 1
		fi
	done
}

# dnsmasq_ipset_state_restore restores the saved IPSet and YAML state, restarts AdGuardHome when necessary, and marks the snapshot for cleanup.
dnsmasq_ipset_state_restore() {
	local ADGUARD_WAS_RUNNING DNSMASQ_RESTART_SKIP IPSET_CURRENT_ABSENT IPSET_CURRENT_STAGE IPSET_RESTORE_STAGE RESTART_REQUIRED SNAPSHOT_DIR YAML_RESTORE_STAGE
	SNAPSHOT_DIR="$1"
	ADGUARD_WAS_RUNNING="${2:-0}"
	RESTART_REQUIRED="0"
	IPSET_CURRENT_ABSENT="0"
	IPSET_CURRENT_STAGE="${IPSET_FILE}.dnsmasq-current.$$"
	IPSET_RESTORE_STAGE="${IPSET_FILE}.dnsmasq-restore.$$"
	YAML_RESTORE_STAGE="${YAML_FILE}.dnsmasq-restore.$$"
	if [ ! -f "${SNAPSHOT_DIR}/ipset.absent" ]; then
		cp -p "${SNAPSHOT_DIR}/ipset" "${IPSET_RESTORE_STAGE}" || {
			rm -f "${IPSET_RESTORE_STAGE}" "${YAML_RESTORE_STAGE}" "${IPSET_CURRENT_STAGE}"
			return 1
		}
	fi
	if [ ! -f "${SNAPSHOT_DIR}/yaml.absent" ]; then
		cp -p "${SNAPSHOT_DIR}/yaml" "${YAML_RESTORE_STAGE}" || {
			rm -f "${IPSET_RESTORE_STAGE}" "${YAML_RESTORE_STAGE}" "${IPSET_CURRENT_STAGE}"
			return 1
		}
	fi
	if [ -e "${IPSET_FILE}" ]; then
		cp -p "${IPSET_FILE}" "${IPSET_CURRENT_STAGE}" || {
			rm -f "${IPSET_RESTORE_STAGE}" "${YAML_RESTORE_STAGE}" "${IPSET_CURRENT_STAGE}"
			return 1
		}
	else
		IPSET_CURRENT_ABSENT="1"
	fi
	if [ -f "${SNAPSHOT_DIR}/ipset.absent" ]; then
		[ ! -e "${IPSET_FILE}" ] || RESTART_REQUIRED="1"
		rm -f "${IPSET_FILE}" || {
			rm -f "${IPSET_RESTORE_STAGE}" "${YAML_RESTORE_STAGE}" "${IPSET_CURRENT_STAGE}"
			return 1
		}
	else
		cmp -s "${SNAPSHOT_DIR}/ipset" "${IPSET_FILE}" || RESTART_REQUIRED="1"
		mv "${IPSET_RESTORE_STAGE}" "${IPSET_FILE}" || {
			rm -f "${IPSET_RESTORE_STAGE}" "${YAML_RESTORE_STAGE}" "${IPSET_CURRENT_STAGE}"
			return 1
		}
	fi
	if [ -f "${SNAPSHOT_DIR}/yaml.absent" ]; then
		[ ! -e "${YAML_FILE}" ] || RESTART_REQUIRED="1"
		rm -f "${YAML_FILE}" || {
			rm -f "${YAML_RESTORE_STAGE}"
			if [ "${IPSET_CURRENT_ABSENT}" = "1" ]; then
				rm -f "${IPSET_FILE}" || agh_log error dnsmasq_params "state=restore action=compensate_ipset result=failed snapshot=${SNAPSHOT_DIR}"
			else
				mv "${IPSET_CURRENT_STAGE}" "${IPSET_FILE}" || agh_log error dnsmasq_params "state=restore action=compensate_ipset result=failed snapshot=${SNAPSHOT_DIR}"
			fi
			return 1
		}
	else
		cmp -s "${SNAPSHOT_DIR}/yaml" "${YAML_FILE}" || RESTART_REQUIRED="1"
		mv "${YAML_RESTORE_STAGE}" "${YAML_FILE}" || {
			rm -f "${YAML_RESTORE_STAGE}"
			if [ "${IPSET_CURRENT_ABSENT}" = "1" ]; then
				rm -f "${IPSET_FILE}" || agh_log error dnsmasq_params "state=restore action=compensate_ipset result=failed snapshot=${SNAPSHOT_DIR}"
			else
				mv "${IPSET_CURRENT_STAGE}" "${IPSET_FILE}" || agh_log error dnsmasq_params "state=restore action=compensate_ipset result=failed snapshot=${SNAPSHOT_DIR}"
			fi
			return 1
		}
	fi
	rm -f "${IPSET_CURRENT_STAGE}" || return 1
	if [ "${RESTART_REQUIRED}" = "1" ] &&
		{ [ "${ADGUARD_WAS_RUNNING}" = "1" ] || pidof "${PROCS}" >/dev/null 2>&1; }; then
		DNSMASQ_RESTART_SKIP="${ADGUARDHOME_SKIP_DNSMASQ_RESTART:-}"
		ADGUARDHOME_SKIP_DNSMASQ_RESTART="1"
		lower_script restart
		RESTART_REQUIRED="$?"
		ADGUARDHOME_SKIP_DNSMASQ_RESTART="${DNSMASQ_RESTART_SKIP}"
		[ "${RESTART_REQUIRED}" -eq 0 ] || return 1
	fi
	dnsmasq_ipset_state_mark_cleanup "${SNAPSHOT_DIR}" || return 1
}

# dnsmasq_publish_staged_config refreshes IPSET state and atomically publishes a staged dnsmasq configuration, restoring prior state if the transaction fails.
dnsmasq_publish_staged_config() (
	ADGUARD_WAS_RUNNING="0"
	CONFIG_PUBLISHED="0"
	CONFIG_FILE="$1"
	CONFIG_STAGE="$2"
	CONFIG_BACKUP="${CONFIG_STAGE}.previous"
	CONFIG_BACKUP_RETAIN="0"
	IPSET_SNAPSHOT_DIR="$3"
	ROLLBACK_ACTIVE="0"
	SNAPSHOT_READY="0"
	TRANSACTION_SIGNAL_PENDING="0"
	[ "$(pidof "${PROCS}" 2>/dev/null | wc -w)" -gt 0 ] && ADGUARD_WAS_RUNNING="1"
	TRANSACTION_ACTIVE="1"
	# dnsmasq_config_association_create durably associates the dnsmasq backup with its pending IPSet snapshot before refresh or publication.
	dnsmasq_config_association_create() {
		local CONFIG_ASSOCIATION_STAGE
		CONFIG_ASSOCIATION_STAGE="${IPSET_SNAPSHOT_DIR}/config.pending.$$"
		{
			printf '%s\n' "${CONFIG_BACKUP}"
			printf '%s\n' "${CONFIG_FILE}"
		} >"${CONFIG_ASSOCIATION_STAGE}" || {
			rm -f "${CONFIG_ASSOCIATION_STAGE}"
			return 1
		}
		mv "${CONFIG_ASSOCIATION_STAGE}" "${IPSET_SNAPSHOT_DIR}/config.pending" || {
			rm -f "${CONFIG_ASSOCIATION_STAGE}"
			return 1
		}
		[ -f "${IPSET_SNAPSHOT_DIR}/cleanup.only" ] && [ ! -L "${IPSET_SNAPSHOT_DIR}/cleanup.only" ] || return 1
		[ ! -e "${IPSET_SNAPSHOT_DIR}/restore.pending" ] && [ ! -L "${IPSET_SNAPSHOT_DIR}/restore.pending" ] || return 1
		mv "${IPSET_SNAPSHOT_DIR}/cleanup.only" "${IPSET_SNAPSHOT_DIR}/restore.pending" || return 1
	}
	# dnsmasq_publish_rollback_published restores the pre-publication dnsmasq and IPSet state after an unsafe publication.
	dnsmasq_publish_rollback_published() {
		ROLLBACK_ACTIVE="1"
		if ! dnsmasq_ipset_state_recover_pending; then
			agh_log error dnsmasq_params "state=publication action=rollback result=failed config=${CONFIG_FILE} snapshot=${IPSET_SNAPSHOT_DIR}"
			CONFIG_BACKUP_RETAIN="1"
			ROLLBACK_ACTIVE="0"
			return 1
		fi
		CONFIG_PUBLISHED="0"
		ROLLBACK_ACTIVE="0"
		return 0
	}
	# dnsmasq_publish_abort aborts a staged dnsmasq configuration transaction, restoring or finalizing its IPSet snapshot as appropriate and exiting with failure when the abort proceeds.
	dnsmasq_publish_abort() {
		if [ "${ROLLBACK_ACTIVE:-0}" = "1" ]; then
			TRANSACTION_SIGNAL_PENDING="1"
			return 0
		fi
		if [ "${TRANSACTION_SIGNAL_PENDING:-0}" = "0" ]; then
			trap 'TRANSACTION_SIGNAL_PENDING="1"' HUP INT QUIT ABRT TERM TSTP
		fi
		trap '' HUP INT QUIT ABRT TERM TSTP
		if [ ! -e "${CONFIG_STAGE}" ]; then
			CONFIG_PUBLISHED="1"
		fi
		if [ "${CONFIG_PUBLISHED:-0}" = "1" ] && [ "${SNAPSHOT_READY:-0}" = "1" ]; then
			if dnsmasq_ipset_state_mark_cleanup "${IPSET_SNAPSHOT_DIR}"; then
				dnsmasq_ipset_state_finalize_cleanup "${IPSET_SNAPSHOT_DIR}" cleanup.pending ||
					agh_log error dnsmasq_params "state=signal action=finalize_snapshot result=failed snapshot=${IPSET_SNAPSHOT_DIR}"
				SNAPSHOT_READY="0"
			else
				agh_log error dnsmasq_params "state=signal action=mark_cleanup result=failed snapshot=${IPSET_SNAPSHOT_DIR}"
				if dnsmasq_publish_rollback_published; then
					SNAPSHOT_READY="0"
				else
					agh_log error dnsmasq_params "state=signal action=rollback_publication result=failed snapshot=${IPSET_SNAPSHOT_DIR}"
				fi
			fi
		fi
		if [ "${TRANSACTION_ACTIVE:-0}" = "1" ] && [ "${SNAPSHOT_READY:-0}" = "1" ] && [ "${CONFIG_PUBLISHED:-0}" = "0" ] && [ "${ROLLBACK_ACTIVE:-0}" = "0" ]; then
			trap '' HUP INT QUIT ABRT TERM TSTP
			if [ -f "${IPSET_SNAPSHOT_DIR}/cleanup.only" ] && [ ! -L "${IPSET_SNAPSHOT_DIR}/cleanup.only" ] &&
				dnsmasq_ipset_state_mark_cleanup_only "${IPSET_SNAPSHOT_DIR}"; then
				dnsmasq_ipset_state_finalize_cleanup "${IPSET_SNAPSHOT_DIR}" cleanup.only ||
					agh_log error dnsmasq_params "state=signal action=finalize_snapshot result=failed snapshot=${IPSET_SNAPSHOT_DIR}"
			else
				ROLLBACK_ACTIVE="1"
				if dnsmasq_ipset_state_restore "${IPSET_SNAPSHOT_DIR}" "${ADGUARD_WAS_RUNNING}"; then
					dnsmasq_ipset_state_finalize_cleanup "${IPSET_SNAPSHOT_DIR}" cleanup.pending ||
						agh_log error dnsmasq_params "state=signal action=finalize_snapshot result=failed snapshot=${IPSET_SNAPSHOT_DIR}"
				else
					agh_log error dnsmasq_params "state=signal action=restore_ipset result=failed snapshot=${IPSET_SNAPSHOT_DIR}"
				fi
				ROLLBACK_ACTIVE="0"
			fi
			trap - HUP INT QUIT ABRT TERM TSTP
		fi
		[ "${CONFIG_PUBLISHED:-0}" = "1" ] || rm -f "${CONFIG_STAGE}"
		[ "${CONFIG_BACKUP_RETAIN:-0}" = "1" ] || rm -f "${CONFIG_BACKUP}"
		exit 1
	}
	# dnsmasq_publish_locked snapshots and refreshes IPSet state, publishes the staged dnsmasq configuration, and restores state if refresh or publication fails.
	dnsmasq_publish_locked() {
		dnsmasq_ipset_state_recover_pending || {
			TRANSACTION_ACTIVE="0"
			rm -f "${CONFIG_STAGE}"
			return 1
		}
		dnsmasq_ipset_state_cleanup_stages || {
			TRANSACTION_ACTIVE="0"
			rm -f "${CONFIG_STAGE}"
			return 1
		}
		if ! dnsmasq_ipset_state_snapshot "${IPSET_SNAPSHOT_DIR}"; then
			TRANSACTION_ACTIVE="0"
			rm -f "${CONFIG_STAGE}"
			return 1
		fi
		SNAPSHOT_READY="1"
		if ! cp -p "${CONFIG_FILE}" "${CONFIG_BACKUP}"; then
			if dnsmasq_ipset_state_mark_cleanup_only "${IPSET_SNAPSHOT_DIR}" &&
				dnsmasq_ipset_state_finalize_cleanup "${IPSET_SNAPSHOT_DIR}" cleanup.only; then
				SNAPSHOT_READY="0"
			else
				agh_log error dnsmasq_params "state=backup action=finalize_snapshot result=failed snapshot=${IPSET_SNAPSHOT_DIR}"
			fi
			TRANSACTION_ACTIVE="0"
			rm -f "${CONFIG_STAGE}"
			return 1
		fi
		if ! dnsmasq_config_association_create; then
			TRANSACTION_ACTIVE="0"
			if [ -f "${IPSET_SNAPSHOT_DIR}/cleanup.only" ] && [ ! -L "${IPSET_SNAPSHOT_DIR}/cleanup.only" ]; then
				dnsmasq_ipset_state_finalize_cleanup "${IPSET_SNAPSHOT_DIR}" cleanup.only ||
					agh_log error dnsmasq_params "state=association action=finalize_snapshot result=failed snapshot=${IPSET_SNAPSHOT_DIR}"
			fi
			rm -f "${CONFIG_BACKUP}" "${CONFIG_STAGE}"
			return 1
		fi
		if ! IPSet_Refresh "${CONFIG_STAGE}"; then
			ROLLBACK_ACTIVE="1"
			if dnsmasq_ipset_state_restore "${IPSET_SNAPSHOT_DIR}" "${ADGUARD_WAS_RUNNING}"; then
				dnsmasq_ipset_state_finalize_cleanup "${IPSET_SNAPSHOT_DIR}" cleanup.pending ||
					agh_log error dnsmasq_params "state=refresh action=finalize_snapshot result=failed snapshot=${IPSET_SNAPSHOT_DIR}"
			else
				agh_log error dnsmasq_params "state=refresh action=restore_ipset result=failed snapshot=${IPSET_SNAPSHOT_DIR}"
			fi
			ROLLBACK_ACTIVE="0"
			if [ "${TRANSACTION_SIGNAL_PENDING}" = "1" ]; then
				TRANSACTION_SIGNAL_PENDING="0"
				TRANSACTION_ACTIVE="0"
				dnsmasq_publish_abort
			fi
			TRANSACTION_ACTIVE="0"
			rm -f "${CONFIG_STAGE}"
			return 1
		fi
		if ! mv "${CONFIG_STAGE}" "${CONFIG_FILE}"; then
			ROLLBACK_ACTIVE="1"
			if dnsmasq_ipset_state_restore "${IPSET_SNAPSHOT_DIR}" "${ADGUARD_WAS_RUNNING}"; then
				dnsmasq_ipset_state_finalize_cleanup "${IPSET_SNAPSHOT_DIR}" cleanup.pending ||
					agh_log error dnsmasq_params "state=publication action=finalize_snapshot result=failed snapshot=${IPSET_SNAPSHOT_DIR}"
			else
				agh_log error dnsmasq_params "state=publication action=restore_ipset result=failed snapshot=${IPSET_SNAPSHOT_DIR}"
			fi
			ROLLBACK_ACTIVE="0"
			if [ "${TRANSACTION_SIGNAL_PENDING}" = "1" ]; then
				TRANSACTION_SIGNAL_PENDING="0"
				TRANSACTION_ACTIVE="0"
				dnsmasq_publish_abort
			fi
			TRANSACTION_ACTIVE="0"
			rm -f "${CONFIG_STAGE}"
			return 1
		fi
		CONFIG_PUBLISHED="1"
		if ! dnsmasq_ipset_state_mark_cleanup "${IPSET_SNAPSHOT_DIR}"; then
			agh_log error dnsmasq_params "state=publication action=mark_cleanup result=failed snapshot=${IPSET_SNAPSHOT_DIR}"
			dnsmasq_publish_rollback_published ||
				agh_log error dnsmasq_params "state=publication action=rollback_publication result=failed snapshot=${IPSET_SNAPSHOT_DIR}"
			TRANSACTION_ACTIVE="0"
			return 1
		fi
		TRANSACTION_ACTIVE="0"
		rm -f "${CONFIG_BACKUP}"
		dnsmasq_ipset_state_finalize_cleanup "${IPSET_SNAPSHOT_DIR}" cleanup.pending ||
			agh_log error dnsmasq_params "state=publication action=finalize_snapshot result=failed snapshot=${IPSET_SNAPSHOT_DIR}"
		return 0
	}
	IPSET_LOCK_INTERRUPT_CALLBACK="dnsmasq_publish_abort"
	trap 'dnsmasq_publish_abort' HUP INT QUIT ABRT TERM TSTP
	IPSet_Lock dnsmasq_publish_locked
	STATUS="$?"
	IPSET_LOCK_INTERRUPT_CALLBACK=""
	trap - HUP INT QUIT ABRT TERM TSTP
	[ "${CONFIG_BACKUP_RETAIN}" = "1" ] || rm -f "${CONFIG_BACKUP}"
	if [ "${STATUS}" -ne 0 ] && [ "${SNAPSHOT_READY}" = "0" ]; then
		TRANSACTION_ACTIVE="0"
		rm -f "${CONFIG_STAGE}"
	fi
	return "${STATUS}"
)

# dnsmasq_params configures dnsmasq for the LAN or specified SDN interface, including DNS routing, reverse zones, and optional IPSet refresh.
dnsmasq_params() {
	local BRIDGE_OPTIONS_STAGE CONFIG CONFIG_FILE CONFIG_STAGE IPSET_SNAPSHOT_DIR IPV6_REVERSE NET_ADDR NET_ADDR6 LAN_IF LAN_IF_SDN NIVARS NDVARS RC_SUPPORT DHCP_IF PRE_START_HOOK
	PRE_START_HOOK="${2:-}"
	if adguard_lan_mode && [ "${CONFIG_DNSMASQ_MODE:-auto}" = "disabled" ] && ! dns_handoff_is_active; then
		agh_log info dnsmasq "state=skip reason=lan_mode_dnsmasq_disabled"
		return 0
	fi
	dnsmasq_resolv_conf_cleanup
	RC_SUPPORT="$(nvram get rc_support 2>/dev/null)"
	LAN_IF="$(nvram get lan_ifname 2>/dev/null)"
	case "${1:-}" in
		"" | /etc/dnsmasq.conf)
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
	CONFIG_FILE="${CONFIG}"
	[ -f "${CONFIG_FILE}" ] || return 0
	[ ! -L "${CONFIG_FILE}" ] || return 1
	# Firmware invokes postconf before starting the replacement dnsmasq process.
	if [ "${PRE_START_HOOK}" != "pre_start" ] &&
		adguard_lan_mode && ! adguard_dnsmasq_running &&
		[ "${CONFIG_DNSMASQ_MODE:-auto}" != "enabled" ] &&
		! dns_handoff_is_active; then
		return 0
	fi
	# Pre-start bypasses replacement-process absence, never native DNS recovery.
	if [ "$(pidof "${PROCS}" 2>/dev/null | wc -w)" -eq 0 ] && ! dns_handoff_is_active; then
		return 0
	fi
	CONFIG_STAGE="${CONFIG_FILE}.adguard.$$"
	if ! cp -p "${CONFIG_FILE}" "${CONFIG_STAGE}"; then
		rm -f "${CONFIG_STAGE}"
		return 1
	fi
	CONFIG="${CONFIG_STAGE}"
	if ! dnsmasq_delete_matching \
		"${CONFIG}" \
		"add-subnet=" \
		"port=" \
		"add-mac" \
		"dhcp-option=${DHCP_IF},6"; then
		rm -f "${CONFIG_STAGE}"
		return 1
	fi
	if ! printf "%s\n" \
		"dhcp-option=${DHCP_IF},6,${NET_ADDR}" \
		"local=/$(ipv4_reverse_zone "${NET_ADDR}")/" \
		"local=/10.in-addr.arpa/" \
		"local=//" \
		"port=553" \
		"add-mac" >>"${CONFIG}"; then
		rm -f "${CONFIG_STAGE}"
		return 1
	fi
	if [ -n "${NET_ADDR6}" ]; then
		IPV6_REVERSE="$(ipv6_reverse_zone "${NET_ADDR6}")"
		printf "%s\n" \
			"add-subnet=32,128" \
			"local=/${IPV6_REVERSE}/" >>"${CONFIG}" || {
			rm -f "${CONFIG_STAGE}"
			return 1
		}
	else
		printf "%s\n" "add-subnet=32" >>"${CONFIG}" || {
			rm -f "${CONFIG_STAGE}"
			return 1
		}
	fi
	case "${DHCP_IF}:${RC_SUPPORT}" in
		lan:*mtlancfg*)
			:
			;;
		lan:*)
			BRIDGE_OPTIONS_STAGE="${CONFIG_STAGE}.bridge-options"
			if ! private_ipv4_bridge_dns_options_with_fallbacks "${LAN_IF}" >"${BRIDGE_OPTIONS_STAGE}"; then
				rm -f "${BRIDGE_OPTIONS_STAGE}" "${CONFIG_STAGE}"
				return 1
			fi
			while read -r NIVARS NDVARS; do
				[ -n "${NIVARS}" ] && [ -n "${NDVARS}" ] || continue
				if ! printf "%s\n" "dhcp-option=${NIVARS},6,${NDVARS}" >>"${CONFIG}"; then
					rm -f "${BRIDGE_OPTIONS_STAGE}" "${CONFIG_STAGE}"
					return 1
				fi
			done <"${BRIDGE_OPTIONS_STAGE}"
			rm -f "${BRIDGE_OPTIONS_STAGE}"
			;;
	esac
	IPSET_REFRESH_FROM_DNSMASQ="1"
	IPSET_SNAPSHOT_DIR="${WORK_DIR}/.AdGuardHome.dnsmasq-ipset.$$"
	dnsmasq_publish_staged_config "${CONFIG_FILE}" "${CONFIG_STAGE}" "${IPSET_SNAPSHOT_DIR}" || return 1

	return 0
}

# dnsmasq_action_handler applies the requested dnsmasq configuration action, or skips it in LAN mode when dnsmasq is inactive and unmanaged.
dnsmasq_action_handler() {
	local PRE_START_HOOK=""
	[ "${1:-}" = "pre_start" ] && PRE_START_HOOK="pre_start"
	if [ "${PRE_START_HOOK}" != "pre_start" ] &&
		adguard_lan_mode && ! adguard_dnsmasq_running && ! dns_handoff_is_active; then
		case "${CONFIG_DNSMASQ_MODE:-auto}" in
			enabled) ;;
			*)
				dnsmasq_resolv_conf_cleanup
				agh_log info dnsmasq "state=skip reason=lan_mode_dnsmasq_not_running"
				return 0
				;;
		esac
	fi
	if [ "${PRE_START_HOOK}" = "pre_start" ]; then
		dnsmasq_params "" "${PRE_START_HOOK}"
	elif [ -n "${1:-}" ]; then
		dnsmasq_params "${1}"
	else
		dnsmasq_params
	fi
}

# interface_ipv4_addr prints the first usable global IPv4 address assigned to the specified network interface.
interface_ipv4_addr() {
	local IFACE
	IFACE="$1"
	[ -n "${IFACE}" ] || return 1
	have_cmd ip || return 1
	ip -o -4 addr list "${IFACE}" scope global 2>/dev/null | /usr/bin/awk '
		$0 !~ /(^|[[:space:]])(tentative|deprecated)([[:space:]]|$)/ {
			split($4, ip_addr, "/")
			if (!seen[ip_addr[1]]++) { print ip_addr[1]; exit }
		}'
}

# interface_ipv6_addr prints the first usable global IPv6 address assigned to the specified interface.
interface_ipv6_addr() {
	local IFACE
	IFACE="$1"
	[ -n "${IFACE}" ] || return 1
	have_cmd ip || return 1
	ip -o -6 addr list "${IFACE}" scope global 2>/dev/null | /usr/bin/awk '
		$0 !~ /(^|[[:space:]])(tentative|deprecated|dadfailed|temporary)([[:space:]]|$)/ {
			split($4, ip_addr, "/")
			if (!seen[ip_addr[1]]++) { print ip_addr[1]; exit }
		}'
}

# ipv4_is_usable_unicast validates that an IPv4 address is a usable unicast address.
ipv4_is_usable_unicast() {
	printf '%s\n' "$1" | awk -F. '
		NF != 4 { exit 1 }
		{
			for (i = 1; i <= 4; i++) {
				if ($i !~ /^[0-9][0-9]*$/ || $i < 0 || $i > 255) exit 1
			}
			if ($1 == 0 || $1 == 127 || $1 >= 224) exit 1
		}
	'
}

# adguard_refresh_lan_bind_addresses updates AdGuardHome's LAN WebUI address and DNS bind hosts in the YAML configuration, preserving the active configuration when staging or validation fails.
adguard_refresh_lan_bind_addresses() {
	local ACTIVE_MD5 BIND_HOSTS LAN_ADDR LAN_ADDR6 LAN_IF NVRAM_ADDR6 REWRITE_FILE SAVED_TRAPS STAGED_MD5 TEMP_FILE WEB_PORT YAML_DIR
	LAN_BIND_ADDRESSES_CHANGED="0"
	LAN_BIND_REFRESH_FAILURE_REASON=""
	adguard_lan_mode || return 0
	YAML_DIR="${YAML_FILE%/*}"
	[ "${YAML_DIR}" != "${YAML_FILE}" ] || YAML_DIR="."
	if [ "${YAML_FILE}" != "${YAML_DIR}/AdGuardHome.yaml" ] || [ ! -f "${YAML_FILE}" ] || [ -L "${YAML_FILE}" ]; then
		LAN_BIND_REFRESH_FAILURE_REASON="active_yaml_not_regular"
		agh_log warning adguard_refresh_lan_bind_addresses "state=config_refresh result=failed reason=active_yaml_not_regular config_preserved=1"
		return 1
	fi
	LAN_IF="$(nvram get lan_ifname 2>/dev/null)"
	if [ -n "${LAN_IF}" ]; then
		LAN_ADDR="$(interface_ipv4_addr "${LAN_IF}")"
		LAN_ADDR6="$(interface_ipv6_addr "${LAN_IF}")"
	fi
	if ! ipv4_is_usable_unicast "${LAN_ADDR:-}"; then
		LAN_BIND_REFRESH_FAILURE_REASON="lan_ipv4_unavailable"
		agh_log warning adguard_refresh_lan_bind_addresses "state=config_refresh result=failed reason=lan_ipv4_unavailable config_preserved=1"
		return 1
	fi
	if [ -z "${LAN_ADDR6:-}" ] && [ -n "${LAN_IF}" ] && have_cmd ip; then
		NVRAM_ADDR6="$(nvram get ipv6_rtr_addr 2>/dev/null)"
		case "${NVRAM_ADDR6}" in
			"" | ::) ;;
			*:*)
				LAN_ADDR6="$(ip -o -6 addr list "${LAN_IF}" scope global 2>/dev/null | /usr/bin/awk -v candidate="${NVRAM_ADDR6}" '
					$0 !~ /(^|[[:space:]])(tentative|deprecated|dadfailed|temporary)([[:space:]]|$)/ {
						split($4, ip_addr, "/")
						if (ip_addr[1] == candidate) { print candidate; exit }
					}')"
				;;
		esac
	fi
	# Keep every discovered bridge address bound because dnsmasq advertises each
	# bridge's own address to clients on that network.
	BIND_HOSTS="$({
		printf '%s\n' 127.0.0.1 "${LAN_ADDR}" "${LAN_ADDR6:-}"
		private_ipv4_bridge_dns_options_with_fallbacks "${LAN_IF}" | /usr/bin/awk 'NF > 1 { print $2 }'
	} | /usr/bin/awk 'NF && !seen[$0]++ { print }')"
	WEB_PORT="$(awk '
		function yaml_key_is(line, expected, text, separator, key) {
			text = line
			sub(/^[[:space:]]*/, "", text)
			separator = index(text, ":")
			if (!separator)
				return 0
			key = substr(text, 1, separator - 1)
			sub(/[[:space:]]*$/, "", key)
			return key == expected || key == "\"" expected "\"" || key == sprintf("%c%s%c", 39, expected, 39)
		}
		function yaml_mapping_header_is(line, expected, text, separator, value) {
			if (!yaml_key_is(line, expected))
				return 0
			text = line
			separator = index(text, ":")
			value = substr(text, separator + 1)
			sub(/^[[:space:]]*/, "", value)
			return value == "" || value ~ /^#/ || value ~ /^&[^][{},[:space:]]+([[:space:]]*#.*)?$/
		}
		/^[^[:space:]]/ && yaml_mapping_header_is($0, "http") { in_http = 1; next }
		in_http && /^[^[:space:]]/ { exit }
		in_http && yaml_key_is($0, "address") {
			value = $0
			value = substr(value, index(value, ":") + 1)
			sub(/[[:space:]]+#.*$/, "", value)
			gsub(/[[:space:]"'"'"']/, "", value)
			count = split(value, components, ":")
			print components[count]
			exit
		}
	' "${YAML_FILE}")"
	case "${WEB_PORT}" in
		"" | *[!0-9]*) return 1 ;;
	esac
	[ "${WEB_PORT}" -gt 0 ] && [ "${WEB_PORT}" -le 65535 ] || return 1
	TEMP_FILE="${YAML_DIR}/.AdGuardHome.yaml.lan-bind.$$"
	REWRITE_FILE="${TEMP_FILE}.rewrite"
	SAVED_TRAPS="$(trap)"
	trap 'rm -f "${TEMP_FILE}" "${REWRITE_FILE}"; trap - HUP INT QUIT ABRT TERM TSTP; [ -n "${SAVED_TRAPS}" ] && eval "${SAVED_TRAPS}"; exit 1' HUP INT QUIT ABRT TERM TSTP
	(umask 077 && cp -p "${YAML_FILE}" "${TEMP_FILE}") || {
		rm -f "${TEMP_FILE}"
		agh_log warning adguard_refresh_lan_bind_addresses "state=config_refresh result=failed reason=stage_copy_failed config_preserved=1"
		trap - HUP INT QUIT ABRT TERM TSTP
		[ -n "${SAVED_TRAPS}" ] && eval "${SAVED_TRAPS}"
		return 1
	}
	(umask 077 && awk -v bind_hosts="${BIND_HOSTS}" -v web_address="${LAN_ADDR}:${WEB_PORT}" '
		function indentation(line) { match(line, /^[[:space:]]*/); return RLENGTH }
		function yaml_key_is(line, expected, text, separator, key) {
			text = line
			sub(/^[[:space:]]*/, "", text)
			separator = index(text, ":")
			if (!separator)
				return 0
			key = substr(text, 1, separator - 1)
			sub(/[[:space:]]*$/, "", key)
			return key == expected || key == "\"" expected "\"" || key == sprintf("%c%s%c", 39, expected, 39)
		}
		function yaml_mapping_header_is(line, expected, text, separator, value) {
			if (!yaml_key_is(line, expected))
				return 0
			text = line
			separator = index(text, ":")
			value = substr(text, separator + 1)
			sub(/^[[:space:]]*/, "", value)
			return value == "" || value ~ /^#/ || value ~ /^&[^][{},[:space:]]+([[:space:]]*#.*)?$/
		}
		/^[^[:space:]]/ && yaml_mapping_header_is($0, "http") { in_http = 1; print; next }
		in_http && /^[^[:space:]]/ { in_http = 0 }
		in_http && yaml_key_is($0, "address") {
			separator = index($0, ":")
			print substr($0, 1, separator) " " web_address
			web_updated = 1
			next
		}
		/^[^[:space:]]/ && yaml_mapping_header_is($0, "dns") { in_dns = 1; print; next }
		in_dns && /^[^[:space:]]/ { in_dns = 0; in_binds = 0 }
		in_dns && yaml_key_is($0, "bind_hosts") {
			bind_indent = indentation($0)
			separator = index($0, ":")
			print substr($0, 1, separator)
			count = split(bind_hosts, hosts, "\n")
			for (host = 1; host <= count; host++)
				if (hosts[host] != "") print substr($0, 1, bind_indent) "  - " hosts[host]
			in_binds = 1
			binds_updated = 1
			next
		}
		in_binds && $0 ~ /^[[:space:]]*($|#)/ { next }
		in_binds && indentation($0) >= bind_indent && $0 ~ /^[[:space:]]*-[[:space:]]/ { next }
		in_binds && indentation($0) > bind_indent { next }
		in_binds { in_binds = 0 }
		{ print }
		END { exit(web_updated && binds_updated ? 0 : 1) }
	' "${TEMP_FILE}" >"${REWRITE_FILE}") || {
		rm -f "${TEMP_FILE}" "${REWRITE_FILE}"
		agh_log warning adguard_refresh_lan_bind_addresses "state=config_refresh result=failed reason=stage_rewrite_failed config_preserved=1"
		trap - HUP INT QUIT ABRT TERM TSTP
		[ -n "${SAVED_TRAPS}" ] && eval "${SAVED_TRAPS}"
		return 1
	}
	# Rewrite the preserved copy in place so the active YAML owner and mode survive
	# the eventual atomic replacement.  The rewrite file is created under umask 077.
	if ! cat "${REWRITE_FILE}" >"${TEMP_FILE}"; then
		rm -f "${TEMP_FILE}" "${REWRITE_FILE}"
		agh_log warning adguard_refresh_lan_bind_addresses "state=config_refresh result=failed reason=stage_rewrite_failed config_preserved=1"
		trap - HUP INT QUIT ABRT TERM TSTP
		[ -n "${SAVED_TRAPS}" ] && eval "${SAVED_TRAPS}"
		return 1
	fi
	rm -f "${REWRITE_FILE}"
	ACTIVE_MD5="$(md5sum "${YAML_FILE}")" || {
		rm -f "${TEMP_FILE}"
		agh_log warning adguard_refresh_lan_bind_addresses "state=config_refresh result=failed reason=stage_compare_failed config_preserved=1"
		trap - HUP INT QUIT ABRT TERM TSTP
		[ -n "${SAVED_TRAPS}" ] && eval "${SAVED_TRAPS}"
		return 1
	}
	STAGED_MD5="$(md5sum "${TEMP_FILE}")" || {
		rm -f "${TEMP_FILE}"
		agh_log warning adguard_refresh_lan_bind_addresses "state=config_refresh result=failed reason=stage_compare_failed config_preserved=1"
		trap - HUP INT QUIT ABRT TERM TSTP
		[ -n "${SAVED_TRAPS}" ] && eval "${SAVED_TRAPS}"
		return 1
	}
	ACTIVE_MD5="${ACTIVE_MD5%%[[:space:]]*}"
	STAGED_MD5="${STAGED_MD5%%[[:space:]]*}"
	case "${ACTIVE_MD5}:${STAGED_MD5}" in
		????????????????????????????????:????????????????????????????????)
			case "${ACTIVE_MD5}${STAGED_MD5}" in
				*[!0123456789abcdefABCDEF]*)
					rm -f "${TEMP_FILE}"
					agh_log warning adguard_refresh_lan_bind_addresses "state=config_refresh result=failed reason=stage_compare_failed config_preserved=1"
					trap - HUP INT QUIT ABRT TERM TSTP
					[ -n "${SAVED_TRAPS}" ] && eval "${SAVED_TRAPS}"
					return 1
					;;
			esac
			;;
		*)
			rm -f "${TEMP_FILE}"
			agh_log warning adguard_refresh_lan_bind_addresses "state=config_refresh result=failed reason=stage_compare_failed config_preserved=1"
			trap - HUP INT QUIT ABRT TERM TSTP
			[ -n "${SAVED_TRAPS}" ] && eval "${SAVED_TRAPS}"
			return 1
			;;
	esac
	# The monitor calls this refresh periodically.  Avoid starting a second
	# AdGuardHome process to validate content that is byte-for-byte unchanged.
	if [ "${ACTIVE_MD5}" = "${STAGED_MD5}" ]; then
		rm -f "${TEMP_FILE}"
		trap - HUP INT QUIT ABRT TERM TSTP
		[ -n "${SAVED_TRAPS}" ] && eval "${SAVED_TRAPS}"
		return 0
	fi
	if [ ! -x "${ADGUARDHOME_BINARY}" ] ||
		! "${ADGUARDHOME_BINARY}" --check-config -c "${TEMP_FILE}" --no-check-update -l /dev/null >/dev/null 2>&1; then
		rm -f "${TEMP_FILE}"
		agh_log warning adguard_refresh_lan_bind_addresses "state=config_refresh result=failed reason=adguard_config_validation_failed config_preserved=1"
		trap - HUP INT QUIT ABRT TERM TSTP
		[ -n "${SAVED_TRAPS}" ] && eval "${SAVED_TRAPS}"
		return 1
	fi
	if ! awk '
		function indentation(line) { match(line, /^[[:space:]]*/); return RLENGTH }
		function yaml_key_is(line, expected, text, separator, key) {
			text = line; sub(/^[[:space:]]*/, "", text); separator = index(text, ":")
			if (!separator) return 0
			key = substr(text, 1, separator - 1); sub(/[[:space:]]*$/, "", key)
			return key == expected || key == "\"" expected "\"" || key == sprintf("%c%s%c", 39, expected, 39)
		}
		function mapping_header_is(line, expected, text, separator, value) {
			if (!yaml_key_is(line, expected)) return 0
			text = line; separator = index(text, ":"); value = substr(text, separator + 1)
			sub(/^[[:space:]]*/, "", value)
			return value == "" || value ~ /^#/ || value ~ /^&[^][{},[:space:]]+([[:space:]]*#.*)?$/
		}
		/^[^[:space:]]/ {
			in_http = in_dns = in_binds = 0
			if (mapping_header_is($0, "http")) { http_maps++; in_http = 1 }
			else if (mapping_header_is($0, "dns")) { dns_maps++; in_dns = 1 }
			next
		}
		in_http && yaml_key_is($0, "address") {
			value = substr($0, index($0, ":") + 1); sub(/[[:space:]]+#.*$/, "", value); gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
			if (value != "" && value != "~" && value !~ /^(null|Null|NULL)$/ && value !~ /^\*/) usable_addresses++
			address_keys++
		}
		in_dns && yaml_key_is($0, "bind_hosts") { bind_keys++; bind_indent = indentation($0); in_binds = 1; next }
		in_binds && indentation($0) > bind_indent && $0 ~ /^[[:space:]]*-[[:space:]]*[^#[:space:]][^#]*([[:space:]]+#.*)?$/ { usable_binds++; next }
		in_binds && $0 !~ /^[[:space:]]*($|#)/ { in_binds = 0 }
		END { exit(http_maps == 1 && dns_maps == 1 && address_keys == 1 && usable_addresses == 1 && bind_keys == 1 && usable_binds > 0 ? 0 : 1) }
	' "${TEMP_FILE}"; then
		rm -f "${TEMP_FILE}"
		agh_log warning adguard_refresh_lan_bind_addresses "state=config_refresh result=failed reason=staged_bind_structure_invalid config_preserved=1"
		trap - HUP INT QUIT ABRT TERM TSTP
		[ -n "${SAVED_TRAPS}" ] && eval "${SAVED_TRAPS}"
		return 1
	fi
	if ! mv -f "${TEMP_FILE}" "${YAML_FILE}"; then
		rm -f "${TEMP_FILE}"
		agh_log warning adguard_refresh_lan_bind_addresses "state=config_refresh result=failed reason=atomic_replace_failed config_preserved=1"
		trap - HUP INT QUIT ABRT TERM TSTP
		[ -n "${SAVED_TRAPS}" ] && eval "${SAVED_TRAPS}"
		return 1
	fi
	LAN_BIND_ADDRESSES_CHANGED="1"
	trap - HUP INT QUIT ABRT TERM TSTP
	[ -n "${SAVED_TRAPS}" ] && eval "${SAVED_TRAPS}"
	return 0
}

# ipv4_reverse_zone converts an IPv4 address to its reverse DNS zone name.
ipv4_reverse_zone() {
	printf "%s\n" "$1" | awk 'BEGIN{FS="."}{print $2"."$1".in-addr.arpa"}'
}

ipv6_reverse_zone() {
	printf "%s\n" "$1" | sed 's/.$//' | awk -F: '{for(i=1;i<=NF;i++)x=x""sprintf (":%4s", $i);gsub(/ /,"0",x);print x}' | cut -c 2- | cut -c 1-20 | sed 's/://g;s/^.*$/\n&\n/;tx;:x;s/\(\n.\)\(.*\)\(.\n\)/\3\2\1/;tx;s/\n//g;s/\(.\)/\1./g;s/$/ip6.arpa/'
}

# netcheck_config prints the explicitly set network-check value, the scoped configuration value, or the supplied default.
netcheck_config() {
	local is_set value
	eval "is_set=\${$1_SET:-}"
	eval "value=\${$1:-}"
	if [ -n "${is_set}" ] && [ -n "${value}" ]; then
		printf '%s\n' "${value}"
		return 0
	fi
	eval "value=\${CONFIG_${1#ADGUARD_}:-}"
	printf '%s\n' "${value:-$2}"
}

# netcheck_dns_ok checks whether any provided hostname resolves through the specified DNS server.
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

# netcheck_ping_ok checks whether any provided host responds to a single ping within three seconds.
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

# netcheck_legacy waits for system time and verifies connectivity through local DNS, ping, and HTTP checks against configured hosts.
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

# netcheck checks readiness using the configured mode and takes no arguments.
# LAN returns 0 without time or public network probes; legacy delegates to
# netcheck_legacy. WAN waits for system time, requires DNS or ping success, and
# probes HTTP when configured. Returns 0 on readiness or 1 on a failed check.
netcheck() {
	local dns_ok dns_server hosts http_required mode ping_ok timeout waited
	mode="$(netcheck_config ADGUARD_NETCHECK_MODE "${DEFAULT_ADGUARD_NETCHECK_MODE}")"
	case "${mode}" in
		lan | LAN)
			# LAN/AP/Bridge needs no WAN or NTP probe before the daemon starts.
			# LAN mode skips public WAN and NTP probes. Local DNS responsiveness is checked
			# separately after AdGuardHome is expected to be serving DNS.
			return 0
			;;
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

# private_ipv4_bridge_dns_options prints usable global IPv4 addresses assigned to bridge interfaces other than the LAN interface.
private_ipv4_bridge_dns_options() {
	local ADDRESS_OUTPUT BRIDGE_ADDR BRIDGE_IF LAN_IF OPTIONS
	LAN_IF="${1:-}"
	[ -n "${LAN_IF}" ] || return 1
	if have_cmd ip; then
		if ADDRESS_OUTPUT="$(ip -o -4 addr show scope global 2>/dev/null)"; then
			OPTIONS="$(printf '%s\n' "${ADDRESS_OUTPUT}" | /usr/bin/awk -v lan_if="${LAN_IF}" '
			function usable_ip(ip, broadcast, octets) {
				split(ip, octets, ".")
				return ip != broadcast && ip ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && (octets[1] == 10 || (octets[1] == 172 && octets[2] >= 16 && octets[2] <= 31) || (octets[1] == 192 && octets[2] == 168)) && octets[3] <= 255 && octets[4] <= 255
			}
			$2 ~ /^br/ && $2 != lan_if && $0 !~ /(^|[[:space:]])(tentative|deprecated)([[:space:]]|$)/ {
				broadcast = ""
				for (i = 1; i < NF; i++) if ($i == "brd") broadcast = $(i + 1)
				for (i = 1; i <= NF; i++) {
					if ($i == "inet") {
						split($(i + 1), ip_addr, "/")
						if (usable_ip(ip_addr[1], broadcast) && !seen[$2, ip_addr[1]]++) { print $2 " " ip_addr[1] }
					}
				}
			}
			')"
		elif ADDRESS_OUTPUT="$(ip -4 addr show scope global 2>/dev/null)"; then
			OPTIONS="$(printf '%s\n' "${ADDRESS_OUTPUT}" | /usr/bin/awk -v lan_if="${LAN_IF}" '
				function usable_ip(ip, broadcast, octets) {
					split(ip, octets, ".")
					return ip != broadcast && ip ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && (octets[1] == 10 || (octets[1] == 172 && octets[2] >= 16 && octets[2] <= 31) || (octets[1] == 192 && octets[2] == 168)) && octets[3] <= 255 && octets[4] <= 255
				}
				/^[0-9]+: / {
					iface = $2
					sub(/:$/, "", iface)
				}
				$1 == "inet" && iface ~ /^br/ && iface != lan_if && $0 !~ /(^|[[:space:]])(tentative|deprecated)([[:space:]]|$)/ {
					split($2, ip_addr, "/")
					broadcast = ""
					for (i = 1; i < NF; i++) if ($i == "brd") broadcast = $(i + 1)
					if (usable_ip(ip_addr[1], broadcast) && !seen[iface, ip_addr[1]]++) { print iface " " ip_addr[1] }
				}
				')"
		else
			return 1
		fi
		printf '%s\n' "${OPTIONS}" | while read -r BRIDGE_IF BRIDGE_ADDR; do
			[ -n "${BRIDGE_IF}" ] && [ -n "${BRIDGE_ADDR}" ] || continue
			agh_log info bridge_discovery "state=discovered family=ipv4 interface=${BRIDGE_IF} address=${BRIDGE_ADDR}"
		done
		printf '%s\n' "${OPTIONS}"
		return
	fi
	return 1
}

# private_ipv4_bridge_address_is_assigned verifies that the specified IPv4 address is assigned to the bridge interface.
private_ipv4_bridge_address_is_assigned() {
	local BRIDGE_ADDR BRIDGE_IF
	BRIDGE_IF="${1:-}"
	BRIDGE_ADDR="${2:-}"
	[ -n "${BRIDGE_IF}" ] && [ -n "${BRIDGE_ADDR}" ] || return 1
	if have_cmd ip; then
		if ip -o -4 addr show dev "${BRIDGE_IF}" scope global 2>/dev/null | /usr/bin/awk -v expected="${BRIDGE_ADDR}" '
			{ for (i = 1; i < NF; i++) if ($i == "inet") { split($(i + 1), address, "/"); if (address[1] == expected) found = 1 } }
			END { exit(found ? 0 : 1) }
		'; then
			return 0
		fi
	fi
	if have_cmd ifconfig; then
		ifconfig "${BRIDGE_IF}" 2>/dev/null | /usr/bin/awk -v expected="${BRIDGE_ADDR}" '
			{
				for (i = 1; i <= NF; i++) {
					address = $i
					sub(/^addr:/, "", address)
					if ((address == expected && $(i - 1) == "inet") || ($i ~ /^addr:/ && address == expected)) found = 1
				}
			}
			END { exit(found ? 0 : 1) }
		'
		return
	fi
	return 1
}

# private_ipv4_bridge_dns_options_with_fallbacks selects IPv4 bridge DNS options for the specified LAN interface, using route-based and legacy fallbacks when needed.
private_ipv4_bridge_dns_options_with_fallbacks() {
	local BRIDGE_ADDR BRIDGE_IF LAN_IF OPTIONS
	LAN_IF="${1:-}"
	[ -n "${LAN_IF}" ] || return 1
	if OPTIONS="$(private_ipv4_bridge_dns_options "${LAN_IF}")"; then
		printf "%s\n" "${OPTIONS}"
		return 0
	fi
	OPTIONS="$(private_ipv4_route_dns_options "${LAN_IF}")"
	if [ -z "${OPTIONS}" ]; then
		OPTIONS="$(private_ipv4_legacy_route_dns_options "${LAN_IF}")"
	fi
	printf '%s\n' "${OPTIONS}" | while read -r BRIDGE_IF BRIDGE_ADDR; do
		[ -n "${BRIDGE_IF}" ] && [ -n "${BRIDGE_ADDR}" ] || continue
		case "${BRIDGE_ADDR}" in
			169.254.*) continue ;;
		esac
		private_ipv4_bridge_address_is_assigned "${BRIDGE_IF}" "${BRIDGE_ADDR}" || continue
		printf '%s %s\n' "${BRIDGE_IF}" "${BRIDGE_ADDR}"
	done
}

# private_ipv4_legacy_route_dns_options identifies private IPv4 router addresses for bridge interfaces other than the specified LAN interface and outputs interface-address pairs.
private_ipv4_legacy_route_dns_options() {
	local LAN_IF
	LAN_IF="${1:-}"
	[ -n "${LAN_IF}" ] || return 1
	have_cmd route || return 1
	route 2>/dev/null | awk -v lan_if="${LAN_IF}" '
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
			if (iface ~ /^br/ && iface != lan_if && private_ip($1) && !seen[iface]++) {
				dns_ip = router_ip($1)
				if (dns_ip != "") { print iface " " dns_ip }
			}
		}
	'
}

# private_ipv4_route_dns_options lists non-LAN bridge interfaces and their private IPv4 DNS source addresses from the routing table.
private_ipv4_route_dns_options() {
	local LAN_IF
	LAN_IF="${1:-}"
	[ -n "${LAN_IF}" ] || return 1
	if have_cmd ip; then
		ip route show 2>/dev/null | awk -v lan_if="${LAN_IF}" '
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
				if (iface ~ /^br/ && iface != lan_if && private_ip(dst) && !seen[iface]++) {
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

# proc_config resolves a process-tuning value from an explicit setting, operation configuration, or fallback default.

proc_config() {
	local is_set value
	eval "is_set=\${$1_SET:-}"
	eval "value=\${$1:-}"
	if [ -n "${is_set}" ] && [ -n "${value}" ]; then
		printf '%s\n' "${value}"
		return 0
	fi
	eval "value=\${CONFIG_${1#ADGUARD_}:-}"
	printf '%s\n' "${value:-$2}"
}

# proc_optimizations_locked applies the configured process and network kernel optimizations while holding the process-optimization lock, or restores managed settings when optimization is disabled.
proc_optimizations_locked() {
	local enabled profile
	enabled="$(proc_config ADGUARD_PROC_OPTIMIZE "${DEFAULT_ADGUARD_PROC_OPTIMIZE}")"
	profile="$(proc_config ADGUARD_PROC_PROFILE "${DEFAULT_ADGUARD_PROC_PROFILE}")"
	case "${enabled}" in
		YES | yes | Yes | ON | on | On | TRUE | true | True | 1) ;;
		*)
			proc_restore_locked
			return 0
			;;
	esac

	# safe: socket buffer ceilings prevent high-volume UDP DNS traffic from being
	# dropped because AdGuard Home's requested per-socket buffers are capped.
	# balanced: safe plus a shorter maximum-retransmit conntrack lifetime, which
	# releases stalled TCP DNS connection state sooner on memory-limited routers.
	# aggressive: balanced plus, when swap is active, strict virtual-memory
	# commitment and normal swap reclaim.  These retain a system-wide memory
	# reserve instead of allowing unrelated allocations to exhaust memory and kill
	# DNS.  Higher neighbour-cache thresholds avoid cache reclamation during large
	# client bursts, while unrestricted ICMP control replies keep path/error feedback
	# available to AdGuard Home's upstream traffic.  A larger PID space is applied
	# by every enabled profile to reduce PID collisions with concurrent NVRAM/user
	# scripts on long-running routers.
	case "${profile}" in
		off)
			proc_restore_locked
			return 0
			;;
		safe | balanced | aggressive) ;;
		*)
			agh_log warning proc_optimizations "state=proc_optimize action=validate_profile reason=invalid_profile result=skipped profile=${profile}"
			return 0
			;;
	esac

	proc_write rmem_max "4194304" "262144" "16777216"
	proc_write wmem_max "1048576" "262144" "16777216"
	proc_write pid_max "4194304" "300" "4194304"
	case "${profile}" in
		balanced | aggressive)
			proc_write conntrack_tcp_timeout_max_retrans "240" "1" "86400"
			;;
		*) proc_restore_one conntrack_tcp_timeout_max_retrans ;;
	esac
	case "${profile}" in
		aggressive)
			if proc_swap_active; then
				proc_write vm_overcommit_memory "2" "0" "2"
				proc_write vm_swappiness "60" "0" "200"
				proc_write vm_overcommit_ratio "50" "0" "100"
			else
				proc_restore_one vm_overcommit_memory
				proc_restore_one vm_swappiness
				proc_restore_one vm_overcommit_ratio
			fi
			proc_write ipv4_icmp_ratelimit "0" "0" "100000"
			proc_write ipv4_neigh_gc_thresh1 "256" "1" "1048576"
			proc_write ipv4_neigh_gc_thresh2 "1024" "1" "1048576"
			proc_write ipv4_neigh_gc_thresh3 "2048" "1" "1048576"
			if [ -n "$(nvram get ipv6_service 2>/dev/null)" ]; then
				proc_write ipv6_icmp_ratelimit "0" "0" "100000"
				proc_write ipv6_neigh_gc_thresh1 "256" "1" "1048576"
				proc_write ipv6_neigh_gc_thresh2 "1024" "1" "1048576"
				proc_write ipv6_neigh_gc_thresh3 "2048" "1" "1048576"
			else
				proc_restore_ipv6
			fi
			;;
		*)
			proc_restore_one vm_overcommit_memory
			proc_restore_one vm_swappiness
			proc_restore_one vm_overcommit_ratio
			proc_restore_one ipv4_icmp_ratelimit
			proc_restore_one ipv4_neigh_gc_thresh1
			proc_restore_one ipv4_neigh_gc_thresh2
			proc_restore_one ipv4_neigh_gc_thresh3
			proc_restore_ipv6
			;;
	esac
	return 0
}

# proc_optimizations applies configured process and kernel optimizations under a serialized lock.
proc_optimizations() {
	proc_lock_run proc_optimizations_locked
}

# proc_swap_active reports whether the system has an active swap device.
proc_swap_active() {
	local device remainder
	[ -r "${PROC_SWAPS_FILE}" ] || return 1
	while read -r device remainder; do
		case "${device}" in "" | Filename) continue ;; esac
		return 0
	done <"${PROC_SWAPS_FILE}"
	return 1
}

# proc_target maps a process setting identifier to its corresponding procfs path and fails for unsupported identifiers.
proc_target() {
	case "$1" in
		rmem_max) PROC_TARGET="${PROC_SYS_ROOT}/net/core/rmem_max" ;;
		wmem_max) PROC_TARGET="${PROC_SYS_ROOT}/net/core/wmem_max" ;;
		conntrack_tcp_timeout_max_retrans) PROC_TARGET="${PROC_SYS_ROOT}/net/netfilter/nf_conntrack_tcp_timeout_max_retrans" ;;
		pid_max) PROC_TARGET="${PROC_SYS_ROOT}/kernel/pid_max" ;;
		vm_overcommit_memory) PROC_TARGET="${PROC_SYS_ROOT}/vm/overcommit_memory" ;;
		vm_swappiness) PROC_TARGET="${PROC_SYS_ROOT}/vm/swappiness" ;;
		vm_overcommit_ratio) PROC_TARGET="${PROC_SYS_ROOT}/vm/overcommit_ratio" ;;
		ipv4_icmp_ratelimit) PROC_TARGET="${PROC_SYS_ROOT}/net/ipv4/icmp_ratelimit" ;;
		ipv4_neigh_gc_thresh1) PROC_TARGET="${PROC_SYS_ROOT}/net/ipv4/neigh/default/gc_thresh1" ;;
		ipv4_neigh_gc_thresh2) PROC_TARGET="${PROC_SYS_ROOT}/net/ipv4/neigh/default/gc_thresh2" ;;
		ipv4_neigh_gc_thresh3) PROC_TARGET="${PROC_SYS_ROOT}/net/ipv4/neigh/default/gc_thresh3" ;;
		ipv6_icmp_ratelimit) PROC_TARGET="${PROC_SYS_ROOT}/net/ipv6/icmp/ratelimit" ;;
		ipv6_neigh_gc_thresh1) PROC_TARGET="${PROC_SYS_ROOT}/net/ipv6/neigh/default/gc_thresh1" ;;
		ipv6_neigh_gc_thresh2) PROC_TARGET="${PROC_SYS_ROOT}/net/ipv6/neigh/default/gc_thresh2" ;;
		ipv6_neigh_gc_thresh3) PROC_TARGET="${PROC_SYS_ROOT}/net/ipv6/neigh/default/gc_thresh3" ;;
		*) return 1 ;;
	esac
}

# proc_boot_id reads and prints the validated system boot identifier, returning failure when it is unavailable or invalid.
proc_boot_id() {
	local boot_id
	[ -r "${PROC_BOOT_ID_FILE}" ] || return 1
	IFS= read -r boot_id <"${PROC_BOOT_ID_FILE}" || return 1
	case "${boot_id}" in "" | *[!A-Za-z0-9-]*) return 1 ;; esac
	printf '%s\n' "${boot_id}"
}

# proc_process_start_time prints the process start time in clock ticks for a given PID.
proc_process_start_time() {
	local fields stat
	[ -r "/proc/$1/stat" ] || return 1
	IFS= read -r stat <"/proc/$1/stat" || return 1
	fields="${stat##*) }"
	# Intentional word splitting: /proc/<pid>/stat is a space-delimited record.
	set -- ${fields}
	shift 19
	case "${1:-}" in "" | *[!0-9]*) return 1 ;; esac
	printf '%s\n' "$1"
}

# proc_lock_claim_matches verifies that the publication claim still belongs to the specified process identity.
proc_lock_claim_matches() {
	local claim_owner
	[ -L "${PROC_LOCK_DIR}.claim" ] || return 1
	claim_owner="$(readlink "${PROC_LOCK_DIR}.claim" 2>/dev/null)" || return 1
	[ "${claim_owner}" = "$1 $2" ]
}

# proc_lock_claim_acquire serializes fallback-lock publication and stale-lock reaping.
proc_lock_claim_acquire() {
	local attempts claim_owner claim_pid claim_start current_start reaper self_start try_only
	self_start="$1"
	try_only="${2:-0}"
	reaper="${PROC_LOCK_DIR}.claim.reap.${PROC_LOCK_PID:-$$}"
	rm -f "${reaper}"
	attempts=0
	while ! ln -s "${PROC_LOCK_PID:-$$} ${self_start}" "${PROC_LOCK_DIR}.claim" 2>/dev/null; do
		if [ "${try_only}" = 1 ]; then adguardhome_run_link_is_private "${PROC_LOCK_DIR}.claim" || return 1; fi
		claim_owner="$(readlink "${PROC_LOCK_DIR}.claim" 2>/dev/null)" || claim_owner=""
		claim_pid="${claim_owner%% *}"
		claim_start="${claim_owner#* }"
		case "${claim_pid}:${claim_start}" in
			*[!0-9:]* | :* | *:)
				[ "${try_only}" != 1 ] || return 1
				current_start=""
				;;
			*) current_start="$(proc_process_start_time "${claim_pid}" 2>/dev/null)" ;;
		esac
		if [ "${try_only}" = 1 ] && { [ "${current_start}" = "${claim_start}" ] || { [ -z "${current_start}" ] && kill -0 "${claim_pid}" 2>/dev/null; }; }; then return 1; fi
		if [ -z "${current_start}" ] || [ "${current_start}" != "${claim_start}" ]; then
			if mv "${PROC_LOCK_DIR}.claim" "${reaper}" 2>/dev/null; then
				claim_owner="$(readlink "${reaper}" 2>/dev/null)" || claim_owner=""
				claim_pid="${claim_owner%% *}"
				claim_start="${claim_owner#* }"
				current_start="$(proc_process_start_time "${claim_pid}" 2>/dev/null)"
				if [ -n "${current_start}" ] && [ "${current_start}" = "${claim_start}" ]; then
					mv "${reaper}" "${PROC_LOCK_DIR}.claim" 2>/dev/null || return 1
				else
					rm -f "${reaper}"
				fi
			fi
		fi
		if [ "${try_only}" = 1 ]; then
			ln -s "${PROC_LOCK_PID:-$$} ${self_start}" "${PROC_LOCK_DIR}.claim" 2>/dev/null || return 1
			break
		fi
		attempts="$((attempts + 1))"
		[ "${attempts}" -lt 100 ] || return 1
		if which usleep >/dev/null 2>&1; then usleep 100000; else sleep 1; fi
	done
	proc_lock_claim_matches "${PROC_LOCK_PID:-$$}" "${self_start}"
}

# proc_lock_claim_release removes the publication claim only while it still belongs to this process.
proc_lock_claim_release() {
	proc_lock_claim_matches "${PROC_LOCK_PID:-$$}" "$1" || return 1
	rm -f "${PROC_LOCK_DIR}.claim"
}

# proc_lock_mkdir_cleanup removes the procfs lock directory when it is owned by the current process.
proc_lock_mkdir_cleanup() {
	local current_start owner owner_start
	current_start="$(proc_process_start_time "${PROC_LOCK_PID:-$$}")" || return 1
	proc_lock_claim_matches "${PROC_LOCK_PID:-$$}" "${current_start}" || proc_lock_claim_acquire "${current_start}" || return 1
	if [ ! -d "${PROC_LOCK_DIR}" ] || [ -L "${PROC_LOCK_DIR}" ]; then
		proc_lock_claim_release "${current_start}" 2>/dev/null
		return 1
	fi
	if [ ! -f "${PROC_LOCK_DIR}/pid" ] || [ -L "${PROC_LOCK_DIR}/pid" ]; then
		rm -f "${PROC_LOCK_DIR}/pid" 2>/dev/null
		rmdir "${PROC_LOCK_DIR}" 2>/dev/null
		proc_lock_claim_release "${current_start}" 2>/dev/null
		return 1
	fi
	IFS=' ' read -r owner owner_start 2>/dev/null <"${PROC_LOCK_DIR}/pid" || {
		rm -f "${PROC_LOCK_DIR}/pid" 2>/dev/null
		rmdir "${PROC_LOCK_DIR}" 2>/dev/null
		proc_lock_claim_release "${current_start}" 2>/dev/null
		return 1
	}
	if [ "${owner}" != "${PROC_LOCK_PID:-$$}" ] || [ "${owner_start}" != "${current_start}" ]; then
		proc_lock_claim_release "${current_start}" 2>/dev/null
		return 1
	fi
	rm -f "${PROC_LOCK_DIR}/pid" || {
		proc_lock_claim_release "${current_start}" 2>/dev/null
		return 1
	}
	rmdir "${PROC_LOCK_DIR}" || {
		proc_lock_claim_release "${current_start}" 2>/dev/null
		return 1
	}
	proc_lock_claim_release "${current_start}"
}

# proc_lock_run serializes procfs changes without allowing an orphaned flock
# holder to block service shutdown indefinitely.  Descriptor locking uses the
# same bounded retry budget as the process-validated mkdir fallback.
proc_lock_run() {
	local attempts current_start has_usleep owner owner_start PROC_LOCK_PID reaper self_start self_stat status
	if [ "${PROC_LOCK_FORCE_MKDIR:-0}" != 1 ] && have_cmd flock && flock_supports_fd; then
		(
			mkdir -p "${WORK_DIR}" 2>/dev/null || exit 1
			exec 6>"${PROC_LOCK_FILE}" || exit 1
			attempts=0
			if which usleep >/dev/null 2>&1; then
				has_usleep=1
			else
				has_usleep=0
			fi
			while ! flock -n 6; do
				attempts="$((attempts + 1))"
				if [ "${has_usleep}" -eq 1 ]; then
					if [ "${attempts}" -ge 50 ]; then
						agh_log warning proc_lock_run "state=proc_optimize action=acquire_lock reason=flock_timeout result=failed attempts=${attempts}"
						exit 1
					fi
					usleep 100000
				else
					if [ "${attempts}" -ge 5 ]; then
						agh_log warning proc_lock_run "state=proc_optimize action=acquire_lock reason=flock_timeout result=failed attempts=${attempts}"
						exit 1
					fi
					sleep 1
				fi
			done
			"$@"
			status="$?"
			flock -u 6 >/dev/null 2>&1 || [ "${status}" -ne 0 ] || status=1
			exec 6>&-
			exit "${status}"
		)
		return $?
	fi
	(
		IFS= read -r self_stat </proc/self/stat || exit 1
		PROC_LOCK_PID="${self_stat%% *}"
		case "${PROC_LOCK_PID}" in "" | *[!0-9]*) exit 1 ;; esac
		attempts=0
		if which usleep >/dev/null 2>&1; then has_usleep=1; else has_usleep=0; fi
		reaper="${PROC_LOCK_DIR}.reap.${PROC_LOCK_PID:-$$}"
		rm -rf "${reaper}"
		self_start="$(proc_process_start_time "${PROC_LOCK_PID:-$$}")" || exit 1
		while :; do
			proc_lock_claim_acquire "${self_start}" || exit 1
			if mkdir "${PROC_LOCK_DIR}" 2>/dev/null; then
				trap 'proc_lock_mkdir_cleanup; exit 1' HUP INT QUIT ABRT TERM TSTP
				proc_lock_claim_matches "${PROC_LOCK_PID:-$$}" "${self_start}" || {
					proc_lock_mkdir_cleanup
					exit 1
				}
				printf '%s %s\n' "${PROC_LOCK_PID:-$$}" "${self_start}" >"${PROC_LOCK_DIR}/pid" || {
					proc_lock_mkdir_cleanup
					exit 1
				}
				proc_lock_claim_matches "${PROC_LOCK_PID:-$$}" "${self_start}" || {
					proc_lock_mkdir_cleanup
					exit 1
				}
				proc_lock_claim_release "${self_start}" || {
					proc_lock_mkdir_cleanup
					exit 1
				}
				break
			fi
			[ -d "${PROC_LOCK_DIR}" ] && [ ! -L "${PROC_LOCK_DIR}" ] || exit 1
			owner=""
			owner_start=""
			IFS=' ' read -r owner owner_start 2>/dev/null <"${PROC_LOCK_DIR}/pid" || owner=""
			case "${owner}" in
				"" | *[!0-9]*)
					if mv "${PROC_LOCK_DIR}" "${reaper}" 2>/dev/null; then
						rm -rf "${reaper}"
						proc_lock_claim_release "${self_start}" || exit 1
						continue
					fi
					;;
				*)
					current_start="$(proc_process_start_time "${owner}" 2>/dev/null)"
					if [ -z "${owner_start}" ] || [ "${current_start}" != "${owner_start}" ]; then
						if mv "${PROC_LOCK_DIR}" "${reaper}" 2>/dev/null; then
							rm -rf "${reaper}"
							proc_lock_claim_release "${self_start}" || exit 1
							continue
						fi
					fi
					;;
			esac
			proc_lock_claim_release "${self_start}" || exit 1
			attempts="$((attempts + 1))"
			[ "${attempts}" -lt 100 ] || exit 1
			if [ "${has_usleep}" -eq 1 ]; then usleep 100000; else sleep 1; fi
		done
		"$@"
		status="$?"
		if ! proc_lock_mkdir_cleanup && [ "${status}" -eq 0 ]; then
			status=1
		fi
		trap - HUP INT QUIT ABRT TERM TSTP
		exit "${status}"
	)
}

# proc_restore_ipv6 restores managed IPv6 procfs settings to their recorded original values.
proc_restore_ipv6() {
	local id
	for id in ipv6_icmp_ratelimit ipv6_neigh_gc_thresh1 ipv6_neigh_gc_thresh2 ipv6_neigh_gc_thresh3; do
		proc_restore_one "${id}"
	done
}

# proc_write applies a validated procfs value and records state needed to restore the original setting safely.
proc_write() {
	local applied boot_id current_value id maximum minimum old_value state_boot_id state_file state_tmp target value
	id="$1"
	value="$2"
	minimum="$3"
	maximum="$4"
	proc_target "${id}" || return 1
	target="${PROC_TARGET}"
	state_file="${PROC_STATE_DIR}/${id}"
	case "${value}:${minimum}:${maximum}" in *[!0-9:]*) return 1 ;; esac
	[ "${value}" -ge "${minimum}" ] && [ "${value}" -le "${maximum}" ] || return 1
	if [ ! -e "${target}" ]; then
		agh_log warning proc_write "state=proc_optimize action=write target=${target} new_value=${value} reason=missing result=failed"
		return 1
	fi
	if ! IFS= read -r old_value <"${target}"; then
		agh_log warning proc_write "state=proc_optimize action=read target=${target} new_value=${value} reason=read_failed result=failed"
		return 1
	fi
	case "${old_value}" in "" | *[!0-9]*) return 1 ;; esac
	current_value="${old_value}"
	if ! boot_id="$(proc_boot_id 2>/dev/null)" || [ -z "${boot_id}" ]; then
		agh_log warning proc_write "state=proc_optimize action=write target=${target} new_value=${value} reason=boot_id_unavailable result=failed"
		return 1
	fi
	if [ -f "${state_file}" ]; then
		IFS=' ' read -r old_value applied state_boot_id <"${state_file}" || return 1
		case "${old_value}:${applied}" in
			*[!0-9:]* | *::* | :* | *:)
				rm -f "${state_file}" || return 1
				proc_write "${id}" "${value}" "${minimum}" "${maximum}"
				return $?
				;;
		esac
		case "${state_boot_id}" in
			"" | *[!A-Za-z0-9-]*)
				rm -f "${state_file}" || return 1
				proc_write "${id}" "${value}" "${minimum}" "${maximum}"
				return $?
				;;
		esac
		[ "${applied}" = "${value}" ] || return 1
		if [ "${state_boot_id}" != "${boot_id}" ]; then
			rm -f "${state_file}" || return 1
			# procfs reset after reboot; claim nothing if the boot default already
			# matches, otherwise preserve this boot's value before reapplying.
			[ "${current_value}" = "${value}" ] && return 0
			proc_write "${id}" "${value}" "${minimum}" "${maximum}"
			return $?
		fi
		[ "${current_value}" = "${value}" ] && return 0
		if [ "${current_value}" = "${old_value}" ]; then
			if ! printf '%s\n' "${value}" >"${target}" 2>/dev/null; then
				agh_log warning proc_write "state=proc_optimize action=write target=${target} old_value=${old_value} new_value=${value} result=failed"
				return 1
			fi
			agh_log info proc_write "state=proc_optimize action=write target=${target} old_value=${old_value} new_value=${value} result=changed"
			return 0
		fi
		# An administrator changed the setting after application; relinquish it.
		rm -f "${state_file}"
		return 0
	fi
	[ "${old_value}" = "${value}" ] && return 0
	mkdir -p "${PROC_STATE_DIR}" 2>/dev/null || return 1
	# Publish the rollback record before changing procfs so interruption is safe.
	state_tmp="${state_file}.tmp.$$"
	if ! printf '%s %s %s\n' "${old_value}" "${value}" "${boot_id}" >"${state_tmp}" ||
		! mv -f "${state_tmp}" "${state_file}"; then
		rm -f "${state_tmp}"
		return 1
	fi
	if ! printf '%s\n' "${value}" >"${target}" 2>/dev/null; then
		agh_log warning proc_write "state=proc_optimize action=write target=${target} old_value=${old_value} new_value=${value} result=failed"
		rm -f "${state_file}"
		return 1
	fi
	agh_log info proc_write "state=proc_optimize action=write target=${target} old_value=${old_value} new_value=${value} result=changed"
	return 0
}

# proc_restore_one restores one managed procfs setting when its current value still matches the value previously applied by the script.
proc_restore_one() {
	local applied boot_id current_value id old_value state_boot_id state_file target
	id="$1"
	proc_target "${id}" || return 1
	state_file="${PROC_STATE_DIR}/${id}"
	[ -f "${state_file}" ] || return 0
	IFS=' ' read -r old_value applied state_boot_id <"${state_file}" || return 1
	case "${state_boot_id}" in
		"" | *[!A-Za-z0-9-]*)
			rm -f "${state_file}"
			return $?
			;;
	esac
	if ! boot_id="$(proc_boot_id 2>/dev/null)" || [ -z "${boot_id}" ]; then
		agh_log warning proc_restore "state=proc_optimize action=restore target=${PROC_TARGET} reason=boot_id_unavailable result=failed"
		return 1
	fi
	if [ "${state_boot_id}" != "${boot_id}" ]; then
		rm -f "${state_file}"
		return 0
	fi
	target="${PROC_TARGET}"
	if ! { IFS= read -r current_value <"${target}"; } 2>/dev/null; then
		agh_log warning proc_restore "state=proc_optimize action=read target=${target} reason=read_failed result=failed"
		return 1
	fi
	if [ "${current_value}" = "${applied}" ]; then
		if printf '%s\n' "${old_value}" >"${target}" 2>/dev/null; then
			agh_log info proc_restore "state=proc_optimize action=restore target=${target} old_value=${applied} new_value=${old_value} result=changed"
			rm -f "${state_file}"
		else
			agh_log warning proc_restore "state=proc_optimize action=restore target=${target} old_value=${applied} new_value=${old_value} result=failed"
			return 1
		fi
	else
		# Preserve an administrator's later value and discard our ownership record.
		rm -f "${state_file}"
	fi
}

# proc_restore_locked restores managed procfs settings while holding the process-settings lock and reports whether all restorations succeeded.
proc_restore_locked() {
	local failed id
	failed=0
	for id in rmem_max wmem_max pid_max conntrack_tcp_timeout_max_retrans vm_overcommit_memory vm_swappiness vm_overcommit_ratio ipv4_icmp_ratelimit ipv4_neigh_gc_thresh1 ipv4_neigh_gc_thresh2 ipv4_neigh_gc_thresh3 ipv6_icmp_ratelimit ipv6_neigh_gc_thresh1 ipv6_neigh_gc_thresh2 ipv6_neigh_gc_thresh3; do
		proc_restore_one "${id}" || failed=1
	done
	rmdir "${PROC_STATE_DIR}" 2>/dev/null || true
	[ "${failed}" -eq 0 ]
}

# proc_restore restores managed procfs settings to their original values.
proc_restore() {
	proc_lock_run proc_restore_locked
}
# netcheck_lan_dns checks whether the local AdGuardHome listener resolves localhost successfully in LAN mode.
netcheck_lan_dns() {
	# Ignore public DNS overrides in LAN mode; this probe is only for the
	# local AdGuardHome listener after the process has started.
	if ! netcheck_dns_ok "127.0.0.1" localhost; then
		agh_log warning netcheck_lan_dns "state=netcheck action=resolve_hosts stage=dns reason=lookup_failed result=failed mode=lan dns=127.0.0.1 hosts=localhost"
		return 1
	fi
	return 0
}

# lower_script delegates a service command to the lower-level service script.

lower_script() {
	case "$1" in
		stop | restart | kill)
			# Restore native resolution before the daemon receives any stop signal.
			if ! dnsmasq_resolv_conf_cleanup; then
				# A manager operation prevents new activation. Native routing can
				# proceed despite contention; unguarded direct callers must wait.
				if ! resolv_conf_uses_rom; then
					if resolv_conf_is_tmp_mount || ! adguard_local_cache_service_active; then return 1; fi
				fi
			fi
			;;
	esac
	case "$1" in
		*)
			${LOWER_SCRIPT_LOC} "$1" "${NAME}"
			;;
	esac
}

# service_wait waits for service readiness, using firmware readiness before a
# LAN/AP/Bridge daemon launch and local DNS afterward; WAN keeps its netcheck.
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

# start_adguardhome prepares AdGuardHome for startup, launches or restarts it, and verifies network readiness.
# start_adguardhome prepares DNS integration, starts or restarts AdGuardHome, and verifies network readiness, returning failure when required preparation, startup, or validation fails.
start_adguardhome() {
	local IPSET_START_FAILURE_SAFE IPSET_START_RESTARTED IPSET_START_STOPPED LAN_BIND_REFRESH_FAILED LOWER_SCRIPT_STATUS db
	IPSET_START_FAILURE_SAFE="0"
	IPSET_START_RESTARTED="0"
	IPSET_START_STOPPED="0"
	LAN_BIND_REFRESH_FAILED="0"
	SERVICE_WAIT_TERMINAL_FAILURE="0"
	if adguard_lan_mode; then
		if ! adguard_refresh_lan_bind_addresses; then
			LAN_BIND_REFRESH_FAILED="1"
			agh_log warning start_adguardhome "state=starting action=refresh_lan_bind_addresses result=failed reason=config_refresh_failed config_preserved=1 service_health=pending"
			if [ "${LAN_BIND_REFRESH_FAILURE_REASON:-}" = "active_yaml_not_regular" ]; then
				SERVICE_WAIT_TERMINAL_FAILURE="1"
				return 1
			fi
		fi
	fi
	if ! adguard_ipset_allowed; then
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
				if [ "${LAN_BIND_REFRESH_FAILED}" -eq 1 ] && [ "${1:-}" != "restart" ]; then
					LOWER_SCRIPT_STATUS="0"
				else
					lower_script restart
					LOWER_SCRIPT_STATUS="$?"
				fi
				;;
		esac
		if [ "${LOWER_SCRIPT_STATUS}" -ne 0 ]; then
			SERVICE_WAIT_TERMINAL_FAILURE="1"
			return "${LOWER_SCRIPT_STATUS}"
		fi
	fi
	for db in stats.db sessions.db; do
		ensure_database_link "/tmp/${db}" "${WORK_DIR}/data/${db}"
	done
	if { service_wait netcheck; }; then
		return "0"
	else
		return "1"
	fi
}

# restart_adguardhome preserves an explicit restart request through the service lock.
restart_adguardhome() {
	start_adguardhome restart
}

# start_monitor runs the AdGuardHome supervision loop with no arguments.
# Uses ADGUARDHOME_BINARY and PROCS to detect the executable and daemon, and
# performs the configured LAN/WAN readiness wait before the first launch.
# Retries a missing executable or daemon and performs periodic DNS health checks.
# USR1 requests daemon shutdown and loop exit; USR2 requests a restart through
# the service lock and DNS handoff. Other trapped termination signals are ignored
# until shutdown restores their default handlers. Runs until a stop request and
# returns the stop operation's status after leaving the loop.
start_monitor() {
	local BINARY_UNAVAILABLE_LOGGED MONITOR_BINARY_RETRY_INTERVAL MONITOR_ELAPSED MONITOR_HEALTHCHECK_INTERVAL MONITOR_HEALTHCHECK_TIMEOUT MONITOR_RECOVERY_RETRY_INTERVAL MONITOR_SLEEP_INTERVAL MONITOR_START_ACTION MONITOR_STATE MONITOR_STOP_STATUS
	MONITOR_BINARY_RETRY_INTERVAL="10"
	MONITOR_HEALTHCHECK_INTERVAL="300"
	MONITOR_HEALTHCHECK_TIMEOUT="150"
	MONITOR_RECOVERY_RETRY_INTERVAL="10"
	MONITOR_SLEEP_INTERVAL="10"
	MONITOR_STATE="running"
	MONITOR_STOP_STATUS="0"
	trap '' HUP INT QUIT ABRT TERM TSTP
	trap 'MONITOR_STATE="stop"' USR1
	trap 'MONITOR_STATE="restart"' USR2
	# Use the configured LAN/WAN netcheck while waiting for the firmware service
	# framework. LAN mode skips public WAN probes before the first launch.
	{ service_wait netcheck; }
	agh_log info start_monitor "state=${MONITOR_STATE} action=start_monitor reason=init result=started"
	agh_log info start_monitor "state=${MONITOR_STATE} action=configure_healthcheck reason=init result=enabled interval=${MONITOR_HEALTHCHECK_INTERVAL}"
	while true; do
		# Postconf restores native routing. Retry cache only after replacements answer.
		case "${MONITOR_STATE}" in
			"running") adguard_local_cache_sync || true ;;
		esac
		case "${MONITOR_STATE}" in
			"running" | "stop")
				check_dns_environment "${MONITOR_STATE}"
				;;
			"restart")
				check_dns_environment "running"
				;;
		esac
		if [ "${MONITOR_STATE}" = "stop" ]; then
			if ! load_operation_config stop; then
				set_operation_config_defaults
				CONFIG_DNSMASQ_MODE="enabled"
				agh_log warning start_monitor "state=stop action=load_config reason=invalid_snapshot result=using_defaults"
			fi
		fi
		if [ "${MONITOR_STATE}" = "stop" ]; then # A place to exit early if needed, or if binary becomes unavailable before service-stop.
			agh_log info start_monitor "state=stop action=stop_monitor reason=signal_USR1 result=stopping"
			trap - HUP INT QUIT ABRT USR1 USR2 TERM TSTP
			{ adguardhome_run stop_adguardhome; }
			MONITOR_STOP_STATUS="$?"
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
						{ adguardhome_run "${MONITOR_START_ACTION:-start_adguardhome}"; }
						unset MONITOR_START_ACTION
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
							# An atomic .config replacement becomes visible as one snapshot here;
							# failed validation retains the preceding healthcheck snapshot.
							if ! load_operation_config monitor-healthcheck; then
								agh_log warning start_monitor "state=running action=load_config reason=invalid_snapshot result=retained"
							fi
							# Periodic verification recovers native DNS on a readiness failure.
							adguard_local_cache_sync verify || true
							if adguard_lan_mode; then
								if ! adguard_refresh_lan_bind_addresses; then
									agh_log warning start_monitor "state=running action=refresh_lan_bind_addresses reason=periodic_sync result=failed"
								elif [ "${LAN_BIND_ADDRESSES_CHANGED:-0}" -eq 1 ]; then
									agh_log info start_monitor "state=running action=refresh_lan_bind_addresses reason=address_changed result=restarting"
									unset MONITOR_ELAPSED
									{ adguardhome_run start_adguardhome; }
									continue
								fi
							fi
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
				if ! load_operation_config stop; then
					set_operation_config_defaults
					CONFIG_DNSMASQ_MODE="enabled"
					agh_log warning start_monitor "state=stop action=load_config reason=invalid_snapshot result=using_defaults"
				fi
				trap - HUP INT QUIT ABRT USR1 USR2 TERM TSTP
				{ adguardhome_run stop_adguardhome; }
				MONITOR_STOP_STATUS="$?"
				break
				;;
			"restart")
				agh_log info start_monitor "state=restart action=restart_adguardhome reason=signal_USR2 result=restarting"
				if ! load_operation_config action; then
					agh_log warning start_monitor "state=restart action=load_config reason=invalid_snapshot result=retained"
				fi
				unset MONITOR_ELAPSED
				MONITOR_START_ACTION="restart_adguardhome"
				MONITOR_STATE="running"
				;;
		esac
	done
	return "${MONITOR_STOP_STATUS}"
}

# post_stop_process_ready verifies that AdGuardHome has no running process.
post_stop_process_ready() {
	[ "$(pidof "${PROCS}" 2>/dev/null | wc -w)" -eq 0 ]
}

# post_stop_handoff_cleared verifies that no installer-owned DNS handoff marker remains.
post_stop_handoff_cleared() {
	local marker
	for marker in /tmp/AdGuardHome.dnsmasq.handoff /tmp/AdGuardHome.dnsmasq.lock "${DNS_HANDOFF_FILE}" "${DNS_HANDOFF_DIR}/lock"; do
		[ ! -e "${marker}" ] && [ ! -L "${marker}" ] || return 1
	done
	return 0
}

# post_stop_native_resolver_ready verifies that optional cache routing is gone.
post_stop_native_resolver_ready() {
	resolv_conf_uses_rom || ! resolv_conf_is_tmp_mount
}

# Preserve managed main/SDN requirements before signalling a monitor.  Explicit
# enabled integration remains required even if dnsmasq later disappears in LAN.
post_stop_capture_dnsmasq_requirements() {
	local ADGUARDHOME_DNS_HANDOFF_REQUIRED ADGUARDHOME_DNSMASQ_CONFIGS="${ADGUARDHOME_DNSMASQ_CONFIGS:-}" config configs index
	case "${STOP_DNSMASQ_REQUIRED:-}" in 0 | 1) return 0 ;; esac
	STOP_DNSMASQ_REQUIRED="0"
	STOP_DNSMASQ_CONFIGS=""
	case "${CONFIG_DNSMASQ_MODE:-auto}" in
		disabled) return 0 ;;
		enabled) STOP_DNSMASQ_REQUIRED="1" ;;
		*) adguard_dnsmasq_managed && STOP_DNSMASQ_REQUIRED="1" ;;
	esac
	[ "${STOP_DNSMASQ_REQUIRED}" -eq 1 ] || return 0
	STOP_DNSMASQ_CONFIGS="/etc/dnsmasq.conf"
	ADGUARDHOME_DNS_HANDOFF_REQUIRED="1"
	if type dnsmasq_handoff_configs >/dev/null 2>&1; then
		configs="$(dnsmasq_handoff_configs)" || return 1
		STOP_DNSMASQ_CONFIGS="${STOP_DNSMASQ_CONFIGS} ${configs}"
	else
		# The manager can remain available after the Entware service file vanishes.
		case " $(nvram get rc_support 2>/dev/null) " in
			*" mtlancfg "*)
				for config in /etc/dnsmasq-[0-9]*.conf; do
					[ -f "${config}" ] || continue
					index="${config#/etc/dnsmasq-}"
					index="${index%.conf}"
					case "${index}" in "" | *[!0-9]*) continue ;; esac
					[ -n "$(sdn_bridge_for_index "${index}")" ] || continue
					STOP_DNSMASQ_CONFIGS="${STOP_DNSMASQ_CONFIGS} ${config}"
				done
				;;
		esac
	fi
	return 0
}

# post_stop_complete verifies the postconditions independently of monitor exit.
post_stop_complete() {
	post_stop_process_ready && post_stop_handoff_cleared && post_stop_native_resolver_ready || return 1
	[ "${STOP_DNSMASQ_REQUIRED:-0}" -eq 0 ] || post_stop_dnsmasq_ready
}

# monotonic_seconds returns integer seconds from the kernel monotonic uptime clock.
monotonic_seconds() {
	local UPTIME_REST UPTIME_SECONDS UPTIME_VALUE
	[ -r /proc/uptime ] || return 1
	IFS=' ' read -r UPTIME_VALUE UPTIME_REST </proc/uptime || return 1
	UPTIME_SECONDS="${UPTIME_VALUE%%.*}"
	case "${UPTIME_SECONDS}" in
		"" | *[!0-9]*) return 1 ;;
	esac
	printf '%s\n' "${UPTIME_SECONDS}"
}

# post_stop_dnsmasq_timeout returns the bounded local-DNS recovery budget in seconds.
post_stop_dnsmasq_timeout() {
	local CONFIGURED RESTART_SECONDS TIMEOUT
	CONFIGURED="${ADGUARDHOME_DNSMASQ_READY_TIMEOUT:-}"
	case "${CONFIGURED}" in
		"" | *[!0-9]*) ;;
		*)
			if [ "${CONFIGURED}" -ge 5 ] && [ "${CONFIGURED}" -le 120 ]; then
				printf '%s\n' "${CONFIGURED}"
				return 0
			fi
			;;
	esac
	RESTART_SECONDS="${1:-0}"
	case "${RESTART_SECONDS}" in
		"" | *[!0-9]*) RESTART_SECONDS="0" ;;
	esac
	TIMEOUT="$((RESTART_SECONDS * 3 + 10))"
	[ "${TIMEOUT}" -ge 15 ] || TIMEOUT="15"
	[ "${TIMEOUT}" -le 60 ] || TIMEOUT="60"
	printf '%s\n' "${TIMEOUT}"
}

# Verify every captured configuration, including main-only recovery.  The
# manager's procfs fallback remains available when /opt's service file is gone.
post_stop_dnsmasq_instances_ready() {
	local ADGUARDHOME_DNSMASQ_CONFIGS args config executable inventory native_pids pid start table
	ADGUARDHOME_DNSMASQ_CONFIGS="${STOP_DNSMASQ_CONFIGS:-}"
	[ -n "${ADGUARDHOME_DNSMASQ_CONFIGS}" ] || return 1
	if type dnsmasq_instances_ready >/dev/null 2>&1; then
		dnsmasq_instances_ready 53 && return 0
	fi
	native_pids="$(pidof dnsmasq 2>/dev/null)"
	if type dnsmasq_managed_instances >/dev/null 2>&1; then
		inventory="$(dnsmasq_managed_instances | awk '{ print $1, $3 }')" || return 1
	else
		inventory="$(
			for pid in ${native_pids}; do
				case "${pid}" in "" | *[!0-9]*) continue ;; esac
				[ "${pid}" -gt 1 ] || continue
				start="$(proc_process_start_time "${pid}")" || continue
				executable="$(readlink "/proc/${pid}/exe" 2>/dev/null)" || continue
				case "${executable}" in /usr/sbin/dnsmasq | /sbin/dnsmasq) ;; *) continue ;; esac
				[ "$(cat "/proc/${pid}/comm" 2>/dev/null)" = dnsmasq ] || continue
				args="$(tr '\000' '\n' <"/proc/${pid}/cmdline" 2>/dev/null)" || continue
				config="$(printf '%s\n' "${args}" | awk '
					NR == 1 { next }
					need_config { config=$0; need_config=0; count++; next }
					$0 == "-C" || $0 == "--conf-file" { need_config=1; next }
					/^--conf-file=/ { config=substr($0, 13); count++; next }
					/^-C./ { config=substr($0, 3); count++; next }
					$0 == "-7" || /^-7./ || /^--conf-dir/ { invalid=1 }
					END {
						if (need_config || count > 1 || invalid) exit 1
						if (count == 0) print "/etc/dnsmasq.conf"
						else print config
					}')" || continue
				case " ${ADGUARDHOME_DNSMASQ_CONFIGS} " in *" ${config} "*) ;; *) continue ;; esac
				[ -f "${config}" ] && [ ! -L "${config}" ] || continue
				[ "$(proc_process_start_time "${pid}")" = "${start}" ] || continue
				printf '%s %s\n' "${pid}" "${config}"
			done
		)" || return 1
	fi
	table="$(netstat -nlp 2>/dev/null)" || return 1
	printf '%s\n' "${table}" | awk -v configs="${ADGUARDHOME_DNSMASQ_CONFIGS}" -v inventory="${inventory}" -v native_pids="${native_pids}" '
		BEGIN {
			count=split(configs, values, /[[:space:]]+/)
			for (i=1; i<=count; i++) if (values[i] != "") required[values[i]]=1
			count=split(inventory, rows, "\n")
			for (i=1; i<=count; i++) {
				split(rows[i], fields, " ")
				if (fields[2] in required) candidates[fields[1]]=fields[2]
			}
			for (config in required) expected++
			for (pid in candidates) { known++; only_pid=pid }
			# Ownerless main rows are safe only with one identified dnsmasq.
			pid_count=split(native_pids, pids, /[[:space:]]+/)
			ownerless=(expected == 1 && ("/etc/dnsmasq.conf" in required) && known == 1 && pid_count == 1 && pids[1] == only_pid)
		}
		$1 ~ /^(tcp|udp)6?$/ && $4 ~ /:53$/ {
			owner=""
			for (i=1; i<=NF; i++) if ($i ~ /^[0-9]+\//) { owner=$i; break }
			if (owner == "" && ownerless) pid=only_pid
			else {
				split(owner, fields, "/")
				pid=fields[1]
				if (fields[2] != "dnsmasq" || !(pid in candidates)) next
			}
			if ($1 ~ /^tcp/) tcp[pid]=1
			if ($1 ~ /^udp/) udp[pid]=1
		}
		END {
			for (pid in candidates) if (tcp[pid] && udp[pid]) ready[candidates[pid]]=1
			for (config in required) if (!(config in ready)) exit 1
		}
	'
}

# post_stop_dnsmasq_ready verifies that required dnsmasq instances own local port
# 53 and resolve localhost through an available DNS server.
post_stop_dnsmasq_ready() {
	local dns_server dns_servers lan_addr
	adguard_dnsmasq_running || return 1
	post_stop_dnsmasq_instances_ready || return 1
	dns_servers="$(netstat -nlp 2>/dev/null | awk '$0 ~ /:53[[:space:]]/ {
		owner = ""
		for (i = NF; i >= 1; i--) if ($i ~ /^[0-9]+\/[^[:space:]]+$/) { owner = $i; break }
		if (owner != "" && owner !~ /\/dnsmasq$/) bad_owner = 1
		if ($1 ~ /^tcp6?$/) tcp = 1
		if ($1 ~ /^udp6?$/) {
			udp = 1
			server = $4
			sub(/:53$/, "", server)
			gsub(/^\[|\]$/, "", server)
			if (!seen[server]++) {
				servers[server] = 1
			}
		}
	}
		END {
			if (bad_owner || !tcp || !udp) exit 1
			for (server in servers) print server
		}
	')" || return 1
	[ -n "${dns_servers}" ] || return 1
	lan_addr="$(nvram get lan_ipaddr 2>/dev/null)"
	for dns_server in ${dns_servers}; do
		case "${dns_server}" in
			0.0.0.0) dns_server="${lan_addr:-127.0.0.1}" ;;
			:: | \*) dns_server="::1" ;;
		esac
		if nslookup localhost "${dns_server}" >/dev/null 2>&1; then
			return 0
		fi
	done
	return 1
}

# stop_adguardhome stops AdGuardHome, restores managed dnsmasq, verifies shutdown and local DNS recovery, and removes expected database links.
stop_adguardhome() {
	local DNSMASQ_READY_ATTEMPTS DNSMASQ_READY_TIMEOUT DNSMASQ_RESTART_ELAPSED DNSMASQ_RESTART_END DNSMASQ_RESTART_START DNSMASQ_WAS_MANAGED STOP_DNSMASQ_CONFIGS="${STOP_DNSMASQ_CONFIGS:-}" STOP_DNSMASQ_REQUIRED="${STOP_DNSMASQ_REQUIRED:-}" STOP_STATUS db
	STOP_STATUS="0"
	post_stop_capture_dnsmasq_requirements || STOP_STATUS="1"
	if ! dnsmasq_resolv_conf_cleanup; then
		if ! resolv_conf_uses_rom; then
			if resolv_conf_is_tmp_mount || ! adguard_local_cache_service_active; then STOP_STATUS="1"; fi
		fi
	fi
	DNSMASQ_WAS_MANAGED="${STOP_DNSMASQ_REQUIRED}"
	DNSMASQ_RESTART_ELAPSED="0"
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
	if ! post_stop_process_ready; then
		agh_log error stop_adguardhome "state=stopping action=stop_process reason=process_still_active result=active process=${PROCS}"
		STOP_STATUS="1"
	fi
	if [ "${ADGUARDHOME_SKIP_DNSMASQ_RESTART:-}" != "1" ] && [ "${DNSMASQ_WAS_MANAGED}" -eq 1 ]; then
		DNSMASQ_RESTART_START="$(monotonic_seconds 2>/dev/null)" || DNSMASQ_RESTART_START=""
		if ! service restart_dnsmasq >/dev/null 2>&1; then
			agh_log error stop_adguardhome "state=stopping action=restart_dnsmasq reason=service_restart_failed result=failed process=${PROCS}"
			STOP_STATUS="1"
		fi
		DNSMASQ_RESTART_END="$(monotonic_seconds 2>/dev/null)" || DNSMASQ_RESTART_END=""
		case "${DNSMASQ_RESTART_START}:${DNSMASQ_RESTART_END}" in
			*[!0-9:]* | :* | *:)
				DNSMASQ_RESTART_ELAPSED="0"
				;;
			*)
				if [ "${DNSMASQ_RESTART_END}" -ge "${DNSMASQ_RESTART_START}" ]; then
					DNSMASQ_RESTART_ELAPSED="$((DNSMASQ_RESTART_END - DNSMASQ_RESTART_START))"
				fi
				;;
		esac
	fi
	if [ "${DNSMASQ_WAS_MANAGED}" -eq 1 ]; then
		DNSMASQ_READY_TIMEOUT="$(post_stop_dnsmasq_timeout "${DNSMASQ_RESTART_ELAPSED}")"
		DNSMASQ_READY_ATTEMPTS="0"
		until post_stop_dnsmasq_ready; do
			DNSMASQ_READY_ATTEMPTS="$((DNSMASQ_READY_ATTEMPTS + 1))"
			if [ "${DNSMASQ_READY_ATTEMPTS}" -ge "${DNSMASQ_READY_TIMEOUT}" ]; then
				agh_log error stop_adguardhome "state=stopping action=verify_local_dns reason=dnsmasq_not_ready result=failed attempts=${DNSMASQ_READY_ATTEMPTS} restart_elapsed=${DNSMASQ_RESTART_ELAPSED} timeout=${DNSMASQ_READY_TIMEOUT}"
				STOP_STATUS="1"
				break
			fi
			sleep 1
		done
		if [ "${DNSMASQ_READY_ATTEMPTS}" -lt "${DNSMASQ_READY_TIMEOUT}" ]; then
			agh_log info stop_adguardhome "state=stopping action=verify_local_dns result=ready attempts=${DNSMASQ_READY_ATTEMPTS} restart_elapsed=${DNSMASQ_RESTART_ELAPSED} timeout=${DNSMASQ_READY_TIMEOUT}"
		fi
	fi
	if ! post_stop_handoff_cleared; then
		agh_log error stop_adguardhome "state=stopping action=verify_handoff reason=installer_marker_remains result=failed"
		STOP_STATUS="1"
	fi
	if ! post_stop_native_resolver_ready; then
		agh_log error stop_adguardhome "state=stopping action=verify_resolver reason=cache_mount_remains result=failed"
		STOP_STATUS="1"
	fi
	for db in stats.db sessions.db; do
		remove_database_link "/tmp/${db}" "${WORK_DIR}/data/${db}"
	done
	return "${STOP_STATUS}"
}

# monitor_process_matches verifies that a PID still belongs to this add-on's
# monitor before a stop escalation signal is sent.
monitor_process_matches() {
	local PID
	PID="$1"
	case "${PID}" in
		"" | *[!0-9]*) return 1 ;;
	esac
	[ -r "/proc/${PID}/cmdline" ] || return 1
	awk '{ print }' "/proc/${PID}/cmdline" 2>/dev/null | grep -q 'monitor-start'
}

# adguard_monitor_pids lists monitor processes regardless of which managed
# entry point launched them.  Older upgrades can leave a monitor named after
# the addon or lower service script instead of S99AdGuardHome.
adguard_monitor_pids() {
	pidof "S99${PROCS}" "AdGuardHome.sh" "rc.func.${PROCS}" 2>/dev/null
}

# Stop every matching monitor left by an earlier service entry point.  A
# single stop request must not leave another monitor able to respawn the daemon.
stop_all_monitors() {
	local FOUND MONITOR_STOP_FORCED PID STOP_DNSMASQ_CONFIGS STOP_DNSMASQ_REQUIRED STOP_RECOVERY_REQUIRED STOP_STATUS
	FOUND=0
	STOP_RECOVERY_REQUIRED=0
	STOP_STATUS=0
	STOP_DNSMASQ_CONFIGS=""
	STOP_DNSMASQ_REQUIRED=""
	post_stop_capture_dnsmasq_requirements || STOP_STATUS=1
	for PID in $(adguard_monitor_pids); do
		[ "${PID}" != "$$" ] || continue
		monitor_process_matches "${PID}" || continue
		FOUND=1
		MON_PID="${PID}"
		stop_monitor "$$" || STOP_STATUS=1
		[ "${MONITOR_STOP_FORCED:-0}" -eq 0 ] || STOP_RECOVERY_REQUIRED=1
	done
	post_stop_complete || STOP_RECOVERY_REQUIRED=1
	if [ "${FOUND}" -eq 0 ] || [ "${STOP_STATUS}" -ne 0 ] || [ "${STOP_RECOVERY_REQUIRED}" -ne 0 ]; then
		# A vanished monitor cannot communicate a failed stop to this parent.
		adguardhome_run stop_adguardhome || STOP_STATUS=1
	fi
	post_stop_complete || STOP_STATUS=1
	return "${STOP_STATUS}"
}

# stop_monitor requests the monitor's normal USR1 shutdown, waits for procfs
# restoration to finish, and uses identity-checked TERM/KILL escalation so a
# stuck monitor cannot keep installer updates in a permanent stopping state.
# MONITOR_STOP_FORCED tells the caller to complete daemon and DNS restoration.
stop_monitor() {
	local ATTEMPTS MONITOR_PID SIGNAL
	MONITOR_STOP_FORCED=0
	case "$1" in
		"${MON_PID}")
			SIGNAL="USR2"
			MONITOR_PID="${MON_PID}"
			;;
		"$$")
			if [ -n "${MON_PID}" ]; then SIGNAL="USR1"; else { adguardhome_run stop_adguardhome; }; fi
			;;
	esac
	[ -n "${SIGNAL}" ] || return 0
	MONITOR_PID="${MONITOR_PID:-${MON_PID}}"
	monitor_process_matches "${MONITOR_PID}" || return 0
	kill -s "${SIGNAL}" "${MONITOR_PID}" 2>/dev/null || return 1
	[ "${SIGNAL}" = "USR1" ] || return 0
	ATTEMPTS=0
	while monitor_process_matches "${MONITOR_PID}" && [ "${ATTEMPTS}" -lt 10 ]; do
		sleep 1
		ATTEMPTS="$((ATTEMPTS + 1))"
	done
	monitor_process_matches "${MONITOR_PID}" || return 0
	MONITOR_STOP_FORCED=1
	kill -TERM "${MONITOR_PID}" 2>/dev/null || return 1
	ATTEMPTS=0
	while monitor_process_matches "${MONITOR_PID}" && [ "${ATTEMPTS}" -lt 5 ]; do
		sleep 1
		ATTEMPTS="$((ATTEMPTS + 1))"
	done
	monitor_process_matches "${MONITOR_PID}" || return 0
	kill -KILL "${MONITOR_PID}" 2>/dev/null || return 1
	ATTEMPTS=0
	while monitor_process_matches "${MONITOR_PID}" && [ "${ATTEMPTS}" -lt 3 ]; do
		sleep 1
		ATTEMPTS="$((ATTEMPTS + 1))"
	done
	! monitor_process_matches "${MONITOR_PID}"
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

# IPSet_Dnsmasq_Restart_After_Unlock restarts managed dnsmasq after releasing the IPSet lock when a restart is pending.
IPSet_Dnsmasq_Restart_After_Unlock() {
	[ "${IPSET_DNSMASQ_RESTART_PENDING:-0}" -eq 1 ] || return 0
	IPSET_DNSMASQ_RESTART_PENDING="0"
	[ "${ADGUARDHOME_SKIP_DNSMASQ_RESTART:-}" != "1" ] || return 0
	service restart_dnsmasq >/dev/null 2>&1
}

# IPSet_Current_UID prints the current process's effective user ID.
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

# IPSet_Lock_Interrupt_Cleanup restores AdGuardHome after an interrupted IPSet operation when the service was stopped by that operation.
IPSet_Lock_Interrupt_Cleanup() {
	if [ "${IPSET_START_STOPPED:-0}" -eq 1 ]; then
		IPSet_Start_Restore || true
	fi
}

# IPSet_Lock_Interrupt_Propagate invokes an outer transaction's signal cleanup while the IPSET lock remains held.
IPSet_Lock_Interrupt_Propagate() {
	[ -n "${IPSET_LOCK_INTERRUPT_CALLBACK:-}" ] || return 0
	"${IPSET_LOCK_INTERRUPT_CALLBACK}"
}

# IPSet_Start_Restore restores AdGuardHome after an IPSet setup rollback and reports whether restoration succeeded.
IPSet_Start_Restore() {
	IPSET_START_STOPPED="0"
	if IPSet_Start_While_Locked; then
		agh_log info IPSet_Start_Restore "state=rollback action=restore_adguardhome reason=ipset_setup_rollback result=restored"
		return 0
	fi
	agh_log error IPSet_Start_Restore "state=rollback action=restore_adguardhome reason=ipset_setup_rollback result=failed"
	return 1
}

# IPSet_Start_While_Locked starts AdGuardHome while deferring any managed dnsmasq restart until the IPSet lock is released.
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
	if [ "${IPSET_LOCK_ACTIVE:-0}" = "1" ]; then
		"$@"
		return "$?"
	fi
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

# IPSet_Lock_Flock serializes an IPSet operation under a file lock and restores its signal handlers and cleanup state afterward.
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
	trap 'if [ "${ROLLBACK_ACTIVE:-0}" = "1" ]; then TRANSACTION_SIGNAL_PENDING="1"; else IPSet_Lock_Interrupt_Cleanup; IPSet_Lock_Interrupt_Propagate; IPSet_Lock_Flock_Cleanup; IPSet_Dnsmasq_Restart_After_Unlock; IPSet_Restore_Traps "${SAVED_TRAPS}"; exit 1; fi' HUP INT QUIT ABRT TERM TSTP
	trap 'STATUS="$?"; IPSet_Lock_Flock_Cleanup; IPSet_Dnsmasq_Restart_After_Unlock; IPSet_Restore_Traps "${SAVED_TRAPS}"; exit "${STATUS}"' EXIT
	IPSET_LOCK_ACTIVE="1"
	"$@"
	STATUS="$?"
	IPSET_LOCK_ACTIVE="0"
	IPSet_Lock_Flock_Cleanup
	IPSet_Restore_Traps "${SAVED_TRAPS}"
	return "${STATUS}"
}

IPSet_Lock_Flock_Cleanup() {
	flock -u 8 >/dev/null 2>&1
	exec 8>&-
}

# IPSet_Lock_Mkdir serializes an IPSet operation using a validated directory lock and restores traps and lock state when it completes.
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
	trap 'if [ "${ROLLBACK_ACTIVE:-0}" = "1" ]; then TRANSACTION_SIGNAL_PENDING="1"; else IPSet_Lock_Interrupt_Cleanup; IPSet_Lock_Interrupt_Propagate; IPSet_Lock_Mkdir_Cleanup "${LOCK_DIR}"; IPSet_Dnsmasq_Restart_After_Unlock; IPSet_Restore_Traps "${SAVED_TRAPS}"; exit 1; fi' HUP INT QUIT ABRT TERM TSTP
	trap 'STATUS="$?"; IPSet_Lock_Mkdir_Cleanup "${LOCK_DIR}"; IPSet_Dnsmasq_Restart_After_Unlock; IPSet_Restore_Traps "${SAVED_TRAPS}"; exit "${STATUS}"' EXIT
	IPSET_LOCK_ACTIVE="1"
	"$@"
	STATUS="$?"
	IPSET_LOCK_ACTIVE="0"
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

# IPSet_Migrate migrates legacy AdGuardHome IPSet mappings into the managed IPSet file and updates the YAML reference when supported.
IPSet_Migrate() {
	local CURRENT_FILE TEMP_FILE USER_TEMP_FILE
	IPSET_MIGRATION_SKIPPED=""
	if ! adguard_ipset_allowed; then
		if ! IPSet_Disable_Managed; then
			agh_log warning IPSet_Migrate "state=migration action=disable_managed_ipset result=skipped reason=lan_mode_remove_failed"
			return 1
		fi
		IPSET_MIGRATION_SKIPPED="1"
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

# IPSet_Disable_Managed removes the managed YAML file reference, or any configured file reference when requested by topology enforcement.
IPSet_Disable_Managed() {
	local CURRENT_FILE TEMP_FILE
	IPSET_DISABLE_CHANGED=""
	[ -f "${YAML_FILE}" ] || return 0
	if ! CURRENT_FILE="$(IPSet_Current_File)"; then
		return 1
	fi
	[ -n "${CURRENT_FILE}" ] || return 0
	if [ "${1:-}" != "configured" ] && [ "${CURRENT_FILE}" != "${IPSET_FILE}" ]; then
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

# IPSet_Disable_Managed_For_Start_Locked stops AdGuardHome to disable managed IPSet configuration, then restores or restarts the service as needed.
IPSet_Disable_Managed_For_Start_Locked() {
	local WAS_RUNNING
	WAS_RUNNING="0"
	IPSET_START_STOPPED="${IPSET_START_STOPPED:-0}"
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
	if ! IPSet_Disable_Managed "${1:-}"; then
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

# IPSet_Enabled reports whether IPSet integration is enabled for the current installation mode and configuration.
IPSet_Enabled() {
	adguard_ipset_allowed || return 1
	[ "${CONFIG_IPSET:-YES}" != "NO" ]
}

# IPSet_Refresh refreshes managed IPSet mappings from an optional dnsmasq configuration file and restarts AdGuardHome when the mappings change.
IPSet_Refresh() {
	if [ "${TRANSACTION_ACTIVE:-0}" = "1" ] && [ "${IPSET_LOCK_ACTIVE:-0}" = "1" ]; then
		IPSet_Refresh_After_Recovery "$@"
	else
		IPSet_Lock IPSet_Refresh_After_Recovery "$@"
	fi
}

# IPSet_Refresh_After_Recovery recovers pending state and completes a non-transactional refresh without releasing the shared lock.
IPSet_Refresh_After_Recovery() {
	local CURRENT_FILE DNSMASQ_RESTART_SKIP RESTART_STATUS
	[ "${TRANSACTION_ACTIVE:-0}" = "1" ] || dnsmasq_ipset_state_recover_pending || return 1
	if ! adguard_ipset_allowed; then
		if ! CURRENT_FILE="$(IPSet_Current_File 2>/dev/null)"; then
			return 1
		fi
		[ -n "${CURRENT_FILE}" ] || return 0
		agh_log info IPSet_Refresh "state=refresh action=disable_configured_ipset result=required reason=topology_disallowed file=${CURRENT_FILE}"
		DNSMASQ_RESTART_SKIP="${ADGUARDHOME_SKIP_DNSMASQ_RESTART:-}"
		if [ "${IPSET_REFRESH_FROM_DNSMASQ:-}" = "1" ]; then
			ADGUARDHOME_SKIP_DNSMASQ_RESTART="1"
		fi
		IPSet_Disable_Managed_For_Start_Locked configured
		RESTART_STATUS="$?"
		ADGUARDHOME_SKIP_DNSMASQ_RESTART="${DNSMASQ_RESTART_SKIP}"
		return "${RESTART_STATUS}"
	fi
	IPSet_Enabled || return 0
	IPSet_Supported || return 0
	IPSET_REFRESH_CHANGED=""
	IPSET_REFRESH_CONFIG="${1:-}"
	IPSet_Setup_Locked || return 1
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

# IPSet_Setup initializes IPSet configuration and mappings when IPSet is enabled and supported.
IPSet_Setup() {
	IPSet_Enabled || return 0
	IPSet_Supported || return 0
	IPSET_REFRESH_CONFIG=""
	IPSet_Lock IPSet_Setup_Locked
}

# IPSet_Setup_For_Start prepares IPSet configuration before AdGuardHome startup and disables managed IPSet settings when integration is unavailable, disabled, or unsupported.
IPSet_Setup_For_Start() {
	if ! adguard_ipset_allowed; then
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

# IPSet_Supported determines whether the installed AdGuardHome version supports IPSet configuration and records legacy-version status.
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

case "${1:-}" in
	status) CONFIG_LOAD_SCOPE="status" ;;
	stop | kill | services-stop | proc-restore) CONFIG_LOAD_SCOPE="stop" ;;
	dnsmasq | dnsmasq-sdn | local-cache) CONFIG_LOAD_SCOPE="dnsmasq" ;;
	firewall) CONFIG_LOAD_SCOPE="firewall" ;;
	*) CONFIG_LOAD_SCOPE="action" ;;
esac
if ! load_operation_config "${CONFIG_LOAD_SCOPE}"; then
	case "${CONFIG_LOAD_SCOPE}" in
		stop)
			set_operation_config_defaults
			CONFIG_DNSMASQ_MODE="enabled"
			printf '%s\n' "${NAME}: continuing stop with conservative configuration defaults" >&2
			;;
		*) return 1 2>/dev/null || exit 1 ;;
	esac
fi

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
{ for PID in $(adguard_monitor_pids); do if monitor_process_matches "${PID}" && [ "${PID}" != "$$" ]; then { MON_PID="${PID}"; }; fi; done; }

unset TZ
case "$1" in
	"monitor-start")
		if [ -n "${MON_PID}" ]; then { stop_monitor "${MON_PID}"; }; else { start_monitor & } fi
		;;
	"proc-restore")
		proc_restore
		;;
	"start" | "restart")
		{ "${SCRIPT_LOC}" init-start >/dev/null 2>&1; }
		;;
	"stop" | "kill")
		{ "${SCRIPT_LOC}" services-stop >/dev/null 2>&1; }
		;;
	"local-cache")
		adguard_local_cache_sync
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
				proc_restore
				{ stop_all_monitors; }
				;;
		esac
		;;
	*)
		{ ${LOWER_SCRIPT_LOC} "$1"; } && exit
		;;
esac
