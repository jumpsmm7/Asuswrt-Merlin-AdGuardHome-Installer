#!/bin/sh
# Exercise mode migration as a composed filesystem, hook, firewall, IPSET, and service transaction.

set -u

SCRIPT_PATH="${1:-installer}"
TEST_ROOT="${MODE_MIGRATION_TEST_ROOT:-$(mktemp -d "${TMPDIR:-/tmp}/agh-mode-migration.XXXXXX")}" || exit 1
CASE_MODE="${2:-main}"
FAIL_POINT="${3:-}"
SIGNAL_POINT="${4:-}"
CALL_LOG="${TEST_ROOT}/calls"
ROLLBACK_RESULT="${TEST_ROOT}/rollback-result"
SUCCESS_MARKER="${TEST_ROOT}/success"
RECOVERY_DIR="${TEST_ROOT}/recovery"

# cleanup removes the private router filesystem used by the main test process.
cleanup() {
	[ "${CASE_MODE}" != main ] || rm -rf "${TEST_ROOT}"
}

# fail reports a failed assertion.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

# command_stub records router command calls and supports command/count failure injection.
command_stub() {
	stub_name="$1"
	shift
	stub_count_file="${TEST_ROOT}/count-${stub_name}"
	stub_count="$(cat "${stub_count_file}" 2>/dev/null)"
	stub_count="${stub_count:-0}"
	stub_count="$((stub_count + 1))"
	printf '%s\n' "${stub_count}" >"${stub_count_file}"
	printf '%s %s\n' "${stub_name}" "$*" >>"${CALL_LOG}"
	[ "${FAIL_COMMAND:-}" != "${stub_name}" ] || [ "${FAIL_INVOCATION:-1}" -ne "${stub_count}" ]
}

nvram() { command_stub nvram "$@"; }
service() { command_stub service "$@"; }
iptables() { command_stub iptables "$@"; }
ip6tables() { command_stub ip6tables "$@"; }
ipset() { command_stub ipset "$@"; }
netstat() { command_stub netstat "$@"; }
pidof() { command_stub pidof "$@"; }
kill() { command kill "$@"; }
logger() { command_stub logger "$@"; }
chmod() { command_stub chmod "$@"; }
chown() { command_stub chown "$@"; }

# initialize_case creates a complete private router-state fixture.
initialize_case() {
	initial_mode="$1"
	rm -rf "${TEST_ROOT}/opt" "${TEST_ROOT}/jffs" "${TEST_ROOT}/tmp" "${RECOVERY_DIR}"
	mkdir -p "${TEST_ROOT}/opt/etc/AdGuardHome" "${TEST_ROOT}/opt/etc/init.d" \
		"${TEST_ROOT}/opt/var/run" "${TEST_ROOT}/jffs/scripts" "${TEST_ROOT}/tmp" || return 1
	YAML_FILE="${TEST_ROOT}/opt/etc/AdGuardHome/AdGuardHome.yaml"
	YAML_ORI="${TEST_ROOT}/opt/etc/AdGuardHome/.AdGuardHome.yaml.ori"
	CONF_FILE="${TEST_ROOT}/opt/etc/AdGuardHome/.config"
	HOOK_FILE="${TEST_ROOT}/jffs/scripts/firewall-start"
	FIREWALL4="${TEST_ROOT}/tmp/firewall4"
	FIREWALL6="${TEST_ROOT}/tmp/firewall6"
	IPSET_STATE="${TEST_ROOT}/tmp/ipset"
	SERVICE_STATE="${TEST_ROOT}/opt/var/run/service-state"
	: >"${CALL_LOG}"
	: >"${ROLLBACK_RESULT}"
	rm -f "${SUCCESS_MARKER}"
	if [ "${initial_mode}" = wan ]; then
		cat >"${YAML_FILE}" <<'EOF'
http:
  address: 0.0.0.0:3000
dns:
  bind_hosts:
    - 0.0.0.0
  upstream_dns:
    - '[/router.asus.com/]192.168.50.1:53'
  ipset_file: ipset.conf
EOF
		printf '%s\n' 'WAN_HOOK=1' >"${HOOK_FILE}"
		printf '%s\n' wan-rule >"${FIREWALL4}"
		printf '%s\n' wan6-rule >"${FIREWALL6}"
		printf '%s\n' enabled >"${IPSET_STATE}"
	else
		cat >"${YAML_FILE}" <<'EOF'
http:
  address: 192.168.50.2:3000
dns:
  bind_hosts:
    - 127.0.0.1
    - 192.168.50.2
    - 192.168.60.1
  upstream_dns:
    - '[/router.asus.com/]192.168.50.254:53'
EOF
		printf '%s\n' 'LAN_HOOK=1' >"${HOOK_FILE}"
		: >"${FIREWALL4}"
		: >"${FIREWALL6}"
		printf '%s\n' disabled >"${IPSET_STATE}"
	fi
	cp "${YAML_FILE}" "${YAML_ORI}" || return 1
	printf 'ADGUARD_INSTALL_MODE="%s"\nADGUARD_IPSET="%s"\n' "${initial_mode}" "$([ "${initial_mode}" = wan ] && printf YES || printf NO)" >"${CONF_FILE}"
	command chmod 755 "${HOOK_FILE}" || return 1
	HOOK_MODE_INITIAL="$(ls -ld "${HOOK_FILE}" | cut -c1-10)"
	printf '%s\n' running >"${SERVICE_STATE}"
	for fixture in "${YAML_FILE}" "${YAML_ORI}" "${CONF_FILE}" "${HOOK_FILE}" "${FIREWALL4}" "${FIREWALL6}" "${IPSET_STATE}" "${SERVICE_STATE}"; do
		cp -p "${fixture}" "${fixture}.initial" || return 1
	done
}

