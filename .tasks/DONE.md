# Done

## TASK-016: Verify graceful monitor shutdown before reporting success

**Priority:** P1 | **Tags:** lifecycle, recovery, dns
**Dependencies:** TASK-015
**Estimated scope:** Medium, up to five files

### Plan

- Modify `AdGuardHome.sh:3162` (`start_monitor`; stop branches at 3201/3286) and `stop_all_monitors:3482`.
- Extend `tests/stop-adguardhome-failure.sh` and `tests/monitor-stop-config-fallback.sh`.
- Refresh both manager checksum sidecars.

**Interfaces:** Preserve `start_monitor`, `stop_all_monitors`, and `adguardhome_run stop_adguardhome`. Reuse `post_stop_process_ready`, `post_stop_handoff_cleared`, native resolver checks, and bounded required-dnsmasq readiness.

**Minimum correction:** Capture and return stop failure from both monitor exit paths. Before signaling, preserve whether DNS integration and main/SDN recovery are required; a later vanished daemon must not erase that requirement. After graceful monitor disappearance, the parent verifies daemon absence, handoff cleanup, native resolver state and required DNS recovery. Failed postconditions trigger one existing final recovery operation; propagate failure if it remains incomplete. Keep intentionally unmanaged LAN/AP integration unchanged and retain identity-checked escalation.

### Acceptance criteria

- [x] Successful stop requires the daemon absent, installer handoff state cleared, native resolver routing restored, and required main/SDN DNS recovered.
- [x] Resolver-unmount failure, surviving daemon, dnsmasq restart/readiness failure, and stale handoff state return nonzero instead of successful monitor disappearance.
- [x] Both monitor stop branches, multiple monitors, forced termination, missing /opt, repeated stop and intentionally unmanaged LAN/AP are covered without respawn or unintended DNS restart.

### Verification

- [x] Baseline focused additions to `sh tests/stop-adguardhome-failure.sh` reproduce direct stop failure with false successful parent/monitor status; fixed cases pass.
- [x] `sh tests/monitor-stop-config-fallback.sh`, `sh tests/service-opt-disappearance.sh`, `sh tests/rc-restart-stop-failure.sh`, and `sh tests/local-cache-serialization.sh` pass.
- [x] Refresh manager digests and run host/BusyBox syntax checks.

---

### Completion record

Implemented in 8ada69b. Both monitor exits propagate stop failure; parent checks daemon, handoff, resolver and remembered main/SDN requirements. Missing-/opt, unrelated DNS owner, old-ash inherited inventory, forced/repeated shutdown and updated adaptive/dispatcher fixtures pass. One bounded recovery retains failure status. Combined canonical validation and hosted checks are tracked separately in TASK-017; hardware acceptance remains TASK-018.

## TASK-015: Serialize every fallback service operation

**Priority:** P1 | **Tags:** lifecycle, concurrency, locks
**Dependencies:** TASK-014
**Estimated scope:** Small, four files

### Plan

- Modify `AdGuardHome.sh:799` (`adguardhome_run_mkdir`) and only its necessary owner/cleanup/status helpers.
- Create proposed `tests/service-lock-serialization.sh`.
- Refresh both manager checksum sidecars.

**Interfaces:** Consume `adguardhome_run_mkdir ACTION`, `adguardhome_run_execute ACTION PID_FILE OWNER`, and TASK-014's safe path contract. Preserve operation status propagation.

**Recommended contention policy:** Return existing nonzero busy status for every action that cannot acquire the mkdir lock, including stop. A bounded-wait policy is an alternative that must specify its budget before implementation; neither policy permits overlapping operations.

**Minimum correction:** Remove unconditional stop bypass and completed-metadata-as-acquisition rules. Require atomic ownership acquisition for each operation, retain ownership until it finishes, and allow only that owner to remove its lock. Recover abandoned state using existing validated PID/start-time patterns; do not delete a live or unverified holder's directory.

### Acceptance criteria

