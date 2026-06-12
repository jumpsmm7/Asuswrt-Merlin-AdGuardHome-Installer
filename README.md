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
- [Service commands](#service-commands)
- [Verify AdGuardHome is running](#verify-adguardhome-is-running)
- [AdGuardHome DNS examples](#adguardhome-dns-examples)
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

## Features

- Installs AdGuardHome from official AdGuardHome binary packages.
- Supports ARM-based Asuswrt-Merlin routers.
- Can redirect LAN DNS queries to AdGuardHome when the Merlin DNS Filter option is selected.
- Supports updating AdGuardHome without reinstalling or reconfiguring from scratch.
- Includes installer, update, backup, reconfiguration, and uninstall flows.
- Provides service integration through Entware init scripts and Asuswrt-Merlin service events.

## Install, update, reconfigure, or uninstall

Run the installer from an SSH shell on the router and follow the prompts:

```sh
curl -L -s -O https://raw.githubusercontent.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/master/installer && sh installer; rm installer
```

The same installer entry point is used for initial installation, updates, reconfiguration, and uninstall actions.

## Service commands

Use the Entware init script directly:

```sh
/opt/etc/init.d/S99AdGuardHome {start|stop|restart|check|kill|reload}
```

Recommended Asuswrt-Merlin service commands:

```sh
service {start|stop|restart|kill|reload}_AdGuardHome
```

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

## IPSET integration

The installer can integrate AdGuardHome with IPSET-based routing and firewall add-ons by configuring AdGuardHome's `dns.ipset_file` setting. When AdGuardHome resolves a matching domain, it adds returned IPv4 or IPv6 addresses to the named IPSET so the add-on that owns that set can apply its routing or firewall policy. The integration can be enabled or disabled from installer menu option **8**; existing installations without an `ADGUARD_IPSET` setting remain enabled for backward compatibility.

### Requirements and ownership

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

AdGuardHome ignores inline `dns.ipset` rules when `dns.ipset_file` is configured, so migrated custom rules are kept in `ipset.user` and merged into `ipset.conf`. The generated file may be replaced during startup, dnsmasq configuration, or firewall events; manual changes to `ipset.conf` will be lost. If a refresh finds no user or dnsmasq mappings, the installer removes the empty generated file and the managed `dns.ipset_file` setting instead of preventing AdGuardHome from starting.

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

Each architecture folder also gets generated metadata:

- `VERSION.txt` lists each archive, local channel name, upstream channel name, and AdGuardHome version from upstream `version.txt`.
- `checksum.txt` lists each archive with its channel, version, MD5 checksum, and SHA-256 checksum.
- `*.tar.gz.md5sum` sidecar files contain only the MD5 checksum for the matching compressed archive.

The local stable filenames use `stable`, while the upstream static AdGuardHome channel path remains `release` to match the installer branch naming.

## Development checks

Repository shell scripts are written for POSIX/BusyBox `ash` compatibility. Avoid Bash-only syntax such as arrays, process substitution, `[[ ... ]]`, and non-portable `pipefail`.

Run the repository quality helper before opening a pull request:

```sh
tools/code-quality.sh
```

The helper validates installer artifact `.md5sum` files, runs ShellCheck on detected shell scripts, and checks formatting with `shfmt`.

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
