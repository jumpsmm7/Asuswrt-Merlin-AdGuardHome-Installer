# v2.7.0 candidate acceptance checklist

## Candidate and decision record

**Target version: v2.7.0-rc.1. Final candidate qualification: NOT RUN. Physical acceptance and soak: NOT RUN.**

This is a preparation record for the opt-in development candidate on `feat/v2.7.0-completion`. It does not announce a published tag or release. Freeze and identify the assembled source before executing these rows; subsequent changes to tested inputs require matching new evidence. Follow the [accepted scope](docs/v2.7.0-plan.md) and [candidate operator guide](docs/v2.7.0-candidate-testing.md).

Use **NOT RUN** for unexecuted work, **PASS** or **FAIL** for observed outcomes, **BLOCKED** for an attempted run that cannot proceed, and **NOT APPLICABLE** only with a specific reason. Mandatory unexecuted or unresolved rows prevent whole-release acceptance. A passing covered virtual contract remains independently accepted while physical rows are pending. Do not infer a hardware pass from host or virtual results.

| Identity / disposition | Candidate record |
|---|---|
| Installer version / banner / installed AI_VERSION | Target `v2.7.0-rc.1`; actual agreement NOT RECORDED |
| Published installer ref and resolved full commit SHA | NOT RECORDED; development branch is not an immutable evidence identity |
| Tested source/content digest and builder fingerprint | NOT RECORDED |
| Installer SHA-256 / MD5 and matching sidecars | NOT RECORDED |
| AdGuardHome.sh SHA-256 / MD5 | NOT RECORDED |
| S99AdGuardHome SHA-256 / MD5 | NOT RECORDED |
| rc.func.AdGuardHome SHA-256 / MD5 | NOT RECORDED |
| Architecture archive/channel versions and checksums | NOT RECORDED for each armv5 / armv7 / armv8 and stable / beta / edge entry |
| Host image digest, UID, shell/BusyBox/lint versions | NOT RECORDED |
| Current-head hosted check URLs / completion times / review disposition | NOT RECORDED |
| Software qualification / operator / timestamp with timezone | NOT RUN / NOT RECORDED / NOT RECORDED |
| Physical qualification / operator / timestamp with timezone | NOT RUN / NOT RECORDED / NOT RECORDED |
| Release publication decision | NOT MADE; no merge, tag or publication is implied by this checklist |

Preserve the operator-reported v2.6.7 physical **PASS** in [its historical checklist](RELEASE-2.6.7-CHECKLIST.md): RT-AC5300 / 386.14_2 and GT-BE98PRO / 3006.102.9 had explicit full-checklist/48-hour confirmation; RT-AC68U / 386.14_2 had additional reported testing without separate duration detail. Those firmware versions and outcomes are historical. Record the firmware actually observed for each new candidate run; no firmware upgrade is part of this plan.

## Software qualification

For every row record: full tested candidate SHA/content digest; exact command and arguments; environment; preconditions; expected and actual behavior; start/end timestamps with timezone; exit status; sanitized evidence/log ID; recovery result; issue/fix and retest identity. Preserve failed logs and identify any modeled firmware inputs. These rows deliberately contain no final-candidate pass claims.

