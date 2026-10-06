#!/bin/sh
# Verify option 6 saves its preference and invokes the installed cache manager.

set -u

SCRIPT_PATH="${1:-installer}"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"

CHECK_DNS_LOCAL_FUNCTION="$(sed -n '/^check_dns_local() {$/,/^}$/p' "${SCRIPT_PATH}")"
MENU_FUNCTION="$(sed -n '/^menu() {$/,/^read_input_dns() {$/p' "${SCRIPT_PATH}" | sed '$d')"

[ -n "${CHECK_DNS_LOCAL_FUNCTION}" ] || fail 'could not extract check_dns_local function'
[ -n "${MENU_FUNCTION}" ] || fail 'could not extract menu function'

eval "${CHECK_DNS_LOCAL_FUNCTION}"
eval "${MENU_FUNCTION}"

INFO='Info:'
ERROR='Error:'
TARG_DIR='/tmp/unused'
AGH_FILE='/tmp/unused/AdGuardHome'
BASE_DIR='/tmp/unused'
HOME='/tmp/unused'
SCRIPT_LOC='/tmp/unused/installer'
BRANCH='test'

for ANSWER in yes no; do
	LOG="${TMPDIR:-/tmp}/installer-local-cache-save-failure.${ANSWER}.$$"
	END_LOG="${LOG}.end"
	: >"${LOG}"
	: >"${END_LOG}"

	nvram() {
		[ "$1:${2:-}" = 'get:dns_local_cache' ] && printf '%s\n' '0'
	}
	read_yesno() {
		[ "${ANSWER}" = 'yes' ]
	}
	write_conf() {
		return 1
	}
	PTXT() {
		printf '%s\n' "$*" >>"${LOG}"
	}
	end_op_message() {
		printf '%s\n' "$1" >>"${END_LOG}"
	}

	if menu setlocalcache; then
		fail "option 6 succeeded after the ${ANSWER} preference failed to save"
	fi
	[ "$(cat "${END_LOG}")" = '1' ] || fail "option 6 did not report an aborted operation after the ${ANSWER} preference failed to save"
	grep -q 'Unable to save the AdGuardHome local cache setting' "${LOG}" || fail "option 6 did not explain the ${ANSWER} preference save failure"
	if grep -q 'please reboot the router' "${LOG}"; then
		fail "option 6 recommended a reboot after the ${ANSWER} preference failed to save"
	fi

	rm -f "${LOG}" "${END_LOG}"
done

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/installer-local-cache-activation.XXXXXX")" || fail 'could not create activation fixture'
trap 'rm -rf "${TEST_ROOT}"' EXIT HUP INT TERM
ADDON_DIR="${TEST_ROOT}/addon"
TARG_DIR="${TEST_ROOT}/work"
mkdir -p "${ADDON_DIR}" "${TARG_DIR}" || fail 'could not create fixture directories'
MANAGER_LOG="${TEST_ROOT}/manager-calls"
export MANAGER_LOG
cat >"${ADDON_DIR}/AdGuardHome.sh" <<'MANAGER'
#!/bin/sh
printf '%s\n' "$*" >>"${MANAGER_LOG}"
exit "${MANAGER_STATUS:-0}"
MANAGER
chmod 755 "${ADDON_DIR}/AdGuardHome.sh" || fail 'could not make manager executable'
# There is intentionally no manager at TARG_DIR: installations use ADDON_DIR.
for ANSWER in yes no; do
	for MANAGER_STATUS in 0 1; do
		export MANAGER_STATUS
		LOG="${TEST_ROOT}/menu-log"
		END_LOG="${TEST_ROOT}/end-log"
		: >"${LOG}"
		: >"${END_LOG}"
		: >"${MANAGER_LOG}"
		write_conf() { printf '%s=%s\n' "$1" "$2" >"${TARG_DIR}/.config"; }
		menu setlocalcache || fail 'saved preference did not finish successfully'
		[ "$(cat "${MANAGER_LOG}")" = 'local-cache x' ] || fail 'option 6 did not invoke the installed manager'
		[ "$(cat "${END_LOG}")" = 0 ] || fail 'saved preference was treated as an aborted operation'
		case "${ANSWER}" in yes) saved=YES ;; no) saved=NO ;; esac
		grep -qx "ADGUARD_LOCAL=\"${saved}\"" "${TARG_DIR}/.config" || fail 'option 6 saved the wrong preference'
		if [ "${MANAGER_STATUS}" -eq 1 ]; then
			grep -q 'activation is deferred' "${LOG}" || fail 'manager failure did not explain deferred activation'
		elif grep -q 'activation is deferred' "${LOG}"; then
			fail 'healthy manager invocation reported deferred activation'
		fi
	done
done
printf '%s\n' 'PASS: option 6 save failures, installed-manager activation and readiness deferral'
