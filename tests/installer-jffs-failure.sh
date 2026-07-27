#!/bin/sh
# Verify JFFS NVRAM failures abort both installer entry pathways.

set -u

INSTALLER_PATH="${1:-installer}"
TEST_ROOT="$(mktemp -d)" || {
	printf '%s\n' "FAIL: could not create test workspace" >&2
	exit 1
}

fail() {
	rm -rf "${TEST_ROOT}"
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}
cleanup() { rm -rf "${TEST_ROOT}"; }
trap cleanup 0

[ -f "${INSTALLER_PATH}" ] || fail "installer script not found: ${INSTALLER_PATH}"

# Extract the CLI install function body (without case label and closing ;;)
sed -n '/^[[:space:]]*install)$/,/^[[:space:]]*;;$/p' "${INSTALLER_PATH}" |
	sed '1d;$d' >"${TEST_ROOT}/cli_install" ||
	fail 'could not extract the CLI install pathway'
[ -s "${TEST_ROOT}/cli_install" ] || fail 'CLI install pathway was not found'

# Stub check_jffs_enabled to fail and wrap in a function
cat >"${TEST_ROOT}/test_cli" <<'EOF'
#!/bin/sh
check_jffs_enabled() { return 1; }
CLI_DRY_RUN=0
cli_require_yes() { return 0; }
AGH_FILE=/dev/null
ADGUARD_INSTALL_MODE=lan
CLI_ALLOW_DNS_NVRAM=1
cli_enable_assume_yes() { :; }
cleanup() { :; }
adguard_branch=""
installer_branch=""
conf_value() { :; }
cli_adguard_branch_is_valid() { return 0; }
create_dir() { return 0; }
TARG_DIR=/tmp
write_conf() { return 0; }
cli_write_adguard_branch() { return 0; }
PTXT() { :; }
check_dns_environment() { return 0; }
inst_AdGuardHome() { return 0; }
ERROR="Error:"

cli_install_test() {
EOF
cat "${TEST_ROOT}/cli_install" >>"${TEST_ROOT}/test_cli"
cat >>"${TEST_ROOT}/test_cli" <<'EOF'
}

cli_install_test
EOF
chmod +x "${TEST_ROOT}/test_cli"

# Test CLI install pathway - should return 1 when check_jffs_enabled fails
"${TEST_ROOT}/test_cli"
status="$?"
if [ "${status}" -eq 0 ]; then
	fail 'CLI install must return 1 when JFFS setup fails'
fi
[ "${status}" -eq 1 ] || fail 'CLI install must return status 1 when JFFS setup fails'

# Test interactive install pathway - should exit 1 when check_jffs_enabled fails
cat >"${TEST_ROOT}/test_interactive" <<'EOF'
#!/bin/sh
check_jffs_enabled() { return 1; }
ADGUARD_INSTALL_MODE=lan
NAT_ENV=""
cleanup() { :; }
adguard_install_mode_detect() { return 0; }
adguard_install_mode_confirmed() { return 0; }

EOF
sed -n '/^case "$2" in$/,/^[[:space:]]*menu$/p' "${INSTALLER_PATH}" >>"${TEST_ROOT}/test_interactive" ||
	fail 'could not extract the interactive install pathway'
printf '%s\n' '		;;' 'esac' >>"${TEST_ROOT}/test_interactive" ||
	fail 'could not complete the interactive install harness'
chmod +x "${TEST_ROOT}/test_interactive"

"${TEST_ROOT}/test_interactive"
status="$?"
if [ "${status}" -eq 0 ]; then
	fail 'interactive install must exit 1 when JFFS setup fails'
fi
[ "${status}" -eq 1 ] || fail 'interactive install must exit with status 1 when JFFS setup fails'

# Verify that both call sites are guarded
call_count="$(grep -c '^[[:space:]]*check_jffs_enabled || \(return\|exit\) 1$' "${INSTALLER_PATH}")" ||
	fail 'could not count guarded JFFS setup calls'
[ "${call_count}" -eq 2 ] || fail 'every JFFS setup call must propagate failure'

printf '%s\n' 'PASS: JFFS setup failures abort CLI and interactive installs'
