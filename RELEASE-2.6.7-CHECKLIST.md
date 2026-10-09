# v2.6.7 repair release acceptance checklist

## Record status

**Physical-router acceptance: BLOCKED — no v2.6.7 hardware results recorded.**

v2.6.7 is limited to repairs of managed hook generation/diagnostics, service-lock safety and serialization, and verified monitor shutdown. It preserves the existing installer transactions, BusyBox/POSIX compatibility, topology policy, saved preferences, and upstream AdGuardHome channels. Software regressions cannot establish that the reported overnight DNS/DHCP outage is resolved on installed firmware.

This checklist carries forward the relevant requirements of [v2.6.5 real-router acceptance](RELEASE-2.6.5-CHECKLIST.md) and [DNS lifecycle validation](docs/dns-lifecycle-validation.md). Their historical results do not count as v2.6.7 results. No operator, maintenance window, router result, or soak outcome has been assigned here.

Use **PASS**, **FAIL**, **BLOCKED**, or **NOT APPLICABLE**. An unrun mandatory row remains BLOCKED. A NOT APPLICABLE row needs a recorded reason, such as firmware without supported SDN capability. Publication and a claim that the reported outage is resolved remain blocked until mandatory hardware coverage passes and failures have an explicit disposition.

## Repair scope and software evidence

The [ARM virtual feature suite](docs/virtual-arm-testing.md) provides feature-scoped acceptance independent of the physical-router release rows. A complete passing three-architecture report unblocks only the contracts and candidate content it names. Firmware/client/reboot/soak rows remain separate observations; their pending status does not block an already passing covered virtual feature check. Record actual virtual results and their native/model boundaries rather than inferring a whole-release hardware waiver.

In the virtual suite, `armv5` is an archive/package routing label for the older ASUS RT-AC68U-class ARMv7 Cortex-A9 software-float target; it is not an ARMv5 physical CPU row. The guest reports `armv7l` and disables VFP/NEON. The separate `armv7` target represents a newer Cortex-A15 hard-float environment.

| Repair | Required behavior | Verification record |
|---|---|---|
| Legacy managed-hook migration (TASK-012) | Cleanup/regeneration leaves a valid first-line interpreter, one intended managed invocation, and final executable mode; unrelated shared commands survive; a failed write restores prior content and mode. | PASS — focused real-helper regressions; software record below. |
| Managed-hook doctor checks (TASK-013) | Malformed executable hooks do not produce a false healthy result; applicable main/SDN/service-event hooks are checked; repair preserves unrelated content and topology policy. | PASS — malformed hooks, safe repair, rollback and legacy-inode preservation regressions. |
| Service-lock/probe paths (TASK-014) | Symlink targets, foreign files/directories and special files are not followed, truncated or removed; descriptor users share a stable lock inode; safe fallback remains available. | PASS — root tests include foreign UID objects. Local privilege impact still depends on firmware permissions and symlink protection. |
| Fallback operation serialization (TASK-015) | Start/stop/restart acquire atomic ownership; a contended action returns a meaningful busy failure; only the owner cleans up; operations never overlap. | PASS — all three backend selections, PID reuse, legacy upgrade and interrupted ownership transitions. |
| Monitor shutdown (TASK-016) | Stop failures propagate; parent-side checks establish daemon absence, handoff cleanup, native resolver state and required DNS restoration before success. | PASS — graceful/forced/repeated stop, missing /opt, remembered SDN and unrelated DNS owner regressions. |
| Canonical regressions and packaging (TASK-017/018) | New failure cases are included in canonical CI; focused tests, lifecycle integration, BusyBox syntax/behavior, lint and all distributed checksums pass at the final candidate commit. | PASS — complete local quality run, both lifecycle shells, syntax, lint, formatting and artifact checksums. Hosted checks were pending for the initial `5c28d8d` validation record; the later PR #1033 review verification at `b31385a` is recorded below. |

Record each software result with the candidate commit, exact command, exit status, validation environment (including UID and BusyBox/lint versions), and evidence reference. Do not copy previous-release totals as current results. Verify banner/version and both checksum manifests after the final version edit. Do not refresh upstream AdGuardHome channels or archives for this release unless independently required by a proven defect.

### Software verification record — October 8, 2026 UTC

Runtime and test source: `5c28d8dab65ed1ecef027137fc283a0be2fe42e0`. Release-record commit `a039ba5` changed documentation/task metadata only; the subsequent PR review repair is recorded below. The four original repair/CI commits are `d783705`, `a9bc559`, `8ada69b` and `5c28d8d`; baseline failure proofs used `85b926b`.

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

### PR #1033 review verification — October 8, 2026 America/New_York

