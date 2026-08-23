# AGENTS.md

These instructions apply to the entire repository unless a deeper `AGENTS.md` overrides them.

This file is the canonical repository guardrail set for all coding and review agents, including Codex, Amazon Q Developer, CodeRabbit, and Qodo. Agent-specific configuration may add workflow or provider details, but it must not weaken or contradict these rules. When agent-specific guidance conflicts with this file, this file wins.

## Primary target

This repository targets POSIX `/bin/sh` scripts running under BusyBox `ash` on Asuswrt-Merlin routers with Entware installed for the AdGuardHome installer runtime.

Assume:

```sh
export LC_ALL=C
```

**PATH contracts by script:**

- **installer**: Stock directories followed by inherited PATH:

  ```sh
  export PATH="/sbin:/bin:/usr/sbin:/usr/bin${PATH:+:$PATH}"
  ```

- **AdGuardHome.sh, S99AdGuardHome, rc.func.AdGuardHome**: Stock plus Entware directories without inherited PATH:

  ```sh
  export PATH="/sbin:/bin:/usr/sbin:/usr/bin:/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin"
  ```

Router stock paths must take priority over Entware paths. The installer appends inherited PATH to preserve user environment during interactive setup. Runtime service scripts (`AdGuardHome.sh`, `S99AdGuardHome`, and `rc.func.AdGuardHome`) use a fixed PATH without inheritance to ensure consistent service behavior regardless of the invoking environment.

## Shared review and editing posture

All agents must use the same finding threshold and investigation guardrails.

* Inspect the current diff first and verify each proposed finding against the current code before reporting or fixing it.
* Read only the directly touched files and the nearest callers, callees, configuration, tests, and lifecycle paths needed to prove the behavior.
* Report a finding only when there is a concrete, reachable failure condition and a practical effect on correctness, security, compatibility, router state, service lifecycle, reliability, or meaningful performance.
* Do not raise speculative, theoretical, style-only, naming, formatting, wording, or preference findings unless they create a real defect.
* Do not duplicate findings already enforced reliably by existing automated checks unless the check exposes a distinct root cause that still requires code changes.
* Group repeated instances of the same underlying problem instead of reporting them separately.
* Do not fill a finding quota. If no high-confidence issue exists, report no finding.
* Every finding should identify the exact failure condition, the practical effect, and a minimal compatible correction.
* Prefer minimal patches over broad refactors and do not reformat or rewrite unrelated code.
* When resolving existing review feedback, re-verify every finding against the current branch, fix only still-valid issues, and skip obsolete findings with a brief reason.
* Do not run expensive, network-heavy, installation, firmware-changing, or destructive commands during review unless the user explicitly asks or they are required to validate the changed behavior.
* Do not claim a test or command passed unless it was actually run successfully.

Prioritize findings in this order:

1. Security regressions.
2. Service interruption, rollback, cleanup, or restore-path regressions.
3. BusyBox `ash` or POSIX `/bin/sh` compatibility failures.
4. Router-specific failures involving NVRAM, firewall, WAN, DNS, VPN, IPSET, or service state.
5. Install, upgrade, restore, or uninstall failures.
6. Performance regressions on constrained router hardware.
7. Maintainability concerns only when they can reasonably cause a defect.

## Shell compatibility rules

Do not use Bash-only features unless the user explicitly requests Bash.

Avoid:

* `[[ ... ]]`
* arrays or associative arrays
* `${var//old/new}`
* process substitution
* here-strings
* `source`
* `mapfile` / `readarray`
* `select`
* `coproc`
* `set -o pipefail`
* Bash regex matching with `=~`

Use POSIX-safe constructs:

* `[ ... ]`
* `case ... esac`
* `while read -r line; do ... done`
* command substitution with `$(...)`
* functions as `name() { ...; }`

## Shell syntax, quoting, and punctuation contract

These are hard requirements for every coding or review agent when writing, suggesting, or evaluating shell code in this repository. Do not apply Python, JavaScript, Bash, or desktop-Linux punctuation conventions to POSIX shell.

Tokenization and separators:

* Shell command arguments are separated by whitespace, **not commas**. Do not write Python/C-style calls such as `printf '%s\n', "${value}"` or `command arg1, arg2` unless the comma is literal data required by the called program.
* Preserve commas that belong to an embedded language or command syntax. For example, AWK function calls require commas: `substr(value, 1, 3)` and `split(value, parts, "/")`.
* Variable assignments use `NAME=value` with no spaces around `=`. Use `NAME="${value}"` when expansion is needed.
* Separate commands with a newline or `;`. Use `&&` or `||` only when success/failure chaining is intentional.
* `if`, `elif`, `while`, `until`, and `for` headers must have a separator before `then` or `do`, normally `; then` or `; do` when kept on one line.
* Do not omit required terminators: `fi`, `done`, `esac`, and `;;` for completed `case` arms.
* Do not add commas between `case` patterns, command arguments, test operands, function arguments at the shell level, or redirections unless the invoked command's own syntax requires them.

