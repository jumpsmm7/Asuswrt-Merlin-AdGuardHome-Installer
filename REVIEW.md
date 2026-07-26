# REVIEW.md

## Purpose and scope

These instructions apply to Qodo code reviews for the entire repository.

Review pull-request changes against the runtime, compatibility, security, lifecycle, and router-specific requirements below. Focus on defects introduced or exposed by the changed code.

This repository also contains `AGENTS.md` files for coding-agent behavior. This file is specifically for code-review findings.

## Review posture

Keep reviews targeted and high-signal.

* Analyze the diff first.
* Inspect only the nearest callers, callees, configuration, tests, and lifecycle paths needed to validate the change.
* Do not raise speculative findings that lack a concrete failure scenario.
* Do not recommend broad rewrites when a small correction resolves the issue.
* Do not raise style-only findings unless the style creates a correctness, compatibility, security, or maintainability defect.
* Do not duplicate findings already enforced reliably by existing automated checks.
* Group repeated instances of the same underlying problem.
* Do not fill a finding quota. When no high-confidence issue exists, return no finding.
* Suggestions must preserve the repository’s existing style unless that style causes a real defect.

Every finding should identify:

1. The exact failure condition.
2. The effect on the router, installer, service, or user.
3. A minimal compatible correction.

## Review priority

Prioritize findings in this order:

1. Security regressions.
2. Service interruption, rollback, cleanup, or restore-path regressions.
3. BusyBox `ash` or POSIX `/bin/sh` compatibility failures.
4. Router-specific failures involving NVRAM, firewall, WAN, DNS, VPN, IPSET, or service state.
5. Install, upgrade, restore, or uninstall failures.
6. Performance regressions on constrained router hardware.
7. Maintainability concerns only when they can reasonably cause a defect.

## Severity guidance

Treat a finding as high severity when the change can:

* Enable command injection or unsafe privilege use.
* Remove or overwrite an unintended file.
* Accept an unsafe archive path or symbolic link.
* Install an unverified or corrupted binary.
* Expose a router service through the firewall.
* Bypass intended DNS or VPN policy.
* Leave AdGuardHome or another managed service stopped.
* Leave firewall, NVRAM, DNS, VPN, or filesystem state partially modified.
* Persist an unintended NVRAM change across reboot.
* Break installation, startup, restore, upgrade, or uninstall on supported routers.

Treat compatibility or lifecycle findings as significant when they affect a supported BusyBox or Asuswrt-Merlin environment, even when they would work on desktop Linux.

Do not report naming, formatting, spelling, comment wording, or minor simplification opportunities as standalone findings.

## Target runtime

The primary runtime is POSIX `/bin/sh` using BusyBox `ash` on Asuswrt-Merlin routers.

Assume:

```sh
export LC_ALL=C
export PATH="/sbin:/bin:/usr/sbin:/usr/bin:/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin${PATH:+:$PATH}"
```

Router-stock paths must take priority over Entware paths.

Flag changes that accidentally depend on Bash, GNU userland, `systemd`, or a conventional desktop/server Linux filesystem.

## POSIX and BusyBox shell compatibility

New or modified shell code must remain compatible with POSIX `/bin/sh` and BusyBox `ash`.

Flag newly introduced use of:

* `[[ ... ]]`
* Indexed or associative arrays
* `${var//old/new}`
* Process substitution
* Here-strings
* `source`
* `mapfile` or `readarray`
* `select`
* `coproc`
* `set -o pipefail`
* Bash regular-expression matching with `=~`
* Bash-specific function syntax
* Other syntax requiring `/bin/bash`

Compatible patterns include:

* `[ ... ]`
* `case ... esac`
* `while read -r line; do ... done`
* `$(...)`
* `name() { ...; }`

`local` is permitted where it is consistent with the existing BusyBox `ash` scripts. Do not flag `local` merely because it is not specified by POSIX.

Review changed shell code for:

