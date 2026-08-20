from pathlib import Path


def read(path):
    return Path(path).read_text(encoding="utf-8")


def write(path, text):
    Path(path).write_text(text, encoding="utf-8")


def replace(path, old, new, expected=1):
    text = read(path)
    count = text.count(old)
    if count != expected:
        raise SystemExit(f"{path}: expected {expected} replacement marker(s), found {count}")
    write(path, text.replace(old, new))


unstable = "(tentative|deprecated|dadfailed|temporary|mngtmpaddr)"
stable = "(tentative|deprecated|dadfailed|temporary)"
replace("AdGuardHome.sh", unstable, stable, 2)
replace("installer", unstable, stable, 2)

readme_old = (
    "Temporary, management-flagged (`mngtmpaddr`), tentative, deprecated, duplicate,\n"
    "loopback, link-local, multicast, and broadcast addresses are excluded from\n"
    "discovery."
)
readme_new = (
    "Temporary, tentative, deprecated, duplicate, loopback, link-local, multicast,\n"
    "and broadcast addresses are excluded from discovery. A stable global IPv6\n"
    "address carrying `mngtmpaddr` remains eligible: that flag marks the template\n"
    "used by the kernel to manage temporary privacy addresses and does not itself\n"
    "make the template address temporary."
)
replace("README.md", readme_old, readme_new)

replace(
    "WIKI.md",
    "are logged.\nFirewall behavior is separate:",
    "are logged. Stable global IPv6 addresses carrying `mngtmpaddr` remain eligible;\n"
    "`mngtmpaddr` marks the template used to manage temporary privacy addresses and is\n"
    "distinct from the `temporary` flag.\nFirewall behavior is separate:",
)

replace(
    "tests/lan-primary-address-selection.sh",
    "[ \"$(interface_ipv6_addr br0)\" = '2001:db8::60' ] || fail 'IPv6 selection retained an unstable address'",
    "[ \"$(interface_ipv6_addr br0)\" = '2001:db8::61' ] || fail 'IPv6 selection rejected a stable mngtmpaddr template address'",
)

replace(
    "tests/installer-bind-addresses.sh",
    "# Prefer a stable global IPv6 address over temporary, tentative, and deprecated addresses.",
    "# Prefer a stable mngtmpaddr IPv6 template over temporary, tentative, deprecated, and dadfailed addresses.",
)
replace(
    "tests/installer-bind-addresses.sh",
    "IPV6_FROM_IP='2001:db8::10'",
    "IPV6_FROM_IP='2001:db8::95'",
)
replace(
    "tests/installer-bind-addresses.sh",
    "[ \"${NET_ADDR6:-}\" = '2001:db8::10' ] || fail 'IPv6 discovery did not prefer the stable global address'",
    "[ \"${NET_ADDR6:-}\" = '2001:db8::95' ] || fail 'IPv6 discovery rejected the stable mngtmpaddr template address'",
)
replace(
    "tests/installer-bind-addresses.sh",
    "! grep -Eq '^    - 2001:db8::(99|98|97|96|95)$' \"${TMP_ROOT}/ipv6-temporary.yaml\" || fail 'unstable IPv6 address was added'",
    "grep -q '^    - 2001:db8::95$' \"${TMP_ROOT}/ipv6-temporary.yaml\" || fail 'stable mngtmpaddr IPv6 template address was omitted'\n"
    "! grep -Eq '^    - 2001:db8::(99|98|97|96)$' \"${TMP_ROOT}/ipv6-temporary.yaml\" || fail 'unstable IPv6 address was added'",
)

