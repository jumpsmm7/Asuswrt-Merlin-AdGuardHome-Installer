#!/usr/bin/env python3
from pathlib import Path


def replace(path, old, new, count=1):
    p = Path(path)
    text = p.read_text()
    found = text.count(old)
    if found != count:
        raise SystemExit(f"{path}: expected {count} occurrence(s), found {found}: {old[:100]!r}")
    p.write_text(text.replace(old, new, count))


# 1. Auto-fix contradictions must preserve the established held outcome.
replace(
    ".agents/skills/qodo-pr-resolver/resources/convergence.md",
    """   - **⚠️ Contradiction** — always prompt via AskUserQuestion with the Contradiction options
     (Defer / Apply / Modify) defaulting to **Defer**; this is the one case auto-fix must
     interrupt for — never silently apply *or* silently defer it. On Defer, reply with the rationale.
""",
    """   - **⚠️ Contradiction** — always prompt via AskUserQuestion with the Contradiction options
     (**Hold prior decision** / Apply / Modify) defaulting to **Hold prior decision**; this is the one case auto-fix must
     interrupt for — never silently apply *or* silently hold it. When the user holds the prior
     decision, keep the code unchanged, preserve the ledger outcome as `decision=held action=none`,
     reply with the one-line **Held** rationale defined above, and resolve the thread.
""",
)

# 2. Stage resolver-owned paths with an option terminator for every path operand.
replace(
    ".agents/skills/qodo-pr-resolver/SKILL.md",
    """    - **GitHub / GitLab / Bitbucket / Azure DevOps:** Git commit the fix. Stage only the files modified by the resolver (explicitly list them; do not use `git add .` or `git add -A` which would capture pre-existing changes), then commit: `git add <resolver-modified-files> && git commit -m \"fix: <issue title>\"`. The issue title comes from Qodo's review content and must be treated as untrusted input; pass it safely as commit message content via a properly quoted/escaped variable or mechanism that prevents shell metacharacters, newlines, quotes, or command-substitution sequences from altering the shell command. If a `PRE_EXISTING_MODIFICATIONS` baseline exists, ensure only resolver-introduced changes are staged.
    - **Gerrit:** Do NOT commit yet — stage the change (`git add <resolver-modified-files>`) but wait until all fixes are applied, then amend into a single commit (see Gerrit note below). If a `PRE_EXISTING_MODIFICATIONS` baseline exists, ensure only resolver-introduced changes are staged.
""",
    """    - **GitHub / GitLab / Bitbucket / Azure DevOps:** Git commit the fix. Stage only the files modified by the resolver (explicitly list them; do not use `git add .` or `git add -A` which would capture pre-existing changes). Precede every resolver-modified path operand with the `--` option terminator; when staging individually, use an argument-safe form such as `git add -- \"$file\"` for each validated path, then commit with `git commit -m \"fix: <issue title>\"`. The issue title comes from Qodo's review content and must be treated as untrusted input; pass it safely as commit message content via a properly quoted/escaped variable or mechanism that prevents shell metacharacters, newlines, quotes, or command-substitution sequences from altering the shell command. If a `PRE_EXISTING_MODIFICATIONS` baseline exists, ensure only resolver-introduced changes are staged.
    - **Gerrit:** Do NOT commit yet — stage only resolver-modified paths, preceding every path operand with the `--` option terminator (for example, `git add -- \"$file\"` when staging individually), but wait until all fixes are applied, then amend into a single commit (see Gerrit note below). If a `PRE_EXISTING_MODIFICATIONS` baseline exists, ensure only resolver-introduced changes are staged.
""",
)
replace(
    ".agents/skills/qodo-pr-resolver/SKILL.md",
    "1. Apply all fixes (Edit tool) and stage them (`git add`)\n",
    "1. Apply all fixes (Edit tool) and stage only resolver-modified paths with an option terminator (for example, `git add -- \"$file\"` for each path)\n",
)

