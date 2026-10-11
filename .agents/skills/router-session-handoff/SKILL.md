---
name: router-session-handoff
description: Preserve a verifiable handoff for every existing agent using the repository task log and current PR/test evidence.
---

# Router session handoff

Use when pausing, transferring ownership, or completing an implementation session.
Read [canonical instructions](../../../AGENTS.md) and the
[integration guide](../../../docs/agent-integrations.md); they govern this skill.

## Procedure

1. Record repository/worktree, branch, full head, base, PR link, and any unrelated
   or uncommitted changes. Distinguish local edits from published remote content.
2. Update the existing task in `.tasks/` and append relevant evidence to
   `.tasks/WORK_LOG.md`; preserve IDs, decisions, and historical test provenance.
3. State the requested goal, completed behavior, remaining work, assumptions,
   scoped authorization, and the next concrete action without a second task queue.
4. Record changed files and meaningful decisions with reasons. Link existing
   documentation; create decision records only when a durable decision needs one.
5. Record tests actually executed, commands, selected features, result locations,
   matching tested-content/builder evidence, exit status, and known limitations.
6. Separate host checks, native ARM evidence, modeled firmware, and operator
   physical results. Keep unreported physical metadata explicitly unknown.
7. Preserve the armv5 label's older ARMv7 RT-AC68U-class software-float meaning,
   with VFP/NEON disabled, and scoped virtual versus physical gate boundaries.
8. Reuse the designated PR observer's fully paginated snapshot. Record head,
   current checks, unresolved threads, pending requests, and rate-limit constraints.
9. Link Qodo's authenticated PR summary/history rather than creating a competing
   resolver ledger. Preserve deliberate dispositions and avoid repeat-fix churn.
10. Transfer observer/writer ownership explicitly. Receiving agents re-check the
    diff, current remote head, and changed evidence before claiming completion.

## Completion and handling

- Move a task to Done only when its acceptance criteria are verified; otherwise
  record remaining blockers and the actual state in the existing task lists.
- Document quota/service failures separately from proven code defects; do not
  mark missing or failed checks as passed or reuse stale head evidence.
- Exclude tokens, credentials, private client identifiers, and unnecessary raw
  router configuration from checked-in logs and public PR descriptions.
- A handoff does not grant merge, release, review-request, or external-setup
  permission beyond the authority already present in the task.

## Provenance

Original procedure informed by EngineeringSuite's decision/context guidance:
`skill://plugins_6aa191da1fc481918b1b2cdf6adf2f7b/documentation-and-adrs/SKILL.md`.
No upstream implementation or external executable is bundled.
