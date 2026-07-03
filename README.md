<p align="center">
  <a href="https://ibb.co/Zm7hLhD"><img src="https://i.ibb.co/0tvfDfb/image.png" alt="Asuswrt-Merlin AdGuardHome Installer" border="0"></a>
</p>

# Asuswrt-Merlin AdGuardHome Installer

The official installer for running [AdGuardHome](https://github.com/AdguardTeam/AdGuardHome) on ARM-based ASUS routers with Asuswrt-Merlin firmware and Entware.

This project installs, updates, reconfigures, backs up, and removes AdGuardHome on supported Asuswrt-Merlin routers while keeping the router-side service scripts in place.

## Table of contents

- [Requirements](#requirements)
- [Known limitations](#known-limitations)
- [Features](#features)
- [Install, update, reconfigure, or uninstall](#install-update-reconfigure-or-uninstall)
- [Non-interactive commands](#non-interactive-commands)
- [Service commands](#service-commands)
- [Status and doctor diagnostics](#status-and-doctor-diagnostics)
- [Runtime behavior settings](#runtime-behavior-settings)
  - [Netcheck modes](#netcheck-modes)
  - [DNS port-owner cleanup policy](#dns-port-owner-cleanup-policy)
  - [Runtime optimization profile](#runtime-optimization-profile)
- [Verify AdGuardHome is running](#verify-adguardhome-is-running)
- [AdGuardHome DNS examples](#adguardhome-dns-examples)
- [Unused blocklist analyzer](#unused-blocklist-analyzer)
- [IPSET integration](#ipset-integration)
  - [Requirements and ownership](#requirements-and-ownership)
  - [Managed files and YAML](#managed-files-and-yaml)
  - [Rule syntax and examples](#rule-syntax-and-examples)
  - [Imported compatibility sources](#imported-compatibility-sources)
  - [Migration and refresh behavior](#migration-and-refresh-behavior)
  - [Locking and recovery](#locking-and-recovery)
  - [Verify and troubleshoot IPSET integration](#verify-and-troubleshoot-ipset-integration)
- [Reverse DNS notes](#reverse-dns-notes)
- [Troubleshooting and issue reports](#troubleshooting-and-issue-reports)
- [Static AdGuardHome archive cache](#static-adguardhome-archive-cache)
- [Development checks](#development-checks)
- [Project notes](#project-notes)
- [Donate](#donate)

## Requirements

- ARM-based ASUS router running Asuswrt-Merlin firmware.
- Minimum supported firmware version: `384.11`.
- Entware installed on a separate USB drive. The same drive should be used for AdGuardHome storage.
- Entware fully updated before installing:

  ```sh
  opkg update && opkg upgrade
  ```

- JFFS custom scripts/configs enabled.
- A swap file is strongly recommended. A minimum of `2 GB` is recommended; AMTM can create up to `10 GB`.
- A router stronger than the RT-AC68U is recommended. AdGuardHome can run on an RT-AC68U, but capacity may be limited.

## Known limitations

- Some double-NAT or dual-WAN environments may not be compatible because AdGuardHome takes over DNS service placement on port `53`.
- The installer moves DNSMASQ to port `553` when AdGuardHome owns port `53`.
- v2.5.0 keeps legacy runtime defaults for compatibility. New safer or more flexible behaviours are opt-in through documented settings.
- Unknown non-AdGuardHome owners of port `53` are still terminated by default to preserve legacy startup behaviour. Set `ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL=1` only if you want startup to abort instead.
- LAN-only or outage-tolerant installs can opt into `ADGUARD_NETCHECK_MODE=lan`; the default `legacy` mode keeps the previous public-host checks.
- Runtime proc/sysctl tuning remains enabled by default with the legacy aggressive profile. Set `ADGUARD_PROC_OPTIMIZE=NO` or select a lower profile if you do not want these writes.

## Features

- Installs AdGuardHome from official AdGuardHome binary packages.
- Supports ARM-based Asuswrt-Merlin routers.
- Can redirect LAN DNS queries to AdGuardHome when the Merlin DNS Filter option is selected.
- Supports updating AdGuardHome without reinstalling or reconfiguring from scratch.
- Includes installer, update, backup, reconfiguration, and uninstall flows.
- Provides service integration through Entware init scripts and Asuswrt-Merlin service events.
- Provides v2.5.0 diagnostics with `sh installer status` and `sh installer doctor`.
- Provides v2.5.0 non-interactive commands for repeatable install, update, backup, restore, doctor, IPSET refresh, performance profile, and uninstall tasks.
- Keeps legacy netcheck, DNS port-owner cleanup, and runtime optimization defaults while allowing users to opt into alternate behaviours.
- Can run an unused blocklist analyzer using menu option **9**, `sh installer blocklists`, or `sh installer unusedblocklists` to identify filter lists with zero query-log rule hits in the analyzed window.

## Install, update, reconfigure, or uninstall

Run the installer from an SSH shell on the router and follow the prompts:

```sh
curl -L -s -O https://raw.githubusercontent.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/master/installer && sh installer; rm installer
```

The same installer entry point is used for initial installation, updates, reconfiguration, and uninstall actions.

## Non-interactive commands

v2.5.0 adds command-line entry points for users who want repeatable actions without the interactive menu. Existing one-argument menu actions such as `sh installer update`, `sh installer install`, and `sh installer backup` still use the interactive compatibility path. Destructive non-interactive actions require `--yes`; install and uninstall actions that may rewrite DNS/NVRAM also require `--allow-dns-nvram`.

Examples:

```sh
sh installer install --installer-branch master --adguardhome-branch release --yes --allow-dns-nvram
sh installer update --installer-branch master --adguardhome-branch release --yes
sh installer update --dry-run
sh installer backup --yes
sh installer restore --file /opt/etc/backup_AdGuardHome.tar.gz --yes
sh installer restore --file /opt/etc/backup_AdGuardHome.tar.gz --dry-run
sh installer doctor
sh installer doctor --fix
sh installer status
sh installer ipset refresh
sh installer ipset refresh --yes
sh installer ipset refresh --dry-run
sh installer netcheck --mode wan --hosts "google.com github.com snbforums.com" --dns 127.0.0.1 --require-http NO --timeout 300
sh installer dns-port-policy --policy refuse-unknown
sh installer performance --profile balanced
sh installer uninstall --yes --allow-dns-nvram
sh installer uninstall --dry-run
```

`--installer-branch` selects the installer repository branch or tag used to fetch installer-managed artifacts. If it is omitted, the installer uses the saved `INSTALLER_BRANCH` value or falls back to `master`.

`--adguardhome-branch` selects the AdGuardHome binary channel. Supported AdGuardHome branches are `release`, `beta`, and `edge`. The older `--branch` option is retained as an alias for `--adguardhome-branch`; use `--installer-branch` when you need to change the installer branch.

The dry-run paths print what would be done and avoid changing the live install.

The `ipset refresh` command checks whether IPSET integration is enabled. Without `--yes`, it does not restart AdGuardHome; with `--yes`, it restarts AdGuardHome so refreshed mappings can take effect.

The `netcheck`, `dns-port-policy`, and `performance` helpers only update installer configuration values. Restart AdGuardHome when you want the changed runtime behaviour to be loaded by the service scripts.

## Service commands

Use the Entware init script directly:

```sh
/opt/etc/init.d/S99AdGuardHome {start|stop|restart|check|kill|reload}
```

Recommended Asuswrt-Merlin service commands:

```sh
service {start|stop|restart|kill|reload}_AdGuardHome
```

## Status and doctor diagnostics

Use `status` for a short service summary:

```sh
sh installer status
```

The status output includes the AdGuardHome service state, monitor state, PID count, port `53` ownership, AdGuardHome version, installer version, selected branch, WebUI address and port, dnsmasq handoff state, and the last startup result found in logs.

Use `doctor` for a broader health check:

```sh
sh installer doctor
```

The doctor command prints simple status lines such as:

```text
[OK] Entware /opt is mounted
[WARN] backup archive missing
[FAIL] DNS port 53 is not listening
```

Doctor checks include Entware mount state, AdGuardHome directories and symlinks, managed Asuswrt-Merlin hook scripts, Entware init scripts, `AdGuardHome.yaml`, `.config`, DNS port `53`, dnsmasq handoff markers and locks, monitor and daemon process counts, WebUI port ownership, installer and AdGuardHome versions, backup archive safety, IPSET files, and DNS-related NVRAM values.

Safe repairs can be requested with:

```sh
sh installer doctor --fix
```

The `--fix` mode is intentionally limited. It can repair permissions, recreate the expected `/opt/sbin/AdGuardHome` symlink, and remove stale handoff markers, stale pid files, and stale temporary files when they are not owned by an active process. It does not rewrite DNS, firewall, or NVRAM settings.

## Runtime behavior settings

v2.5.0 exposes several runtime behaviours through environment or `.config` settings while preserving the previous defaults until users opt into a change. Environment variables take precedence for the current invocation. Persistent settings can be placed in `/opt/etc/AdGuardHome/.config` using the same `NAME="value"` style already used by the installer.

### Netcheck modes

Default behaviour remains the legacy netcheck path:

```sh
ADGUARD_NETCHECK_MODE="legacy"
```

Legacy mode keeps the previous public-host checks against `google.com`, `github.com`, and `snbforums.com`, uses `127.0.0.1` for DNS lookups, waits up to `300` seconds for system time, and preserves the old DNS, ping, and HTTP probing flow.

Users who want the configurable v2.5.0 checks can set the values directly in `.config` or use the non-interactive helper:

```sh
sh installer netcheck --mode wan --hosts "google.com github.com snbforums.com" --dns 127.0.0.1 --require-http NO --timeout 300
```

This writes values equivalent to:

```sh
ADGUARD_NETCHECK_MODE="wan"
ADGUARD_NETCHECK_HOSTS="google.com github.com snbforums.com"
ADGUARD_NETCHECK_DNS="127.0.0.1"
ADGUARD_NETCHECK_REQUIRE_HTTP="NO"
ADGUARD_NETCHECK_TIMEOUT="300"
```

In `wan` mode, netcheck succeeds when system time is ready and at least one configured host resolves or pings. HTTP probing is required only when `ADGUARD_NETCHECK_REQUIRE_HTTP="YES"`.

For isolated LAN deployments or sites where public Internet reachability should not block local service management, run:

```sh
sh installer netcheck --mode lan
```

This writes:

```sh
ADGUARD_NETCHECK_MODE="lan"
```

LAN mode skips public WAN probes. The monitor still checks local AdGuardHome DNS responsiveness after the process is expected to be serving DNS.

### DNS port-owner cleanup policy

During startup, dnsmasq is stopped normally so AdGuardHome can own port `53`. By default, v2.5.0 keeps the legacy cleanup behaviour: if another non-AdGuardHome process still owns port `53`, the service script logs the owner and terminates that PID so startup can continue.

To opt into conservative handling, run:

```sh
sh installer dns-port-policy --policy refuse-unknown
```

This writes:

```sh
ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="1"
```

With refusal enabled, unknown non-dnsmasq owners of port `53` cause startup to abort instead of being terminated. The log message includes the PID, netstat owner, process name, and command when available.

If refusal is enabled and you still need to force termination for a specific startup, set:

```sh
ADGUARDHOME_FORCE_DNS_PORT_KILL="1"
```

`ADGUARDHOME_FORCE_DNS_PORT_KILL=1` overrides the refusal setting for that invocation.

To restore the default legacy cleanup policy, run:

```sh
sh installer dns-port-policy --policy legacy
```

This writes `ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="0"`.

### Runtime optimization profile

Runtime proc/sysctl tuning remains enabled by default to preserve the previous behaviour:

```sh
ADGUARD_PROC_OPTIMIZE="YES"
ADGUARD_PROC_PROFILE="aggressive"
```

The supported profiles are:

| Profile | Behaviour |
| --- | --- |
| `off` | Do not write proc/sysctl values. |
| `safe` | Set UDP receive and write buffer limits. |
| `balanced` | Apply `safe` plus lower the conntrack TCP max retrans timeout. |
| `aggressive` | Apply `balanced` plus the legacy PID, memory overcommit, swappiness, ICMP rate-limit, and neighbour-cache tuning. |

To disable runtime optimization completely, set:

```sh
ADGUARD_PROC_OPTIMIZE="NO"
```

To keep optimization enabled but select a lower profile, set for example:

```sh
ADGUARD_PROC_OPTIMIZE="YES"
ADGUARD_PROC_PROFILE="balanced"
```

The non-interactive performance helper maps user-facing profiles to runtime profiles:

```sh
sh installer performance --profile balanced
sh installer performance --profile low-memory
sh installer performance --profile fast
```

`balanced` writes `ADGUARD_PROC_PROFILE="balanced"`, `low-memory` writes `ADGUARD_PROC_PROFILE="safe"`, and `fast` writes `ADGUARD_PROC_PROFILE="aggressive"`. Runtime proc writes are logged with old and new values when they are attempted, and startup does not fail only because a proc/sysctl write fails.

## Verify AdGuardHome is running

Check for the AdGuardHome process:

```sh
pidof AdGuardHome
```

If AdGuardHome is running, the command returns one or more process IDs.

You can also use the service check command:

```sh
/opt/etc/init.d/S99AdGuardHome check
```

Expected output when AdGuardHome is alive:

```text
  Checking AdGuardHome...              alive.
```

## AdGuardHome DNS examples

AdGuardHome supports many upstream DNS formats, including plain DNS, DNS-over-TLS, DNS-over-HTTPS, DNS-over-QUIC, DNSCrypt, and split DNS rules.

<p align="center">
  <a href="https://ibb.co/ZhTX4N4"><img src="https://i.ibb.co/cNT3fxf/Features.jpg" alt="AdGuardHome features" border="0"></a>
</p>

Examples:

- `94.140.14.140` - plain DNS over UDP.
- `tls://dns-unfiltered.adguard.com` - encrypted DNS-over-TLS.
- `https://cloudflare-dns.com/dns-query` - encrypted DNS-over-HTTPS.
- `quic://dns-unfiltered.adguard.com:784` - experimental DNS-over-QUIC.
- `tcp://1.1.1.1` - plain DNS over TCP.
- `sdns://...` - DNS stamp for DNSCrypt or DNS-over-HTTPS resolvers.
- `[/example.local/]1.1.1.1` - route a specific domain suffix to a specific upstream.

<p align="center">
  <a href="https://ibb.co/txhZqvt"><img src="https://i.ibb.co/SdxQtM8/Upstream-DNS.jpg" alt="AdGuardHome upstream DNS" border="0"></a>
</p>

More DNS provider references:

- [SNBForums AdGuardHome installer thread](http://www.snbforums.com/threads/release-asuswrt-merlin-adguardhome-installer-amaghi.76506/post-735471)
- [AdGuard DNS providers knowledge base](https://adguard-dns.io/kb/general/dns-providers/)
- [AdGuardHome wiki](https://github.com/AdguardTeam/AdGuardHome/wiki)

## Unused blocklist analyzer

Run the analyzer from installer menu option **9**, or call it directly with `sh installer blocklists` or `sh installer unusedblocklists`. The installer can download and run [`blocklilst_analyzer.py`](https://gist.github.com/graysky2/8035291d1bf87b8fe3693668965337e1), an AdGuard Home Blocklist Usage Analyzer script by [@graysky2](https://github.com/graysky2). The analyzer inspects AdGuardHome data under `${TARG_DIR}/data`, the filter cache under `${TARG_DIR}/data/filters`, and the AdGuardHome query log to report which filter lists had matching blocking-rule hits during the analyzed log window.

In this report, **unused** means the blocklist had zero `Result.Rules[].FilterListID` hits in the query log entries that were analyzed. It does **not** mean the list is globally useless, redundant for every network, or safe to remove in all future traffic patterns. Review the printed list carefully before confirming any removal because removing filter lists can change blocking behavior.

When removal is confirmed, the installer backs up `${TARG_DIR}/AdGuardHome.yaml`, removes matching unused filter entries by `id:`, validates the resulting YAML with AdGuardHome's configuration checker, and restores the backup if validation fails. This restore path is intended to keep AdGuardHome from being left with an invalid configuration after an interrupted or failed cleanup.

Removal can be handled in two ways after the unused list report is printed. The **ALL** option removes every listed unused filter in one pass after a single confirmation, which is faster but should be used only after reviewing the full printed list. The **one by one** option prompts for each unused filter individually so you can keep specific lists even if they were unused during the analyzed window. Both paths remove filters by their AdGuardHome `id:` entries and use the same backup, validation, and restore safety checks before the changed configuration is kept.

Python 3 is required to run the analyzer. On Entware-based installs, install it before using the analyzer if the installer has not already installed it for you:

```sh
opkg install python3 coreutils-sha256sum
```

For SHA-256 verification support on firmware builds that do not include `sha256sum`, install:

```sh
opkg install coreutils-sha256sum
```

`python3` and `coreutils-sha256sum` are Entware dependencies, not a stock Asuswrt-Merlin router command. The analyzer itself is optional; users who do not want Entware Python 3 installed can skip this feature and manage filter lists manually from the AdGuardHome web interface.

## IPSET integration

The installer can integrate AdGuardHome with IPSET-based routing and firewall add-ons by configuring AdGuardHome's `dns.ipset_file` setting. When AdGuardHome resolves a matching domain, it adds returned IPv4 or IPv6 addresses to the named IPSET so the add-on that owns that set can apply its routing or firewall policy. The integration can be enabled or disabled from installer menu option **8**; existing installations without an `ADGUARD_IPSET` setting remain enabled for backward compatibility.

### Requirements and ownership

- IPSET integration is optional. If installer-managed mappings cannot be prepared, the installer removes the managed `dns.ipset_file` reference before allowing AdGuardHome to start without IPSET integration. Startup is aborted only when that reference cannot be safely removed, preventing stale routing or firewall mappings from remaining active.
- IPSET integration is available only on Linux. AdGuardHome added `dns.ipset_file` in v0.107.13; this integration requires v0.107.48 or later because the generated file contains supported comment lines.
- The routing or firewall add-on remains responsible for creating, restoring, flushing, and deleting its IPSETs and for installing any rules that use them. The AdGuardHome installer only supplies domain-to-IPSET mappings and does not create IPSETs or policy-routing/firewall rules.
- A target set must already exist when AdGuardHome tries to add an address. IPv4 answers require a set with the `ipv4` family, and IPv6 answers require a set with the `ipv6` family.
- Domain VPN Routing, x3mRouting, WireGuard Manager, Skynet/IPSet_ASUS, or another add-on should be installed and configured according to that project's instructions before its set names are referenced here.

See the upstream [AdGuardHome configuration documentation](https://github.com/AdguardTeam/AdGuardHome/wiki/Configuration#configuration-file) for the authoritative `dns.ipset` and `dns.ipset_file` behavior.

### Managed files and YAML

The integration uses the following files:

| Path | Owner | Purpose |
| --- | --- | --- |
| `/opt/etc/AdGuardHome/AdGuardHome.yaml` | AdGuardHome and this installer | The installer sets `dns.ipset: []` and points `dns.ipset_file` to the generated file. |
| `/opt/etc/AdGuardHome/ipset.conf` | This installer | Generated AdGuardHome rule file. It is rebuilt atomically and must not be edited manually. |
| `/opt/etc/AdGuardHome/ipset.user` | User | Persistent custom and migrated rules. Add manual rules here. |
| `/opt/var/run/AdGuardHome-ipset/flock` | Locking code | Runtime lock file used when file-descriptor `flock` is supported. |
| `/opt/var/run/AdGuardHome-ipset/mkdir/` | Locking code | Runtime legacy lock directory used when `flock` is unavailable. |

The resulting YAML contains entries equivalent to:

```yaml
dns:
  ipset: []
  ipset_file: /opt/etc/AdGuardHome/ipset.conf
```

AdGuardHome ignores inline `dns.ipset` rules when `dns.ipset_file` is configured, so migrated custom rules are kept in `ipset.user` and merged into `ipset.conf`. The generated file may be replaced during startup, dnsmasq configuration, or firewall events; manual changes to `ipset.conf` will be lost. If a refresh finds no user or dnsmasq mappings, the installer removes the empty generated file and the managed `dns.ipset_file` setting instead of preventing AdGuardHome from starting. If setup fails, the installer removes the managed `dns.ipset_file` reference and allows AdGuardHome to start without IPSET integration. If the reference cannot be safely removed, startup is aborted rather than retaining stale mappings. Refresh failures are logged and leave the existing running configuration unchanged until a later successful refresh.

Both IPSET files are inside `/opt/etc/AdGuardHome`, so the installer's normal backup and restore flow includes them. Uninstalling the installer removes them with the rest of that directory.

### Rule syntax and examples

Write one AdGuardHome IPSET rule per line in `ipset.user` using this format:

```text
DOMAIN[,DOMAIN,...]/IPSET_NAME[,IPSET_NAME,...]
```

Examples:

```text
example.com/ROUTE_VPN
example.net,example.org/ROUTE_WG
streaming.example/ROUTE_VPN,TRACK_STREAMING
```

The first example adds answers for `example.com` to `ROUTE_VPN`. The second associates multiple domains with one set. The third associates one domain with multiple sets.

Rules in `ipset.user` are already in AdGuardHome format: do not add the dnsmasq `ipset=` prefix or surround domains with leading and trailing slashes. Empty lines are discarded. Exact duplicate lines are written only once. Lines beginning with `#` may be used for comments. AdGuardHome supports comments in `ipset_file` starting with v0.107.48.

A compatible dnsmasq directive such as:

```text
ipset=/example.com/example.net/ROUTE_VPN
```

is converted to:

```text
example.com,example.net/ROUTE_VPN
```

### Imported compatibility sources

Each refresh scans active, non-commented dnsmasq `ipset=` directives from the configuration passed by the current dnsmasq hook and from these locations when they exist:

```text
/etc/dnsmasq.conf
/etc/dnsmasq-<index>.conf
/jffs/configs/dnsmasq.conf.add
/jffs/configs/dnsmasq.d/*.conf
/jffs/addons/x3mRouting/*.conf
/jffs/configs/domain_vpn_routing/*.conf
/jffs/addons/wireguard/*.conf
```

Guest Network Pro/SDN post-configuration also passes the matching `/etc/dnsmasq-<index>.conf` file to the refresh. Every refresh scans all existing numeric-index SDN dnsmasq configurations as well, so overlapping post-configuration callbacks retain mappings from the other active SDNs. These sources cover dnsmasq directives produced by the supported routing integrations; any compatible directive present in the scanned files is imported regardless of which add-on wrote it.

The collector imports mappings only. It does not execute another add-on, copy its firewall rules, infer missing set names, or create the target IPSET. Files outside the listed locations are not scanned automatically; copy persistent custom mappings into `ipset.user` instead.

### Migration and refresh behavior

On each setup run, the installer checks whether it already owns the YAML IPSET configuration:

- If `dns.ipset_file` is empty or points to `/opt/etc/AdGuardHome/ipset.conf`, supported inline `dns.ipset` entries are merged into `ipset.user`, exact duplicates and empty lines are removed, and the YAML is normalized to the managed settings shown above. Existing `ipset.user` rules are preserved.
- If `dns.ipset_file` points anywhere else, the installer leaves the YAML and external file untouched, skips its managed IPSET migration and refresh for that run, and allows AdGuardHome to use the existing configuration. To opt in to managed integration, copy persistent mappings from the external file into `ipset.user`, clear `dns.ipset_file` while AdGuardHome is stopped, and restart AdGuardHome.
- If no mappings are available after migration and collection, the installer removes its managed `dns.ipset_file` setting and starts AdGuardHome normally. The setting is restored automatically when integration is enabled and a later refresh discovers mappings.
- If IPSET integration is disabled from installer menu option **8**, startup removes only the installer-managed `dns.ipset_file` setting. `ipset.user` is retained so custom mappings are available if the feature is re-enabled.

The installer never reads or imports a YAML-selected external file with elevated privileges. Once managed integration is active, it generates `ipset.conf` from `ipset.user` plus all detected compatible dnsmasq directives.

Refreshes occur at these points:

- before AdGuardHome starts or restarts;
- after the standard dnsmasq post-configuration hook runs;
- after a Guest Network Pro/SDN dnsmasq post-configuration hook runs;
- when Asuswrt-Merlin invokes `/jffs/scripts/firewall-start`.

To apply changes after editing `ipset.user`, restart AdGuardHome so the generated file is refreshed before AdGuardHome reloads its configuration:

```sh
service restart_AdGuardHome
```

To regenerate `ipset.conf` manually, run:

```sh
/jffs/addons/AdGuardHome.d/AdGuardHome.sh firewall
```

A refresh writes a temporary file, removes empty and exact duplicate lines, and replaces `ipset.conf` only when its content changed. If AdGuardHome is running and the generated file changes, the command restarts AdGuardHome so the updated IPSET rules take effect; unchanged output does not trigger a restart.

### Locking and recovery

Concurrent setup and refresh events are serialized to prevent multiple writers from replacing the YAML or generated rule file at the same time:

- Firmware with working file-descriptor locking waits on `flock` for `/opt/var/run/AdGuardHome-ipset/flock`, so a concurrent invocation runs after the active writer finishes.
- Older firmware falls back to `/opt/var/run/AdGuardHome-ipset/mkdir/`, records the owner PID, waits up to 30 seconds, and removes a stale lock when its owner no longer exists.
- Both lock paths save the caller's current traps, install temporary cleanup traps for `EXIT`, `HUP`, `INT`, `QUIT`, `ABRT`, `TERM`, and `TSTP`, and restore the previous trap environment before returning. This prevents IPSET cleanup from replacing the manager's monitor or exit handlers.

Do not remove an active lock. If a legacy lock remains after an abnormal termination and its recorded process is no longer running, the next refresh removes it automatically.

### Verify and troubleshoot IPSET integration

Confirm that the YAML points to the managed file:

```sh
grep -A 2 '^  ipset:' /opt/etc/AdGuardHome/AdGuardHome.yaml
```

Review persistent and generated rules:

```sh
cat /opt/etc/AdGuardHome/ipset.user
cat /opt/etc/AdGuardHome/ipset.conf
```

Confirm that the target sets exist before testing DNS answers:

```sh
ipset list -n
ipset list ROUTE_VPN
```

After querying a mapped domain through AdGuardHome, inspect the owning set again. If no address appears:

1. Confirm that the domain mapping is present in `ipset.conf` and uses AdGuardHome syntax.
2. Confirm that the target set exists and has the correct IPv4 or IPv6 family.
3. Restart AdGuardHome after changing `ipset.user` or the YAML.
4. Confirm that the query was answered by this AdGuardHome instance and was not served exclusively by another resolver.
5. Check system logging for refresh or lock errors:

   ```sh
   logread | grep -iE 'AdGuardHome|IPSET'
   ```

6. Run AdGuardHome's configuration validation:

   ```sh
   /opt/sbin/AdGuardHome --check-config -c /opt/etc/AdGuardHome/AdGuardHome.yaml --no-check-update -l /dev/null
   ```

When reporting a problem, include `AdGuardHome.yaml`, `ipset.user`, `ipset.conf`, the relevant dnsmasq/add-on configuration, `ipset list` output for the referenced sets, and the installer diagnostic archive described below. Remove private domains or addresses before publishing logs or configuration files.

## Reverse DNS notes

The installer configures reverse DNS integration automatically. The notes below are included for users who want to understand or review the router-side configuration.

<p align="center">
  <a href="https://imgbb.com/"><img src="https://i.ibb.co/QvJ5nNV/Lan.jpg" alt="Asuswrt-Merlin LAN domain settings" border="0"></a>
</p>

In the Asuswrt-Merlin LAN DHCP page, define a local domain such as `lan` or another local-only domain.

<p align="center">
  <a href="https://ibb.co/vDRpFQh"><img src="https://i.ibb.co/4J3zqY2/Reverse-DNS.jpg" alt="AdGuardHome private reverse DNS settings" border="0"></a>
</p>

Then review the matching rules in AdGuardHome under Private Reverse DNS Servers.

## Troubleshooting and issue reports

For AdGuardHome application issues that are not installer-specific, use the upstream AdGuardHome issue tracker:

- <https://github.com/AdguardTeam/AdGuardHome/issues>

For installer issues, include the following information:

- DNS server selected during installation.
- Router model.
- Asuswrt-Merlin firmware version.
- A tar archive containing the relevant installer, service, and configuration paths listed below.

Relevant paths:

```text
/opt/etc/AdGuardHome
/opt/sbin/AdGuardHome
/opt/etc/init.d/S99AdGuardHome
/opt/etc/init.d/rc.func.AdGuardHome
/jffs/addons/AdGuardHome.d
/jffs/scripts/init-start
/jffs/scripts/dnsmasq.postconf
/jffs/scripts/firewall-start
/jffs/scripts/services-stop
/jffs/scripts/service-event-end
```

Create the diagnostic archive from the router SSH shell:

```sh
echo .config > exclude-files; tar -cvf AdGuardHome.tar -X exclude-files /opt/etc/AdGuardHome /opt/sbin/AdGuardHome /opt/etc/init.d/S99AdGuardHome /opt/etc/init.d/rc.func.AdGuardHome /jffs/addons/AdGuardHome.d /jffs/scripts/init-start /jffs/scripts/dnsmasq.postconf /jffs/scripts/firewall-start /jffs/scripts/services-stop /jffs/scripts/service-event-end; rm exclude-files
```

Attach `AdGuardHome.tar` to the issue report.

## Static AdGuardHome archive cache

This repository includes a scheduled GitHub Actions workflow that refreshes local static copies of upstream AdGuardHome archives four times per day: 00:00, 06:00, 12:00, and 18:00 UTC.

The workflow downloads stable, beta, and edge archives from `https://static.adguard.com/adguardhome/<channel>/AdGuardHome_<platform>_<architecture>.tar.gz` and saves them by router architecture folder:

- `armv8/` stores `linux_arm64` archives.
- `armv7/` stores `linux_armv7` archives.
- `armv5/` stores `linux_armv5` archives.

Archives are written with versioned local filenames, such as `AdGuardHome_stable_v0.107.62_linux_arm64.tar.gz`, and `checksum.txt` is published after the archives and checksum sidecars are ready. Installers use `checksum.txt` to select the current archive, which avoids exposing a newly referenced archive before its SHA-256 sidecar is available.

Each architecture folder also gets generated metadata:

- `VERSION.txt` lists each archive, local channel name, upstream channel name, and AdGuardHome version from upstream `version.txt`.
- `checksum.txt` lists each archive with its channel, version, MD5 checksum, and SHA-256 checksum.
- `*.tar.gz.sha256sum` sidecar files contain the preferred SHA-256 integrity checksum for the matching compressed archive.
- `*.tar.gz.md5sum` sidecar files are retained as compatibility metadata for older installer flows and mirrors that do not have SHA-256 sidecars yet.

The local stable filenames use `stable`, while the upstream static AdGuardHome channel path remains `release` to match the installer branch naming.

## Development checks

Repository shell scripts are written for POSIX/BusyBox `ash` compatibility. Avoid Bash-only syntax such as arrays, process substitution, `[[ ... ]]`, and non-portable `pipefail`.

Run the repository quality helper before opening a pull request:

```sh
tools/code-quality.sh
```

The helper validates installer artifact checksum files, runs ShellCheck on detected shell scripts, and checks formatting with `shfmt`. SHA-256 metadata is preferred for release integrity checks; `.md5sum` files remain compatibility metadata and are used only when SHA-256 metadata is unavailable.

To apply `shfmt` formatting locally, run:

```sh
tools/code-quality.sh --fix
```

If CI reports `shfmt` formatting differences, you can also run the `Create shfmt formatting PR` workflow against the affected branch to open an automated formatting pull request.

Pull requests that change shell scripts, checksum files, tools, prompts, or workflows are also reviewed by the Codex Code Improvement workflow when the repository has an `OPENAI_API_KEY` Actions secret configured. The Codex prompt includes the local code-quality output so formatting failures can be reported with the same remediation steps shown in CI.

## Project notes

- Changelog: <https://github.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/commits/master>
- AdGuardHome binaries come from <https://github.com/AdguardTeam/AdGuardHome>.
- The installer script was inspired by `entware-setup.sh` from Asuswrt-Merlin.
- License: [GPL-3.0](https://raw.githubusercontent.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/master/LICENSE)

## Donate

This script is open source and free to use under the GPL-3.0 license. If you want to support future development, you can donate through:

- [PayPal](https://paypal.me/swotrb)
- [Buy Me a Coffee](https://www.buymeacoffee.com/swotrb)
