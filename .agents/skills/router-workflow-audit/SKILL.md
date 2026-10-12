---
name: router-workflow-audit
description: Audit repository automation for concrete Actions trust-boundary defects while retaining existing reviewers and test contracts.
---

# Router workflow audit

Use when auditing or changing GitHub Actions and agent automation.
Read [canonical instructions](../../../AGENTS.md) and the
[integration guide](../../../docs/agent-integrations.md); they govern this skill.

## Procedure

1. Inspect touched workflows, their callers, scripts, triggers, permissions, and
   checkout refs. Establish which inputs originate from an untrusted PR or event.
2. Trace any path from attacker-controlled content to a privileged job, secret,
   write token, cache, artifact, executable, or publication step.
3. Check least-required permissions and third-party action/source pinning.
   Report a defect only when the trust path and practical consequence are proven.
4. Inspect expression interpolation into shell commands, unsafe event handling,
   and any `pull_request_target` execution of untrusted PR code with privileges.
5. Keep privileged publication separate from untrusted validation. Inspect cache
   and artifact provenance before accepting their contents as executable evidence.
6. Verify that regression imports/execution cannot access analysis credentials;
   secrets must stay out of logs, reports, fixtures, and untrusted processes.
7. Preserve CodeRabbit/Qodo/Sonar and existing quality/security checks. Do not
   disable findings, weaken thresholds, or change protections to obtain green CI.
8. Preserve exact-content ARM evidence and affected-builder invalidation. Host
   checks cannot substitute for native selected-feature acceptance.
9. For an authorized repair, propose the smallest compatible workflow change,
   run applicable static checks, and inspect resulting current-head CI evidence.
10. Record scope, evidence, concrete remediation, and external-state limitations
    in the existing task log; do not infer live settings from local YAML alone.

## Boundaries

- Begin with local, read-only inspection; do not execute untrusted repository code
  with credentials or trigger external workflows merely to explore a suspicion.
- Repository edits follow the task's authority. App installation, secrets,
  billing, rulesets, review requests, merge, and release need their own authority.
- Audit findings concern code and trust paths, not contributor identity or intent.
- Use available checking tools; no bundled upstream auditor is assumed here.

## Provenance

Original procedure informed by Awesome Maintainer Defense's evidence-led audit:
`skill://plugins_6a6edab2886c81918be9c9772e4ca904/audit-repository-workflows/SKILL.md`.
No upstream implementation or external executable is bundled.
