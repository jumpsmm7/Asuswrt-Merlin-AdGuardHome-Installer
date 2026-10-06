# Work Log

- TASK-001: Established branch and root-mapped baseline; documented expected behavior and router-only release checks.
- TASK-002: Safe missing-policy defaults and explicit CLI/user-choice regressions pass.
- TASK-003: Read-only managed detection tests pass under BusyBox ash: main and multiple SDN PIDs, alternate display names, duplicate sockets, unknown/stale PIDs, unsupported firmware, foreign configs, scoped listeners and symlinks. Runtime syntax passes.
- TASK-004: Managed owner escalation revalidates PID/config identity; replacement main and SDN listeners are checked with bounded retries. Multi-SDN lifecycle, existing handoff, WAN/LAN lifecycle, netstat, dnsmasq publication and permission tests pass under BusyBox 1.30. Firmware ALL_SDN dispatch documented; hardware checks remain pending.
- TASK-005: Local Cache resolver bind removed from postconf; startup and monitor apply only after AGH loopback and all enabled SDN/main readiness. Cleanup runs before start, shutdown and failure. Cache race/failure/idempotence, handoff, publication, stop, monitor and preference regressions pass under BusyBox 1.30.
- TASK-006: 41 relevant regressions pass; 157 BusyBox ash syntax checks and complete artifact MD5/SHA-256 verification pass. New tests added to CI; recovery ordering corrected; release notes and acceptance matrix documented. Hardware testing explicitly skipped by user and remains unverified.
