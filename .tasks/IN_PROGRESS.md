# In Progress

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
- [x] Version/banner/manifests agree and release notes distinguish demonstrated repairs from unverified firmware cases. Local software checks pass at source commit 5c28d8d. No automatic merge/publication is part of this task plan.
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

## TASK-017: Run the new failure cases in canonical CI

**Priority:** P1 | **Tags:** validation, ci
**Dependencies:** TASK-012, TASK-013, TASK-014, TASK-015, TASK-016
**Estimated scope:** Medium, up to four files

### Plan

- Modify `tools/code-quality.sh` and `.github/workflows/shell-validation.yml` to execute all new fixtures under the appropriate shell/UID.
- Update `tests/fixtures/service-lifecycle-cases.tsv` and `tests/fixtures/service-lifecycle-coverage.tsv` only for independently covered integration scenarios.
- Keep regression paths and time limits aligned; do not loosen assertions or mask environment failures to obtain green results.

### Acceptance criteria

- [x] Canonical validation actually executes real-helper legacy migration, doctor malformed-hook, lock-path, contention, and graceful-stop failure cases.
- [x] Host sh and BusyBox ash checks pass; security tests execute in an isolated UID-0 host with foreign-UID cases; target BusyBox 1.25.1 ash harness passes. Firmware libc/ARM/applets remain hardware acceptance.
- [ ] Full lifecycle integration, lint, formatting and artifact checksums pass against the final combined source, with current-head hosted review/check evidence.

### Verification

- [x] Run `sh tools/code-quality.sh` in the documented isolated validation host with declared prerequisites; exit 0 at source 5c28d8d.
- [x] Run `sh tests/service-lifecycle-integration.sh`; separate `AGH_INTEGRATION_SHELL=busybox AGH_INTEGRATION_SHELL_ARG=ash busybox ash tests/service-lifecycle-integration.sh` also exits 0 for all 28 groups.
- [x] Run `sh tools/check-md5.sh`, `sh tools/check-sha256.sh`, `sh tools/check-release-consistency.sh`, workflow lint and `git diff --check`.
- [x] The combined passing result is a software validation gate; it is not evidence of ASUS firmware dispatch, DHCP leases or overnight physical-router behavior.

### Current result

All local canonical checks pass, including lint/formatting and 162 syntax checks in each of sh, BusyBox 1.37 ash and the built 1.25.1 ash harness. Existing helper-extraction fixtures and the workflow command inventory were updated for the new dependencies without suppressing failures. CI retains its 180-second per-check budget; the isolated local host used a recorded 600-second budget. TASK-017 stays In Progress pending current-head hosted evidence; TASK-018 stays In Progress with physical acceptance BLOCKED.

---