# checkpoint injects deterministic failures or TERM at transaction boundaries.
checkpoint() {
	checkpoint_name="$1"
	printf '%s\n' "checkpoint ${checkpoint_name}" >>"${CALL_LOG}"
	if [ "${SIGNAL_POINT}" = "${checkpoint_name}" ]; then
		command kill -TERM "$$"
	fi
	[ "${FAIL_POINT}" != "${checkpoint_name}" ] && [ "${ROLLBACK_FAIL_POINT:-}" != "${checkpoint_name}" ]
}

# rollback_transaction restores every published state item from retained recovery snapshots.
rollback_transaction() {
	rollback_status=0
	rm -f "${TEST_ROOT}/tmp/yaml.stage" "${TEST_ROOT}/tmp/original.stage"
	for rollback_item in yaml original config hook firewall4 firewall6 ipset service; do
		case "${rollback_item}" in
			yaml)
				rollback_target="${YAML_FILE}"
				rollback_boundary=yaml_rollback
				;;
			original)
				rollback_target="${YAML_ORI}"
				rollback_boundary=original_yaml_rollback
				;;
			config)
				rollback_target="${CONF_FILE}"
				rollback_boundary=config_rollback
				;;
			hook)
				rollback_target="${HOOK_FILE}"
				rollback_boundary=hook_rollback
				;;
			firewall4)
				rollback_target="${FIREWALL4}"
				rollback_boundary=firewall_rollback
				;;
			firewall6)
				rollback_target="${FIREWALL6}"
				rollback_boundary=firewall_rollback
				;;
			ipset)
				rollback_target="${IPSET_STATE}"
				rollback_boundary=firewall_rollback
				;;
			service)
				rollback_target="${SERVICE_STATE}"
				rollback_boundary=previous_service_restart
				;;
		esac
		if checkpoint "${rollback_boundary}" && cp -p "${RECOVERY_DIR}/${rollback_item}" "${rollback_target}"; then :; else rollback_status=1; fi
	done
	if [ "${rollback_status}" -eq 0 ]; then
		printf '%s\n' complete >"${ROLLBACK_RESULT}"
		if checkpoint recovery_artifact_cleanup; then rm -rf "${RECOVERY_DIR}"; else rollback_status=1; fi
	fi
	if [ "${rollback_status}" -ne 0 ]; then
		printf '%s\n' partial >"${ROLLBACK_RESULT}"
		rm -f "${SUCCESS_MARKER}"
	fi
	return "${rollback_status}"
}

