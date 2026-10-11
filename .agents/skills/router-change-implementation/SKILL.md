---
name: router-change-implementation
description: Implement a bounded router installer change while preserving BusyBox compatibility, state recovery, and all agent guardrails.
---

# Router change implementation

Use after a concrete task plan exists and implementation is authorized.
Read [canonical instructions](../../../AGENTS.md) and the
[integration guide](../../../docs/agent-integrations.md); they govern this skill.

## Procedure

1. Read the active `.tasks/` plan, current diff, and nearest lifecycle callers.
   Preserve unrelated changes and match the surrounding file's shell style.
2. Make only changes required by the observed failure or approved behavior.
   Avoid speculative abstractions, broad refactors, or additional dependencies.
3. Keep runtime code POSIX `/bin/sh` and BusyBox 1.25.1 compatible. Preserve
   per-script PATH, quoting, applet limits, and the stock/Entware distinction.
4. Preserve shared JFFS content when repairing managed hooks. Validate required
   shebangs, executable permissions, managed-entry cleanup, and repeatability.
5. For stateful changes, inspect partial setup, signals, service restart failures,
   rollback ownership, stale locks, and restoration of firewall/NVRAM state.
6. Preserve topology-aware DNS/IPSET rules and IPv4/IPv6 policy. Do not introduce
   incidental flash writes, unbounded retries, or uncontrolled background work.
7. Add a focused regression when needed to prove a real behavioral correction.
   Validate nested AWK, regex, YAML, and JSON separately from shell syntax.
8. When changing `installer`, regenerate its MD5 and SHA-256 companion records.
   Run [router change verification](../router-change-verification/SKILL.md).
9. Inspect the final diff and record changed behavior, evidence, and limitations
   in the existing task log. Coordinate publication through the designated writer.

## Scope and authority

- Only one writer stages, publishes, or mutates a PR at a time; delegates own
  distinct files and report changes for the coordinator's independent review.
- Host Python, GNU tools, Docker, and QEMU do not become router dependencies.
- Older armv5-labeled coverage is ARMv7 software float with VFP/NEON disabled.
- Do not weaken current-head checks or physical release gates to complete work.
- Merge, release, review requests, and external setup need task authorization.

## Provenance

Original repository procedure informed by minimal, goal-driven implementation:
`skill://plugins_6ab00df042548191acc5580e83767711/karpathy-guidelines/SKILL.md`.
No upstream implementation or external executable is bundled.
