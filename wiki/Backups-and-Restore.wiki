# Backups and Restore

## Create a backup

```sh
sh installer backup --yes
```

## Restore from backup

Preview the restore first:

```sh
sh installer restore --file /opt/etc/backup_AdGuardHome.tar.gz --dry-run
```

Run the restore:

```sh
sh installer restore --file /opt/etc/backup_AdGuardHome.tar.gz --yes
```

## Notes

- Backup and restore paths under `/opt` require Entware and an installed or partially installed AdGuardHome environment.
- Restore can affect DNS service. Run it during a maintenance window when possible.
- Check `sh installer status` after restore.
