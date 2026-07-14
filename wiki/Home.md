# Asuswrt-Merlin AdGuardHome Installer Wiki

Welcome to the operator wiki for the Asuswrt-Merlin AdGuardHome Installer.

This wiki documents installing, updating, backing up, troubleshooting, and uninstalling AdGuardHome on supported ARM-based Asuswrt-Merlin routers.

## Quick start

Set a router-stock-first environment before bootstrap commands:

```sh
export LC_ALL=C
export PATH="/sbin:/bin:/usr/sbin:/usr/bin:${PATH:-}"
```

Download and run the installer with a router-stock downloader:

```sh
/usr/sbin/curl -L -s -O https://raw.githubusercontent.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/master/installer && sh installer; rm installer
```

or:

```sh
/usr/sbin/wget -O installer https://raw.githubusercontent.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/master/installer && sh installer; rm installer
```

## Main topics

- [Supported Environment](Supported-Environment)
- [Before You Install](Before-You-Install)
- [Installation](Installation)
- [Installer Commands](Installer-Commands)
- [Runtime Paths](Runtime-Paths)
- [Service Management](Service-Management)
- [Troubleshooting](Troubleshooting)
