# Next

## v2.6.7 repair-only implementation plan

**Baseline:** `85b926b4b32fcab4f48d038b6ab6281f23d3df70` on the existing `work` checkout; installer identifies itself as v2.6.6. Plan recorded October 7, 2026 (America/New_York).

**Goal:** Repair reproducible hook, service-lock, and shutdown failures, then validate the reported DNS/DHCP outage on supported firmware.

**Architecture:** Keep the existing installer transactions and service entry points. Repair their content, ownership, serialization, and shutdown postconditions with narrowly scoped POSIX shell changes. Preserve BusyBox 1.25.1, fixed stock-first runtime PATH, topology gating, explicit DNS cleanup preferences, user hook commands, and aggregate rollback.

**Scope:** No new features or broad refactors. Future implementation should use an isolated repair branch and one independently verified commit per task. This record authorizes planning only; no runtime code, release version, GitHub issue, PR, or publication was changed.

**Evidence:** Legacy hook-only migration deletes the chmodded file and recreates it without a shebang at mode 0600 under umask 077. Reinstall changes mode but leaves the malformed header, which doctor falsely accepts. Additional isolated actual-function fixtures reproduce mkdir start/stop overlap, suppressed monitor shutdown failure, and predictable lock/probe symlink target truncation. The latter's local privilege impact depends on unprivileged /tmp access and firmware symlink protection; no remote exploit or affected-router exploit was established.

**Task order:** TASK-012 -> TASK-013 for installer changes; TASK-014 -> TASK-015 -> TASK-016 for manager changes. The two tracks can proceed independently after interfaces are agreed. TASK-017 depends on all five repairs; TASK-018 depends on TASK-017 and hardware acceptance. Run each focused fixture against the unchanged baseline first, implement only the failure it proves, rerun it and nearest affected regressions, refresh the touched distributed script's two digests, then commit the passing slice.

---

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

- [ ] Real writer succeeds for absent, empty, legacy-only, and previously broken 0600/shebangless files; generated hooks have `#!/bin/sh` on line 1, exactly one intended managed invocation, and final 0755 mode under umasks 077 and 022.
- [ ] Repeated install/repair is idempotent; shared custom commands and a valid existing interpreter line are preserved; applicable main/SDN hook policy is unchanged.
- [ ] Injected cleanup, append, chmod, and publication failure returns nonzero and restores the original content/mode through the real transaction path.

### Verification

- [ ] Baseline: `sh tests/installer-managed-hook-invariants.sh` (proposed) fails specifically on legacy-only migration's blank header/non-executable mode.
- [ ] After repair: the same test passes; `sh tests/installer-legacy-hook-cleanup.sh`, `sh tests/installer-event-script-modes.sh`, and `sh tests/installer-event-script-transactions.sh` pass.
- [ ] `sh tools/update-checksums.sh installer`; `sh -n installer`; BusyBox ash syntax and focused fixtures pass on the supported validation host.

---

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

- [ ] Executable shebangless, non-executable, missing-call, and duplicate owned-hook fixtures never produce a false OK; a repaired managed malformed hook passes the invariant check.
- [ ] SDN checks apply only with enabled dnsmasq integration and mtlancfg capability; disabled integration and intentionally absent LAN firewall hooks remain respected.
- [ ] Read-only doctor performs no edits; --fix preserves unrelated content, rejects symlink targets, reports repair failures, and does not restart services or change DNS/firewall/NVRAM.

### Verification

- [ ] The new doctor cases in `sh tests/installer-managed-hook-invariants.sh` fail on baseline false-OK behavior, then pass after repair.
- [ ] `sh tests/installer-doctor-fix-safety.sh` and `sh tests/installer-doctor-rollback-result.sh` pass.
- [ ] Refresh installer digests and run host/BusyBox syntax checks.

---

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

- [ ] Symlink targets, foreign regular files, foreign-owned directories, FIFOs and dangling links retain contents, permissions and identity after activity checks, start/stop attempts and capability probes.
- [ ] Privileged validation verifies foreign UID fixtures; the same-UID symlink fixture proves no target truncation without needing a router.
- [ ] Concurrent descriptor users share one lock inode; compatibility fallback still works when flock is absent or cannot lock file descriptors.

