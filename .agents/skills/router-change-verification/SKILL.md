---
name: router-change-verification
description: Verify changed router contracts with current-head host checks, scoped ARM evidence, and separately reported physical acceptance.
---

# Router change verification

Use before publishing or claiming that a changed contract passes.
Read [canonical instructions](../../../AGENTS.md) and the
[integration guide](../../../docs/agent-integrations.md); they govern this skill.

## Procedure

1. Record the candidate head, final diff, selected contracts, and prerequisites.
   Match commands to changed behavior; avoid repeating costly checks needlessly.
2. For touched shell, run target-appropriate syntax checks, preferring BusyBox
   `ash -n` when available. Inspect embedded-language syntax and final quoting.
3. Run the nearest meaningful regressions and `sh tools/code-quality.sh` as
   required by the change. Inspect actual output and exit status before reporting.
4. Select virtual features from `tools/virtual-arm/features.tsv` and execute with
   the current checkout's `tools/test-virtual-arm.sh` and testing guide.
5. Validate reports using `tools/virtual-arm/check-evidence.py`. Require matching
   selected scope, tested content, and complete armv5/armv7/armv8 execution.
6. Rebuild affected environments when builder inputs change; obtain fresh matching
   reports when tested inputs change. Retain failures and report actual counts.
7. After publication, have the designated PR observer inspect every architecture
   job and the aggregate ARM feature acceptance check on the exact published head.
8. Paginate all check data. Missing, pending, skipped, cancelled, failed, stale,
   or incomplete evidence cannot support a passing claim for that contract.
9. Record commands, statuses, evidence locations, selected features, provenance,
   and limitations in `.tasks/WORK_LOG.md`; report remaining work explicitly.

## Evidence boundaries

- armv5 is the RT-AC68U-class older ARMv7 software-float package target, with
  VFP/NEON disabled. Keep newer armv7 and AArch64 armv8 evidence distinct.
- Native guest CPU/process/socket assertions differ from modeled firmware calls.
- Complete virtual evidence unblocks its covered feature/change checks; physical
  acceptance does not independently block a covered passing virtual contract.
- Virtual tests do not prove physical hook dispatch, DHCP/isolation, reboot,
  WAN exposure, soak, or whole-release acceptance. Preserve those release gates.
- Operator physical results must state models, firmware, scope, and provenance;
  preserve unreported details as unknown instead of inventing evidence.

## Provenance

Original procedure informed by evidence-based completion guidance:
`skill://plugins_6a806c0ea80c8191baf8ddda2285e1e8/verification-before-completion/SKILL.md`.
No upstream implementation or external executable is bundled.
