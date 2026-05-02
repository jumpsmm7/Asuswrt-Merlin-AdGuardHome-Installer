# Development Workflow

This repository targets Asuswrt-Merlin routers and Entware environments. The installer should remain compatible with `/bin/sh` on BusyBox/ash unless a change explicitly documents a different requirement.

## Branch Strategy

Use small, focused development branches:

- `dev/readme-installer-improvements` for README and user-facing documentation.
- `dev/installer-safety-hardening` for safer shell behavior and input handling.
- `dev/installer-service-refactor` for reducing repeated AdGuard Home service logic.
- `dev/diagnostics-debug-bundle` for issue-reporting and debug collection improvements.
- `dev/repo-hygiene-ci` for repository metadata, CI, and validation checks.

## Shell Compatibility Rules

Prefer POSIX/BusyBox ash-compatible syntax:

- Use `[` instead of `[[`.
- Avoid arrays.
- Avoid process substitution.
- Quote variable expansions unless intentional word splitting is required.
- Prefer helper functions for repeated service, download, and package checks.

## Suggested Local Checks

Before opening a pull request, run:

```sh
sh -n installer
shellcheck installer
```

If helper scripts are added under `tools/`, run:

```sh
find tools -type f -name '*.sh' -exec sh -n {} \;
find tools -type f -name '*.sh' -exec shellcheck {} \;
```

## Installer Change Guidelines

When changing `installer`:

1. Keep each pull request narrowly scoped.
2. Avoid changing runtime behavior and refactoring in the same commit.
3. Preserve existing menu flows unless the pull request explicitly targets UX changes.
4. Prefer adding helpers first, then replacing repeated logic in a follow-up commit.
5. Test on at least one supported Asuswrt-Merlin device or a close shell-compatible environment before merging.
