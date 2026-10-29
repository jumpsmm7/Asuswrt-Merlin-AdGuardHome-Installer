# In Progress

## TASK-038: Repair reboot recovery and complete stack CI synchronization

**Priority:** P1 | **Tags:** v2.7.0, recovery, ci
**Dependencies:** TASK-033, TASK-035
**Authority:** October 29, 2026 maintainer request to resolve merge conflicts, regression pathways and CI issues across stack #1044.

### Plan

- Preserve the reproduced #1045 failure: a persistent IPSet recovery journal references a volatile dnsmasq backup lost at reboot; actual helpers repeatedly refuse recovery and publication under host sh and BusyBox 1.25.1.
- Retain new recovery backups durably with validated boot identity. Preserve regenerated runtime configuration on a new boot; narrowly rebase legacy journals only at a validated, locked managed publication boundary. Preserve refusal and retry evidence when those conditions are absent.
- Replace the OSV differential job's full-history/all-ref checkout with bounded exact-commit selection and secure full-scan reporting when no baseline exists. Keep vulnerability failure enforcement and upload permissions intact.
- Synchronize master archive updates through readiness, DNS and completion with history-preserving merges, then run focused recovery/checkout/workflow checks, canonical host quality and fresh published-head native acceptance.

### Acceptance criteria

- [x] #1045 legacy missing-backup recovery and new-boot durable recovery unblock the covered publication contract; same-boot rollback, unsafe journals, signals and cleanup remain covered by host sh and BusyBox 1.25.1 regressions.
- [x] Actual local Git fixtures cover PR, push, new branch/root and unavailable predecessor selection without all-history fetching or suppressed vulnerabilities.
- [x] Complete scanner results are required before full/differential reporting and uploads; missing or partial scans fail while genuine vulnerability results remain reportable.
- [ ] All three branches include their immediate base; complete current-head checks/reviews and matching three-target native gates are observed after publication.
- [x] Retain v2.7.0-rc.1 and the default master-promotion restriction. Physical operator acceptance and soak remain NOT RUN.

**Status:** Focused checks and isolated canonical host quality PASS at implementation `03ffa2972abff228d18881a97d9f389184b1fadf` / tree `a40ba2ec821c9ccf645d3bcc47b44c15af2c4003`. Subsequent master archive synchronization and current-head hosted/native verification remain pending; no merge, physical or release claim is made.

## TASK-036: Record v2.7.0 physical acceptance and soak

**Priority:** P1 | **Tags:** v2.7.0, reliability, validation
**Dependencies:** TASK-035
**Scope:** Run candidate-specific firmware/client/reboot/isolation/WAN checks and 48-hour ARMv7/AArch64 soak, including older RT-AC68U coverage; record actual models/firmware, candidate hashes, configuration, timestamps/events and sanitized outcomes.

### Plan

- Read the accepted [v2.7.0 plan](../docs/v2.7.0-plan.md), current diff and nearest lifecycle tests.
- Implement a small evidence-backed slice in the listed surfaces; split independent corrections into reviewable commits/PRs.
- Verify the focused regression, appropriate host checks and fresh matching native scope before claiming completion. Preserve failure logs and physical boundaries.

**Likely surfaces:** New release checklist; operator evidence; task log

### Acceptance criteria

- [ ] Operator evidence identifies exact deployed candidate and real coverage/duration. Earlier v2.6.7 PASS remains historical PASS. Software feature acceptance stays independently unblocking; whole-release physical approval is separate.
- [ ] Record actual verification, publication/current-head status and remaining limitations in this ledger.

### Physical execution boundary

Prepare the complete candidate-specific checklist and sanitized evidence record now. Actual router runs and the final 48-hour ARMv7/AArch64 soak require operator hardware results and stay unchecked until supplied. Historical v2.6.7 passes are not relabeled.

### Preparation checkpoint (2026-10-22T12:11:21-04:00)

The qualified software source, hashes, operator guide and candidate checklist are recorded. New candidate deployments, actual firmware/operator/start/end identities, full physical checklist and 48-hour ARMv7/AArch64 soak remain NOT RUN / NOT RECORDED for RT-AC68U, RT-AC5300 and GT-BE98PRO. Historical v2.6.7 physical PASS remains historical PASS; passing covered virtual software contracts are independently accepted.


---

## TASK-018: Validate physical-router recovery and package v2.6.7

**Published release state:** v2.6.7 is published at tag `047ce167685f6de8db86519557b865e9f23e98f3` (October 10, 2026 America/New_York). Later unchecked pre-merge/quota statements below are historical snapshots, not current release blockers or relabeled passes. Unreported supplemental traceability stays unreported; new v2.7.0 qualification is tracked separately.

