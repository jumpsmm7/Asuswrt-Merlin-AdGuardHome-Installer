#!/bin/sh
# Exercise complete installer startup/dispatch with private router paths. Clean
# recovery helpers remain real; explicit recovery faults model only their result.

set -u

INSTALLER_PATH="${1:-installer}"
TEST_ROOT="${TMPDIR:-/tmp}/installer-support-startup.$$"
TEST_SHELL="${SUPPORT_STARTUP_TEST_SHELL:-sh}"

# cleanup removes only this test's private fixture.
cleanup() { rm -rf "${TEST_ROOT}"; }
# fail reports a routing contract failure and its most recent installer output.
fail() {
	printf '%s\n' "FAIL: support startup: $*" >&2
	for log in stdout stderr calls; do
		[ ! -f "${TEST_ROOT}/${log}" ] || cat "${TEST_ROOT}/${log}" >&2
	done
	exit 1
}

trap cleanup 0
trap 'exit 1' HUP INT TERM
(umask 077 && mkdir "${TEST_ROOT}") || exit 1
EXPECTED_INSTALLER_VERSION="$(awk -F '"' '/^AI_VERSION="[^"]+"$/ { version=$2; count++ }
	END { if (count != 1) exit 1; print version }' "${INSTALLER_PATH}")" || fail 'could not read exact installer version'
mkdir -p "${TEST_ROOT}/bin" "${TEST_ROOT}/fs/opt/etc" \
	"${TEST_ROOT}/fs/jffs/scripts" "${TEST_ROOT}/fs/tmp" "${TEST_ROOT}/out" || exit 1
export TEST_ROOT

# Preserve the actual collector, parser, early dispatch, recovery predicate and
# exit handler. Rename four recovery boundaries so the clean cases invoke their
# actual implementation and fault cases inject a declared result at that point.
# Fatal spies make any ordinary setup/source/download path observable even when
# a caller ignores a helper's status. Only this generated copy changes PATH.
# build_fixture rewrites only fixed router paths and the declared test seams.
build_fixture() {
	awk -v root="${TEST_ROOT}" '
	BEGIN {
		count=split("write_conf del_conf download_file resolve_installer_branch installer_dependencies_available adguard_install_mode_detect amtm_update_check check_version menu nvram_transaction_begin setup_AdGuardHome inst_AdGuardHome backup_restore create_dir installer_requested_bundle_update_allowed cli_pre_runtime_defaults_preview cli_pre_remote_dry_run opkg_clean_env agh_start agh_stop agh_restart", names, " ")
		for (i=1; i<=count; i++) forbidden[names[i]]=1
		count=split("nvram_transaction_recovery_dependencies_available adguard_committed_binary_cleanup_retry all_event_scripts_recover_startup nvram_transaction_recover_pending", names, " ")
		for (i=1; i<=count; i++) boundaries[names[i]]=1
	}
	{
		if (skipping) { if ($0 == "}") skipping=0; next }
		if ($0 ~ /^[a-zA-Z_][a-zA-Z0-9_]*\(\) \{$/) {
			name=$1; sub(/\(\)$/, "", name)
			if (name in forbidden) {
				print name "() {"
				print "\tprintf '\''%s\\n'\'' '\''FORBIDDEN " name "'\'' >>\"${TEST_ROOT}/calls\""
				print "\texit 93"
				print "}"
				seen[name]=1; skipping=1; next
			}
			if (name in boundaries) { sub(name "\\(\\)", "fixture_actual_" name "()"); seen[name]=1 }
		}
		if ($0 == "nvram_transaction_recovery_dependencies_available || exit 1") {
			while ((getline line < (root "/recovery-model")) > 0) print line
			close(root "/recovery-model"); dispatch=1
		}
		gsub(/\/tmp/, root "/fs/tmp")
		gsub(/\/opt/, root "/fs/opt")
		gsub(/\/jffs/, root "/fs/jffs")
		print
		if ($0 ~ /^export PATH=/) print "export PATH=\"${TEST_ROOT}/bin:${PATH}\""
	}
	END {
		if (!dispatch || skipping) exit 1
		for (name in forbidden) if (!(name in seen)) exit 1
		for (name in boundaries) if (!(name in seen)) exit 1
	}
	' "${INSTALLER_PATH}" >"${TEST_ROOT}/installer"
}

cat >"${TEST_ROOT}/recovery-model" <<'MODEL'
# Model dependency availability while preserving the clean real command checks.
nvram_transaction_recovery_dependencies_available() {
	printf '%s\n' startup:dependencies >>"${TEST_ROOT}/calls"
	[ "${STARTUP_RECOVERY_CASE}" != dependencies-failed ] || return 1
	fixture_actual_nvram_transaction_recovery_dependencies_available
}
# Model a committed-backup cleanup failure; clean calls retain real validation.
adguard_committed_binary_cleanup_retry() {
	printf '%s\n' startup:binary-cleanup >>"${TEST_ROOT}/calls"
	[ "${STARTUP_RECOVERY_CASE}" != binary-failed ] || return 1
	fixture_actual_adguard_committed_binary_cleanup_retry
}
# Model event-hook recovery failure without fabricating restored filesystem state.
all_event_scripts_recover_startup() {
	printf '%s\n' startup:event-hooks >>"${TEST_ROOT}/calls"
	[ "${STARTUP_RECOVERY_CASE}" != hooks-failed ] || return 1
	fixture_actual_all_event_scripts_recover_startup
}
# Model cleanup-only versus unsafe recovery results at the pending-state boundary.
nvram_transaction_recover_pending() {
	printf '%s\n' startup:nvram >>"${TEST_ROOT}/calls"
	case "${STARTUP_RECOVERY_CASE}" in
		cleanup-only)
			NVRAM_TRANSACTION_RECOVERY_DIAGNOSTIC_SAFE=1
			return 1
			;;
		unsafe)
			NVRAM_TRANSACTION_RECOVERY_DIAGNOSTIC_SAFE=0
			return 1
			;;
	esac
	fixture_actual_nvram_transaction_recover_pending
}
MODEL

