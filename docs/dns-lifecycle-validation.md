# DNS lifecycle validation

Development base: v2.6.5, e3866c4. Changes belong on the development branch until all release checkpoints pass.

## Baseline

The initial `wan_handoff` failure under an unprivileged shell is an environment issue: authenticated handoff files and their owning process must be root-owned. `unshare -Ur` provides a root-mapped namespace for host tests without weakening runtime authentication. The unchanged handoff regression passes under dash in that namespace.

## Expected behavior

- AdGuardHome owns its configured TCP and UDP port-53 listeners.
- Main and supported SDN dnsmasq instances retain DHCP and local/reverse-name service on port 553 while AdGuardHome is running.
- Legacy guest bridges retain their existing DHCP DNS advertisements and firewall isolation.
- An unknown conflicting port owner aborts default startup with diagnostics; explicit legacy policy remains available.
- Startup failure restores native DNS; interruption must not leave handoff markers or stopped managed services behind.
- Local Cache is a preference. Router resolver routing changes only after services are ready, and native routing returns on shutdown or failure.

## Router release checkpoint

Host tests cannot prove firmware service behavior, DHCP exchanges, or network isolation. Do not mark this checkpoint complete without router results.

| Configuration | Checks | Status |
| --- | --- | --- |
| Main LAN, IPv4 | DHCP lease and option 6, external DNS, local and reverse DNS | Pending router |
| Multiple enabled SDNs | Separate dnsmasq PIDs/configs, port ownership, DHCP and DNS per network | Pending router |
| Legacy guest networks | DHCP advertisements, DNS reachability, guest-to-LAN isolation | Pending router |
| IPv6 where supported | DNS listeners, RA/DHCPv6, external and reverse DNS | Pending router |
| Cache enabled and disabled | Router resolution before, during and after startup | Pending router |
| Lifecycle | Cold boot, AGH restart, dnsmasq restart, SDN changes | Pending router |
| Failure recovery | Invalid AGH config, startup timeout, interrupted start, failed restart | Pending router |

For every row, record firmware/model, enabled networks, cache setting, observed listeners/PIDs, and results. Run with an actual client on each network; router-local DNS tests alone do not establish client connectivity or isolation.

## Firmware service evidence

Reviewed upstream Merlin `release/src/router/rc/services.c` and `sdn.c` on 2026-10-06. The `dnsmasq` service handler dispatches a command without indices to `ALL_SDN`; stop uses all dnsmasq instances and start regenerates the main and enabled SDN configurations. SDN launch uses `dnsmasq -C /etc/dnsmasq-<index>.conf --log-async`. Therefore the installer retains `service stop_dnsmasq` / `service restart_dnsmasq`, rather than introducing an unsupported SDN-specific service name. The firmware's own stop is broad; installer escalation is restricted to verified conflicting managed processes under refusal policy.

Sources: [services.c](https://github.com/RMerl/asuswrt-merlin.ng/blob/main/release/src/router/rc/services.c), [sdn.c](https://github.com/RMerl/asuswrt-merlin.ng/blob/main/release/src/router/rc/sdn.c). Installed firmware must still be validated on hardware.

An additional baseline defect was confirmed under BusyBox ash: declaring `SERVICE_REFRESH_ONLY` separately reset its inherited value. Initializing it in its local declaration preserves service-only refresh selection. The unchanged upgrade regression passes after the correction.