### Verification

- [ ] Baseline `sh tests/service-lock-path-safety.sh` (proposed) demonstrates target truncation; fixed code passes.
- [ ] Run `sh tests/runtime-writable-path-security.sh` as UID 0 on an isolated host, including real foreign-owner cases; run `sh tests/installer-service-lock-fd.sh` and affected Local Cache/process-lock fixtures.
- [ ] Refresh manager digests and run host/BusyBox syntax checks. Record firmware symlink protection and local-user reachability before assigning security severity; do not describe the issue as remotely exploitable.

---

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

- [ ] With absent and descriptor-incapable flock, startup and stop never overlap; stop cannot report success before an in-flight startup later launches the daemon.
- [ ] Two contenders observing completed metadata admit at most one action; duplicate cleanup helpers cannot remove another action's lock or metadata.
- [ ] Live-holder, stale-holder, PID-reuse and interrupted-owner fixtures preserve safe ownership and meaningful nonzero failure; the flock path remains serialized.

### Verification

- [ ] Baseline `sh tests/service-lock-serialization.sh` (proposed) fails on recorded start/stop overlap; repaired code passes.
- [ ] Run the new fixture with both backend selections, `sh tests/installer-service-lock-fd.sh`, `sh tests/local-cache-serialization.sh`, and `sh tests/start-adguardhome-lifecycle.sh`.
- [ ] Refresh manager digests and run host/BusyBox syntax checks.

---

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

- [ ] Successful stop requires the daemon absent, installer handoff state cleared, native resolver routing restored, and required main/SDN DNS recovered.
- [ ] Resolver-unmount failure, surviving daemon, dnsmasq restart/readiness failure, and stale handoff state return nonzero instead of successful monitor disappearance.
- [ ] Both monitor stop branches, multiple monitors, forced termination, missing /opt, repeated stop and intentionally unmanaged LAN/AP are covered without respawn or unintended DNS restart.

### Verification

- [ ] Baseline focused additions to `sh tests/stop-adguardhome-failure.sh` reproduce direct stop failure with false successful parent/monitor status; fixed cases pass.
- [ ] `sh tests/monitor-stop-config-fallback.sh`, `sh tests/service-opt-disappearance.sh`, `sh tests/rc-restart-stop-failure.sh`, and `sh tests/local-cache-serialization.sh` pass.
- [ ] Refresh manager digests and run host/BusyBox syntax checks.

---

## TASK-017: Run the new failure cases in canonical CI

**Priority:** P1 | **Tags:** validation, ci
**Dependencies:** TASK-012, TASK-013, TASK-014, TASK-015, TASK-016
**Estimated scope:** Medium, up to four files

### Plan

- Modify `tools/code-quality.sh` and `.github/workflows/shell-validation.yml` to execute all new fixtures under the appropriate shell/UID.
- Update `tests/fixtures/service-lifecycle-cases.tsv` and `tests/fixtures/service-lifecycle-coverage.tsv` only for independently covered integration scenarios.
- Keep regression paths and time limits aligned; do not loosen assertions or mask environment failures to obtain green results.

### Acceptance criteria

- [ ] Canonical validation actually executes real-helper legacy migration, doctor malformed-hook, lock-path, contention, and graceful-stop failure cases.
- [ ] Host sh and BusyBox ash checks pass; security tests execute in an isolated UID-0 host with foreign-UID cases; target BusyBox 1.25.1 behavior is verified or explicitly pending.
- [ ] Full lifecycle integration, lint, formatting and artifact checksums pass against the final combined source, with current-head hosted review/check evidence.

### Verification

- [ ] Run `sh tools/code-quality.sh` in the documented isolated validation host with declared prerequisites.
- [ ] Run `sh tests/service-lifecycle-integration.sh`; for BusyBox use `AGH_INTEGRATION_SHELL=busybox AGH_INTEGRATION_SHELL_ARG=ash sh tests/service-lifecycle-integration.sh`.
- [ ] Run `sh tools/check-md5.sh`, `sh tools/check-sha256.sh`, `sh tools/check-release-consistency.sh`, workflow lint and `git diff --check`.
- [ ] The combined passing result is a software validation gate; it is not evidence of ASUS firmware dispatch, DHCP leases or overnight physical-router behavior.

