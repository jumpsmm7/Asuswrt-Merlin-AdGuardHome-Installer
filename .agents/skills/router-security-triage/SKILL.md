---
name: router-security-triage
description: Triage concrete router and repository security findings with sanitized evidence, bounded verification, and compatible repairs.
---

# Router security triage

Use for supplied vulnerability reports or a scoped code security review.
Read [canonical instructions](../../../AGENTS.md) and the
[integration guide](../../../docs/agent-integrations.md); they govern this skill.

## Procedure

1. Establish the supplied finding, affected code/configuration, candidate head,
   authorized scope, evidence date, and intended security decision.
2. Inspect the current diff and nearest trust boundaries. Identify untrusted
   values, reachable entry points, required conditions, and the practical effect.
3. Examine relevant download integrity/TLS, shell injection, path traversal,
   symlink races, script permissions, unsafe cleanup, and sensitive logging paths.
4. For router-state changes, inspect DNS/WAN exposure, IPv4/IPv6 policy, shared
   hooks, service interruption, persistent NVRAM, and rollback/restoration paths.
5. Separate confirmed observations, model assumptions, and unknowns. Record
   source, affected location, trigger, impact, confidence, and evidence limitation.
6. Group repeated root causes; reject speculative or style-only findings. Route
   duplicate Qodo feedback through its existing resolver and prior-round history.
7. When fixes are authorized, make the smallest BusyBox-compatible correction
   and prove it with a safe focused regression in an isolated validation context.
8. Verify matching selected ARM contracts when affected; state modeled firmware
   limits and any separate physical release validation that remains necessary.
9. Record disposition, fix/evidence references, residual impact, and follow-up
   scope in `.tasks/`; use the existing PR observer/writer for remote activity.

## Evidence and authority

- Prefer sanitized supplied logs, repository code, approved administrative
  exports, and permitted public references. Do not collect or publish secrets.
- Do not probe external routers, enumerate accounts, test credentials, exploit
  systems, or infer permission from a public hostname or apparent ownership.
- Local isolated regression work stays within the authorized repair scope;
  external investigation needs separately established scope and authority.
- Merge, release, review requests, external setup, and disclosure are separate
  actions; this skill does not authorize them.

## Provenance

Original procedure informed by defensive evidence synthesis:
`skill://plugins_6a972043ba948191848287ee55e51b98/defensive-exposure-analysis/SKILL.md`.
No upstream implementation or external executable is bundled.
