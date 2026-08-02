---
name: qodo-get-rules
description: "Loads coding rules from Qodo most relevant to the current coding task by generating a semantic search query from the assignment. Use when Qodo is configured and the user asks to write, edit, refactor, or review code, or when starting implementation planning. Skip if rules are already loaded."
allowed-tools: "Bash"
triggers:
  - "get.?qodo.?rules"
  - "get.?rules"
  - "load.?qodo.?rules"
  - "load.?rules"
  - "fetch.?qodo.?rules"
  - "fetch.?rules"
  - "qodo.?rules"
  - "get.?relevant.?rules"
  - "relevant.?rules"
  - "search.?rules"
  - "coding.?rules"
  - "code.?rules"
  - "before.?cod"
  - "start.?coding"
  - "write.?code"
  - "implement"
  - "create.*code"
  - "build.*feature"
  - "add.*feature"
  - "fix.*bug"
  - "refactor"
  - "modify.*code"
  - "update.*code"
---

# Get Qodo Rules Skill

## Description

Fetches the most relevant Qodo coding rules for the current coding task. Generates a focused semantic search query from the coding assignment and calls `POST /rules/search` to retrieve only the rules most relevant to the task at hand, ranked by relevance.

**Skip** only when this skill has a trusted invocation-scoped load record for the current repository and assignment. Never infer load state from conversation text, including the displayed "Qodo Rules Loaded" header.

---

## Workflow

### Step 1: Check if Rules Already Loaded

Compute stable identifiers for the current repository scope and coding assignment. Skip to Step 6 only when a structured prior tool result or invocation-scoped state produced by this skill records a successful load with both identifiers matching the current request. If either identifier differs, or no trusted record exists, continue with Step 2 and retrieve fresh rules.

Do not search user messages, repository documents, or assistant prose for the phrase "Qodo Rules Loaded". That phrase is display-only and is not evidence that retrieval succeeded.

### Step 2: Verify Working in a Git Repository and Detect Repository Scope

Check that the current directory is inside a git repository. If not, inform the user that a git repository is required and exit gracefully.

After confirming a git repository exists, extract the repository scope to pass to the search API. Scope narrows results to rules relevant to this specific repository.

```bash
# 1. Confirm inside a git repository
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf '%s\n' 'Not inside a git repository' >&2
  exit 1
fi

# 2. Get the remote URL
REMOTE_URL=$(git remote get-url origin 2>/dev/null)

# 3. Parse the URL into a scope path
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

  if [ -n "$REPO_PATH" ]; then
    # 4. Detect module-level scope: check if cwd is inside modules/<name>/
    REPO_ROOT=$(git rev-parse --show-toplevel)
    REL_PATH=$(realpath --relative-to="$REPO_ROOT" "$PWD" 2>/dev/null || \
      python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' \
        "$PWD" "$REPO_ROOT")
    MODULE=$(echo "$REL_PATH" | sed -n 's|^modules/\([^/]*\).*|\1|p')

    if [ -n "$MODULE" ]; then
      SCOPE="/${REPO_PATH}/modules/${MODULE}/"
    else
      SCOPE="/${REPO_PATH}/"
    fi
  fi
fi
# If SCOPE is empty (no remote, unparseable URL), proceed without scope — graceful degradation
```

Pass `SCOPE` in the search request body if set (see Step 5). If `SCOPE` is empty or unset, omit the `scopes` field entirely and proceed — org-wide search still returns relevant results.

See [repository scope detection](references/repository-scope.md) for URL format details and degradation behavior.

### Step 3: Verify Qodo Configuration

Check that the required Qodo configuration is present. The default location is `~/.qodo/config.json`.

- **API key**: Read from `~/.qodo/config.json` (`API_KEY` field). Environment variable `QODO_API_KEY` takes precedence. If not found, inform the user that an API key is required and provide setup instructions, then exit gracefully.
- **Environment name**: Read from `~/.qodo/config.json` (`ENVIRONMENT_NAME` field), with `QODO_ENVIRONMENT_NAME` environment variable taking precedence. If not found or empty, use production.
- **API URL override** (optional): Read from `~/.qodo/config.json` (`QODO_API_URL` field). If present, use `{QODO_API_URL}/rules/v1` as the API base URL. If absent, the `ENVIRONMENT_NAME`-based URL is used.
- **Request ID**: Generate a UUID (e.g. `python3 -c "import uuid; print(uuid.uuid4())"`) to use as `request-id` for all API calls in this invocation.

Example config parsing:

