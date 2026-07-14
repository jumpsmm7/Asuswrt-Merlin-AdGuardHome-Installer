# Supported Environment

The installer targets POSIX `/bin/sh` scripts running under BusyBox `ash` on Asuswrt-Merlin routers.

## Requirements

- ARM-based ASUS router running Asuswrt-Merlin firmware.
- Firmware version `384.11` or newer.
- JFFS custom scripts and configs enabled.
- Entware installed and mounted on attached storage before AdGuardHome runtime paths under `/opt` are used.
- A swap file is strongly recommended; `2 GB` or larger is preferred.
- Router stock paths before Entware paths in `PATH`.

## Recommended shell environment

```sh
export LC_ALL=C
export PATH="/sbin:/bin:/usr/sbin:/usr/bin:${PATH:-}"
```

## Compatibility notes

- Do not use Bash-only syntax in installer-managed scripts.
- Treat BusyBox applets as limited implementations.
- Do not assume GNU coreutils behavior.
- Commands such as `nvram`, `cru`, `service`, `iptables`, `ip6tables`, `curl`, and `wget` are router-stock binaries, not BusyBox applets.
