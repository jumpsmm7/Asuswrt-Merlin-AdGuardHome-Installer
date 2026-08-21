# AGENTS.md

These instructions apply to the entire repository unless a deeper `AGENTS.md` overrides them.

Amazon Q Developer must treat this file as binding repository guidance. When generic Linux or Bash advice conflicts with these rules, follow this repository's BusyBox `ash` and Asuswrt-Merlin requirements.

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

Router stock paths must take priority over Entware paths. The installer appends inherited PATH to preserve user environment during interactive setup. Runtime service scripts (AdGuardHome.sh, S99AdGuardHome, rc.func.AdGuardHome) use a fixed PATH without inheritance to ensure consistent service behavior regardless of the invoking environment.

## Cost-conscious behavior

Keep reviews and edits small, targeted, and high-signal.

* Inspect the diff first.
* Read only the directly touched files and the nearest callers/callees needed to understand the change.
* Do not scan the whole repository unless the user explicitly asks or the diff cannot be reviewed safely without it.
* Do not rewrite large blocks just for style.
* Prefer minimal patches over broad refactors.
* Avoid low-value nits. Comment only when there is a likely bug, security regression, router-breaking edge case, compatibility issue, or meaningful performance problem.
* In review mode, cap findings to the most important issues. If no high-confidence issue exists, say so plainly.
* Do not run expensive, network-heavy, or installation commands during review unless the user explicitly asks.
* When validation is needed, prefer syntax-only checks on touched shell files.

Recommended review priority:

1. Security regressions.
2. Service interruption, restore-path, or cleanup regressions.
3. BusyBox `ash` / POSIX compatibility issues.
4. Router-specific edge cases involving NVRAM, firewall, WAN, DNS, VPN, or service state.
5. Performance problems on constrained router hardware.
6. Maintainability issues only when they can cause real defects.

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

These are hard requirements for Amazon Q Developer when writing or editing shell code in this repository. Do not "clean up" working shell by applying Python, JavaScript, Bash, or desktop-Linux punctuation conventions.

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
* When an embedded program is single-quoted, remember that shell variables do not expand inside it unless values are passed explicitly (for example with `awk -v`).
* When changing nested quotes, verify both layers: the shell must parse, and the embedded expression must still receive the intended characters.

Required pre-delivery checks for shell changes:

1. Run `sh -n` on every touched shell script or shell fixture.
2. If ShellCheck is available in the development environment, run `shellcheck -s sh` on touched runtime shell files.
3. Inspect the final diff for unmatched quotes, accidental commas, missing separators/terminators, unquoted expansions, Bash-only syntax, and GNU-only assumptions.
4. Run the nearest targeted regression test(s) for the changed behavior when available.
5. Do not claim a command or test passed unless it was actually run successfully.

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

For touched shell scripts, suggest or run syntax checks with:

```sh
sh -n scriptname
```

If ShellCheck is available outside the router, it may be used as an additional check:

```sh
shellcheck -s sh scriptname
```

Do not require validation commands that need Python, Perl, GNU coreutils, `systemd`, `apt`, or Entware unless explicitly allowed.

## Answer style for this repository

* Give direct usable code first.
* Then briefly explain BusyBox `ash` compatibility.
* Point out commands that rely on router-stock binaries rather than BusyBox applets.
* Point out unavailable commands if a suggestion would otherwise depend on them.
* Keep explanations concise and practical.
* Prefer small targeted patches unless the user asks for a full rewrite.
