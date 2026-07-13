#!/bin/sh
# Verify preflight action routing stays flow-aware for Entware and jq checks.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-preflight-actions.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions"

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

sed -n '/^preflight_action_requires_entware() {$/,/^preflight_check_path() {$/p' "${SCRIPT_PATH}" | sed '$d' >"${FUNCTIONS_FILE}" ||
	fail 'could not extract preflight action helpers'
[ -s "${FUNCTIONS_FILE}" ] || fail 'preflight action helper extraction was empty'

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
grep -q 'preflight_check_router_eligibility || failed="1"' "${SCRIPT_PATH}" ||
	fail 'preflight must check router eligibility for actionable flows'
grep -q 'preflight_check_entware_package coreutils-sha256sum' "${SCRIPT_PATH}" ||
	fail 'preflight must report coreutils-sha256sum install guidance when SHA-256 support is missing'
grep -q 'preflight.entware.password_hash.install_hint=opkg install python3 python3-bcrypt' "${SCRIPT_PATH}" ||
	fail 'preflight must report password hashing package guidance'
grep -q 'preflight_check_entware_package column' "${SCRIPT_PATH}" ||
	fail 'preflight must check the Entware column package when timezone selection needs it'

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

	assert_timezone_column_required() {
		local action
		for action in "$@"; do
			if ! preflight_action_requires_timezone_column "${action}"; then
				printf '%s\n' "expected timezone column requirement for action: ${action}" >&2
				exit 1
			fi
		done
	}

	assert_entware_required '' install update reconfigure restore uninstall ipset backup doctor netcheck dns-port-policy performance migrate-runtime-defaults
	assert_router_eligibility_required '' install update reconfigure restore uninstall ipset backup doctor netcheck dns-port-policy performance migrate-runtime-defaults
	assert_router_eligibility_skipped status preflight
	assert_entware_skipped status preflight
	assert_jq_skipped '' install update reconfigure restore uninstall ipset backup doctor status preflight netcheck dns-port-policy performance migrate-runtime-defaults
	assert_sha256_required '' install update restore blocklists unusedblocklists 9
	assert_password_hash_required '' install reconfigure changepw 3 4
	assert_timezone_column_required '' install reconfigure restore 4
) || fail 'preflight action helper returned an unexpected result'

printf '%s\n' 'PASS: preflight action routing keeps Entware and jq checks flow-aware'
