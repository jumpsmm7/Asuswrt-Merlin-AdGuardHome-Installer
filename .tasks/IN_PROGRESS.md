# In Progress

## TASK-025: Resolve integration-checker hosted findings

**Priority:** P1 | **Tags:** agents, review, security, validation
**Scope:** PR #1034 onto master, current published correction head `33b9cf80de4d0171a61c5b3631507d25a6b5b072`. Correct newly reported host-only checker findings while preserving registry rejection and filesystem safety. Existing TASK-024 completion is the earlier implementation/publication snapshot.

### Plan

- Independently verify all 11 Sonar findings, including repeated policy literals, frontmatter parsing complexity, numeric character classes, redundant exception handling and caller-supplied root selection.
- Address two subsequently reported Codex consistency gaps: requested-provider deletion and malformed optional skill metadata must fail validation. Preserve valid existing Qodo trigger headers and document the supported metadata grammar; add isolated negative tests.
- Reject unquoted leading-decimal exponents consistently across agents' YAML versions while preserving quoted text; add signed/unsigned and quoted controls for the subsequently reported CodeRabbit case.
- Correct the focused Codex review's three portable-header gaps: decoded lone Unicode surrogates, comma-leading plain scalars, and tab indentation hidden by comment skipping. Cover adjacent reproduced non-ASCII separator/indentation cases while preserving valid Unicode text and space-indented comments. Add explicit binary-number controls for CodeRabbit's already-rejected case without changing working numeric detection.
- Simplify parsing and make CLI repository selection derive from the checked-in checker location. Keep isolated real-process tests by placing the checker in each disposable fixture repository; preserve no-follow descriptor access, nonregular-file rejection, read-only checks, stderr and timeout assertions.
- Re-run focused host safety tests and genuine credential-free coverage, independently review the final diff, and obtain fresh frozen all-three-target native evidence for the changed tested content. Keep physical acceptance separate and do not weaken thresholds or suppress findings.
- Publish normal leased PR updates, inspect current-head Sonar and other agent/check results through one observer, and record evidence-based thread dispositions using the existing Qodo resolver.

### Acceptance criteria

- [ ] All current Sonar issues are corrected and current-head strict zero-unresolved enforcement passes.
- [ ] Both valid Codex drift findings have rejected-fixture coverage; its obsolete task-status comment has an evidence-based disposition.
- [ ] The focused Codex portable-header findings have rejection and valid-string controls; CodeRabbit's binary-number claim has an evidence-based disposition.
- [ ] Focused rejection/safety tests, host quality and measured coverage pass without exclusions or changed thresholds.
- [ ] Fresh native evidence matches final tested content and aggregate acceptance passes on all three targets.
- [ ] Published-head review and check states are inspected; external blockers are reported separately. No merge, release, credentials, billing or branch-rule changes.

### Verification snapshot

- Script-derived CLI selection, linear frontmatter parsing, policy/metadata constants, ASCII numeric matching and exception simplification are implemented. Published correction `0211ddd` passes Sonar scan and strict zero-unresolved enforcement: all ratings A, 98.9% new-code coverage and zero unresolved issues. Its native runners are superseded by the subsequent Codex fixes and cannot unblock final source.
- The final checker protects all 27 requested providers and validates complete supported optional metadata, including colon separation. All 42 focused tests pass, with every provider-removal case, malformed optional fields, external-root rejection and bounded 100,000-whitespace parsing. Existing Qodo skills remain unchanged.
- Genuine credential-free final coverage passes 86 tests, measuring checker coverage at 99.10% and combined Python/C at 92.72%, with no exclusions or warnings. Full isolated host quality exits 0 (its integration step ran the earlier 37-case source before the subsequent focused Codex corrections); all final 42 cases also pass separately. Final frozen native acceptance and new-head hosted checks remain pending.
- At `33b9cf8`, hosted Sonar scan and strict enforcement pass with zero unresolved issues, all ratings A and 99.1% new-code coverage; Qodo reports zero findings. All three frozen local native runners complete 118 scenarios each, but the subsequent focused Codex corrections supersede that tested digest. These results are retained as source-specific evidence and do not unblock the next source.
- The portable-header corrections pass all 44 focused tests, including lone-surrogate rejection, valid Unicode/surrogate pairs, comma handling, ASCII layout, preserved non-ASCII scalar content and exact-name mismatches. Signed/unsigned binary-number controls verify existing rejection without a regex change. Independent review, refreshed coverage, native acceptance and published-head checks are still pending at this snapshot. The preceding hosted push's existing `dns_environment` case timed out; its unchanged local reproduction and two PR quality jobs pass, with no proven cause or timeout/gate change.

---

## TASK-018: Validate physical-router recovery and package v2.6.7

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
