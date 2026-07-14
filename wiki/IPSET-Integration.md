# IPSET Integration

IPSET integration lets AdGuardHome populate ipset sets for router policy routing or firewall use.

## Commands

```sh
sh installer ipset status
sh installer ipset doctor
sh installer ipset refresh
sh installer ipset refresh --dry-run
sh installer ipset refresh --yes
```

Without `--yes`, refresh checks whether IPSET integration is enabled and reports planned work. With `--yes`, the installer refreshes mappings and restarts AdGuardHome so changes can take effect.

## Guidance

- Handle IPv4 and IPv6 sets separately.
- Keep rules idempotent.
- Include cleanup for firewall rules that consume ipset sets.
- Do not rely on `flock` unless the existing compatibility probe confirms descriptor-lock support; preserve the mkdir/PID fallback path.