**Subsequent repository state:** PR [#1033](https://github.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/pull/1033) was merged into master as `047ce167685f6de8db86519557b865e9f23e98f3` on October 10, 2026 (America/New_York). Pre-merge authorization and check statements below are historical records, not a claim that the PR remains open. Release publication and supplemental traceability remain separate; the quota-blocked reviewer is not relabeled as passing.

**Physical acceptance: PASS — operator-confirmed full checklist and 48 hours on RT-AC5300 / 386.14_2 and GT-BE98PRO / 3006.102.9, plus reported RT-AC68U / 386.14_2 physical testing (October 10, 2026 America/New_York). Remaining work is exact build/event traceability and the separate hosted required-check/release disposition.**

**Priority:** P1 | **Tags:** release, hardware, dns
**Dependencies:** TASK-017
**Estimated scope:** Medium, five files

### Plan

- Create proposed `RELEASE-2.6.7-CHECKLIST.md` from the applicable requirements of the existing v2.6.5 checklist and DNS lifecycle validation document.
- Update `README.md` with the new checklist and accurately scoped repair notes.
- Prepare the authorized software candidate by changing only installer banner and `AI_VERSION` to v2.6.7 and refreshing `installer.md5sum`/`installer.sha256sum`. Physical acceptance is now recorded as PASS; hosted required-check disposition and release approval remain separate.
- Keep upstream AGH channels and archive refreshes outside this repair release unless independently required to fix a proven defect.

### Acceptance criteria

- [x] Fresh install, legacy v2.6.0-or-earlier upgrade, v2.6.5 upgrade, and v2.6.6 upgrade repair hooks and preserve user settings; no duplicate hooks, cron jobs or firewall rules. Operator confirmed the full checklist passed on the recorded RT-AC5300 and GT-BE98PRO configurations; individual RT-AC68U checklist detail was not separately supplied.
- [x] Firmware-dispatched DNS restart, cold boot, AGH restart/failure, DHCP new lease/renewal/expiry, main/SDN local A/PTR resolution, guest isolation, cache on/off, supported IPv6, slow filter startup and interrupted upgrade/uninstall recover correctly. Validate from a client on each network and verify both TCP/UDP listeners: AGH 53 with managed dnsmasq 553 while running; native DNS after required recovery.
- [x] Recommended soak: at least two overnight maintenance periods (48 hours) with actual scheduled events recorded; include the originally affected model/firmware when available. Capture sanitized listener/PID ownership, hook first lines/modes, relevant event logs and lease outcomes before/after; verify intended WAN IPv4/IPv6 TCP/UDP DNS exposure. Operator confirmed 48 hours and the full checklist passed; detailed event timestamps/logs were not supplied. Current physical results are in RELEASE-2.6.7-CHECKLIST.md.
- [x] Version/banner/manifests agree and release notes distinguish demonstrated repairs from unverified firmware cases. Local and hosted software checks pass at verified repair implementation 22d44a2, except the separately quota-blocked generated AI review; older source records remain historical evidence. No automatic merge/publication is part of this task plan.
- [ ] All current-head hosted required checks/reviews pass before merge or release. Generated GitHub AI review at 22d44a2 remains blocked by HTTP 402 monthly quota; no merge, tag, release or policy waiver is authorized by this physical update.

### Verification

- [x] Record the operator's physical pass report, the three models/firmware pairs and the two explicit full-checklist/48-hour runs in RELEASE-2.6.7-CHECKLIST.md. Detailed per-router artifacts are identified as not supplied.
- [ ] Complete supplemental traceability when available: BusyBox version, topology/SDNs, initial installer/channel, cache setting, deployed commit/hashes, event/start/end timestamps and sanitized artifacts; individual RT-AC68U duration/checklist detail is also unreported. These unprovided fields are not invented or treated as a new physical test failure.
- [x] Run `sh tools/update-checksums.sh installer`, all checksum/release-consistency checks, and affected targeted checks after the version change.
- [x] Preserve rollback evidence and pre-upgrade recovery paths; do not repeat the destructive whole-file workaround on shared hooks. The current operator-reported physical acceptance is PASS; the historical planning record below is unchanged.

### Decisions to settle before implementation

- [x] Selected TASK-015's recommended immediate busy status for a contended fallback stop; atomic acquisition and no-overlap requirements remain fixed.
- [x] Physical coverage is completed and reported by the maintainer/operator on October 10, 2026 America/New_York. The RT-AC5300 and GT-BE98PRO completed the full checklist and 48 hours; RT-AC68U is additional reported coverage. Exact window timestamps remain unreported.

---

### Historical planning verification record

- Four existing hook/doctor regressions passed under host sh: event-script modes, event-script transactions, doctor fix safety, and legacy hook cleanup.
- Independent actual-function scratch proofs reproduced malformed hook generation/reinstall/doctor false OK, fallback start/stop overlap, monitor shutdown failure suppression, and lock/probe symlink target truncation.
- BusyBox and ShellCheck were unavailable in this planning host. Physical router and firmware behavior were not exercised.
- Historical #735 slow-startup and #252/#253 firewall/DNS Director reports are regression inputs, not newly confirmed v2.6.6 defects.
- No current source fix, exhaustive vulnerability scan, remote exploitation, security advisory, issue reopening, or release was claimed.

Sources: [reported DHCP regression #1029](https://github.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/issues/1029), [v2.6.6 repair PR #1030](https://github.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/pull/1030), [virtual acceptance and firmware limitations](https://github.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/pull/1030#issuecomment-6022881933).