* Unquoted expansions that can split words or expand globs.
* Unsafe handling of empty or unset variables.
* Missing `${var:-}` protection where an unset value is possible.
* Use of `echo -e` instead of predictable `printf`.
* Unintentional glob expansion.
* Pipelines whose behavior depends on unavailable `pipefail`.
* Variable loss caused by modifying variables inside a pipeline-fed subshell.
* `read` behavior that loses backslashes because `-r` is missing.
* Tests that become invalid when a variable is empty.
* Incorrect operator precedence in combined `[ ... ]` expressions.
* Commands whose exit status is hidden or discarded unexpectedly.

Do not request unquoted expansion merely to shorten code.

When suggesting a command-availability check for router-targeted code, follow the repository’s existing `which` convention rather than introducing a stylistic rewrite.

## BusyBox version and applets

Target BusyBox version:

```text
BusyBox v1.25.1
```

Treat BusyBox applets as limited implementations rather than GNU equivalents.

Commonly available BusyBox applets include:

```text
ash awk basename cat chmod chown cp crond crontab cut date dd df
dirname dmesg du echo egrep env expr find grep gunzip gzip head
hostname ifconfig kill killall ln logger logread ls md5sum mkdir
mount mv nc netstat nohup nslookup pidof ping ping6 printf ps pwd
readlink reboot rm rmdir route sed sh sha256sum sleep sort stty
sync tail tar tee test top touch tr true umount uname uniq unzip
uptime usleep vi watch wc which xargs zcat
```

Flag GNU-only options unless support for the target BusyBox version or a required Entware package is established.

Do not assume an applet listed above supports every option provided by its GNU counterpart.

## Entware boundary

Entware is an expected dependency for the AdGuardHome installer runtime.

Existing installer and service code may use:

* `/opt`
* `/opt/bin`
* `/opt/sbin`
* `/opt/usr/bin`
* `/opt/usr/sbin`
* `opkg`

Do not flag those paths merely because they are not router-stock paths when the code is part of an established installer-managed Entware flow.

New Entware dependencies must satisfy all of the following:

* The dependency is actually required.
* The package is added to the repository’s allowed package list.
* The required `opkg install ...` path is added or preserved.
* Stock-router code and Entware-dependent code remain clearly separated.
* The command is not assumed to exist before package installation succeeds.
* Failure to install the package is handled.

Allowed Entware packages currently referenced by the installer are:

* `apache`
* `apache-utils`
* `column`
* `coreutils-sha256sum`
* `go`
* `go_nohf`
* `python3`
* `python3-bcrypt`

Flag an unrelated new package dependency unless the same change updates the dependency handling appropriately.

Outside installer-managed Entware paths and package-install flows, default to router-stock commands and BusyBox applets.

## Commands unavailable in the stock router PATH

Do not assume the following commands are available from the stock router environment:

* `realpath`
* `timeout`
* `perl`
* `python`
* `python3`

`python3` is acceptable only in an established Entware flow that installs or verifies the required package.

Also flag new assumptions involving:

* GNU coreutils behavior
* `systemd`
* `systemctl`
* `apt`
* `apt-get`
* Desktop Linux service management
* Desktop Linux filesystem layouts

## Router-stock command paths

When changed code requires an absolute router-stock path, review it against these known paths:

| Command     | Router-stock path     |
| ----------- | --------------------- |
| `awk`       | `/usr/bin/awk`        |
| `sed`       | `/bin/sed`            |
| `grep`      | `/bin/grep`           |
| `find`      | `/usr/bin/find`       |
| `xargs`     | `/usr/bin/xargs`      |
| `sort`      | `/usr/bin/sort`       |
| `uniq`      | `/usr/bin/uniq`       |
| `cut`       | `/usr/bin/cut`        |
| `tr`        | `/usr/bin/tr`         |
| `date`      | `/bin/date`           |
| `readlink`  | `/usr/bin/readlink`   |
| `curl`      | `/usr/sbin/curl`      |
| `wget`      | `/usr/sbin/wget`      |
| `jq`        | `/usr/bin/jq`         |
| `openssl`   | `/usr/sbin/openssl`   |
| `flock`     | `/usr/bin/flock`      |
| `nvram`     | `/bin/nvram`          |
| `cru`       | `/usr/sbin/cru`       |
| `service`   | `/sbin/service`       |
| `iptables`  | `/usr/sbin/iptables`  |
| `ip6tables` | `/usr/sbin/ip6tables` |
| `ip`        | `/usr/sbin/ip`        |
| `ebtables`  | `/usr/sbin/ebtables`  |
| `brctl`     | `/bin/brctl`          |
| `logger`    | `/usr/bin/logger`     |

