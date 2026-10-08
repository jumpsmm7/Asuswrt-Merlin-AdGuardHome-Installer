# Virtual ARM feature tests

Run the installer and runtime feature regressions inside native ARM package targets on ARMv7 and ARMv8 Linux guests. These are full-system QEMU TCG machines with their own kernels, native BusyBox 1.25.1 applets and native external tools. They exercise real ARM instruction execution, `/proc`, signals, permissions, concurrency and sockets. They do not use a host shell disguised as an ARM environment.

Passing virtual tests **unblocks the selected feature assertions at the tested content digest**. Hardware acceptance for unrelated behavior does not block that feature decision. The result applies only to the scenarios and boundaries recorded in the manifest and report; it does not clear physical firmware or release checkpoints automatically.

## Run locally

The validation host needs Docker, Python 3, curl and SHA-256 tooling. The isolated builder provides cross-compilers, QEMU, build utilities and native guest packages. Its base image, Linux 6.1.157 and BusyBox 1.25.1 source archives are pinned; source checksums are verified before compilation. Initial provisioning downloads sources and packages. Guests run without external networking and receive read-only candidate sources; fixture state stays inside their disposable initramfs.

From the repository root:

```sh
# Build reusable native environments. Keep build assets outside the tested source directories.
sh tools/virtual-arm/build-environments.sh armv5 ../work/virtual-arm-cache
sh tools/virtual-arm/build-environments.sh armv7 ../work/virtual-arm-cache
sh tools/virtual-arm/build-environments.sh armv8 ../work/virtual-arm-cache

# Run all declared feature contracts on all three architectures.
sh tools/test-virtual-arm.sh \
  --cache ../work/virtual-arm-cache \
  --output ../work/virtual-arm-results

# Run only the hooks, locks and shutdown feature contracts on all architectures.
sh tools/test-virtual-arm.sh \
  --features hooks,locks,lifecycle \
  --architectures armv5,armv7,armv8 \
  --cache ../work/virtual-arm-cache \
  --output ../work/virtual-arm-repair-results

# Recheck saved artifacts against the current tested candidate content.
python3 tools/virtual-arm/check-evidence.py \
  --features hooks,locks,lifecycle \
  --architectures armv5,armv7,armv8 \
  ../work/virtual-arm-repair-results
```

A single-architecture diagnostic run uses `--architectures armv5 --defer-acceptance`. It records execution and validates those artifacts with `unblocks: false`; it cannot satisfy feature acceptance. Aggregate reports from all three architectures with the same selected feature scope and tested content to obtain an acceptance decision. Empty, duplicate or unknown feature IDs are rejected.

Host verification tooling is separate. The DNS response-parser regression requires a host C compiler (`build-essential` on Debian/Ubuntu):

```sh
python3 tests/virtual-arm-evidence.py
python3 tests/virtual-arm-dns-query.py
python3 tools/virtual-arm/check-evidence.py --select --features all
python3 tools/virtual-arm/check-evidence.py --content-digest
```

The evidence-policy regression uses explicitly synthetic records to prove rejection rules. Its success is not a native ARM feature result.

## Environment matrix

The target names below preserve the installer's archive routing names. They are not CPU generation names. The `armv5` row models the older ASUS RT-AC68U: its archive is the armv5 compatibility package, while the actual router-class CPU and guest are ARMv7 Cortex-A9. It has no hard-float option; the guest explicitly disables VFP and NEON and uses the software-float armel ABI. The newer `armv7` row is the separate Cortex-A15 hard-float environment.

| Target (package/archive) | Router-class guest CPU | QEMU machine / CPU options | Native ABI | Guest `uname -m` |
|---|---|---|---|---|
| armv5 archive (RT-AC68U) | ARMv7 Cortex-A9, older generation | `vexpress-a9` / `cortex-a9,vfp=off,neon=off` | armel software float; no VFP/NEON | `armv7l` |
| armv7 archive | ARMv7 Cortex-A15, newer generation | `virt` / `cortex-a15` | armhf hard float; VFPv3-D16 and NEON | `armv7l` |
| armv8 archive | ARMv8-A Cortex-A53 | `virt` / `cortex-a53` | AArch64 AAPCS64 | `aarch64` |

`environment.json` records the archive/package target separately from the actual CPU ISA, float ABI, FPU policy, router-class model, machine/options, actual kernel release and kernel/source/config hashes, BusyBox/source/config hashes, compiler target/flags/version, native package versions/source hashes, native executable identities, rootfs fingerprint and build-source fingerprint. The runner verifies cached artifact identities before launching, then requires a matching architecture/kernel/BusyBox boot record and a per-run token. The guest smoke check also rejects an armv5 run whose ARMv7 kernel exposes VFP or NEON. The virtual Linux kernel and Debian guest libc are recorded validation environments; they do not establish equivalence to every supported Merlin kernel or uClibc build.

