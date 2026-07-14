# Installer Commands

## Common commands

```sh
sh installer
sh installer preflight
sh installer status
sh installer doctor
sh installer doctor --fix
sh installer update --dry-run
sh installer update --yes
sh installer backup --yes
sh installer restore --file /opt/etc/backup_AdGuardHome.tar.gz --dry-run
sh installer restore --file /opt/etc/backup_AdGuardHome.tar.gz --yes
sh installer uninstall --dry-run
sh installer uninstall --yes --allow-dns-nvram
```

## Branch selection

```sh
sh installer install --installer-branch master --adguardhome-branch release --yes --allow-dns-nvram
sh installer update --installer-branch master --adguardhome-branch beta --yes
sh installer update --adguardhome-branch edge --dry-run
```

Supported AdGuardHome channels are `release`, `beta`, and `edge`.

## Runtime helpers

```sh
sh installer netcheck --mode wan --hosts "google.com github.com snbforums.com" --dns 127.0.0.1 --require-http NO --timeout 300
sh installer netcheck --mode lan
sh installer dns-port-policy --policy refuse-unknown
sh installer dns-port-policy --policy legacy
sh installer performance --profile balanced
sh installer migrate-runtime-defaults
sh installer migrate-runtime-defaults --dry-run
sh installer migrate-runtime-defaults --yes
```

Commands referencing `/opt/...` require Entware and an installed or partially installed AdGuardHome environment.
