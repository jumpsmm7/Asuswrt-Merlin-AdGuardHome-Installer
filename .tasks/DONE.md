# Done

Completion records below are dated snapshots. Current v2.6.7 physical acceptance is recorded in [the acceptance checklist](../RELEASE-2.6.7-CHECKLIST.md); earlier BLOCKED observations are retained as history.

## TASK-030: Repair installation readiness and installer source selection

**Priority:** P1 | **Tags:** v2.7.0, reliability, validation
**Dependencies:** TASK-029
**Scope:** Reproduce the incomplete JFFS preflight and saved-source reset; correct readiness diagnostics, preserve action-scoped dependency repair, retain explicit/saved source through checks/re-exec, define --no-auto-update for a coherent installer/helper bundle, and clarify early unsupported non-interactive fresh-install refusal while preserving interactive compatibility.

### Plan

- Read the accepted [v2.7.0 plan](../docs/v2.7.0-plan.md), current diff and nearest lifecycle tests.
- Implement a small evidence-backed slice in the listed surfaces; split independent corrections into reviewable commits/PRs.
- Verify the focused regression, appropriate host checks and fresh matching native scope before claiming completion. Preserve failure logs and physical boundaries.

**Likely surfaces:** installer; nearest/new readiness/source/CLI regressions; checksums; README; host/native registration

### Implementation checkpoint

