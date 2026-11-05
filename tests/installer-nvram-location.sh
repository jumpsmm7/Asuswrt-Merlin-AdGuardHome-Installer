#!/bin/sh
# Exercise real stock NVRAM resolution, JFFS diagnostics and transactions.
set -u

INSTALLER_PATH="${1:-installer}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/installer-nvram-location.XXXXXX")" || exit 1
NVRAM_TEST_WHICH=""
NVRAM_TEST_STATE="${TEST_ROOT}/state"
NVRAM_TEST_CALLS="${TEST_ROOT}/calls"
NVRAM_TEST_SHOW_STATUS=0
NVRAM_TEST_STATUS=0
export NVRAM_TEST_WHICH NVRAM_TEST_STATE NVRAM_TEST_CALLS NVRAM_TEST_SHOW_STATUS NVRAM_TEST_STATUS

# fail reports a failed contract while cleanup removes only private fixtures.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}
cleanup() { rm -rf "${TEST_ROOT}"; }
trap cleanup 0
trap 'exit 1' HUP INT TERM
NVRAM_TEST_WHICH="$(which which 2>/dev/null)" || fail 'actual which executable is unavailable'
[ -x "${NVRAM_TEST_WHICH}" ] || fail 'actual which executable is unavailable'

# command models a missing optional builtin even if this test shell provides it.
# Any attempted use must fail and leave evidence.
command() {
	printf '%s\n' used >>"${TEST_ROOT}/command-used"
	return 127
}

# Extract each production helper unchanged before rebasing stock filesystem
# literals. The real which executable searches a private stock-only PATH;
# no replacement lookup function supplies the expected answer.
for helper in ai_have_cmd installer_nvram_path installer_nvram preflight_check_nvram \
	jffs_read_settings preflight_check_jffs_ready preflight_check_path preflight \
	nvram_transaction_begin nvram_transaction_begin_locked nvram_transaction_set \
	nvram_transaction_apply nvram_transaction_restore nvram_transaction_restart_services; do
	sed -n "/^${helper}() {$/,/^}/p" "${INSTALLER_PATH}" >"${TEST_ROOT}/extracted"
	[ -s "${TEST_ROOT}/extracted" ] || fail "missing production helper: ${helper}"
	cat "${TEST_ROOT}/extracted" >>"${TEST_ROOT}/functions.original"
done
sed -e "s|/sbin:/bin:/usr/sbin:/usr/bin|${TEST_ROOT}/stock/sbin:${TEST_ROOT}/stock/bin:${TEST_ROOT}/stock/usr/sbin:${TEST_ROOT}/stock/usr/bin|g" \
	-e "s|/usr/sbin/nvram|${TEST_ROOT}/stock/usr/sbin/nvram|g" \
	-e "s|/bin/nvram|${TEST_ROOT}/stock/bin/nvram|g" \
	"${TEST_ROOT}/functions.original" >"${TEST_ROOT}/functions" || fail 'could not isolate stock paths'
. "${TEST_ROOT}/functions"

mkdir -p "${TEST_ROOT}/stock/sbin" "${TEST_ROOT}/stock/bin" \
	"${TEST_ROOT}/stock/usr/sbin" "${TEST_ROOT}/stock/usr/bin" "${TEST_ROOT}/attacker" || exit 1
