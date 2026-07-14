# Troubleshooting

## First checks

```sh
sh installer status
sh installer doctor
sh installer preflight status
```

Use `doctor --fix` only when diagnostics recommend it:

```sh
sh installer doctor --fix
```

## Common areas to inspect

- Entware is mounted and `/opt` exists.
- JFFS custom scripts are enabled.
- DNS port `53` is owned by the expected service.
- dnsmasq handoff is active when AdGuardHome owns port `53`.
- Firewall hooks are present and not duplicated.
- Recent logs show the last startup or rollback result.

## Router-safe approach

Prefer syntax checks and targeted diagnostics. Avoid installing new packages or running network-heavy commands unless they are needed for the issue.
