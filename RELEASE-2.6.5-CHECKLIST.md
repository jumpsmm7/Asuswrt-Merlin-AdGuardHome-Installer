# v2.6.5 real-router acceptance checklist

## Record status

**Release disposition: BLOCKED — real-router execution required.**

This checklist was created on 2026-08-22 UTC in the repository validation container. That environment has no supported Asuswrt-Merlin router, router firmware, Entware installation, or safe access to router NVRAM, DNS, firewall, IPSET, reboot, and service lifecycle state. Consequently, no hardware result below is represented as executed. Mandatory scenarios remain **BLOCKED** until an operator runs them on the recorded hardware and replaces each placeholder with sanitized evidence.

Allowed result values are **PASS**, **FAIL**, **BLOCKED**, and **NOT APPLICABLE**. A release must not be approved while any mandatory row is BLOCKED or while a FAIL lacks a fix, accepted limitation, or explicit release-blocking disposition.

## Evidence safety rules

Never commit passwords, password hashes, tokens, private keys, full NVRAM dumps, full AdGuard Home YAML, public IP addresses, client MAC addresses, personal DNS query logs, or other identifying client data. Record only the minimum lines needed to prove the expected result. Replace sensitive values with stable labels such as `<PUBLIC-IP-REDACTED>` or `<CLIENT-REDACTED>` before committing evidence.

Checksum verification and TLS certificate verification are separate safeguards. Do not describe an artifact as verified unless the applicable checksum path and transport behavior were both observed.

Do not run `nvram commit` to collect evidence. Do not use `realpath`, `timeout`, Perl, or Python on the router.

## Hardware inventory and coverage

Complete one row per physical router before scenario execution.

| Router ID | Model | Firmware | CPU architecture | BusyBox | Entware | Initial installer | Initial AdGuard Home / channel | Initial mode | IPv4 | IPv6 | dnsmasq | IPSET | Operator | UTC date/time | Result / waiver |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ARMV7-01 | `<required>` | `<required>` | ARMv7 | `<required>` | `<required>` | v2.6.1 | `<required>` | `<required>` | `<required>` | `<required>` | `<required>` | `<required>` | `<required>` | `<required>` | **BLOCKED — no ARMv7 router connected** |
| ARMV8-01 | `<required>` | `<required>` | ARMv8/aarch64 | `<required>` | `<required>` | v2.6.1 | `<required>` | `<required>` | `<required>` | `<required>` | `<required>` | `<required>` | `<required>` | `<required>` | **BLOCKED — no ARMv8 router connected** |
| ARMV5-01 | `<if available>` | `<if available>` | ARMv5 | `<required if tested>` | `<required if tested>` | `<required>` | `<required>` | `<required>` | `<required>` | `<required>` | `<required>` | `<required>` | `<required>` | `<required>` | **BLOCKED — hardware availability unknown; waiver requires maintainer approval** |

Required cross-hardware coverage:

| Coverage item | Router ID | Status | Sanitized evidence / waiver |
|---|---|---|---|
| Current supported Asuswrt-Merlin release | `<assign>` | BLOCKED | No router access in validation container. |
| Older supported firmware, where practical | `<assign>` | BLOCKED | Select firmware and document practicality before release. |
| Usable descriptor-lock `flock` | `<assign>` | BLOCKED | Record capability-probe result; do not infer from binary presence alone. |
| mkdir/PID fallback (native or controlled override) | `<assign>` | BLOCKED | Record the compatibility override and bounded cleanup evidence. |
| ARMv5 test or approved waiver | ARMV5-01 | BLOCKED | No hardware result and no waiver approval recorded. |

## Scenario record format

Every executed row must retain these fields. If detailed evidence is too large for the table, add a sanitized subsection below the table and reference its evidence ID.

| Field | Required entry |
|---|---|
| Scenario name | Stable scenario name from this document. |
| Preconditions | Router ID, versions, mode, network, service, and feature state. |
| Expected result | Concrete state transition or safe failure. |
| Observed result | What actually occurred; never copy secrets or full configuration. |
| Status | PASS, FAIL, BLOCKED, or NOT APPLICABLE. |
| Recovery result | Complete, partial, failed, not required, or not executed. |
| Sanitized evidence | Minimal command output or evidence ID. |
| Related issue | Issue URL/ID or `none`. |
| Fix commit | Commit hash or `none`. |
| Retest result | Status, router ID, and UTC timestamp. |

