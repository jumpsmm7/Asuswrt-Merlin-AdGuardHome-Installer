# Before You Install

## Enable JFFS scripts

In the Asuswrt-Merlin web interface:

1. Open **Administration**.
2. Open **System**.
3. Enable **JFFS custom scripts and configs**.
4. Reboot if prompted.

## Prepare Entware

Install Entware on attached storage before running a full AdGuardHome install. After Entware is mounted, update packages:

```sh
opkg update && opkg upgrade
```

`opkg` is an Entware command and is valid only after Entware is available.

## Check DNS ownership

AdGuardHome normally listens on DNS port `53`. The installer moves dnsmasq to a managed handoff port. Before installing, identify any other service intentionally bound to port `53` and decide whether it should be stopped or reconfigured.

## Use router-stock bootstrap commands

Before Entware is available, use `/bin`, `/sbin`, `/usr/bin`, and `/usr/sbin` commands only. Do not use `/opt/...` paths for bootstrap commands.
