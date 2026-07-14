# Asuswrt-Merlin AdGuardHome Installer Wiki

This wiki is a practical operator guide for installing, maintaining, and troubleshooting AdGuardHome with this installer on Asuswrt-Merlin routers.

This repository also includes GitHub-wiki-ready split pages under [`Github Wiki Pages`](https://github.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/wiki) for publishing to `Asuswrt-Merlin-AdGuardHome-Installer.wiki.git`.

## Contents

- [Supported environment](#supported-environment)
- [Before you install](#before-you-install)
- [Install or re-run the installer](#install-or-re-run-the-installer)
- [Installer menu and CLI actions](#installer-menu-and-cli-actions)
- [Runtime paths](#runtime-paths)
- [Service management](#service-management)
- [Status and health checks](#status-and-health-checks)
- [Runtime behavior settings](#runtime-behavior-settings)
- [DNS behavior and port 53 ownership](#dns-behavior-and-port-53-ownership)
- [IPSET integration](#ipset-integration)
- [Unused blocklist analyzer](#unused-blocklist-analyzer)
- [Backups and restore](#backups-and-restore)
- [Updates](#updates)
- [Uninstall](#uninstall)
- [Troubleshooting](#troubleshooting)
- [Issue reports](#issue-reports)
- [Developer validation](#developer-validation)

## Supported environment

This installer targets ARM-based ASUS routers running Asuswrt-Merlin firmware with Entware installed on attached storage. The runtime scripts are written for POSIX `/bin/sh` and BusyBox `ash`; do not use Bash-only syntax when editing installer-managed scripts.

Minimum expected environment:

- Asuswrt-Merlin firmware `384.11` or newer.
- JFFS custom scripts and configs enabled.
- Entware installed and mounted on a separate USB drive before installing AdGuardHome.
- A swap file, preferably `2 GB` or larger.
- Router stock paths before Entware paths in `PATH`.

Use this PATH ordering for bootstrap commands:

```sh
export LC_ALL=C
export PATH="/sbin:/bin:/usr/sbin:/usr/bin:${PATH:-}"
```

Entware commands such as `opkg` are valid only after Entware is installed and `/opt` is mounted.

## Before you install

Update Entware before installing AdGuardHome:

```sh
opkg update && opkg upgrade
```

Confirm that JFFS scripts are enabled in the Asuswrt-Merlin web interface:

1. Open **Administration**.
2. Open **System**.
3. Enable **JFFS custom scripts and configs**.
4. Reboot if the firmware asks you to.

Make sure no other DNS service is intentionally bound to port `53` unless you plan to reconfigure it. During normal operation, AdGuardHome listens on port `53` and dnsmasq is moved to a handoff port managed by the installer.

## Install or re-run the installer

Run one of these commands from an SSH shell on the router. These examples use router-stock download tools and do not require `/opt/...` paths before the downloaded installer starts.

Using router-stock `curl`:

```sh
/usr/sbin/curl -L -s -O https://raw.githubusercontent.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/master/installer && sh installer; rm installer
```

Using router-stock `wget`:

```sh
/usr/sbin/wget -O installer https://raw.githubusercontent.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/master/installer && sh installer; rm installer
```

The same installer entry point handles new installs, updates, reconfiguration, backups, restores, diagnostics, and uninstall.

## Installer menu and CLI actions

Interactive mode is the safest default for most users:

```sh
sh installer
```

Common non-interactive commands include:

```sh
sh installer preflight
sh installer status
sh installer doctor
sh installer update --dry-run
sh installer update --yes
sh installer backup --yes
sh installer restore --file /opt/etc/backup_AdGuardHome.tar.gz --dry-run
sh installer restore --file /opt/etc/backup_AdGuardHome.tar.gz --yes
sh installer uninstall --dry-run
sh installer uninstall --yes --allow-dns-nvram
```

Destructive install and uninstall paths require `--yes`. Actions that may rewrite DNS or NVRAM settings also require `--allow-dns-nvram`.

Branch selection options:

```sh
sh installer install --installer-branch master --adguardhome-branch release --yes --allow-dns-nvram
sh installer update --installer-branch master --adguardhome-branch beta --yes
sh installer update --adguardhome-branch edge --dry-run
```

Supported AdGuardHome channels are `release`, `beta`, and `edge`.

## Runtime paths

The most important installed paths are:

| Path | Purpose |
| --- | --- |
| `/opt/etc/AdGuardHome` | AdGuardHome configuration, data, installer `.config`, and IPSET user files. |
| `/opt/sbin/AdGuardHome` | AdGuardHome binary symlink managed by the installer. |
| `/opt/etc/init.d/S99AdGuardHome` | Entware init script. |
| `/opt/etc/init.d/rc.func.AdGuardHome` | Shared service functions. |
| `/jffs/addons/AdGuardHome.d` | Asuswrt-Merlin hook integration. |
| `/jffs/scripts/dnsmasq.postconf` | dnsmasq post-configuration hook. |
| `/jffs/scripts/firewall-start` | Firewall-start hook. |
| `/jffs/scripts/service-event-end` | Service event hook. |

Every `/opt/...` path requires Entware and an installed or partially installed AdGuardHome environment.

## Service management

Recommended Asuswrt-Merlin service commands:

```sh
service start_AdGuardHome
service stop_AdGuardHome
service restart_AdGuardHome
service reload_AdGuardHome
service kill_AdGuardHome
```

You can also call the Entware init script directly after Entware is mounted:

```sh
/opt/etc/init.d/S99AdGuardHome start
/opt/etc/init.d/S99AdGuardHome stop
/opt/etc/init.d/S99AdGuardHome restart
/opt/etc/init.d/S99AdGuardHome check
```

Restarting AdGuardHome affects DNS service on the router. Avoid unnecessary restarts during active network use.

## Status and health checks

Use `status` for a short service summary:

```sh
sh installer status
```

Use `doctor` for broader diagnostics:

```sh
sh installer doctor
```

Use limited automatic repair only when the diagnostics recommend it:

```sh
sh installer doctor --fix
```

`doctor --fix` is intentionally conservative. It can repair permissions, recreate the expected `/opt/sbin/AdGuardHome` symlink, and remove stale temporary files or markers that are not owned by an active process. It does not rewrite DNS, firewall, or NVRAM policy.

## Runtime behavior settings

Persistent runtime settings live in `/opt/etc/AdGuardHome/.config`. Environment variables override saved values for the current invocation.

Inspect runtime default migration status:

```sh
sh installer migrate-runtime-defaults
sh installer migrate-runtime-defaults --dry-run
```

Write safer current defaults where legacy or missing values are detected:

```sh
sh installer migrate-runtime-defaults --yes
```

### Netcheck mode

WAN-style checks are suitable for normal Internet-connected installs:

```sh
sh installer netcheck --mode wan --hosts "google.com github.com snbforums.com" --dns 127.0.0.1 --require-http NO --timeout 300
```

LAN mode avoids public Internet probes for isolated or local-only deployments:

```sh
sh installer netcheck --mode lan
```

### DNS port-owner cleanup policy

The safer policy refuses to kill unknown non-dnsmasq owners of port `53`:

```sh
sh installer dns-port-policy --policy refuse-unknown
```

The legacy policy allows the older cleanup behavior:

```sh
sh installer dns-port-policy --policy legacy
```

### Performance profile

Use the balanced profile for most routers:

```sh
sh installer performance --profile balanced
```

Other supported profile choices:

```sh
sh installer performance --profile low-memory
sh installer performance --profile fast
```

`low-memory` maps to the safer low-impact profile. `fast` maps to the legacy aggressive profile and should be used only when you understand the router-wide proc/sysctl changes.

## DNS behavior and port 53 ownership

AdGuardHome is expected to own DNS port `53`. dnsmasq remains part of the router DNS stack and is moved to the installer-managed handoff port when required.

If startup fails because another process owns port `53`:

1. Run `sh installer doctor`.
2. Identify the reported owner.
3. Stop or reconfigure the conflicting service.
4. Start AdGuardHome again.

Avoid forcing port-owner cleanup unless you are sure the owner is safe to terminate.

## IPSET integration

IPSET integration is optional. It lets AdGuardHome add resolved addresses for selected domains to IPSETs owned by other routing or firewall add-ons.

The installer manages these files after Entware and AdGuardHome are installed:

| Path | Purpose |
| --- | --- |
| `/opt/etc/AdGuardHome/ipset.user` | Persistent user-maintained mappings. |
| `/opt/etc/AdGuardHome/ipset.conf` | Generated AdGuardHome mapping file. Do not edit manually. |

User rule format:

```text
DOMAIN[,DOMAIN,...]/IPSET_NAME[,IPSET_NAME,...]
```

Examples:

```text
example.com/ROUTE_VPN
example.net,example.org/ROUTE_WG
streaming.example/ROUTE_VPN,TRACK_STREAMING
```

After editing `ipset.user`, restart AdGuardHome so mappings are regenerated and loaded:

```sh
service restart_AdGuardHome
```

Read-only diagnostics:

```sh
sh installer ipset status
sh installer ipset doctor
```

The installer does not create IPSETs or firewall rules. The add-on that owns the set must create the IPv4 or IPv6 set before AdGuardHome can add addresses to it.

## Unused blocklist analyzer

The optional unused blocklist analyzer can be launched from installer menu option **9** or from the CLI:

```sh
sh installer blocklists
sh installer unusedblocklists
```

The analyzer requires Entware Python 3. If it is not already installed and you want this feature, install it after Entware is available:

```sh
opkg install python3 coreutils-sha256sum
```

Review analyzer output carefully. A list reported as unused had no matching query-log hits during the analyzed window; that does not prove the list is unnecessary for all future traffic.

## Backups and restore

Create a backup:

```sh
sh installer backup --yes
```

Dry-run a restore first:

```sh
sh installer restore --file /opt/etc/backup_AdGuardHome.tar.gz --dry-run
```

Restore after reviewing the dry-run output:

```sh
sh installer restore --file /opt/etc/backup_AdGuardHome.tar.gz --yes
```

Backups include installer-managed AdGuardHome configuration and runtime files under `/opt/etc/AdGuardHome`.

## Updates

Preview an update:

```sh
sh installer update --dry-run
```

Run an update on the saved branch/channel:

```sh
sh installer update --yes
```

Run an update and select branches explicitly:

```sh
sh installer update --installer-branch master --adguardhome-branch release --yes
```

The installer keeps existing runtime settings unless a migration helper is explicitly used.

## Uninstall

Preview uninstall actions:

```sh
sh installer uninstall --dry-run
```

Run uninstall when you are ready for DNS/NVRAM changes:

```sh
sh installer uninstall --yes --allow-dns-nvram
```

After uninstall, review DNS behavior from a client and confirm the router is resolving names through the intended service.

## Troubleshooting

Start with these commands:

```sh
sh installer status
sh installer doctor
logread | grep -iE 'AdGuardHome|dnsmasq|ipset'
```

Common checks:

```sh
pidof AdGuardHome
netstat -lnp | grep ':53 '
service restart_AdGuardHome
```

For configuration validation after installation, use the installed AdGuardHome binary:

```sh
/opt/sbin/AdGuardHome --check-config -c /opt/etc/AdGuardHome/AdGuardHome.yaml --no-check-update -l /dev/null
```

If IPSET mappings do not work, confirm:

1. `ipset.user` contains the expected domain rule.
2. `ipset.conf` was regenerated.
3. The target IPSET exists.
4. The target IPSET family matches the answer type: IPv4 answers need an IPv4 set; IPv6 answers need an IPv6 set.
5. The query was answered by this AdGuardHome instance.

## Issue reports

For installer issues, include:

- Router model.
- Asuswrt-Merlin firmware version.
- Installer version and selected AdGuardHome channel.
- DNS server choice made during installation.
- Output from `sh installer status`.
- Output from `sh installer doctor`.
- Relevant `logread` lines.
- A diagnostic archive when possible.

Create a diagnostic archive from the router shell:

```sh
echo .config > exclude-files; tar -cvf AdGuardHome.tar -X exclude-files /opt/etc/AdGuardHome /opt/sbin/AdGuardHome /opt/etc/init.d/S99AdGuardHome /opt/etc/init.d/rc.func.AdGuardHome /jffs/addons/AdGuardHome.d /jffs/scripts/init-start /jffs/scripts/dnsmasq.postconf /jffs/scripts/firewall-start /jffs/scripts/services-stop /jffs/scripts/service-event-end; rm exclude-files
```

Remove private domains, addresses, usernames, or tokens before posting logs or configuration publicly.

## Developer validation

From the repository root, run syntax checks for primary shell scripts:

```sh
sh -n installer AdGuardHome.sh S99AdGuardHome rc.func.AdGuardHome
```

Run repository portability and checksum checks:

```sh
sh tools/check-shell-portability.sh
sh tools/check-sha256.sh
```

Run the full quality helper on a development workstation when optional tools such as ShellCheck and shfmt are installed:

```sh
tools/code-quality.sh
```

ShellCheck and shfmt are development tools, not router dependencies.
