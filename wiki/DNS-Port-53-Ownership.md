# DNS Port 53 Ownership

AdGuardHome normally owns DNS port `53`. dnsmasq is moved to a managed handoff port so router DNS features can continue to function behind AdGuardHome.

## Cleanup policy

Use the safer policy to refuse unknown non-dnsmasq owners of port `53`:

```sh
sh installer dns-port-policy --policy refuse-unknown
```

Use the legacy policy only when you intentionally want the older cleanup behavior:

```sh
sh installer dns-port-policy --policy legacy
```

## Operational guidance

- Review port `53` ownership before changing DNS service placement.
- Avoid broad process kills.
- Preserve existing DNS/NVRAM values when practical.
- Include restore logic for DNS, firewall, WAN, VPN, or service-related changes.