# Preserve the production plain which invocation. This private executable runs
# actual which under the rebased stock PATH, rather than supplying a path.
cat >"${TEST_ROOT}/stock/usr/bin/which" <<'EOF_WHICH'
#!/bin/sh
exec "${NVRAM_TEST_WHICH}" "$@"
EOF_WHICH
chmod 755 "${TEST_ROOT}/stock/usr/bin/which" || exit 1
cat >"${TEST_ROOT}/model" <<'EOF_MODEL'
#!/bin/sh
printf 'call=%s\n' "$0" >>"${NVRAM_TEST_CALLS}"
for argument do printf 'arg=%s\n' "${argument}" >>"${NVRAM_TEST_CALLS}"; done
case "$1" in
	get)
		awk -v key="$2" 'index($0, key "=") == 1 { print substr($0, length(key) + 2); found=1; exit } END { exit(found ? 0 : 1) }' "${NVRAM_TEST_STATE}"
		;;
	show)
		cat "${NVRAM_TEST_STATE}" || exit 1
		exit "${NVRAM_TEST_SHOW_STATUS}"
		;;
	set)
		key="${2%%=*}"
		value="${2#*=}"
		awk -v key="${key}" -v value="${value}" 'BEGIN { done=0 } index($0, key "=") == 1 { print key "=" value; done=1; next } { print } END { if (!done) print key "=" value }' "${NVRAM_TEST_STATE}" >"${NVRAM_TEST_STATE}.new" &&
			mv "${NVRAM_TEST_STATE}.new" "${NVRAM_TEST_STATE}"
		;;
	unset)
		awk -v key="$2" 'index($0, key "=") != 1' "${NVRAM_TEST_STATE}" >"${NVRAM_TEST_STATE}.new" &&
			mv "${NVRAM_TEST_STATE}.new" "${NVRAM_TEST_STATE}"
		;;
	commit) : ;;
	probe)
		printf '%s\n' 'probe-output'
		exit "${NVRAM_TEST_STATUS}"
		;;
	*) exit 1 ;;
esac
EOF_MODEL
chmod 755 "${TEST_ROOT}/model" || exit 1
cp "${TEST_ROOT}/model" "${TEST_ROOT}/attacker/nvram" || exit 1
PATH="${TEST_ROOT}/attacker:/bin:/usr/bin:/usr/sbin:/sbin"
export PATH

# reset_layout clears only candidate files and modeled state between cases.
reset_layout() {
	rm -f "${TEST_ROOT}/stock/bin/nvram" "${TEST_ROOT}/stock/usr/sbin/nvram" \
		"${TEST_ROOT}/stock/sbin/nvram" "${TEST_ROOT}/stock/usr/bin/nvram" || exit 1
	: >"${NVRAM_TEST_CALLS}"
	NVRAM_TEST_SHOW_STATUS=0
	NVRAM_TEST_STATUS=0
}
# install_model places an independent executable at a private stock location.
install_model() { cp "${TEST_ROOT}/model" "${TEST_ROOT}/stock/$1/nvram" || exit 1; }
# assert_selected runs both the real path resolver and read-only preflight probe.
assert_selected() {
	[ "$(installer_nvram_path)" = "${TEST_ROOT}/stock/$1/nvram" ] || fail "$1 was not selected"
	ai_have_cmd nvram || fail "$1 availability probe failed"
	preflight_check_nvram >"${TEST_ROOT}/preflight-path" || fail "$1 preflight failed"
	grep -Fxq "preflight.nvram.which=${TEST_ROOT}/stock/$1/nvram" "${TEST_ROOT}/preflight-path" || fail 'preflight reported a different executable'
	grep -Fxq 'preflight.nvram.result=OK' "${TEST_ROOT}/preflight-path" || fail 'preflight did not report success'
	[ ! -s "${NVRAM_TEST_CALLS}" ] || fail 'path diagnosis executed nvram'
}
# assert_rejected checks status propagation and refuses all executable fallback.
assert_rejected() {
	installer_nvram_path >/dev/null 2>&1 && fail 'foreign or unavailable candidate was selected'
	ai_have_cmd nvram && fail 'availability probe accepted an unavailable stock command'
	preflight_check_nvram >"${TEST_ROOT}/preflight-path" && fail 'unavailable stock command passed preflight'
	grep -Fxq 'preflight.nvram.which=missing' "${TEST_ROOT}/preflight-path" || fail 'missing stock command was not diagnosed'
	status=0
	installer_nvram probe >/dev/null 2>&1 || status=$?
	[ "${status}" -eq 127 ] || fail "missing stock command returned ${status}, expected 127"
	[ ! -s "${NVRAM_TEST_CALLS}" ] || fail 'rejected resolution executed a PATH fallback'
}
# PTXT captures the production diagnostic helpers without terminal formatting.
PTXT() { printf '%s\n' "$*"; }

