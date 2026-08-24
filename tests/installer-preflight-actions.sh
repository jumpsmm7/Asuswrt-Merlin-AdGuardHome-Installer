#!/bin/sh
# Verify preflight action routing stays flow-aware for Entware and jq checks.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-preflight-actions.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions"
PREFLIGHT_FILE="${TMP_ROOT}/preflight"
SHA256_FILE="${TMP_ROOT}/sha256-functions"

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

{
	sed -n '/^ipv4_is_valid() {$/,/^port_is_valid() {$/p' "${SCRIPT_PATH}" | sed '$d'
	sed -n '/^preflight_action_requires_entware() {$/,/^preflight_check_path() {$/p' "${SCRIPT_PATH}" | sed '$d'
} >"${FUNCTIONS_FILE}" || fail 'could not extract preflight action helpers'
[ -s "${FUNCTIONS_FILE}" ] || fail 'preflight action helper extraction was empty'

sed -n '/^preflight() {$/,/^sanitize_branch() {$/p' "${SCRIPT_PATH}" | sed '$d' >"${PREFLIGHT_FILE}" ||
	fail 'could not extract preflight function'
[ -s "${PREFLIGHT_FILE}" ] || fail 'preflight function extraction was empty'

{
	sed -n '/^sha256sum_available() {$/,/^jq_executable_usable() {$/p' "${SCRIPT_PATH}" | sed '$d'
	sed -n '/^preflight_check_sha256_support() {$/,/^preflight_check_timezone_column() {$/p' "${SCRIPT_PATH}" | sed '$d'
} >"${SHA256_FILE}" || fail 'could not extract SHA-256 preflight helpers'
[ -s "${SHA256_FILE}" ] || fail 'SHA-256 preflight helper extraction was empty'
sed -e 's#/opt/bin/sha256sum#"${SHA256SUM_OPT_BIN:-/opt/bin/sha256sum}"#g' \
	-e 's#/bin/busybox#"${BUSYBOX_BIN:-/bin/busybox}"#g' \
	"${SHA256_FILE}" >"${SHA256_FILE}.tmp" || fail 'could not isolate SHA-256 helper paths'
mv "${SHA256_FILE}.tmp" "${SHA256_FILE}" || fail 'could not update isolated SHA-256 helpers'

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
grep -q 'preflight_check_entware_package jq-full "opkg install jq-full --force-depends --force-overwrite --force-reinstall"' "${SCRIPT_PATH}" ||
	fail 'preflight jq check must report one canonical Entware install hint'
grep -q 'preflight_check_stock_commands || failed="1"' "${SCRIPT_PATH}" ||
	fail 'preflight must check the broader stock command set'
grep -q 'preflight_action_requires_downloader "${action}"' "${SCRIPT_PATH}" ||
	fail 'preflight must gate downloader checks by action'
grep -q 'preflight_action_requires_cru "${action}"' "${SCRIPT_PATH}" ||
	fail 'preflight must gate cru checks by action'
grep -q 'preflight_action_requires_firewall_tools "${action}"' "${SCRIPT_PATH}" ||
	fail 'preflight must gate firewall checks by action'
grep -A12 '^preflight() {$' "${SCRIPT_PATH}" | grep -q 'adguard_install_mode_detect >/dev/null 2>&1' ||
	fail 'preflight must snapshot shared install mode detection before action checks'
grep -q 'PREFLIGHT_INSTALL_MODE_DETECTED="1"' "${SCRIPT_PATH}" ||
	fail 'preflight must mark its install mode snapshot for all action checks'
grep -q 'adguard_install_mode_confirmed || return 1' "${SCRIPT_PATH}" ||
	fail 'preflight firewall checks must skip mode-dependent checks when detection is unknown'
grep -q 'preflight_check_jffs_ready || failed="1"' "${SCRIPT_PATH}" ||
	fail 'preflight must check pending JFFS format for install/reconfigure flows'
grep -q 'nvram get jffs2_format' "${SCRIPT_PATH}" ||
	fail 'preflight JFFS readiness must read jffs2_format without changing nvram'
