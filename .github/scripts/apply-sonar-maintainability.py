from pathlib import Path


def replace_one(path, old, new):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one match, found {count}: {old!r}")
    p.write_text(text.replace(old, new, 1))


# Keep Sonar active on tests, but suppress four maintainability-only rules whose
# prescribed rewrites alter or obscure test-double semantics.
path = Path("sonar-project.properties")
text = path.read_text()
old = "sonar.issue.ignore.multicriteria=e1,e2,e3,e4\n"
new = "sonar.issue.ignore.multicriteria=e1,e2,e3,e4,e5,e6,e7,e8\n"
if text.count(old) != 1:
    raise SystemExit("sonar-project.properties: multicriteria list did not match expected state")
text = text.replace(old, new, 1)
text += (
    "\n# Test doubles intentionally preserve production symbol names, controlled case\n"
    "# domains, positional-parameter fixtures, and last-command status semantics.\n"
    "# Suppress only these four maintainability rules in tests; all other\n"
    "# maintainability, reliability, and security rules remain active.\n"
    "sonar.issue.ignore.multicriteria.e5.ruleKey=shelldre:S7682\n"
    "sonar.issue.ignore.multicriteria.e5.resourceKey=tests/**\n"
    "sonar.issue.ignore.multicriteria.e6.ruleKey=shelldre:S7679\n"
    "sonar.issue.ignore.multicriteria.e6.resourceKey=tests/**\n"
    "sonar.issue.ignore.multicriteria.e7.ruleKey=shelldre:S131\n"
    "sonar.issue.ignore.multicriteria.e7.resourceKey=tests/**\n"
    "sonar.issue.ignore.multicriteria.e8.ruleKey=shelldre:S100\n"
    "sonar.issue.ignore.multicriteria.e8.resourceKey=tests/**\n"
)
path.write_text(text)

# Downloader: name the HTTPS-only protocol value and make checksum validation
# exhaustive without changing accepted values.
replace_one(
    "tools/download-adguardhome-static.sh",
    'BASE_URL="https://static.adguard.com/adguardhome"\nOUT_DIR="${1:-.}"',
    'BASE_URL="https://static.adguard.com/adguardhome"\nHTTPS_PROTOCOL="=https"\nOUT_DIR="${1:-.}"',
)
p = Path("tools/download-adguardhome-static.sh")
text = p.read_text()
old = "--proto '=https' --proto-redir '=https'"
count = text.count(old)
if count != 2:
    raise SystemExit(
        "tools/download-adguardhome-static.sh: expected two HTTPS protocol "
        f"option pairs, found {count}"
    )
text = text.replace(
    old, '--proto "${HTTPS_PROTOCOL}" --proto-redir "${HTTPS_PROTOCOL}"'
)
p.write_text(text)
replace_one(
    "tools/download-adguardhome-static.sh",
    'case "${_sum_value}" in\n\t\t*[!0123456789abcdefABCDEF]*) return 1 ;;\n\tesac',
    'case "${_sum_value}" in\n\t\t*[!0123456789abcdefABCDEF]*) return 1 ;;\n\t\t*) : ;;\n\tesac',
)

# Code-quality runner: make validation cases exhaustive and flatten a redundant
# nested branch while preserving status behavior.
replace_one(
    "tools/code-quality.sh",
    'case "${_timeout_version}" in\n\t\ttimeout\\ \\(GNU\\ coreutils\\)*) return 0 ;;\n\tesac',
    'case "${_timeout_version}" in\n\t\ttimeout\\ \\(GNU\\ coreutils\\)*) return 0 ;;\n\t\t*) : ;;\n\tesac',
)
replace_one(
    "tools/code-quality.sh",
    'while IFS= read -r _script; do\n\t\tif [ -n "${_script}" ]; then\n\t\t\tif ! run_test_command "$@" "${_script}"; then\n\t\t\t\t_check_failed=1\n\t\t\tfi\n\t\tfi\n\tdone <"${SCRIPT_LIST}"',
    'while IFS= read -r _script; do\n\t\tif [ -n "${_script}" ] && ! run_test_command "$@" "${_script}"; then\n\t\t\t_check_failed=1\n\t\tfi\n\tdone <"${SCRIPT_LIST}"',
)
replace_one(
    "tools/code-quality.sh",
    "case \"${TEST_MAX_RUNTIME_SECONDS}\" in\n\t'' | *[!0-9]*)\n\t\tprintf '%s\\n' 'Error: TEST_MAX_RUNTIME_SECONDS must be a non-negative integer.' >&2\n\t\texit 2\n\t\t;;\nesac",
    "case \"${TEST_MAX_RUNTIME_SECONDS}\" in\n\t'' | *[!0-9]*)\n\t\tprintf '%s\\n' 'Error: TEST_MAX_RUNTIME_SECONDS must be a non-negative integer.' >&2\n\t\texit 2\n\t\t;;\n\t*) : ;;\nesac",
)

