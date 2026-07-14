# Uninstall

Preview uninstall actions first:

```sh
sh installer uninstall --dry-run
```

Run uninstall when ready:

```sh
sh installer uninstall --yes --allow-dns-nvram
```

`--allow-dns-nvram` is required because uninstall can restore DNS/NVRAM-related settings.

## Guidance

- Run uninstall during a maintenance window.
- Confirm DNS service returns to the expected router state afterward.
- Check for stale hooks or firewall rules if the uninstall was interrupted.
