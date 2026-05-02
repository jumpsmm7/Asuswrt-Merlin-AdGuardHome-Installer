# Installer Code Hardening Local Apply Workflow

The active `installer` file is large enough that some GitHub connector/API views truncate the file body. To avoid accidentally committing a truncated installer, apply installer-code changes from a local clone where the complete file is available.

## Branch

Use this branch for the squash-merge installer work:

```sh
git checkout dev/installer-code-hardening-squash
```

## Apply Installer Hardening

Run:

```sh
python3 tools/apply-installer-hardening.py --check
python3 tools/apply-installer-hardening.py
```

The script performs conservative exact-context edits. If any expected context is missing or appears more than once, it exits instead of guessing.

## Update and Validate Checksums

After the installer changes are applied, run:

```sh
sh tools/update-changed-md5.sh --all
sh tools/check-md5.sh
```

If `installer.md5` exists, it will be updated automatically. If it does not exist yet, create it with:

```sh
sh tools/update-md5.sh installer.md5
```

## Validate Shell Syntax

Run:

```sh
sh -n installer
find tools -type f -name '*.sh' -exec sh -n {} \;
```

ShellCheck is advisory for now:

```sh
shellcheck installer || true
```

## Commit Everything Together

Commit the modified installer and matching checksum file in the same branch:

```sh
git status
git add installer installer.md5 tools docs .github
git commit -m "installer: harden package checks and password hashing"
git push origin dev/installer-code-hardening-squash
```

Then open or update the PR and squash merge when ready.

## Installer Hardening Included

The apply script currently targets these low-risk improvements:

- Adds exact Entware package detection helpers.
- Replaces partial `grep -q` package checks with exact package matching.
- Avoids unnecessary package force-reinstall behavior in the authentication dependency path.
- Uses `python3` for bcrypt hashing.
- Passes the password to Python over stdin instead of interpolating it into Python source.
- Quotes restore-time file ownership changes.
- Uses timestamped `.err` files for invalid YAML rather than overwriting a fixed error file.
- Quotes the JFFS NVRAM key assignment.
