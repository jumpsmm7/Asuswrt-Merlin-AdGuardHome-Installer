# Next

## v2.6.7 repair-only implementation plan

**Baseline:** `85b926b4b32fcab4f48d038b6ab6281f23d3df70` on the existing `work` checkout; installer identifies itself as v2.6.6. Plan recorded October 7, 2026 (America/New_York).

**Goal:** Repair reproducible hook, service-lock, and shutdown failures, then validate the reported DNS/DHCP outage on supported firmware.

**Architecture:** Keep the existing installer transactions and service entry points. Repair their content, ownership, serialization, and shutdown postconditions with narrowly scoped POSIX shell changes. Preserve BusyBox 1.25.1, fixed stock-first runtime PATH, topology gating, explicit DNS cleanup preferences, user hook commands, and aggregate rollback.

**Scope:** No new features or broad refactors. The user authorized repository implementation on October 8, 2026. Work proceeds on fix/v2.6.7-repairs with independently verified commits. Preparing the v2.6.7 software candidate is authorized; publication and claims of physical-router recovery remain gated on recorded hardware results.

**Evidence:** Legacy hook-only migration deletes the chmodded file and recreates it without a shebang at mode 0600 under umask 077. Reinstall changes mode but leaves the malformed header, which doctor falsely accepts. Additional isolated actual-function fixtures reproduce mkdir start/stop overlap, suppressed monitor shutdown failure, and predictable lock/probe symlink target truncation. The latter's local privilege impact depends on unprivileged /tmp access and firmware symlink protection; no remote exploit or affected-router exploit was established.

**Task order:** TASK-012 -> TASK-013 for installer changes; TASK-014 -> TASK-015 -> TASK-016 for manager changes. The two tracks can proceed independently after interfaces are agreed. TASK-017 depends on all five repairs; TASK-018 depends on TASK-017 and hardware acceptance. Run each focused fixture against the unchanged baseline first, implement only the failure it proves, rerun it and nearest affected regressions, refresh the touched distributed script's two digests, then commit the passing slice.

---
