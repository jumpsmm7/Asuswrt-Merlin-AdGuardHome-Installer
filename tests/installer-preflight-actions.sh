#!/bin/sh
# Verify preflight action routing stays flow-aware for Entware and jq checks.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-preflight-actions.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions"
PREFLIGHT_FILE="${TMP_ROOT}/preflight"

cleanup() {
	rm -rf "${TMP_ROOT}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"
mkdir -p "${TMP_ROOT}" || fail 'could not create test directory'

sed -n '/^ipv4_is_valid() {$/,/^}$/p; /^preflight_action_requires_entware() {$/,/^preflight_check_path() {$/p' "${SCRIPT_PATH}" | sed '$d' >"${FUNCTIONS_FILE}" ||
	fail 'could not extract preflight action helpers'
[ -s "${FUNCTIONS_FILE}" ] || fail 'preflight action helper extraction was empty'

sed -n '/^preflight() {$/,/^sanitize_branch() {$/p' "${SCRIPT_PATH}" | sed '$d' >"${PREFLIGHT_FILE}" ||
	fail 'could not extract preflight function'
[ -s "${PREFLIGHT_FILE}" ] || fail 'preflight function extraction was empty'

usage_line="$(grep -n 'sh installer preflight \[install|reconfigure|update|restore|uninstall|status\]' "${SCRIPT_PATH}" | cut -d: -f1)" ||
	fail 'preflight usage line is missing'
handler_line="$(grep -n '^if \[ "${1:-}" = "preflight" \]; then' "${SCRIPT_PATH}" | cut -d: -f1)" ||
	fail 'preflight top-level handler is missing'
dependency_line="$(grep -n '^installer_dependencies_available || exit 1' "${SCRIPT_PATH}" | cut -d: -f1)" ||
	fail 'dependency validation line is missing'
if [ -z "${usage_line}" ] || [ -z "${handler_line}" ] || [ -z "${dependency_line}" ]; then
	fail 'could not compare preflight routing lines'
fi
if [ "${handler_line}" -ge "${dependency_line}" ]; then
	fail 'preflight must run before dependency validation so missing Entware can be reported safely'
fi

grep -q 'preflight_check_jq "${entware_required}"' "${SCRIPT_PATH}" ||
	fail 'preflight jq check must receive the Entware-required state'
grep -q 'preflight.jq.install_hint=opkg install jq' "${SCRIPT_PATH}" ||
	fail 'preflight jq check must report the Entware install hint'
grep -q 'preflight_check_stock_commands || failed="1"' "${SCRIPT_PATH}" ||
	fail 'preflight must check the broader stock command set'
grep -q 'preflight_action_requires_downloader "${action}"' "${SCRIPT_PATH}" ||
	fail 'preflight must gate downloader checks by action'
grep -q 'preflight_action_requires_cru "${action}"' "${SCRIPT_PATH}" ||
	fail 'preflight must gate cru checks by action'
grep -q 'preflight_action_requires_firewall_tools "${action}"' "${SCRIPT_PATH}" ||
	fail 'preflight must gate firewall checks by action'
grep -q 'preflight_check_jffs_ready || failed="1"' "${SCRIPT_PATH}" ||
	fail 'preflight must check pending JFFS format for install/reconfigure flows'
grep -q 'nvram get jffs2_format' "${SCRIPT_PATH}" ||
	fail 'preflight JFFS readiness must read jffs2_format without changing nvram'
grep -q 'preflight_check_router_eligibility || failed="1"' "${SCRIPT_PATH}" ||
	fail 'preflight must check router eligibility for actionable flows'
grep -q 'preflight_check_entware_package coreutils-sha256sum || true' "${SCRIPT_PATH}" ||
	fail 'preflight must keep coreutils-sha256sum package guidance from satisfying SHA-256 support'
grep -q 'preflight.entware.password_hash.install_hint=opkg install python3 python3-bcrypt' "${SCRIPT_PATH}" ||
	fail 'preflight must report password hashing package guidance'
grep -q 'python_bcrypt_available || bcrypt_tool_available' "${SCRIPT_PATH}" ||
	fail 'preflight must verify bcrypt-tool before reporting password hashing support'
grep -q 'bcrypt-tool hash preflight 10' "${SCRIPT_PATH}" ||
	fail 'bcrypt-tool availability must probe hash generation'
grep -q 'preflight_check_entware_package column || true' "${SCRIPT_PATH}" ||
	fail 'preflight must keep column package guidance from satisfying timezone column support'
grep -q 'preflight.entware.dependent_checks=SKIP_ENTWARE_MISSING' "${SCRIPT_PATH}" ||
	fail 'preflight must skip Entware-dependent checks when Entware is unavailable'

run_preflight_gate_case() {
	case_name="$1"
	entware_status="$2"
	expected_skip="$3"
	out_file="${TMP_ROOT}/${case_name}.out"
	stub_file="${TMP_ROOT}/${case_name}.stub"
	cat >"${stub_file}" <<EOF
PTXT() { printf '%s\n' "\$*"; }
AI_VERSION=TEST
PATH=/bin:/sbin:/usr/bin:/usr/sbin
preflight_action_requires_downloader() { return 1; }
preflight_action_requires_service_tools() { return 1; }
preflight_action_requires_cru() { return 1; }
preflight_action_requires_firewall_tools() { return 1; }
preflight_action_requires_jffs_ready() { return 1; }
preflight_action_requires_router_eligibility() { return 1; }
preflight_action_requires_entware() { return 0; }
preflight_action_requires_jq() { return 1; }
preflight_action_requires_sha256() { return 0; }
preflight_action_requires_password_hash() { return 0; }
preflight_action_requires_timezone_column() { return 0; }
preflight_check_path() { return 0; }
preflight_check_stock_commands() { return 0; }
preflight_check_entware() { return ${entware_status}; }
preflight_check_sha256_support() { PTXT 'called.sha256=yes'; return 0; }
preflight_check_password_hash_support() { PTXT 'called.password_hash=yes'; return 0; }
preflight_check_timezone_column() { PTXT 'called.column=yes'; return 0; }
. "${PREFLIGHT_FILE}"
preflight install
EOF
	sh "${stub_file}" >"${out_file}" 2>&1 || true
	case "${expected_skip}" in
		yes)
			grep -q 'preflight.entware.dependent_checks=SKIP_ENTWARE_MISSING' "${out_file}" ||
				fail 'preflight must report skipped Entware-dependent checks when Entware is missing'
			if grep -q '^called\.' "${out_file}"; then
				fail 'preflight must not run Entware-dependent checks when Entware is missing'
			fi
			;;
		no)
			grep -q 'called.sha256=yes' "${out_file}" || fail 'preflight must run SHA-256 check when Entware is available'
			grep -q 'called.password_hash=yes' "${out_file}" || fail 'preflight must run password hash check when Entware is available'
			grep -q 'called.column=yes' "${out_file}" || fail 'preflight must run column check when Entware is available'
			if grep -q 'SKIP_ENTWARE_MISSING' "${out_file}"; then
				fail 'preflight must not report Entware skip when Entware is available'
			fi
			;;
	esac
}