doc_test = "tests/lan-bridge-discovery-doc-consistency.sh"
replace(
    doc_test,
    'BRIDGE_FUNCTION_FILE="${TMP_ROOT}/private_ipv4_bridge_dns_options"',
    'BRIDGE_FUNCTION_FILE="${TMP_ROOT}/private_ipv4_bridge_dns_options"\n'
    'IPV6_FUNCTION_FILE="${TMP_ROOT}/interface_ipv6_addr"',
)
replace(
    doc_test,
    "[ -s \"${BRIDGE_FUNCTION_FILE}\" ] || fail 'private_ipv4_bridge_dns_options extraction was empty'",
    "[ -s \"${BRIDGE_FUNCTION_FILE}\" ] || fail 'private_ipv4_bridge_dns_options extraction was empty'\n"
    "sed -n '/^interface_ipv6_addr() {$/,/^}$/p' \"${SCRIPT_PATH}\" >\"${IPV6_FUNCTION_FILE}\" ||\n"
    "\tfail 'could not extract interface_ipv6_addr'\n"
    "[ -s \"${IPV6_FUNCTION_FILE}\" ] || fail 'interface_ipv6_addr extraction was empty'",
)
replace(
    doc_test,
    "for term in tentative deprecated temporary mngtmpaddr; do",
    "for term in tentative deprecated temporary; do",
)
replace(
    doc_test,
    'grep -q "${term}" "${SCRIPT_PATH}" || fail "AdGuardHome.sh no longer excludes ${term} addresses"',
    'grep -q "${term}" "${IPV6_FUNCTION_FILE}" || fail "AdGuardHome.sh no longer excludes ${term} IPv6 addresses"',
)
replace(
    doc_test,
    "done\ngrep -q 'dadfailed' \"${SCRIPT_PATH}\" || fail 'AdGuardHome.sh no longer excludes dadfailed addresses'",
    "done\n"
    "! grep -q 'mngtmpaddr' \"${IPV6_FUNCTION_FILE}\" || fail 'interface_ipv6_addr incorrectly excludes stable mngtmpaddr template addresses'\n"
    "grep -qi 'mngtmpaddr' \"${README_PATH}\" || fail 'README.md does not document mngtmpaddr eligibility'\n"
    "grep -qi 'mngtmpaddr' \"${WIKI_PATH}\" || fail 'WIKI.md does not document mngtmpaddr eligibility'\n"
    "grep -q 'dadfailed' \"${SCRIPT_PATH}\" || fail 'AdGuardHome.sh no longer excludes dadfailed addresses'",
)
replace(
    doc_test,
    "[ -s \"${TMP_ROOT}/refresh_function\" ] || fail 'adguard_refresh_lan_bind_addresses extraction was empty'",
    "[ -s \"${TMP_ROOT}/refresh_function\" ] || fail 'adguard_refresh_lan_bind_addresses extraction was empty'\n"
    "! grep -q 'mngtmpaddr' \"${TMP_ROOT}/refresh_function\" ||\n"
    "\tfail 'LAN bind refresh incorrectly excludes stable mngtmpaddr template addresses'",
)

review_path = ".github/workflows/code-quality-review.yml"
review_text = read(review_path)
curl_marker = "curl --proto '=https' --proto-redir '=https' -fsS -u"
if review_text.count(curl_marker) != 2:
    raise SystemExit(f"{review_path}: expected two Sonar curl calls")
review_text = review_text.replace(
    curl_marker,
    "curl --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 60 -fsS -u",
)
payload_old = (
    '          issues = payload.get("issues", [])\n'
    '          total = int(payload.get("total", len(issues)))\n'
)
payload_new = "\n".join(
    [
        "          if not isinstance(payload, dict):",
        '              print("Error: Sonar issues response must be a JSON object.", file=sys.stderr)',
        "              sys.exit(1)",
        "",
        '          issues = payload.get("issues")',
        '          total = payload.get("total")',
        "          if (",
        "              not isinstance(issues, list)",
        "              or type(total) is not int",
        "              or total < 0",
        "              or total < len(issues)",
        "              or any(not isinstance(issue, dict) for issue in issues)",
        "          ):",
        "              print(",
        '                  "Error: Sonar issues response must contain a list-valued issues field, "',
        '                  "a non-negative integer total not smaller than the returned issue count, "',
        '                  "and object-valued issue entries.",',
        "                  file=sys.stderr,",
        "              )",
        "              sys.exit(1)",
        "",
    ]
)
if review_text.count(payload_old) != 1:
    raise SystemExit(f"{review_path}: Sonar payload marker changed unexpectedly")
write(review_path, review_text.replace(payload_old, payload_new))

pr_head = "$" + "{{ github.event.pull_request.head.sha }}"
workflow_path = ".github/workflows/code-quality.yml"
workflow_text = read(workflow_path)
marker = "  apply-sonar-parser-cleanup:\n"
if workflow_text.count(marker) != 1:
    raise SystemExit(f"{workflow_path}: expected one Sonar cleanup job")
prefix = workflow_text.split(marker, 1)[0]
final_job = "\n".join(
    [
        "  apply-sonar-parser-cleanup:",
        "    name: Apply Sonar parser cleanup",
        "    if: github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name == github.repository && github.event.pull_request.head.ref == 'v2.6.5'",
        "    runs-on: ubuntu-latest",
        "    timeout-minutes: 10",
        "    permissions:",
        "      contents: read",
        "    steps:",
        "      - name: Check out immutable pull request head",
        "        uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09 # v5",
        "        with:",
        f"          ref: {pr_head}",
        "          persist-credentials: false",
        "          fetch-depth: 2",
        "",
        "      - name: Validate parser-friendly rewrite",
        "        run: |",
        "          set -eu",
        "          python3 .github/scripts/fix-sonar-shell-parse.py",
        "          sh -n AdGuardHome.sh",
        "          sh tests/installer-status.sh",
        "          sh tools/update-checksums.sh AdGuardHome.sh",
        "          git diff --check",
        "          git diff --exit-code -- AdGuardHome.sh AdGuardHome.sh.md5sum AdGuardHome.sh.sha256sum || {",
        "            printf '%s\\n' 'Error: Sonar parser cleanup or checksum sidecars are not current.' >&2",
        "            exit 1",
        "          }",
        "",
    ]
)
write(workflow_path, prefix + final_job)

