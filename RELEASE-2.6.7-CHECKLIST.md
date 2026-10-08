# v2.6.7 repair release acceptance checklist

## Record status

**Physical-router acceptance: BLOCKED — no v2.6.7 hardware results recorded.**

v2.6.7 is limited to repairs of managed hook generation/diagnostics, service-lock safety and serialization, and verified monitor shutdown. It preserves the existing installer transactions, BusyBox/POSIX compatibility, topology policy, saved preferences, and upstream AdGuardHome channels. Software regressions cannot establish that the reported overnight DNS/DHCP outage is resolved on installed firmware.

This checklist carries forward the relevant requirements of [v2.6.5 real-router acceptance](RELEASE-2.6.5-CHECKLIST.md) and [DNS lifecycle validation](docs/dns-lifecycle-validation.md). Their historical results do not count as v2.6.7 results. No operator, maintenance window, router result, or soak outcome has been assigned here.

Use **PASS**, **FAIL**, **BLOCKED**, or **NOT APPLICABLE**. An unrun mandatory row remains BLOCKED. A NOT APPLICABLE row needs a recorded reason, such as firmware without supported SDN capability. Publication and a claim that the reported outage is resolved remain blocked until mandatory hardware coverage passes and failures have an explicit disposition.

## Repair scope and software evidence

| Repair | Required behavior | Verification record |
|---|---|---|
| Legacy managed-hook migration (TASK-012) | Cleanup/regeneration leaves a valid first-line interpreter, one intended managed invocation, and final executable mode; unrelated shared commands survive; a failed write restores prior content and mode. | PASS — focused real-helper regressions; software record below. |
| Managed-hook doctor checks (TASK-013) | Malformed executable hooks do not produce a false healthy result; applicable main/SDN/service-event hooks are checked; repair preserves unrelated content and topology policy. | PASS — malformed hooks, safe repair, rollback and legacy-inode preservation regressions. |
| Service-lock/probe paths (TASK-014) | Symlink targets, foreign files/directories and special files are not followed, truncated or removed; descriptor users share a stable lock inode; safe fallback remains available. | PASS — root tests include foreign UID objects. Local privilege impact still depends on firmware permissions and symlink protection. |
| Fallback operation serialization (TASK-015) | Start/stop/restart acquire atomic ownership; a contended action returns a meaningful busy failure; only the owner cleans up; operations never overlap. | PASS — all three backend selections, PID reuse, legacy upgrade and interrupted ownership transitions. |
| Monitor shutdown (TASK-016) | Stop failures propagate; parent-side checks establish daemon absence, handoff cleanup, native resolver state and required DNS restoration before success. | PASS — graceful/forced/repeated stop, missing /opt, remembered SDN and unrelated DNS owner regressions. |
| Canonical regressions and packaging (TASK-017/018) | New failure cases are included in canonical CI; focused tests, lifecycle integration, BusyBox syntax/behavior, lint and all distributed checksums pass at the final candidate commit. | PASS — complete local quality run, both lifecycle shells, syntax, lint, formatting and artifact checksums. Hosted checks are pending. |

Record each software result with the candidate commit, exact command, exit status, validation environment (including UID and BusyBox/lint versions), and evidence reference. Do not copy previous-release totals as current results. Verify banner/version and both checksum manifests after the final version edit. Do not refresh upstream AdGuardHome channels or archives for this release unless independently required by a proven defect.

### Software verification record — October 8, 2026 UTC

Runtime and test source: `5c28d8dab65ed1ecef027137fc283a0be2fe42e0`. Subsequent release-record edits change documentation/task metadata only. The four repair/CI commits are `d783705`, `a9bc559`, `8ada69b` and `5c28d8d`; baseline failure proofs used `85b926b`.

Validation ran in an isolated Debian trixie Docker container as UID 0 with source mounted read-only and networking disabled. Image ID: `sha256:09530469596db579622e3f335974e985eacc439d55805a179b5e6a5bf86ce6ba`. Tools: BusyBox 1.37, gawk 5.2.1, jq 1.7, ShellCheck 0.10, shfmt 3.8, actionlint 1.7.12, GNU coreutils timeout 9.7 and Python 3.13.5. Foreign-UID cases are part of the privileged lock/path fixtures.