# 3. Remove unsupported fractional sleep from BusyBox-targeted polling paths.
p = Path("tests/dns-startup-handoff.sh")
text = p.read_text()
fractional_count = text.count("command sleep 0.01")
if fractional_count < 1:
    raise SystemExit("tests/dns-startup-handoff.sh: expected at least one fractional polling sleep")
p.write_text(text.replace("command sleep 0.01", "command usleep 100000"))

# 4. Track both checksum publication temporaries for interruption cleanup.
replace(
    "tools/download-adguardhome-static.sh",
    'ACTIVE_DOWNLOAD_TMP=""\nACTIVE_PUBLICATION_ARCHIVE=""\n',
    'ACTIVE_DOWNLOAD_TMP=""\nACTIVE_DOWNLOAD_MD5_TMP=""\nACTIVE_DOWNLOAD_SHA256_TMP=""\nACTIVE_PUBLICATION_ARCHIVE=""\n',
)
replace(
    "tools/download-adguardhome-static.sh",
    """\tif [ -n \"${ACTIVE_DOWNLOAD_TMP:-}\" ]; then
\t\trm -f \"${ACTIVE_DOWNLOAD_TMP}\"
\t\tACTIVE_DOWNLOAD_TMP=\"\"
\tfi
}
""",
    """\tif [ -n \"${ACTIVE_DOWNLOAD_TMP:-}\" ]; then
\t\trm -f \"${ACTIVE_DOWNLOAD_TMP}\"
\t\tACTIVE_DOWNLOAD_TMP=\"\"
\tfi
\tif [ -n \"${ACTIVE_DOWNLOAD_MD5_TMP:-}\" ]; then
\t\trm -f \"${ACTIVE_DOWNLOAD_MD5_TMP}\"
\t\tACTIVE_DOWNLOAD_MD5_TMP=\"\"
\tfi
\tif [ -n \"${ACTIVE_DOWNLOAD_SHA256_TMP:-}\" ]; then
\t\trm -f \"${ACTIVE_DOWNLOAD_SHA256_TMP}\"
\t\tACTIVE_DOWNLOAD_SHA256_TMP=\"\"
\tfi
}
""",
)
replace(
    "tools/download-adguardhome-static.sh",
    """\t_md5_tmp=\"${_md5_file}.tmp.$$\"
\t_sha256_tmp=\"${_sha256_file}.tmp.$$\"
\t_publish_state=\"${_archive_file}.publish-in-progress\"
""",
    """\t_md5_tmp=\"${_md5_file}.tmp.$$\"
\t_sha256_tmp=\"${_sha256_file}.tmp.$$\"
\tACTIVE_DOWNLOAD_MD5_TMP=\"${_md5_tmp}\"
\tACTIVE_DOWNLOAD_SHA256_TMP=\"${_sha256_tmp}\"
\t_publish_state=\"${_archive_file}.publish-in-progress\"
""",
)
replace(
    "tools/download-adguardhome-static.sh",
    """\t\tACTIVE_PUBLICATION_ARCHIVE=\"\"
\t\treturn 0
\tfi
""",
    """\t\tACTIVE_PUBLICATION_ARCHIVE=\"\"
\t\tACTIVE_DOWNLOAD_MD5_TMP=\"\"
\t\tACTIVE_DOWNLOAD_SHA256_TMP=\"\"
\t\treturn 0
\tfi
""",
)
replace(
    "tools/download-adguardhome-static.sh",
    """\tACTIVE_PUBLICATION_ARCHIVE=\"\"
\tFAILED=1
\treturn 1
}
""",
    """\tACTIVE_PUBLICATION_ARCHIVE=\"\"
\tACTIVE_DOWNLOAD_MD5_TMP=\"\"
\tACTIVE_DOWNLOAD_SHA256_TMP=\"\"
\tFAILED=1
\treturn 1
}
""",
)
replace(
    "tests/download-static-interruption-cleanup.sh",
    """ACTIVE_DOWNLOAD_TMP=\"${TEST_ROOT}/AdGuardHome_stable_linux_arm64.tar.gz.tmp.$$\"
printf '%s\\n' \"partial archive\" >\"${ACTIVE_DOWNLOAD_TMP}\" ||
\tfail \"could not create partial archive\"
cleanup_download_tmp
[ ! -e \"${TEST_ROOT}/AdGuardHome_stable_linux_arm64.tar.gz.tmp.$$\" ] ||
\tfail \"download cleanup left the partial archive behind\"
[ ! -e \"${TEST_ROOT}/AdGuardHome_stable_linux_arm64.tar.gz.tmp.$$.sha256sum\" ] ||
\tfail \"download cleanup left unpublished checksum metadata behind\"
[ -z \"${ACTIVE_DOWNLOAD_TMP}\" ] ||
\tfail \"download cleanup did not clear the tracked path\"

_sha256_file=\"${TEST_ROOT}/AdGuardHome_stable_linux_arm64.tar.gz.sha256sum\"
ACTIVE_DOWNLOAD_TMP=\"${_sha256_file}.tmp.$$\"
printf '%s\\n' \"partial checksum\" >\"${ACTIVE_DOWNLOAD_TMP}\" || fail \"could not create partial checksum\"
cleanup_download_tmp
[ ! -e \"${_sha256_file}.tmp.$$\" ] || fail \"download cleanup left the tracked checksum temporary file behind\"
""",
    """_archive_file=\"${TEST_ROOT}/AdGuardHome_stable_linux_arm64.tar.gz\"
ACTIVE_DOWNLOAD_TMP=\"${_archive_file}.tmp.$$\"
ACTIVE_DOWNLOAD_MD5_TMP=\"${_archive_file}.md5sum.tmp.$$\"
ACTIVE_DOWNLOAD_SHA256_TMP=\"${_archive_file}.sha256sum.tmp.$$\"
_archive_tmp=\"${ACTIVE_DOWNLOAD_TMP}\"
_md5_tmp=\"${ACTIVE_DOWNLOAD_MD5_TMP}\"
_sha256_tmp=\"${ACTIVE_DOWNLOAD_SHA256_TMP}\"
printf '%s\\n' \"partial archive\" >\"${_archive_tmp}\" || fail \"could not create partial archive\"
printf '%s\\n' \"partial md5\" >\"${_md5_tmp}\" || fail \"could not create partial MD5 checksum\"
printf '%s\\n' \"partial sha256\" >\"${_sha256_tmp}\" || fail \"could not create partial SHA256 checksum\"
grep -F 'ACTIVE_DOWNLOAD_MD5_TMP=\"${_md5_tmp}\"' \"${SCRIPT_PATH}\" >/dev/null ||
\tfail \"publisher does not track the MD5 publication temporary\"
grep -F 'ACTIVE_DOWNLOAD_SHA256_TMP=\"${_sha256_tmp}\"' \"${SCRIPT_PATH}\" >/dev/null ||
\tfail \"publisher does not track the SHA256 publication temporary\"
cleanup_download_tmp
for _tracked_tmp in \"${_archive_tmp}\" \"${_md5_tmp}\" \"${_sha256_tmp}\"; do
\t[ ! -e \"${_tracked_tmp}\" ] || fail \"download cleanup left tracked temporary ${_tracked_tmp} behind\"
done
[ -z \"${ACTIVE_DOWNLOAD_TMP}\" ] || fail \"download cleanup did not clear the tracked archive path\"
[ -z \"${ACTIVE_DOWNLOAD_MD5_TMP}\" ] || fail \"download cleanup did not clear the tracked MD5 path\"
[ -z \"${ACTIVE_DOWNLOAD_SHA256_TMP}\" ] || fail \"download cleanup did not clear the tracked SHA256 path\"
""",
)
replace(
    "tests/download-static-interruption-cleanup.sh",
    'printf \'%s\\n\' "PASS: interrupted static downloads remove partial archives"\n',
    'printf \'%s\\n\' "PASS: interrupted static downloads remove partial archives and checksum publication temporaries"\n',
)