Runtime/test source: `b31385a27dfcf34be5b0ef1d31305fbc56b929e5` (TASK-019). Owner cleanup now retries brief live-claim contention with a ten-second bound while service contenders remain immediately busy. Malformed/unsafe claim identities are preserved. The dnsmasq fixture isolates lock/probe paths and propagates extraction errors; serialization uses bounded integer sleeps and explicit contention handshakes. The reported defects were reproduced before correction. Missing descriptions were added without changing the corresponding helper behavior.

Validation used the same isolated UID-0, read-only-source, network-disabled Docker image and tool versions recorded above. The built 1.25.1 binary remains a host ash harness, with the same firmware/libc/applet limitations.

| Check / command | Result / evidence ID |
|---|---|
| `TEST_MAX_RUNTIME_SECONDS=600 SERVICE_LIFECYCLE_MAX_RUNTIME_SECONDS=5160 sh tools/code-quality.sh` | PASS, exit 0; complete lifecycle/regression, lint, formatting, release and artifact checks; `pr1033-review/combined-code-quality.log`. |
| `AGH_INTEGRATION_SHELL=busybox AGH_INTEGRATION_SHELL_ARG=ash busybox ash tests/service-lifecycle-integration.sh` | PASS, exit 0; all 28 groups; `pr1033-review/busybox-lifecycle.log`. Cleanup diagnostic limitation below. |
| All listed scripts under `sh -n`, `busybox ash -n`, and built 1.25.1 `ash -n`; `actionlint -shellcheck= -pyflakes=` | PASS, exit 0; 162 scripts in each shell; `pr1033-review/syntax-workflows.log`. |
| `tests/service-lock-serialization.sh` and `tests/service-lock-path-safety.sh` under sh, BusyBox 1.37 ash and built 1.25.1 ash; `tests/local-cache-serialization.sh` under sh | PASS, exit 0; real live-owner cleanup, bounded retry, malformed/unsafe claims and subsequent action covered; `pr1033-review/lock-cleanup-*.log`. |
| `tests/dnsmasq-lan-mode.sh` under all three shells, sentinel preservation and 18 extraction/rewrite fault injections | PASS; real host lock path remains intact and failures propagate immediately; `pr1033-review/fixture-and-cleanup-independent-review.md`. |
| Independent documentation audit of new/changed shell definitions against `85b926b` | PASS; 132/132 definitions across 18 shell files have descriptions; `pr1033-review/changed-definition-documentation-audit.log`. CodeRabbit's hosted check separately passes at 94.07%, above its 80% threshold. |
| Hosted checks/review at published repair head `b31385a` | PASS; Code Quality `37797727577`, Shell validation `37797727572`, Semgrep `37797734312`, OpenSSF Scorecard `37797727476` and OSV `37797727496` succeeded. Draft-only Code Quality Review `37797727692` skipped. CodeRabbit approved; reread found zero unresolved threads. |

The separate BusyBox matrix printed timeout text after all PASS groups during watchdog cleanup. An unchanged-baseline reproduction confirmed that interrupting the watchdog's unchecked sleep can print this message without an elapsed timeout. The suite exited 0; this is a pre-existing diagnostic race, not a clean-output or actual-timeout claim.

Source SHA-256 at `b31385a`: installer `531ea3be43b4943cebe6a8998c20d6470a6476262153b4c404b0d9d45d957ceb`; manager `f201a1819736ac998027b276e999b3085d924573148c914f7082045e1bf85a19`. All three original inline agent threads received evidence replies and were resolved. The summary's predictable-probe warning does not apply to exclusive creation inside the validated owner-private directory; the existing privileged fixture verifies pre-created symlink rejection and target preservation. Any subsequent published head needs its own hosted CI/review inspection before merge or release. Physical-router rows remain BLOCKED.

### Native ARM feature verification — October 8, 2026 America/New_York

**Covered virtual feature acceptance: PASS and unblocked.** Final tested-content SHA-256: `08a676a9e204034ab2eb189b68628b3cf984229002a43aeecde64a6ab2411e3a`. Builder/source fingerprint: `24bb230a13c30665db96d28e1497a3e554406281837287bb7a1057520f55b702`. Evidence carries provenance label `1781f71ae76754e6f43ed7e47e91d4fa51b5a270` plus the verified working-tree changes; the exact content digest binds what ran. Completion documentation is excluded from that digest. Earlier software records above remain historical, not evidence for changed inputs.

All guests use full-system QEMU TCG, Linux `6.1.157-agh-virtual`, native BusyBox 1.25.1 and native external tools. The legacy armv5 package guest is `vexpress-a9`, `cortex-a9,vfp=off,neon=off`, 256 MiB, armel software float; it reports `armv7l` and CPU features `half thumb fastmult edsp tls` (no VFP/NEON). The newer armv7 guest is Cortex-A15/armhf, 512 MiB; armv8 is Cortex-A53/AArch64, 1024 MiB. Candidate sources are read-only, guest fixture state is disposable and external guest networking is disabled. Builder image ID: `sha256:7d18b5ee72008387e677c84fd6a17dcbf94ff578edb151a12838c9922bfa559a`.

