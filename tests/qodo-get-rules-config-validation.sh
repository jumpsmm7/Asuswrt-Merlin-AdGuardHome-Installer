#!/bin/sh
# Regression test for the qodo-get-rules config parser. The canonical logic is
# tracked in config-parsing.sh; the Markdown example is checked for drift and is
# never executed directly.

set -u

SKILL='.agents/skills/qodo-get-rules/SKILL.md'
CANONICAL='.agents/skills/qodo-get-rules/config-parsing.sh'
SEARCH_ENDPOINT='.agents/skills/qodo-get-rules/references/search-endpoint.md'
REPO_SCOPE='.agents/skills/qodo-get-rules/references/repository-scope.md'

fail() {
	printf '%s\n' "FAIL: $1" >&2
	exit 1
}

for f in "${SKILL}" "${CANONICAL}" "${SEARCH_ENDPOINT}" "${REPO_SCOPE}"; do
	[ -f "${f}" ] || fail "expected skill file not found: ${f}"
done

TMP_ROOT="${TMPDIR:-/tmp}/qodo-get-rules-config-validation.$$"
mkdir -p "${TMP_ROOT}" || fail 'unable to create temp workspace'
trap 'rm -rf "${TMP_ROOT}"' EXIT
trap 'rm -rf "${TMP_ROOT}"; exit 1' HUP INT TERM

SNIPPET="${TMP_ROOT}/config-parsing.sh"

# Verify the documented example remains synchronized with the canonical script.
awk '
	/^Example config parsing:$/ { found = 1 }
	found && /^```bash$/ { incode = 1; next }
	incode && /^```$/ { exit }
	incode { print }
' "${SKILL}" >"${SNIPPET}"
cmp -s "${CANONICAL}" "${SNIPPET}" || fail 'SKILL.md config-parsing snippet differs from the canonical script'

# run_snippet executes only the tracked canonical script with an isolated HOME
# and an explicit, minimal environment.
run_snippet() {
	_home="$1"
	shift
	env -i HOME="${_home}" PATH="${PATH}" "$@" sh -c '. "$1"; printf "RESULT|%s|%s|%s\n" "${API_KEY}" "${ENV_NAME}" "${API_URL}"' sh "${CANONICAL}"
}

make_config() {
	# usage: make_config <home_dir> <json_body> <dir_mode> <file_mode>
	_home="$1"
	_json="$2"
	_dir_mode="$3"
	_file_mode="$4"
	mkdir -p "${_home}/.qodo" || fail 'unable to create fixture .qodo directory'
	printf '%s' "${_json}" >"${_home}/.qodo/config.json" || fail 'unable to write fixture config.json'
	chmod "${_dir_mode}" "${_home}/.qodo" || fail 'unable to chmod fixture .qodo directory'
	chmod "${_file_mode}" "${_home}/.qodo/config.json" || fail 'unable to chmod fixture config.json'
}

assert_success() {
	_label="$1"
	_rc="$2"
	_out="$3"
	[ "${_rc}" -eq 0 ] || fail "${_label}: expected success, got exit ${_rc}, output: ${_out}"
}

assert_failure() {
	_label="$1"
	_rc="$2"
	_out="$3"
	_needle="$4"
	[ "${_rc}" -ne 0 ] || fail "${_label}: expected failure, but snippet exited 0"
	printf '%s\n' "${_out}" | grep -Fq "${_needle}" || fail "${_label}: expected output to contain '${_needle}', got: ${_out}"
}

extract_result_field() {
	# usage: extract_result_field <output> <field-number 1..3>
	printf '%s\n' "$1" | grep '^RESULT|' | tail -n1 | cut -d'|' -f "$(($2 + 1))"
}