grep -q 'preflight_check_router_eligibility || failed="1"' "${SCRIPT_PATH}" ||
	fail 'preflight must check router eligibility for actionable flows'
grep -q 'preflight_check_entware_package coreutils-sha256sum || true' "${SCRIPT_PATH}" ||
	fail 'preflight must keep coreutils-sha256sum package guidance from satisfying SHA-256 support'
grep -q 'preflight.entware.password_hash.install_hint=opkg install python3 python3-bcrypt --force-depends --force-overwrite --force-reinstall' "${SCRIPT_PATH}" ||
	fail 'preflight must report password hashing package guidance'
grep -q 'python_bcrypt_available || bcrypt_tool_available' "${SCRIPT_PATH}" ||
	fail 'preflight must verify bcrypt-tool before reporting password hashing support'
grep -q 'bcrypt-tool hash preflight 10' "${SCRIPT_PATH}" ||
	fail 'bcrypt-tool availability must probe hash generation'
grep -q 'preflight_check_entware_package column || true' "${SCRIPT_PATH}" ||
	fail 'preflight must keep column package guidance from satisfying timezone column support'
grep -q 'preflight.entware.dependent_checks=SKIP_ENTWARE_MISSING' "${SCRIPT_PATH}" ||
	fail 'preflight must skip Entware-dependent checks when Entware is unavailable'

# run_preflight_gate_case verifies that Entware-dependent preflight checks run or are skipped according to the simulated Entware status.
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
adguard_install_mode_detect() { ADGUARD_INSTALL_MODE_DETECTION=unknown; }
preflight_check_path() { return 0; }
preflight_check_stock_commands() { return 0; }
preflight_check_entware() { return ${entware_status}; }
preflight_check_sha256_support() { PTXT 'called.sha256=yes'; return 0; }
preflight_check_password_hash_support() { PTXT 'called.password_hash=yes'; return 0; }
preflight_check_timezone_column() { PTXT 'called.column=yes'; return 0; }
. "${PREFLIGHT_FILE}"
preflight install
EOF
	run_status=0
	sh "${stub_file}" >"${out_file}" 2>&1 || run_status=$?
	case "${expected_skip}" in
		yes)
			[ "${run_status}" -eq 1 ] || fail 'preflight must fail when Entware is missing'
			grep -q 'preflight.entware.dependent_checks=SKIP_ENTWARE_MISSING' "${out_file}" ||
				fail 'preflight must report skipped Entware-dependent checks when Entware is missing'
			grep -q 'called.sha256=yes' "${out_file}" ||
				fail 'preflight must check stock-compatible SHA-256 support when Entware is missing'
			if grep -q '^called\.password_hash=yes$' "${out_file}" ||
				grep -q '^called\.column=yes$' "${out_file}"; then
				fail 'preflight must not run Entware-dependent password or column checks when Entware is missing'
			fi
			;;
		no)
			[ "${run_status}" -eq 0 ] || fail 'preflight must succeed when Entware is available'
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

# run_preflight_sha_action_case verifies that checksum-dependent actions invoke the SHA-256 preflight independently of Entware.
run_preflight_sha_action_case() {
	action="$1"
	expected="$2"
	out_file="${TMP_ROOT}/sha-action-${action:-default}.out"
	stub_file="${TMP_ROOT}/sha-action-${action:-default}.stub"
	cat >"${stub_file}" <<EOF
PTXT() { printf '%s\n' "\$*"; }
AI_VERSION=TEST
PATH=/bin:/sbin:/usr/bin:/usr/sbin
adguard_install_mode_detect() { ADGUARD_INSTALL_MODE_DETECTION=unknown; }
preflight_action_requires_downloader() { return 1; }
preflight_action_requires_service_tools() { return 1; }
preflight_action_requires_cru() { return 1; }
preflight_action_requires_firewall_tools() { return 1; }
preflight_action_requires_jffs_ready() { return 1; }
preflight_action_requires_router_eligibility() { return 1; }
preflight_action_requires_entware() { return 1; }
preflight_action_requires_jq() { return 1; }
preflight_action_requires_password_hash() { return 1; }
preflight_action_requires_timezone_column() { return 1; }
. "${FUNCTIONS_FILE}"
preflight_check_path() { return 0; }
preflight_check_stock_commands() { return 0; }
preflight_check_sha256_support() { PTXT 'called.sha256=yes'; return 0; }
. "${PREFLIGHT_FILE}"
preflight '${action}'
EOF
	sh "${stub_file}" >"${out_file}" 2>&1 || true
	case "${expected}" in
		called) grep -q '^called.sha256=yes$' "${out_file}" || fail "${action:-default}: SHA-256 preflight was not called" ;;
		skipped)
			grep -q '^preflight.sha256.result=SKIP$' "${out_file}" || fail "${action}: SHA-256 preflight was not skipped"
			if grep -q '^called.sha256=yes$' "${out_file}"; then fail "${action}: SHA-256 preflight was called"; fi
			;;
	esac
}