run_preflight_gate_case missing 1 yes
run_preflight_gate_case available 0 no

run_router_mode_case() {
	case_name="$1"
	sw_mode="$2"
	lan_ipaddr="$3"
	expected_status="$4"
	shift 4
	out_file="${TMP_ROOT}/router-${case_name}.out"
	stub_file="${TMP_ROOT}/router-${case_name}.stub"
	cat >"${stub_file}" <<EOF
PTXT() { printf '%s\n' "\$*"; }
ROUTER_MODEL=RT-AC68U
nvram() {
	[ "\$1" = "get" ] || return 1
	case "\$2" in
		sw_mode) printf '%s\n' '${sw_mode}' ;;
		lan_ipaddr) printf '%s\n' '${lan_ipaddr}' ;;
		*) return 1 ;;
	esac
}
. "${FUNCTIONS_FILE}"
preflight_check_router_eligibility
EOF
	if sh "${stub_file}" >"${out_file}" 2>&1; then
		actual_status=0
	else
		actual_status=1
	fi
	[ "${actual_status}" -eq "${expected_status}" ] || fail "unexpected router mode status for ${case_name}"
	for expected_line; do
		grep -q "^${expected_line}\$" "${out_file}" || fail "missing router mode line for ${case_name}: ${expected_line}"
	done
}

run_router_mode_case wan 1 '' 0 \
	'preflight.router.mode=wan' \
	'preflight.router.mode.result=OK'
run_router_mode_case lan 2 192.168.50.1 0 \
	'preflight.router.mode=lan' \
	'preflight.router.mode.result=OK' \
	'preflight.router.mode.note=non-router-mode-lan-install'
run_router_mode_case missing-lan-ip '' 192.168.50.1 0 \
	'preflight.router.mode=lan' \
	'preflight.router.mode.result=OK' \
	'preflight.router.mode.note=missing-sw-mode-lan-ip-fallback'
run_router_mode_case missing-no-lan-ip '' '' 1 \
	'preflight.router.mode=missing' \
	'preflight.router.mode.result=FAIL' \
	'preflight.router.mode.reason=missing-sw-mode-and-no-usable-lan-ip'
