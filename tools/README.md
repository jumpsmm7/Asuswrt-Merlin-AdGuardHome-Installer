# Helper Scripts

This directory contains standalone helper scripts and staged helper functions for improving the Asuswrt-Merlin-AdGuardHome-Installer codebase.

These files are not automatically sourced by the main `installer` unless that behavior is explicitly added in a future pull request.

## Current Helpers

### `installer-safety-helpers.sh`

Staged functions for safer installer behavior:

- Exact Entware package detection.
- Install-only-when-missing package helper.
- Safer temporary file creation.
- Password hashing through `python3` standard input.
- Centralized download helper with `curl` and `wget` fallback.
- Timestamped file backup helper.

### `agh-service-helpers.sh`

Staged functions for future service-control cleanup:

- AdGuard Home process detection.
- Expected process-count waits with timeouts.
- Start, stop, restart, and check wrappers.

## Integration Rules

Before moving any helper into the main installer:

1. Keep the change in a focused branch.
2. Preserve BusyBox/ash compatibility.
3. Run `sh -n` against the changed files.
4. Test on a router or close Asuswrt-Merlin/Entware environment.
5. Avoid mixing behavior changes and refactors in the same pull request.

## Suggested Merge Order

1. Documentation and CI changes.
2. Helper files under `tools/`.
3. Small installer changes that use one helper at a time.
4. Larger service-flow cleanup only after the smaller helper integrations are proven stable.