## Selected feature contracts

[features.tsv](../tools/virtual-arm/features.tsv) defines each required scenario, exact test path, evidence class, assertions and exclusions. All listed scenarios for a selected feature must pass on all three architectures. The broad groups cover most functional installer/runtime regressions; lint, provider configuration and host package-conversion checks remain in the canonical host quality suite.

| Feature ID | Covered assertions |
|---|---|
| hooks | Managed first-line interpreter/mode/idempotence, shared content preservation, aggregate hook rollback and safe doctor diagnosis/repair |
| transactions | Install/update/interruption state, owned rollback/cleanup, preference continuity and modeled uninstall recovery |
| topology | WAN/LAN/AP/Bridge selection, eligible WAN NAT, bind addresses and topology-aware policy |
| dns | Modeled main/SDN handoff, readiness, managed-owner detection, resolver selection and failure rollback |
| lifecycle | Start/stop/restart failure propagation, process identity, monitor/native-routing recovery and cancellation/expiry of suite watchdogs |
| locks | Private path safety, stable descriptor inode, fallback ownership/serialization, stale identity recovery and unsafe target preservation |
| cache | Readiness, serialized activation, native routing restoration and preference failure propagation |
| settings | Scoped YAML/preferences, staged authentication, input validation, runtime defaults and permissions |
| ipset | Topology/version gates, modeled rule publication/cleanup, setup rollback and preference failures |
| integrity | Digest/output rejection, secure-download fallback decisions, path/dependency contracts and owned cleanup |
| native_dns | Native beta/edge/stable binary execution and configuration validation; stable AdGuardHome/dnsmasq lifecycle, real TCP/UDP local/forward/reverse DNS, listener ownership, actual current service helpers, restart, native resolver recovery and refusal of a foreign DNS owner |

The `fixture` class executes the real selected script helpers under the native CPU and shell while modeling dependencies such as `nvram`, firmware service dispatch, topology and socket enumeration where the existing test requires it. A group succeeds only when all named tests pass; the group assertions describe the union of those tests, not a claim that every individual test exercises every assertion.

The `native` class uses actual ARM AdGuardHome/dnsmasq processes and DNS exchanges, with modeled router `nvram`/`service`/`cru` dependencies declared. The default scenario executes the committed beta, edge and stable binaries and validates their configuration on each CPU; service startup/restart/cache/shutdown/conflict coverage uses the stable binary. These results do not credit beta/edge service lifecycle behavior. Real socket/query results establish those virtual Linux service behaviors. They do not establish a physical client's DHCP lease, firmware hook dispatcher, hardware bridge isolation, WAN exposure, reboot persistence or overnight maintenance behavior.

## Evidence and unblocking

Each architecture writes `evidence.json`, `environment.json`, scenario logs and the serial boot log under the selected output directory. The evidence schema records requested features, scenario selection digest, exact tested-content digest, provenance commit label, native environment identity, guest boot/completion records, serial-log hash, isolation/time bounds, timestamps, and every scenario's test-source hash, status, exit code, elapsed time and log hash.

The tested-content digest binds runtime scripts, sidecars, architecture artifacts, test scripts/fixtures, validation tools/build configs, the virtual workflow and the README policy text consumed by the secure-download scenario. It excludes Git metadata, `.tasks` and completion documentation. Changes to a tested policy input require new matching evidence; the commit label remains provenance, while the content digest identifies what actually ran. Runtime, test, configuration, architecture archive, executable mode or manifest changes require new matching evidence.

`check-evidence.py` rejects missing architectures/scenarios, stale inputs or build fingerprints, mismatched scope, duplicate records or JSON keys, failed/skipped/timed-out cases, wrong execution class, inconsistent guest boot/completion, missing logs and changed log hashes. The saved serial log must contain the matching token-bound boot, ordered scenario results and successful completion. Acceptance succeeds only for the complete selected matrix, producing `unblocks: true` and the explicit `unblocked_features` list. Partial execution produces no unblocked features. It records physical release acceptance as unchanged.

For a discovered defect, preserve the failing scenario/log, apply a minimal compatible fix, and rerun the affected feature matrix at the new content digest. Record the failure, fix and retest in task/release evidence. The harness does not invent an acceptance result when infrastructure prevents execution.

## CI

[Virtual ARM feature tests](../.github/workflows/virtual-arm-feature-tests.yml) runs all feature contracts for push, pull request and merge-group events. Manual dispatch accepts an explicit feature selection. Three architecture jobs build/cache native assets and upload their execution artifacts even after failure. The `ARM feature acceptance` job requires successful jobs and validates the complete artifact matrix against its immutable candidate checkout.

The workflow uses read-only repository permissions and pinned actions. It does not change branch protection, merge a PR, publish a release or waive unrelated physical coverage. The acceptance JSON and scenario logs are the evidence for the selected feature decision.
