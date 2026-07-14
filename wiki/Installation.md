# Installation

Open an SSH shell on the router and set a router-stock-first environment:

```sh
export LC_ALL=C
export PATH="/sbin:/bin:/usr/sbin:/usr/bin:${PATH:-}"
```

## Install with curl

```sh
/usr/sbin/curl -L -s -O https://raw.githubusercontent.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/master/installer && sh installer; rm installer
```

## Install with wget

```sh
/usr/sbin/wget -O installer https://raw.githubusercontent.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/master/installer && sh installer; rm installer
```

## Interactive mode

```sh
sh installer
```

Follow the menu prompts for install, update, backup, restore, reconfiguration, diagnostics, or uninstall.

## Non-interactive install

```sh
sh installer install --installer-branch master --adguardhome-branch release --yes --allow-dns-nvram
```

`--yes` confirms the action. `--allow-dns-nvram` is required for actions that may rewrite DNS or NVRAM settings.
