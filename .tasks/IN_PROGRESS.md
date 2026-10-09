# In Progress

## TASK-022: Resolve ready-review SonarCloud and Qodo findings

**Priority:** P1 | **Tags:** review, security, coverage, hooks, locks, tests
**Scope:** User follow-up on October 9, 2026 America/New_York: PR #1033 is now ready for review. Resolve its current SonarCloud findings and unresolved Qodo feedback while preserving repair-only behavior, the older ARMv7/software-float target, scoped virtual acceptance and separate physical release gates.

### Plan

- Inventory current-head SonarCloud issues, coverage/security gate conditions and Qodo inline/summary feedback; deduplicate and independently reproduce valid failures.
- Repair guest dependency confinement, indented managed-hook handling, read-only stale-owner activity detection and accurate historical-lock diagnostics with focused negative/safety regressions.
- Resolve valid scanner findings without disabling checks, weakening thresholds or rewriting unrelated code. Produce real coverage evidence for supported host Python/C sources and preserve the documented shell coverage limitation.
- Run focused checks, checksum/release validation, canonical host quality and fresh matching native ARM evidence for changed tested inputs; rebuild native tooling when required.
- Publish normal leased branch updates, reply with evidence and resolve addressed/rejected findings; inspect final-head Qodo, CodeRabbit, SonarCloud and software/ARM checks. Preserve the user's ready-for-review status and record external service blockers separately.

### Acceptance criteria

- [ ] Four current Qodo inline findings have reproduced fixes, evidence replies and resolutions. The summary's two alternative approaches are not additional findings; its recommendation agrees with scoped virtual acceptance and separate physical release gates.
- [ ] SonarCloud's current issue inventory and failing coverage/security conditions are resolved or individually documented with concrete evidence and any genuine access limitation.
- [ ] Runtime changes remain BusyBox 1.25.1/POSIX compatible; affected sidecars, targeted safety tests and complete isolated canonical host validation pass.
- [ ] Final matching three-target native execution and aggregate acceptance pass for changed tested content; pending/stale/skipped evidence is not reported complete.
- [ ] Published-head review/check states are inspected; PR stays ready for review with no merge, tag, release, check-policy waiver or billing/settings change. Physical TASK-018 gates remain separate.

### Execution record

- Authenticated CI logs contain all 51 unresolved Sonar issues: one reliability, 41 maintainability and nine security findings. Supporting Python/C tools, builder downloads and default-user policy have focused corrections; fresh hosted analysis must confirm closure.
- Qodo's payload escape is reproduced and prevented using canonical archive names and no-follow directory-descriptor reads. Regression cases reject parent traversal, absolute paths, symlink escapes and parent swaps while decoding a valid guest image.
- Ordinary hook indentation already worked. The remaining reproduced gap is an indented owned guard with a `# !manager` suffix; cleanup now agrees with validation and preserves unrelated commands/comments. Doctor distinguishes intentionally retained descriptor inodes from removable handoff markers.
- Read-only service probes require strictly validated dead PID/start-time identities before ignoring crashed metadata. Actual SIGKILL publication/cleanup cases preserve metadata; live, malformed and unsafe records remain busy. Independent review caught and regressed noncanonical leading-zero identities.
- Exact BusyBox 1.25.1 hook/doctor/lock/cache checks, 26 evidence-policy tests, host-tool and serial-protocol regressions, 259 real DNS protocol/CLI/socket cases and strict host/all-three-target C compilation pass. All modified Python functions score at most 14 under an estimator calibrated against Sonar's eight original scores; the limit remains 15.
- Fresh candidate coverage executes 44 tests. Python measured 924/989 lines and 270/320 branches; native C measured 214/227 lines and 134/152 branches, or 91.35% combined. CI imports actual execution reports, keeps supported sources in the denominator and retains all existing thresholds. Hosted new-code coverage remains pending.
- Builder source fingerprint is `eeb2c4d151b006598dfdb411caaf5f1e4ab1530684ae8a504779eea490c43339`. All three guests rebuilt successfully. The first canonical run passed behavioral/static checks but correctly failed portability on a new fixture's `command -v` lookup. It now uses the required `which`; both portability checks and Doctor's safety test pass. Canonical and full native evidence are rerunning at corrected tested-content digest `67139f867e43e874c0425112bd49a51ae0cc86452ea142e1325e80ae4fbf23ed`. Superseded native runs never unblock acceptance.
- Documentation audit finds purpose documentation for all 144 standalone Python, 13 embedded Python, 169 touched shell and 21 C definitions. Manager/installer MD5 and SHA-256 sidecars are refreshed. Publish the reviewed fixes after focused validation so hosted Sonar/Qodo analysis runs alongside complete final-content validation; remote review/check completion remains pending.

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