| Check / command inside the validation container | Result / evidence ID |
|---|---|
| `TEST_MAX_RUNTIME_SECONDS=600 SERVICE_LIFECYCLE_MAX_RUNTIME_SECONDS=5160 sh tools/code-quality.sh` | PASS, exit 0; includes main sh lifecycle matrix, privileged regressions, all artifact MD5/SHA-256, release consistency, portability, ShellCheck and shfmt; `combined-code-quality-final.log`. |
| `AGH_INTEGRATION_SHELL=busybox AGH_INTEGRATION_SHELL_ARG=ash busybox ash tests/service-lifecycle-integration.sh` | PASS, exit 0; all 28 declared scenario groups; `busybox-integration-final.log`. |
| Each repository script listed by `sh tools/list-shell-scripts.sh`, checked with `sh -n`, `busybox ash -n`, and the built 1.25.1 binary's `ash -n` | PASS, exit 0; 162 scripts in each shell; `syntax-final.log`. |
| `tests/service-lock-path-safety.sh` and `tests/service-lock-serialization.sh` under `sh`, BusyBox 1.37 ash and the built 1.25.1 ash | PASS, exit 0 for each invocation; `lock-focused-final.log`. Expected SIGKILL diagnostics are asserted failure-injection cases. |
| Managed-hook, doctor, transaction, monitor postcondition, adaptive readiness and service-status fixtures under the built 1.25.1 ash | PASS, exit 0; `target-ash-focused.log`, `lock-focused-final.log`, `adaptive-fixture-final.log`, `target-status-final.log`. |
| `actionlint -shellcheck= -pyflakes=`; `git diff --check`; unchanged-source digest check | PASS, exit 0. |

The 1.25.1 binary is a static x86_64 glibc **ash shell harness**, built from upstream tag `1_25_1` at `868530ade244bf8162fb6a10816bd815b166d509`. Its SHA-256 is `e2970bfb7eafd54fef1aabd8d4904f005449e91feaa4bc50e8c0d608381610a2`. These tests use validation-host external commands; they do not establish firmware libc, ARM executable, or complete 1.25.1 applet equivalence. Physical firmware and client tests remain required.

The local quality run uses an explicitly recorded 600-second per-check host budget; checked-in CI retains its 180-second per-check budget. The lifecycle matrix uses its existing 5160-second bound. Final source digests: installer `9b148dedfe1ecb4e04617fd8c59656c1063a9034f58daf6ba0522f7e98bd6cf4`; manager `e23018c57077a0c7ff4f22f6b850a443ce1b9a0bafe6c5376a94745e7e26cccb`. Hosted checks and reviews must be assessed at the published PR head; no hosted success is claimed by this local record.

## Evidence and execution

Run service restarts, failure injection, upgrade, uninstall and reboot on test hardware in a maintenance window with a pre-upgrade backup and a working recovery path. Save the prior hook content/mode and relevant settings before corrupt-hook fixtures. Do not replace a shared JFFS hook wholesale with the reported workaround: unrelated commands must survive.

Keep evidence minimal and sanitized. Never commit credentials, private keys, full NVRAM/YAML dumps, public addresses, client MAC addresses, personal query logs, or identifying client data. Use stable labels for networks, clients and public addresses. Read-only evidence collection must not add `nvram commit`, modify firewall/DNS state, or restart services. Router tests must not depend on GNU `timeout`, `realpath`, Perl or Python.

For every executed scenario, record router ID, candidate commit, initial installer/AdGuardHome versions and channel, preconditions, expected/observed result, PASS/FAIL/BLOCKED/NOT APPLICABLE, recovery result, sanitized evidence ID, related issue/fix commit and retest result. Record event timestamps with explicit timezones. Initial placeholder observations below are **Not executed**, recovery is **Not executed**, and evidence is **None recorded**.