All unexecuted rows below have common evidence: **“Not executed: repository validation container has no Asuswrt-Merlin router access.”** Their fix commit and retest result are `none / not executed`.

## Fresh installation

Expected results for every applicable fresh-install row: correct persisted mode; correct WebUI and DNS binds; correct hooks; correct IPv4/IPv6 firewall state; correct IPSET policy; bounded readiness or failure; no stale lock or DNS handoff marker; and no unexpected NVRAM commit.

| Scenario | Preconditions | Expected result | Observed result | Status | Recovery | Evidence | Issue / fix / retest |
|---|---|---|---|---|---|---|---|
| Fresh WAN/router mode | AdGuard Home absent; dnsmasq running | WAN policy installed and service ready | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Fresh AP/LAN mode | AdGuard Home absent; confirmed AP mode | LAN binds and LAN policy installed | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Fresh repeater/media bridge | Supported model and mode | Detected mode applied without WAN-only exposure | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Fresh IPv4-only | IPv6 disabled | IPv4 succeeds without IPv6 residue | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Fresh dual stack | Working IPv4 and IPv6 | Both families use intended binds/rules | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| LAN with dnsmasq initially stopped | Confirmed LAN mode | Prior DNS/service state handled safely | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Offline fresh-install attempt | AdGuard Home absent; WAN disconnected | Bounded failure; no partial install | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |

## Upgrade from v2.6.1 to v2.6.5

Expected results: user configuration remains intact; no unintended mode migration; no duplicate hooks, firewall rules, cron jobs, or config keys; prior service state is preserved; runtime files and manifests update; and migration artifacts are absent after success.

| Scenario | Preconditions | Expected result | Observed result | Status | Recovery | Evidence | Issue / fix / retest |
|---|---|---|---|---|---|---|---|
| WAN to WAN upgrade | v2.6.1 WAN installation | Remains WAN without duplicates | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| LAN to LAN upgrade | v2.6.1 LAN installation | Remains LAN without duplicates | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Custom WebUI port | Non-default valid port | Port remains unchanged and ready | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Custom YAML | Sanitized custom keys present | User keys remain intact | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Custom hook content | Unrelated hook lines present | Unrelated lines remain exactly once | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Existing IPSET state | Managed IPSET enabled/disabled | Current mode policy applied without unrelated loss | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Existing runtime profile | Non-default supported profile | Profile remains intact | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Initially running | Service running before upgrade | Running state restored | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Initially stopped | Service stopped before upgrade | Stopped state preserved | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |

## Mode migration

For each row compare sanitized summaries of active YAML, original YAML snapshot, reverse upstream, DNS bind hosts, IPSET, IPv4/IPv6 firewall state, event hooks, dnsmasq, AdGuard Home, and recovery artifacts.

| Scenario | Preconditions | Expected result | Observed result | Status | Recovery | Evidence | Issue / fix / retest |
|---|---|---|---|---|---|---|---|
| WAN to LAN/AP | Confirmed mode change | Transactional LAN policy; prior state restored on failure | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| LAN/AP to WAN | Confirmed mode change | WAN hooks precede persistence; WAN policy restored | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Unknown/unreadable `sw_mode` | Persisted mode exists | Byte-identical no-op; no restart/commit/snapshot | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| LAN IP temporarily unavailable | Confirmed LAN; address unavailable | Bounded safe failure with prior state retained | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Mode change while running | AdGuard Home running | Prior running state restored after migration | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Mode change while stopped | AdGuard Home stopped | Service remains stopped after migration | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |

## TERM interruption

Expected results: bounded completion; DNS restoration when rollback succeeds; no stale live-owner lock or active handoff marker; incomplete rollback evidence retained; rerun diagnoses or recovers state; and read-only diagnosis performs no NVRAM commit.