Quoting and expansion:

* Quote parameter expansions by default: use `"${var}"`, not `$var`, unless field splitting or pathname expansion is deliberately required.
* Quote command substitutions when the result must remain one argument: `"$(command)"`.
* Quote path variables and redirection targets: `>"${file}"`, `rm -f "${file}"`, `cd "${dir}"`.
* Use double quotes when expansions must occur and single quotes for literal text that must not expand.
* Keep quote pairs balanced. Never leave unmatched `'` or `"` characters in generated shell.
* Use braces around parameter names when adjacent text could be parsed as part of the variable name: `"${name}_suffix"`.
* Under `set -u`, use forms such as `${var:-}` when an unset variable is valid and expected.
* Do not single-quote text that is supposed to expand variables or command substitutions.
* Do not leave wildcard characters unquoted unless pathname expansion is intended. `case` patterns are an exception when pattern matching is intentional.
* Keep `printf` format strings literal and pass data as separate arguments, for example `printf '%s\n' "${value}"`. Do not use user-controlled data as the format string.

Tests, conditionals, and control flow:

* POSIX test syntax requires spaces: `[ "${value}" = "expected" ]`, not `["${value}"="expected"]`.
* Use `=` and `!=` for string comparisons in `[ ... ]`; use `-eq`, `-ne`, `-lt`, `-le`, `-gt`, and `-ge` for integer comparisons.
* Prefer `[ -n "${value:-}" ]` and `[ -z "${value:-}" ]` for explicit non-empty/empty checks.
* Use `case "${value}" in ... esac` for multi-pattern matching instead of Bash `[[ ... =~ ... ]]`.
* Use `read -r` unless backslash interpretation is intentionally required.
* Do not rely on variables modified inside a pipeline-fed `while` loop being available afterward; pipeline components may run in subshells.
* When a command substitution's status controls the next action, do not hide it behind `local NAME="$(command)"`; declare the local first and assign separately. Do not flag a combined declaration when the substitution status is intentionally ignored.

Functions, redirections, and here-documents:

* Define functions as `name() { ...; }`. Keep a command separator before the closing `}`.
* Attach file-descriptor numbers directly to redirection operators, for example `2>/dev/null` and `2>&1`.
* Quote here-document delimiters (`<<'EOF'`) when the body must remain literal. Use an unquoted delimiter only when parameter or command expansion in the body is intentional.
* Preserve redirection order when it matters; `>"${file}" 2>&1` is not interchangeable with `2>&1 >"${file}"`.
* Keep temporary-file creation, cleanup traps, and ownership/permission handling compatible with BusyBox and the existing repository patterns.

Asuswrt-Merlin shell style:

* Preserve the surrounding file's tab-based indentation for shell blocks; do not mass-convert indentation.
* Keep one logical command per line unless a short `&&`/`||` chain clearly improves the existing code.
* Use LF line endings, no trailing whitespace, and exactly one trailing newline at end of text files.
* Preserve nearby declaration/order/style conventions unless changing them is necessary for correctness.
* Keep patches narrowly scoped. Do not reformat unrelated code while fixing shell syntax.

Embedded-language safety:

* Shell files in this repository contain AWK, `sed`, `jq`, regex, YAML, and JSON fragments. Validate the syntax of the embedded language separately from the outer shell quoting.
* Do not remove required AWK commas, regex escapes, JSON commas/quotes, or YAML spacing while adjusting shell quotes.
* When an embedded program is single-quoted, remember that shell variables do not expand inside it unless values are passed explicitly, for example with `awk -v`.
* When changing nested quotes, verify both layers: the shell must parse, and the embedded expression must still receive the intended characters.

General shell rules:

* Quote variables by default.
* Prefer `"${var}"`, not `$var`, unless unquoted expansion is intentional.
* Use `${var:-}` when an unset variable could be possible.
* Use `printf`, not `echo -e`.
* Use `which` for router-targeted command lookups.
* Avoid process-heavy code inside loops.
* Avoid unquoted glob expansion unless intentional.
* Preserve the existing coding style when practical.
* Use uppercase for global/config variables.
* Use lowercase for local loop variables where practical.
* `local` is acceptable when consistent with existing BusyBox `ash` scripts in this repository.

## Entware assumptions

