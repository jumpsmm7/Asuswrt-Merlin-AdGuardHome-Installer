#!/bin/sh
# Verify stale ownerless reapers are reclaimed after atomic owner publication.

set -u

INSTALLER_PATH="${1:-installer}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/installer-reaper-owner-publication.XXXXXX")" || {
	printf '%s\n' 'FAIL: could not create exclusive reaper test workspace' >&2
	exit 1
}
FUNCTIONS_FILE="${TEST_ROOT}/functions"

# fail reports a test failure and exits with a nonzero status.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

# cleanup removes the temporary test workspace.
cleanup() {
	[ -z "${TEST_LIVE_PID:-}" ] || kill "${TEST_LIVE_PID}" 2>/dev/null || true
	rm -rf "${TEST_ROOT}"
}
trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

/bin/sed -n '/^nvram_transaction_setup_files_failure() {$/,/^nvram_transaction_setup_files_restore() {$/p' "${INSTALLER_PATH}" |
	/bin/sed '$d' >"${FUNCTIONS_FILE}" || fail 'could not extract setup journal helpers'
/bin/sed -n '/^nvram_transaction_recover_startup() {$/,/^installer_lan_domain_set() {$/p' "${INSTALLER_PATH}" |
	/bin/sed '$d' >>"${FUNCTIONS_FILE}" || fail 'could not extract transaction lock helpers'
[ -s "${FUNCTIONS_FILE}" ] || fail 'transaction lock helper extraction was empty'

# Every production function touched by the reaper publication change must keep
# a function-specific shell documentation comment directly above its definition.
for documented_helper in \
	nvram_transaction_lock_reaper_claim_mkdir \
	nvram_transaction_lock_reaper_claim_owner_write \
	nvram_transaction_lock_reaper_claim_owner_secure \
	nvram_transaction_lock_reaper_claim_publish \
	nvram_transaction_lock_reaper_claim_remove \
	nvram_transaction_lock_reaper_claim_cleanup \
	nvram_transaction_lock_reaper_legacy_claim \
	nvram_transaction_lock_reaper_acquire_impl \
	setup_files_journal_diagnostic; do
	awk -v function_signature="${documented_helper}() {" -v comment_prefix="# ${documented_helper} " '
		$0 == function_signature {
			found = 1
			documented = index(previous, comment_prefix) == 1
		}
		{ previous = $0 }
		END { exit !(found && documented) }
	' "${INSTALLER_PATH}" || fail "production helper lacks its function documentation comment: ${documented_helper}"
done

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"
for reaper_fn in nvram_transaction_lock_reaper_acquire nvram_transaction_lock_reaper_release; do
	type "${reaper_fn}" >/dev/null 2>&1 || fail "extracted helpers are missing ${reaper_fn}()"
done

reaper_path="${TEST_ROOT}/owner-publication.reaper"
LOCK_OWNER="66816:373949"
CLAIM_MKDIR_CALLS=0

# nvram_transaction_lock_reaper_claim_mkdir rejects nonportable claim names while
# allowing owner data containing a colon inside the published pid file.
nvram_transaction_lock_reaper_claim_mkdir() {
	CLAIM_MKDIR_CALLS="$((CLAIM_MKDIR_CALLS + 1))"
	case "$1" in
		*:*) return 1 ;;
	esac
	/bin/mkdir "$1"
}

# nvram_transaction_lock_flock_supports_fd reports that file-descriptor locking is unavailable.
nvram_transaction_lock_flock_supports_fd() { return 1; }
# nvram_transaction_lock_readlink returns 127 to indicate that symbolic-link support is unavailable.
nvram_transaction_lock_readlink() { return 127; }
# sleep skips acquisition backoff delays in this regression test.
sleep() { :; }

# Two abandoned candidates carrying this process identity are recoverable. The
# bounded suffix loop must clean both before publishing a third candidate.
candidate_test_path="${TEST_ROOT}/candidate-recovery.reaper"
mkdir "${candidate_test_path}.claim.66816.373949" "${candidate_test_path}.claim.66816.373949.1" || fail 'could not create same-owner candidate fixtures'
printf '%s\n' "${LOCK_OWNER}" >"${candidate_test_path}.claim.66816.373949/pid"
printf '%s\n' "${LOCK_OWNER}" >"${candidate_test_path}.claim.66816.373949.1/pid"
nvram_transaction_lock_reaper_legacy_claim "${candidate_test_path}" "${LOCK_OWNER}" || fail "same-owner candidates were not recovered: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-missing diagnostic}"
[ ! -e "${candidate_test_path}.claim.66816.373949" ] || fail 'first same-owner candidate remained after recovery'
[ ! -e "${candidate_test_path}.claim.66816.373949.1" ] || fail 'second same-owner candidate remained after recovery'
[ "$(cat "${candidate_test_path}/pid" 2>/dev/null)" = "${LOCK_OWNER}" ] || fail 'recovered candidate did not publish its owner'
rm -rf "${candidate_test_path}"