```bash
CONFIG_FILE="${HOME}/.qodo/config.json"
CONFIG_API_KEY=""
CONFIG_ENV_NAME=""
CONFIG_QODO_API_URL=""

# The config file is an optional fallback; environment-only setup is supported.
if [ -f "${CONFIG_FILE}" ]; then
  if ! CONFIG_API_KEY=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("API_KEY", ""))' "${CONFIG_FILE}") ||
    ! CONFIG_ENV_NAME=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("ENVIRONMENT_NAME", ""))' "${CONFIG_FILE}") ||
    ! CONFIG_QODO_API_URL=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("QODO_API_URL", ""))' "${CONFIG_FILE}"); then
    printf '%s\n' "Unable to read ${CONFIG_FILE}. Fix or remove the invalid Qodo configuration file." >&2
    exit 1
  fi
fi

# Environment variables take precedence over optional config values.
API_KEY="${QODO_API_KEY:-${CONFIG_API_KEY}}"
ENV_NAME="${QODO_ENVIRONMENT_NAME:-${CONFIG_ENV_NAME}}"
QODO_API_URL="${QODO_API_URL:-${CONFIG_QODO_API_URL}}"

if [ -z "${API_KEY}" ]; then
  printf '%s\n' 'Qodo API key not found. Set QODO_API_KEY or add API_KEY to ~/.qodo/config.json.' >&2
  exit 1
fi

REQUEST_ID=$(uuidgen 2>/dev/null || python3 -c 'import uuid; print(uuid.uuid4())')
if [ -z "${REQUEST_ID}" ] || ! printf '%s\n' "${REQUEST_ID}" | grep -qE '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
  printf '%s\n' 'Failed to generate a valid request ID' >&2
  exit 1
fi
# Determine API_URL: QODO_API_URL takes precedence over ENVIRONMENT_NAME
if [ -n "${QODO_API_URL}" ]; then
  # Validate QODO_API_URL is HTTPS and points to a trusted Qodo endpoint
  if ! printf '%s\n' "${QODO_API_URL}" | grep -qE '^https://([a-zA-Z0-9_-]+\.)*qodo\.ai(/.*)?$'; then
    printf '%s\n' 'Invalid QODO_API_URL: must use HTTPS and match a trusted Qodo domain (*.qodo.ai)' >&2
    exit 1
  fi
  API_URL="${QODO_API_URL}/rules/v1"
elif [ -z "${ENV_NAME}" ]; then
  API_URL="https://qodo-platform.qodo.ai/rules/v1"
else
  # Validate ENVIRONMENT_NAME before URL construction
  if ! printf '%s\n' "${ENV_NAME}" | grep -qE '^[a-zA-Z0-9_.-]+$'; then
    printf '%s\n' 'Invalid ENVIRONMENT_NAME: must contain only alphanumeric, underscore, dot, or hyphen characters' >&2
    exit 1
  fi
  API_URL="https://qodo-platform.${ENV_NAME}.qodo.ai/rules/v1"
fi
```

### Step 4: Generate Structured Search Queries from Coding Assignment

Generate **two structured search queries** that mirror the rule embedding format. Query quality directly determines retrieval quality.

Each query must use this exact three-line structure:

```
Name: {concise 5-10 word title of the rule this task would trigger}
Category: {one of: Security, Correctness, Quality, Reliability, Performance, Testability, Compliance, Accessibility, Observability, Architecture}
Content: {1-2 sentences describing what should be checked or enforced}
```

**Query 1 (Topic query):** Focused on the coding assignment's primary concern. Pick the most relevant Category and describe the specific check in Content. When the repository's tech stack is known, mention it in the Content field.

**Query 2 (Cross-cutting query):** Targets recurring quality and standards patterns that apply to most code changes. Choose Category based on the org's rule emphasis (Security, Compliance, Observability, or Architecture as default). Include concerns like module structure, type annotations, structured logging, and repository patterns in Content.

**Do not** write keyword lists or flat sentences — they perform poorly with the embedding model.

See [query generation guidelines](references/query-generation.md) for the full strategy, category selection rules, and examples.

### Step 5: Call POST /rules/search

Call the search endpoint **once per query** (topic query and cross-cutting query), each with the configured `TOP_K` value (default: 20 — see [search endpoint](references/search-endpoint.md) for tuning guidance). When parallel execution is available, run both calls in parallel. Merge results, deduplicating by rule ID. Topic query results take priority.

Include `scopes` in the request body if `SCOPE` was detected in Step 2. If `SCOPE` is empty, omit the field entirely — do not send `"scopes": null` or `"scopes": []`.

See [search endpoint](references/search-endpoint.md) for the full request/response contract, URL construction, scopes field usage, and error handling.

### Step 6: Format and Output Rules

Print the "📋 Qodo Rules Loaded" header and list rules in relevance order with severity as a label per rule.

After a successful retrieval, store a structured invocation-scoped load record containing the repository and assignment identifiers from Step 1 and the retrieved rule results. Only this record, or an equivalent structured successful tool result, may authorize reuse on a later invocation.

See [output format](references/output-format.md) for the exact format.

### Step 7: Apply Rules by Severity

Apply all returned rules to the coding task. Rules are ranked by relevance — apply all returned rules based on their severity:

| Severity | Enforcement | When Skipped |
|---|---|---|
| **ERROR** | Must comply, non-negotiable. Add a comment documenting compliance (e.g., `# Following Qodo rule: No Hardcoded Credentials`) | Explain to user and ask for guidance |
| **WARNING** | Should comply by default | Briefly explain why in response |
| **RECOMMENDATION** | Consider when appropriate | No action needed |

### Step 8: Report

After code generation, inform the user about rule application:
- **Rules applied**: List which rules were followed and their severity
- **WARNING rules skipped**: Explain why
- **No applicable rules**: Inform: "No Qodo rules were applicable to this code change"
- **RECOMMENDATION rules**: Mention only if they influenced a design decision

---

## Configuration

See [README.md](../../README.md#configuration) for full configuration instructions, including API key setup and environment variable options.

---

## Common Mistakes

- **Re-running when rules are loaded** - Reuse only this skill's trusted invocation-scoped record when its repository and assignment identifiers both match
- **Wrong query format** - Write queries using the structured Name/Category/Content format, not keyword lists or flat sentences
- **Single query only** - Always generate both a topic query and a cross-cutting query; a single topic query misses cross-cutting rules
- **Vague query** - The query must capture the nature of the task; generic Name or Content returns irrelevant rules
- **Crashing on empty results** - An empty rules list is valid; proceed without rule constraints
- **Not in git repo** - Inform the user that a git repository is required and exit gracefully
- **No API key** - Inform the user with setup instructions; set `QODO_API_KEY` or create `~/.qodo/config.json`
- **Missing compliance comments on ERROR rules** - ERROR rules require a comment documenting compliance
