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

The installer automatically enables AdGuardHome's `dns.ipset_file` support and maintains these files:

- `/opt/etc/AdGuardHome/ipset.conf` - generated rules consumed by AdGuardHome.
- `/opt/etc/AdGuardHome/ipset.user` - persistent user-managed rules that are merged into the generated file.

Existing inline `dns.ipset` rules and an existing external `dns.ipset_file` are migrated into `ipset.user` the first time the integration runs. The manager also imports dnsmasq-style `ipset=/domain/set` directives used by Domain VPN Routing, x3mRouting, and WireGuard Manager. Refreshes run during AdGuardHome startup, dnsmasq post-configuration, and firewall-start events.

Use AdGuardHome's `DOMAIN[,DOMAIN,...]/IPSET_NAME[,IPSET_NAME,...]` syntax for custom entries in `ipset.user`. The referenced IPSETs must already be created by the routing or firewall add-on that owns them.

Concurrent refreshes are serialized with `flock` when file-descriptor locking is supported. Older firmware falls back to a stale-aware `mkdir` lock. Both paths restore the manager's existing trap handlers after cleanup.

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