## Hardware inventory and coverage

Complete one inventory row per physical router before execution; add rows as needed.

| Router ID | Model / firmware | Architecture / BusyBox | Entware / AdGuardHome channel | Initial installer | Mode / networks / cache | Operator / window | Status |
|---|---|---|---|---|---|---|---|
| ARMV7-01 | Unassigned | ARMv7 / unrecorded | Unrecorded | Unrecorded | Unrecorded | Unassigned | BLOCKED |
| ARMV8-01 | Unassigned | ARMv8 / unrecorded | Unrecorded | Unrecorded | Unrecorded | Unassigned | BLOCKED |
| ARMV5-01 | Unassigned | ARMv5 / unrecorded | Unrecorded | Unrecorded | Unrecorded | Unassigned | BLOCKED — test or explicit maintainer waiver required |
| REPORT-01 | Originally affected model/firmware, if available | Unrecorded | Unrecorded | v2.6.5/v2.6.6 report | Unrecorded | Unassigned | BLOCKED — reproduction hardware not assigned |

| Required coverage | Status | Evidence / disposition |
|---|---|---|
| Supported current firmware on ARMv7 and ARMv8 | BLOCKED | No physical-router result recorded. |
| Older supported firmware, where practical | BLOCKED | Select firmware or record an explicit coverage disposition. |
| ARMv5 test or maintainer waiver | BLOCKED | No result or waiver recorded. |
| Functional descriptor-lock backend | BLOCKED | Record capability result; binary presence alone is insufficient. |
| mkdir/PID fallback, absent or descriptor-incapable flock | BLOCKED | Record any controlled override and its removal after testing. |
| Main LAN, supported SDNs and legacy guest topology | BLOCKED | Record enabled networks and firmware `mtlancfg` capability. |
| WAN and LAN/AP/Bridge, including qualifying WAN-interface NAT | BLOCKED | Verify existing topology gating without broadening hook/IPSET policy. |
| IPv6, cache enabled/disabled and original reported configuration | BLOCKED | Record applicability and any unavailable coverage. |

## Installation, migration and hook repair

For every row, verify settings/YAML preservation, appropriate hooks, no duplicated managed invocations/cron/firewall rules, and expected running/stopped state. A generated managed hook must have its valid interpreter on line 1 and final mode 0755. Preserve an existing valid custom interpreter and unrelated shared commands.

| Scenario | Expected result | Status | Evidence / recovery |
|---|---|---|---|
| Fresh install | Valid executable applicable hooks; correct DNS placement and persisted topology; no stale lock/stage/handoff state. | BLOCKED | Not executed / none recorded. |
| Legacy v2.6.0-or-earlier upgrade | Legacy-only hook cleanup preserves final interpreter/mode and intended invocation; saved preferences remain. | BLOCKED | Not executed / none recorded. |
| v2.6.5 upgrade | Existing settings, active/stopped state and applicable hooks survive migration. | BLOCKED | Not executed / none recorded. |
| v2.6.6 upgrade | Existing settings, active/stopped state and applicable hooks survive migration. | BLOCKED | Not executed / none recorded. |
| Corrupted legacy hook: missing shebang and mode 0600 | Upgrade repairs the reported state; firmware can invoke the managed call. | BLOCKED | Not executed / none recorded. |
| Executable shebangless hook and duplicate managed calls | Read-only doctor identifies the defect; requested repair leaves one intended invocation and valid header/mode. | BLOCKED | Not executed / none recorded. |
| Empty/missing managed hook; shared hook with custom commands | Install/repair creates needed content while preserving unrelated commands and valid interpreter; repeated repair is idempotent. | BLOCKED | Not executed / none recorded. |
| Disabled dnsmasq integration / unsupported SDN / LAN without qualifying NAT | Intentionally absent hooks remain absent; unrelated shared content remains; topology/IPSET gating is unchanged. | BLOCKED | Not executed / none recorded. |
| Read-only doctor then `doctor --fix` | Diagnosis performs no writes; repair reports failures, rejects symlink targets and does not restart services or change DNS/firewall/NVRAM. | BLOCKED | Not executed / none recorded. |
| Hook write/chmod/publication failure or interrupted migration | Operation fails meaningfully and restores aggregate original content/mode/settings; incomplete rollback evidence remains available. | BLOCKED | Not executed / none recorded. |

