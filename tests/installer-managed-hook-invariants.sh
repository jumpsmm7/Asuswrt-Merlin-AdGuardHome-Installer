#!/bin/sh
# Exercise real hook writers, aggregate rollback, and topology-aware doctor checks.

set -u

SCRIPT_PATH="${1:-installer}"
TEST_CASE="${2:-all}"
TEST_ROOT="${TMPDIR:-/tmp}/installer-managed-hook-invariants.$$"
FUNCTIONS_FILE="${TEST_ROOT}/functions"

# fail reports the invariant that failed and stops the fixture.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

# cleanup removes only the isolated fixture directory.
cleanup() {
	rm -rf "${TEST_ROOT}"
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
mkdir -p "${TEST_ROOT}/jffs/scripts" "${TEST_ROOT}/base" "${TEST_ROOT}/addons" || fail 'fixture creation failed'
awk '
	/^(_quote|PTXT|installer_cleanup_tmp_file|del_between_magic|del_jffs_script|write_command_script|write_manager_script|event_scripts_snapshot|event_scripts_restore|all_event_scripts_snapshot|all_event_scripts_restore|event_scripts_recovery_marker_write|all_event_scripts_transaction_begin|all_event_scripts_transaction_rollback|doctor_status|doctor_fix_msg|doctor_managed_script_state|doctor_check_managed_hooks|service_event_hook_command|managed_hook_[a-z_]+|write_managed_hook)\(\) \{/ { copying = 1 }
	copying { print }
	copying && /^}/ { copying = 0 }
' "${SCRIPT_PATH}" >"${FUNCTIONS_FILE}.raw" || fail 'helper extraction failed'
sed "s|/jffs/scripts|${TEST_ROOT}/jffs/scripts|g; s|/jffs/addons/AdGuardHome.d|${TEST_ROOT}/addons|g" "${FUNCTIONS_FILE}.raw" >"${FUNCTIONS_FILE}" || fail 'helper isolation failed'
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

INFO=INFO
ERROR=ERROR
WARNING=WARNING
BASE_DIR="${TEST_ROOT}/base"
ADDON_DIR="${TEST_ROOT}/addons"
CONF_FILE="${TEST_ROOT}/config"
YAML_FILE="${TEST_ROOT}/yaml"
YAML_ORI="${TEST_ROOT}/yaml-original"
printf '%s\n' '#!/bin/sh' >"${ADDON_DIR}/AdGuardHome.sh"
printf '%s\n' 'original config' >"${CONF_FILE}"
printf '%s\n' 'original yaml' >"${YAML_FILE}"
printf '%s\n' 'original yaml source' >"${YAML_ORI}"
EXPECTED_LINE="[ -x ${ADDON_DIR}/AdGuardHome.sh ] && ${ADDON_DIR}/AdGuardHome.sh dnsmasq pre_start"

# assert_hook checks the firmware-dispatched script after the real writer returns.
assert_hook() {
	[ "$(sed -n '1p' "$1")" = "$2" ] || fail "$3: first-line interpreter was not preserved or repaired"
	[ "$(ls -ld "$1" | awk '{ print $1 }')" = '-rwxr-xr-x' ] || fail "$3: final mode is not 0755"
	[ "$(grep -c -x -F "${EXPECTED_LINE}" "$1")" -eq 1 ] || fail "$3: managed invocation is missing or duplicated"
	sh -n "$1" || fail "$3: generated script does not parse"
}

if [ "${TEST_CASE}" != doctor ]; then
	for test_umask in 077 022; do
		(
			umask "${test_umask}"
			for fixture in legacy absent empty broken shared duplicate quoted indented; do
				TARGET="${TEST_ROOT}/jffs/scripts/dnsmasq.postconf"
				rm -f "${TARGET}"
				HEADER='#!/bin/sh'
				case "${fixture}" in
					legacy) printf '%s\n' '#!/bin/sh' "[ -x ${ADDON_DIR}/legacy ] && ${ADDON_DIR}/legacy dnsmasq" >"${TARGET}" ;;
					empty) : >"${TARGET}" ;;
					broken)
						printf '\n%s\n' "${EXPECTED_LINE}" >"${TARGET}"
						chmod 600 "${TARGET}"
						;;
					shared)
						HEADER='#!/bin/sh -e'
						printf '%s\n' "${HEADER}" 'echo unrelated-user-command' "[ -x ${ADDON_DIR}/legacy ] && legacy" >"${TARGET}"
						;;
					duplicate) printf '%s\n' '#!/bin/sh' "${EXPECTED_LINE}" "${EXPECTED_LINE}" "${ADDON_DIR}/AdGuardHome.sh dnsmasq pre_start" >"${TARGET}" ;;
					quoted)
						printf '%s\n' '#!/bin/sh' "${EXPECTED_LINE}" "echo '[ -x ${ADDON_DIR}/legacy ]'" "# [ -x ${ADDON_DIR}/legacy ] && legacy" >"${TARGET}"
						;;
					indented)
						printf '%s\n' '#!/bin/sh' "  ${EXPECTED_LINE}" "  ${EXPECTED_LINE} # !manager" >"${TARGET}"
						printf '\t%s\n' "${ADDON_DIR}/AdGuardHome.sh dnsmasq pre_start" >>"${TARGET}"
						printf '%s\n' 'echo unrelated-user-command' "echo '${EXPECTED_LINE}'" "# ${EXPECTED_LINE}" >>"${TARGET}"
						;;
					absent) : ;;
				esac
				write_manager_script "${TARGET}" 'dnsmasq pre_start' >"${TEST_ROOT}/writer-output" 2>&1 || fail "${fixture}: writer failed"
				assert_hook "${TARGET}" "${HEADER}" "${fixture} umask ${test_umask}"
				[ "${fixture}" != shared ] || grep -qx 'echo unrelated-user-command' "${TARGET}" || fail 'shared user command was removed'
				if [ "${fixture}" = quoted ]; then
					grep -qx -F "echo '[ -x ${ADDON_DIR}/legacy ]'" "${TARGET}" || fail 'writer removed a user command containing a quoted legacy-hook string'
					grep -qx -F "# [ -x ${ADDON_DIR}/legacy ] && legacy" "${TARGET}" || fail 'writer removed a user comment containing a legacy-hook string'
				fi
				if [ "${fixture}" = indented ]; then
					grep -qx 'echo unrelated-user-command' "${TARGET}" || fail 'writer removed unrelated content beside indented owned hooks'
					grep -qx -F "echo '${EXPECTED_LINE}'" "${TARGET}" || fail 'writer removed a quoted indented-hook lookalike'
					grep -qx -F "# ${EXPECTED_LINE}" "${TARGET}" || fail 'writer removed a commented indented-hook lookalike'
				fi
				cp "${TARGET}" "${TEST_ROOT}/first-pass"
				write_manager_script "${TARGET}" 'dnsmasq pre_start' >/dev/null 2>&1 || fail 'repeated writer failed'
				cmp -s "${TARGET}" "${TEST_ROOT}/first-pass" || fail "${fixture}: repeated repair changed content"
				assert_hook "${TARGET}" "${HEADER}" "${fixture} repeated repair"
			done
		) || exit 1
	done

	for injected_failure in cleanup append chmod publish; do
		(
			TARGET="${TEST_ROOT}/jffs/scripts/dnsmasq.postconf"
			printf '%s\n' '#!/bin/sh' "[ -x ${ADDON_DIR}/legacy ] && legacy" 'echo original-user-command' >"${TARGET}"
			chmod 640 "${TARGET}"
			cp -p "${TARGET}" "${TEST_ROOT}/original"
			EVENT_SCRIPTS_ACTIVE_SNAPSHOT=''
			SNAPSHOT="${BASE_DIR}/.AdGuardHome.event-hooks.${injected_failure}"
			all_event_scripts_transaction_begin "${SNAPSHOT}" || fail 'aggregate snapshot failed'
			# PTXT injects failure when appending the actual managed invocation.
			PTXT() {
				[ "${injected_failure}" != append ] || [ "$*" != "${EXPECTED_LINE}" ] || return 1
				printf '%s\n' "$@"
			}
			# sed injects a legacy-cleanup edit failure.
			sed() {
				[ "${injected_failure}" != cleanup ] || [ "$1" != -i ] || return 1
				command sed "$@"
			}
			# chmod rejects the final hook mode while allowing unrelated snapshot work.
			chmod() {
				[ "${injected_failure}" != chmod ] || [ "$*" != "755 ${TARGET}.agh.$$" ] || return 1
				command chmod "$@"
			}
			# mv rejects only hook publication, leaving rollback publication usable.
			mv() {
				case "$*" in
					*".agh.$$ ${TARGET}") [ "${injected_failure}" != publish ] || return 1 ;;
				esac
				command mv "$@"
			}
			if write_manager_script "${TARGET}" 'dnsmasq pre_start' >/dev/null 2>&1; then
				fail "${injected_failure}: real writer hid the injected failure"
			fi
			all_event_scripts_transaction_rollback || fail "${injected_failure}: aggregate rollback failed"
			cmp -s "${TARGET}" "${TEST_ROOT}/original" || fail "${injected_failure}: rollback changed original content"
			[ "$(ls -ld "${TARGET}" | awk '{ print $1 }')" = '-rw-r-----' ] || fail "${injected_failure}: rollback lost original mode"
		) || exit 1
	done
	for unsafe_type in fifo directory symlink; do
		TARGET="${TEST_ROOT}/jffs/scripts/dnsmasq.postconf"
		rm -f "${TARGET}"
		case "${unsafe_type}" in
			fifo) mkfifo "${TARGET}" ;;
			directory) mkdir "${TARGET}" ;;
			symlink) ln -s "${TEST_ROOT}/missing-target" "${TARGET}" ;;
		esac
		SNAPSHOT="${BASE_DIR}/unsafe-${unsafe_type}"
		if event_scripts_snapshot "${SNAPSHOT}" "${TARGET}"; then
			fail "snapshot accepted ${unsafe_type} as an absent hook"
		fi
		[ ! -e "${SNAPSHOT}" ] || fail 'unsafe hook left a recovery snapshot'
		if write_manager_script "${TARGET}" 'dnsmasq pre_start'; then
			fail "writer accepted ${unsafe_type} hook target"
		fi
		case "${unsafe_type}" in
			fifo)
				[ -p "${TARGET}" ] || fail 'FIFO hook was removed'
				rm -f "${TARGET}"
				;;
			directory)
				[ -d "${TARGET}" ] || fail 'directory hook was removed'
				rmdir "${TARGET}"
				;;
			symlink)
				[ -L "${TARGET}" ] || fail 'symlink hook was removed'
				rm -f "${TARGET}"
				;;
		esac
	done
	# Simulate interruption after stage creation and exercise the registered outer cleanup helper.
	MANAGED_HOOK_TMP_FILE="${TEST_ROOT}/jffs/scripts/init-start.agh.$$"
	: >"${MANAGED_HOOK_TMP_FILE}"
	: >"${MANAGED_HOOK_TMP_FILE}.content"
	: >"${TEST_ROOT}/jffs/scripts/user-file"
	YAML_ORI="${TEST_ROOT}/yaml-original"
	installer_cleanup_tmp_file managed-hook "${TEST_ROOT}/jffs/scripts/user-file"
	installer_cleanup_tmp_file managed-hook "${MANAGED_HOOK_TMP_FILE}"
	installer_cleanup_tmp_file managed-hook "${MANAGED_HOOK_TMP_FILE}.content"
	[ ! -e "${MANAGED_HOOK_TMP_FILE}" ] && [ ! -e "${MANAGED_HOOK_TMP_FILE}.content" ] || fail 'interrupted hook staging survived registered cleanup'
	[ -f "${TEST_ROOT}/jffs/scripts/user-file" ] || fail 'hook cleanup removed unrelated content'