reset_layout
install_model bin
assert_selected bin
reset_layout
install_model usr/sbin
assert_selected usr/sbin
reset_layout
install_model bin
install_model usr/sbin
assert_selected bin
reset_layout
install_model bin
chmod 644 "${TEST_ROOT}/stock/bin/nvram" || exit 1
install_model usr/sbin
assert_selected usr/sbin
reset_layout
assert_rejected
install_model bin
install_model usr/sbin
chmod 644 "${TEST_ROOT}/stock/bin/nvram" "${TEST_ROOT}/stock/usr/sbin/nvram" || exit 1
assert_rejected
reset_layout
mkdir "${TEST_ROOT}/stock/bin/nvram" || exit 1
assert_rejected
rmdir "${TEST_ROOT}/stock/bin/nvram" || exit 1
reset_layout
install_model sbin
assert_rejected
reset_layout
install_model usr/bin
assert_rejected
reset_layout
ln -s "${TEST_ROOT}/model" "${TEST_ROOT}/stock/bin/nvram" || exit 1
assert_selected bin
reset_layout
ln -s "${TEST_ROOT}/missing" "${TEST_ROOT}/stock/bin/nvram" || exit 1
assert_rejected

# An nvram function or inherited PATH executable cannot replace stock command
# execution. Both stock candidates exist when execution fails, so
# exactly one call also proves there is no retry against the second candidate.
reset_layout
install_model bin
install_model usr/sbin
(
	# Lookup still uses actual which; execution must use the resolved binary.
	nvram() {
		printf '%s\n' 'shadow nvram' >>"${NVRAM_TEST_CALLS}"
		return 1
	}
	assert_selected bin
	NVRAM_TEST_STATUS=37
	status=0
	installer_nvram probe 'space * = value' '' 'semi;$(literal)' >"${TEST_ROOT}/probe-output" || status=$?
	[ "${status}" -eq 37 ] || fail 'wrapper did not preserve command failure status'
) || exit 1
cat >"${TEST_ROOT}/expected-calls" <<EOF_EXPECTED
call=${TEST_ROOT}/stock/bin/nvram
arg=probe
arg=space * = value
arg=
arg=semi;\$(literal)
EOF_EXPECTED
cmp -s "${TEST_ROOT}/expected-calls" "${NVRAM_TEST_CALLS}" || fail 'wrapper retried, changed arguments or used a shadow command'
[ "$(cat "${TEST_ROOT}/probe-output")" = probe-output ] || fail 'wrapper changed command output'
reset_layout
(
	nvram() {
		printf '%s\n' 'shadow nvram' >>"${NVRAM_TEST_CALLS}"
		return 0
	}
	assert_rejected
) || exit 1

# A plain which invocation may be supplied unusable output. Validate its data
# and status before executing anything, even when both stock files exist.
for lookup_case in empty relative multiline disallowed failed; do
	reset_layout
	install_model bin
	install_model usr/sbin
	(
		# which models invalid lookup data without executing a replacement binary.
		which() {
			case "${lookup_case}" in
				empty) return 0 ;;
				relative) printf '%s\n' nvram ;;
				multiline) printf '%s\n' "${TEST_ROOT}/stock/bin/nvram" "${TEST_ROOT}/stock/usr/sbin/nvram" ;;
				disallowed) printf '%s\n' "${TEST_ROOT}/attacker/nvram" ;;
				failed)
					printf '%s\n' "${TEST_ROOT}/stock/bin/nvram"
					return 1
					;;
				*) return 1 ;;
			esac
		}
		assert_rejected
	) || fail "unusable which output was accepted: ${lookup_case}"
done

# Model unrelated package/topology checks only; the real preflight dispatch,
# stock NVRAM check and JFFS reader run together against both firmware layouts.
AI_VERSION=TEST
adguard_install_mode_detect() { return 0; }
preflight_action_requires_downloader() { return 1; }
preflight_action_requires_service_tools() { return 1; }
preflight_action_requires_cru() { return 1; }
preflight_action_requires_firewall_tools() { return 1; }
preflight_check_stock_commands() { return 0; }
preflight_action_requires_jffs_ready() { return 0; }
preflight_action_requires_router_eligibility() { return 1; }
preflight_action_requires_entware() { return 1; }
preflight_action_requires_jq() { return 1; }
preflight_action_requires_sha256() { return 1; }
for location in bin usr/sbin; do
	reset_layout
	install_model "${location}"
	printf '%s\n' jffs2_format=0 jffs2_scripts=1 jffs2_enable=1 >"${NVRAM_TEST_STATE}"
	cp "${NVRAM_TEST_STATE}" "${TEST_ROOT}/expected-state" || exit 1
	preflight install >"${TEST_ROOT}/ready-preflight" || fail "${location}-only ready JFFS preflight failed"
	grep -Fxq 'preflight.jffs.result=OK' "${TEST_ROOT}/ready-preflight" || fail 'preflight did not inspect actual ready JFFS state'
	grep -Fxq 'preflight.result=PASS' "${TEST_ROOT}/ready-preflight" || fail 'preflight dispatch did not pass'
	cmp -s "${TEST_ROOT}/expected-state" "${NVRAM_TEST_STATE}" || fail 'preflight changed NVRAM state'
	if grep -Eq '^arg=(set|unset|commit)$' "${NVRAM_TEST_CALLS}"; then fail 'preflight mutated NVRAM'; fi
