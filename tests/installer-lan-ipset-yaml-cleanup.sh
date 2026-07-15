#!/bin/sh
# Verify LAN-mode IPSET enforcement removes YAML ipset_file safely.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-lan-ipset-yaml-cleanup.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions"
CONF_FILE="${TMP_ROOT}/.config"
TARG_DIR="${TMP_ROOT}/AdGuardHome"
YAML_FILE="${TARG_DIR}/AdGuardHome.yaml"

cleanup() {
	rm -rf "${TMP_ROOT}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

mode_string() {
	ls -ld "$1" | awk 'NR == 1 { print substr($1, 1, 10) }'
}

extract_function() {
	_function_name="$1"
	awk -v name="${_function_name}" '
		$0 == name "() {" { copying = 1 }
		copying { print }
		copying && $0 == "}" { exit }
	' "${SCRIPT_PATH}" >>"${FUNCTIONS_FILE}" || return 1
}

write_conf() {
	_key="$1"
	_value="$2"
	_tmp_file="${CONF_FILE}.tmp.$$"
	awk -v KEY="${_key}" -v VALUE="${_value}" '
		BEGIN { replaced = 0 }
		index($0, KEY "=") == 1 {
			print KEY "=" VALUE
			replaced = 1
			next
		}
		{ print }
		END {
			if (!replaced) print KEY "=" VALUE
		}
	' "${CONF_FILE}" >"${_tmp_file}" && mv -f "${_tmp_file}" "${CONF_FILE}" || {
		rm -f "${_tmp_file}"
		return 1
	}
}

