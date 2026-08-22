#!/bin/sh
# Verify BusyBox shell syntax, router command policy, and optional flock fallback enforcement.

set -u

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)" || exit 1
CHECKER="${ROOT_DIR}/tools/check-shell-portability.sh"
FIXTURES="${ROOT_DIR}/tests/fixtures/portability"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/shell-portability-policy.XXXXXX")" || exit 1

# cleanup removes the private policy-test workspace.
cleanup() { rm -rf "${TEST_ROOT}"; }

# fail reports a policy regression.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

# check_rejected requires the checker to reject one negative fixture.
check_rejected() {
	fixture="$1"
	case "${fixture##*/}" in
		runtime-* | *flock*.sh)
			cp "${fixture}" "${TEST_ROOT}/AdGuardHome.sh" || return 1
			checked_file="${TEST_ROOT}/AdGuardHome.sh"
			;;
		*) checked_file="${fixture}" ;;
	esac
	if (cd "${ROOT_DIR}" && sh "${CHECKER}" "${checked_file}") >"${TEST_ROOT}/reject.out" 2>&1; then
		fail "checker accepted failing fixture ${fixture##*/}"
	fi
}

for fixture in "${FIXTURES}"/fail/*.sh; do
	check_rejected "${fixture}"
done

for fixture in "${FIXTURES}"/pass/*.sh; do
	case "${fixture##*/}" in
		approved-python3.sh)
			cp "${fixture}" "${TEST_ROOT}/installer" || fail 'could not stage approved Python fixture'
			checked_file="${TEST_ROOT}/installer"
			;;
		flock-fallback.sh)
			cp "${fixture}" "${TEST_ROOT}/AdGuardHome.sh" || fail 'could not stage flock fallback fixture'
			checked_file="${TEST_ROOT}/AdGuardHome.sh"
			;;
		*) checked_file="${fixture}" ;;
	esac
	(cd "${ROOT_DIR}" && sh "${CHECKER}" "${checked_file}") >/dev/null 2>&1 ||
		fail "checker rejected passing fixture ${fixture##*/}"
done

# The existing behavioral suite exercises compatible flock, missing flock,
# incompatible descriptor locking, acquisition failure, live/stale fallback
# ownership, PID identity validation, cleanup, and bounded lock attempts.
(cd "${ROOT_DIR}" && sh tests/ipset-lock-security.sh) >"${TEST_ROOT}/flock.out" 2>&1 || {
	cat "${TEST_ROOT}/flock.out" >&2
	fail 'optional flock and mkdir/PID fallback behavior regressed'
}
grep -q '^PASS:' "${TEST_ROOT}/flock.out" || fail 'flock fallback behavior did not report completion'

(cd "${ROOT_DIR}" && sh "${CHECKER}") >/dev/null || fail 'repository shell scripts violate the portability policy'
printf '%s\n' 'PASS: router command and BusyBox portability policy rejects unsupported constructs without embedded-language false positives'
