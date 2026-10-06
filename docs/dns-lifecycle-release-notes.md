# Unreleased DNS lifecycle changes

These changes are on `feature/dns-sdn-cache-lifecycle`, based on v2.6.5. No release version was bumped, no artifacts were published, and master was not modified.

## Behavior

- Missing DNS cleanup policies default to `refuse-unknown` for fresh installs and upgrades. Saved choices and the `legacy` CLI option are preserved.
- Installer escalation recognizes main and independent SDN dnsmasq instances from stock executable identity and managed configuration paths. It deduplicates socket owners and revalidates process start time/configuration before signaling managed survivors.
- Firmware stop/restart commands retain their all-SDN behavior. After successful startup, required main and enabled SDN configurations must have replacement TCP/UDP DNS listeners on port 553, including configurations created during firmware restart. Failure recovery checks restored listeners on port 53 with bounded retries.
- Failed post-start checks return control to the service runner so AdGuardHome is stopped before native DNS recovery begins.
- Local Cache remains menu option 6. Its resolver switch now follows DNS readiness rather than running in postconf. The monitor retries after service restarts; readiness loss, disabled cache, startup failure and shutdown restore native routing. Failed optional activation does not stop a healthy AdGuardHome instance.
- Final review fixes account for dnsmasq DHCP helpers when checking readiness and refresh sockets before refusing an owner that may have exited. Local Cache rereads saved preferences under a shared resolver lock, waits for manager service operations to finish, and restores native resolution before stop/restart signals.
- PR review follow-up reconstructs required DNS configurations when process inventory is empty, uses current process identity for detached monitor locks, moves DNS queries outside the resolver lock, and reserves full cache probes for activation and periodic healthchecks. The installed manager path is used for immediate menu activation.
- BusyBox baseline fixes preserve service-only refresh selection and avoid ambiguous awk concatenation while saving startup traps.

## Validation

44 distinct relevant regressions passed across policy, DNS handoff, process signaling, main/SDN lifecycle, dnsmasq publication, Local Cache, monitor supervision, WAN/LAN setup, event hooks, mode migration, and legacy guest-bridge DNS discovery. Router BusyBox syntax passed for all 158 discovered shell scripts. MD5 and SHA-256 checks passed for all 13 runtime-script and bundled AdGuardHome archive targets. ShellCheck 0.10.0 also passed at warning severity for all 158 scripts. The five new behavioral tests are included in GitHub shell validation and the canonical `tools/code-quality.sh` runner. These counts describe local validation before the initial push; current CI results are available on PR #1030. The large installer needed an extended host ShellCheck timeout.

Final review added concurrent cache activation checks under both descriptor and mkdir locks, helper-first dnsmasq readiness, exiting-owner refusal recovery, and regression checks for the reused process-lock implementation and IPSET LAN lifecycle.

PR #1030 follow-up passed the complete `tools/code-quality.sh` runner as UID 0 in an isolated Ubuntu 24.04 container, including foreign-owner security fixtures, service lifecycle integration, ShellCheck 0.9.0, shfmt 3.8.0, and artifact checksums. The container supplied jq and a working GNU Awk; its original mawk interval-regex failure and missing jq were validation-environment defects, confirmed by unchanged smoke checks and the earlier passing GitHub checks. Focused BusyBox 1.30 ash regressions and syntax checks also pass. The runtime-default regression now expects `refuse-unknown` for a missing upgrade policy and verifies preservation of both explicit values.

Most regressions ran with BusyBox 1.30 ash in a root-mapped namespace. The unchanged usleep shim test ran under dash because the downloaded BusyBox build prefers its own usleep applet over the PATH shim. The portability/lock-policy regression ran under unprivileged dash because a single-UID root-mapped namespace cannot chown fixtures to a foreign UID. BusyBox 1.38 exposed baseline fixture timeouts; it is not the validation target for these results. The initial unprivileged handoff failure was due to root-ownership checks, not a production handoff defect.

Hardware testing was explicitly skipped by the user. DHCP exchanges, network isolation, IPv6 operation, and installed firmware service behavior remain unverified on a physical router. See `dns-lifecycle-validation.md` for the acceptance matrix and upstream firmware evidence.