Entware is an expected dependency for this installer. Existing installer/service code may use `/opt`, `/opt/bin`, `/opt/sbin`, `/opt/usr/bin`, `/opt/usr/sbin`, and `opkg` where that matches current project behavior.

Do not add unrelated Entware dependencies casually. If a new Entware package is needed, update the allowed package list in this section in the same change, clearly separate stock-router code from Entware-dependent code, and include or preserve the required `opkg install ...` step.

Allowed Entware packages currently referenced by the installer are:

* `apache`
* `apache-utils`
* `column`
* `coreutils-sha256sum`
* `go`
* `go_nohf`
* `jq-full`
* `python3`
* `python3-bcrypt`

Default to router stock paths and BusyBox applets outside installer-managed Entware paths and package-install flows.

## BusyBox environment

Target BusyBox version: `BusyBox v1.25.1`.
Treat BusyBox applets as limited implementations, not GNU coreutils.
Avoid GNU-only flags unless confirmed for BusyBox v1.25.1.

Available BusyBox applets include: `ash`, `awk`, `basename`, `cat`, `chmod`, `chown`, `cp`, `crond`, `crontab`, `cut`, `date`, `dd`, `df`, `dirname`, `dmesg`, `du`, `echo`, `egrep`, `env`, `expr`, `find`, `grep`, `gunzip`, `gzip`, `head`, `hostname`, `ifconfig`, `kill`, `killall`, `ln`, `logger`, `logread`, `ls`, `md5sum`, `mkdir`, `mkfifo`, `mount`, `mv`, `nc`, `netstat`, `nohup`, `nslookup`, `pidof`, `ping`, `ping6`, `printf`, `ps`, `pwd`, `readlink`, `reboot`, `renice`, `rm`, `rmdir`, `route`, `sed`, `sh`, `sha256sum`, `sleep`, `sort`, `stty`, `sync`, `tail`, `tar`, `tee`, `test`, `top`, `touch`, `tr`, `true`, `umount`, `uname`, `uniq`, `unzip`, `uptime`, `usleep`, `vi`, `watch`, `wc`, `which`, `xargs`, and `zcat`.

`flock` is optional across supported firmware. Do not rely on it unconditionally; preserve the existing compatibility probe and fallback path for IPSET/service locking when `flock` is absent or lacks descriptor-lock support.

## Important router stock command paths

When no default path has been defined earlier, prefer these known stock paths when absolute paths are needed:

* `awk`: `/usr/bin/awk`
* `sed`: `/bin/sed`
* `grep`: `/bin/grep`
* `find`: `/usr/bin/find`
* `xargs`: `/usr/bin/xargs`
* `sort`: `/usr/bin/sort`
* `uniq`: `/usr/bin/uniq`
* `cut`: `/usr/bin/cut`
* `tr`: `/usr/bin/tr`
* `date`: `/bin/date`
* `readlink`: `/usr/bin/readlink`
* `curl`: `/usr/sbin/curl`
* `wget`: `/usr/sbin/wget`
* `jq`: `/usr/bin/jq`
* `openssl`: `/usr/sbin/openssl`
* `flock` (optional): `/usr/bin/flock`
* `nvram`: `/bin/nvram`
* `cru`: `/usr/sbin/cru`
* `service`: `/sbin/service`
* `iptables`: `/usr/sbin/iptables`
* `ip6tables`: `/usr/sbin/ip6tables`
* `ip`: `/usr/sbin/ip`
* `ebtables`: `/usr/sbin/ebtables`
* `brctl`: `/bin/brctl`
* `logger`: `/usr/bin/logger`

Optional or firmware-dependent tooling includes `flock`; use it only after checking availability and descriptor-lock support, and keep the mkdir/PID fallback path intact.

Note when a proposed command relies on a router-stock binary rather than a BusyBox applet, such as `curl`, `wget`, `jq`, `openssl`, `nvram`, `cru`, `service`, `iptables`, `ip6tables`, `ip`, `ipset`, `tc`, `openvpn`, `wg`, `stubby`, `dnsmasq`, `sqlite3`, `socat`, `conntrack`, `iperf3`, or `ookla`.

## Commands unavailable in stock router PATH

Do not suggest or require these unless Entware or another source is explicitly allowed:

* `realpath`
* `timeout`
* `perl`
* `python`
* `python3`

Also avoid assumptions about GNU coreutils, `systemd`, `apt`, or desktop Linux behavior.

## Asuswrt-Merlin filesystem assumptions

Common writable/script locations:

* `/jffs`
* `/jffs/scripts`
* `/tmp`
* `/tmp/mnt`

