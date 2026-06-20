# AGENTS.md

These instructions apply to the entire repository unless a deeper `AGENTS.md` overrides them.

## Primary target

This repository targets POSIX `/bin/sh` scripts running under BusyBox `ash` on Asuswrt-Merlin routers with Entware installed for the AdGuardHome installer runtime.

Assume:

```sh
export LC_ALL=C
export PATH="/sbin:/bin:/usr/sbin:/usr/bin:/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin${PATH:+:$PATH}"
```

Router stock paths must take priority over Entware paths.

## Cost-conscious Codex behavior

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
* `go`
* `go_nohf`
* `python3`
* `python3-bcrypt`

Default to router stock paths and BusyBox applets outside installer-managed Entware paths and package-install flows.

## BusyBox environment

Target BusyBox version: `BusyBox v1.25.1`.
Treat BusyBox applets as limited implementations, not GNU coreutils.
Avoid GNU-only flags unless confirmed for BusyBox v1.25.1.

Available BusyBox applets include: `ash`, `awk`, `basename`, `cat`, `chmod`, `chown`, `cp`, `crond`, `crontab`, `cut`, `date`, `dd`, `df`, `dirname`, `dmesg`, `du`, `echo`, `egrep`, `env`, `expr`, `find`, `grep`, `gunzip`, `gzip`, `head`, `hostname`, `ifconfig`, `kill`, `killall`, `ln`, `logger`, `logread`, `ls`, `md5sum`, `mkdir`, `mount`, `mv`, `nc`, `netstat`, `nohup`, `nslookup`, `pidof`, `ping`, `ping6`, `printf`, `ps`, `pwd`, `readlink`, `reboot`, `rm`, `rmdir`, `route`, `sed`, `sh`, `sha256sum`, `sleep`, `sort`, `stty`, `sync`, `tail`, `tar`, `tee`, `test`, `top`, `touch`, `tr`, `true`, `umount`, `uname`, `uniq`, `unzip`, `uptime`, `usleep`, `vi`, `watch`, `wc`, `which`, `xargs`, and `zcat`.

`flock` is optional across supported firmware. Do not rely on it unconditionally; preserve the existing compatibility probe and fallback path for IPSET/service locking when `flock` is absent or lacks descriptor-lock support.

## Important router stock command paths

Prefer these known stock paths when absolute paths are needed:

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
