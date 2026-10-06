# In Progress

## TASK-005: Defer Local Cache until DNS readiness
**Priority:** P1 | **Tags:** dns, lifecycle

Part 5 of the six-part implementation. Keep changes off master; commit and validate separately.

### Plan

- Keep saved preference; move resolver changes behind service readiness; restore on stop/failure; test lifecycle and switch failures.

---