# Release consistency: make helper status explicit, bind positional parameters
# once, make one-sided cases exhaustive, and flatten the Git availability check.
replace_one(
    "tools/check-release-consistency.sh",
    "fail() {\n\tprintf '%s\\n' \"Error: $1\" >&2\n\tFAILED=1\n}",
    "fail() {\n\tlocal _message\n\t_message=\"$1\"\n\tprintf '%s\\n' \"Error: ${_message}\" >&2\n\tFAILED=1\n\treturn 0\n}",
)
replace_one(
    "tools/check-release-consistency.sh",
    "manifest_value() {\n\tawk 'NF { value = $1; count++; if (NF != 1) invalid = 1 }\n\t\tEND { if (count != 1 || invalid) exit 1; print value }' \"$1\"\n}",
    "manifest_value() {\n\tlocal _manifest\n\t_manifest=\"$1\"\n\tawk 'NF { value = $1; count++; if (NF != 1) invalid = 1 }\n\t\tEND { if (count != 1 || invalid) exit 1; print value }' \"${_manifest}\"\n\treturn $?\n}",
)
for old, new in [
    (
        'case "${_file}" in\n\t\t\t\'\' | \\#*) continue ;;\n\t\tesac',
        'case "${_file}" in\n\t\t\t\'\' | \\#*) continue ;;\n\t\t\t*) : ;;\n\t\tesac',
    ),
    (
        'case " ${_seen_channels} " in\n\t\t\t*" ${_channel} "*)\n\t\t\t\tfail "duplicate ${_channel} channel in ${_channel_file}"\n\t\t\t\tcontinue\n\t\t\t\t;;\n\t\tesac',
        'case " ${_seen_channels} " in\n\t\t\t*" ${_channel} "*)\n\t\t\t\tfail "duplicate ${_channel} channel in ${_channel_file}"\n\t\t\t\tcontinue\n\t\t\t\t;;\n\t\t\t*) : ;;\n\t\tesac',
    ),
    (
        '\t\t\tedge)\n\t\t\t\tif [ -z "${EXPECTED_EDGE_VERSION}" ]; then\n\t\t\t\t\tEXPECTED_EDGE_VERSION="${_version}"\n\t\t\t\telif [ "${EXPECTED_EDGE_VERSION}" != "${_version}" ]; then\n\t\t\t\t\tfail "edge channel version differs in ${_channel_file}: expected ${EXPECTED_EDGE_VERSION}, actual ${_version}"\n\t\t\t\tfi\n\t\t\t\t;;\n\t\tesac',
        '\t\t\tedge)\n\t\t\t\tif [ -z "${EXPECTED_EDGE_VERSION}" ]; then\n\t\t\t\t\tEXPECTED_EDGE_VERSION="${_version}"\n\t\t\t\telif [ "${EXPECTED_EDGE_VERSION}" != "${_version}" ]; then\n\t\t\t\t\tfail "edge channel version differs in ${_channel_file}: expected ${EXPECTED_EDGE_VERSION}, actual ${_version}"\n\t\t\t\tfi\n\t\t\t\t;;\n\t\t\t*) : ;;\n\t\tesac',
    ),
    (
        'case "${_md5}" in *[!0123456789abcdefABCDEF]*)\n\t\t\tfail "invalid MD5 in ${_channel_file} for ${_file}"\n\t\t\tcontinue\n\t\t\t;;\n\t\tesac',
        'case "${_md5}" in\n\t\t\t*[!0123456789abcdefABCDEF]*)\n\t\t\t\tfail "invalid MD5 in ${_channel_file} for ${_file}"\n\t\t\t\tcontinue\n\t\t\t\t;;\n\t\t\t*) : ;;\n\t\tesac',
    ),
    (
        'case "${_sha256}" in *[!0123456789abcdefABCDEF]*)\n\t\t\tfail "invalid SHA-256 in ${_channel_file} for ${_file}"\n\t\t\tcontinue\n\t\t\t;;\n\t\tesac',
        'case "${_sha256}" in\n\t\t\t*[!0123456789abcdefABCDEF]*)\n\t\t\t\tfail "invalid SHA-256 in ${_channel_file} for ${_file}"\n\t\t\t\tcontinue\n\t\t\t\t;;\n\t\t\t*) : ;;\n\t\tesac',
    ),
]:
    replace_one("tools/check-release-consistency.sh", old, new)
replace_one(
    "tools/check-release-consistency.sh",
    'if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then\n\tif git rev-parse --verify "${RELEASE_BASE:-HEAD^}" >/dev/null 2>&1; then\n\t\tRELEASE_BASE_RESOLVED="$(git rev-parse --verify "${RELEASE_BASE:-HEAD^}")"\n\tfi\nfi',
    'if git rev-parse --is-inside-work-tree >/dev/null 2>&1 &&\n\tgit rev-parse --verify "${RELEASE_BASE:-HEAD^}" >/dev/null 2>&1; then\n\tRELEASE_BASE_RESOLVED="$(git rev-parse --verify "${RELEASE_BASE:-HEAD^}")"\nfi',
)