# A mkdir failure without a colliding artifact is a candidate-creation error.
mkdir_failure_path="${TEST_ROOT}/mkdir-failure.reaper"
nvram_transaction_lock_reaper_claim_mkdir() { return 1; }
NVRAM_TRANSACTION_LOCK_DIAGNOSTIC=""
if nvram_transaction_lock_reaper_legacy_claim "${mkdir_failure_path}" "${LOCK_OWNER}"; then
	fail 'claim succeeded after injected candidate mkdir failure'
fi
case "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" in
	"operation=create-reaper-claim candidate=${mkdir_failure_path}.claim.66816.373949 destination=${mkdir_failure_path} reason=mkdir-failed") ;;
	*) fail "candidate mkdir failure diagnostic was imprecise: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-unset}" ;;
esac

# An owner write failure identifies both the candidate and final destination.
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"
write_failure_path="${TEST_ROOT}/write-failure.reaper"
nvram_transaction_lock_reaper_claim_owner_write() { return 1; }
NVRAM_TRANSACTION_LOCK_DIAGNOSTIC=""
if nvram_transaction_lock_reaper_legacy_claim "${write_failure_path}" "${LOCK_OWNER}"; then
	fail 'claim succeeded after injected owner-file write failure'
fi
case "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" in
	"operation=write-reaper-claim-owner candidate=${write_failure_path}.claim.66816.373949 destination=${write_failure_path} path=${write_failure_path}.claim.66816.373949/pid reason=write-failed owner=${LOCK_OWNER}") ;;
	*) fail "owner-file write failure diagnostic was imprecise: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-unset}" ;;
esac
[ ! -e "${write_failure_path}.claim.66816.373949" ] || fail 'owner write failure left its candidate'

# Owner-file permission failures retain their own stage diagnostic and remove
# every candidate whose owner record still identifies this process.
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"
permission_failure_path="${TEST_ROOT}/permission-failure.reaper"
nvram_transaction_lock_reaper_claim_owner_secure() { return 1; }
NVRAM_TRANSACTION_LOCK_DIAGNOSTIC=""
if nvram_transaction_lock_reaper_legacy_claim "${permission_failure_path}" "${LOCK_OWNER}"; then
	fail 'claim succeeded after injected owner-file permission failure'
fi
case "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" in
	"operation=secure-reaper-claim-owner candidate=${permission_failure_path}.claim.66816.373949 destination=${permission_failure_path} path=${permission_failure_path}.claim.66816.373949/pid reason=permission-failed owner=${LOCK_OWNER}") ;;
	*) fail "owner-file permission failure diagnostic was imprecise: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-unset}" ;;
esac
[ ! -e "${permission_failure_path}.claim.66816.373949" ] || fail 'owner permission failure left its candidate'

# Verification has a distinct diagnostic. A candidate whose owner record was
# changed by another actor must not be removed as though it were still ours.
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"
verification_failure_path="${TEST_ROOT}/verification-failure.reaper"
nvram_transaction_lock_reaper_claim_owner_secure() {
	/bin/chmod 600 "$1/pid" || return 1
	printf '%s\n' '999999999:1' >"$1/pid"
}
NVRAM_TRANSACTION_LOCK_DIAGNOSTIC=""
if nvram_transaction_lock_reaper_legacy_claim "${verification_failure_path}" "${LOCK_OWNER}"; then
	fail 'claim succeeded after injected owner-file verification failure'
fi
case "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" in
	"operation=verify-reaper-claim-owner candidate=${verification_failure_path}.claim.66816.373949 destination=${verification_failure_path} path=${verification_failure_path}.claim.66816.373949/pid reason=owner-verification-failed owner=${LOCK_OWNER}") ;;
	*) fail "owner-file verification failure diagnostic was imprecise: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-unset}" ;;
esac
[ "$(cat "${verification_failure_path}.claim.66816.373949/pid" 2>/dev/null)" = '999999999:1' ] || fail 'verification failure reclaimed a candidate whose owner changed'
rm -rf "${verification_failure_path}.claim.66816.373949"