## Firmware lifecycle and client connectivity

Use an actual client on each enabled LAN/SDN/guest network. Router-local DNS queries alone do not prove DHCP delivery, client connectivity or isolation. While AdGuardHome is running, verify owned TCP and UDP listeners on its configured port-53 addresses and required main/SDN dnsmasq listeners on port 553. After shutdown/failure recovery, verify required native DNS listeners and native router resolver routing. Capture before/after ownership, hook first lines/modes and relevant event logs.

| Scenario | Expected result | Status | Evidence / recovery |
|---|---|---|---|
| Cold boot / installed firmware persistence | Applicable executable hooks run; main and supported SDN DHCP/DNS recover with no port conflict or stale ownership. | BLOCKED | Not executed / none recorded. |
| Firmware-dispatched dnsmasq restart | Regenerated main/SDN configurations run through their hooks; correct TCP/UDP ports return; no `Address already in use` or non-executable-hook log. | BLOCKED | Not executed / none recorded. |
| AdGuardHome restart and repeated service events | Serialized operations return meaningful status and restore correct DNS placement without duplicate state. | BLOCKED | Not executed / none recorded. |
| New DHCP lease, renewal and expiry/reacquisition | Actual clients retain/recover lease and intended DNS option/address across lifecycle events on each network. | BLOCKED | Not executed / none recorded. |
| Main LAN and each supported SDN local A/PTR | Forward and reverse local-name resolution work through the intended dnsmasq upstream; external DNS succeeds. | BLOCKED | Not executed / none recorded. |
| Supported SDN enable/disable during lifecycle | Enabled instances return with required listeners; disabled SDNs are removed from readiness requirements only after verified topology discovery. | BLOCKED | Not executed / none recorded. |
| Legacy guest DHCP/DNS and isolation | Intended DNS advertisements/connectivity remain; guest-to-LAN and inter-network isolation are preserved. | BLOCKED | Not executed / none recorded. |
| Cache disabled and enabled | Router resolution works before/during/after service events; cache activates only after readiness; loss/failure/shutdown restores native routing. | BLOCKED | Not executed / none recorded. |
| Supported IPv6 | Intended IPv6 TCP/UDP listeners, RA/DHCPv6 DNS delivery, external/local/reverse queries and network isolation work from clients. | BLOCKED | Not executed / none recorded. |
| Intended WAN IPv4/IPv6 DNS exposure | External TCP/UDP DNS reachability agrees with the saved intended policy; repair adds no unintended exposure or firewall bypass. | BLOCKED | Not executed / none recorded. |
| WAN offline | Local DHCP/local-name service and required recovery remain usable; external failure does not invalidate successful native local DNS restoration. | BLOCKED | Not executed / none recorded. |

## Lock, failure and recovery scenarios

Use controlled fixtures without targeting unrelated processes or valuable files. Preserve evidence if cleanup or rollback is incomplete. Foreign lock/path checks are local file-integrity tests; they do not establish a remotely exploitable vulnerability.