# 5. Treat the generated marker path as data, not sed/grep syntax.
replace(
    "tests/installer-doctor-fix-safety.sh",
    'sed "s#/tmp/AdGuardHome\\.dnsmasq\\.lock#${DANGLING_MARKER}#g" "${FUNCTIONS_FILE}" >"${FUNCTIONS_FILE}.tmp" || fail \'could not isolate dangling marker path\'\n',
    'DANGLING_MARKER_SED="$(printf \'%s\\n\' "${DANGLING_MARKER}" | sed \'s/[\\&#]/\\\\&/g\')" || fail \'could not escape dangling marker path\'\n'
    'sed "s#/tmp/AdGuardHome\\.dnsmasq\\.lock#${DANGLING_MARKER_SED}#g" "${FUNCTIONS_FILE}" >"${FUNCTIONS_FILE}.tmp" || fail \'could not isolate dangling marker path\'\n',
)
replace(
    "tests/installer-doctor-fix-safety.sh",
    'printf \'%s\\n\' "${DOCTOR_OUTPUT}" | grep -q "^\\[WARN\\].*dnsmasq handoff marker/lock exists: ${DANGLING_MARKER}.*Next:" || fail \'dangling handoff marker was not reported with its path\'\n',
    '''printf '%s\\n' "${DOCTOR_OUTPUT}" | awk -v marker="${DANGLING_MARKER}" '\n\t/^\\[WARN\\]/ && index($0, marker) && index($0, "| Next:") { found = 1 }\n\tEND { exit found ? 0 : 1 }\n' || fail 'dangling handoff marker was not reported with its path and next step'\n''',
)