Readiness/source/CLI corrections are published in PR [#1037](https://github.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/pull/1037) at `bb734a5`. All current host checks, both fresh three-architecture matrices/aggregates (121 scenarios per target, 11 groups) and the retried current Sonar analysis pass with zero unresolved issues. CodeRabbit approves with 5/5 pre-merge checks and 100% purpose coverage across 80 functions; all 15 review threads have evidence-backed resolutions. The critical certifi finding is fixed with verified hashes and a clean complete lock installation. Two OSV jobs still fail for Semgrep's exact vulnerable mcp dependency, so the PR is not all-checks-green or merge-ready. Covered virtual acceptance and physical release qualification remain separate. Earlier source-specific/interrupted evidence stays historical.

### Acceptance criteria

- [x] Failed reads cannot report JFFS OK; ready flags avoid unnecessary writes; dependency failures identify their stage. Explicit/saved refs and self-update policy persist without checksum bypasses or mismatched helpers. Interactive fresh setup remains supported; unsupported flagged setup stops before new ordinary writes/downloads, with existing recovery distinct.
- [x] Record actual verification, publication/current-head status and remaining limitations in this ledger.

### Final source verification (October 21, 2026 America/New_York)

Published source `fcd36c29bf0d1c0512592862efb14abe1e7fc0d0` has 36 completed checks: 35 success, Scorecard neutral and no pending/failing checks. All three package targets and both aggregates accept 121 scenarios per target / 11 groups at digest 8475528d2d909dfe5cf9fab7ddcee5a09ab9a03d48302fed4a7dab21e25c7faf. Both OSV full/new scans, Semgrep, Sonar and canonical host jobs pass. CodeRabbit completes with 5/5 pre-merge checks; all 16 threads resolved. These records supersede earlier checkpoints; physical v2.7.0 qualification stays separate. No release, merge or hardware action is claimed.

---

## TASK-031: Remove dnsmasq rebind and DNSSEC state during AGH takeover

**Priority:** P1 | **Tags:** v2.7.0, reliability, validation
**Dependencies:** TASK-029
**Scope:** Filter exact rebind/DNSSEC directives, companions, all trust-anchor/key entries and DNSSEC-only references from each managed main/SDN runtime config. Handle mixed/nested includes through safe runtime views, preserve persistent originals and existing per-file transactions/native regeneration.

### Plan

- Read the accepted [v2.7.0 plan](../docs/v2.7.0-plan.md), current diff and nearest lifecycle tests.
- Implement a small evidence-backed slice in the listed surfaces; split independent corrections into reviewable commits/PRs.
- Verify the focused regression, appropriate host checks and fresh matching native scope before claiming completion. Preserve failure logs and physical boundaries.

**Likely surfaces:** AdGuardHome.sh; focused dnsmasq/include/recovery tests; checksum sidecars; test manifests/docs

### Implementation checkpoint

The staged takeover filter is published in stacked PR [#1040](https://github.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/pull/1040), depending on #1037. It removes exact rebind/DNSSEC options and key/anchor entries while preserving persistent sources and unrelated settings. Combined source `c33f23a` passes the full host suite and its push ARM matrix/aggregate (122 scenarios per target, 11 groups); later review changes still require fresh matching validation. Those changes distinguish raw control bytes from quoted-space markers and bulk-copy unchanged line segments, with 20,000-line, partial-write and cleanup regressions. Exact BusyBox applet and eight nearest host checks pass. Empty-directory and option/suffix review claims were checked against actual behavior; mandatory per-source NUL checks remain. The reproduced pre-existing pending-restore backup defect is tracked separately as #1041 under TASK-033. Physical release boundaries remain unchanged.

### Acceptance criteria

- [x] All effective targeted options/keys absent at managed publication, including custom/root-rollover anchors. Includes preserve unrelated settings and valid lifetimes. Repeated/overlapping takeover, native fallback and staging/IPSET/publication failures preserve configuration/recovery invariants.
- [x] Record actual verification, publication/current-head status and remaining limitations in this ledger.

### Final source verification (October 21, 2026 America/New_York)

Published source `10f1dc6a8ac646b5957fd7dd4cdd022ae1478111` has 35 completed successful checks and no pending/failing checks. All three package targets and both aggregates accept 122 scenarios per target / 11 groups at digest 1c70021b05212b0c2632c3bfb9dfaf861bc98a3f7d2ccc3f696a4fb7190e4aec. Both OSV full/new scans, Semgrep, Sonar and canonical host jobs pass. CodeRabbit completes with 5/5 pre-merge checks; all six threads resolved. Pre-existing recovery defect #1041 is tracked separately by TASK-033. These records supersede earlier checkpoints; physical v2.7.0 qualification stays separate. No release, merge or hardware action is claimed.

---

## TASK-037: Remove the unused vulnerable MCP dependency from CI scanning

**Priority:** P1 | **Tags:** v2.7.0, security, ci
**Scope:** Resolve the OSV MCP finding on both PR #1037 and stacked PR #1040 while preserving Semgrep policy coverage and full vulnerability enforcement.

### Plan

- Verify current Semgrep constraints and the MCP advisory against primary sources; never force an incompatible Python dependency or add a vulnerability suppression.
- Validate the shipped native Semgrep CLI against the current Python frontend for all existing fixtures, every local policy scope, finding exits and SARIF. Keep its experimental native selector explicit and pin the same engine artifact with SHA-256.
- Install only the native executable, retain an OSV-readable Semgrep artifact inventory, update reporter output syntax, and verify actual workflow commands before publishing the same change to both branches.

### Acceptance criteria

- [x] Existing policy findings, scope, error exits and SARIF remain enforced without installing the Python MCP SDK. The actual workflow commands pass in an offline clean Ubuntu container with only the TLS/hash-verified native artifact transfer modeled; corrupt hashes and invalid rules refuse. All three original fixtures and 58 injected findings across 17 scoped paths match the original frontend. The pinned OSV reporter passes clean input, fails vulnerable input and emits valid SARIF without the deprecated output warning.
- [x] Both published implementation heads pass their full/new-vulnerability OSV and Semgrep jobs without waivers. Current-head CodeRabbit reviews complete with no actionable comments, 5/5 pre-merge checks and zero unresolved threads; Sonar passes. Remaining unrelated host/native runs at the recorded cutoff are delivery follow-up, not a prerequisite for this scoped dependency correction.

### Verification

At the October 21, 2026 20:18 UTC cutoff, PR #1037 implementation `a8b324cb40e8b783500dd6bbe0ba86086e78bd47` and stacked PR #1040 implementation `d88e73025b1f5bf5e5f7239de58e199fd94c5f95` each pass both full and new-vulnerability OSV jobs and both Semgrep jobs. Actual scanner logs confirm one inventoried Semgrep package and exit 0; native policy runs retain all five rules across 17 scoped files, fixture detections, finding enforcement and valid SARIF. The reporter deprecation is removed; the separate scanner-action output warning remains upstream. Current-head CodeRabbit reports no actionable comments and 5/5 pre-merge checks; all 15 readiness and five DNS threads are resolved. Sonar passes with zero new issues. Native/host delivery jobs still running at this cutoff are not represented as completed.

The task-record follow-up changes no tested input, workflow, artifact inventory, router runtime or MCP client configuration. Subsequent published-head outcomes remain in the PRs. Physical v2.7.0 qualification and later release phases remain separate.

---

## TASK-029: Establish the v2.7.0 implementation baseline

**Priority:** P1 | **Tags:** v2.7.0, planning, baseline

### Plan and acceptance

- [x] Verify current master and create an isolated implementation worktree without changing the original work checkout.
- [x] Record the approved complete scope and task IDs, preserving historical v2.6.7 and physical records.
- [x] Verify published release state and distinguish actual baseline checks from new validation.

### Verification

Master/ref `7ecacf124658cc1ec23cb6aae62622f2ace9bfd5`, tree `b130924b304ad2c9498ee4853a31eb53a7e39329`, fetched normally into isolated `feat/v2.7.0-readiness`. GitHub reports v2.6.7 published October 10, 2026 at 17:57:04 America/New_York. There are no existing open PRs at this snapshot. The archive-update master commit has one successful check; this is not a fresh full quality/native validation claim. Tasks030–036 preserve the accepted scope and upcoming evidence requirements. No runtime change, router action, release publication or new physical pass occurs in this task.

---

## TASK-028: Align shared MCP routing across agents

**Priority:** P2 | **Tags:** agents, mcp, configuration, validation
**Scope:** Existing PR #1035 onto master; source baseline `81515e81e5ec13107c8d667a549c8289e03e4e6d`. Preserve the combined Context7, Firecrawl and Lovable catalog, native client syntax and all existing task/review/test authorities.

### Plan

- Audit all registered agent entry points, portable skills and native MCP mirrors against canonical policy. Distinguish repository configuration from account authentication, effective tool availability and hosted review scopes.
- Add direct shared MCP guide routing to every registered agent entry point. Clarify CodeRabbit's dashboard authentication and Review-scope requirement, Qodo's unverified hosted external-MCP support, and the common fallback to verified repository context when an optional connection is unavailable.
- Extend the existing read-only integration checker to require those direct pointers and a safe, nonempty MCP guide; add isolated rejection and valid-fixture coverage without changing provider inventory or introducing dependencies.
- Run focused host regressions and genuine credential-free coverage, independently review the final diff, and publish normal leased updates to this PR. Obtain fresh matching native evidence for changed checker/tests and inspect published-head checks/review feedback through one observer.

### Acceptance criteria

- [x] All registered agents route to canonical policy, the shared agent guide and the shared MCP guide; Amazon Q remains byte-identical to canonical policy.
- [x] Available authorized tools and verified repository handoffs share the same finding, task-state, review ownership and feature-evidence rules; missing optional connections do not invent defects or passing external checks.
- [x] CodeRabbit and Qodo instructions accurately describe hosted activation limits without account changes or unsupported configuration fields.
- [x] Automated alignment checks and focused regressions pass; genuine coverage and fresh current-content native/hosted outcomes are recorded without weakening gates.
- [x] Existing PR #1035 is updated and current-head review/check status is verified. No merge, release, account provisioning, secrets or billing changes.

### Verification

Implemented as source `7bb3d757b713320a4ec67ea47ce0e547cda39373`, exact tree `58da394bb96caaeb62a13f3838c9d27e440bd7cc`, matching local `df8d55a24081c684b9db7d4f8d896a1516b57382`.

- All eight agent entry points now directly reference canonical policy, the shared agent guide and the MCP guide. Native server names/URLs remain synchronized; ten skills and 27 provider IDs remain intact. Amazon Q is byte-identical to canonical policy.
- The read-only checker requires direct MCP routing and a safe nonempty guide. All 60 integration regressions pass, including eight missing-pointer rejection cases and missing, empty, invalid UTF-8, symlink, directory and bounded FIFO guide rejection. Existing native formats, future adapters and no-follow/read-only controls remain covered.
- Genuine credential-free collection passes 104 tests with all six Python modules retained, zero exclusions and no warnings. Checker coverage is 353/356 lines plus 79/80 branches (99.08%); combined Python/native-C is 1976/2124 (93.03%). Full isolated UID-0/network-none canonical host quality and actionlint pass on frozen source, including privileged lifecycle checks, ShellCheck and shfmt. Independent bounded review found no actionable issue.
- The single observer's October 12, 18:49:04 UTC snapshot verifies matching published PR/ref/base and open, non-draft, mergeable, unmerged state. All 36 source checks are terminal: 35 successful and existing Scorecard neutral, no failures or pending jobs. All three full quality suites, six fresh ARM executions and both aggregates pass: 118 scenarios per architecture /354 per matrix, all 11 selected feature groups accepted. Exact-head host logs verify 60 integration tests, unchanged 8/10/27 inventory and passing DNS-environment fixture.
- Sonar verifies exact source SCM, 104 tests, quality gate PASS, strict zero unresolved issues and 98.0% new-code coverage. CodeRabbit completed this source review with no actionable comments and all five pre-merge checks passing. Complete GraphQL/REST pagination confirms zero inline comments/threads, six issue comments and two formal reviews. Formal CodeRabbit/Amazon Q reviews, Qodo's zero-findings footer and completed Codex review still identify historical `a0d3bc8`; no new-source formal approval or Qodo/Codex/Amazon Q review is claimed.
- Fresh hosted native evidence binds `30f0be165e4d0eedd1cdcb736eb6de471cc9fcb9abcd0508bec275131fcd0c03`, matching the actual normal-permission `df8d55a` Git archive. Local host validation snapshots retain digest `e51fb8325519113ef14554b6dde19bf7c188e6ccaf8ac30385a995b96d2598dc`: 43 included executable files have restricted 0700 modes. Identical tracked bytes with normal Git execute bits independently reproduce the hosted identity. These are distinct filesystem provenance records; earlier native results are not relabeled or reused. The armv5 package target remains older RT-AC68U-class ARMv7/software-float with VFP/NEON disabled; physical acceptance is unchanged.

### Completion record

Repository alignment, source verification and authorized publication are complete. This follow-up changes task records only and preserves tested inputs. Later published-head check/review outcomes are tracked in the PR description rather than pre-claimed here. Hosted account authentication, selected tools and scope activation remain separate; absent optional services do not establish repository defects or external validation. No account, credentials, billing, merge or release changes occur.

---

## TASK-027: Synchronize repository MCP clients

**Priority:** P2 | **Tags:** agents, mcp, configuration, validation
**Scope:** New PR onto master `f576f1fb6ad99120c5b7cad80926d9797e8d3a0a`, following the maintainer's request to combine and synchronize repository-scoped MCP server support across capable agents. The existing union is Context7, Firecrawl and Lovable, with the exact supplied endpoints preserved.

### Plan

- Use portable root `.mcp.json` as the canonical shared HTTP server catalog for compatible Claude/Copilot clients. Mirror the combined inventory into supported Codex, Amazon Q, Cursor and Kiro repository formats, and verify any necessary older VS Code compatibility format without duplicate assumptions.
- Preserve client-specific transport/authentication syntax, including Lovable's published public Cursor OAuth client identifier, while keeping credentials, account login and tool approval state outside committed configuration.
- Add read-only consistency validation to the existing host integration checker and focused drift/rejection coverage. Preserve unrelated existing agent policy, Qodo handling, provider IDs, task records and reviewer coordination.
- Align shared usage guidance and entry-point routing, distinguishing native file support from hosted provider dashboard/manual setup. Do not invent Qodo or CodeRabbit client configuration or modify external accounts.
- Verify the changed host checks and coverage, publish a new ready-for-review PR onto master, and inspect exact-head hosted checks, fresh native ARM acceptance and actual review feedback through one observer.

### Acceptance criteria

- [x] Each configured capable client declares the combined server names and exact canonical URLs in its supported native shape; drift, missing servers and incompatible client fields are rejected.
- [x] Clients preserve their documented authentication/trust behavior; no tokens, automatic approval, external setup, router dependency, merge or release is introduced.
- [x] Existing agent policy and Qodo/task authority remain intact; new optional Kiro routing follows the same canonical rules.
- [x] Meaningful host regressions and genuine coverage pass without exclusions or reduced thresholds. Native evidence for changed tested inputs is refreshed rather than reusing historical acceptance.
- [x] A new PR is published onto master and its current-head validation/review state is recorded accurately.

### Verification

Implemented and published as ready-for-review PR [#1035](https://github.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/pull/1035) onto master. Source head `a0d3bc82aa2ba903b46c78ddf5afe2e363c1505f`, exact tree `b96cdf2a2ec78248c07bc3a7cc729fc0f1e8bf9a`, matches frozen local commit `5ca3a31413f8d6b1a2e0a21f14912c9138090a27`.

- All 58 integration tests pass, including combined-inventory drift, native formats, public Cursor OAuth metadata, strict JSON/TOML, no-follow reads, coordinated future additions and optional `.vscode/mcp.json`/`.github/mcp.json` override rejection. Registry remains eight agent entry points, ten skills and 27 providers; Amazon Q policy remains byte-identical.
- Genuine credential-free collection passes 102 tests with all six Python modules retained, zero exclusions and no warnings. Checker coverage is 350/353 lines plus 79/80 branches (99.08%); combined Python/native-C is 1973/2121 (93.02%). Live authentication or client tool execution is not inferred from these offline checks.
- Full isolated UID-0 canonical host quality passes on preceding frozen `cb61b3c` source. Its later host-only override delta passes the fresh focused/coverage runs; exact final-source hosted validation is recorded separately below.
- The single observer's October 12, 05:35:49 UTC source snapshot verifies matching PR/ref/base and open, non-draft, mergeable, unmerged state. All 37 checks complete: 36 successful, existing Scorecard neutral, no failures or pending jobs. All three full quality suites and six fresh ARM executions pass; both acceptance aggregates pass all 11 selected groups, 118 scenarios per architecture /354 per matrix. These are fresh source executions, not historical ARM reuse. Physical acceptance remains unchanged.
- Sonar verifies exact source SCM, 102 tests, strict zero unresolved issues and 97.9% new-code coverage. Qodo and Codex report no findings. CodeRabbit formally approves exact source (`5486805918`), reports no actionable comments and passes all five pre-merge checks. Complete GraphQL/REST pagination confirms zero inline comments/threads and no active Codex review.
- Fresh hosted ARM evidence and the actual immutable `5ca3a31` archive share digest `ba74a23402547cc0d48b218f2e1d7bf4af91e4452514a4b069662f811c1dc27c`. The editable local worktree digest is `34bd09b7694135ec553e5764c43f43f7d932181e71c47edd85fe127e626a9e46`: 43 included executable files have restricted local 0700 modes. Recomputing over identical tracked bytes with normal Git execute bits exactly reproduces the hosted/archive identity. These are distinct filesystem provenance records, not interchangeable execution claims.

This completion-record follow-up changes task files only. Later published-head results are tracked in the PR description rather than pre-claimed here. No external account, credential, trust, billing, merge or release changes occur.

Current master includes the merged shared-agent/Lovable support PR #1034 plus the maintainer's Codex Lovable server addition. Existing Amazon Q declares Context7 and Firecrawl; no other repository MCP client declarations were found. Primary vendor documentation is being used to verify native client formats and provider authentication details.

---

## TASK-026: Add optional Lovable repository handoff support

**Priority:** P2 | **Tags:** agents, integration, documentation
**Scope:** PR #1034 onto master. The user selected repository integration support first; no Lovable project, database, connector, workspace skill or deployment is provisioned by this task.

### Plan

- Add a portable, repository-scoped Lovable skill and a versioned handoff contract for canonical policy, exact source provenance, existing task ownership and actual validation evidence.
- Document optional references to user-owned Lovable Cloud/Supabase data with explicit ownership, authorization and read-only scope. Keep `.tasks/`, GitHub review state and existing ARM/physical gate authority; private model training data is not exposed by these APIs.
- Register the adapter and align shared agent routing without replacing existing provider configurations. Explain GitHub API access separately from Lovable Git sync and preserve unrelated project/workspace instructions.
- Run existing integration checks, validate the handoff schema and its intended constraints, review the diff and publish a normal leased update to the existing PR. Observe the published head through one designated reviewer; report missing, pending or rate-limited results accurately.

### Acceptance criteria

- [x] The skill remains usable when imported alone into Lovable and loads canonical repository instructions from the supplied exact-head packet or verified immutable references.
- [x] Handoffs distinguish advisory analysis, host checks, native ARM execution, modeled firmware and physical operator reports; optional database references cannot become a second task ledger or a test waiver.
- [x] All existing agent entry points, Qodo skills and original provider IDs are preserved; Amazon Q remains byte-identical to canonical policy.
- [x] Existing integration checks and schema verification pass. Any unchanged native evidence is identified by its tested-content digest, not relabeled as a new run.
- [x] The updated PR is published and current-head check/review state is recorded, including external service limitations.

### Verification

The read-only registry check passes with eight agent entry points, ten skills and 27 providers. All 44 existing integration regressions pass. The Draft 2020-12 schema and documented baseline packet validate, and its actual historical policy hash matches. Independent boundary review passes eight positive controls, 26 negative schema-shape controls and three bounded timestamp rejection controls. The timestamp controls register an explicit temporary checker; this adds no repository dependency and does not claim comprehensive RFC3339 parser validation. Amazon Q remains byte-identical to canonical policy, and `git diff --check` passes.

The current tested-content digest remains `28098abaac867cb1b95541bd4387c726ef5d797a865d60b84e58689b10c99877`. Existing frozen armv5/armv7/armv8 reports each contain 118 passing scenarios (354 total), and aggregate validation against the current checkout passes all 11 selected contracts. These are revalidated earlier executions, not new runs. No runtime, archive, test, validation-tool or workflow input changes are made here; physical acceptance is unchanged. Implementation published normally to PR #1034 at `9dca9fbe54013d90bc59fbd3c0cdd75122b370eb`, exact tree `abf1c27bf99b6d0ce2313044cfd5a7949cf027b6`. The single observer's October 11, 19:18:58 UTC snapshot verifies matching PR/ref, unchanged master base and exactly the 11 intended paths. All nine review threads and 20 inline comments remain resolved; Qodo's new-head footer reports zero findings. At that cutoff, 31 current-head checks are starting with no failures, and CodeRabbit is reviewing; these are pending hosted results, not claimed passes. The PR description tracks later hosted outcomes; this task-record follow-up does not change tested inputs.

Read-only account inventory on October 11, 2026 found a Pro workspace with zero projects, workspace skills and added connectors. The user chose repository support before external setup. No account identifiers, credentials or private database content are checked in.

---

## TASK-025: Resolve integration-checker hosted findings

**Priority:** P1 | **Tags:** agents, review, security, validation
**Scope:** PR #1034 onto master; verified source head `4bec2dbcf913f2e9381e2bfaaaff59a8fe7e8fa4`. Correct newly reported host-only checker findings while preserving registry rejection and filesystem safety. Existing TASK-024 completion is the earlier implementation/publication snapshot.

### Plan

- Independently verify all 11 Sonar findings, including repeated policy literals, frontmatter parsing complexity, numeric character classes, redundant exception handling and caller-supplied root selection.
- Address two subsequently reported Codex consistency gaps: requested-provider deletion and malformed optional skill metadata must fail validation. Preserve valid existing Qodo trigger headers and document the supported metadata grammar; add isolated negative tests.
- Reject unquoted leading-decimal exponents consistently across agents' YAML versions while preserving quoted text; add signed/unsigned and quoted controls for the subsequently reported CodeRabbit case.
- Correct the focused Codex review's three portable-header gaps: decoded lone Unicode surrogates, comma-leading plain scalars, and tab indentation hidden by comment skipping. Cover adjacent reproduced non-ASCII separator/indentation cases while preserving valid Unicode text and space-indented comments. Add explicit binary-number controls for CodeRabbit's already-rejected case without changing working numeric detection.
- Simplify parsing and make CLI repository selection derive from the checked-in checker location. Keep isolated real-process tests by placing the checker in each disposable fixture repository; preserve no-follow descriptor access, nonregular-file rejection, read-only checks, stderr and timeout assertions.
- Re-run focused host safety tests and genuine credential-free coverage, independently review the final diff, and obtain fresh frozen all-three-target native evidence for the changed tested content. Keep physical acceptance separate and do not weaken thresholds or suppress findings.
- Publish normal leased PR updates, inspect current-head Sonar and other agent/check results through one observer, and record evidence-based thread dispositions using the existing Qodo resolver.

### Acceptance criteria

- [x] All current Sonar issues are corrected and current-head strict zero-unresolved enforcement passes.
- [x] Both valid Codex drift findings have rejected-fixture coverage; its obsolete task-status comment has an evidence-based disposition.
- [x] The focused Codex portable-header findings have rejection and valid-string controls; CodeRabbit's binary-number claim has an evidence-based disposition.
- [x] Focused rejection/safety tests, host quality and measured coverage pass without exclusions or changed thresholds.
- [x] Fresh native evidence matches final tested content and aggregate acceptance passes on all three targets.
- [x] Published-head review and check states are inspected; external blockers are reported separately. No merge, release, credentials, billing or branch-rule changes.

### Verification

- All 44 focused integration tests pass, preserving the eight required agents, nine skills and 27 requested providers. Fixtures cover no-follow/read-only filesystem access, nonregular files, external-root rejection, linear long-input parsing, complete optional metadata, exact names, ASCII layout and valid Unicode. Binary-number rejection was already implemented; its exact reported signed/unsigned examples and quoted controls now document the evidence-based disposition.
- Genuine credential-free collection runs 88 tests. Checker coverage is 281/283 lines and 57/58 branches (99.12%); combined Python/native-C is 1882/2029 lines and branches (92.76%). Six intended Python modules are measured, with zero excluded lines, no coverage warnings and unchanged thresholds. Sonar credential variables are absent during regressions.
- Full isolated UID-0 canonical host quality exits 0 on frozen local source `a02e470080f41fec8ed32e10885bc25f5fbe0d96`, including lifecycle matrices, checksums, ShellCheck and shfmt. The unchanged DNS-environment fixture passes standalone and within the matrix. The preceding hosted push's unexplained timeout remains failure history; no timeout, assertion or gate was weakened.
- Frozen armv5, armv7 and armv8 executions each pass 118 scenarios, 354 total. Matching aggregate acceptance passes and unblocks only all 11 selected manifest contracts at tested-content digest `28098abaac867cb1b95541bd4387c726ef5d797a865d60b84e58689b10c99877`; builder fingerprint remains `d51320e563c39a2c747f12f209de493df295144b1f26bf3a0d04343059d3fae9`. The armv5 package target remains older RT-AC68U-class ARMv7/software-float with VFP/NEON disabled. Physical acceptance is unchanged; superseded or interrupted runs cannot unblock this source.
- Published source `4bec2db` has exact local/remote tree parity. Sonar scan and strict enforcement pass with zero unresolved issues and 88 hosted tests. Qodo reports zero findings on that head. CodeRabbit approves the source. All nine review threads have evidence replies/dispositions and are resolved, with complete pagination; no Codex request remains active. The independent final Unicode/layout review is clean, so no additional reassurance-only review was requested.
- At the source completion cutoff (18:35:11 UTC), all 36 hosted checks are terminal: 35 succeed and the existing Scorecard check is neutral, with no failures or pending jobs. Both native acceptance aggregates, all six architecture jobs and all three full quality jobs pass. CodeRabbit's four passed pre-merge checks and one inconclusive linked-issue assessment are recorded separately from its approval. The PR body now states the maintainer request and canonical TASK-024/TASK-025 tracking; repository policy has no mandatory GitHub-issue link, and no governing issue applies. The assessment remains enabled, with its refresh and final-head checks tracked as delivery follow-up.

### Completion record

Source corrections, matching local acceptance, authorized publication and review-thread resolution are complete on October 11, 2026 (America/New_York). This completion-record update changes only task documentation and preserves the tested-content digest. Final published-head hosted observation continues; no pending result is relabeled as a pass. PR #1034 stays ready for review onto master, with no merge, release, credentials, billing or branch-rule changes.

---

## TASK-024: Integrate shared development and review workflows

**Priority:** P1 | **Tags:** agents, integrations, validation
**Baseline:** master `047ce167685f6de8db86519557b865e9f23e98f3` after PR #1033 merged; branch `chore/shared-agent-integrations`.

### Plan

- Inventory the requested plugins and distinguish existing services, repository-consumable skills, optional external capabilities, and unavailable integrations.
- Add focused planning, implementation, verification, review completion, workflow auditing, security triage and session handoff skills under the canonical AGENTS.md rules. Keep the existing TaskPlanner records and Qodo resolver authoritative for their respective state.
- Connect existing Codex, Amazon Q, CodeRabbit, Qodo, Claude and Cursor guidance to the shared catalog, and add the GitHub Copilot instructions entry point. Add no credentials, redundant review service, automatic merge, or router-runtime dependency.
- Add a read-only host validator for integration paths, skill discovery, shared policy pointers and the Amazon Q mirror; exercise rejection behavior with isolated fixtures and register it in the existing quality runner.
- Verify the final diff and affected host checks, then publish a new PR targeting master. Preserve feature-scoped native ARM acceptance and separate physical release gates; record actual hosted status without borrowing earlier PR results.

### Acceptance criteria

- [x] Every useful supported capability has a documented entry point, with truthful activation and provenance information.
- [x] All existing agent adapters share AGENTS.md and the same testing/evidence rules.
- [x] Integration drift fails validation, and valid configurations pass focused regressions.
- [x] A new reviewable PR targets master; merging and release publication remain separate actions.

### Verification

- Read-only registry check: eight agent entry points, nine skills and all 27 requested plugin dispositions pass; Amazon Q remains byte-identical to AGENTS.md.
- All 35 integration regressions pass. Genuine credential-free coverage runs 79 tests and measures 98.87% for the new checker, with no coverage exclusions or changed thresholds.
- Full isolated UID-0 `sh tools/code-quality.sh` completes with exit 0, including host regressions, checksums, warning-level ShellCheck and shfmt. Independent review is clean.
- The first ARM run's 118 older-ARMv7 scenarios passed, but its evidence was correctly rejected because host validation sources changed during execution. Its logs are retained and are not credited as acceptance.
- Replacement frozen-snapshot full-system executions each pass 118 scenarios, 354 total. Three-target aggregate evidence passes and unblocks all 11 selected feature groups at content digest `124058f538a25928104be7381a1e51a45e0c4925a7179c1bea2ab786733385cf`; builder fingerprint remains `d51320e563c39a2c747f12f209de493df295144b1f26bf3a0d04343059d3fae9`. The armv5 package target remains older ARMv7/software-float with VFP and NEON disabled.
- Published [PR #1034](https://github.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/pull/1034), ready for review onto master, from head `e583f4603adcc3e510d242a92f1c8e1cc42ac6e3`. Its tree matches the independently tested local commit. Hosted PR checks and external reviews are pending at this completion snapshot and remain delivery follow-up; they are not claimed as passes. Router runtime, package archives and physical release evidence are unchanged. No merge or release is performed.


### Completion record

Repository integration implementation, local verification and authorized PR creation are complete on October 11, 2026 (America/New_York). The final metadata-subset clarification and this task record are documentation-only follow-up; tested host sources and native content identity remain unchanged. Current-head hosted findings, if any, must be independently verified and handled before claiming hosted acceptance. The catalog does not install or authenticate external providers.

---

## TASK-023: Record completed physical-router acceptance

**Priority:** P1 | **Tags:** release, hardware, documentation
**Scope:** User confirmation on October 10, 2026 America/New_York: both ARMv7 and AArch64 physical routers completed 48 hours and passed the full physical checklist. Record RT-AC5300 / 386.14_2 and GT-BE98PRO / 3006.102.9 full-checklist/48-hour results plus additional RT-AC68U / 386.14_2 testing. Preserve unreported build/event details and separate software/release gates.

### Plan

- Update the v2.6.7 checklist's hardware coverage, scenarios, soak and sign-off to PASS based on the operator's full-checklist confirmation; clearly distinguish reported physical evidence from independently run software checks.
- Align README, current TASK-018 status and PR #1033 with completed physical acceptance; label older hardware-skipped records historical without rewriting their results.
- Validate documentation consistency, references and unchanged runtime/builder inputs. README participates in the ARM content digest, so publish a normal leased update and require fresh matching three-target hosted execution plus acceptance; inspect all new review/check states.
- Move this recording task to Done after verification. Keep exact unreported build/event traceability fields visible, the separate external AI quota condition visible and the PR ready/unmerged.

### Acceptance criteria

- [x] RT-AC5300 / 386.14_2 and GT-BE98PRO / 3006.102.9 have operator-confirmed full-checklist and 48-hour PASS results. Additional RT-AC68U / 386.14_2 physical testing is recorded with its individual duration/checklist detail unreported.
- [x] Current checklist, README and TASK-018 physical criteria agree; older hardware-skipped results remain explicitly historical and virtual-test limits stay intact.
- [x] Documentation/status/model/link checks, release/version/manifests and release-check negative regressions pass. README is the sole changed tested policy input; runtime/builder inputs are unchanged. Publication and fresh matching hosted verification proceed as delivery follow-up; pending results are not credited as passes.

### Completion record

Physical evidence ID `PHYS-2026-10-10-OPERATOR` records the user's October 10, 2026 America/New_York report and explicit confirmation, "Both passed the full checklist". The confirmed 48-hour/full-checklist routers are ASUS RT-AC5300 / 386.14_2 (ARMv7) and ASUS GT-BE98PRO / 3006.102.9 (AArch64). The user also reports RT-AC68U / 386.14_2 physical testing; a separate duration/checklist breakdown was not supplied. Device models and firmware are recorded; deployed commit/hashes, BusyBox/configuration details, event/start/end timestamps and detailed artifacts remain identified as unreported.

Updated all 32 physical scenarios, eight coverage criteria, four soak checkpoints and seven physical sign-off rows to reflect the operator's full-checklist confirmation and additional older-model physical coverage. Current physical acceptance is PASS for the confirmed configurations. README links the current v2.6.7 checklist; the earlier DNS documents label their hardware-skipped snapshots historical and link the new record. TASK-018's physical criteria are complete; supplemental traceability and the separate required-check/release disposition remain tracked without treating unprovided metadata as a new failed physical test.

Independent read-only documentation review finds no substantive issue. Counts, all three model/firmware pairs, relative links, historical separation and the byte-identical canonical Amazon Q mirror pass. `sh tools/check-release-consistency.sh`, `sh tests/release-consistency.sh` and `git diff --check` pass. README participates in acceptance identity, producing tested-content digest `25447412491651ce8abb5af65576f3921db08b61e7597b979d5132c532904ad9`; builder fingerprint remains `d51320e563c39a2c747f12f209de493df295144b1f26bf3a0d04343059d3fae9`. Older `7c0a8167…` native reports are historical implementation evidence and cannot unblock this new digest. Fresh published-head three-target execution and aggregate acceptance are required before claiming the new virtual gate passes.

The documentation recording task is verified. Normal leased publication, PR gate-status update and new-head hosted review/check completion remain delivery follow-up at this record; no future CI result is claimed here. The baseline generated GitHub AI review is separately blocked by HTTP 402 monthly quota exhaustion. PR stays ready and unmerged; no tag, release, check waiver or billing/settings change.

---

## TASK-022: Resolve ready-review SonarCloud and Qodo findings

**Priority:** P1 | **Tags:** review, security, coverage, hooks, locks, tests
**Scope:** User follow-up on October 9, 2026 America/New_York: PR #1033 is now ready for review. Resolve its current SonarCloud findings and unresolved Qodo feedback while preserving repair-only behavior, the older ARMv7/software-float target, scoped virtual acceptance and separate physical release gates.

### Plan

- Inventory current-head SonarCloud issues, coverage/security gate conditions and Qodo inline/summary feedback; deduplicate and independently reproduce valid failures.
- Repair guest dependency confinement, indented managed-hook handling, read-only stale-owner activity detection and accurate historical-lock diagnostics with focused negative/safety regressions.
- Resolve valid scanner findings without disabling checks, weakening thresholds or rewriting unrelated code. Produce real coverage evidence for supported host Python/C sources and preserve the documented shell coverage limitation.
- Run focused checks, checksum/release validation, canonical host quality and fresh matching native ARM evidence for changed tested inputs; rebuild native tooling when required.
- Publish normal leased branch updates, reply with evidence and resolve addressed/rejected findings; inspect final-head Qodo, CodeRabbit, SonarCloud and software/ARM checks. Preserve the user's ready-for-review status and record external service blockers separately.

### Acceptance criteria

- [x] All four Qodo inline findings have reproduced fixes, published evidence replies and resolutions; the current Qodo summary reports zero bugs/rule violations. Its alternative designs are not additional findings.
- [x] SonarCloud's 51 original findings and one follow-up finding are closed by corrections. Hosted quality gate and zero-unresolved enforcement pass: zero unresolved/accepted issues, A reliability/security/maintainability and 91.8% new-code coverage; thresholds and supported-source coverage scope are unchanged.
- [x] BusyBox 1.25.1/POSIX runtime compatibility, artifact sidecars, focused negative/safety regressions and the complete isolated canonical host suite pass.
- [x] Fresh rebuilt armv5/armv7/armv8 environments each pass 118 scenarios, 354 total; matching aggregate evidence unblocks all 11 selected feature groups. Superseded results cannot unblock.
- [x] Published implementation review/check states are inspected; the user's ready status and separate physical TASK-018 gates are preserved. Final workflow-hardening publication gets its own hosted inspection before delivery; no merge, tag, release, policy waiver or billing/settings change.

### Completion record

Published runtime/scanner corrections: `94be8a5f6cfbe7d7e63d4543b70a3f1fadab5e58`; follow-up read-only DNS query parameter: `c454e77701545dd923e6945de33443569e41bd8d`. Qodo payload confinement now uses canonical archive names and no-follow directory-descriptor reads; tests reject traversal, symlink escape and directory swaps. Managed-hook cleanup recognizes the reproduced indented guard suffix and preserves unrelated commands. Read-only service probes ignore only proven dead canonical PID/start-time identities, preserving live, malformed and unsafe metadata; actual SIGKILL cases pass. Doctor correctly distinguishes retained historical descriptor inodes without unlinking them.

Exact BusyBox 1.25.1 hook/doctor/lock/cache checks, 26 evidence-policy tests, real-child serial-protocol checks, host artifact regressions, 259 DNS protocol/CLI/socket cases and strict host/all-three-target C compilation pass. Genuine coverage runs 44 tests and measures Python 924/989 lines plus 272/320 branches, native C 214/227 lines plus 134/152 branches. The final combined line/branch result is 91.47%. Supporting Python/C repairs, HTTPS-only download redirects and the unprivileged builder default address scanner findings without suppressions or coverage-denominator exclusions. Sonar run `37947173480`, quality-gate job `113876910604`, passes at `c454e77` with 91.8% new-code coverage and zero unresolved issues.

Final tested-content SHA-256: `7c0a81678581085fbd5a8f3ab9a6239c13ac0f4e36cfabf9297d96783b17c96f`; builder fingerprint: `d51320e563c39a2c747f12f209de493df295144b1f26bf3a0d04343059d3fae9`. Fresh `accepted-armv5`, `accepted-armv7`, `accepted-armv8` executions exit 0; `final-acceptance.json` returns `status: pass`, `unblocks: true`, all three architectures and all 11 feature groups. The armv5 package target remains an RT-AC68U-class older ARMv7 Cortex-A9 with software float and VFP/NEON disabled. Canonical isolated host validation (`canonical-quality-final.log`) exits 0. Earlier portability failure logs and invalidated native runs are preserved; they never contribute to acceptance. The corrected fixture uses stock-compatible `which`.

All four Qodo findings have published evidence replies/resolutions and a Round 1 summary (`6083218635`); Qodo's refreshed review reports zero findings. CodeRabbit's review of `c454e77` passes all five pre-merge checks with 94.77% documentation coverage and raises one additional valid credential-boundary finding. Coverage/tzdata tests now execute before the Sonar token is exported. The collector also rejects presence of either Sonar credential variable, including empty values, before loading regressions or writing reports. Independent negative checks and workflow ordering checks pass; a fresh credential-free measurement again passes all 44 tests. This workflow-only correction does not change either ARM content identity. Original-thread reply/resolution follows publication; final publication's hosted reviews and all three ARM jobs plus acceptance are inspected before delivery.

At this record, `c454e77` hosted Sonar, canonical quality, shell/checksum, Semgrep, OSV and Scorecard workflow checks pass. Push ARM run `37947163503` passes all three targets and aggregate acceptance job `113883286609`; the pull-request matrix still awaits its final target and acceptance. Final publication gets its own complete hosted inspection. The separate generated GitHub AI review fails before producing a code finding because of HTTP 402 monthly quota exhaustion. This external service condition is not waived or treated as a software pass. PR #1033 remains ready for review. TASK-018 physical firmware/client/DHCP/isolation/reboot/WAN/48-hour-soak acceptance remains BLOCKED independently.

---

## TASK-021: Resolve ARM-suite review findings and hosted acceptance failure

**Priority:** P1 | **Tags:** review, virtualization, arm, ci, tests
**Scope:** User follow-up on October 8, 2026 America/New_York: repair PR #1033 review findings and failed ARMv7/aggregate acceptance, align all agent guidance, and clear CodeRabbit pre-merge checks without weakening thresholds. Preserve the older RT-AC68U-class ARMv7 software-float target, scoped acceptance, draft status and physical release gates.

### Plan

- Verify current feedback and hosted failure logs; reproduce valid findings before correction.
- Repair BusyBox option validation, DNS pointer rejection and malformed guest-result cleanup with focused regressions.
- Isolate the reproduced cache fixture dependency while preserving real serialization, service guards and normal retry budgets.
- Align agent guidance, document affected functions and validate configuration consistency and unchanged executable behavior.
- Follow up on the later outside-diff host-provisioning finding: install the declared Docker prerequisite in both canonical and mirrored guidance, verify configuration consistency, publish evidence and inspect that final head.
- Rebuild affected guests, verify complete matching native/host checks, publish normal branch updates, reply/resolve original threads and inspect published-head ARM/pre-merge results.

### Acceptance criteria

- [x] All three original CodeRabbit findings were corrected in `a1d3f81`, received evidence replies and were resolved.
- [x] Actual overlapping service probes reproduce the cache pair's early exit; all final cache scenarios pass without weakening production behavior.
- [x] Fresh final-content native execution passes 118 scenarios per target, 354 total; aggregate acceptance unblocks all 11 covered contracts. Canonical host quality passes.
- [x] Nine agent guidance entry points share the canonical ARM contract; seven configuration/skill regressions, format parsing and exact Amazon Q mirror checks pass.
- [x] Both hosted ARM workflows at implementation `3d3169b` pass all three targets and aggregate acceptance.
- [x] All five CodeRabbit pre-merge checks pass at `3d3169b`; hosted documentation coverage is 92.83% against the unchanged 80% threshold.
- [x] PR remains draft; no merge, physical release, check-policy waiver or billing/settings change.

### Completion record

Verified implementation: `3d3169b14f2fb67605fb74f98e089644490a825c`. Final tested-content SHA-256: `c07f53f48f37014b04d0684827059b70dbfe6261f3bfe02c5c3222c0551844fe`; builder fingerprint: `3a2d79cc550a49cadb9fff6584235681be23bd15893c7c1ccb5968fa06e2e013`. Fresh builds, all 354 native executions, aggregate acceptance and canonical host quality pass. Evidence IDs are `premerge-final-armv5/armv5`, `premerge-final-armv7/armv7`, `premerge-final-armv8/armv8`, `premerge-final-acceptance.json` and `premerge-canonical-final.log`; earlier failures remain recorded.

Hosted pull-request ARM run `37872521379` passes all targets and acceptance job `113637716278`; push run `37872516957` also passes, including acceptance job `113637202694`. The pull-request gate records the exact final digest, 118 scenarios per architecture and `status: pass`, `unblocks: true`. All five CodeRabbit pre-merge checks pass at this implementation, including 92.83% documentation coverage. Independent documentation audit and executable AST/preprocessed-C comparisons support the purpose-only changes.

The subsequent Amazon Q mirror-link finding is corrected and validated locally; its documentation-only publication, original-thread reply/resolution and that publication's own hosted check/review inspection remain delivery follow-up, not results claimed by this implementation record. Its bytes do not change the tested-content digest. The separate GitHub AI review run `37872524141`, job `113633597418`, failed before producing a code finding because of monthly quota exhaustion. TASK-018 physical-router, firmware/client/reboot/WAN/soak acceptance remains BLOCKED independently.

Delivery follow-up: mirror-link fix `6f2d60e` received an evidence reply and resolution; all eight inline threads are resolved. CodeRabbit approved that head and also identified a valid outside-diff omission in the host setup command. Both guidance copies now install `docker.io`, verify its version and require a running, accessible daemon before guest builds; QEMU/cross-compilers remain supplied by the isolated builder. Existing agent/configuration checks, mirror comparison, local Docker version/daemon probes and diff checks pass; tested-content digest remains `c07f53f4…`. Publication/evidence reply for this provisioning correction and final-head hosted inspection follow; no new native execution or review pass is claimed here.

---

## TASK-020: Build ARM virtual feature environments and scoped acceptance

**Priority:** P1 | **Tags:** virtualization, arm, tests, ci
**Scope:** User authorization on October 8, 2026 (America/New_York): native ARM package-target feature testing and repairs, with acceptance limited to covered feature/change contracts. The legacy armv5 package represents an ASUS RT-AC68U-class older ARMv7 CPU with software float, not a newer hard-float target.

### Plan

- Build disposable full-system Cortex-A9/software-float, Cortex-A15/hard-float and Cortex-A53/AArch64 guests with pinned kernels and native BusyBox 1.25.1; disable VFP/NEON for the RT-AC68U-class guest.
- Exercise broad real-helper regressions and actual shipped AdGuardHome/dnsmasq processes, DNS sockets, API and lifecycle behavior; distinguish modeled firmware dependencies.
- Bind fail-closed feature acceptance to exact candidate content, complete architecture coverage and hashed native execution evidence.
- Reproduce defects, make minimal corrections, refresh runtime digests, and retest the final integrated matrix.
- Add bounded local/CI execution, cache provenance and artifacts; record the software result without waiving firmware/physical release coverage.

### Acceptance criteria

- [x] All three declared environments boot and run native tools and shipped binaries; the older ARMv7 target uses software float with VFP/NEON disabled.
- [x] All 118 scenarios pass on every target, totaling 354 executions; discovered product, fixture and infrastructure failures have corrections and retest evidence.
- [x] Complete selected contracts unblock only their tested content; stale, incomplete, skipped, failed or unknown evidence is rejected.
- [x] Full host quality, evidence-policy/runner/DNS-parser regressions, syntax, lint, formatting, workflow lint and artifact checks pass. Hosted execution of the new workflow remains pending at publication.
- [x] Native/model boundaries and separate physical release gates are documented; PR #1033 stays draft, without merge or release.

### Completion record

Final tested-content SHA-256: `08a676a9e204034ab2eb189b68628b3cf984229002a43aeecde64a6ab2411e3a`; builder fingerprint: `24bb230a13c30665db96d28e1497a3e554406281837287bb7a1057520f55b702`. All three full runs exit 0 and the aggregate gate returns `status: pass`, `unblocks: true` for the 11 selected feature groups. The provenance commit label is `1781f71` plus the verified working-tree changes; content identity, rather than that historical label alone, binds the result. Exact commands, failures/fixes, evidence IDs and validation environment are in RELEASE-2.6.7-CHECKLIST.md.

Native guest testing found a real runtime portability defect: resolver mount detection required optional `df -h`. It now uses `df -P` with limited-applet regression coverage and refreshed manager sidecars. Native fixtures also needed BusyBox-safe command usage, scoped variable names and synchronized integer waits. The serialization fixture preserves production retry budgets in normal scenarios and bounds only its dedicated timeout case. The suite watchdog no longer prints a false expiry when cancelled. The DNS assertion validates every declared answer, authority and additional record rather than accepting a matching prefix of a truncated response; 96 positive/negative host cases pass.

Actual beta/edge/stable binaries execute and validate configuration on each CPU. Stable-only native lifecycle, UDP/TCP A/AAAA/PTR, listener ownership, restart, resolver recovery and foreign-owner refusal pass. Router nvram/service/cru/SDN dependencies remain modeled. TASK-018 hardware/firmware/client/reboot/WAN/soak coverage stays BLOCKED independently; this does not block the covered virtual feature result. Current published-head checks/review must be inspected before merge or release.

---

## TASK-019: Resolve PR #1033 automated review feedback

**Priority:** P1 | **Tags:** review, locks, portability, tests
**Scope:** User-requested resolution of existing agent feedback on October 8, 2026 (America/New_York); preserve v2.6.7 repair-only behavior, draft status and hardware acceptance gates. No merge or release.

### Plan

- Verify all unresolved inline threads and agent summaries against head a039ba5 before accepting suggestions.
- Repair owner cleanup contention without changing immediate-busy acquisition or unsafe-claim preservation; prove the live-claim case with the real helpers.
- Keep dnsmasq fixture lock/probe state under its private workspace and preserve helper-extraction failure status.
- Replace fractional fixture sleeps with supported bounded integer waits and explicit synchronization.
- Document touched shell helpers missing descriptions to address the automated coverage warning; refresh both touched runtime digest pairs.
- Run focused sh/BusyBox/1.25.1 harness regressions, canonical local validation and relevant hosted checks. Push normal commits, reply on each original thread with evidence, then resolve and reread current review state.
- Follow-up review: clarify that the summary's pending hosted status belongs to the original 5c28d8d record, retain the later passing b31385a evidence, verify the documentation diff and reply/resolve the timeline thread.

### Acceptance criteria

- [x] All applicable inline findings have verified corrections and passing regression evidence.
- [x] Agent summary warnings receive evidence-backed fixes or a documented reason for rejection.
- [x] Current source syntax, lint, formatting, lifecycle checks and artifact digests pass.
- [x] Original threads have fix/rejection replies and are resolved; current-head feedback and checks are inspected before reporting completion.

### Completion record

Implemented in b31385a. All three original CodeRabbit threads received evidence replies and are resolved; subsequent thread inventory returned zero unresolved. Real-helper regressions prove bounded live-owner cleanup, immediate-busy contenders and preservation of malformed/unsafe claims. The isolated dnsmasq fixture preserves host state and extraction failures. All fractional fixture sleeps were replaced with bounded integer waits and real contention handshakes.

Full isolated UID-0 canonical validation exits 0. Separate BusyBox lifecycle validation passes all 28 groups with exit 0; an unchanged-baseline watchdog cleanup diagnostic race is recorded in RELEASE-2.6.7-CHECKLIST.md. All 162 scripts parse under sh/BusyBox1.37/1.25.1 ash; targeted three-shell checks, local-cache regression, ShellCheck, shfmt, actionlint and all artifact digests pass. Independent documentation audit: 132/132 changed/new definitions described. Probe warning rejected with private-parent/exclusive-create/path-safety evidence; style-only preferences are not defects under AGENTS.md.

Hosted Code Quality, Shell validation, Semgrep, OpenSSF Scorecard and OSV checks pass at published repair head b31385a; draft-only Code Quality Review skips. CodeRabbit approved and its hosted documentation check passes at 94.07%. Subsequent published-head inspection remains part of the delivery; physical release gates stay in TASK-018. No hardware acceptance, merge or release is claimed.

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

- [x] Canonical validation actually executes real-helper legacy migration, doctor malformed-hook, lock-path, contention, and graceful-stop failure cases.
- [x] Host sh and BusyBox ash checks pass; security tests execute in an isolated UID-0 host with foreign-UID cases; target BusyBox 1.25.1 ash harness passes. Firmware libc/ARM/applets remain hardware acceptance.
- [x] Full lifecycle integration, lint, formatting and artifact checksums pass against the final combined source, with published repair-head b31385a hosted review/check evidence.

### Verification

- [x] Run `sh tools/code-quality.sh` in the documented isolated validation host with declared prerequisites; exit 0 at source 5c28d8d.
- [x] Run `sh tests/service-lifecycle-integration.sh`; separate `AGH_INTEGRATION_SHELL=busybox AGH_INTEGRATION_SHELL_ARG=ash busybox ash tests/service-lifecycle-integration.sh` also exits 0 for all 28 groups.
- [x] Run `sh tools/check-md5.sh`, `sh tools/check-sha256.sh`, `sh tools/check-release-consistency.sh`, workflow lint and `git diff --check`.
- [x] The combined passing result is a software validation gate; it is not evidence of ASUS firmware dispatch, DHCP leases or overnight physical-router behavior.

### Completion record

All local canonical checks pass, including lint/formatting and 162 syntax checks in each of sh, BusyBox 1.37 ash and the built 1.25.1 ash harness. Existing helper-extraction fixtures and the workflow command inventory were updated for the new dependencies without suppressing failures. PR #1033 review repair source b31385a also passes canonical validation and the separate 28-group BusyBox matrix; its existing cleanup diagnostic race is recorded in the release checklist. CI retains its 180-second per-check budget; the isolated local host used a recorded 600-second budget. All five executed hosted workflows pass at published repair head b31385a, draft-only review skips, and CodeRabbit approves. TASK-017 is complete for that source; recheck subsequent published heads before merge or release. TASK-018 stays In Progress with physical acceptance BLOCKED.

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