# Build the generated installer only after its injected model exists.
build_fixture || fail 'could not build isolated complete installer'
sh -n "${TEST_ROOT}/installer" || fail 'isolated installer does not parse'

cat >"${TEST_ROOT}/bin/probe-model" <<'MODEL'
#!/bin/sh
name="${0##*/}"
printf '%s\n' "probe:${name} $*" >>"${TEST_ROOT}/calls"
case "${name}" in
	nvram)
		if [ "$#" -ne 2 ] || [ "$1" != get ]; then
			printf '%s\n' 'FORBIDDEN command:nvram-write-or-dump' >>"${TEST_ROOT}/calls"
			exit 93
		fi
		case "$2" in
			productid) printf '%s\n' RT-AC68U ;;
			firmver) printf '%s\n' 386 ;;
			buildno) printf '%s\n' 14 ;;
			extendno) printf '%s\n' 2 ;;
			*) exit 93 ;;
		esac
		;;
	uname) [ "$*" = -m ] || exit 93; printf '%s\n' armv7l ;;
	df) printf '%s\n' 'Filesystem 1024-blocks Used Available Capacity Mounted on' 'fixture 10000 1000 9000 10% /fixture' ;;
	pidof) exit 1 ;;
	ps | netstat) exit 0 ;;
	*) printf '%s\n' "FORBIDDEN command:${name}" >>"${TEST_ROOT}/calls"; exit 93 ;;
esac
MODEL
chmod 700 "${TEST_ROOT}/bin/probe-model" || exit 1
for command in nvram uname df pidof ps netstat service opkg iptables ip6tables curl wget reboot; do
	ln -s probe-model "${TEST_ROOT}/bin/${command}" || exit 1
done
# Host-fixture polling acceleration; monotonic deadlines and actual probe
# process execution remain the collector implementation under test.
cat >"${TEST_ROOT}/bin/usleep" <<'MODEL'
#!/bin/sh
if [ -x /bin/busybox ] && /bin/busybox usleep 0 2>/dev/null; then
	exec /bin/busybox usleep 20000
fi
exec sleep 0.02
MODEL
chmod 700 "${TEST_ROOT}/bin/usleep" || exit 1

# snapshot records router-path names and file contents, excluding report output.
snapshot() {
	find "${TEST_ROOT}/fs" -print | sort
	find "${TEST_ROOT}/fs" -type f | sort | while IFS= read -r file; do
		sha256sum "${file}" || return 1
	done
}

# run invokes the entire generated installer with hostile inherited diagnostic
# identity, checks the result, and rejects writes or ordinary startup calls.
run() {
	case_name="$1"
	recovery_case="$2"
	expected_result="$3"
	shift 3
	: >"${TEST_ROOT}/calls"
	snapshot >"${TEST_ROOT}/before" || fail 'could not snapshot router inputs'
	(
		cd "${TEST_ROOT}" || exit 1
		STARTUP_RECOVERY_CASE="${recovery_case}" \
			SUPPORT_EXPORT_SOURCE_REF=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
			SUPPORT_EXPORT_RECOVERY_STATUS=forged-completion AI_NO_AUTO_UPDATE=0 \
			"${TEST_SHELL}" "${TEST_ROOT}/installer" "$@"
	) >"${TEST_ROOT}/stdout" 2>"${TEST_ROOT}/stderr"
	result="$?"
	snapshot >"${TEST_ROOT}/after" || fail 'could not check router inputs'
	cmp -s "${TEST_ROOT}/before" "${TEST_ROOT}/after" || fail "${case_name}: router inputs changed"
	if grep -q '^FORBIDDEN ' "${TEST_ROOT}/calls"; then fail "${case_name}: entered an ordinary write/source/download path"; fi
	case "${expected_result}:${result}" in
		pass:0)
			printf '%s\n' startup:dependencies startup:binary-cleanup startup:event-hooks startup:nvram >"${TEST_ROOT}/expected-recovery"
			sed -n '1,4p' "${TEST_ROOT}/calls" >"${TEST_ROOT}/actual-recovery"
			cmp -s "${TEST_ROOT}/expected-recovery" "${TEST_ROOT}/actual-recovery" || fail "${case_name}: collection bypassed prior recovery checks"
			;;
		fail:0) fail "${case_name}: rejected command succeeded" ;;
		fail:*) ;;
		*) fail "${case_name}: support export failed with exit ${result}" ;;
	esac
}

