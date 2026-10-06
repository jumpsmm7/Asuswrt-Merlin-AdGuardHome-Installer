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