for action in '' install update restore switchbranch 1 7 r R blocklists unusedblocklists 9; do
	run_preflight_sha_action_case "${action}" called
done
for action in uninstall reconfigure status preflight backup doctor; do
	run_preflight_sha_action_case "${action}" skipped
done

# Exercise the shared functional probe used by both preflight and runtime enforcement.
mkdir -p "${TMP_ROOT}/sha256-bin" || fail 'could not create temporary SHA-256 fixture directory'
cat >"${TMP_ROOT}/sha256-bin/sha256sum" <<'EOF'
#!/bin/sh
printf '%s  %s\n' 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' "${1:-}"
EOF
chmod 755 "${TMP_ROOT}/sha256-bin/sha256sum" || fail 'could not make temporary SHA-256 fixture executable'
cat >"${TMP_ROOT}/sha256-bin/which" <<EOF
#!/bin/sh
[ "\${1:-}" = sha256sum ] || exit 1
printf '%s\n' '${TMP_ROOT}/sha256-bin/sha256sum'
EOF
chmod 755 "${TMP_ROOT}/sha256-bin/which" || fail 'could not make temporary which fixture executable'
(
	PTXT() { printf '%s\n' "$*"; }
	ai_have_cmd() {
		[ "$1" = sha256sum ] || return 1
		[ "$(which "$1" 2>/dev/null)" = "${TMP_ROOT}/sha256-bin/sha256sum" ]
	}
	preflight_check_entware_package() {
		PTXT 'called.package=yes'
		return 1
	}
	. "${SHA256_FILE}"
	PATH="${TMP_ROOT}/sha256-bin"
	SHA256SUM_OPT_BIN="${TMP_ROOT}/missing-opt-sha256sum"
	BUSYBOX_BIN="${TMP_ROOT}/missing-busybox"
	sha256sum_available || exit 1
	preflight_check_sha256_support 0 || exit 1
) >"${TMP_ROOT}/sha-stock.out" 2>&1 || fail 'functional PATH sha256sum must satisfy SHA-256 preflight'
if grep -q '^called.package=yes$' "${TMP_ROOT}/sha-stock.out"; then
	fail 'functional stock sha256sum must not require coreutils-sha256sum'
fi

mkdir -p "${TMP_ROOT}/opt/bin" || fail 'could not create temporary Entware SHA-256 fixture directory'
cp "${TMP_ROOT}/sha256-bin/sha256sum" "${TMP_ROOT}/opt/bin/sha256sum" ||
	fail 'could not create temporary Entware SHA-256 fixture'