---

## TASK-018: Validate physical-router recovery and package v2.6.7

**Priority:** P1 | **Tags:** release, hardware, dns
**Dependencies:** TASK-017
**Estimated scope:** Medium, five files

### Plan

- Create proposed `RELEASE-2.6.7-CHECKLIST.md` from the applicable requirements of the existing v2.6.5 checklist and DNS lifecycle validation document.
- Update `README.md` with the new checklist and accurately scoped repair notes.
- After software/hardware acceptance, modify only installer banner and `AI_VERSION` to v2.6.7 and refresh `installer.md5sum`/`installer.sha256sum`.
- Keep upstream AGH channels and archive refreshes outside this repair release unless independently required to fix a proven defect.

### Acceptance criteria

- [ ] Fresh install, legacy v2.6.0-or-earlier upgrade, v2.6.5 upgrade, and v2.6.6 upgrade repair hooks and preserve user settings; no duplicate hooks, cron jobs or firewall rules. Use test hardware in a maintenance window.
- [ ] Firmware-dispatched DNS restart, cold boot, AGH restart/failure, DHCP new lease/renewal/expiry, main/SDN local A/PTR resolution, guest isolation, cache on/off, supported IPv6, slow filter startup and interrupted upgrade/uninstall recover correctly. Validate from a client on each network and verify both TCP/UDP listeners: AGH 53 with managed dnsmasq 553 while running; native DNS after required recovery.
- [ ] Recommended soak: at least two overnight maintenance periods (48 hours) with actual scheduled events recorded; include the originally affected model/firmware when available. Capture sanitized listener/PID ownership, hook first lines/modes, relevant event logs and lease outcomes before/after; verify intended WAN IPv4/IPv6 TCP/UDP DNS exposure. Mandatory unrun or failing hardware rows block the claim that the reported outage is resolved.
- [ ] Version/banner/manifests agree, all current-head required checks pass, and release notes distinguish demonstrated repairs from unverified firmware cases. No automatic merge/publication is part of this task plan.

### Verification

- [ ] Record model, supported firmware, architecture, actual BusyBox version, topology, enabled SDNs, initial installer and AGH channel, cache setting, event timestamps and PASS/FAIL/BLOCKED/N/A for every applicable row.
- [ ] Run `sh tools/update-checksums.sh installer`, all checksum/release-consistency checks, and affected targeted checks after the version change.
- [ ] Preserve rollback evidence and pre-upgrade recovery paths; do not repeat the destructive whole-file workaround on shared hooks.

### Decisions to settle before implementation

- [ ] Confirm TASK-015's recommended immediate busy status for a contended fallback stop, or select an existing bounded wait budget; acquisition and no-overlap requirements are fixed either way.
- [ ] Assign physical-router coverage and maintenance windows before treating TASK-018 hardware rows as executable. No dates or operators were invented.

---

### Planning verification record

- Four existing hook/doctor regressions passed under host sh: event-script modes, event-script transactions, doctor fix safety, and legacy hook cleanup.
- Independent actual-function scratch proofs reproduced malformed hook generation/reinstall/doctor false OK, fallback start/stop overlap, monitor shutdown failure suppression, and lock/probe symlink target truncation.
- BusyBox and ShellCheck were unavailable in this planning host. Physical router and firmware behavior were not exercised.
- Historical #735 slow-startup and #252/#253 firewall/DNS Director reports are regression inputs, not newly confirmed v2.6.6 defects.
- No current source fix, exhaustive vulnerability scan, remote exploitation, security advisory, issue reopening, or release was claimed.

Sources: [reported DHCP regression #1029](https://github.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/issues/1029), [v2.6.6 repair PR #1030](https://github.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/pull/1030), [virtual acceptance and firmware limitations](https://github.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/pull/1030#issuecomment-6022881933).