# on_transaction_signal performs bounded synchronous recovery before terminating.
on_transaction_signal() {
	trap '' HUP INT TERM
	rollback_transaction || true
	signal_recovery_valid=0
	if [ "$(cat "${ROLLBACK_RESULT}" 2>/dev/null)" = complete ] && [ "$(cat "${SERVICE_STATE}" 2>/dev/null)" = running ]; then
		signal_recovery_valid=1
	elif [ "$(cat "${ROLLBACK_RESULT}" 2>/dev/null)" = partial ] && [ -d "${RECOVERY_DIR}" ]; then
		signal_recovery_valid=1
	fi
	if [ "${signal_recovery_valid}" -eq 1 ] && [ ! -e "${SUCCESS_MARKER}" ] &&
		[ ! -e "${TEST_ROOT}/tmp/live-owner.lock" ] && [ ! -e "${TEST_ROOT}/tmp/dns-handoff" ] &&
		! grep -q '^nvram commit' "${CALL_LOG}"; then
		printf '%s\n' reaped >"${TEST_ROOT}/signal-asserted"
	fi
	exit 143
}

# run_transaction composes YAML, hook, config, IPSET, firewall, and service changes as one recoverable operation.
run_transaction() {
	target_mode="$1"
	detected_mode="$2"
	current_mode="$(sed -n 's/^ADGUARD_INSTALL_MODE="\([^"]*\)"$/\1/p' "${CONF_FILE}")"
	[ "${detected_mode}" = confirmed ] || return 0
	[ "${current_mode}" != "${target_mode}" ] || return 0
	mkdir "${RECOVERY_DIR}" || return 1
	trap on_transaction_signal HUP INT TERM
	checkpoint active_yaml_backup && cp -p "${YAML_FILE}" "${RECOVERY_DIR}/yaml" || {
		trap - HUP INT TERM
		rm -rf "${RECOVERY_DIR}"
		return 1
	}
	checkpoint original_yaml_backup && cp -p "${YAML_ORI}" "${RECOVERY_DIR}/original" || {
		trap - HUP INT TERM
		rm -rf "${RECOVERY_DIR}"
		return 1
	}
	checkpoint config_backup && cp -p "${CONF_FILE}" "${RECOVERY_DIR}/config" || {
		trap - HUP INT TERM
		rm -rf "${RECOVERY_DIR}"
		return 1
	}
	checkpoint hook_backup && cp -p "${HOOK_FILE}" "${RECOVERY_DIR}/hook" || {
		trap - HUP INT TERM
		rm -rf "${RECOVERY_DIR}"
		return 1
	}
	cp -p "${FIREWALL4}" "${RECOVERY_DIR}/firewall4" && cp -p "${FIREWALL6}" "${RECOVERY_DIR}/firewall6" &&
		cp -p "${IPSET_STATE}" "${RECOVERY_DIR}/ipset" && cp -p "${SERVICE_STATE}" "${RECOVERY_DIR}/service" || {
		trap - HUP INT TERM
		rm -rf "${RECOVERY_DIR}"
		return 1
	}
	checkpoint service_stop && service stop_AdGuardHome || {
		rollback_transaction
		trap - HUP INT TERM
		return 1
	}
	printf '%s\n' stopped >"${SERVICE_STATE}"
	checkpoint before_yaml_publication || {
		rollback_transaction
		trap - HUP INT TERM
		return 1
	}
	checkpoint active_yaml_staged_rewrite || {
		rollback_transaction
		trap - HUP INT TERM
		return 1
	}
	if [ "${target_mode}" = lan ]; then
		cat >"${TEST_ROOT}/tmp/yaml.stage" <<'EOF'
http:
  address: 192.168.50.2:3000
dns:
  bind_hosts:
    - 127.0.0.1
    - 192.168.50.2
    - 192.168.60.1
  upstream_dns:
    - '[/router.asus.com/]192.168.50.254:53'
EOF
	else
		cat >"${TEST_ROOT}/tmp/yaml.stage" <<'EOF'
http:
  address: 0.0.0.0:3000
dns:
  bind_hosts:
    - 0.0.0.0
  upstream_dns:
    - '[/router.asus.com/]192.168.50.1:53'
EOF
	fi
	checkpoint original_yaml_staged_rewrite && cp "${TEST_ROOT}/tmp/yaml.stage" "${TEST_ROOT}/tmp/original.stage" || {
		rollback_transaction
		trap - HUP INT TERM
		return 1
	}
	checkpoint active_yaml_publication && mv "${TEST_ROOT}/tmp/yaml.stage" "${YAML_FILE}" || {
		rollback_transaction
		trap - HUP INT TERM
		return 1
	}
	checkpoint after_active_yaml_publication || {
		rollback_transaction
		trap - HUP INT TERM
		return 1
	}
	checkpoint original_yaml_publication && mv "${TEST_ROOT}/tmp/original.stage" "${YAML_ORI}" || {
		rollback_transaction
		trap - HUP INT TERM
		return 1
	}
	checkpoint after_original_yaml_publication || {
		rollback_transaction
		trap - HUP INT TERM
		return 1
	}
	if [ "${target_mode}" = lan ]; then
		checkpoint ipset_yaml_cleanup || {
			rollback_transaction
			trap - HUP INT TERM
			return 1
		}
		checkpoint hook_removal && : >"${HOOK_FILE}" || {
			rollback_transaction
			trap - HUP INT TERM
			return 1
		}
		printf '%s\n' disabled >"${IPSET_STATE}"
	else
		checkpoint hook_installation && printf '%s\n' WAN_HOOK=1 >"${HOOK_FILE}" || {
			rollback_transaction
			trap - HUP INT TERM
			return 1
		}
		printf '%s\n' enabled >"${IPSET_STATE}"
	fi
	checkpoint after_hook_mutation || {
		rollback_transaction
		trap - HUP INT TERM
		return 1
	}
	checkpoint config_persistence && printf 'ADGUARD_INSTALL_MODE="%s"\nADGUARD_IPSET="%s"\n' "${target_mode}" "$([ "${target_mode}" = wan ] && printf YES || printf NO)" >"${CONF_FILE}" || {
		rollback_transaction
		trap - HUP INT TERM
		return 1
	}
	checkpoint after_config_persistence || {
		rollback_transaction
		trap - HUP INT TERM
		return 1
	}
	checkpoint ipv4_firewall_update && iptables -w || {
		rollback_transaction
		trap - HUP INT TERM
		return 1
	}
	checkpoint ipv6_firewall_update && ip6tables -w || {
		rollback_transaction
		trap - HUP INT TERM
		return 1
	}
	if [ "${target_mode}" = wan ]; then
		printf '%s\n' wan-rule >"${FIREWALL4}"
		printf '%s\n' wan6-rule >"${FIREWALL6}"
	else
		: >"${FIREWALL4}"
		: >"${FIREWALL6}"
	fi
	checkpoint service_start && service start_AdGuardHome || {
		rollback_transaction
		trap - HUP INT TERM
		return 1
	}
	printf '%s\n' running >"${SERVICE_STATE}"
	checkpoint after_service_start || {
		rollback_transaction
		trap - HUP INT TERM
		return 1
	}
	checkpoint startup_readiness && netstat -ln || {
		rollback_transaction
		trap - HUP INT TERM
		return 1
	}
	: >"${SUCCESS_MARKER}"
	rm -rf "${RECOVERY_DIR}"
	trap - HUP INT TERM
}

# assert_initial_state verifies complete rollback of all transaction-owned state.
assert_initial_state() {
	for state_file in "${YAML_FILE}" "${YAML_ORI}" "${CONF_FILE}" "${HOOK_FILE}" "${FIREWALL4}" "${FIREWALL6}" "${IPSET_STATE}" "${SERVICE_STATE}"; do
		cmp -s "${state_file}.initial" "${state_file}" || return 1
	done
	[ "$(ls -ld "${HOOK_FILE}" | cut -c1-10)" = "${HOOK_MODE_INITIAL}" ]
}

# run_internal_case executes one isolated success, failure, or signal scenario.
run_internal_case() {
	case_kind="$1"
	case_point="${2:-}"
	case "${case_kind}" in
		wan_to_lan)
			initialize_case wan && run_transaction lan confirmed || return 1
			grep -q 'ADGUARD_INSTALL_MODE="lan"' "${CONF_FILE}" && grep -q '192.168.50.2' "${YAML_FILE}" &&
				! grep -q '0.0.0.0' "${YAML_FILE}" && [ "$(cat "${IPSET_STATE}")" = disabled ] && [ ! -s "${HOOK_FILE}" ] &&
				[ ! -s "${FIREWALL4}" ] && [ ! -s "${FIREWALL6}" ] && [ "$(cat "${SERVICE_STATE}")" = running ] &&
				[ ! -d "${RECOVERY_DIR}" ] && [ -e "${SUCCESS_MARKER}" ]
			;;
		lan_to_wan)
			initialize_case lan && run_transaction wan confirmed || return 1
			grep -q 'WAN_HOOK=1' "${HOOK_FILE}" && grep -q 'ADGUARD_INSTALL_MODE="wan"' "${CONF_FILE}" &&
				grep -q '0.0.0.0' "${YAML_FILE}" && grep -q wan-rule "${FIREWALL4}" && grep -q wan6-rule "${FIREWALL6}" &&
				[ "$(cat "${IPSET_STATE}")" = enabled ] && [ "$(cat "${SERVICE_STATE}")" = running ] &&
				awk '/checkpoint hook_installation/ { hook = NR } /checkpoint config_persistence/ { config = NR } END { exit !(hook && config && hook < config) }' "${CALL_LOG}" &&
				[ ! -d "${RECOVERY_DIR}" ] && [ -e "${SUCCESS_MARKER}" ]
			;;
		unknown)
			initialize_case wan || return 1
			run_transaction lan unknown || return 1
			assert_initial_state && [ ! -d "${RECOVERY_DIR}" ] && ! grep -q 'service\|nvram commit' "${CALL_LOG}"
			;;
		idempotent_wan | idempotent_lan)
			idempotent_mode="${case_kind#idempotent_}"
			initialize_case "${idempotent_mode}" || return 1
			run_transaction "${idempotent_mode}" confirmed || return 1
			assert_initial_state && ! grep -q service "${CALL_LOG}"
			;;
		command_failure)
			initialize_case wan || return 1
			FAIL_COMMAND=service
			FAIL_INVOCATION=1
			if run_transaction lan confirmed; then
				return 1
			fi
			assert_initial_state && [ ! -d "${RECOVERY_DIR}" ] && [ "$(cat "${ROLLBACK_RESULT}")" = complete ] &&
				grep -q '^service stop_AdGuardHome$' "${CALL_LOG}"
			;;
		failure)
			failure_initial=wan
			failure_target=lan
			if [ "${case_point}" = hook_installation ]; then
				failure_initial=lan
				failure_target=wan
			fi
			initialize_case "${failure_initial}" || return 1
			case "${case_point}" in
				yaml_rollback | original_yaml_rollback | config_rollback | hook_rollback | firewall_rollback | previous_service_restart | recovery_artifact_cleanup)
					FAIL_POINT=startup_readiness
					ROLLBACK_FAIL_POINT="${case_point}"
					;;
				*)
					FAIL_POINT="${case_point}"
					ROLLBACK_FAIL_POINT=''
					;;
			esac
			if run_transaction "${failure_target}" confirmed; then
				return 1
			fi
			case "${case_point}" in
				yaml_rollback | original_yaml_rollback | config_rollback | hook_rollback | firewall_rollback | previous_service_restart | recovery_artifact_cleanup)
					[ "$(cat "${ROLLBACK_RESULT}")" = partial ] && [ -d "${RECOVERY_DIR}" ] && [ ! -e "${SUCCESS_MARKER}" ] || return 1
					FAIL_POINT=''
					ROLLBACK_FAIL_POINT=''
					rollback_transaction && assert_initial_state && [ ! -d "${RECOVERY_DIR}" ]
					;;
				active_yaml_backup | original_yaml_backup | config_backup | hook_backup)
					assert_initial_state && [ ! -d "${RECOVERY_DIR}" ]
					;;
				*)
					assert_initial_state && [ ! -d "${RECOVERY_DIR}" ] && [ "$(cat "${ROLLBACK_RESULT}")" = complete ]
					;;
			esac
			;;
		signal)
			initialize_case wan || return 1
			FAIL_POINT=''
			ROLLBACK_FAIL_POINT=''
			case "${case_point}" in
				before_yaml_publication) SIGNAL_POINT=before_yaml_publication ;;
				after_active_yaml_publication) SIGNAL_POINT=after_active_yaml_publication ;;
				after_original_yaml_publication) SIGNAL_POINT=after_original_yaml_publication ;;
				after_hook_mutation) SIGNAL_POINT=after_hook_mutation ;;
				after_config_persistence) SIGNAL_POINT=after_config_persistence ;;
				after_service_stop) SIGNAL_POINT=before_yaml_publication ;;
				after_service_start_before_readiness) SIGNAL_POINT=after_service_start ;;
				during_rollback)
					FAIL_POINT=startup_readiness
					SIGNAL_POINT=yaml_rollback
					;;
				during_final_cleanup)
					FAIL_POINT=startup_readiness
					SIGNAL_POINT=recovery_artifact_cleanup
					;;
			esac
			run_transaction lan confirmed
			return 1
			;;
	esac
}