- [x] With absent and descriptor-incapable flock, startup and stop never overlap; stop cannot report success before an in-flight startup later launches the daemon.
- [x] Two contenders observing completed metadata admit at most one action; duplicate cleanup helpers cannot remove another action's lock or metadata.
- [x] Live-holder, stale-holder, PID-reuse and interrupted-owner fixtures preserve safe ownership and meaningful nonzero failure; the flock path remains serialized.

### Verification

- [x] Baseline `sh tests/service-lock-serialization.sh` (proposed) fails on recorded start/stop overlap; repaired code passes.
- [x] Run the new fixture with both backend selections, `sh tests/installer-service-lock-fd.sh`, `sh tests/local-cache-serialization.sh`, and `sh tests/start-adguardhome-lifecycle.sh`.
- [x] Refresh manager digests and run host/BusyBox syntax checks.

---

### Completion record

Implemented in a9bc559. Absent/incapable/descriptor backends, immediate-busy fallback stop, PID reuse, successor cleanup, legacy0644 upgrade, failed owner writing and SIGKILL publication/cleanup/reaper/writer cases pass real-helper fixtures. Existing proc claim callers keep their default behavior. Combined canonical validation and hosted checks are tracked separately in TASK-017; hardware acceptance remains TASK-018.

## TASK-014: Prevent unsafe reuse of service-lock and probe paths

**Priority:** P1 | **Tags:** security, locks, file-integrity
**Dependencies:** None
**Estimated scope:** Medium, up to five files

### Plan

- Modify `AdGuardHome.sh:710` through the service-lock/probe helpers, especially truncating opens at lines 725/756 and probe creation at 823/824.
- Extend `tests/runtime-writable-path-security.sh`; create proposed `tests/service-lock-path-safety.sh` if needed to isolate nonprivileged file-integrity cases.
- Refresh `AdGuardHome.sh.md5sum` and `AdGuardHome.sh.sha256sum`.

**Interfaces:** Preserve `adguardhome_run ACTION`, `adguardhome_run_flock ACTION`, `adguardhome_run_flock_active`, and `flock_supports_fd`. Lock/probe creation must not follow or truncate a foreign filesystem object.

**Minimum correction:** Reuse existing private-directory owner/mode/type validation and exclusive-creation patterns. Keep a stable descriptor lock inode in a private runtime directory across contenders; isolate capability probes there. Reject foreign-owned directories, symlinks and special files; validate service metadata as well as descriptor paths. Handle legacy active locks conservatively without deleting or replacing a lock a live holder may own. A failed capability probe must still allow the safe mkdir fallback.

### Acceptance criteria

- [x] Symlink targets, foreign regular files, foreign-owned directories, FIFOs and dangling links retain contents, permissions and identity after activity checks, start/stop attempts and capability probes.
- [x] Privileged validation verifies foreign UID fixtures; the same-UID symlink fixture proves no target truncation without needing a router.
- [x] Concurrent descriptor users share one lock inode; compatibility fallback still works when flock is absent or cannot lock file descriptors.

### Verification

- [x] Baseline `sh tests/service-lock-path-safety.sh` (proposed) demonstrates target truncation; fixed code passes.
- [x] Run `sh tests/runtime-writable-path-security.sh` as UID 0 on an isolated host, including real foreign-owner cases; run `sh tests/installer-service-lock-fd.sh` and affected Local Cache/process-lock fixtures.
- [x] Refresh manager digests and run host/BusyBox syntax checks. Record firmware symlink protection and local-user reachability before assigning security severity; do not describe the issue as remotely exploitable.

---

### Completion record

Implemented in a9bc559. Private runtime paths, exclusive probes and persistent descriptor inode pass root Docker foreign-UID, symlink, hard-link, special-file and metadata checks under sh, BusyBox 1.37 and the 1.25.1 ash harness. Firmware-specific privilege severity remains unassigned. Combined canonical validation and hosted checks are tracked separately in TASK-017; hardware acceptance remains TASK-018.

