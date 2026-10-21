# Next

## v2.7.0 authorized implementation roadmap

Baseline: master `7ecacf124658cc1ec23cb6aae62622f2ace9bfd5`. The maintainer approved the consolidated release scope and authorized implementation. Work follows [the release plan](../docs/v2.7.0-plan.md); pending physical acceptance is separate from covered virtual feature checks.



## TASK-032: Add an opt-in sanitized diagnostic export

**Priority:** P2 | **Tags:** v2.7.0, reliability, validation
**Dependencies:** TASK-030, TASK-031
**Scope:** Build a bounded allowlisted support report from existing status/doctor/recovery data; exclude secrets, raw NVRAM/configuration, query history and private client/domain/address details. Preserve safe path handling, unavailable-storage behavior and operator-controlled sharing.

### Plan

- Read the accepted [v2.7.0 plan](../docs/v2.7.0-plan.md), current diff and nearest lifecycle tests.
- Implement a small evidence-backed slice in the listed surfaces; split independent corrections into reviewable commits/PRs.
- Verify the focused regression, appropriate host checks and fresh matching native scope before claiming completion. Preserve failure logs and physical boundaries.

**Likely surfaces:** installer; diagnostic regressions; README/help; checksum sidecars

### Acceptance criteria

- [ ] Useful sanitized state is retained; secret/path/adverse-storage fixtures pass. Clean-state collection starts no setup and makes no service/NVRAM/firewall changes; interrupted-transaction recovery is separately reported. No automatic upload or required external database.
- [ ] Record actual verification, publication/current-head status and remaining limitations in this ledger.

---

## TASK-033: Investigate constrained-router maintenance failure gaps

**Priority:** P2 | **Tags:** v2.7.0, reliability, validation
**Dependencies:** TASK-030
**Scope:** Inventory coverage and reproduce missing/delayed Entware/USB, full/read-only storage, download/extraction/write failures, interruptions and resource pressure. Implement only demonstrated corrections, preserving settings/shared hooks/DNS recovery.

### Plan

- Read the accepted [v2.7.0 plan](../docs/v2.7.0-plan.md), current diff and nearest lifecycle tests.
- Implement a small evidence-backed slice in the listed surfaces; split independent corrections into reviewable commits/PRs.
- Verify the focused regression, appropriate host checks and fresh matching native scope before claiming completion. Preserve failure logs and physical boundaries.

**Likely surfaces:** Affected helpers and nearest regressions, determined by reproduction

### Investigation inputs