# 6. Record successful reaper releases and assert signal/interactive ordering.
replace(
    "tests/installer-end-op-rollback.sh",
    """\t# nvram_transaction_lock_reaper_release_active reports that the active NVRAM transaction reaper was released.
\tnvram_transaction_lock_reaper_release_active() { return 0; }
\trm -f \"${TEST_ROOT}/unexpected-signal-return\"
""",
    """\tSIGNAL_REAPER_LOG=\"${TEST_ROOT}/${signal_mode}-signal-reaper.log\"
\t: >\"${SIGNAL_REAPER_LOG}\" || fail \"could not create ${signal_mode} signal reaper log\"
\t# nvram_transaction_lock_reaper_release_active records a successful active-reaper release.
\tnvram_transaction_lock_reaper_release_active() {
\t\tprintf '%s\\n' release >>\"${SIGNAL_REAPER_LOG}\"
\t\treturn 0
\t}
\trm -f \"${TEST_ROOT}/unexpected-signal-return\"
""",
)
replace(
    "tests/installer-end-op-rollback.sh",
    """\t[ \"${status}\" -eq 2 ] || fail \"${signal_mode} signal cleanup exited with status ${status} instead of 2\"
\t[ ! -e \"${TEST_ROOT}/unexpected-signal-return\" ] || fail \"${signal_mode} signal cleanup returned to the interrupted operation\"

\t# nvram_transaction_lock_reaper_release_active simulates failure to release the active NVRAM transaction reaper.
""",
    """\t[ \"${status}\" -eq 2 ] || fail \"${signal_mode} signal cleanup exited with status ${status} instead of 2\"
\t[ ! -e \"${TEST_ROOT}/unexpected-signal-return\" ] || fail \"${signal_mode} signal cleanup returned to the interrupted operation\"
\t[ \"$(wc -l <\"${SIGNAL_REAPER_LOG}\")\" -eq 1 ] || fail \"${signal_mode} signal cleanup did not release the active reaper exactly once before exit\"

\t# nvram_transaction_lock_reaper_release_active simulates failure to release the active NVRAM transaction reaper.
""",
)
replace(
    "tests/installer-end-op-rollback.sh",
    """# nvram_transaction_lock_release always fails to release the NVRAM transaction lock.
nvram_transaction_lock_release() { return 1; }
# nvram_transaction_lock_reaper_release_active reports that the active NVRAM transaction reaper was released.
nvram_transaction_lock_reaper_release_active() { return 0; }
""",
    """INTERACTIVE_RELEASE_LOG=\"${TEST_ROOT}/interactive-release-order.log\"
: >\"${INTERACTIVE_RELEASE_LOG}\" || fail 'could not create interactive release-order log'
# nvram_transaction_lock_release records the lock-release attempt and then fails it.
nvram_transaction_lock_release() {
\tprintf '%s\\n' lock >>\"${INTERACTIVE_RELEASE_LOG}\"
\treturn 1
}
# nvram_transaction_lock_reaper_release_active records the successful active-reaper release.
nvram_transaction_lock_reaper_release_active() {
\tprintf '%s\\n' reaper >>\"${INTERACTIVE_RELEASE_LOG}\"
\treturn 0
}
""",
)
replace(
    "tests/installer-end-op-rollback.sh",
    """grep -q 'Unable to release the installer NVRAM transaction lock' \"${TEST_ROOT}/interactive-output\" || fail 'interactive lock-release failure was not reported'

CLI_MODE=\"1\"
""",
    """grep -q 'Unable to release the installer NVRAM transaction lock' \"${TEST_ROOT}/interactive-output\" || fail 'interactive lock-release failure was not reported'
[ \"$(grep -c '^reaper$' \"${INTERACTIVE_RELEASE_LOG}\")\" -eq 1 ] || fail 'interactive path did not release the active reaper exactly once'
[ \"$(sed -n '1p' \"${INTERACTIVE_RELEASE_LOG}\")\" = reaper ] || fail 'interactive path attempted lock release before active-reaper release'
[ \"$(sed -n '2p' \"${INTERACTIVE_RELEASE_LOG}\")\" = lock ] || fail 'interactive path did not attempt the transaction lock release after the active reaper'

CLI_MODE=\"1\"
""",
)

