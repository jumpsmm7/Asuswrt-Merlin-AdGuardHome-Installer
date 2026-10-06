# Done

## TASK-001: Establish DNS lifecycle baseline
**Priority:** P1 | **Tags:** dns, lifecycle

Part 1 of the six-part implementation. Keep changes off master; commit and validate separately.

### Checkpoint

- Development branch created from origin/master at e3866c4.
- Original handoff failure diagnosed as non-root fixture ownership; unchanged dash test passes in a root-mapped namespace.
- BusyBox netstat, startup readiness, adaptive dnsmasq readiness and Local Cache save-failure tests pass. Extended lifecycle tests are being checked separately.
- Expected behavior and pending router checks recorded in docs/dns-lifecycle-validation.md.

---

## TASK-002: Default to refuse-unknown on install and upgrade
**Priority:** P1 | **Tags:** dns, lifecycle

Part 2 of the six-part implementation. Keep changes off master; commit and validate separately.

### Checkpoint

- Missing install/upgrade policies default to refusal; explicit 0/1 and both CLI selections tested. Upgrade and migration regressions pass. Checksums regenerated.

---
