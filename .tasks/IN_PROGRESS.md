# In Progress

## TASK-021: Resolve ARM-suite review findings and hosted acceptance failure

**Priority:** P1 | **Tags:** review, virtualization, arm, ci, tests
**Scope:** User follow-up on October 8, 2026 America/New_York: resolve current PR #1033 CodeRabbit feedback and the failed ARMv7 execution/aggregate acceptance checks. Preserve the RT-AC68U-class older ARMv7 software-float target, feature-scoped unblocking, draft status and separate physical release gates.

### Plan

- Verify all current unresolved review threads and exact-head hosted logs against `62c6143`; reproduce each valid claim before changing behavior.
- Repair required BusyBox option validation, DNS compression-pointer rejection and malformed guest result handling/cleanup with focused failure regressions.
- Diagnose the early cache-serialization failure from the hosted ARMv7 run; correct only the reproduced product or fixture cause and retain real ownership/serialization assertions and normal retry budgets.
- Rebuild changed native tooling, run affected checks and the complete matching three-target matrix, and verify host quality/CI configuration.
- Publish normal leased branch updates, reply on each original review thread with evidence, resolve confirmed corrections, and observe the new published head until hosted ARM execution and feature acceptance are terminal. Record any external review-capacity blocker without bypassing it.

### Acceptance criteria

- [ ] Every current in-scope CodeRabbit finding has a verified fix or evidence-backed rejection, reply and resolution.
- [ ] The hosted ARMv7 failure has a demonstrated cause and passing regression evidence; failure/skip/stale evidence still cannot unblock.
- [ ] Fresh exact-content native ARM matrix and host checks pass without concealing earlier failures.
- [ ] New-head hosted ARMv5/ARMv7/ARMv8 feature execution and aggregate acceptance succeed; pending results are not reported complete.
- [ ] PR remains draft; no physical release, merge, check-policy waiver or billing/settings change.

---

## TASK-018: Validate physical-router recovery and package v2.6.7

**Priority:** P1 | **Tags:** release, hardware, dns
**Dependencies:** TASK-017
**Estimated scope:** Medium, five files

### Plan

- Create proposed `RELEASE-2.6.7-CHECKLIST.md` from the applicable requirements of the existing v2.6.5 checklist and DNS lifecycle validation document.
- Update `README.md` with the new checklist and accurately scoped repair notes.
- Prepare the authorized software candidate by changing only installer banner and `AI_VERSION` to v2.6.7 and refreshing `installer.md5sum`/`installer.sha256sum`. Publication remains gated on hardware acceptance.
- Keep upstream AGH channels and archive refreshes outside this repair release unless independently required to fix a proven defect.

### Acceptance criteria

- [ ] Fresh install, legacy v2.6.0-or-earlier upgrade, v2.6.5 upgrade, and v2.6.6 upgrade repair hooks and preserve user settings; no duplicate hooks, cron jobs or firewall rules. Use test hardware in a maintenance window.
- [ ] Firmware-dispatched DNS restart, cold boot, AGH restart/failure, DHCP new lease/renewal/expiry, main/SDN local A/PTR resolution, guest isolation, cache on/off, supported IPv6, slow filter startup and interrupted upgrade/uninstall recover correctly. Validate from a client on each network and verify both TCP/UDP listeners: AGH 53 with managed dnsmasq 553 while running; native DNS after required recovery.
- [ ] Recommended soak: at least two overnight maintenance periods (48 hours) with actual scheduled events recorded; include the originally affected model/firmware when available. Capture sanitized listener/PID ownership, hook first lines/modes, relevant event logs and lease outcomes before/after; verify intended WAN IPv4/IPv6 TCP/UDP DNS exposure. Mandatory unrun or failing hardware rows block the claim that the reported outage is resolved.
- [x] Version/banner/manifests agree and release notes distinguish demonstrated repairs from unverified firmware cases. Local software checks pass at review repair source b31385a; prior verification at 5c28d8d remains historical evidence. No automatic merge/publication is part of this task plan.
- [ ] All current-head hosted required checks/reviews pass before merge or release.

### Verification

- [ ] Record model, supported firmware, architecture, actual BusyBox version, topology, enabled SDNs, initial installer and AGH channel, cache setting, event timestamps and PASS/FAIL/BLOCKED/N/A for every applicable row.
- [x] Run `sh tools/update-checksums.sh installer`, all checksum/release-consistency checks, and affected targeted checks after the version change.
- [x] Preserve rollback evidence and pre-upgrade recovery paths; do not repeat the destructive whole-file workaround on shared hooks. Hardware execution remains pending.

### Decisions to settle before implementation

- [x] Selected TASK-015's recommended immediate busy status for a contended fallback stop; atomic acquisition and no-overlap requirements remain fixed.
- [ ] Assign physical-router coverage and maintenance windows before treating TASK-018 hardware rows as executable. No dates or operators were invented.

---

### Planning verification record

- Four existing hook/doctor regressions passed under host sh: event-script modes, event-script transactions, doctor fix safety, and legacy hook cleanup.
- Independent actual-function scratch proofs reproduced malformed hook generation/reinstall/doctor false OK, fallback start/stop overlap, monitor shutdown failure suppression, and lock/probe symlink target truncation.
- BusyBox and ShellCheck were unavailable in this planning host. Physical router and firmware behavior were not exercised.
- Historical #735 slow-startup and #252/#253 firewall/DNS Director reports are regression inputs, not newly confirmed v2.6.6 defects.
- No current source fix, exhaustive vulnerability scan, remote exploitation, security advisory, issue reopening, or release was claimed.

Sources: [reported DHCP regression #1029](https://github.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/issues/1029), [v2.6.6 repair PR #1030](https://github.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/pull/1030), [virtual acceptance and firmware limitations](https://github.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/pull/1030#issuecomment-6022881933).