# 7. Downloader stubs fail closed when no recognized output operand was supplied.
p = Path("tests/installer-secure-download-fallback.sh")
text = p.read_text()
for command, option, diagnostic in (
    ("curl", "-o", "curl stub did not receive a recognized -o output path"),
    ("wget", "-O", "wget stub did not receive a recognized -O output path"),
):
    start = text.index(f"{command}() {{")
    end = text.index("\n}\n", start)
    block = text[start:end]
    if diagnostic in block:
        continue
    marker = '\tcase " $* " in\n'
    idx = block.index(marker)
    guard = (
        '\tif [ -z "${_out}" ]; then\n'
        f"\t\tprintf '%s\\n' '{diagnostic}' >&2\n"
        '\t\treturn 2\n'
        '\tfi\n'
    )
    block = block[:idx] + guard + block[idx:]
    text = text[:start] + block + text[end:]
p.write_text(text)

# 8. Interrupted writable-path tests terminate after cleanup.
replace(
    "tests/runtime-writable-path-security.sh",
    "trap cleanup EXIT HUP INT TERM\n",
    "trap cleanup EXIT\ntrap 'cleanup; exit 1' HUP INT TERM\n",
)

# 9. The documented Qodo endpoint returns an object, not a singleton array.
old_validation = '''  if type != "array" or length != 1 then
    error("Qodo rules request failed: invalid JSON response (expected exactly one object)")
  else .[0] end |
  if type != "object" or (.rules | type) != "array" then
    error("Qodo rules request failed: malformed response (expected object with rules array)")
'''
new_validation = '''  if type != "object" or (.rules | type) != "array" then
    error("Qodo rules request failed: malformed response (expected object with rules array)")
'''
replace(
    ".agents/skills/qodo-get-rules/references/search-endpoint.md",
    old_validation,
    new_validation,
    count=2,
)

# 10. Service-script PATH is fixed and must not inherit caller entries.
replace(
    "REVIEW.md",
    'export PATH="/sbin:/bin:/usr/sbin:/usr/bin:/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin${PATH:+:$PATH}"\n',
    'export PATH="/sbin:/bin:/usr/sbin:/usr/bin:/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin"\n',
)