| ID | Required candidate behavior / evidence | Status | Evidence / recovery / retest |
|---|---|---|---|
| SW-01 | Banner and AI_VERSION agree exactly, including RC suffix. Local/remote/staged installer parsing accepts the same bounded version grammar. Full version identity distinguishes RC from stable and other RC numbers. | NOT RUN | NOT RECORDED |
| SW-02 | `sh tools/check-release-consistency.sh` passes with refreshed MD5/SHA-256 sidecars; channel archives, architecture metadata, cross-architecture versions and stale-manifest enforcement remain valid. | NOT RUN | NOT RECORDED |
| SW-03 | Isolated canonical `sh tools/code-quality.sh`, applicable coverage and current-head hosted checks/reviews pass; unresolved genuine blockers are addressed. Record actual source/check IDs and tool versions. | NOT RUN | NOT RECORDED |
| SW-04 | Fresh interactive installation completes on supported topology. Flagged unattended fresh install refuses before ordinary setup writes/downloads; separately required prior recovery is reported. | NOT RUN | NOT RECORDED |
| SW-05 | v2.6.7 upgrades while running and stopped preserve settings, channel, working service state and shared hooks. Supported v2.6.0-or-earlier, v2.6.5 and v2.6.6 migration paths remain covered. | NOT RUN | NOT RECORDED |
| SW-06 | Explicit/saved installer refs survive checks/re-exec; unsafe/unavailable refs fail. `--no-auto-update` preserves the matching component bundle and refuses incompatible bundle-changing actions without a checksum bypass. Installer ref and AGH channel remain independent. | NOT RUN | NOT RECORDED |
| SW-07 | JFFS read/format/lock/storage failures have accurate stages; ready settings avoid unnecessary writes. Initially absent action dependencies are repaired only at the appropriate authorized boundary with functional recheck. | NOT RUN | NOT RECORDED |
| SW-08 | Main/enabled SDN takeover removes exact rebind/DNSSEC options, keys and effective references; mixed/nested includes preserve unrelated settings and persistent sources. Repetition, overlap, refusal and native recovery preserve valid references and configuration. | NOT RUN | NOT RECORDED |
| SW-09 | #1041: refresh/publication/interruption plus failed IPSet restoration retains the needed dnsmasq backup; actual recovery succeeds after faults clear. Successful restoration and cleanup-only failures do not retain unnecessary backups. | NOT RUN | NOT RECORDED |
| SW-10 | #1039: inspect/reproduce exact stop-window download ordering. Verified required artifacts are ready before DNS is stopped; failed fetch/verification leaves prior service usable and performs no destructive partial publication. Record the demonstrated correction and boundaries. | NOT RUN | NOT RECORDED |
| SW-11 | Opt-in `sh installer support-export --output /absolute/report.txt` is bounded and allowlisted; secret/malicious fixtures, unavailable/full/read-only storage and unsafe paths are handled. No automatic upload or new setup/service/DNS/NVRAM/firewall changes; prior transaction recovery is separately reported. | NOT RUN | NOT RECORDED |
| SW-12 | Missing/delayed Entware/USB, failed download/extraction/write, full/read-only storage and interruption preserve the previous working state or report actionable recovery. Resource claims distinguish actual process/filesystem tests from modeled firmware and physical limits. | NOT RUN | NOT RECORDED |
| SW-13 | Repeated update/repair, validated backup/restore and uninstall preserve preferences/shared content, avoid duplicate hooks/cron/firewall rules, and restore native or previous working DNS. Interrupted operations retain safe retryable recovery state. | NOT RUN | NOT RECORDED |
| SW-14 | All selected changed contracts have fresh matching armv5/armv7/armv8 reports and aggregate acceptance against frozen candidate/build inputs. No skipped/failed/stale execution becomes acceptance. | NOT RUN | NOT RECORDED |

Record each actually exercised channel lifecycle below, including archive version/hash, architecture, scenario selection/count, listener ownership, TCP/UDP DNS, applicable local A/PTR, restart, stop, recovery and conflict handling. `stable` is the archive label for CLI channel `release`. Execution/config-only checks do not establish lifecycle parity. The armv5 package target represents older ARMv7 Cortex-A9 software float, not a physical ARMv5 router.

| AGH CLI channel / archive label | armv5 | armv7 | armv8 | Exact candidate / archive versions / reports |
|---|---|---|---|---|
| release / stable | NOT RUN | NOT RUN | NOT RUN | NOT RECORDED |
| beta / beta | NOT RUN | NOT RUN | NOT RUN | NOT RECORDED |
| edge / edge | NOT RUN | NOT RUN | NOT RUN | NOT RECORDED |

## Physical inventory and per-run identity

Use test hardware in a maintenance window with console/SSH access, a validated pre-upgrade backup and a recovery path. Controlled interruption/storage/lock tests must not target valuable files or unrelated services. No router command here requires host-only Python, GNU timeout, QEMU or Docker.

| Router ID | Model / architecture | Actual observed firmware / BusyBox | Deployed commit / script hashes | Topology / SDNs / channel / cache | Operator / start / end with timezone | Status |
|---|---|---|---|---|---|---|
| AC68U-270 | RT-AC68U / older ARMv7 | NOT RECORDED | NOT RECORDED | NOT RECORDED | NOT RECORDED | NOT RUN |
| AC5300-270 | RT-AC5300 / ARMv7 | NOT RECORDED | NOT RECORDED | NOT RECORDED | NOT RECORDED | NOT RUN |
| BE98PRO-270 | GT-BE98PRO / AArch64 | NOT RECORDED | NOT RECORDED | NOT RECORDED | NOT RECORDED | NOT RUN |

For each run also record initial installer/AGH version and archive hash, Entware mount/provider state, available storage/swap, WAN/LAN/AP/bridge mode, qualifying WAN-interface NAT when applicable, supported SDN capability, network/client labels, IPv4/IPv6, expected WAN exposure, configured DNS/filter preferences, lock backend and cache setting. Retain before/after process/listener ownership, hook interpreter/mode and sanitized event logs. Store private backup/configuration separately; no raw NVRAM/YAML dumps, credentials, query history or identifying client/address data belong in shared evidence.

## Physical scenarios

Execute applicable rows on each listed router and each enabled LAN/SDN/legacy guest network. A result must identify router ID, deployed candidate and actual firmware; split per-network observations when outcomes differ. Use actual clients for DHCP, resolution and isolation checks. While AGH owns DNS, verify intended TCP/UDP port 53 listeners and managed dnsmasq port 553; after recovery verify native port 53 and the router resolver path.

