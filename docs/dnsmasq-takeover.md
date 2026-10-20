# dnsmasq security settings during AdGuardHome takeover

While AdGuardHome owns DNS, each managed main or supported SDN dnsmasq callback filters its generated runtime configuration before publication. It removes these exact options, including valued forms:

- `stop-dns-rebind`
- `dnssec`, `dnssec-check-unsigned`, `dnssec-no-timecheck`
- `proxy-dnssec`, `dnssec-debug`, `dnssec-timestamp`, `dnssec-limits`
- Every `trust-anchor`, including custom and rollover anchors
- Generic `dns-rr` records carrying DNSSEC keys or trust anchors

Unrelated options such as rebind exception lists, DHCP settings and local records remain. AdGuardHome's own DNSSEC preferences are independent. The filter does not change NVRAM selections, persistent key files or custom source files.

## Included configuration

Static absolute `conf-file` and `conf-dir` content is expanded into the same staged parent configuration and filtered there. Mixed includes retain their unrelated settings. No generated sidecar configuration needs to survive a restart, and shared persistent includes remain untouched.

The expansion preserves include position, device/inode deduplication and directory suffix filters. Directory ordering follows dnsmasq 2.80's native directory order or the bytewise sort used from 2.81 onward. The stock-first `dnsmasq --version` probe is needed only for directory includes. Quoted paths with spaces or `#` are supported.

Takeover fails before publishing that configuration when an include cannot be inspected safely. Refused cases include relative or stdin paths, dynamic `conf-script`, missing/unreadable/nonregular files, final symlink sources or directories, selected symlink directory entries, control characters or quoted commas in paths, unsupported quoted escapes, unknown directory ordering versions and nesting deeper than 32 levels. The error is logged as a `filter_dns_security` staging failure. Correct the include source before retrying; a failed filter is not a successful takeover.

## Publication and recovery

Filtering runs after the existing management, topology and active-AdGuardHome/handoff gates. Inactive or unmanaged callbacks leave native configuration alone. The filtered configuration then goes through the existing IPSET refresh and staged publication path. An edit, refresh or publication failure retains the live file and preserves the existing compensation behavior.

Publication is atomic for each configuration file; it is not one transaction across all main and SDN instances. Native recovery continues to use firmware regeneration from current persistent preferences and custom sources, restoring the original DNS security settings. There is no long-lived backup of those preferences. Later custom hooks can reintroduce settings after this callback; diagnose that hook rather than overwriting its persistent source.

## Verification scope

`tests/dnsmasq-security-takeover.sh` exercises directive/key filtering, nested mixed includes, directory semantics and refused input. The dnsmasq LAN-mode and startup-handoff regressions exercise managed main/SDN publication, failure preservation and modeled native regeneration. These fixtures are registered in the shared host suite and virtual ARM inventory. They model firmware inputs; physical hook dispatch and client DNS behavior require candidate-specific router validation under the release plan.
