---
name: router-change-plan
description: Plan an Asuswrt-Merlin installer change with shared task state, bounded scope, and verifiable router contracts.
---

# Router change plan

Use for a multi-step repair, feature change, or integration before implementation.
Read [canonical instructions](../../../AGENTS.md) and the
[integration guide](../../../docs/agent-integrations.md); they govern this skill.

## Procedure

1. Confirm the requested result, repository, branch, current head, and existing
   modifications. Inspect the diff and only the code needed to establish scope.
2. Read `.tasks/config.json` and the current task lists. Prefer Next over Backlog;
   preserve IDs and use the existing TaskPlanner state rather than a second queue.
3. Record a short plan in the selected task before coding. Name affected files,
   observable behavior, acceptance criteria, and unresolved material assumptions.
4. Distinguish router-runtime dependencies from permitted host validation tools.
   Target POSIX `/bin/sh`, BusyBox 1.25.1, constrained memory, and stock PATH rules.
5. Map the change to service, DNS/DHCP, firewall, NVRAM, install/upgrade/uninstall,
   interruption, rollback, and shared-hook preservation contracts as applicable.
6. Choose the smallest coherent implementation. Identify directly required
   companion tests, generated checksums, documentation, and agent configuration.
7. Select verification from existing tools and `tools/virtual-arm/features.tsv`.
   Define what each check proves and what remains a physical release requirement.
8. Delegate independent work with separate file ownership; identify one PR
   observer and one publishing writer so agents reuse a common review snapshot.

## Acceptance boundary

- The armv5 package label represents older ARMv7 RT-AC68U-class software float,
  with VFP/NEON disabled; it is not a hard-float or newer-generation target.
- Virtual acceptance requires matching selected scope on armv5, armv7, and armv8
  for the tested candidate content. It unblocks covered feature/change checks.
- Physical hooks, clients, reboot, WAN exposure, and soak remain separate gates.
- A plan does not authorize merges, releases, review requests, or external setup.

## Provenance

Original repository procedure informed by Skillquiver planning and Karpathy:
`skill://plugins_6a806c0ea80c8191baf8ddda2285e1e8/writing-plans/SKILL.md`;
`skill://plugins_6ab00df042548191acc5580e83767711/karpathy-guidelines/SKILL.md`.
No upstream implementation or external executable is bundled.
