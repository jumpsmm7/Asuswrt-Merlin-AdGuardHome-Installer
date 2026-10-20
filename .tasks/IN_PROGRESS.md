# In Progress

## TASK-030: Repair installation readiness and installer source selection

**Priority:** P1 | **Tags:** v2.7.0, reliability, validation
**Dependencies:** TASK-029
**Scope:** Reproduce the incomplete JFFS preflight and saved-source reset; correct readiness diagnostics, preserve action-scoped dependency repair, retain explicit/saved source through checks/re-exec, define --no-auto-update for a coherent installer/helper bundle, and clarify early unsupported non-interactive fresh-install refusal while preserving interactive compatibility.

### Plan

- Read the accepted [v2.7.0 plan](../docs/v2.7.0-plan.md), current diff and nearest lifecycle tests.
- Implement a small evidence-backed slice in the listed surfaces; split independent corrections into reviewable commits/PRs.
- Verify the focused regression, appropriate host checks and fresh matching native scope before claiming completion. Preserve failure logs and physical boundaries.

**Likely surfaces:** installer; nearest/new readiness/source/CLI regressions; checksums; README; host/native registration

### Implementation checkpoint

Readiness/source/CLI corrections and their focused regressions are implemented. They include stock JFFS read reasons and transaction stages, saved-source retention and read-error refusal, early flagged-fresh-install refusal, and the per-invocation compatible-bundle opt-out. Three new regressions are registered in the canonical host suite and shared native inventory. Independent review and focused checks pass; final integrated host/native evidence and publication remain pending. Interim `36e4fee` coverage passed 104 genuine tests and workflow lint passed 11 workflows, but its interrupted full quality run exposed three older fixture extraction gaps; those results are not a final full-suite pass.

### Acceptance criteria

- [ ] Failed reads cannot report JFFS OK; ready flags avoid unnecessary writes; dependency failures identify their stage. Explicit/saved refs and self-update policy persist without checksum bypasses or mismatched helpers. Interactive fresh setup remains supported; unsupported flagged setup stops before new ordinary writes/downloads, with existing recovery distinct.
- [ ] Record actual verification, publication/current-head status and remaining limitations in this ledger.

---

## TASK-031: Remove dnsmasq rebind and DNSSEC state during AGH takeover

**Priority:** P1 | **Tags:** v2.7.0, reliability, validation
**Dependencies:** TASK-029
**Scope:** Filter exact rebind/DNSSEC directives, companions, all trust-anchor/key entries and DNSSEC-only references from each managed main/SDN runtime config. Handle mixed/nested includes through safe runtime views, preserve persistent originals and existing per-file transactions/native regeneration.

### Plan

- Read the accepted [v2.7.0 plan](../docs/v2.7.0-plan.md), current diff and nearest lifecycle tests.
- Implement a small evidence-backed slice in the listed surfaces; split independent corrections into reviewable commits/PRs.
- Verify the focused regression, appropriate host checks and fresh matching native scope before claiming completion. Preserve failure logs and physical boundaries.

**Likely surfaces:** AdGuardHome.sh; focused dnsmasq/include/recovery tests; checksum sidecars; test manifests/docs

### Acceptance criteria

- [ ] All effective targeted options/keys absent at managed publication, including custom/root-rollover anchors. Includes preserve unrelated settings and valid lifetimes. Repeated/overlapping takeover, native fallback and staging/IPSET/publication failures preserve configuration/recovery invariants.
- [ ] Record actual verification, publication/current-head status and remaining limitations in this ledger.

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