| Interruption point | Preconditions | Expected result | Observed result | Status | Recovery | Evidence | Issue / fix / retest |
|---|---|---|---|---|---|---|---|
| Download | Active prior installation | Prior install runnable | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Archive staging | Download complete | Staged artifact removed or retained safely | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| YAML migration | Pending mode migration | YAML rollback is atomic | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Hook migration | Hook snapshot present | Hook contents/modes restored | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| NVRAM transaction | Transaction lock active | Persisted state restored without extra commit | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Service stop | Service initially running | DNS and prior service state restored | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| DNS handoff | Handoff active | Marker/guard removed; dnsmasq restored | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Startup readiness | Process launched | Failed start rolls back safely | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Final cleanup | Operation otherwise complete | No stale live evidence; retained recovery if incomplete | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |

## Offline and degraded network

Expected results: every wait is bounded; intentional MD5 compatibility is distinct; SHA-256 mismatch never downgrades; unverified artifacts are never installed; and the prior installation remains runnable.

| Scenario | Preconditions | Expected result | Observed result | Status | Recovery | Evidence | Issue / fix / retest |
|---|---|---|---|---|---|---|---|
| WAN disconnected | Existing installation | Bounded failure; local service retained | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| DNS unavailable, IP available | Direct connectivity available | Bounded DNS-specific failure | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| HTTP unavailable | DNS available | Bounded transport failure | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| GitHub unavailable | Other network available | Cache/fallback policy behaves as documented | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Incorrect system clock | TLS validation affected | Fail closed without insecure publication | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| TLS certificate failure | Invalid certificate path | Verified transport attempted first; safe bounded failure/fallback | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| SHA-256 unavailable, valid MD5 | Valid MD5 metadata/digest | Intentional legacy-compatible path succeeds and logs distinctly | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| SHA-256 mismatch, valid MD5 present | Mismatching SHA-256 | Retry/fail without MD5 downgrade | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Both checksum routes unavailable | No usable metadata/calculator | Artifact rejected | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Partial download | Truncated transport | Partial artifact rejected and removed | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Corrupt archive | Matching transport but invalid archive | Archive rejected before replacement | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |

## Service failures

Expected results: unknown owners fail closed; unrelated processes survive; dnsmasq is restored where required; stop/restart returns meaningful failure; and offline WAN does not invalidate successful local DNS restoration.

| Scenario | Preconditions | Expected result | Observed result | Status | Recovery | Evidence | Issue / fix / retest |
|---|---|---|---|---|---|---|---|
| AdGuard Home exits immediately | Launch requested | Start fails and DNS recovers | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| TCP 53 missing | Process alive | Readiness fails closed | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| UDP 53 missing | Process alive | Readiness fails closed | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| WebUI port unavailable | DNS sockets present | Startup rejected/rolled back | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Foreign DNS owner | Port held by unrelated process | No unrelated kill; fail closed | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Ownerless BusyBox netstat | Owner unavailable | Unknown owner policy applied safely | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Duplicate AdGuard Home processes | Multiple matching PIDs | Meaningful failure; no broad unsafe kill | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| dnsmasq refuses stop | Managed dnsmasq running | Start aborts and state is reported | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| dnsmasq refuses restart | Recovery required | Failure reported with recovery evidence | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| AdGuard Home ignores TERM/INT | Stuck process | Bounded escalation and meaningful status | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Monitor restart while unhealthy | Monitor request active | Serialized bounded restart behavior | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |

## Filesystem and resource failures

Expected results: foreign objects are not followed or removed; working files survive; optional DB links do not block startup; stale locks require identity validation; cleanup is bounded; and required evidence is retained.