# Cleanup failures are terminal and identify the candidate, destination, and
# failed operation instead of retaining the preceding owner-write diagnostic.
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"
cleanup_failure_path="${TEST_ROOT}/cleanup-failure.reaper"
nvram_transaction_lock_reaper_claim_owner_write() { return 1; }
nvram_transaction_lock_reaper_claim_remove() { return 1; }
NVRAM_TRANSACTION_LOCK_DIAGNOSTIC=""
if nvram_transaction_lock_reaper_legacy_claim "${cleanup_failure_path}" "${LOCK_OWNER}"; then
	fail 'claim succeeded after injected cleanup failure'
fi
case "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" in
	"operation=cleanup-reaper-claim candidate=${cleanup_failure_path}.claim.66816.373949 destination=${cleanup_failure_path} reason=remove-failed owner=${LOCK_OWNER} after-failed-operation=write-reaper-claim-owner") ;;
	*) fail "candidate cleanup failure diagnostic was imprecise: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-unset}" ;;
esac
rm -rf "${cleanup_failure_path}.claim.66816.373949"

# The publication helper invokes /bin/mv in production. Inject its failure at
# the helper boundary to distinguish a rejected rename from a winning peer.
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"
publish_failure_path="${TEST_ROOT}/publish-failure.reaper"
nvram_transaction_lock_reaper_claim_publish() { return 1; }
NVRAM_TRANSACTION_LOCK_DIAGNOSTIC=""
if nvram_transaction_lock_reaper_legacy_claim "${publish_failure_path}" "${LOCK_OWNER}"; then
	fail 'claim succeeded after injected /bin/mv publication failure'
fi
case "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" in
	"operation=publish-reaper-claim candidate=${publish_failure_path}.claim.66816.373949 destination=${publish_failure_path} reason=rename-rejected owner=${LOCK_OWNER}") ;;
	*) fail "absent-destination publication diagnostic was imprecise: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-unset}" ;;
esac
[ ! -e "${publish_failure_path}.claim.66816.373949" ] || fail 'rejected publication left its candidate'

# A destination appearing while /bin/mv fails is contention, not a filesystem
# rename rejection, and the peer-owned destination must remain untouched.
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"
contender_path="${TEST_ROOT}/contender.reaper"
nvram_transaction_lock_reaper_claim_publish() {
	mkdir "$2" || return 1
	printf '%s\n' '999999999:1' >"$2/pid" || return 1
	return 1
}
NVRAM_TRANSACTION_LOCK_DIAGNOSTIC=""
if nvram_transaction_lock_reaper_legacy_claim "${contender_path}" "${LOCK_OWNER}"; then
	fail 'claim succeeded after competing destination publication'
fi
case "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" in
	"operation=publish-reaper-claim candidate=${contender_path}.claim.66816.373949 destination=${contender_path} reason=contender-published owner=${LOCK_OWNER}") ;;
	*) fail "competing publication diagnostic was imprecise: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-unset}" ;;
esac
[ "$(cat "${contender_path}/pid" 2>/dev/null)" = '999999999:1' ] || fail 'publication failure removed or changed the contender'
[ ! -e "${contender_path}.claim.66816.373949" ] || fail 'contended publication left its current-process candidate'
rm -rf "${contender_path}"

# Restore the production helper boundaries for the acquisition scenarios.
# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"
nvram_transaction_lock_flock_supports_fd() { return 1; }
nvram_transaction_lock_readlink() { return 127; }
sleep() { :; }
nvram_transaction_lock_reaper_claim_mkdir() {
	CLAIM_MKDIR_CALLS="$((CLAIM_MKDIR_CALLS + 1))"
	case "$1" in
		*:*) return 1 ;;
	esac
	/bin/mkdir "$1"
}

# A colliding candidate owned by another live process is never reclaimed; the
# bounded suffix loop must publish through another filename instead.
sleep 30 &
TEST_LIVE_PID=$!
live_start="$(awk '{ print $22 }' "/proc/${TEST_LIVE_PID}/stat")" || fail 'could not read live candidate owner identity'
live_candidate_owner="${TEST_LIVE_PID}:${live_start}"
live_candidate_path="${TEST_ROOT}/live-candidate.reaper"
mkdir "${live_candidate_path}.claim.66816.373949" || fail 'could not create live-owner candidate fixture'
printf '%s\n' "${live_candidate_owner}" >"${live_candidate_path}.claim.66816.373949/pid"
nvram_transaction_lock_reaper_legacy_claim "${live_candidate_path}" "${LOCK_OWNER}" || fail "live-owner candidate blocked bounded recovery: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-missing diagnostic}"
[ "$(cat "${live_candidate_path}.claim.66816.373949/pid" 2>/dev/null)" = "${live_candidate_owner}" ] || fail 'different live owner candidate was reclaimed or changed'
[ "$(cat "${live_candidate_path}/pid" 2>/dev/null)" = "${LOCK_OWNER}" ] || fail 'claim was not published beside live-owner candidate'
rm -rf "${live_candidate_path}" "${live_candidate_path}.claim.66816.373949"
kill "${TEST_LIVE_PID}" 2>/dev/null || true
wait "${TEST_LIVE_PID}" 2>/dev/null || true
TEST_LIVE_PID=""

