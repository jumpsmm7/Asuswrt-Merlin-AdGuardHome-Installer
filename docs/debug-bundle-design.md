# Debug Bundle Design

This branch is intended to add a safer issue-reporting workflow for Asuswrt-Merlin-AdGuardHome-Installer.

## Goal

Create a repeatable way for users to collect troubleshooting information without manually copying many paths from the README.

## Proposed Debug Bundle Contents

The debug bundle should include:

- Router model and firmware version.
- CPU architecture.
- AdGuard Home process status.
- Port 53 listener information.
- DNS-related NVRAM values that affect AdGuard Home integration.
- Relevant installer-created files under `/jffs/addons/AdGuardHome.d`.
- Relevant init/service files under `/opt/etc/init.d`.
- Relevant Asuswrt-Merlin custom script hooks under `/jffs/scripts`.

## Privacy and Safety Requirements

Before sharing a debug bundle publicly, users should review it for private values.

The bundle helper should avoid collecting unnecessary private state and should exclude the installer `.config` file by default. It should also avoid collecting full logs unless the user explicitly chooses to include them.

## Recommended Implementation Plan

1. Add a menu option named `Create debug bundle`.
2. Write the bundle to `/tmp` by default.
3. Exclude `.config` by default.
4. Print the archive path after creation.
5. Warn the user to review the archive before uploading it to GitHub or a forum.

## Future Installer Integration

Once reviewed, the installer can call a helper function similar to:

```sh
create_debug_bundle() {
    # collect selected paths
    # write system summary
    # exclude .config
    # tar output into /tmp
}
```

This should be implemented with POSIX/BusyBox ash-compatible syntax only.