chmod 755 "${TMP_ROOT}/opt/bin/sha256sum" || fail 'could not make temporary Entware SHA-256 fixture executable'
mkdir -p "${TMP_ROOT}/no-sha-bin" || fail 'could not create empty PATH fixture directory'
cat >"${TMP_ROOT}/no-sha-bin/which" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod 755 "${TMP_ROOT}/no-sha-bin/which" || fail 'could not make empty PATH which fixture executable'
(
	PTXT() { printf '%s\n' "$*"; }
	ai_have_cmd() { return 1; }
	preflight_check_entware_package() {
		PTXT 'called.package=yes'
		return 1
	}
	. "${SHA256_FILE}"
	PATH="${TMP_ROOT}/no-sha-bin"
	SHA256SUM_OPT_BIN="${TMP_ROOT}/opt/bin/sha256sum"
	BUSYBOX_BIN="${TMP_ROOT}/missing-busybox"
	sha256sum_available || exit 1
	preflight_check_sha256_support 1 || exit 1
) >"${TMP_ROOT}/sha-opt.out" 2>&1 || fail 'functional /opt/bin/sha256sum must satisfy SHA-256 preflight when Entware is present'
if grep -q '^called.package=yes$' "${TMP_ROOT}/sha-opt.out"; then
	fail 'functional /opt/bin/sha256sum must not require coreutils-sha256sum'
fi
mkdir -p "${TMP_ROOT}/failing-bin"
cat >"${TMP_ROOT}/failing-bin/sha256sum" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod 755 "${TMP_ROOT}/failing-bin/sha256sum"
cat >"${TMP_ROOT}/failing-bin/which" <<EOF
#!/bin/sh
[ "\${1:-}" = sha256sum ] || exit 1
printf '%s\n' '${TMP_ROOT}/failing-bin/sha256sum'
EOF
chmod 755 "${TMP_ROOT}/failing-bin/which"
(
	PTXT() { printf '%s\n' "$*"; }
	ai_have_cmd() { [ "$1" = sha256sum ]; }
	preflight_check_entware_package() {
		PTXT 'called.package=yes'
		return 1
	}
	. "${SHA256_FILE}"
	PATH="${TMP_ROOT}/failing-bin"
	SHA256SUM_OPT_BIN="${TMP_ROOT}/missing-opt-sha256sum"
	BUSYBOX_BIN="${TMP_ROOT}/missing-busybox"
	if sha256sum_available; then
		exit 1
	fi
	if preflight_check_sha256_support 1; then
		exit 1
	fi
) >"${TMP_ROOT}/sha-failing.out" 2>&1 || fail 'present but failing sha256sum must be reported missing'
grep -q '^preflight.sha256.result=MISSING$' "${TMP_ROOT}/sha-failing.out" || fail 'failing sha256sum did not report MISSING'
grep -q '^called.package=yes$' "${TMP_ROOT}/sha-failing.out" || fail 'missing SHA-256 support with Entware must run the package diagnostic'

(
	PTXT() { printf '%s\n' "$*"; }
	ai_have_cmd() { [ "$1" = sha256sum ]; }
	preflight_check_entware_package() {
		PTXT 'called.package=yes'
		return 1
	}
	. "${SHA256_FILE}"
	PATH="${TMP_ROOT}/failing-bin"
	SHA256SUM_OPT_BIN="${TMP_ROOT}/missing-opt-sha256sum"
	BUSYBOX_BIN="${TMP_ROOT}/missing-busybox"
	if preflight_check_sha256_support 0; then
		exit 1
	fi
) >"${TMP_ROOT}/sha-no-entware.out" 2>&1 || fail 'missing SHA-256 support without Entware must fail preflight'
grep -q '^preflight.entware.package.coreutils-sha256sum.required=not_checked$' "${TMP_ROOT}/sha-no-entware.out" ||
	fail 'missing SHA-256 support without Entware must skip the package diagnostic'
if grep -q '^called.package=yes$' "${TMP_ROOT}/sha-no-entware.out"; then
	fail 'missing SHA-256 support without Entware ran the package diagnostic'
fi