fi

if [ "${TEST_CASE}" != writer ]; then
	TARGET="${TEST_ROOT}/jffs/scripts/dnsmasq.postconf"
	for fixture in shebangless nonexecutable missing duplicate substring invalidinterpreter; do
		case "${fixture}" in
			shebangless) printf '%s\n' "${EXPECTED_LINE}" >"${TARGET}" ;;
			nonexecutable) printf '%s\n' '#!/bin/sh' "${EXPECTED_LINE}" >"${TARGET}" ;;
			missing) printf '%s\n' '#!/bin/sh' 'echo user-command' >"${TARGET}" ;;
			duplicate) printf '%s\n' '#!/bin/sh' "${EXPECTED_LINE}" "${EXPECTED_LINE}" >"${TARGET}" ;;
			substring) printf '%s\n' '#!/bin/sh' "# ${EXPECTED_LINE}" >"${TARGET}" ;;
			invalidinterpreter) printf '%s\n' '#!/missing/interpreter' "${EXPECTED_LINE}" >"${TARGET}" ;;
		esac
		chmod 755 "${TARGET}"
		[ "${fixture}" != nonexecutable ] || chmod 600 "${TARGET}"
		cp -p "${TARGET}" "${TEST_ROOT}/before-doctor"
		DOCTOR_FAILED=0
		if doctor_managed_script_state "${TARGET}" 'dnsmasq pre_start' >"${TEST_ROOT}/doctor-output"; then
			fail "doctor falsely accepts ${fixture} managed hook"
		fi
		grep -q '^\[OK\]' "${TEST_ROOT}/doctor-output" && fail "doctor reports ${fixture} as healthy"
		cmp -s "${TARGET}" "${TEST_ROOT}/before-doctor" || fail 'read-only doctor edited hook content'
	done
	type doctor_check_managed_hooks >/dev/null 2>&1 || fail 'topology-aware doctor hook helper missing'
	DNS_MODE=enabled
	INSTALL_MODE=lan
	SDN_SUPPORT=mtlancfg
	NAT_ENABLED=0
	# conf_value supplies persisted topology without touching router configuration.
	conf_value() {
		case "$1" in
			ADGUARD_DNSMASQ_MODE) printf '%s\n' "${DNS_MODE}" ;;
			ADGUARD_INSTALL_MODE) printf '%s\n' "${INSTALL_MODE}" ;;
			*) return 1 ;;
		esac
	}
	# nvram permits only read-only capability inspection.
	nvram() {
		[ "$*" = 'get rc_support' ] || fail "unexpected nvram call: $*"
		printf '%s\n' "${SDN_SUPPORT}"
	}
	# adguard_ipset_allowed supplies the shared topology predicate without firewall writes.
	adguard_ipset_allowed() { [ "${INSTALL_MODE}" = wan ] || [ "${NAT_ENABLED}" -eq 1 ]; }
	for fixture in init-start services-stop dnsmasq.postconf dnsmasq-sdn.postconf service-event-end; do
		case "${fixture}" in
			init-start) LINE="[ -x ${ADDON_DIR}/AdGuardHome.sh ] && ${ADDON_DIR}/AdGuardHome.sh init-start &" ;;
			services-stop) LINE="[ -x ${ADDON_DIR}/AdGuardHome.sh ] && ${ADDON_DIR}/AdGuardHome.sh services-stop &" ;;
			dnsmasq.postconf) LINE="${EXPECTED_LINE}" ;;
			dnsmasq-sdn.postconf) LINE="[ -x ${ADDON_DIR}/AdGuardHome.sh ] && ${ADDON_DIR}/AdGuardHome.sh dnsmasq-sdn \$2" ;;
			service-event-end) LINE="$(service_event_hook_command)" ;;
		esac
		printf '\n%s\n%s\n' 'echo unrelated-user-command' "${LINE}" >"${TEST_ROOT}/jffs/scripts/${fixture}"
		chmod 600 "${TEST_ROOT}/jffs/scripts/${fixture}"
	done
	DOCTOR_FAILED=0
	doctor_check_managed_hooks 1 >"${TEST_ROOT}/doctor-fix-output" || fail 'recognized hook repair failed'
	[ "${DOCTOR_FAILED}" -eq 0 ] || fail 'successful repair reported failure'
	for fixture in init-start services-stop dnsmasq.postconf dnsmasq-sdn.postconf service-event-end; do
		[ "$(sed -n '1p' "${TEST_ROOT}/jffs/scripts/${fixture}")" = '#!/bin/sh' ] || fail "doctor did not repair ${fixture} header"
		[ -x "${TEST_ROOT}/jffs/scripts/${fixture}" ] || fail "doctor did not repair ${fixture} mode"
		grep -qx 'echo unrelated-user-command' "${TEST_ROOT}/jffs/scripts/${fixture}" || fail "doctor discarded ${fixture} user content"
	done
	grep -q 'service-event-end managed hook present' "${TEST_ROOT}/doctor-fix-output" || fail 'doctor skipped command-format service event hook'
	grep -q 'dnsmasq-sdn.postconf managed hook present' "${TEST_ROOT}/doctor-fix-output" || fail 'doctor skipped enabled supported SDN hook'
	grep -q 'firewall-start.*missing' "${TEST_ROOT}/doctor-fix-output" && fail 'doctor required intentionally absent LAN firewall hook'
	for DNS_MODE in auto ''; do
		printf '%s\n' "${EXPECTED_LINE}" >"${TARGET}"
		chmod 600 "${TARGET}"
		doctor_check_managed_hooks 0 >"${TEST_ROOT}/doctor-auto-output" || true
		grep -q 'dnsmasq.postconf managed hook has an invalid' "${TEST_ROOT}/doctor-auto-output" || fail 'doctor omitted an existing auto/legacy DNS hook'
		doctor_check_managed_hooks 1 >"${TEST_ROOT}/doctor-auto-fix-output" || fail 'doctor auto/legacy hook repair failed'
		assert_hook "${TARGET}" '#!/bin/sh' 'doctor auto/legacy repair'
		rm -f "${TARGET}" "${TEST_ROOT}/jffs/scripts/dnsmasq-sdn.postconf"
		doctor_check_managed_hooks 1 >"${TEST_ROOT}/doctor-auto-absent-output" || true
		grep -q 'dnsmasq.*managed hook missing' "${TEST_ROOT}/doctor-auto-absent-output" && fail 'doctor required absent auto/legacy DNS hook'
		[ ! -e "${TARGET}" ] || fail 'doctor recreated absent auto/legacy DNS hook'
	done
	printf '%s\n' '#!/missing/interpreter' "${EXPECTED_LINE}" >"${TARGET}"
	chmod 600 "${TARGET}"
	cp -p "${TARGET}" "${TEST_ROOT}/before-doctor"
	DOCTOR_FAILED=0
	if doctor_managed_script_state "${TARGET}" 'dnsmasq pre_start' 1 >"${TEST_ROOT}/doctor-failure-output"; then
		fail 'doctor concealed refused invalid-interpreter repair'
	fi
	grep -q '^\[FAIL\].*managed hook repair failed' "${TEST_ROOT}/doctor-failure-output" || fail 'doctor omitted failed repair status'
	cmp -s "${TARGET}" "${TEST_ROOT}/before-doctor" || fail 'failed doctor repair changed original content'
	DNS_MODE=disabled
	SDN_SUPPORT=''
	rm -f "${TARGET}" "${TEST_ROOT}/jffs/scripts/dnsmasq-sdn.postconf"
	doctor_check_managed_hooks 1 >"${TEST_ROOT}/doctor-disabled-output" || fail 'disabled integration check failed'
	grep -q 'dnsmasq.*managed hook missing' "${TEST_ROOT}/doctor-disabled-output" && fail 'doctor required intentionally disabled dnsmasq hooks'
	[ ! -e "${TARGET}" ] && [ ! -e "${TEST_ROOT}/jffs/scripts/dnsmasq-sdn.postconf" ] || fail 'doctor recreated disabled hooks'
	DNS_MODE=enabled
	doctor_check_managed_hooks 0 >"${TEST_ROOT}/doctor-unsupported-output" || true
	grep -q 'dnsmasq-sdn.*managed hook missing' "${TEST_ROOT}/doctor-unsupported-output" && fail 'doctor required unsupported SDN hook'
	printf '%s\n' "${EXPECTED_LINE}" >"${TEST_ROOT}/foreign-hook"
	chmod 600 "${TEST_ROOT}/foreign-hook"
	ln -s "${TEST_ROOT}/foreign-hook" "${TARGET}" || fail 'symlink fixture failed'
	DOCTOR_FAILED=0
	doctor_check_managed_hooks 1 >"${TEST_ROOT}/doctor-symlink-output" || true
	grep -q '^\[FAIL\].*unsafe managed hook' "${TEST_ROOT}/doctor-symlink-output" || fail 'doctor did not reject hook symlink'
	[ "$(ls -ld "${TEST_ROOT}/foreign-hook" | awk '{ print $1 }')" = '-rw-------' ] || fail 'doctor changed symlink target mode'
	[ "$(sed -n '1p' "${TEST_ROOT}/foreign-hook")" = "${EXPECTED_LINE}" ] || fail 'doctor changed symlink target content'
fi

printf '%s\n' 'PASS: managed hook writer and doctor invariants'