# This directory represents an older installer paused after mkdir and before
# writing pid. A new installer must not steal its directory while it can resume.
mkdir "${reaper_path}" || fail 'could not create ownerless reaper directory'
if nvram_transaction_lock_reaper_acquire "${reaper_path}" "${LOCK_OWNER}"; then
	fail 'a contender stole a paused legacy owner publication'
fi
[ -d "${reaper_path}" ] || fail 'a contender removed the paused legacy reaper'
printf '%s\n' "${LOCK_OWNER}" >"${reaper_path}/pid" || fail 'paused legacy owner could not resume publication'
[ "$(cat "${reaper_path}/pid" 2>/dev/null)" = "${LOCK_OWNER}" ] || fail 'resumed legacy publication changed owner'
rm -rf "${reaper_path}"

# Dead and PID-reused published owners remain safely reclaimable.
printf '%s\n' 999999999 >"${reaper_path}.stale-owner"
mkdir "${reaper_path}.claim.66816.373949" || fail 'could not create colliding claim artifact'
mkdir "${reaper_path}" || fail 'could not create stale reaper fixture'
mv "${reaper_path}.stale-owner" "${reaper_path}/pid" || fail 'could not publish stale reaper owner'
CLAIM_MKDIR_CALLS=0
nvram_transaction_lock_reaper_acquire "${reaper_path}" "${LOCK_OWNER}" || fail 'stale published owner was not reclaimed'
[ "${CLAIM_MKDIR_CALLS}" -eq 4 ] || fail 'stale-owner reclaim did not keep claim creation to two attempts per publication'
[ "$(cat "${reaper_path}/pid" 2>/dev/null)" = "${LOCK_OWNER}" ] || fail 'reclaimed reaper did not preserve the original owner identity'
nvram_transaction_lock_reaper_release "${reaper_path}" "${LOCK_OWNER}" || fail 'stale reaper was not released'
rm -rf "${reaper_path}.claim.66816.373949" || fail 'could not remove colliding claim fixture'

mkdir "${reaper_path}" || fail 'could not create PID-reuse reaper fixture'
printf '%s:0\n' "$$" >"${reaper_path}/pid" || fail 'could not publish PID-reuse owner'
nvram_transaction_lock_reaper_acquire "${reaper_path}" "${LOCK_OWNER}" || fail 'PID-reused owner was not reclaimed'
nvram_transaction_lock_reaper_release "${reaper_path}" "${LOCK_OWNER}" || fail 'PID-reused reaper was not released'

# Exercise the stale-symlink replacement path with the same filename check.
# nvram_transaction_lock_readlink delegates supported symbolic-link reads to the system command.
nvram_transaction_lock_readlink() {
	[ "$#" -gt 0 ] || return 0
	command readlink "$@"
}
TEMP_SYMLINK_CALLS=0
# nvram_transaction_lock_reaper_temp_symlink_create rejects nonportable temporary symlink names.
nvram_transaction_lock_reaper_temp_symlink_create() {
	TEMP_SYMLINK_CALLS="$((TEMP_SYMLINK_CALLS + 1))"
	case "$2" in
		*:*) return 1 ;;
	esac
	/bin/ln -s "$1" "$2"
}
/bin/ln -s stale-owner "${reaper_path}.symlink" || fail 'could not create stale symlink fixture'
/bin/ln -s "${LOCK_OWNER}" "${reaper_path}.symlink.66816.373949" || fail 'could not create colliding temporary symlink fixture'
nvram_transaction_lock_reaper_acquire "${reaper_path}" "${LOCK_OWNER}" || fail 'stale symlink owner was not reclaimed with a filename-safe artifact'
[ "${TEMP_SYMLINK_CALLS}" -eq 2 ] || fail 'temporary symlink collision did not use exactly two creation attempts'
[ "${NVRAM_TRANSACTION_REAPER_LOCK_MODE:-}" = symlink ] || fail 'stale symlink reclaim did not select symlink locking'
[ "$(cat "${reaper_path}/pid" 2>/dev/null)" = "${LOCK_OWNER}" ] || fail 'symlink reclaim changed the colon-delimited pid owner'
nvram_transaction_lock_reaper_release "${reaper_path}" "${LOCK_OWNER}" || fail 'symlink-backed reaper was not released'
rm -f "${reaper_path}.symlink.66816.373949" || fail 'could not remove colliding temporary symlink fixture'