The installer also manages Entware-backed paths under `/opt`, including `/opt/etc`, `/opt/sbin`, `/opt/bin`, and `/opt/var/run`. Do not assume unrelated `/opt` paths exist outside installer-managed or explicitly Entware-dependent code.

## NVRAM rules

* Use `nvram get` and `nvram set` carefully.
* Preserve existing `nvram commit` calls for installer-managed persisted settings and rollback/restore paths that must survive reboot.
* Do not add incidental or newly introduced `nvram commit` flash writes unless the user explicitly requests persistence or the installer-managed flow requires it.
* Preserve old values before changing important NVRAM values when practical.
* For DNS, firewall, WAN, VPN, or service-related NVRAM changes, include restore logic when practical.
* Review changes for interrupted-install, signal-trap, rollback, and restart/restore failure paths.

## Service and firewall rules

* Avoid restarting services unless requested.
* If a service restart is needed, explain what it affects.
* When adding firewall rules, include matching cleanup/unload rules when practical.
* Use comments where supported so rules can be identified and removed safely.
* Handle IPv4 and IPv6 separately.
* For router-only traffic, be explicit about chain, interface, source, destination, protocol, and port.
* Prefer idempotent add/remove logic.
* Check for duplicate rules, stale rules, and failure paths after partial setup.

## Performance guidance

Routers are constrained systems. Prefer simple shell and applets over heavy pipelines.

* Avoid unnecessary forks inside loops.
* Avoid repeated `nvram`, `iptables`, `ip6tables`, `grep`, `sed`, or `awk` calls when values can be read once.
* Avoid long blocking waits without bounded retry logic.
* Avoid uncontrolled background processes.
* Prefer direct `case`/test logic over complex parsing where possible.
* Keep log output useful but not noisy.

## Security review checklist

When reviewing changes, look for:

* Unsafe unquoted variables.
* Command injection via user-controlled values.
* Path traversal or unsafe file removal.
* Unsafe writes under `/jffs`, `/tmp`, or mounted USB paths.
* Insecure download/update flows.
* Missing checksum, signature, or TLS verification when applicable.
* Incorrect permissions on scripts, keys, config files, or downloaded binaries.
* Firewall rules that expose router services or bypass intended DNS/VPN policy.
* NVRAM changes that persist unexpectedly or lack restore logic.
* Signal/interruption paths that leave services stopped or firewall/NVRAM state altered.

## Edge-case review checklist

Check for:

* Empty, unset, or whitespace-containing variables.
* Missing files/directories on fresh install.
* Read-only or unavailable mount points.
* Partial downloads or corrupt archives.
* Interrupted install/upgrade/uninstall.
* Duplicate cron jobs or firewall rules.
* IPv4-only logic where IPv6 also matters.
* Service already stopped, already running, or stuck stopping.
* PID reuse or broad `killall`/`pidof` matching.
* BusyBox option differences from GNU tools.

## Validation

Validation hosts and CI runners, unlike router runtime scripts, explicitly allow these host-only prerequisites:

* `python3` for validation helpers such as `.github/scripts/fix-sonar-shell-parse.py`.
* GNU coreutils `timeout` at `/usr/bin/timeout` for bounding regression and lint commands. Do not use a PATH-resolved or BusyBox `timeout` substitute.

Install and verify them on Debian/Ubuntu validation hosts with:

```sh
sudo apt-get install -y python3 coreutils
python3 --version
/usr/bin/timeout --version
```

These commands are validation-host exceptions only. They do not allow `python3` or GNU `timeout` dependencies in router-runtime scripts, and they do not imply that either command is available in the router stock PATH.

For touched shell scripts or shell fixtures, run the syntax check that matches the target environment when available:

```sh
sh -n scriptname
```

For router-runtime shell, BusyBox `ash -n` is preferred when BusyBox is available in the validation environment. If ShellCheck is available off-router, use it as an additional check:

```sh
shellcheck -s sh scriptname
```

Run the nearest targeted regression test for changed behavior when practical. Do not require validation commands that need Python, Perl, GNU coreutils, `systemd`, `apt`, network access, or a new Entware package unless the changed feature explicitly requires that environment.

Before delivery, inspect the final diff for unmatched quotes, accidental commas, missing separators or terminators, unquoted expansions, Bash-only syntax, GNU-only assumptions, and unrelated changes.

## Answer style for this repository

* Give direct usable code first.
* Then briefly explain BusyBox `ash` compatibility.
* Point out commands that rely on router-stock binaries rather than BusyBox applets.
* Point out unavailable commands if a suggestion would otherwise depend on them.
* Keep explanations concise and practical.
* Prefer small targeted patches unless the user asks for a full rewrite.