Do not automatically require absolute paths when the configured `PATH` safely resolves the intended router-stock command first.

Treat commands such as the following as router-stock or firmware-provided binaries rather than guaranteed BusyBox applets:

* `curl`
* `wget`
* `jq`
* `openssl`
* `nvram`
* `cru`
* `service`
* `iptables`
* `ip6tables`
* `ip`
* `ipset`
* `tc`
* `openvpn`
* `wg`
* `stubby`
* `dnsmasq`
* `sqlite3`
* `socat`
* `conntrack`
* `iperf3`
* `ookla`

Flag their use only when availability is not established for the affected firmware or code path.

## Optional `flock` support

`flock` is optional across supported firmware and may lack descriptor-lock support.

Any changed locking code must preserve:

* An availability probe.
* A descriptor-lock capability probe where descriptor locking is used.
* The existing `mkdir` or PID-based fallback.
* Cleanup of lock state on success, failure, and interruption.
* Protection against stale locks and PID reuse where practical.

Flag code that makes `flock` an unconditional requirement or removes a working fallback.

## Filesystem assumptions

Common writable or script locations include:

* `/jffs`
* `/jffs/scripts`
* `/tmp`
* `/tmp/mnt`

The installer also manages Entware-backed paths under `/opt`, including:

* `/opt/etc`
* `/opt/sbin`
* `/opt/bin`
* `/opt/var/run`

Review changed filesystem operations for:

* Unsafe path construction.
* Path traversal.
* Empty path variables.
* Whitespace or glob characters in paths.
* Unsafe recursive deletion.
* Symbolic-link attacks.
* Writes through unexpected symbolic links.
* Incorrect ownership or permissions.
* Missing parent directories on a fresh installation.
* Read-only or unavailable mount points.
* Cross-filesystem replacement assumptions.
* Failure to clean temporary files.
* Non-atomic replacement of important files.
* Overwriting an existing script instead of updating it intentionally.
* Assuming unrelated `/opt` paths exist.

Temporary files containing sensitive or executable content must not be created with unsafe permissions or predictable names when an attacker-controlled collision is possible.

## Download, archive, and update safety

Review install and update changes for:

* Missing TLS verification.
* Missing checksum or signature verification where the project expects it.
* Accepting partial or empty downloads.
* Replacing a working binary before the new artifact is verified.
* Archive entries using absolute paths.
* Archive entries escaping through `..`.
* Unsafe symbolic-link or hard-link targets.
* Extraction outside the intended installation root.
* Failure to preserve the previous working installation until replacement succeeds.
* Incorrect architecture or platform selection.
* Temporary files being mistaken for completed downloads.
* Cleanup that deletes the previous working installation after a failed replacement.

Archive validation must match the extraction behavior. Listing an archive successfully is not sufficient when unsafe entry names or links can still be extracted.

## Installer and lifecycle safety

Review all changed install, upgrade, restore, uninstall, and replacement flows for their complete lifecycle.

Check:

* Normal success.
* Early validation failure.
* Command failure.
* Partial file replacement.
* Interrupted download.
* Interrupted extraction.
* Interrupted service stop.
* Signal handling for `HUP`, `INT`, and `TERM`.
* Rollback failure.
* Restart failure.
* Re-execution after interruption.
* Fresh install with no prior files.
* Upgrade with an existing working installation.
* Restore from an older backup.
* Uninstall after a partial installation.

When a flow stops AdGuardHome, its monitor, DNS, or another managed service, every exit path after the stop must either:

* Restore and restart the previous working state, or
* Clearly transfer responsibility to a reliable cleanup handler.

Flag any path that can leave the daemon or monitor stopped after an error or signal.

Signal cleanup must not discard a previous trap without preserving required cleanup behavior.

Rollback logic must restore all related state, not merely the primary binary.