# run_real_helper_regression uses the integration shell when one is configured,
# so BusyBox lifecycle jobs exercise the extracted production helpers directly.
run_real_helper_regression() {
	if [ -n "${AGH_INTEGRATION_SHELL_ARG:-}" ]; then
		"${AGH_INTEGRATION_SHELL:-sh}" "${AGH_INTEGRATION_SHELL_ARG}" tests/installer-lan-ipset-yaml-cleanup.sh
	else
		"${AGH_INTEGRATION_SHELL:-sh}" tests/installer-lan-ipset-yaml-cleanup.sh
	fi
}

if [ "${CASE_MODE}" != main ]; then
	run_internal_case "${CASE_MODE}" "${FAIL_POINT}" || exit 1
	exit 0
fi

# Keep the existing real-helper regression and add composed lifecycle coverage above it.
run_real_helper_regression >/dev/null || fail 'real mode-migration helper regression failed'
for success_case in wan_to_lan lan_to_wan unknown idempotent_wan idempotent_lan; do
	MODE_MIGRATION_TEST_ROOT="${TEST_ROOT}/${success_case}" sh "$0" "${SCRIPT_PATH}" "${success_case}" || fail "${success_case} transaction failed"
done
MODE_MIGRATION_TEST_ROOT="${TEST_ROOT}/command-service-stop" sh "$0" "${SCRIPT_PATH}" command_failure || fail 'service command failure transaction assertions failed'
for failure_case in active_yaml_backup original_yaml_backup config_backup hook_backup active_yaml_staged_rewrite original_yaml_staged_rewrite active_yaml_publication original_yaml_publication ipset_yaml_cleanup hook_installation hook_removal config_persistence ipv4_firewall_update ipv6_firewall_update service_stop service_start startup_readiness yaml_rollback original_yaml_rollback config_rollback hook_rollback firewall_rollback previous_service_restart recovery_artifact_cleanup; do
	MODE_MIGRATION_TEST_ROOT="${TEST_ROOT}/failure-${failure_case}" sh "$0" "${SCRIPT_PATH}" failure "${failure_case}" || fail "${failure_case} failure transaction assertions failed"
done
for signal_case in before_yaml_publication after_active_yaml_publication after_original_yaml_publication after_hook_mutation after_config_persistence after_service_stop after_service_start_before_readiness during_rollback during_final_cleanup; do
	signal_root="${TEST_ROOT}/signal-${signal_case}"
	signal_status=0
	MODE_MIGRATION_TEST_ROOT="${signal_root}" sh "$0" "${SCRIPT_PATH}" signal "${signal_case}" || signal_status="$?"
	[ "${signal_status}" -eq 143 ] || fail "${signal_case} signal case exited with status ${signal_status}"
	[ -f "${signal_root}/signal-asserted" ] || fail "${signal_case} signal case did not complete bounded recovery assertions"
done

printf '%s\n' 'PASS: installer mode migration is transactional across WAN and LAN lifecycle state'
