# Lovable repository handoff support

This repository supplies a portable
[router-lovable-handoff skill](../.agents/skills/router-lovable-handoff/SKILL.md)
and a [version-1 JSON handoff schema](lovable-handoff.schema.json). They let a
Lovable assistant analyze this repository's supplied evidence while following
[AGENTS.md](../AGENTS.md) and the [shared integration guide](agent-integrations.md).
This change configures repository support only. It creates no Lovable project,
workspace skill, connector, database or deployment and makes no account changes.

## Keep one source of authority

Use `.tasks/` for task state, GitHub for PR/review/check state, and the existing
Qodo resolver for Qodo findings. Name one publishing writer and one review
observer in each handoff. Lovable's analysis goes back to those owners; it does
not create another task ledger or prove a review finding valid by itself.

Identify the exact source commit, policy bytes and SHA-256, authorized goal,
existing task reference, evidence source, selected scope and unknowns. Before
analysis, verify that policy and optional guide URLs name the source commit and
that the exact UTF-8 policy bytes match its digest. Supplied policy text must
retain the original final newline. Schema validation checks shape and limits;
it cannot authenticate source identity, match hashes, compare commit fields,
redact sensitive prose, establish authorization, or verify a reported pass.

Record advisory analysis, host checks, native ARM execution, modeled firmware,
operator physical reports and review snapshots separately. The native feature
gate still requires matching complete armv5/armv7/armv8 reports for the selected
scope and tested content. The armv5 package label represents an older
RT-AC68U-class ARMv7 Cortex-A9 software-float guest with VFP and NEON disabled.
Passing covered virtual contracts remains distinct from physical release
acceptance. Historical reports, missing results and assistant summaries cannot
substitute for fresh evidence required by changed tested inputs.

## Use a handoff packet

The example below illustrates an unverified baseline handoff. Its source is the
actual master merge commit from PR #1033 and its policy digest is the digest of
`AGENTS.md` at that commit. It records **no test pass** and assigns no new task.
The shared integration guide was not present at that baseline, so `guide_url`
is omitted and the limitation is explicit. For real work, replace the source
and ownership with the current candidate and existing task; receiving agents
must recheck the current published head and policy.

```json
{
  "schema_version": 1,
  "repository": "https://github.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer",
  "source": {
    "commit_sha": "047ce167685f6de8db86519557b865e9f23e98f3",
    "branch": "master",
    "policy": {
      "url": "https://github.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/blob/047ce167685f6de8db86519557b865e9f23e98f3/AGENTS.md",
      "sha256": "b488b24f1baf1b615161571d7b0437ad2631d61665dc9f3c5722567971f8a225"
    }
  },
  "goal": "Illustrate an advisory handoff; infer no current test or release result.",
  "task_ref": null,
  "owner": {"writer": "Designated repository writer", "observer": "Designated PR observer"},
  "evidence": [],
  "unknowns": [
    "Policy has not been retrieved and independently verified for this illustrative handoff.",
    "The shared integration guide is absent at the historical source commit.",
    "Current candidate, check state and task ownership are not supplied."
  ],
  "database_references": []
}
```

An evidence record names its kind, status, provenance, scope, source commit and
reference. `pass` requires a timestamp and reference; host/native/modeled/review
passes also require a source commit, and native passes require content/builder
digests and architecture labels. A single-architecture diagnostic pass is not
aggregate acceptance. Physical source commits may remain unknown when the
operator did not report them. Advisory analysis cannot be recorded as a pass.
Keep an unavailable result unknown, pending or skipped with the actual reason.

The schema follows JSON Schema Draft 2020-12. Validate it and packets with a
validator supporting that draft; enable format assertions to check timestamps.
It is a documentation contract, with no exporter or added runtime dependency.

## Optional future Lovable setup

After a separate setup task identifies an authorized workspace/project, a
workspace owner or admin can import the standalone skill from its public GitHub
directory or create it through Lovable's skill tools. In Lovable, choose
**Workspace settings → Skills → Add → Import from GitHub** and use:

```text
https://github.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/tree/chore/shared-agent-integrations/.agents/skills/router-lovable-handoff
```

After this PR merges, replace the branch with `master`; pin a full published
commit instead when reproducibility is required. Invoke `/router-lovable-handoff`
with a verified packet in the selected project chat. This is a manual future
setup path, not an installation performed by this PR. Its repository-specific
trigger protects unrelated apps. Supply the current policy packet rather than
expecting repository-relative links to resolve in the workspace skill. Read
existing project/workspace knowledge before changing it; prefer project-scoped
context so router rules do not affect unrelated projects. Knowledge replacement
and skill installation are separate account mutations.
[Lovable skills](https://docs.lovable.dev/features/skills) and
[knowledge](https://docs.lovable.dev/features/knowledge) document these mechanisms.

Lovable Git sync exports a Lovable project to a new GitHub repository; it cannot
import this existing installer repository. A separately configured GitHub API
connector can supply repository files and PR context in project chat. Use
explicit read-only, exact-head lookups or a supplied packet rather than adding
hosted polling. The connector is added through the Lovable dashboard; repository
files alone do not install it. See [Git sync](https://docs.lovable.dev/integrations/github)
and [GitHub API access](https://docs.lovable.dev/integrations/github-api).

A selected project agent can use plan mode for advisory assistance. Its output
still needs repository verification. Lovable's native subagents are temporary,
read-only investigations; they do not register Qodo, CodeRabbit or other agents.
Cross-project referencing is read-only, permission-bound and within one workspace.
See [subagents](https://docs.lovable.dev/features/subagents) and
[cross-project context](https://docs.lovable.dev/features/cross-project-referencing).

## User-owned database references

`database_references` is optional and may be empty. When a separately authorized
task supplies a user-owned Lovable Cloud/Supabase store, use a non-sensitive
project alias, provider, ownership, metadata-only scope, actual availability,
and optional schema references. Metadata is context, not a connection or query
request. Account ownership alone does not authorize importing every app's data.
Review sharing permissions and prose before publishing a packet; keep private
account identifiers, credentials, DSNs and raw database records out of the PR.

The callable database tools concern the project's own database. They expose no
private training database belonging to a model or outside review service.
Lovable's AI gateway supports in-app assistants over supplied content separately
from its coding agent. Creating an app, enabling a database, querying records,
writing migrations or adding a model requires its own scoped setup task; this
contract performs none of those actions. A subscription entitlement is not
evidence of unlimited Cloud/AI usage. See [project databases](https://docs.lovable.dev/features/database)
and [AI features](https://docs.lovable.dev/features/ai).