done
printf '%s\n' jffs2_scripts=1 jffs2_on=1 >"${NVRAM_TEST_STATE}"
NVRAM_TEST_SHOW_STATUS=7
preflight_check_jffs_ready >"${TEST_ROOT}/legacy-preflight" || fail 'usable HND inventory with nonzero status was rejected'
grep -Fxq 'preflight.jffs.format_pending=legacy-absent' "${TEST_ROOT}/legacy-preflight" || fail 'legacy JFFS absence was not preserved'
if grep -Eq '^arg=(set|unset|commit)$' "${NVRAM_TEST_CALLS}"; then fail 'legacy diagnosis mutated NVRAM'; fi

# Only lock ownership and prior-setup recovery are outside this location
# fixture. Snapshot creation, staging, writes, commits and rollback remain real.
nvram_transaction_lock_acquire() { return 0; }
nvram_transaction_lock_release() { return 0; }
nvram_transaction_finalize_setup_pair() { return 0; }
rollback_result_write() { printf '%s\n' "$*" >&2; }
BASE_DIR="${TEST_ROOT}/base"
mkdir -p "${BASE_DIR}" || exit 1
printf '%s\n' existing=old >"${NVRAM_TEST_STATE}"
: >"${NVRAM_TEST_CALLS}"
nvram_transaction_begin location existing absent || fail 'usr/sbin-only transaction snapshot failed'
[ -f "${NVRAM_TRANSACTION_DIR}/exists.existing" ] || fail 'existing key presence was not snapshotted'
[ ! -f "${NVRAM_TRANSACTION_DIR}/exists.absent" ] || fail 'absent key was marked present'
nvram_transaction_set existing 'new value' || fail 'existing key staging failed'
nvram_transaction_set absent added || fail 'absent key staging failed'
nvram_transaction_apply - 1 || fail 'usr/sbin-only transaction apply failed'
printf '%s\n' 'existing=new value' absent=added >"${TEST_ROOT}/expected-state"
cmp -s "${TEST_ROOT}/expected-state" "${NVRAM_TEST_STATE}" || fail 'transaction values were not applied'
[ -f "${NVRAM_TRANSACTION_DIR}/dirty" ] || fail 'retained transaction lost its recovery marker'
nvram_transaction_restore - || fail 'usr/sbin-only transaction rollback failed'
printf '%s\n' existing=old >"${TEST_ROOT}/expected-state"
cmp -s "${TEST_ROOT}/expected-state" "${NVRAM_TEST_STATE}" || fail 'rollback did not restore existing and unset absent keys'
[ ! -e "${NVRAM_TRANSACTION_DIR}" ] || fail 'successful rollback retained its snapshot'
[ "$(grep -c '^arg=commit$' "${NVRAM_TEST_CALLS}")" -eq 2 ] || fail 'apply/restore did not commit exactly once each'
grep -Fxq 'arg=unset' "${NVRAM_TEST_CALLS}" || fail 'rollback did not unset the initially absent key'
if grep '^call=' "${NVRAM_TEST_CALLS}" | grep -Fvx "call=${TEST_ROOT}/stock/usr/sbin/nvram" >/dev/null; then
	fail 'transaction executed a different NVRAM binary'
fi

[ ! -e "${TEST_ROOT}/command-used" ] || fail 'stock lookup invoked the unavailable command builtin'
printf '%s\n' 'PASS: stock NVRAM lookup needs no command builtin and preserves preflight, JFFS and transactions'
