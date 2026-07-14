# Issue Reports

Please include concise, paste-safe diagnostics.

## Useful commands

```sh
sh installer preflight status
sh installer status
sh installer doctor
```

If reporting an install, update, restore, or uninstall problem, also include the exact command you ran and whether the operation was interrupted.

## Include

- Router model and Asuswrt-Merlin firmware version.
- Installer version shown by the script.
- AdGuardHome channel: `release`, `beta`, or `edge`.
- Whether Entware is mounted.
- Whether JFFS custom scripts are enabled.
- Any recent DNS, firewall, WAN, VPN, or NVRAM changes.

Do not paste secrets, API tokens, private keys, or full configuration files without redacting sensitive values.