# --- Scenario: no config file, no env vars -> missing API key is a hard failure.
HOME_NO_KEY="${TMP_ROOT}/home-no-key"
mkdir -p "${HOME_NO_KEY}" || fail 'unable to create home-no-key fixture'
OUT=$(run_snippet "${HOME_NO_KEY}" 2>&1)
RC=$?
assert_failure 'no config, no env' "${RC}" "${OUT}" 'Qodo API key not found'

# --- Scenario: QODO_API_KEY via env only, no config file -> succeeds with the
# production default API URL.
HOME_ENV_KEY="${TMP_ROOT}/home-env-key"
mkdir -p "${HOME_ENV_KEY}" || fail 'unable to create home-env-key fixture'
OUT=$(run_snippet "${HOME_ENV_KEY}" QODO_API_KEY=env-only-key 2>&1)
RC=$?
assert_success 'env API key only' "${RC}" "${OUT}"
[ "$(extract_result_field "${OUT}" 1)" = 'env-only-key' ] || fail "env API key only: unexpected API_KEY in result: ${OUT}"
[ "$(extract_result_field "${OUT}" 3)" = 'https://qodo-platform.qodo.ai/rules/v1' ] || fail "env API key only: unexpected default API_URL: ${OUT}"

# --- Scenario: well-formed, correctly-permissioned config file supplies API key
# and environment name; API_URL is derived from ENVIRONMENT_NAME.
HOME_CONFIG_OK="${TMP_ROOT}/home-config-ok"
mkdir -p "${HOME_CONFIG_OK}" || fail 'unable to create home-config-ok fixture'
make_config "${HOME_CONFIG_OK}" '{"API_KEY": "cfg-key", "ENVIRONMENT_NAME": "staging"}' 700 600
OUT=$(run_snippet "${HOME_CONFIG_OK}" 2>&1)
RC=$?
assert_success 'valid config file' "${RC}" "${OUT}"
[ "$(extract_result_field "${OUT}" 1)" = 'cfg-key' ] || fail "valid config file: unexpected API_KEY in result: ${OUT}"
[ "$(extract_result_field "${OUT}" 3)" = 'https://qodo-platform.staging.qodo.ai/rules/v1' ] || fail "valid config file: unexpected staging API_URL: ${OUT}"

# --- Scenario: env QODO_API_KEY takes precedence over a config file value.
HOME_PRECEDENCE="${TMP_ROOT}/home-precedence"
mkdir -p "${HOME_PRECEDENCE}" || fail 'unable to create home-precedence fixture'
make_config "${HOME_PRECEDENCE}" '{"API_KEY": "cfg-key", "ENVIRONMENT_NAME": "staging"}' 700 600
OUT=$(run_snippet "${HOME_PRECEDENCE}" QODO_API_KEY=env-wins 2>&1)
RC=$?
assert_success 'env key precedence' "${RC}" "${OUT}"
[ "$(extract_result_field "${OUT}" 1)" = 'env-wins' ] || fail "env key precedence: env QODO_API_KEY did not take precedence over config: ${OUT}"

# --- Scenario: world-readable config directory (not mode 700) is rejected when
# any of the three env-only settings is missing.
HOME_BAD_DIR="${TMP_ROOT}/home-bad-dir"
mkdir -p "${HOME_BAD_DIR}" || fail 'unable to create home-bad-dir fixture'
make_config "${HOME_BAD_DIR}" '{"API_KEY": "cfg-key"}' 755 600
OUT=$(run_snippet "${HOME_BAD_DIR}" 2>&1)
RC=$?
assert_failure 'insecure config directory' "${RC}" "${OUT}" 'must have mode 700'

# --- Scenario: world-readable config file (not mode 600) is rejected even when
# the directory permissions are correct.
HOME_BAD_FILE="${TMP_ROOT}/home-bad-file"
mkdir -p "${HOME_BAD_FILE}" || fail 'unable to create home-bad-file fixture'
make_config "${HOME_BAD_FILE}" '{"API_KEY": "cfg-key"}' 700 644
OUT=$(run_snippet "${HOME_BAD_FILE}" 2>&1)
RC=$?
assert_failure 'insecure config file' "${RC}" "${OUT}" 'must have mode 600'