run_router_mode_case lan-no-lan-ip 2 '' 1 \
	'preflight.router.mode=lan' \
	'preflight.router.mode.result=FAIL' \
	'preflight.router.mode.reason=non-router-mode-and-no-usable-lan-ip'

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"

	assert_entware_required() {
		local action
		for action in "$@"; do
			if ! preflight_action_requires_entware "${action}"; then
				printf '%s\n' "expected Entware requirement for action: ${action}" >&2
				exit 1
			fi
		done
	}

	assert_entware_skipped() {
		local action
		for action in "$@"; do
			if preflight_action_requires_entware "${action}"; then
				printf '%s\n' "unexpected Entware requirement for action: ${action}" >&2
				exit 1
			fi
		done
	}

	assert_jq_skipped() {
		local action
		for action in "$@"; do
			if preflight_action_requires_jq "${action}"; then
				printf '%s\n' "unexpected jq requirement for action: ${action}" >&2
				exit 1
			fi
		done
	}

	assert_sha256_required() {
		local action
		for action in "$@"; do
			if ! preflight_action_requires_sha256 "${action}"; then
				printf '%s\n' "expected SHA-256 requirement for action: ${action}" >&2
				exit 1
			fi
		done
	}

	assert_password_hash_required() {
		local action
		for action in "$@"; do
			if ! preflight_action_requires_password_hash "${action}"; then
				printf '%s\n' "expected password hashing requirement for action: ${action}" >&2
				exit 1
			fi
		done
	}

	assert_jffs_ready_required() {
		local action
		for action in "$@"; do
			if ! preflight_action_requires_jffs_ready "${action}"; then
				printf '%s\n' "expected JFFS readiness requirement for action: ${action}" >&2
				exit 1
			fi
		done
	}

	assert_jffs_ready_skipped() {
		local action
		for action in "$@"; do
			if preflight_action_requires_jffs_ready "${action}"; then
				printf '%s\n' "unexpected JFFS readiness requirement for action: ${action}" >&2
				exit 1
			fi
		done
	}

	assert_router_eligibility_required() {
		local action
		for action in "$@"; do
			if ! preflight_action_requires_router_eligibility "${action}"; then
				printf '%s\n' "expected router eligibility requirement for action: ${action}" >&2
				exit 1
			fi
		done
	}

	assert_router_eligibility_skipped() {
		local action
		for action in "$@"; do
			if preflight_action_requires_router_eligibility "${action}"; then
				printf '%s\n' "unexpected router eligibility requirement for action: ${action}" >&2
				exit 1
			fi
		done
	}

	assert_base_tools_required() {
		local action
		for action in "$@"; do
			if ! preflight_action_requires_downloader "${action}" ||
				! preflight_action_requires_service_tools "${action}" ||
				! preflight_action_requires_cru "${action}" ||
				! preflight_action_requires_firewall_tools "${action}"; then
				printf '%s\n' "expected base tool requirements for action: ${action}" >&2
				exit 1
			fi
		done
	}

	assert_base_tools_skipped() {
		local action
		for action in "$@"; do
			if preflight_action_requires_downloader "${action}" ||
				preflight_action_requires_service_tools "${action}" ||
				preflight_action_requires_cru "${action}" ||
				preflight_action_requires_firewall_tools "${action}"; then
				printf '%s\n' "unexpected base tool requirements for action: ${action}" >&2
				exit 1
			fi
		done
	}

	assert_timezone_column_required() {
		local action
		for action in "$@"; do
			if ! preflight_action_requires_timezone_column "${action}"; then
				printf '%s\n' "expected timezone column requirement for action: ${action}" >&2
				exit 1
			fi
		done
	}

	assert_base_tools_required '' install update reconfigure restore uninstall ipset backup doctor netcheck dns-port-policy performance migrate-runtime-defaults
	assert_base_tools_skipped status preflight
	assert_entware_required '' install update reconfigure restore uninstall ipset backup doctor netcheck dns-port-policy performance migrate-runtime-defaults
	assert_jffs_ready_required '' install reconfigure 4
	assert_jffs_ready_skipped update restore uninstall ipset backup doctor netcheck dns-port-policy performance migrate-runtime-defaults status preflight
	assert_router_eligibility_required '' install update reconfigure restore uninstall ipset backup doctor netcheck dns-port-policy performance migrate-runtime-defaults
	assert_router_eligibility_skipped status preflight
	assert_entware_skipped status preflight
	assert_jq_skipped '' install update reconfigure restore uninstall ipset backup doctor status preflight netcheck dns-port-policy performance migrate-runtime-defaults
	assert_sha256_required '' install update restore blocklists unusedblocklists 9
	assert_password_hash_required '' install reconfigure changepw 3 4
	assert_timezone_column_required '' install reconfigure restore 4
) || fail 'preflight action helper returned an unexpected result'

printf '%s\n' 'PASS: preflight action routing keeps Entware and jq checks flow-aware'