assert_no_ipset_file() {
	if grep -q 'ipset_file' "${YAML_FILE}"; then
		fail "$1: ipset_file was not removed"
	fi
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"
mkdir -p "${TMP_ROOT}" "${TARG_DIR}" || fail 'could not create test directory'
: >"${FUNCTIONS_FILE}"
extract_function conf_value || fail 'could not extract conf_value'
extract_function adguardhome_yaml_ipset_file || fail 'could not extract YAML parser'
extract_function adguardhome_yaml_remove_ipset_file || fail 'could not extract YAML cleanup helper'
extract_function adguard_enforce_lan_ipset_disabled || fail 'could not extract LAN enforcement helper'
[ -s "${FUNCTIONS_FILE}" ] || fail 'helper extraction was empty'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

INFO='Info:'
PTXT() { :; }

cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write custom YAML ipset_file'
dns:
  bind_hosts:
    - 0.0.0.0
  ipset_file: custom-ipset.conf
  bootstrap_dns:
    - 1.1.1.1
EOF_YAML
chmod 600 "${YAML_FILE}" || fail 'could not set YAML mode'
adguardhome_yaml_remove_ipset_file || fail 'custom YAML ipset_file cleanup failed'
assert_no_ipset_file custom-path
[ "$(mode_string "${YAML_FILE}")" = '-rw-------' ] || fail 'YAML mode was not preserved after cleanup'
grep -q 'bootstrap_dns:' "${YAML_FILE}" || fail 'cleanup removed following dns child key'

cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write quoted-key YAML ipset_file'
"dns":
  'ipset_file': custom-quoted-ipset.conf
  bootstrap_dns:
    - 1.0.0.1
EOF_YAML
chmod 644 "${YAML_FILE}" || fail 'could not set world-readable YAML mode'
adguardhome_yaml_remove_ipset_file || fail 'quoted-key YAML ipset_file cleanup failed'
assert_no_ipset_file quoted-key
[ "$(mode_string "${YAML_FILE}")" = '-rw-------' ] || fail 'YAML mode was not tightened after quoted-key cleanup'
grep -q 'bootstrap_dns:' "${YAML_FILE}" || fail 'quoted-key cleanup removed following dns child key'

cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write block scalar YAML ipset_file'
dns:
  ipset_file: |
    custom-ipset.conf
    stale-continuation.conf
  bootstrap_dns:
    - 9.9.9.9
filtering:
  protection_enabled: true
EOF_YAML
chmod 600 "${YAML_FILE}" || fail 'could not reset YAML mode'
adguardhome_yaml_remove_ipset_file || fail 'block-scalar YAML ipset_file cleanup failed'
assert_no_ipset_file block-scalar
if grep -q 'custom-ipset.conf\|stale-continuation.conf' "${YAML_FILE}"; then
	fail 'block-scalar continuation was not removed'
fi
grep -q 'bootstrap_dns:' "${YAML_FILE}" || fail 'block cleanup removed following dns key'
grep -q 'filtering:' "${YAML_FILE}" || fail 'block cleanup removed following top-level key'
[ "$(mode_string "${YAML_FILE}")" = '-rw-------' ] || fail 'YAML mode was not preserved after block cleanup'

cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write folded block YAML ipset_file'
'dns':
  "ipset_file": >-
    folded-ipset.conf
    folded-continuation.conf
  bootstrap_dns:
    - 8.8.8.8
EOF_YAML
chmod 600 "${YAML_FILE}" || fail 'could not reset folded YAML mode'
adguardhome_yaml_remove_ipset_file || fail 'folded block YAML ipset_file cleanup failed'
assert_no_ipset_file folded-block
if grep -q 'folded-ipset.conf\|folded-continuation.conf' "${YAML_FILE}"; then
	fail 'folded block continuation was not removed'
fi
grep -q 'bootstrap_dns:' "${YAML_FILE}" || fail 'folded cleanup removed following dns key'

cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write YAML without ipset_file'
dns:
  bootstrap_dns:
    - 4.4.4.4
EOF_YAML
chmod 644 "${YAML_FILE}" || fail 'could not set no-op YAML mode'
adguardhome_yaml_remove_ipset_file || fail 'no-op YAML cleanup failed'
[ "$(mode_string "${YAML_FILE}")" = '-rw-r--r--' ] || fail 'no-op cleanup rewrote YAML permissions unexpectedly'
grep -q 'bootstrap_dns:' "${YAML_FILE}" || fail 'no-op cleanup changed YAML content'

cat >"${CONF_FILE}" <<'EOF_CONF' || fail 'could not write restored WAN config'
ADGUARD_INSTALL_MODE="wan"
ADGUARD_IPSET="YES"
EOF_CONF
cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write restored YAML ipset_file'
dns:
  ipset_file: restored-custom.conf
EOF_YAML
ADGUARD_INSTALL_MODE='lan'
adguard_enforce_lan_ipset_disabled || fail 'LAN enforcement failed for detected LAN/restored WAN config'
[ "$(conf_value ADGUARD_INSTALL_MODE)" = 'lan' ] || fail 'LAN enforcement did not persist detected LAN mode'
[ "$(conf_value ADGUARD_IPSET)" = 'NO' ] || fail 'LAN enforcement did not disable ADGUARD_IPSET'
assert_no_ipset_file detected-lan

cat >"${CONF_FILE}" <<'EOF_CONF' || fail 'could not write restored LAN config'
ADGUARD_INSTALL_MODE="lan"
ADGUARD_IPSET="YES"
EOF_CONF
cat >"${YAML_FILE}" <<'EOF_YAML' || fail 'could not write restored LAN YAML ipset_file'
dns:
  ipset_file: restored-lan.conf
EOF_YAML
ADGUARD_INSTALL_MODE=''
adguard_enforce_lan_ipset_disabled || fail 'LAN enforcement failed for restored LAN config'
[ "$(conf_value ADGUARD_INSTALL_MODE)" = 'lan' ] || fail 'LAN enforcement did not keep restored LAN mode'
[ "$(conf_value ADGUARD_IPSET)" = 'NO' ] || fail 'LAN enforcement did not disable restored ADGUARD_IPSET'
assert_no_ipset_file restored-lan

printf '%s\n' 'PASS: LAN IPSET YAML cleanup covers simple, quoted, block, no-op, and restore paths'