# Exercise successful descriptor locking when the validation host provides
# flock. The optional router capability still falls back when flock is absent.
if [ -x /usr/bin/flock ]; then
	nvram_transaction_lock_flock_supports_fd() { return 0; }
	mkdir "${reaper_path}.claim.66816.373949" || fail 'could not create flock claim collision fixture'
	nvram_transaction_lock_reaper_acquire "${reaper_path}" "${LOCK_OWNER}" || fail 'flock-backed reaper did not bypass a colliding filename-safe claim'
	[ "${NVRAM_TRANSACTION_REAPER_LOCK_MODE:-}" = flock ] || fail 'descriptor-capable reaper did not select flock locking'
	[ "$(cat "${reaper_path}/pid" 2>/dev/null)" = "${LOCK_OWNER}" ] || fail 'flock-backed reaper changed the colon-delimited pid owner'
	nvram_transaction_lock_reaper_release "${reaper_path}" "${LOCK_OWNER}" || fail 'flock-backed reaper was not released'
	[ -z "${NVRAM_TRANSACTION_REAPER_LOCK_MODE:-}" ] || fail 'flock-backed release retained its lock mode'
	rm -rf "${reaper_path}.claim.66816.373949" || fail 'could not remove flock claim collision fixture'
fi

# Reproduce the reported setup-journal boundary with the complete transaction
# lock path. The simulated filesystem rejects the old colon-bearing claim name.
BASE_DIR="${TEST_ROOT}/setup"
YAML_FILE="${TEST_ROOT}/AdGuardHome.yaml"
YAML_ORI="${TEST_ROOT}/AdGuardHome.yaml.original"
YAML_BAK="${TEST_ROOT}/AdGuardHome.yaml.backup"
CONF_FILE="${TEST_ROOT}/.config"
mkdir -p "${BASE_DIR}" || fail 'could not create setup-journal base directory'
mkdir "${BASE_DIR}/.AdGuardHome.nvram.lock.reaper.claim.66816.373949" || fail 'could not create setup-journal claim collision fixture'
CLAIM_MKDIR_CALLS=0
# nvram_transaction_lock_owner_current returns the deterministic owner identity used by this fixture.
nvram_transaction_lock_owner_current() {
	case "${1:-66816}" in
		66816) printf '%s\n' "${LOCK_OWNER}" ;;
		*) return 1 ;;
	esac
}
# nvram_transaction_lock_readlink reports that symbolic-link inspection is unavailable for this fixture.
nvram_transaction_lock_readlink() { return 127; }
nvram_transaction_setup_files_begin || fail "setup journal lock acquisition failed: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-missing diagnostic}"
[ "${CLAIM_MKDIR_CALLS}" -eq 2 ] || fail 'setup journal claim collision did not use exactly two directory creation attempts'
[ -d "${BASE_DIR}/.AdGuardHome.nvram/setup-files" ] || fail 'setup journal was not published after filename-safe reaper acquisition'
[ "${NVRAM_TRANSACTION_LOCK_MODE:-}" = mkdir ] || fail 'setup journal transaction did not select mkdir locking'
[ "$(cat "${BASE_DIR}/.AdGuardHome.nvram.lock.d/pid" 2>/dev/null)" = "${LOCK_OWNER}" ] || fail 'setup journal lock did not persist the colon-delimited owner identity'
[ -z "${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC:-}" ] || fail "successful setup journal acquisition retained a lock diagnostic: ${NVRAM_TRANSACTION_LOCK_DIAGNOSTIC}"
nvram_transaction_lock_release || fail 'setup journal transaction lock was not released'
[ ! -e "${BASE_DIR}/.AdGuardHome.nvram.lock.d" ] || fail 'setup journal transaction lock remained after release'
rm -rf "${BASE_DIR}/.AdGuardHome.nvram.lock.reaper.claim.66816.373949" || fail 'could not remove setup-journal claim collision fixture'

if /usr/bin/find "${TEST_ROOT}" \( -name '*.claim.*' -o -name '*.symlink.*' \) -print | /bin/grep -q .; then
	fail 'temporary reaper publication artifacts remained after release'
fi

printf '%s\n' 'PASS: mkdir reaper preserves paused legacy publishers and reclaims verified stale owners'