config_path = "tests/coderabbit-and-workflow-config-checks.sh"
config_text = read(config_path)
start_marker = "# --- The Sonar parser cleanup must be idempotent"
end_marker = "\n# --- Static archive publication"
start = config_text.find(start_marker)
end = config_text.find(end_marker, start)
if start < 0 or end < 0:
    raise SystemExit(f"{config_path}: could not locate Sonar cleanup regression block")
contract = "\n".join(
    [
        "# --- The Sonar parser cleanup must be idempotent. Pull-request validation must",
        "# use the immutable head SHA with a non-persistent read-only checkout and fail",
        "# when the parser rewrite or checksum sidecars would change the committed tree.",
        "grep -Fq 'old_count == 1 and new_count == 0' \"${SONAR_REWRITE}\" ||",
        "\tfail \"${SONAR_REWRITE}: expected validation of the pre-rewrite state\"",
        "grep -Fq 'old_count == 0 and new_count == 1' \"${SONAR_REWRITE}\" ||",
        "\tfail \"${SONAR_REWRITE}: expected the already-applied rewrite state to succeed\"",
        "grep -Fq 'sh tools/update-checksums.sh AdGuardHome.sh' \"${WORKFLOW}\" ||",
        "\tfail \"${WORKFLOW}: Sonar parser validation must regenerate AdGuardHome.sh checksums before comparison\"",
        f"grep -Fq 'ref: {pr_head}' \"${{WORKFLOW}}\" ||",
        "\tfail \"${WORKFLOW}: Sonar parser validation must check the immutable pull-request head SHA\"",
        "grep -Fq 'persist-credentials: false' \"${WORKFLOW}\" ||",
        "\tfail \"${WORKFLOW}: Sonar parser validation must not persist checkout credentials\"",
        "if grep -Fq 'contents: write' \"${WORKFLOW}\"; then",
        "\tfail \"${WORKFLOW}: pull-request quality workflow must not grant contents write permission\"",
        "fi",
        "if grep -Fq 'git push origin HEAD:v2.6.5' \"${WORKFLOW}\"; then",
        "\tfail \"${WORKFLOW}: pull-request quality workflow must not publish branch changes\"",
        "fi",
        "grep -Fq 'git diff --exit-code -- AdGuardHome.sh AdGuardHome.sh.md5sum AdGuardHome.sh.sha256sum' \"${WORKFLOW}\" ||",
        "\tfail \"${WORKFLOW}: Sonar parser validation must fail when generated artifacts differ\"",
        "",
    ]
)
config_text = config_text[:start] + contract + config_text[end:]
dependency_line = (
    '\tfail "${REVIEW_WORKFLOW}: expected the same host-side dependencies as the blocking quality workflow"\n'
)
if config_text.count(dependency_line) != 1:
    raise SystemExit(f"{config_path}: review dependency assertion marker changed unexpectedly")
sonar_contract = dependency_line + "\n".join(
    [
        '[ "$(grep -Fc -- \'--connect-timeout 10 --max-time 60\' "${REVIEW_WORKFLOW}")" -eq 2 ] ||',
        '\tfail "${REVIEW_WORKFLOW}: both Sonar requests must have bounded request-level timeouts"',
        "grep -Fq 'if not isinstance(payload, dict):' \"${REVIEW_WORKFLOW}\" ||",
        '\tfail "${REVIEW_WORKFLOW}: Sonar response validation must reject non-object payloads"',
        "grep -Fq 'not isinstance(issues, list)' \"${REVIEW_WORKFLOW}\" ||",
        '\tfail "${REVIEW_WORKFLOW}: Sonar response validation must require an issues list"',
        "grep -Fq 'type(total) is not int' \"${REVIEW_WORKFLOW}\" ||",
        '\tfail "${REVIEW_WORKFLOW}: Sonar response validation must require an integer total"',
        "grep -Fq 'total < len(issues)' \"${REVIEW_WORKFLOW}\" ||",
        '\tfail "${REVIEW_WORKFLOW}: Sonar response validation must reject inconsistent totals"',
        "",
    ]
)
write(config_path, config_text.replace(dependency_line, sonar_contract, 1))