## NVRAM safety

Review changed NVRAM code carefully.

Requirements:

* Use `nvram get` and `nvram set` with controlled keys and values.
* Preserve existing `nvram commit` calls when persistence is intentionally required.
* Do not introduce incidental `nvram commit` calls.
* Avoid unnecessary flash writes.
* Preserve previous values before modifying important settings when practical.
* Restore previous values on rollback, uninstall, or failed installation when practical.
* Do not confuse temporary runtime changes with persisted configuration.
* Validate values before using them in shell commands, paths, firewall rules, or arithmetic.

Pay particular attention to NVRAM changes affecting:

* DNS
* DHCP
* WAN
* Dual WAN
* VPN
* Firewall behavior
* Service startup
* Boot scripts
* Router administration access

Flag interrupted paths that can leave NVRAM values changed without restoring the corresponding service or firewall state.

## Service-state safety

Do not assume a service begins in a particular state.

Changed service-management code must handle relevant cases such as:

* Already running.
* Already stopped.
* Starting.
* Stopping.
* Failed.
* Stale PID file.
* PID reused by an unrelated process.
* Monitor running while the daemon is stopped.
* Daemon running while the monitor is stopped.
* Restart command returning before the service is ready.
* Service stop timing out or failing.

Flag broad `killall` or `pidof` matching when it can affect an unrelated process.

PID validation should confirm the intended process where practical before sending a signal.

Avoid introducing unbounded waits. Polling must have a defined limit and a useful failure path.

## Firewall and networking safety

Review changed firewall and network code for both setup and cleanup behavior.

Requirements:

* Use idempotent add and remove logic where practical.
* Avoid duplicate rules.
* Remove stale rules from previous runs.
* Add matching cleanup or unload behavior.
* Handle partially applied rule sets.
* Handle IPv4 and IPv6 separately.
* Do not assume an IPv4 rule also protects IPv6.
* Use comments or another stable identifier where supported.
* Be explicit about the affected table, chain, interface, direction, source, destination, protocol, and port.
* Preserve intended DNS and VPN leak protection.
* Do not expose router-local services unintentionally.
* Do not weaken an existing default-deny or kill-switch path.
* Check the return status of commands whose failure would leave the router in an unsafe state.

Pay special attention to changes involving:

* `iptables`
* `ip6tables`
* `ipset`
* `ebtables`
* `ip`
* `tc`
* DNS interception
* VPN policy routing
* WAN failover
* Router-local traffic
* NAT or NAT66
* Port forwarding
* INPUT, OUTPUT, FORWARD, or custom chains

A rule insertion is incomplete unless corresponding cleanup and interrupted-setup behavior are safe.

## DNS, WAN, and VPN state

Flag changes that can:

* Route DNS outside the intended resolver path.
* Leave stale DNS redirection rules.
* Create an IPv6 DNS leak while protecting only IPv4.
* Break name resolution during service replacement.
* Restore DNS configuration without restarting or reloading the dependent service.
* Bypass a VPN kill switch during tunnel failure.
* Apply policy routing to the wrong WAN interface.
* Assume the primary or secondary WAN is already initialized.
* Fail during cold boot when interfaces become ready in a different order.
* Leave a failover interface in an unmonitored or unusable state.

State restoration must include the services and rules needed to make restored configuration effective.

## Cron and boot-script behavior

Review changes to `cru`, cron files, `/jffs/scripts`, and startup hooks for:

* Duplicate jobs.
* Duplicate script entries.
* Overwriting an existing user script.
* Non-idempotent appends.
* Missing executable permissions.
* Incorrect shebangs.
* Commands that depend on an incomplete boot-time `PATH`.
* Jobs running before required mounts or Entware are available.
* Missing uninstall cleanup.
* Multiple concurrent instances.
* Unbounded background processes.

A change should preserve unrelated existing startup-script content unless replacement is explicitly intended.

## Performance on constrained hardware

Routers are constrained systems.

Flag meaningful regressions such as:

* Repeated `nvram` calls inside loops when the value can be read once.
* Repeated firewall command invocations that can be consolidated safely.
* Excessive `grep`, `sed`, `awk`, or other process creation inside hot loops.
* Polling without a bounded retry count.
* Long fixed sleeps where readiness can be checked.
* Uncontrolled background loops.
* Log flooding.
* Repeated parsing of the same file.
* Loading large files into memory unnecessarily.
* Performing network-heavy or package-install operations during normal service checks.
* Rebuilding unchanged firewall, IPSET, or configuration state repeatedly.

Do not report a theoretical micro-optimization unless the affected path runs frequently or handles enough data to matter on router hardware.

## Security review requirements

Look for concrete instances of:

* Command injection through user-controlled, downloaded, configuration-derived, or NVRAM-derived values.
* Unsafe `eval`.
* Shell commands assembled as strings.
* Unquoted values used as command arguments.
* Path traversal.
* Unsafe `rm`, `mv`, `cp`, `tar`, or redirection targets.
* Writes through attacker-controlled symbolic links.
* Predictable sensitive temporary files.
* Downloads without appropriate integrity validation.
* Incorrect executable, configuration, key, certificate, or credential permissions.
* Secrets written to logs.
* Firewall changes exposing administration or resolver services.
* DNS or VPN policy bypass.
* NVRAM persistence without a matching restore path.
* Signal handling that leaves security controls disabled.
* Trusting archive contents before validating entry names and link targets.
* Trusting a PID without confirming the process identity.
* Parsing configuration values into commands without validation.

A security finding must explain the reachable input and the resulting operation. Do not report an abstract injection risk without identifying how untrusted data reaches the command.

## Edge cases

Check changed code against relevant cases including:

* Empty variables.
* Unset variables.
* Whitespace-containing values.
* Newline-containing command output.
* Wildcard characters in filenames or values.
* Missing files or directories.
* Existing files with unexpected ownership or permissions.
* Read-only filesystems.
* Unavailable USB mounts.
* Partial downloads.
* Corrupt archives.
* Interrupted installation.
* Interrupted upgrade.
* Interrupted restore.
* Interrupted uninstall.
* Duplicate cron jobs.
* Duplicate firewall rules.
* Stale lock directories.
* PID reuse.
* Service already stopped.
* Service already running.
* Service stuck stopping.
* IPv4-only behavior on an IPv6-enabled router.
* Commands returning output but failing.
* Pipelines masking the failure of an earlier command.
* BusyBox options differing from GNU behavior.
* Cross-filesystem moves.
* Power loss between state changes.
* First boot or cold boot ordering differences.

Only raise an edge-case finding when the changed code makes the case reachable and consequential.

## Validation expectations

For changed shell scripts, the minimum appropriate validation is:

```sh
sh -n scriptname
```

ShellCheck may be recommended as an additional off-router validation when available:

```sh
shellcheck -s sh scriptname
```

Do not require validation that depends on:

* Python
* Perl
* GNU coreutils
* `systemd`
* `apt`
* A new Entware package
* Internet access
* Installation or removal of router packages

unless the changed feature explicitly requires that environment.

Do not request expensive, network-heavy, package-install, firmware-changing, service-restarting, or destructive validation merely to prove a review finding.

Tests should reproduce the actual failure path and preserve compatibility with the repository’s existing test environment.

## Review suggestion style

When proposing a correction:

* Prefer the smallest safe patch.
* Use POSIX `/bin/sh` syntax.
* Preserve BusyBox `ash` compatibility.
* Preserve existing rollback and cleanup behavior.
* Avoid introducing a new dependency.
* Avoid rewriting unrelated code.
* Do not replace a compatible router implementation with a desktop Linux pattern.
* Mention when the correction relies on a router-stock binary rather than a BusyBox applet.
* Mention when an Entware dependency is required.
* Do not suggest unavailable commands without also addressing their installation and lifecycle requirements.

A suggested patch must not fix one path while breaking rollback, interruption handling, IPv6, fresh installation, or uninstall behavior.
:::

This version intentionally concentrates Qodo on review findings while leaving implementation workflow and agent-response preferences in `AGENTS.md`. A paired, slimmed-down `AGENTS.md` can be prepared to eliminate duplication between the two files.