## TASK-013: Diagnose and repair malformed managed hooks accurately

**Priority:** P1 | **Tags:** doctor, hooks, recovery
**Dependencies:** TASK-012
**Estimated scope:** Small, four or five files

### Plan

- Modify `installer:3490` (`doctor_managed_script_state`), `doctor_fix_permissions:3527`, and doctor hook enumeration at `installer:3662`.
- Extend proposed `tests/installer-managed-hook-invariants.sh`; extend `tests/installer-doctor-fix-safety.sh` only where needed.
- Refresh both installer checksum sidecars.

**Interfaces:** Consume existing `doctor [--fix]`, `doctor_managed_script_state SCRIPT_PATH OP`, topology configuration, and TASK-012's hook invariants. Preserve current diagnostic severity/exit conventions except that an invalid header must never be described as healthy.

**Minimum correction:** Validate header/interpreter, intended owned invocation, file type and execute permission together. Repair an already-present, recognized installer-managed malformed header and final mode using the same invariant as generation. Include supported `dnsmasq-sdn.postconf` and managed `service-event-end` content using the latter's command-hook format, rather than the manager-call matcher. Determine applicable checks from persisted integration/capability/topology state; absent intentionally disabled hooks must not be recreated or reported as required.

### Acceptance criteria

- [x] Executable shebangless, non-executable, missing-call, and duplicate owned-hook fixtures never produce a false OK; a repaired managed malformed hook passes the invariant check.
- [x] SDN checks apply only with enabled dnsmasq integration and mtlancfg capability; disabled integration and intentionally absent LAN firewall hooks remain respected.
- [x] Read-only doctor performs no edits; --fix preserves unrelated content, rejects symlink targets, reports repair failures, and does not restart services or change DNS/firewall/NVRAM.

### Verification

- [x] The new doctor cases in `sh tests/installer-managed-hook-invariants.sh` fail on baseline false-OK behavior, then pass after repair.
- [x] `sh tests/installer-doctor-fix-safety.sh` and `sh tests/installer-doctor-rollback-result.sh` pass.
- [x] Refresh installer digests and run host/BusyBox syntax checks.

---

### Completion record

Implemented in d783705. Doctor catches malformed owned calls and repairs recognized hooks without changing DNS/firewall/NVRAM. Main/SDN/service-event gating, unsafe targets, active claims and stable legacy descriptor inode preservation pass focused checks. Combined canonical validation and hosted checks are tracked separately in TASK-017; hardware acceptance remains TASK-018.

## TASK-012: Preserve executable hook invariants through legacy migration

**Priority:** P0 | **Tags:** dns, hooks, upgrade
**Dependencies:** None
**Estimated scope:** Small, four files

### Plan

- Modify `installer:9465` (`write_manager_script`) and only the necessary interaction with `del_jffs_script:6771`.
- Create proposed `tests/installer-managed-hook-invariants.sh`.
- Refresh `installer.md5sum` and `installer.sha256sum` after implementation.

**Interfaces:** Consume existing `write_manager_script TARG OP` and `del_jffs_script TARG FILTER`. Preserve status 0/1 conventions and existing `dnsmasq pre_start` dispatcher contract. Successful generation must produce a complete executable hook, not merely a successful append.

**Minimum correction:** Perform legacy cleanup before final creation/header normalization. If cleanup removes the file, recreate its header before appending the managed call. Repair an installer-produced blank or missing first-line header, preserve an existing valid interpreter and unrelated commands, and apply/verify final 0755 mode after all content operations. Propagate write/chmod/validation failures into existing aggregate restoration; retain restoration evidence if rollback fails. Do not change generic uninstall cleanup's ability to remove installer-only hooks.

### Acceptance criteria

