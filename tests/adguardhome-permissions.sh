#!/bin/sh
# Verify installer and init permission helpers cover config, binary, and IPSET files.

set -u

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP_DIR="${TMPDIR:-/tmp}/agh-permissions.$$"
INSTALLER_FUNCTIONS="${TMP_DIR}/installer-functions.sh"
S99_FUNCTIONS="${TMP_DIR}/s99-functions.sh"

cleanup() {
	rm -rf "${TMP_DIR}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

mode_string() {
	ls -ld "$1" | awk 'NR == 1 { print substr($1, 1, 10) }'
}

assert_mode() {
	_path="$1"
	_expected="$2"
	_actual="$(mode_string "${_path}")" || fail "could not read mode for ${_path}"
	[ "${_actual}" = "${_expected}" ] || fail "${_path} mode ${_actual}, expected ${_expected}"
}

extract_permission_functions() {
	_source_file="$1"
	_output_file="$2"
	_start="$3"
	_stop="$4"
	awk -v start="${_start}" -v stop="${_stop}" '
		$0 == start { copying = 1 }
		$0 == stop { copying = 0 }
		copying { print }
	' "${_source_file}" >"${_output_file}" || return 1
	[ -s "${_output_file}" ]
}

setup_tree() {
	_base_dir="$1"
	mkdir -p "${_base_dir}/custom" || return 1
	cat >"${_base_dir}/AdGuardHome" <<'EOS'
#!/bin/sh
printf '%s\n' "AdGuard Home, version test"
EOS
	cat >"${_base_dir}/AdGuardHome.yaml" <<'EOS'
dns:
  ipset_file: "custom/from-yaml.conf"
EOS
	printf '%s\n' 'managed rules' >"${_base_dir}/ipset.conf" || return 1
	printf '%s\n' 'user rules' >"${_base_dir}/ipset.user" || return 1
	printf '%s\n' 'yaml rules' >"${_base_dir}/custom/from-yaml.conf" || return 1
	printf '%s\n' 'symlink target' >"${_base_dir}/../symlink-target" || return 1
	ln -s "${_base_dir}/../symlink-target" "${_base_dir}/linked.conf" || return 1
	chmod 755 "${_base_dir}" "${_base_dir}/AdGuardHome.yaml" \
		"${_base_dir}/ipset.conf" "${_base_dir}/ipset.user" \
		"${_base_dir}/custom/from-yaml.conf" || return 1
	chmod 600 "${_base_dir}/AdGuardHome" || return 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

mkdir -p "${TMP_DIR}" || exit 1
extract_permission_functions "${REPO_DIR}/installer" "${INSTALLER_FUNCTIONS}" \
	'adguardhome_yaml_ipset_file() {' 'create_backup_archive() {' || fail 'could not extract installer permission helpers'
extract_permission_functions "${REPO_DIR}/S99AdGuardHome" "${S99_FUNCTIONS}" \
	'adguardhome_yaml_ipset_file() {' 'pre_start_adguardhome() {' || fail 'could not extract S99 permission helpers'

(
	# shellcheck disable=SC1090
	. "${INSTALLER_FUNCTIONS}"

	PTXT() { printf '%s\n' "$*" >/dev/null; }
	nvram() { [ "$1" = get ] && [ "$2" = http_username ] && printf '%s\n' root; }
	CHOWN_LOG="${TMP_DIR}/installer-chown.log"
	chown() { printf '%s\n' "$2" >>"${CHOWN_LOG}"; return 0; }

	BASE_DIR="${TMP_DIR}/installer"
	TARG_DIR="${BASE_DIR}/AdGuardHome"
	AGH_FILE="${TARG_DIR}/AdGuardHome"
	YAML_FILE="${AGH_FILE}.yaml"
	ERROR='Error:'
	mkdir -p "${TARG_DIR}" || exit 1
	setup_tree "${TARG_DIR}" || exit 1

	[ "$(adguardhome_yaml_ipset_file)" = 'custom/from-yaml.conf' ] || fail 'installer did not parse relative ipset_file from YAML'
	cat >"${YAML_FILE}" <<'EOS'
dns:
  'ipset_file': "custom/from-yaml.conf"
EOS
	[ "$(adguardhome_yaml_ipset_file)" = 'custom/from-yaml.conf' ] || fail 'installer did not parse quoted ipset_file key from YAML'
	ensure_adguardhome_directory_permissions >/dev/null || fail 'installer permission helper failed'
	grep -Fx "${TARG_DIR}/custom/from-yaml.conf" "${CHOWN_LOG}" >/dev/null || fail 'installer did not chown nested YAML IPSET file'
	assert_mode "${TARG_DIR}" 'drwxrwxrwx'
	assert_mode "${TARG_DIR}/custom" 'drwxrwxrwx'
	assert_mode "${YAML_FILE}" '-rw-r--r--'
	assert_mode "${TARG_DIR}/ipset.conf" '-rw-r--r--'
	assert_mode "${TARG_DIR}/ipset.user" '-rw-r--r--'
	assert_mode "${TARG_DIR}/custom/from-yaml.conf" '-rw-r--r--'
	assert_mode "${TARG_DIR}/linked.conf" 'lrwxrwxrwx'
	assert_mode "${AGH_FILE}" '-rwxr-xr-x'
) || exit 1

(
	# shellcheck disable=SC1090
	. "${S99_FUNCTIONS}"

	logger() { :; }
	nvram() { [ "$1" = get ] && [ "$2" = http_username ] && printf '%s\n' root; }
	CHOWN_LOG="${TMP_DIR}/s99-chown.log"
	chown() {
		[ -L "$2" ] && return 1
		printf '%s\n' "$2" >>"${CHOWN_LOG}"
		return 0
	}

	PROCS="AdGuardHome"
	WORK_DIR="${TMP_DIR}/s99/AdGuardHome"
	EXTERNAL_IPSET_FILE="${TMP_DIR}/external-ipset.conf"
	mkdir -p "${WORK_DIR}" || exit 1
	setup_tree "${WORK_DIR}" || exit 1
	printf '%s\n' 'external rules' >"${EXTERNAL_IPSET_FILE}" || exit 1
	chmod 644 "${EXTERNAL_IPSET_FILE}" || exit 1
	ln -s "${EXTERNAL_IPSET_FILE}" "${WORK_DIR}/external-link" || exit 1

	[ "$(adguardhome_yaml_ipset_file)" = 'custom/from-yaml.conf' ] || fail 'S99 did not parse relative ipset_file from YAML'
	cat >"${WORK_DIR}/AdGuardHome.yaml" <<'EOS'
dns:
  "ipset_file": 'custom/from-yaml.conf'
EOS
	[ "$(adguardhome_yaml_ipset_file)" = 'custom/from-yaml.conf' ] || fail 'S99 did not parse quoted ipset_file key from YAML'
	ensure_adguardhome_work_dir_permissions >/dev/null || fail 'S99 permission helper failed'
	grep -Fx "${WORK_DIR}/custom/from-yaml.conf" "${CHOWN_LOG}" >/dev/null || fail 'S99 did not chown nested YAML IPSET file'
	assert_mode "${WORK_DIR}" 'drwxrwxrwx'
	assert_mode "${WORK_DIR}/custom" 'drwxrwxrwx'
	assert_mode "${WORK_DIR}/AdGuardHome.yaml" '-rw-r--r--'
	assert_mode "${WORK_DIR}/ipset.conf" '-rw-r--r--'
	assert_mode "${WORK_DIR}/ipset.user" '-rw-r--r--'
	assert_mode "${WORK_DIR}/custom/from-yaml.conf" '-rw-r--r--'
	assert_mode "${WORK_DIR}/linked.conf" 'lrwxrwxrwx'
	assert_mode "${WORK_DIR}/AdGuardHome" '-rwxr-xr-x'
	assert_mode "${EXTERNAL_IPSET_FILE}" '-rw-r--r--'
	cat >"${WORK_DIR}/AdGuardHome.yaml" <<EOS
dns:
  ipset_file: "${EXTERNAL_IPSET_FILE}"
EOS
	chmod 644 "${WORK_DIR}/AdGuardHome.yaml" "${EXTERNAL_IPSET_FILE}" || exit 1
	[ "$(adguardhome_yaml_ipset_file)" = "${EXTERNAL_IPSET_FILE}" ] || fail 'S99 did not parse absolute ipset_file from YAML'
	ensure_adguardhome_work_dir_permissions >/dev/null || fail 'S99 permission helper failed with external IPSET file'
	assert_mode "${EXTERNAL_IPSET_FILE}" '-rw-r--r--'

	printf '%s\n' 'parent rules' >"${TMP_DIR}/s99/external-ipset.conf" || exit 1
	chmod 644 "${TMP_DIR}/s99/external-ipset.conf" || exit 1
	cat >"${WORK_DIR}/AdGuardHome.yaml" <<'EOS'
dns:
  ipset_file: ../external-ipset.conf
EOS
	ensure_adguardhome_work_dir_permissions >/dev/null || fail 'S99 permission helper failed with parent-relative IPSET file'
	assert_mode "${TMP_DIR}/s99/external-ipset.conf" '-rw-r--r--'

	cat >"${WORK_DIR}/AdGuardHome.yaml" <<EOS
dns:
  ipset_file: "${WORK_DIR}/../external-ipset.conf"
EOS
	ensure_adguardhome_work_dir_permissions >/dev/null || fail 'S99 permission helper failed with parent-traversing absolute IPSET file'
	assert_mode "${TMP_DIR}/s99/external-ipset.conf" '-rw-r--r--'
) || exit 1

awk '
	/^check_AdGuardHome_yaml\(\) \{$/ { in_check = 1; next }
	in_check && /^}$/ { in_check = 0 }
	in_check && /chmod 644 "\$\{YAML_FILE\}"/ { yaml_chmod++ }
	/^install_adguard_archive\(\) \{$/ { in_install = 1; next }
	in_install && /^}$/ { in_install = 0 }
	in_install && /ensure_adguardhome_directory_permissions \|\|/ { install_call++ }
	/^backup_restore\(\) \{$/ { in_restore = 1; next }
	in_restore && /^}$/ { in_restore = 0 }
	in_restore && /ensure_adguardhome_directory_permissions/ { restore_call++ }
	/^create_dir\(\) \{$/ { in_create_dir = 1; next }
	in_create_dir && /^}$/ { in_create_dir = 0 }
	in_create_dir && /mkdir -p "\$\{1\}"/ { create_mkdir++ }
	in_create_dir && /chmod 777 "\$\{1\}"/ { create_chmod++ }
	/if ! create_dir "\$\{TARG_DIR\}" \|\| ! ensure_adguardhome_directory_permissions; then/ { create_call++ }
	END { exit(yaml_chmod == 1 && install_call == 1 && restore_call >= 1 && create_call == 1 && create_mkdir == 1 && create_chmod == 1 ? 0 : 1) }
' "${REPO_DIR}/installer" || fail 'installer permission helper is not wired into all expected install, restore, and config paths'

awk '
	/^pre_start_adguardhome\(\) \{$/ { in_pre = 1; next }
	in_pre && /^}$/ { in_pre = 0 }
	in_pre && /ensure_adguardhome_work_dir_permissions \|\| return 1/ { pre_call++ }
	/^case "\$\{1:-\}" in$/ { in_case = 1; next }
	in_case && /"start" \| "restart" \| "reload"\)/ { action_case++ }
	in_case && /ensure_adguardhome_work_dir_permissions \|\| exit 1/ { action_call++ }
	in_case && /^esac$/ { in_case = 0 }
	END { exit(pre_call == 1 && action_case == 1 && action_call == 1 ? 0 : 1) }
' "${REPO_DIR}/S99AdGuardHome" || fail 'S99 permission helper is not wired into all expected service paths'