# --- Scenario: when QODO_API_KEY, QODO_ENVIRONMENT_NAME, and QODO_API_URL are all
# supplied via the environment, the (unrelated/legacy) config file's permissions
# must NOT block startup, since it is never consulted.
HOME_FULL_ENV="${TMP_ROOT}/home-full-env"
mkdir -p "${HOME_FULL_ENV}" || fail 'unable to create home-full-env fixture'
make_config "${HOME_FULL_ENV}" '{"API_KEY": "cfg-key"}' 755 644
OUT=$(run_snippet "${HOME_FULL_ENV}" QODO_API_KEY=env-key QODO_ENVIRONMENT_NAME=prod QODO_API_URL=https://qodo-platform.qodo.ai 2>&1)
RC=$?
assert_success 'full env bypasses insecure config perms' "${RC}" "${OUT}"
[ "$(extract_result_field "${OUT}" 1)" = 'env-key' ] || fail "full env bypasses insecure config perms: unexpected API_KEY: ${OUT}"

# --- Scenario: malformed JSON config file surfaces a clear error instead of an
# unhandled interpreter traceback.
HOME_BAD_JSON="${TMP_ROOT}/home-bad-json"
mkdir -p "${HOME_BAD_JSON}" || fail 'unable to create home-bad-json fixture'
make_config "${HOME_BAD_JSON}" '{not valid json' 700 600
OUT=$(run_snippet "${HOME_BAD_JSON}" 2>&1)
RC=$?
assert_failure 'malformed config JSON' "${RC}" "${OUT}" 'Fix or remove the invalid Qodo configuration file'

# --- Scenario: QODO_API_URL env var rejects a plain non-Qodo HTTPS domain.
HOME_URL="${TMP_ROOT}/home-url"
mkdir -p "${HOME_URL}" || fail 'unable to create home-url fixture'
OUT=$(run_snippet "${HOME_URL}" QODO_API_KEY=k QODO_API_URL=https://evil.example.com 2>&1)
RC=$?
assert_failure 'non-qodo domain rejected' "${RC}" "${OUT}" 'Invalid QODO_API_URL'

# --- Scenario: QODO_API_URL rejects a domain-suffix spoof (qodo.ai as a prefix of
# an attacker-controlled domain, e.g. "qodo.ai.evil.com").
OUT=$(run_snippet "${HOME_URL}" QODO_API_KEY=k QODO_API_URL=https://qodo.ai.evil.com 2>&1)
RC=$?
assert_failure 'domain-suffix spoof rejected' "${RC}" "${OUT}" 'Invalid QODO_API_URL'

# --- Scenario: QODO_API_URL rejects a userinfo spoof (qodo.ai before an "@",
# with the real host being attacker-controlled).
OUT=$(run_snippet "${HOME_URL}" QODO_API_KEY=k QODO_API_URL=https://qodo.ai@evil.example.com 2>&1)
RC=$?
assert_failure 'userinfo spoof rejected' "${RC}" "${OUT}" 'Invalid QODO_API_URL'

# --- Scenario: QODO_API_URL rejects plain HTTP even against a trusted domain.
OUT=$(run_snippet "${HOME_URL}" QODO_API_KEY=k QODO_API_URL=http://qodo-platform.qodo.ai 2>&1)
RC=$?
assert_failure 'plain http rejected' "${RC}" "${OUT}" 'Invalid QODO_API_URL'

# --- Scenario: QODO_API_URL accepts a multi-level trusted subdomain and strips a
# trailing slash before appending /rules/v1 (no double slash).
OUT=$(run_snippet "${HOME_URL}" QODO_API_KEY=k QODO_API_URL=https://a.b.qodo.ai/ 2>&1)
RC=$?
assert_success 'multi-level trusted subdomain with trailing slash' "${RC}" "${OUT}"
[ "$(extract_result_field "${OUT}" 3)" = 'https://a.b.qodo.ai/rules/v1' ] || fail "multi-level trusted subdomain with trailing slash: unexpected API_URL: ${OUT}"

# --- Scenario: QODO_ENVIRONMENT_NAME rejects shell metacharacters / injection
# attempts before they are ever used to build a URL.
OUT=$(run_snippet "${HOME_URL}" QODO_API_KEY=k QODO_ENVIRONMENT_NAME='staging;rm -rf /' 2>&1)
RC=$?
assert_failure 'invalid environment name rejected' "${RC}" "${OUT}" 'Invalid ENVIRONMENT_NAME'

# --- Scenario: a valid QODO_ENVIRONMENT_NAME is used verbatim to build the URL.
OUT=$(run_snippet "${HOME_URL}" QODO_API_KEY=k QODO_ENVIRONMENT_NAME=qodost.st 2>&1)
RC=$?
assert_success 'valid environment name' "${RC}" "${OUT}"
[ "$(extract_result_field "${OUT}" 3)" = 'https://qodo-platform.qodost.st.qodo.ai/rules/v1' ] || fail "valid environment name: unexpected API_URL: ${OUT}"

# --- Scenario: QODO_API_URL env var takes precedence over a config-file
# QODO_API_URL value, even though both are individually valid.
HOME_URL_PRECEDENCE="${TMP_ROOT}/home-url-precedence"
mkdir -p "${HOME_URL_PRECEDENCE}" || fail 'unable to create home-url-precedence fixture'
make_config "${HOME_URL_PRECEDENCE}" '{"API_KEY": "cfg-key", "QODO_API_URL": "https://config-value.qodo.ai"}' 700 600
OUT=$(run_snippet "${HOME_URL_PRECEDENCE}" QODO_API_URL=https://env-value.qodo.ai 2>&1)
RC=$?
assert_success 'env QODO_API_URL precedence' "${RC}" "${OUT}"
[ "$(extract_result_field "${OUT}" 3)" = 'https://env-value.qodo.ai/rules/v1' ] || fail "env QODO_API_URL precedence: config value was used instead of env value: ${OUT}"

# --- Cross-file consistency: the TOP_K positive-integer validation regex shown in
# search-endpoint.md's curl and Python examples must actually reject non-positive
# and non-numeric values and accept positive integers, in both places it appears.
TOP_K_OCCURRENCES=$(grep -c "grep -Eq '\^\[1-9\]\[0-9\]\*\\\$'" "${SEARCH_ENDPOINT}")
[ "${TOP_K_OCCURRENCES}" -ge 2 ] || fail "search-endpoint.md: expected the TOP_K validation regex to appear at least twice (curl and Python examples), found ${TOP_K_OCCURRENCES}"

for good in 1 20 100 999; do
	printf '%s\n' "${good}" | grep -Eq '^[1-9][0-9]*$' || fail "TOP_K regex unexpectedly rejected valid value: ${good}"
done
for bad in 0 -5 007 abc '' '20.5' ' 20'; do
	if printf '%s\n' "${bad}" | grep -Eq '^[1-9][0-9]*$'; then
		fail "TOP_K regex unexpectedly accepted invalid value: '${bad}'"
	fi
done

# --- Cross-file consistency: the "never send scopes: null / scopes: []" rule must
# be stated consistently across the skill and both reference docs that describe
# the search request body, so a future edit to one copy can't silently diverge.
for f in "${SKILL}" "${SEARCH_ENDPOINT}" "${REPO_SCOPE}"; do
	grep -Fq '"scopes": null' "${f}" || fail "${f}: missing the 'do not send scopes: null' guidance"
	grep -Fq '"scopes": []' "${f}" || fail "${f}: missing the 'do not send scopes: []' guidance"
done

printf '%s\n' 'PASS: qodo-get-rules config parsing snippet enforces credential/URL validation as documented'