| Command / final evidence ID | Result |
|---|---|
| For each target: `sh tools/virtual-arm/build-environments.sh TARGET /workspace/work/arm-virtualization/cache`; `build-armv5-sections.log`, `build-armv7-sections.log`, `build-armv8-sections.log` | PASS, exit 0; all native assets rebuilt at the final builder fingerprint. |
| For each target: `sh tools/test-virtual-arm.sh --features all --architectures TARGET --cache /workspace/work/arm-virtualization/cache --output /workspace/work/arm-virtualization/final-TARGET-sections --defer-acceptance` | PASS, exit 0; 118/118 per target, 354 executions total. Per-target diagnostics deliberately retain `unblocks: false`. Evidence, environment, scenario logs and token-bound serial logs are under `final-armv5-sections/armv5`, `final-armv7-sections/armv7`, `final-armv8-sections/armv8`. |
| `python3 tools/virtual-arm/check-evidence.py --features all --architectures armv5,armv7,armv8 --summary /workspace/work/arm-virtualization/final-acceptance.json` followed by the three final `evidence.json` paths | PASS, exit 0; `status: pass`, `unblocks: true`. Unblocked groups: hooks, transactions, topology, dns, lifecycle, locks, cache, settings, ipset, integrity and native_dns. Physical release acceptance is unchanged. |
| `TEST_MAX_RUNTIME_SECONDS=600 SERVICE_LIFECYCLE_MAX_RUNTIME_SECONDS=5160 sh tools/code-quality.sh` in the isolated validation container; `canonical-final-sections.log` | PASS, exit 0; full real-helper regressions and 28-group lifecycle integration, evidence-policy/runner/DNS-parser checks, shell syntax, portability, warning-profile ShellCheck, shfmt, checksums and release consistency. UID 0, read-only source, no network; image `sha256:6bac2fcd6a3694b3c32f4a4c0f917314fef56b902c5666e4a37f80d32529c7ec`. |
| `python3 tests/virtual-arm-evidence.py`; `python3 tests/virtual-arm-dns-query.py`; `actionlint -shellcheck= -pyflakes=`; staged diff whitespace check excluding the nested BusyBox patch's required context prefixes | PASS, exit 0; 21 evidence-policy tests and 96 UDP/TCP A/AAAA/PTR parser cases. The nested patch is validated by all three successful builds. Synthetic policy and host parser results are not native feature evidence. |

Native beta, edge and stable binaries execute and validate configurations on each target. The stable binary alone supplies actual service lifecycle, API, UDP/TCP DNS, listener ownership, cache/restart, native resolver recovery and foreign-DNS-owner refusal coverage. Fixture groups execute real helpers while modeling firmware inputs. Even the native group models nvram/service/cru/SDN commands. These results do not establish ASUS firmware dispatch, physical DHCP/client isolation, Merlin kernel/libc equivalence, persistent reboot behavior, WAN exposure or overnight soak.

Discovered product correction: resolver mount detection used optional `df -h`, which failed with the limited native BusyBox configuration. It now uses portable `df -P`; the limited-applet mounted/unmounted regression passes. Final manager MD5: `e167596847bc328fcf710de561ab89da`; SHA-256: `b0d4cee4f89cf915cfb50656c26833f7344a7bec83db810706aa78c7e6961235`.

Fixture/infrastructure corrections preserve success/failure assertions: scoped IPSET fixture variables avoid ash local-variable shadowing; unsupported find pruning and fractional waits were replaced; service-stop contention uses an explicit handshake; cancelled watchdog sleep cannot fall through to a false timeout. RT-AC68U-class boot required the VExpress SYSREG/clock providers and compatibility time configuration; the mandatory DTB and actual no-FPU boot state are now verified. The DNS assertion previously accepted a matching record before checking later truncated answer/authority/additional records; it now validates all declared sections and matches only an answer record. The baseline section test produced 36 false passes; the corrected 96-case regression and final native DNS cases pass.

An intermediate full matrix at digest `191bcb58…` failed cache serialization on all three targets (117/118 each): a fixture-only retry reduction expired before its intentionally delayed mount. Normal production retry budgets are now unchanged; only the explicit timeout scenario uses a separately bounded helper copy. The complete final matrix above passes cache serialization and all other scenarios on every target. Intermediate, partial, cancelled or stale runs are not acceptance evidence. Hosted execution/review of the newly published source remains pending; historical CodeRabbit approval does not approve these new inputs.

### ARM hosted/review follow-up — October 8, 2026 America/New_York

