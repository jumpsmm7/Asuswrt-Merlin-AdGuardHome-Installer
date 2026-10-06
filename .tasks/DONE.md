# Done

## TASK-009: Resolve PR #1030 docstring coverage

**Priority:** P2 | **Tags:** documentation, validation

### Checkpoint

- Confirmed PR #1030 and checkout at c6a8aff37ff28a2ce8e186481c3c04ea7d48d440. Added function comments for undocumented runtime and fixture helpers; regenerated all four runtime artifacts' MD5/SHA-256 sidecars.
- Local comment audit covers 137/137 touched shell definitions, including fixtures; the hosted CodeRabbit percentage still requires a remote rerun. All 16 edited shell files contain only full-line comment additions. Syntax, eight digests, and 11 focused regressions pass under host sh.
- DNS handoff regression fails at the same successful-start assertion on both unchanged HEAD and this patch under the host shell. BusyBox ash and ShellCheck are unavailable; router behavior was not exercised.

---

## TASK-008: Resolve PR 1030 CI failures and agent review threads

**Priority:** P1 | **Tags:** dns, lifecycle, ci

### Checkpoint

- The missing upgrade policy regression expects `refuse-unknown`; explicit `legacy` and `refuse-unknown` values are preserved. All five new tests run in the canonical quality suite, and Amazon Q guardrails mirror the canonical file.
- Seven Qodo findings and three CodeRabbit findings were verified against the current code. Confirmed resolver/lock/readiness defects were fixed, intentional expansion was documented, and the serialization fixture allows bounded scheduling delay on busy CI. Required SDN configurations include files created during firmware restart.
- The complete root Docker code-quality runner passes, including lifecycle integration, foreign-owner security fixtures, ShellCheck, formatting and checksums. Focused BusyBox ash tests and syntax checks pass. Qodo's summary, evidence replies and thread resolution are tracked on PR #1030.
- Hardware validation remains skipped as requested. Changes stay off master and the user retains PR merge ownership.

---

## TASK-007: Review and validate final DNS lifecycle readiness

**Priority:** P1 | **Tags:** dns, lifecycle

### Checkpoint

- Independent review found and fixed helper-PID readiness, exiting-owner reconciliation, stale Local Cache preferences, concurrent resolver mounts and cleanup ordering before stop/restart.
- 44 relevant regressions pass, including both resolver lock backends and the reused process-lock/IPSET paths. All 158 shell scripts pass BusyBox ash syntax and ShellCheck warning checks. Artifact checksum verification and checksum-format checks pass.
- Documentation states the refuse-unknown default and current cache lifecycle. Changes remain on the development branch; hardware validation remains explicitly skipped and unverified. GitHub Actions has not been run for this branch.

---

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

## TASK-003: Identify managed main and SDN dnsmasq instances

**Priority:** P1 | **Tags:** dns, lifecycle

Part 3 of the six-part implementation. Keep changes off master; commit and validate separately.

### Checkpoint

- Read-only managed detection tests pass under BusyBox ash: main and multiple SDN PIDs, alternate display names, duplicate sockets, unknown/stale PIDs, unsupported firmware, foreign configs, scoped listeners and symlinks. Runtime syntax passes.

---

## TASK-004: Coordinate DNS handoff and recovery

**Priority:** P1 | **Tags:** dns, lifecycle

Part 4 of the six-part implementation. Keep changes off master; commit and validate separately.

### Checkpoint

- Managed owner escalation revalidates PID/config identity; replacement main and SDN listeners are checked with bounded retries. Multi-SDN lifecycle, existing handoff, WAN/LAN lifecycle, netstat, dnsmasq publication and permission tests pass under BusyBox 1.30. Firmware ALL_SDN dispatch documented; hardware checks remain pending.

---

## TASK-005: Defer Local Cache until DNS readiness

**Priority:** P1 | **Tags:** dns, lifecycle

Part 5 of the six-part implementation. Keep changes off master; commit and validate separately.

### Checkpoint

- Local Cache resolver bind removed from postconf; startup and monitor apply only after AGH loopback and all enabled SDN/main readiness. Cleanup runs before start, shutdown and failure. Cache race/failure/idempotence, handoff, publication, stop, monitor and preference regressions pass under BusyBox 1.30.

---

## TASK-006: Validate integration and prepare release documentation

**Priority:** P1 | **Tags:** dns, lifecycle

Part 6 of the six-part implementation. Keep changes off master; commit and validate separately.

### Checkpoint

- 41 relevant regressions pass; 157 BusyBox ash syntax checks and complete artifact MD5/SHA-256 verification pass. New tests added to CI; recovery ordering corrected; release notes and acceptance matrix documented. Hardware testing explicitly skipped by user and remains unverified.

---