# run_preflight_firewall_mode_case verifies flow-aware firewall gating and mode-detection snapshot reuse for a preflight action.
# run_preflight_firewall_mode_case verifies firewall-tool gating, install-mode detection reuse, and the expected preflight result for an action.
run_preflight_firewall_mode_case() {
	case_name="$1"
	action="$2"
	conf_mode="$3"
	detected_mode="$4"
	expected_firewall="$5"
	expected_result="${6:-success}"
	out_file="${TMP_ROOT}/firewall-${case_name}.out"
	stub_file="${TMP_ROOT}/firewall-${case_name}.stub"
	cat >"${stub_file}" <<EOF
PTXT() { printf '%s\n' "\$*"; }
AI_VERSION=TEST
PATH=/bin:/sbin:/usr/bin:/usr/sbin
conf_value() {
	case '${conf_mode}' in
		missing) return 1 ;;
		*) printf '%s\n' '${conf_mode}' ;;
	esac
}
adguard_install_mode_detect() {
	case '${detected_mode}' in
		missing) ADGUARD_INSTALL_MODE_DETECTION=unknown ;;
		*) ADGUARD_INSTALL_MODE_DETECTION='${detected_mode}'; ADGUARD_INSTALL_MODE='${detected_mode}' ;;
	esac
}
. "${FUNCTIONS_FILE}"
adguard_install_mode_detect() {
	detection_count="\$((\${detection_count:-0} + 1))"
	case '${detected_mode}' in
		missing) ADGUARD_INSTALL_MODE_DETECTION=unknown ;;
		*) ADGUARD_INSTALL_MODE_DETECTION='${detected_mode}'; ADGUARD_INSTALL_MODE='${detected_mode}' ;;
	esac
}
adguard_install_mode_confirmed() {
	case "\${ADGUARD_INSTALL_MODE_DETECTION:-unknown}" in wan | lan) return 0 ;; *) return 1 ;; esac
}
preflight_action_requires_downloader() { return 1; }
preflight_action_requires_service_tools() { return 1; }
preflight_action_requires_cru() { return 1; }
preflight_action_requires_jffs_ready() { return 1; }
preflight_action_requires_entware() { return 1; }
preflight_action_requires_jq() { return 1; }
preflight_action_requires_sha256() { return 1; }
preflight_action_requires_password_hash() { return 1; }
preflight_action_requires_timezone_column() { return 1; }
preflight_check_path() {
	case "\$1" in
		iptables | ip6tables) PTXT "called.\$1=yes" ;;
	esac
	return 0
}
preflight_check_stock_commands() { return 0; }
preflight_check_router_eligibility() {
	[ "\${PREFLIGHT_INSTALL_MODE_DETECTED:-0}" = "1" ] || return 1
	[ "\${detection_count:-0}" -eq 1 ] || return 1
	adguard_install_mode_confirmed
}
. "${PREFLIGHT_FILE}"
if preflight '${action}'; then
	PTXT 'called.preflight_result=success'
else
	PTXT 'called.preflight_result=failure'
fi
PTXT "called.mode_detection_count=\${detection_count:-0}"
EOF
	sh "${stub_file}" >"${out_file}" 2>&1 || true
	case "${expected_firewall}" in
		required)
			grep -q '^called.iptables=yes$' "${out_file}" || fail "${case_name}: expected iptables check"
			grep -q '^called.ip6tables=yes$' "${out_file}" || fail "${case_name}: expected ip6tables check"
			;;
		skipped)
			grep -q '^preflight.iptables.required=no$' "${out_file}" || fail "${case_name}: missing iptables skip required line"
			grep -q '^preflight.iptables.result=SKIP$' "${out_file}" || fail "${case_name}: missing iptables skip result line"
			grep -q '^preflight.ip6tables.required=no$' "${out_file}" || fail "${case_name}: missing ip6tables skip required line"
			grep -q '^preflight.ip6tables.result=SKIP$' "${out_file}" || fail "${case_name}: missing ip6tables skip result line"
			if grep -q '^called\.ip6\{0,1\}tables=yes$' "${out_file}"; then
				fail "${case_name}: firewall tool check ran for LAN mode"
			fi
			;;
	esac
	grep -q '^called.mode_detection_count=1$' "${out_file}" ||
		fail "${case_name}: preflight did not reuse one mode-detection snapshot"
	grep -q "^called.preflight_result=${expected_result}$" "${out_file}" ||
		fail "${case_name}: unexpected preflight result"
}