# Qodo config parser: bind the path parameter once, flatten the jq availability
# check, and make validation cases explicit.
replace_one(
    ".agents/skills/qodo-get-rules/config-parsing.sh",
    'config_mode() {\n\tlocal mode\n\tif mode=$(stat -c \'%a\' "$1" 2>/dev/null); then\n\t\tprintf \'%s\\n\' "${mode}"\n\telif mode=$(stat -f \'%Lp\' "$1" 2>/dev/null); then\n\t\tprintf \'%s\\n\' "${mode}"\n\telse\n\t\tprintf \'%s\\n\' "Error: unable to read permission mode for $1" >&2\n\t\treturn 1\n\tfi\n}',
    'config_mode() {\n\tlocal config_path mode\n\tconfig_path="$1"\n\tif mode=$(stat -c \'%a\' "${config_path}" 2>/dev/null); then\n\t\tprintf \'%s\\n\' "${mode}"\n\telif mode=$(stat -f \'%Lp\' "${config_path}" 2>/dev/null); then\n\t\tprintf \'%s\\n\' "${mode}"\n\telse\n\t\tprintf \'%s\\n\' "Error: unable to read permission mode for ${config_path}" >&2\n\t\treturn 1\n\tfi\n}',
)
replace_one(
    ".agents/skills/qodo-get-rules/config-parsing.sh",
    '\tif [ "${CONFIG_USABLE}" -eq 1 ]; then\n\t\t# Require jq for robust JSON parsing\n\t\tif ! which jq >/dev/null 2>&1; then\n\t\t\tif [ "${CONFIG_REQUIRED}" -eq 1 ]; then\n\t\t\t\tprintf \'%s\\n\' "Error: jq is required to parse ${CONFIG_FILE}. Install jq or use environment variables (QODO_API_KEY, QODO_ENVIRONMENT_NAME, QODO_API_URL)." >&2\n\t\t\t\texit 1\n\t\t\tfi\n\t\t\tCONFIG_USABLE=0\n\t\tfi\n\tfi',
    '\t# Require jq for robust JSON parsing.\n\tif [ "${CONFIG_USABLE}" -eq 1 ] && ! which jq >/dev/null 2>&1; then\n\t\tif [ "${CONFIG_REQUIRED}" -eq 1 ]; then\n\t\t\tprintf \'%s\\n\' "Error: jq is required to parse ${CONFIG_FILE}. Install jq or use environment variables (QODO_API_KEY, QODO_ENVIRONMENT_NAME, QODO_API_URL)." >&2\n\t\t\texit 1\n\t\tfi\n\t\tCONFIG_USABLE=0\n\tfi',
)
for old, new in [
    (
        'case "${CONFIG_QODO_API_URL}" in\n\t\t\t*\\?* | *\\#*) CONFIG_QODO_API_URL="${INVALID_QODO_API_URL}" ;;\n\t\tesac',
        'case "${CONFIG_QODO_API_URL}" in\n\t\t\t*\\?* | *\\#*) CONFIG_QODO_API_URL="${INVALID_QODO_API_URL}" ;;\n\t\t\t*) : ;;\n\t\tesac',
    ),
    (
        '\tcase "${QODO_API_URL}" in\n\t\t*\\?* | *\\#*)\n\t\t\tprintf \'%s\\n\' \'Invalid QODO_API_URL: must not contain query string or fragment\' >&2\n\t\t\texit 1\n\t\t\t;;\n\tesac',
        '\tcase "${QODO_API_URL}" in\n\t\t*\\?* | *\\#*)\n\t\t\tprintf \'%s\\n\' \'Invalid QODO_API_URL: must not contain query string or fragment\' >&2\n\t\t\texit 1\n\t\t\t;;\n\t\t*) : ;;\n\tesac',
    ),
    (
        '\tcase "${ENV_NAME}" in\n\t\t*[!a-zA-Z0-9_.-]* | "")\n\t\t\tprintf \'%s\\n\' \'Invalid ENVIRONMENT_NAME: must contain only alphanumeric, underscore, dot, or hyphen characters\' >&2\n\t\t\texit 1\n\t\t\t;;\n\tesac',
        '\tcase "${ENV_NAME}" in\n\t\t*[!a-zA-Z0-9_.-]* | "")\n\t\t\tprintf \'%s\\n\' \'Invalid ENVIRONMENT_NAME: must contain only alphanumeric, underscore, dot, or hyphen characters\' >&2\n\t\t\texit 1\n\t\t\t;;\n\t\t*) : ;;\n\tesac',
    ),
]:
    replace_one(".agents/skills/qodo-get-rules/config-parsing.sh", old, new)