| Scenario | Preconditions | Expected result | Observed result | Status | Recovery | Evidence | Issue / fix / retest |
|---|---|---|---|---|---|---|---|
| `/jffs` read-only | Safe test window | Bounded failure without partial hooks | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| `/opt` unavailable before install | Entware path absent | Clear preflight failure | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| `/opt` unavailable during service | Safely reproducible only | Service fails without corrupting router state | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| `/tmp` nearly full | Controlled capacity limit | Bounded staging failure | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Work directory nearly full | Controlled capacity limit | Existing files survive | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Pre-created temporary symlink | Foreign symlink at candidate path | Symlink not followed/removed | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Foreign-owned lock | Safe foreign UID fixture | Lock rejected and preserved | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Stale lock | Dead PID/start-time identity | Reaped only after identity validation | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Regular file at `/tmp/stats.db` | Foreign regular file | Optional DB handling does not block startup or delete it | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Low memory | Safely reproducible only | Bounded failure and retained working install | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |

## Downgrade and re-upgrade

Before downgrade preserve sanitized checks or hashes for `.config`, active YAML, original YAML, event scripts, firewall summary, runtime script versions, and service state. Do not commit their complete sensitive contents.

| Scenario | Preconditions | Expected result | Observed result | Status | Recovery | Evidence | Issue / fix / retest |
|---|---|---|---|---|---|---|---|
| v2.6.5 to selected prior known-good | Completed v2.6.5 acceptance state | Older release uses retained configuration; no artifact confusion; proc settings restore conservatively | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Re-upgrade to v2.6.5 | Downgrade completed | Upgrade remains possible and transactional | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |

Downgrade support is **not yet established**. If testing shows it cannot be supported safely, mark the downgrade row FAIL or BLOCKED, document downgrade as unsupported in release notes, and do not imply support.

## Uninstall and reboot

| Scenario | Preconditions | Expected result | Observed result | Status | Recovery | Evidence | Issue / fix / retest |
|---|---|---|---|---|---|---|---|
| Uninstall | Installed and running/stopped cases | AdGuard Home stops; dnsmasq resumes; only owned hook lines/rules/IPSET/proc state/DNS state are removed or restored | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Artifact audit | Uninstall completed | No owned cron, lock, marker, stage, rollback artifact, or optional symlink remains | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |
| Reboot recovery | Uninstall and artifact audit complete | Normal router DNS works after reboot | Not executed | BLOCKED | Not executed | Common blocked evidence | none / none / not executed |

## Sanitized evidence command set

Run only the commands needed for a scenario and redact output before committing it:

```sh
/bin/nvram get sw_mode
/bin/nvram get lan_ipaddr
/bin/nvram get ipv6_service
/usr/sbin/service status_AdGuardHome
/bin/pidof AdGuardHome
/bin/pidof dnsmasq
/bin/netstat -nlp
/usr/bin/logread
/usr/bin/find /jffs/scripts -maxdepth 1 -type f
/usr/sbin/iptables-save
/usr/sbin/ip6tables-save
```

`nvram`, `service`, `iptables-save`, and `ip6tables-save` are router-stock commands rather than generic BusyBox applets. Collecting evidence must not add an `nvram commit`, restart a service unnecessarily, expose public addresses, or capture unrelated client/query data.

## Release sign-off

| Requirement | Status | Evidence / disposition |
|---|---|---|
| ARMv7 recorded | BLOCKED | ARMV7-01 has no connected router result. |
| ARMv8 recorded | BLOCKED | ARMV8-01 has no connected router result. |
| ARMv5 tested or waived | BLOCKED | Neither execution nor approved waiver exists. |
| v2.6.1 upgrade recorded | BLOCKED | Hardware execution required. |
| Both mode directions recorded | BLOCKED | Hardware execution required. |
| Unknown mode recorded | BLOCKED | Hardware execution required. |
| TERM interruption recorded | BLOCKED | Hardware execution required. |
| Offline operation recorded | BLOCKED | Hardware execution required. |
| MD5 compatibility fallback recorded | BLOCKED | Hardware execution required. |
| SHA-256 mismatch/no downgrade recorded | BLOCKED | Hardware execution required. |
| Downgrade recorded or declared unsupported | BLOCKED | Decision requires hardware result. |
| Uninstall and reboot recorded | BLOCKED | Hardware execution required. |
| Every failure dispositioned | BLOCKED | No real-router scenarios have been executed. |

**Final v2.6.5 real-router acceptance: BLOCKED. Do not treat this document as release approval until the mandatory rows contain sanitized physical-router results.**