for action in install update restore; do
	run_preflight_firewall_mode_case "persisted-wan-detected-lan-${action}" "${action}" wan lan skipped
	run_preflight_firewall_mode_case "persisted-lan-detected-wan-${action}" "${action}" lan wan required
	run_preflight_firewall_mode_case "detected-wan-${action}" "${action}" missing wan required
	run_preflight_firewall_mode_case "detected-lan-${action}" "${action}" missing lan skipped
	run_preflight_firewall_mode_case "detected-unknown-${action}" "${action}" missing missing skipped failure
done
run_preflight_firewall_mode_case "detected-unknown-uninstall" uninstall missing missing skipped success

# run_router_mode_case tests router eligibility for a router mode and LAN IP address, verifying the status and expected output lines.
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
	'preflight.router.mode.result=OK'
run_router_mode_case lan-invalid-ip 2 999.168.50.1 1 \
	'preflight.router.mode=unknown' \
	'preflight.router.mode.result=FAIL' \
	'preflight.router.mode.reason=unknown-or-unreadable-router-mode'
run_router_mode_case lan-wildcard-ip 2 0.0.0.0 1 \
	'preflight.router.mode=unknown' \
	'preflight.router.mode.result=FAIL' \
	'preflight.router.mode.reason=unknown-or-unreadable-router-mode'
run_router_mode_case missing-loopback-ip '' 127.0.0.1 1 \
	'preflight.router.mode=unknown' \
	'preflight.router.mode.result=FAIL' \
	'preflight.router.mode.reason=unknown-or-unreadable-router-mode'
run_router_mode_case missing-lan-ip '' 192.168.50.1 1 \
	'preflight.router.mode=unknown' \
	'preflight.router.mode.result=FAIL' \
	'preflight.router.mode.reason=unknown-or-unreadable-router-mode'
run_router_mode_case missing-no-lan-ip '' '' 1 \
	'preflight.router.mode=unknown' \
	'preflight.router.mode.result=FAIL' \
	'preflight.router.mode.reason=unknown-or-unreadable-router-mode'
