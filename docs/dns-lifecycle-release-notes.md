# Unreleased DNS lifecycle changes

These changes are on `feature/dns-sdn-cache-lifecycle`, based on v2.6.5. No release version was bumped, no artifacts were published, and master was not modified.

## Behavior

- Missing DNS cleanup policies default to `refuse-unknown` for fresh installs and upgrades. Saved choices and the `legacy` CLI option are preserved.
- Installer escalation recognizes main and independent SDN dnsmasq instances from stock executable identity and managed configuration paths. It deduplicates socket owners and revalidates process start time/configuration before signaling managed survivors.
- Firmware stop/restart commands retain their all-SDN behavior. After successful startup, previously managed instances must have replacement TCP/UDP DNS listeners on port 553; failure recovery checks restored listeners on port 53 with bounded retries.
- Failed post-start checks return control to the service runner so AdGuardHome is stopped before native DNS recovery begins.
- Local Cache remains menu option 6. Its resolver switch now follows DNS readiness rather than running in postconf. The monitor retries after service restarts; readiness loss, disabled cache, startup failure and shutdown restore native routing. Failed optional activation does not stop a healthy AdGuardHome instance.
- BusyBox baseline fixes preserve service-only refresh selection and avoid ambiguous awk concatenation while saving startup traps.

## Validation

41 distinct relevant regressions passed across policy, DNS handoff, process signaling, main/SDN lifecycle, dnsmasq publication, Local Cache, monitor supervision, WAN/LAN setup, event hooks, mode migration, and legacy guest-bridge DNS discovery. Router BusyBox syntax passed for all 157 discovered shell scripts. MD5 and SHA-256 checks passed for all tracked release artifacts. The four new behavioral tests are included in GitHub shell validation.

Most regressions ran with BusyBox 1.30 ash in a root-mapped namespace. The unchanged usleep shim test ran under dash because the downloaded BusyBox build prefers its own usleep applet over the PATH shim. The portability/lock-policy regression ran under unprivileged dash because a single-UID root-mapped namespace cannot chown fixtures to a foreign UID. BusyBox 1.38 exposed baseline fixture timeouts; it is not the validation target for these results. The initial unprivileged handoff failure was due to root-ownership checks, not a production handoff defect.

Hardware testing was explicitly skipped by the user. DHCP exchanges, network isolation, IPv6 operation, and installed firmware service behavior remain unverified on a physical router. See `dns-lifecycle-validation.md` for the acceptance matrix and upstream firmware evidence.
