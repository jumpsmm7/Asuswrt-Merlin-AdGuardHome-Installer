# Next

## TASK-003: Identify managed main and SDN dnsmasq instances
**Priority:** P1 | **Tags:** dns, lifecycle

Part 3 of the six-part implementation. Keep changes off master; commit and validate separately.

### Plan

- Verify process identity and managed configuration paths; enumerate conflicting listeners; test multiple SDN PIDs and unknown owners.

---

## TASK-004: Coordinate DNS handoff and recovery
**Priority:** P1 | **Tags:** dns, lifecycle

Part 4 of the six-part implementation. Keep changes off master; commit and validate separately.

### Plan

- Stop managed instances; verify release; restore main and SDN DNS/DHCP after startup or failure; test bounded recovery.

---

## TASK-005: Defer Local Cache until DNS readiness
**Priority:** P1 | **Tags:** dns, lifecycle

Part 5 of the six-part implementation. Keep changes off master; commit and validate separately.

### Plan

- Keep saved preference; move resolver changes behind service readiness; restore on stop/failure; test lifecycle and switch failures.

---

## TASK-006: Validate integration and prepare release documentation
**Priority:** P1 | **Tags:** dns, lifecycle

Part 6 of the six-part implementation. Keep changes off master; commit and validate separately.

### Plan

- Run combined regressions and syntax/checksum checks; document router acceptance matrix and outstanding hardware checks.

---