| ID | Scenario / required observation | Status | Router/network / timestamps / evidence / recovery |
|---|---|---|---|
| PH-01 | Fresh interactive install; v2.6.7 running/stopped upgrade; applicable supported legacy migration. Preserve settings/shared hooks and prevent duplicate managed state. | NOT RUN | NOT RECORDED |
| PH-02 | Firmware-dispatched main/SDN dnsmasq restart, AGH restart/failure and repeated service events restore ownership/listeners without port conflicts. | NOT RUN | NOT RECORDED |
| PH-03 | Cold boot with actual Entware/USB availability; missing/delayed mount and supported recovery; installed hooks/persistence work. | NOT RUN | NOT RECORDED |
| PH-04 | Actual client DHCP new lease, renewal, expiry/reacquisition; correct DNS delivery on every enabled network. | NOT RUN | NOT RECORDED |
| PH-05 | External TCP/UDP DNS plus local A/PTR through the intended main/SDN upstream; supported SDN enable/disable and legacy guest behavior. | NOT RUN | NOT RECORDED |
| PH-06 | Guest-to-LAN/inter-network isolation, WAN and LAN/AP/bridge topology, with/without qualifying WAN-interface NAT as applicable. Unsupported topology combinations get an explicit disposition. | NOT RUN | NOT RECORDED |
| PH-07 | Cache off/on and supported IPv6 RA/DHCPv6, listeners and external/local/reverse client DNS across restart/stop/failure. | NOT RUN | NOT RECORDED |
| PH-08 | Firmware rebind/DNSSEC preferences remain persistent; takeover filtering is effective and stop/failure/native regeneration restores the user's selected native behavior. | NOT RUN | NOT RECORDED |
| PH-09 | Slow filter startup, DNS/WAN outage, failed update/download, resource/storage pressure and controlled interruption recover with actionable status. Physical memory/USB reliability is recorded as observed, without speculative tuning claims. | NOT RUN | NOT RECORDED |
| PH-10 | Descriptor lock and supported mkdir/PID fallback; concurrent start/stop, stale identity and failed cleanup preserve ownership and bounded recovery. | NOT RUN | NOT RECORDED |
| PH-11 | Validated backup/restore, required rollback test, shutdown and uninstall restore intended native DNS; unrelated hooks/preferences survive. | NOT RUN | NOT RECORDED |
| PH-12 | Intended WAN IPv4/IPv6 TCP/UDP DNS exposure matches policy when tested from an external vantage; no unintended exposure or firewall bypass. | NOT RUN | NOT RECORDED |

## Final-candidate soak and event log

Run at least 48 elapsed hours spanning two overnight maintenance periods on ARMv7 and AArch64. Include RT-AC68U coverage and record its actual duration/checklist separately. Start each soak after deploying and verifying the final candidate identity; changes invalidate reuse for changed contracts. Record scheduled/actual cron, filter/update, DHCP, service and WAN events and their recovery outcomes. Elapsed time alone does not demonstrate those events occurred.

| Router / coverage | Candidate / actual firmware / topology / channel / cache | Start / end with timezone | Actual elapsed duration | Scheduled and observed event evidence | Result |
|---|---|---|---|---|---|
| RT-AC5300 / ARMv7 48-hour soak | NOT RECORDED | NOT RECORDED | NOT RECORDED | NOT RECORDED | NOT RUN |
| GT-BE98PRO / AArch64 48-hour soak | NOT RECORDED | NOT RECORDED | NOT RECORDED | NOT RECORDED | NOT RUN |
| RT-AC68U / older ARMv7 coverage | NOT RECORDED | NOT RECORDED | NOT RECORDED | NOT RECORDED | NOT RUN |

Copy this event row per actual observation; do not substitute the report date for event times:

| Evidence ID / router / exact candidate | Scheduled / actual timestamp with timezone | Event / client-network label | Expected / observed DNS-DHCP-service state | Recovery / issue / retest identity | Result |
|---|---|---|---|---|---|
| NOT RECORDED | NOT RECORDED | NOT EXECUTED | NOT RECORDED | NOT RECORDED | NOT RUN |

## Final disposition

- [ ] Candidate identity, versions, all checksums and release notes agree with the tested published source.
- [ ] Required software rows, matching native aggregate and current-head checks/reviews have recorded satisfactory results or an explicit permitted disposition.
- [ ] Applicable physical rows and required soak have candidate-specific operator evidence, including actual firmware and older-router coverage.
- [ ] Failed runs and recovery/retest outcomes are retained; remaining limitations and downgrade compatibility are documented.
- [ ] Maintainer records the separate release decision and timestamp. No publication is performed by completing this document.
