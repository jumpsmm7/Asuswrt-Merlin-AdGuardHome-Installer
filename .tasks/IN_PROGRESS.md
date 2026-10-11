# In Progress

## TASK-026: Add optional Lovable repository handoff support

**Priority:** P2 | **Tags:** agents, integration, documentation
**Scope:** PR #1034 onto master. The user selected repository integration support first; no Lovable project, database, connector, workspace skill or deployment is provisioned by this task.

### Plan

- Add a portable, repository-scoped Lovable skill and a versioned handoff contract for canonical policy, exact source provenance, existing task ownership and actual validation evidence.
- Document optional references to user-owned Lovable Cloud/Supabase data with explicit ownership, authorization and read-only scope. Keep `.tasks/`, GitHub review state and existing ARM/physical gate authority; private model training data is not exposed by these APIs.
- Register the adapter and align shared agent routing without replacing existing provider configurations. Explain GitHub API access separately from Lovable Git sync and preserve unrelated project/workspace instructions.
- Run existing integration checks, validate the handoff schema and its intended constraints, review the diff and publish a normal leased update to the existing PR. Observe the published head through one designated reviewer; report missing, pending or rate-limited results accurately.

### Acceptance criteria

- [x] The skill remains usable when imported alone into Lovable and loads canonical repository instructions from the supplied exact-head packet or verified immutable references.
- [x] Handoffs distinguish advisory analysis, host checks, native ARM execution, modeled firmware and physical operator reports; optional database references cannot become a second task ledger or a test waiver.
- [x] All existing agent entry points, Qodo skills and original provider IDs are preserved; Amazon Q remains byte-identical to canonical policy.
- [x] Existing integration checks and schema verification pass. Any unchanged native evidence is identified by its tested-content digest, not relabeled as a new run.
- [ ] The updated PR is published and current-head check/review state is recorded, including external service limitations.

### Verification

The read-only registry check passes with eight agent entry points, ten skills and 27 providers. All 44 existing integration regressions pass. The Draft 2020-12 schema and documented baseline packet validate, and its actual historical policy hash matches. Independent boundary review passes eight positive controls, 26 negative schema-shape controls and three bounded timestamp rejection controls. The timestamp controls register an explicit temporary checker; this adds no repository dependency and does not claim comprehensive RFC3339 parser validation. Amazon Q remains byte-identical to canonical policy, and `git diff --check` passes.

The current tested-content digest remains `28098abaac867cb1b95541bd4387c726ef5d797a865d60b84e58689b10c99877`. Existing frozen armv5/armv7/armv8 reports each contain 118 passing scenarios (354 total), and aggregate validation against the current checkout passes all 11 selected contracts. These are revalidated earlier executions, not new runs. No runtime, archive, test, validation-tool or workflow input changes are made here; physical acceptance is unchanged. Publication and hosted observation are pending.

Read-only account inventory on October 11, 2026 found a Pro workspace with zero projects, workspace skills and added connectors. The user chose repository support before external setup. No account identifiers, credentials or private database content are checked in.

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
