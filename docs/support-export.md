# Support export

Run an opt-in export to a new file in an existing directory owned by the invoking account:

```sh
sh installer support-export --output /tmp/agh-support.txt
```

Use a physical absolute path without symlinked parent directories. Existing files,
symlinks, hardlinks, directories and special files are refused. Group/world writable
parents are refused except an owned root sticky directory such as `/tmp`. The report
is published atomically without overwriting another object and has mode `0600`.
There is no upload; review the report and decide whether to share it.

The fixed `key=value` schema reports installer and AdGuard Home versions/source,
router model/firmware/architecture, Entware presence, available storage and memory,
daemon/monitor counts, categorized listener owners for ports 53 and 553, hook
presence/header/executable checks and categorized recovery markers. Unexpected
values become `unknown` or `custom`; private paths, addresses, process arguments,
raw logs, DNS queries, full configuration and NVRAM inventories are never copied.
The collector does not source configuration or invoke repair, installation, service,
firewall, network or NVRAM write commands. Missing Entware and unavailable probes
produce a partial report with `missing`/`unknown` fields and failed-probe counts.
Monitor counts are `unknown` when the firmware does not support wide `ps -ww`
output; truncated process listings are never treated as a reliable zero.

Existing installer startup recovery is separate and may run before collection.
`recovery.prior_startup=checked` means those checks succeeded; it does not assert
that a recovery changed state. `pending` means startup reported pending recovery.
`not-reported` means no startup outcome was supplied. Saved rollback contexts map
to fixed stages such as package, restore, NVRAM, YAML, blocklist or service. Results
become complete, incomplete, not-attempted or unknown. Recovery details and artifact
contents are excluded from the export.

Each fixed external probe gets at most two monotonic seconds, bounded regular-file
capture and an 8192-byte file-size limit. Collection shares a thirty-second probe
budget; report data is below 16 KiB. On BusyBox, the internal file limits use 512-byte
blocks (16 blocks for probes and 32 blocks for the report). Temporary directories are created with mode `0700` in
the output directory and removed only when owner, inode and permissions still
match this invocation. If that identity cannot be verified, the private stage is
retained with a warning. Probe termination checks kernel PID identity, also cleans
up observed immediate workers with one bounded procfs scan, and never waits on a
still-running kernel task. Fixed stock probes do not create persistent workers;
this mechanism does not supervise arbitrary programs that daemonize.

The runtime uses POSIX shell/BusyBox 1.25.1 applets (`awk`, `cat`, `dd`, `df`, `ln`,
`ls`, `mkdir`, `netstat`, `pidof`, `ps`, `rm`, `sleep`, `uname`, `usleep`, `wc`), shell
builtins, Linux `/proc/uptime`, `/proc/self/status`, `/proc/PID/stat`, and read-only
`nvram get`. AdGuard Home `--version` runs only when its fixed installed binary is
regular and executable. No Entware package, Python or GNU `timeout` is required.

The focused regression executes extracted installer helpers against isolated input
paths and declared firmware-command fixtures. Real procfs, signals, resource limits,
staging and file publication are exercised. Host fixtures are not physical-router
validation or proof of unrelated startup recovery behavior.
