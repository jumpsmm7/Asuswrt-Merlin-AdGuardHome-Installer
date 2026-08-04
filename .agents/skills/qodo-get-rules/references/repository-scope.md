# Repository Scope Detection

The skill detects the repository scope from the git `origin` remote URL and passes it to the search API as the `scopes` field. This narrows results to rules that are relevant to the specific repository, improving retrieval precision.

## Git Repository Check

```bash
# Must be inside a git repository
git rev-parse --is-inside-work-tree
```

Exit code is non-zero (128) if not in a git repository. If not in a git repo, inform the user and exit gracefully.

## Scope Extraction

After confirming a git repository, extract the scope from the `origin` remote:

```bash
REMOTE_URL=$(git remote get-url origin 2>/dev/null)
```

### URL Format Handling

| Remote format | Example | Parsed `REPO_PATH` |
|---|---|---|
| HTTPS | `https://github.com/org/repo.git` | `org/repo` |
| SSH | `git@github.com:org/repo.git` | `org/repo` |

The `.git` suffix is stripped before parsing. The resulting scope path is `/org/repo/`.

### Module-Level Scope

If the current working directory is inside a `modules/<name>/` subdirectory of the repository root, the scope is narrowed to that module:

```
/org/repo/modules/<name>/
```

Otherwise the repository-wide scope `/org/repo/` is used.

Detection:

```bash
REPO_PATH=""
SCOPE=""

# Parse REPO_PATH from REMOTE_URL
if [ -n "$REMOTE_URL" ]; then
  # Strip .git suffix if present
  REMOTE_URL="${REMOTE_URL%.git}"

  # Handle SSH format: git@github.com:org/repo
  if echo "$REMOTE_URL" | grep -q "^git@"; then
    REPO_PATH=$(echo "$REMOTE_URL" | sed 's/^git@[^:]*://')
  # Handle HTTPS format: https://github.com/org/repo
  elif echo "$REMOTE_URL" | grep -q "^https\?://"; then
    REPO_PATH=$(echo "$REMOTE_URL" | sed 's|^https\?://[^/]*/||')
  else
    REPO_PATH=""
  fi
fi

if [ -n "$REPO_PATH" ]; then
  REPO_ROOT=$(git rev-parse --show-toplevel)
  REL_PATH=$(realpath --relative-to="$REPO_ROOT" "$PWD" 2>/dev/null \
    || python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' \
      "$PWD" "$REPO_ROOT")
  MODULE=$(echo "$REL_PATH" | sed -n 's|^modules/\([^/]*\).*|\1|p')

  if [ -n "$MODULE" ]; then
    SCOPE="/${REPO_PATH}/modules/${MODULE}/"
  else
    SCOPE="/${REPO_PATH}/"
  fi
fi
```

## Graceful Degradation

Scope is **optional**. If scope cannot be determined for any reason, the skill proceeds without it — org-wide semantic search still returns relevant results.

Skip scope and proceed without error when:
- No `origin` remote is configured
- Remote URL cannot be parsed into an org/repo path
- Any other unexpected failure during extraction

Do not send `"scopes": null` or `"scopes": []` — omit the `scopes` field entirely from the request body.