| Scenario | Expected result | Status | Evidence / recovery |
|---|---|---|---|
| Concurrent start/stop/restart with descriptor locks | One operation owns the stable lock inode at a time; no overlap or successful stop followed by an in-flight startup. | BLOCKED | Not executed / none recorded. |
| Concurrent actions with mkdir/PID fallback | Atomic owner acquisition; contended stop returns busy failure; only owner removes metadata/lock. | BLOCKED | Not executed / none recorded. |
| Stale/reused PID and interrupted lock owner | Identity checks govern recovery; live/unverified owners are preserved; rerun is bounded and meaningful. | BLOCKED | Not executed / none recorded. |
| Symlink, foreign file/directory and special file at lock/probe paths | Targets/content/mode/identity remain intact; unsafe objects are rejected; safe fallback still works. | BLOCKED | Not executed / none recorded. |
| Graceful monitor exit while daemon/DNS cleanup fails | Parent verifies actual stop postconditions, attempts existing bounded recovery, and propagates unresolved failure. | BLOCKED | Not executed / none recorded. |
| Slow/stuck monitor query and forced monitor termination | Daemon termination, handoff cleanup, required main/SDN DNS and native resolver restoration are verified before success. | BLOCKED | Not executed / none recorded. |
| Invalid AGH configuration / immediate exit / missing TCP or UDP listener | Failed start restores native DNS, keeps diagnostics/recovery evidence and returns failure. | BLOCKED | Not executed / none recorded. |
| Slow filter startup / readiness timeout | Readiness remains bounded; timeout does not leave DHCP/DNS without required recovery. | BLOCKED | Not executed / none recorded. |
| Foreign DNS owner | Default refuse-unknown policy fails closed; unrelated process survives; explicit saved legacy policy remains compatible. | BLOCKED | Not executed / none recorded. |
| Interrupted upgrade / interrupted uninstall | Prior or native working state is restored when rollback succeeds; incomplete restoration is reported and evidence retained. | BLOCKED | Not executed / none recorded. |
| Uninstall from running and stopped states, then reboot | Daemon stops; native DHCP/DNS returns; only owned hooks/rules/cron/locks/markers/stages are removed; shared commands survive reboot. | BLOCKED | Not executed / none recorded. |

## Overnight soak

**Recommended coverage: at least 48 hours spanning two overnight maintenance periods**, preferably on the originally affected model/firmware. This is a proposed duration, not an observed result. Record actual scheduled firmware/AGH/filter/update events, start/end timestamps, candidate commit, clients/networks, lease outcomes and any interruption. If applicable maintenance events do not occur, record that gap rather than crediting elapsed time as event coverage.

| Soak checkpoint | Required evidence | Status |
|---|---|---|
| Before soak | Correct hook first lines/modes, listener/PID ownership, client DHCP/DNS baseline and scheduled events. | BLOCKED — not executed. |
| First overnight maintenance period | Relevant event logs, hook execution, main/SDN listeners and client lease/renewal/name-resolution outcomes. | BLOCKED — not executed. |
| Second overnight maintenance period | Same checks plus expired/reacquired lease where practical; no recurring DNS socket conflict or non-executable hook. | BLOCKED — not executed. |
| End and recovery | Final ownership/connectivity, elapsed time, actual event coverage and recovery/retest for every failure. | BLOCKED — not executed. |

## Candidate sign-off

| Requirement | Status | Evidence / disposition |
|---|---|---|
| Final candidate local software checks and both manifests | PASS | Source `5c28d8d`; full local quality run and separate BusyBox lifecycle matrix exit 0. |
| Version/banner/manifests agree | PASS | Banner and AI_VERSION are v2.6.7; both runtime MD5/SHA-256 sidecars agree. |
| Hosted required checks and reviews at the published PR head | BLOCKED | Pending; inspect current-head CI/review evidence before merge or release. |
| Fresh, legacy, v2.6.5 and v2.6.6 upgrade coverage | BLOCKED | Hardware execution required. |
| Reported corrupt hook repair and firmware invocation | BLOCKED | Hardware execution required. |
| Client DHCP/local/reverse DNS and network isolation | BLOCKED | Hardware execution required. |
| Cache, supported IPv6, SDN and intended WAN exposure | BLOCKED | Hardware execution or justified applicability disposition required. |
| Both lock backends and monitor failure recovery | BLOCKED | Hardware execution required. |
| Reboot, interruption and uninstall recovery | BLOCKED | Hardware execution required. |
| Overnight soak and all failure dispositions | BLOCKED | No soak or physical-router result recorded. |

**v2.6.7 physical-router release acceptance remains BLOCKED.** Software implementation may proceed and a development candidate may be reviewed while this evidence is pending; this document is not release approval.