- [Issue #1039](https://github.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/issues/1039) reports helper downloads attempted after AGH stops while router DNS is unavailable. Reproduce the update/download ordering and recovery before selecting a fix; reported router behavior is not yet a new verified result.
- [Issue #1041](https://github.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/issues/1041) records a verified pre-existing recovery gap: failed refresh/publication plus failed IPSet restoration retains a configuration association but deletes its required backup, so the next actual recovery still fails after the fault clears. Finalization-only cleanup failures recover successfully and must not cause blanket backup retention. This is separate from PR #1040's takeover parser.

### Acceptance criteria

- [ ] Every correction has a failing reproduction and focused pass; successful paths and recovery remain intact. Distinguish guest failures from modeled firmware/hardware resource evidence; avoid speculative tuning.
- [ ] Record actual verification, publication/current-head status and remaining limitations in this ledger.

---

## TASK-034: Extend supported-channel native lifecycle coverage

**Priority:** P2 | **Tags:** v2.7.0, reliability, validation
**Dependencies:** TASK-030, TASK-031
**Scope:** Extend actual startup/listener/DNS/restart/stop/recovery/conflict checks for beta and edge alongside stable, with per-channel/architecture provenance and bounded runs.

### Plan

- Read the accepted [v2.7.0 plan](../docs/v2.7.0-plan.md), current diff and nearest lifecycle tests.
- Implement a small evidence-backed slice in the listed surfaces; split independent corrections into reviewable commits/PRs.
- Verify the focused regression, appropriate host checks and fresh matching native scope before claiming completion. Preserve failure logs and physical boundaries.

**Likely surfaces:** tests/virtual-arm-native.sh; feature manifest; evidence regressions/docs/workflow only as needed

### Acceptance criteria

- [ ] Every claimed lifecycle contract has real matching channel/architecture evidence. Execution/config-only tests are labeled honestly; failures cannot be skipped or converted into parity claims.
- [ ] Record actual verification, publication/current-head status and remaining limitations in this ledger.

---

## TASK-035: Qualify the v2.7.0 software release candidate

**Priority:** P1 | **Tags:** v2.7.0, reliability, validation
**Dependencies:** TASK-030, TASK-031, TASK-032, TASK-033, TASK-034
**Scope:** Assemble reviewed changes, update candidate version/checksums/docs and aligned agent guidance, validate fresh and supported legacy migration/update/restore/uninstall/interruption paths, obtain current-candidate host/coverage/native/hosted review evidence.

### Plan

- Read the accepted [v2.7.0 plan](../docs/v2.7.0-plan.md), current diff and nearest lifecycle tests.
- Implement a small evidence-backed slice in the listed surfaces; split independent corrections into reviewable commits/PRs.
- Verify the focused regression, appropriate host checks and fresh matching native scope before claiming completion. Preserve failure logs and physical boundaries.

**Likely surfaces:** Candidate/version/checksum/release docs; shared agent guidance; required regressions

### Acceptance criteria

- [ ] Published-head applicable checks and genuine blocking findings resolved. Fresh matching selected contracts across all three package targets; no native/physical scope conflation. Existing Qodo/task/MCP authorities retained; no new mandatory external service.
- [ ] Record actual verification, publication/current-head status and remaining limitations in this ledger.

---

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

---

## Historical v2.6.7 planning record

The following is retained history; the v2.6.7 release is already published.


## v2.6.7 repair-only implementation plan

**Baseline:** `85b926b4b32fcab4f48d038b6ab6281f23d3df70` on the existing `work` checkout; installer identifies itself as v2.6.6. Plan recorded October 7, 2026 (America/New_York).

**Goal:** Repair reproducible hook, service-lock, and shutdown failures, then validate the reported DNS/DHCP outage on supported firmware.

**Architecture:** Keep the existing installer transactions and service entry points. Repair their content, ownership, serialization, and shutdown postconditions with narrowly scoped POSIX shell changes. Preserve BusyBox 1.25.1, fixed stock-first runtime PATH, topology gating, explicit DNS cleanup preferences, user hook commands, and aggregate rollback.

**Scope:** No new features or broad refactors. The user authorized repository implementation on October 8, 2026. Work proceeds on fix/v2.6.7-repairs with independently verified commits. Preparing the v2.6.7 software candidate is authorized; publication and claims of physical-router recovery remain gated on recorded hardware results.

**Evidence:** Legacy hook-only migration deletes the chmodded file and recreates it without a shebang at mode 0600 under umask 077. Reinstall changes mode but leaves the malformed header, which doctor falsely accepts. Additional isolated actual-function fixtures reproduce mkdir start/stop overlap, suppressed monitor shutdown failure, and predictable lock/probe symlink target truncation. The latter's local privilege impact depends on unprivileged /tmp access and firmware symlink protection; no remote exploit or affected-router exploit was established.

**Task order:** TASK-012 -> TASK-013 for installer changes; TASK-014 -> TASK-015 -> TASK-016 for manager changes. The two tracks can proceed independently after interfaces are agreed. TASK-017 depends on all five repairs; TASK-018 depends on TASK-017 and hardware acceptance. Run each focused fixture against the unchanged baseline first, implement only the failure it proves, rerun it and nearest affected regressions, refresh the touched distributed script's two digests, then commit the passing slice.

---
