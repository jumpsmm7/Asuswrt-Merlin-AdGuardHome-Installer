# Runtime writable-path inventory

This inventory covers the four shipped runtime scripts: `installer`,
`AdGuardHome.sh`, `S99AdGuardHome`, and `rc.func.AdGuardHome`.  `$$` denotes the
creating shell's PID.  Names derived from a key, archive member, PID, or process
start time are accepted only after the validation performed by the owning
function.

All four scripts set `umask 077` before creating runtime state.  An
operation-specific path must be absent (including a dangling symlink) before it
is created.  Existing shared paths are accepted only when their owner, type,
mode, and (for regular files) single-link status match the owning helper.  A
temporary replacement lives beside its target whenever publication uses `mv`.

## `installer`

| Kind | Path or path family | Lifetime / publication |
| --- | --- | --- |
| download metadata | `/tmp/AGH_STATIC_METADATA_$$.d/channels.txt{,.release,.beta,.edge}` | Files live in an exclusively created root-owned `700` workspace for one installer invocation; exact entries and then the directory are removed by installer cleanup. |
| NVRAM transaction | `/opt/etc/.AdGuardHome.nvram/{lock,lock.d,reaper,reaper.*,.reaper-*}` and per-transaction `.tmp.$$`, snapshot, `dirty`, `exists.*`, and `new.*` entries | Private `700` snapshot/lock directories. PID plus `/proc` start time identifies owners; reapers revalidate the published identity before removal. |
| setup journal / marker | `/opt/etc/.AdGuardHome.nvram/setup-files{,.tmp.$$,.done.$$}` and `/opt/etc/.AdGuardHome.nvram/setup-committed{,.tmp.$$}` | Same-filesystem staged journal and commit marker. |
| rollback result | `/opt/etc/.AdGuardHome.rollback_result{,.tmp.$$}` | Same-filesystem atomic diagnostic publication. |
| archive / extraction | `/opt/etc/backup_AdGuardHome.tar.gz{,.tmp.$$}` and `/opt/etc/.AdGuardHome.extract.$$` | Archive stage and private extraction directory; archive members are authenticated before installation. |
| upgrade restore | `/opt/etc/.AdGuardHome.restore.$$` and `/opt/etc/.AdGuardHome.rollback.$$` | Same-filesystem stage and rollback directory; retained only while replacement is active. |
| downloaded file | `<target-directory>/.<filename>.$$` | Same-filesystem authenticated download stage, then atomic rename. |
| YAML/config stages | `AdGuardHome.yaml.{bak,err}`, `.AdGuardHome.yaml.ori`, `*.setup.$$`, `*.rollback.$$`, `*.mode-migration.*.$$`, `*.webui-port.$$`, and `${TMPDIR:-/tmp}/AdGuardHome.{config,config.webui-port,dnsfilter}.$$` | Setup, migration, validation, and rollback state. Cleanup uses the exact recorded path, never a wildcard. |
| blocklist stages | Paths recorded in `BLOCKLIST_ANALYZER_*_FILE` and `BLOCKLIST_YAML_{BACKUP,REMOVED,TMP}_FILE` | Exact paths are registered before work and cleared through the blocklist cleanup handler. |
| timezone extraction | `/root/<tz archive member>` and `/root/usr` | Validated archive extraction paths removed explicitly; no wildcard expansion. |

The persistent `AdGuardHome.yaml.bak`, `.AdGuardHome.yaml.ori`, and
`backup_AdGuardHome.tar.gz` files are backups rather than temporary files, but
are included because rollback and restore consume them.

## `AdGuardHome.sh`

| Kind | Path or path family | Lifetime / publication |
| --- | --- | --- |
| service lock | `/tmp/AdGuardHome`, `/tmp/AdGuardHome/pid`, and `/tmp/AdGuardHome.lock` | Descriptor `flock` when supported, otherwise a private mkdir/PID lock. |
| flock probe | `/tmp/adguardhome-flock-test.$$` | Capability probe only; exact path removed after the probe. |
| DNS handoff | `/tmp/AdGuardHome.dns-handoff/{active,lock,lock.<pid>,lock.stale.$$}` | Shared with `S99AdGuardHome`; root-owned `700` directory and `600` single-link marker files. Marker identity is PID plus `/proc/<pid>/stat` start time. |
| LAN YAML refresh | `/opt/etc/AdGuardHome/.AdGuardHome.yaml.lan-bind.$${,.rewrite}` | Same directory/filesystem as the active YAML; validated before atomic `mv`. |
| IPSet runtime | `/opt/var/run/AdGuardHome-ipset/{flock,mkdir,mkdir/pid,mkdir/traps,reap.*,traps.$$}` | Root-owned private lock workspace with bounded stale-lock retries and exact-owner cleanup. |
| IPSet stages | `ipset.user.{tmp,new,legacy}.$$`, `AdGuardHome.yaml.{ipset,ipset-legacy,ipset-setup}.$$`, and `ipset.conf.{raw,tmp}.$$` | Same-filesystem stages and rollback copy, removed by exact name. |
| database links | `/tmp/{querylog.json,stats.db,sessions.db}` | Installer-owned compatibility symlinks; removed only when canonical targets still match the active work directory. |
| resolver bind mount | `/tmp/resolv.conf` | Router-managed mount point; unmounted only after mount and canonical-path checks. |

## `S99AdGuardHome`

| Kind | Path or path family | Lifetime / publication |
| --- | --- | --- |
| daemon PID | `/opt/var/run/AdGuardHome.pid` | Written by AdGuardHome itself and consumed by the service wrapper. |
| DNS handoff | `/tmp/AdGuardHome.dns-handoff/{active,lock,lock.<pid>,lock.stale.$$,watchdog-traps.$$.*}` | Private shared workspace. Lock and marker activity requires matching PID/start-time identity. |
| guard readiness | `/tmp/AdGuardHome.dns-handoff/guard-<pid>-<start-time>/{ready,wait}` | Operation-owned `700` directory, `600` single-link readiness marker, and `600` single-link FIFO. A pre-existing entry is rejected; cleanup validates the exact entry before unlinking it. |

## `rc.func.AdGuardHome`

| Kind | Path or path family | Lifetime / publication |
| --- | --- | --- |
| transition state | `/opt/var/run/<process>/service-state{,.$$}` | Root-owned `700` directory and `600` single-link file. State is created exclusively beside the target and atomically renamed. |
| startup trap snapshots | `/tmp/AdGuardHome-start-traps.$$.*` and its `all` / filtered trap files | Random-suffixed `700` operation directory with `600` files; signal cleanup removes only the recorded workspace after validation. |

## Cleanup and failure policy

* Creation failure, including a read-only filesystem, aborts the operation before
  a target is replaced.
* A symlink, foreign owner, wrong type/mode, or multiply linked regular file is
  treated as foreign state and is not truncated or recursively removed.
* PID records which control stale cleanup are paired with process start time;
  `kill -0` alone is not sufficient where reclaiming another operation's path is
  possible.
* Signal handlers are armed before publication and use the exact recorded path.
  Recursive cleanup is restricted to private `700` operation directories whose
  ownership record still matches.
* Runtime code does not use `mktemp`; it relies on exclusive creation, private
  mkdir workspaces, bounded retries, and same-filesystem stages.
