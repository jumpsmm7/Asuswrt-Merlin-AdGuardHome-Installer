# Installer Hardening Roadmap

This roadmap describes a low-risk path for making the installer safer and easier to maintain without destabilizing existing installs.

## Phase 1: Validation and Documentation

- Keep `sh -n installer` as the required CI check.
- Keep ShellCheck advisory-only until the legacy installer has been cleaned up.
- Document helper scripts and expected merge order.
- Avoid changing the active installer until helpers have been reviewed.

## Phase 2: Safe One-Line Behavior Fixes

Prioritize fixes that reduce risk without changing user-facing behavior:

- Replace partial package matching with exact package matching.
- Quote package names and file paths.
- Avoid overwriting `.err` and backup files when timestamped names are safer.
- Prefer `python3` when installing Python 3 dependencies.
- Avoid password interpolation into inline Python source.

## Phase 3: Helper Integration

Fold helper logic into the installer in small pull requests:

1. Add exact package detection helper.
2. Add centralized download helper.
3. Add timestamped backup helper.
4. Add service start/stop/restart helper functions.
5. Replace repeated service-control blocks one call site at a time.

## Phase 4: Diagnostics

Add a user-facing debug bundle option after the design is reviewed and tested.

The debug bundle should:

- Exclude `.config` by default.
- Save to `/tmp` by default.
- Print the output archive path.
- Warn users to review the archive before sharing it.

## Phase 5: Release Discipline

Before each release:

- Confirm `sh -n installer` passes.
- Confirm helper scripts pass `sh -n`.
- Test install/update/reconfigure/uninstall paths.
- Test at least one clean install and one update install.
- Confirm README install command points to the intended branch.
