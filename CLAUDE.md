<!-- TASKPLANNER:START -->
## TaskPlanner workflow

Track tasks in `.tasks/` using `.tasks/config.json`. Select Next before Backlog, move selected work to In Progress, and record a plan before coding. After verification, summarize results and move the task to Done. Preserve task IDs and unrelated content. Record completion in `.tasks/WORK_LOG.md`.
<!-- TASKPLANNER:END -->

Read [AGENTS.md](AGENTS.md) as the canonical engineering and review guardrails before changing or reviewing code. Its [ARM virtual validation](AGENTS.md#arm-virtual-validation) section and [virtual testing guide](docs/virtual-arm-testing.md) define the shared host checks, package/CPU identities and feature-scoped native acceptance rules. Preserve the distinction between validation-host tooling and router runtime, and between modeled firmware behavior and native guest assertions.
