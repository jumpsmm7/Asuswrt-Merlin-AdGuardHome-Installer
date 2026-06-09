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
- [IPSet integration](#ipset-integration)
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
- Mirrors dnsmasq `ipset=` domain associations into AdGuardHome, including Skynet shared-whitelist rules, while preserving valid mappings added directly to AdGuardHome’s `ipset.conf`.

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

## IPSet integration

AdGuardHome can add the IP addresses returned for selected domain names to Linux IPSet sets.  This is useful when firewall tools such as Skynet need domain-based allowlists or blocklists, because the firewall can match the resulting IP addresses without intercepting or bypassing DNS traffic.

The installer configures the following setting inside the `dns:` section of `/opt/etc/AdGuardHome/AdGuardHome.yaml`:

```yaml
dns:
  ipset_file: /jffs/addons/AdGuardHome.d/ipset.conf
```

The referenced kernel IPSet sets must already exist.  AdGuardHome fills existing sets; it does not create them.  For example, an IPv4 set can be created with:

```sh
ipset create ExampleSet hash:ip family inet -exist
```

Use a separate `family inet6` set for IPv6 addresses when required.  Confirm that a set exists and inspect its members with:

```sh
ipset list ExampleSet
```

### Method 1: Manage mappings through dnsmasq configuration

Add dnsmasq-style mappings to `/jffs/configs/dnsmasq.conf.add`:

```text
ipset=/example.com/example.net/ExampleSet
```

Multiple destination sets can be specified after the final slash:

```text
ipset=/example.com/ExampleSet,AnotherSet
```

The manager converts these entries to AdGuardHome's `DOMAIN[,DOMAIN]/IPSET[,IPSET]` format.  The first example becomes:

```text
example.com,example.net/ExampleSet
```

Apply changes by restarting dnsmasq:

```sh
service restart_dnsmasq
```

The dnsmasq post-configuration hook regenerates `/jffs/addons/AdGuardHome.d/ipset.conf`.  If the effective mappings changed, the manager restarts AdGuardHome so it reloads the file.

### Automatic imports from routing add-ons

The manager also imports domain-to-set mappings maintained by these routing add-ons:

- **x3mRouting:** reads active x3mRouting commands from `/jffs/scripts/nat-start`. Both `dnsmasq=domain1,domain2` and `dnsmasq_file=/path/to/domain-list` are supported, including current `ipset_name=SetName` commands and converted legacy commands whose set name is positional.
- **Domain-based VPN Routing by Ranger802004:** reads each `/jffs/configs/domain_vpn_routing/policy_*_domainlist` file and associates its domains with the corresponding existing `DomainVPNRouting-<policy>-ipv4` and/or `DomainVPNRouting-<policy>-ipv6` sets.
- **WireGuard Session Manager:** discovers enabled set names from `/opt/etc/wireguard.d/Wireguard.db`. Existing WGM `ipset=` rules in `/jffs/configs/dnsmasq.conf.add` are already imported by Method 1. Optional AdGuardHome-only domain lists can also be stored in `/opt/etc/wireguard.d/ipset.d/<IPSET>.domains`.

These imports copy domain mappings into AdGuardHome; they do not copy the current IP addresses stored in a set. AdGuardHome then adds newly resolved IPv4 and IPv6 addresses to the same existing sets used by the routing add-on.

WireGuard Session Manager stores routing set names and state, but not domain names. For a WGM set that should be populated only by AdGuardHome, first enable the set in WGM and then create a matching domain file. For example:

```sh
mkdir -p /opt/etc/wireguard.d/ipset.d
cat > /opt/etc/wireguard.d/ipset.d/NETFLIX-DNS.domains <<'EOF'
netflix.com
netflix.net
nflxvideo.net
EOF
```

The filename before `.domains` must exactly match an enabled IPSet shown by `wgm ipset`. Domain files accept one domain or a comma-separated domain group per line; blank lines and `#` comments are ignored. Disabled or deleted WGM sets are not imported from these files.

The synchronization runs during AdGuardHome service startup, dnsmasq post-configuration, and firewall-start. To request it manually, run:

```sh
/jffs/addons/AdGuardHome.d/AdGuardHome.sh ipset
```

Restart AdGuardHome after manually requesting a synchronization if the service monitor is not running.

### Method 2: Add AdGuardHome-only mappings

Mappings that should not be managed through dnsmasq can be added directly to `/jffs/addons/AdGuardHome.d/ipset.conf`, one rule per line:

```text
updates.example.com/UpdateServers
video.example.com,cdn.example.com/StreamingServers
```

After editing the file directly, restart AdGuardHome so it reloads the mappings:

```sh
service restart_AdGuardHome
```

Direct entries are preserved when automatic mappings are synchronized. The manager tracks mappings imported from dnsmasq, x3mRouting, Domain-based VPN Routing, and WireGuard Session Manager in `/jffs/addons/AdGuardHome.d/ipset.sources.conf`. This allows obsolete imported rules to be removed without deleting valid AdGuardHome-only entries. Existing installations are migrated automatically from the former `ipset.dnsmasq.conf` state file.

> [!IMPORTANT]
> Do not edit `ipset.sources.conf`; it is managed automatically. The effective `ipset.conf` is normalized, sorted, and deduplicated during synchronization, so formatting and comments may be removed.

### Verify that IPSet integration is working

1. Confirm that the YAML points to the managed file:

   ```sh
   grep -A5 '^dns:' /opt/etc/AdGuardHome/AdGuardHome.yaml | grep ipset_file
   ```

2. Review the effective mappings:

   ```sh
   cat /jffs/addons/AdGuardHome.d/ipset.conf
   ```

3. Query a mapped domain through AdGuardHome:

   ```sh
   nslookup example.com "$(nvram get lan_ipaddr)"
   ```

4. Check whether its resolved address was added to the target set:

   ```sh
   ipset list ExampleSet
   ```

AdGuardHome's IPSet syntax and behavior are documented in the upstream [AdGuardHome configuration reference](https://github.com/AdguardTeam/AdGuardHome/wiki/Configuration#configuration-file).

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
/jffs/scripts/services-stop
/jffs/scripts/service-event-end
```

Create the diagnostic archive from the router SSH shell:

```sh
echo .config > exclude-files; tar -cvf AdGuardHome.tar -X exclude-files /opt/etc/AdGuardHome /opt/sbin/AdGuardHome /opt/etc/init.d/S99AdGuardHome /opt/etc/init.d/rc.func.AdGuardHome /jffs/addons/AdGuardHome.d /jffs/scripts/init-start /jffs/scripts/dnsmasq.postconf /jffs/scripts/services-stop /jffs/scripts/service-event-end; rm exclude-files
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