- [x] Real writer succeeds for absent, empty, legacy-only, and previously broken 0600/shebangless files; generated hooks have `#!/bin/sh` on line 1, exactly one intended managed invocation, and final 0755 mode under umasks 077 and 022.
- [x] Repeated install/repair is idempotent; shared custom commands and a valid existing interpreter line are preserved; applicable main/SDN hook policy is unchanged.
- [x] Injected cleanup, append, chmod, and publication failure returns nonzero and restores the original content/mode through the real transaction path.

### Verification

- [x] Baseline: `sh tests/installer-managed-hook-invariants.sh` (proposed) fails specifically on legacy-only migration's blank header/non-executable mode.
- [x] After repair: the same test passes; `sh tests/installer-legacy-hook-cleanup.sh`, `sh tests/installer-event-script-modes.sh`, and `sh tests/installer-event-script-transactions.sh` pass.
- [x] `sh tools/update-checksums.sh installer`; `sh -n installer`; BusyBox ash syntax and focused fixtures pass on the supported validation host.

---

### Completion record

Implemented in d783705. Real-hook migration, shared-content, final interpreter/mode, rollback and interruption fixtures pass under root Docker sh/BusyBox and the BusyBox 1.25.1 ash harness. Both installer manifests refreshed. Combined canonical validation and hosted checks are tracked separately in TASK-017; hardware acceptance remains TASK-018.

## TASK-011: Plan the v2.6.7 repair release

**Priority:** P0 | **Tags:** planning, dns, reliability

### Checkpoint

- Reviewed clean runtime HEAD 85b926b, v2.6.5/v2.6.6 issue and PR history, canonical AGENTS.md, existing TaskPlanner state, relevant source and nearest tests.
- Reproduced the reported legacy-only dnsmasq hook migration defect with actual installer functions: successful generation produces an empty first line and mode 0600 under the installer umask. Reinstall restores 0755 but leaves the malformed header, which doctor falsely marks healthy.
- Independent isolated actual-function proofs reproduced fallback start/stop overlap and successful monitor/parent stop status despite failed daemon/DNS cleanup. Reproduced symlink target truncation through service-lock activity checks and descriptor capability probes; any local privilege impact remains conditional on router /tmp access and symlink protection.
- Four existing hook/doctor regressions passed under host sh. BusyBox, ShellCheck and physical-router validation were unavailable; no exhaustive security audit or affected-router exploit was claimed.
- Recorded TASK-012 through TASK-018 in Next with file responsibilities, interface contracts, acceptance criteria, focused commands, dependencies, rollback constraints, checksum/CI gates, and a recommended 48-hour router soak. Immediate busy versus bounded waiting for contended fallback stop is an explicit implementation decision; hardware coverage requires operator assignment.
- Planning metadata only changed. Runtime code, checksums, version, releases and external GitHub objects remain unchanged. No commit, push, merge or publication was performed.

---

## TASK-010: Deep review PR 1030 and finalize readiness

**Priority:** P1 | **Tags:** dns, lifecycle, review

### Checkpoint

- Six independent reviews covered the complete PR diff and nearest process-identity, DNS handoff/recovery, Local Cache, lock/security, installer/policy/documentation/CI, and regression paths. Only concrete reproduced findings were changed.
- Separate commits correct SDN disablement during handoff, older BusyBox/libc hosts-file bypass of the cache probe, and missing daemon/DNS restoration after forced monitor termination. New regressions fail against the preceding implementations; focused BusyBox ash checks and independent lifecycle reviews pass.
- The complete root Docker quality suite passes for the three fixes. Concurrent CodeRabbit helper comments were merged without changing executable lines in its 16 edited shell files; combined BusyBox syntax, ShellCheck, formatting, focused regressions and all eight runtime checksums pass. Preserved CodeRabbit's TASK-009 and assigned this review TASK-010.
- Release notes and validation guidance are updated. Current-head hosted checks and review status are recorded on PR #1030. No formal Codex Security server scan was available in this session; the independent source review includes the changed security and ownership paths.
- Hardware validation remains skipped as requested. Master is unchanged and the user retains PR merge ownership.

---

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