# expect verifies one report field without accepting a substring match.
expect() {
	grep -Fx "$2" "$1" >/dev/null || fail "missing report field: $2"
}

report="${TEST_ROOT}/out/fresh.txt"
run fresh clean pass support-export --output "${report}"
expect "${report}" "installer.version=${EXPECTED_INSTALLER_VERSION}"
expect "${report}" installation.state=absent
expect "${report}" installer.source=unknown
expect "${report}" recovery.prior_startup=checked
[ ! -e "${TEST_ROOT}/fs/opt/etc/AdGuardHome" ] || fail 'fresh diagnostic created installation directory'

mkdir "${TEST_ROOT}/fs/opt/etc/AdGuardHome" || exit 1
printf '%s\n' 'INSTALLER_BRANCH="master"' 'ADGUARD_BRANCH="beta"' >"${TEST_ROOT}/fs/opt/etc/AdGuardHome/.config"
printf 'EXECUTE="$(touch %s)"\n' "${TEST_ROOT}/source-was-executed" >>"${TEST_ROOT}/fs/opt/etc/AdGuardHome/.config"
cat >"${TEST_ROOT}/fs/opt/etc/AdGuardHome/AdGuardHome" <<'MODEL'
#!/bin/sh
if [ "$*" != --version ]; then
	printf '%s\n' 'FORBIDDEN installed-binary-action' >>"${TEST_ROOT}/calls"
	exit 93
fi
printf '%s\n' 'AdGuard Home, version v0.107.59'
MODEL
chmod 700 "${TEST_ROOT}/fs/opt/etc/AdGuardHome/AdGuardHome" || exit 1
for flag_position in none leading suffix middle; do
	report="${TEST_ROOT}/out/${flag_position}.txt"
	case "${flag_position}" in
		none) set -- support-export --output "${report}" ;;
		leading) set -- --no-auto-update support-export --output "${report}" ;;
		suffix) set -- support-export --output "${report}" --no-auto-update ;;
		middle) set -- support-export --no-auto-update --output "${report}" ;;
	esac
	run "${flag_position}" clean pass "$@"
	expect "${report}" installer.source=master
	expect "${report}" adguardhome.channel=beta
	expect "${report}" recovery.prior_startup=checked
	diff -u "${TEST_ROOT}/before" "${TEST_ROOT}/after" || fail 'installed diagnostic changed its inputs'
done
[ ! -e "${TEST_ROOT}/source-was-executed" ] || fail 'diagnostic sourced private configuration'

report="${TEST_ROOT}/out/rejected.txt"
run missing-output clean fail support-export
run missing-value clean fail support-export --output
run unknown-option clean fail support-export --unknown "${report}"
run relative-path clean fail support-export --output relative.txt
run source-override clean fail support-export --installer-branch master --output "${report}"
run extra-argument clean fail support-export --output "${report}" extra
run duplicate-output clean fail support-export --output "${report}" --output "${report}"
[ ! -e "${report}" ] || fail 'malformed invocation published a report'
printf '%s\n' preserve >"${TEST_ROOT}/out/foreign"
ln -s foreign "${TEST_ROOT}/out/unsafe-link" || exit 1
run unsafe-output clean fail support-export --output "${TEST_ROOT}/out/unsafe-link"
expect "${TEST_ROOT}/out/foreign" preserve

report="${TEST_ROOT}/out/pending.txt"
run cleanup-only cleanup-only pass support-export --output "${report}" --no-auto-update
expect "${report}" recovery.prior_startup=pending
grep -q 'continuing with read-only diagnostics' "${TEST_ROOT}/stdout" || fail 'cleanup-only recovery continuation was not disclosed'
for recovery_case in unsafe dependencies-failed binary-failed hooks-failed; do
	report="${TEST_ROOT}/out/${recovery_case}.txt"
	run "${recovery_case}" "${recovery_case}" fail support-export --output "${report}"
	[ ! -e "${report}" ] || fail "${recovery_case}: failed recovery published a report"
	if grep -q '^probe:' "${TEST_ROOT}/calls"; then fail "${recovery_case}: collection ran after recovery failure"; fi
done

printf '%s\n' 'PASS: complete support-export startup routes before ordinary setup; checked/pending recovery and fail-closed boundaries verified (firmware probes and recovery faults modeled)'