TASK-021 continues verification after the original native ARM record. At published source `62c6143`, pull-request workflow `37862312200` passed armv5/armv8 but armv7 exited 1 in the initial cache-serialization pair; aggregate acceptance `113604910110` correctly failed. The same source's push workflow `37862307788` passed all three targets and aggregate acceptance. The failed fixture emitted no per-worker diagnostic, so the exact instruction in that historical run is unavailable.

A controlled actual-helper reproduction explains a reachable early exit: `sync` releases the resolver lock before full readiness, and two nonblocking service-activity probes may overlap on service descriptor 9. One correctly reports busy, violating the fixture's assumption that both initial callers must always succeed. That initial case now models an inactive service to isolate resolver-lock serialization and still requires both workers to succeed and exactly one mount. Later phases remove that override and retain the real held-descriptor, detached-service and failure/cleanup guard assertions. Production service detection and normal lock retry budgets are unchanged.

Three confirmed review corrections are included: required BusyBox configuration rejects missing `FLOCK` or `USLEEP`; DNS compression pointers must reference an earlier label at every traversal hop; malformed guest `END` fields are validated before log-stream removal, and cleanup continues through stream/container-removal faults. Baseline tests reproduced six UDP/TCP DNS false passes and malformed-result `KeyError` with a leaked real child process. The corrected parser passes 110 response cases; runner regressions check malformed/empty/negative/oversized numbers, retained logs, real child reap/pipe closure and container cleanup. Independent review found no remaining concrete runner defect.

Final input digest for this follow-up: `e1585f14cb8cfab1cc3bac302b631b16c6115129c821f97f3f7ef4e1eb416270`; builder fingerprint: `f328d35447979db60ce381808cba41d6ca39eb0776f008e3581830cfd26aa9a6`. All three rebuilt environments exit 0 (`review-build-armv5.log`, `review-build-armv7.log`, `review-build-armv8.log`). Complete final native runs and canonical host verification are in progress under `review-final-armv5`, `review-final-armv7`, `review-final-armv8` and `review-canonical-final.log`; no new complete-matrix or hosted acceptance result is claimed by this pending record. Physical release acceptance remains separate and BLOCKED.

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
| RT-AC68U-01 | ASUS RT-AC68U / unassigned firmware | ARMv7 Cortex-A9 / unrecorded | Unrecorded | Unrecorded | Unrecorded | Unassigned | BLOCKED — reproduction hardware not assigned |
| REPORT-01 | Originally affected model/firmware, if available | Unrecorded | Unrecorded | v2.6.5/v2.6.6 report | Unrecorded | Unassigned | BLOCKED — reproduction hardware not assigned |

| Required coverage | Status | Evidence / disposition |
|---|---|---|
| Supported current firmware on ARMv7 and ARMv8 | BLOCKED | No physical-router result recorded. |
| Older supported firmware, where practical | BLOCKED | Select firmware or record an explicit coverage disposition. |
| Older RT-AC68U-class ARMv7 physical test or maintainer waiver | BLOCKED | No result or waiver recorded; the virtual `armv5` package-target result is not a physical-router result. |
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
| Final candidate local software checks and both manifests | PASS | Final content digest `08a676a9…`; full local quality exits 0 and all 354 native ARM feature executions pass; exact commands and corrected diagnostic limitations recorded above. |
| Selected virtual feature/change contracts | PASS — unblocked | Complete three-target aggregate gate returns `unblocks: true` for all 11 covered groups at the final content digest. Physical rows do not block that scoped result. |
| Version/banner/manifests agree | PASS | Banner and AI_VERSION are v2.6.7; both runtime MD5/SHA-256 sidecars agree. |
| Hosted required checks and reviews at the published PR head | PENDING for new ARM-suite source | Historical `b31385a` workflows/CodeRabbit passed; the new published head requires its own inspection. No current-head hosted pass is inferred from local results. |
| Fresh, legacy, v2.6.5 and v2.6.6 upgrade coverage | BLOCKED | Hardware execution required. |
| Reported corrupt hook repair and firmware invocation | BLOCKED | Hardware execution required. |
| Client DHCP/local/reverse DNS and network isolation | BLOCKED | Hardware execution required. |
| Cache, supported IPv6, SDN and intended WAN exposure | BLOCKED | Hardware execution or justified applicability disposition required. |
| Both lock backends and monitor failure recovery | BLOCKED | Hardware execution required. |
| Reboot, interruption and uninstall recovery | BLOCKED | Hardware execution required. |
| Overnight soak and all failure dispositions | BLOCKED | No soak or physical-router result recorded. |

**v2.6.7 physical-router release acceptance remains BLOCKED.** Software implementation may proceed and a development candidate may be reviewed while this evidence is pending; this document is not release approval.
