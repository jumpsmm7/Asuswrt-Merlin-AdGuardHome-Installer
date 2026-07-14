# Updates

## Dry run

```sh
sh installer update --dry-run
```

## Update installer and AdGuardHome release channel

```sh
sh installer update --installer-branch master --adguardhome-branch release --yes
```

## Other AdGuardHome channels

```sh
sh installer update --adguardhome-branch beta --yes
sh installer update --adguardhome-branch edge --dry-run
```

## After updating

Check service state and diagnostics:

```sh
sh installer status
sh installer doctor
```

Existing installs preserve saved runtime settings unless a migration command is explicitly run.