run_router_mode_case lan-no-lan-ip 2 '' 1 \
	'preflight.router.mode=unknown' \
	'preflight.router.mode.result=FAIL' \
	'preflight.router.mode.reason=unknown-or-unreadable-router-mode'

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	# conf_value returns a failure status without producing a configuration value.
	conf_value() { return 1; }
	# adguard_install_mode_detect determines the detected AdGuard installation mode and returns a failure status when detection is unavailable.
	adguard_install_mode_detect() { return 1; }

	# assert_entware_required verifies that each specified action requires Entware.
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

	# assert_jq_required verifies that each specified action requires jq.
	assert_jq_required() {
		local action
		for action in "$@"; do
			if ! preflight_action_requires_jq "${action}"; then
				printf '%s\n' "expected jq requirement for action: ${action}" >&2
				exit 1
			fi
		done
	}

	# assert_jq_skipped verifies that the specified actions do not require jq.
	assert_jq_skipped() {
		local action
		for action in "$@"; do
			if preflight_action_requires_jq "${action}"; then
				printf '%s\n' "unexpected jq requirement for action: ${action}" >&2
				exit 1
			fi
		done
	}

	# assert_sha256_required verifies that each specified action requires SHA-256 support.
	assert_sha256_required() {
		local action
		for action in "$@"; do
			if ! preflight_action_requires_sha256 "${action}"; then
				printf '%s\n' "expected SHA-256 requirement for action: ${action}" >&2
				exit 1
			fi
		done
	}

	# assert_sha256_optional verifies that each specified action can proceed without SHA-256 support, exiting with an error if an action requires it.
	assert_sha256_optional() {
		local action
		for action in "$@"; do
			if preflight_action_requires_sha256 "${action}"; then
				printf '%s\n' "unexpected SHA-256 requirement for MD5-fallback action: ${action}" >&2
				exit 1
			fi
		done
	}

	# assert_password_hash_required verifies that each specified action requires password hashing support.
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

	# assert_router_eligibility_skipped verifies that router eligibility is not required for the specified actions.
	assert_router_eligibility_skipped() {
		local action
		for action in "$@"; do
			if preflight_action_requires_router_eligibility "${action}"; then
				printf '%s\n' "unexpected router eligibility requirement for action: ${action}" >&2
				exit 1
			fi
		done
	}

	# assert_firewall_required verifies that firewall tools are required for each specified preflight action.
	assert_firewall_required() {
		local action
		for action in "$@"; do
			if ! preflight_action_requires_firewall_tools "${action}"; then
				printf '%s\n' "expected firewall tools requirement for action: ${action}" >&2
				exit 1
			fi
		done
	}

	# assert_firewall_skipped verifies that firewall tools are not required for the specified actions.
	assert_firewall_skipped() {
		local action
		for action in "$@"; do
			if preflight_action_requires_firewall_tools "${action}"; then
				printf '%s\n' "unexpected firewall tools requirement for action: ${action}" >&2
				exit 1
			fi
		done
	}

	# conf_value outputs the configured mode and fails when no mode is configured.
	conf_value() {
		case "${CONF_MODE:-missing}" in
			missing) return 1 ;;
			*) printf '%s\n' "${CONF_MODE}" ;;
		esac
	}
	# adguard_install_mode_detect records the detected installation mode, or marks the mode as unknown when detection provides no value.
	adguard_install_mode_detect() {
		case "${DETECTED_MODE:-missing}" in
			missing) ADGUARD_INSTALL_MODE_DETECTION=unknown ;;
			*)
				ADGUARD_INSTALL_MODE_DETECTION="${DETECTED_MODE}"
				ADGUARD_INSTALL_MODE="${DETECTED_MODE}"
				;;
		esac
	}
	CONF_MODE=wan DETECTED_MODE=lan assert_firewall_skipped install update restore
	CONF_MODE=lan DETECTED_MODE=wan assert_firewall_required install update restore
	CONF_MODE=missing DETECTED_MODE=lan assert_firewall_skipped install update restore
	CONF_MODE=missing DETECTED_MODE=wan assert_firewall_required install update restore

	# assert_base_tools_required verifies that each specified action requires downloader, service, CRU, and firewall tools.
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

	# assert_base_tools_skipped verifies that the specified actions do not require base tools.
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

	# assert_timezone_column_required verifies that each specified action requires timezone column support.
	assert_timezone_column_required() {
		local action
		for action in "$@"; do
			if ! preflight_action_requires_timezone_column "${action}"; then
				printf '%s\n' "expected timezone column requirement for action: ${action}" >&2
				exit 1
			fi
		done
	}

	DETECTED_MODE=wan
	assert_base_tools_required '' install update reconfigure restore uninstall ipset backup doctor netcheck dns-port-policy performance migrate-runtime-defaults
	assert_base_tools_skipped status preflight
	assert_entware_required '' install update reconfigure restore uninstall ipset backup doctor netcheck dns-port-policy performance migrate-runtime-defaults
	assert_jffs_ready_required '' install reconfigure 4
	assert_jffs_ready_skipped update restore uninstall ipset backup doctor netcheck dns-port-policy performance migrate-runtime-defaults status preflight
	assert_router_eligibility_required '' install update reconfigure restore ipset backup doctor netcheck dns-port-policy performance migrate-runtime-defaults
	assert_router_eligibility_skipped uninstall status preflight
	assert_entware_skipped status preflight
	assert_jq_required '' install update reconfigure restore 1 4 r R
	assert_jq_skipped uninstall ipset backup doctor status preflight netcheck dns-port-policy performance migrate-runtime-defaults
	assert_sha256_required '' install update restore switchbranch 1 7 r R blocklists unusedblocklists 9
	assert_sha256_optional uninstall reconfigure changepw ipset backup doctor status preflight netcheck dns-port-policy performance migrate-runtime-defaults
	assert_password_hash_required '' install reconfigure changepw 3 4
	assert_timezone_column_required '' install reconfigure restore 4
) || fail 'preflight action helper returned an unexpected result'

printf '%s\n' 'PASS: preflight action routing keeps Entware and jq checks flow-aware'
