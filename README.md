<a href="https://ibb.co/Zm7hLhD"><img src="https://i.ibb.co/0tvfDfb/image.png" alt="image" border="0"></a>

# Asuswrt-Merlin-AdGuardHome-Installer

The official installer for [AdGuard Home](https://github.com/AdguardTeam/AdGuardHome) on Asuswrt-Merlin.

## Requirements

- ARM-based ASUS router running Asuswrt-Merlin firmware.
- Entware installed on a separate USB drive used for storage.
- JFFS custom scripts and configs enabled.
- Entware fully updated before installing:

```sh
opkg update && opkg upgrade
```

- A swap file is strongly recommended. A minimum of 2 GB is recommended, and larger swap files can be created with AMTM if needed.
- Minimum supported Asuswrt-Merlin firmware version: `384.11`.
- A router stronger than the RT-AC68U is recommended. AdGuard Home can run on the RT-AC68U, but only at a limited capacity.

## Incompatibilities and Important Notes

- There are no confirmed universal incompatibilities at this time.
- Some double-NAT or dual-WAN environments may require additional testing or manual adjustment.
- AdGuard Home takes over DNS service placement on port `53`.
- `dnsmasq` is moved to port `553` by the installer.
- Do not run another DNS service on port `53` at the same time unless you know exactly how it interacts with this installer.

## Current Features

- Installs and manages [AdGuard Home](https://github.com/AdguardTeam/AdGuardHome), a network-wide DNS server for blocking ads, trackers, and malicious domains.
- Supports encrypted DNS protocols such as DNS-over-HTTPS, DNS-over-TLS, and DNS-over-QUIC when configured in AdGuard Home.
- Supports ARM-based Asuswrt-Merlin routers.
- Can redirect LAN DNS queries to AdGuard Home when the user chooses the Merlin DNS Filter option.
- Supports updating AdGuard Home without a full reinstall or full reconfiguration.
- Includes installer, update, backup, restore, and uninstall functions.

## AdGuard Home Supports Multiple Upstream DNS Formats

<a href="https://ibb.co/ZhTX4N4"><img src="https://i.ibb.co/cNT3fxf/Features.jpg" alt="Features" border="0"></a>

Examples:

- `94.140.14.140`: plain DNS over UDP.
- `tls://dns-unfiltered.adguard.com`: encrypted DNS-over-TLS.
- `https://cloudflare-dns.com/dns-query`: encrypted DNS-over-HTTPS.
- `quic://dns-unfiltered.adguard.com:784`: DNS-over-QUIC.
- `tcp://1.1.1.1`: plain DNS over TCP.
- `sdns://...`: DNS stamps for DNSCrypt or DNS-over-HTTPS resolvers.
- `[/example.local/]1.1.1.1`: upstream DNS server for a specific domain.

<a href="https://ibb.co/txhZqvt"><img src="https://i.ibb.co/SdxQtM8/Upstream-DNS.jpg" alt="Upstream-DNS" border="0"></a>

Additional DNS provider references:

- SNBForums setup discussion: http://www.snbforums.com/threads/release-asuswrt-merlin-adguardhome-installer-amaghi.76506/post-735471
- AdGuard DNS providers: https://adguard-dns.io/kb/general/dns-providers/

## Setting Up Router Reverse DNS

<a href="https://imgbb.com/"><img src="https://i.ibb.co/QvJ5nNV/Lan.jpg" alt="Lan" border="0"></a>

- On the Asuswrt-Merlin LAN DHCP page, define a local domain such as `lan` or another preferred local domain.

<a href="https://ibb.co/vDRpFQh"><img src="https://i.ibb.co/4J3zqY2/Reverse-DNS.jpg" alt="Reverse-DNS" border="0"></a>

- Define the appropriate rules inside **Private reverse DNS servers**.
- The installer already configures the needed reverse DNS behavior, but this section is included for user reference and troubleshooting.

## Best AdGuard Home Setup Guide

For AdGuard Home configuration guidance, see the official wiki:

https://github.com/AdguardTeam/AdGuardHome/wiki

## AdGuard Home Development and Upstream Issues

For issues with AdGuard Home itself, report them upstream:

https://github.com/AdguardTeam/AdGuardHome/issues

## Changelog

https://github.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/commits/master

## Install, Update, Reconfigure, or Uninstall

Run this command from an SSH shell on the router and follow the prompts:

```sh
curl -L -s -O https://raw.githubusercontent.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/master/installer && sh installer; rm installer
```

For development branch testing only:

```sh
curl -L -s -O https://raw.githubusercontent.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/dev/readme-installer-improvements/installer && sh installer; rm installer
```

## Service Commands

Direct init script command:

```sh
/opt/etc/init.d/S99AdGuardHome {start|stop|restart|check|kill|reload}
```

Recommended service commands:

```sh
service {start|stop|restart|kill|reload}_AdGuardHome
```

## How to Check Whether AdGuard Home Is Running

Run:

```sh
pidof AdGuardHome
```

If AdGuard Home is running, the command returns one or more process IDs.

You can also run:

```sh
/opt/etc/init.d/S99AdGuardHome check
```

Expected output:

```text
  Checking AdGuardHome...              alive.
```

## How to Report an Issue

When reporting an issue, include the following information:

- DNS server option selected during AdGuard Home installation.
- Router model.
- Asuswrt-Merlin firmware version.
- Whether your setup uses dual WAN, double NAT, VPN Director, DNS Director, or other DNS-related scripts.
- Any relevant install or update error messages.

The following directories and files are useful for debugging:

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

You can create a debug archive with:

```sh
echo .config > exclude-files; tar -cvf AdGuardHome.tar -X exclude-files /opt/etc/AdGuardHome /opt/sbin/AdGuardHome /opt/etc/init.d/S99AdGuardHome /opt/etc/init.d/rc.func.AdGuardHome /jffs/addons/AdGuardHome.d /jffs/scripts/init-start /jffs/scripts/dnsmasq.postconf /jffs/scripts/services-stop /jffs/scripts/service-event-end; rm exclude-files
```

The archive is created in the current directory as `AdGuardHome.tar`. Review the archive before sharing it to make sure it does not contain private information.

## How This Installer Was Made

- Uses AdGuard Home binary packages from https://github.com/AdguardTeam/AdGuardHome
- Installer logic was inspired by `entware-setup.sh` from Asuswrt-Merlin.
- Source code is available at https://github.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer

## Donate

This script will always be open source and free to use under the [GPL-3.0 License](https://raw.githubusercontent.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/master/LICENSE). If you want to support future development, you can donate through [PayPal](https://paypal.me/swotrb) or [Buy Me a Coffee](https://www.buymeacoffee.com/swotrb).
