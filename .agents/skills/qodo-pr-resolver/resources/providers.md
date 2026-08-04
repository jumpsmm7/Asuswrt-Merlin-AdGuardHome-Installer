# Git Provider Commands Reference

This document contains all provider-specific CLI commands and API interactions for the Qodo PR Resolver skill. Reference this file when implementing provider-specific operations.

## Supported Providers

- GitHub (via `gh` CLI)
- GitLab (via `glab` CLI)
- Bitbucket (via REST API with `curl`)
- Azure DevOps (via `az` CLI with DevOps extension)
- Gerrit (via REST API with `curl`) — see [gerrit.md](./gerrit.md)

## Provider Detection

Detect the git provider from the remote URL:

```bash
git remote get-url origin
```

Match against:
- `github.com` → GitHub
- `gitlab.com` → GitLab
- `bitbucket.org` → Bitbucket
- `dev.azure.com`, or the host configured by `AZURE_DEVOPS_URL` (from environment or `~/.qodo/config.json`) → Azure DevOps
- `.gitreview` file or port `29418` or `googlesource.com` → Gerrit (see [gerrit.md](./gerrit.md))

For Azure DevOps detection, load `AZURE_DEVOPS_URL` from the Qodo config file as a fallback if not set in the environment:

```bash
# Load AZURE_DEVOPS_URL from Qodo config for provider detection if not already set
if [ -z "${AZURE_DEVOPS_URL:-}" ]; then
  if [ -z "${HOME:-}" ]; then
    echo "Error: HOME environment variable is not set; set QODO_CONFIG explicitly or ensure HOME is defined" >&2
    exit 1
  fi
  QODO_CONFIG=${QODO_CONFIG:-${HOME}/.qodo/config.json}
  if [ -f "$QODO_CONFIG" ]; then
    # Require secure permissions before reading credentials
    QODO_DIR=$(dirname "$QODO_CONFIG")
    if [ "$(stat -c '%a' "$QODO_DIR" 2>/dev/null || stat -f '%Lp' "$QODO_DIR" 2>/dev/null)" != "700" ]; then
      echo "Error: Qodo config directory $QODO_DIR must have mode 700 (owner-only access)" >&2
      exit 1
    fi
    if [ "$(stat -c '%a' "$QODO_CONFIG" 2>/dev/null || stat -f '%Lp' "$QODO_CONFIG" 2>/dev/null)" != "600" ]; then
      echo "Error: Qodo config file $QODO_CONFIG must have mode 600 (owner-only access)" >&2
      exit 1
    fi
    AZURE_DEVOPS_URL=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("AZURE_DEVOPS_URL", ""))' "$QODO_CONFIG" 2>/dev/null || echo "")
  fi
fi
# Now match remote URL host against dev.azure.com or AZURE_DEVOPS_URL
```

## Prerequisites by Provider

**Shared requirement for all providers:**
- **python3** (required for JSON parsing and validation)
  - **Verify:**
    ```bash
    python3 --version
    ```

### GitHub

**CLI:** `gh`
- **Install:** `brew install gh` or [cli.github.com](https://cli.github.com/)
- **Authenticate:** `gh auth login`
- **Verify:**
  ```bash
  gh --version && gh auth status
  ```

### GitLab

**CLI:** `glab`
- **Install:** `brew install glab` or [glab.readthedocs.io](https://glab.readthedocs.io/)
- **Authenticate:** `glab auth login`
- **Verify:**
  ```bash
  glab --version && glab auth status
  ```

### Bitbucket

**Authentication:** Bitbucket REST API with an App Password (there is no official `bb` CLI)
- Create an App Password: Bitbucket → **Settings → App passwords**
  - Required scopes: **Repositories: Read**, **Pull requests: Read, Write**
- **Qodo config** (`~/.qodo/config.json`) — store credentials persistently:
  ```json
  {
    "BB_USERNAME": "your-bitbucket-username",
    "BB_APP_PASSWORD": "your-app-password"
  }
  ```
  These examples support **Bitbucket Cloud only**. Bitbucket Server and Data Center use different REST routes and project/repository addressing, so do not point these commands at a self-hosted instance.
- **Load configuration** (existing environment variables take precedence):
  ```bash
  if [ -z "${HOME:-}" ]; then
    echo "Error: HOME environment variable is not set; set QODO_CONFIG explicitly or ensure HOME is defined" >&2
    exit 1
  fi
  QODO_CONFIG=${QODO_CONFIG:-${HOME}/.qodo/config.json}
  if [ -f "$QODO_CONFIG" ]; then
    # Require secure permissions before reading credentials
    QODO_DIR=$(dirname "$QODO_CONFIG")
    if [ "$(stat -c '%a' "$QODO_DIR" 2>/dev/null || stat -f '%Lp' "$QODO_DIR" 2>/dev/null)" != "700" ]; then
      echo "Error: Qodo config directory $QODO_DIR must have mode 700 (owner-only access)" >&2
      exit 1
    fi
    if [ "$(stat -c '%a' "$QODO_CONFIG" 2>/dev/null || stat -f '%Lp' "$QODO_CONFIG" 2>/dev/null)" != "600" ]; then
      echo "Error: Qodo config file $QODO_CONFIG must have mode 600 (owner-only access)" >&2
      exit 1
    fi
    [ -n "${BB_USERNAME:-}" ] || BB_USERNAME=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("BB_USERNAME", ""))' "$QODO_CONFIG")
    [ -n "${BB_APP_PASSWORD:-}" ] || BB_APP_PASSWORD=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("BB_APP_PASSWORD", ""))' "$QODO_CONFIG")
  fi
  if [ -z "${BB_USERNAME:-}" ] || [ -z "${BB_APP_PASSWORD:-}" ]; then
    echo "Bitbucket credentials are missing; set BB_USERNAME and BB_APP_PASSWORD or add them to $QODO_CONFIG" >&2
    exit 1
  fi
  ```
- Set the Bitbucket Cloud API endpoint, then extract the workspace and repository slug from either HTTPS or SSH remote syntax:
  ```bash
  BB_API_URL=https://api.bitbucket.org
  BB_HOST=api.bitbucket.org
  BB_REMOTE=$(git remote get-url origin)
  BB_REMOTE_PATH=$(printf '%s\n' "$BB_REMOTE" | sed -E \
    -e 's|^[^@]+@[^:]+:||' \
    -e 's|^[a-zA-Z][a-zA-Z0-9+.-]*://[^/]+/||' \
    -e 's|^/+||' \
    -e 's|\.git$||')
  BB_WORKSPACE=$(printf '%s\n' "$BB_REMOTE_PATH" | cut -d/ -f1)
  BB_REPO=$(printf '%s\n' "$BB_REMOTE_PATH" | cut -d/ -f2)
  if [ -z "$BB_HOST" ] || [ -z "$BB_WORKSPACE" ] || [ -z "$BB_REPO" ]; then
    echo "Failed to derive Bitbucket host, workspace/project, or repository" >&2
    exit 1
  fi
  ```
- **Setup netrc file** (to avoid exposing password via command-line arguments):
  ```bash
  umask 077
  if ! BB_NETRC=$(mktemp "${TMPDIR:-/tmp}/bb-netrc.XXXXXX"); then
    echo "Failed to create temporary netrc file" >&2
    exit 1
  fi
  trap 'rm -f "$BB_NETRC"' EXIT
  trap 'rm -f "$BB_NETRC"; exit 129' HUP
  trap 'rm -f "$BB_NETRC"; exit 130' INT
  trap 'rm -f "$BB_NETRC"; exit 143' TERM
  if ! cat > "$BB_NETRC" << EOF
machine $BB_HOST
login $BB_USERNAME
password $BB_APP_PASSWORD
EOF
  then
    echo "Failed to write netrc file" >&2
    exit 1
  fi
  if ! chmod 600 "$BB_NETRC"; then
    echo "Failed to set permissions on netrc file" >&2
    exit 1
  fi
  ```
- **Verify:**
  ```bash
  curl --fail --silent --show-error --connect-timeout 10 --max-time 30 --netrc-file "$BB_NETRC" \
    "$BB_API_URL/2.0/user" | python3 -m json.tool
  ```

### Azure DevOps

**CLI:** `az` with DevOps extension
- **Install:** `brew install azure-cli` or [docs.microsoft.com/cli/azure](https://docs.microsoft.com/cli/azure)
- **Install extension:** `az extension add --name azure-devops`
- **Qodo config** (`~/.qodo/config.json`) — optional, for non-interactive auth:
  ```json
  {
    "AZURE_DEVOPS_EXT_PAT": "your-personal-access-token",
    "AZURE_DEVOPS_URL": "https://dev.azure.com"
  }
  ```
  `AZURE_DEVOPS_EXT_PAT` replaces `az login`. `AZURE_DEVOPS_URL` is optional — only needed for on-premises Azure DevOps Server.
- **Authenticate and configure:**
  ```bash
  if [ -z "${HOME:-}" ]; then
    echo "Error: HOME environment variable is not set; set QODO_CONFIG explicitly or ensure HOME is defined" >&2
    exit 1
  fi
  QODO_CONFIG=${QODO_CONFIG:-${HOME}/.qodo/config.json}
  if [ -f "$QODO_CONFIG" ]; then
    # Require secure permissions before reading credentials
    QODO_DIR=$(dirname "$QODO_CONFIG")
    if [ "$(stat -c '%a' "$QODO_DIR" 2>/dev/null || stat -f '%Lp' "$QODO_DIR" 2>/dev/null)" != "700" ]; then
      echo "Error: Qodo config directory $QODO_DIR must have mode 700 (owner-only access)" >&2
      exit 1
    fi
    if [ "$(stat -c '%a' "$QODO_CONFIG" 2>/dev/null || stat -f '%Lp' "$QODO_CONFIG" 2>/dev/null)" != "600" ]; then
      echo "Error: Qodo config file $QODO_CONFIG must have mode 600 (owner-only access)" >&2
      exit 1
    fi
    [ -n "${AZURE_DEVOPS_EXT_PAT:-}" ] || AZURE_DEVOPS_EXT_PAT=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("AZURE_DEVOPS_EXT_PAT", ""))' "$QODO_CONFIG")
    [ -n "${AZURE_DEVOPS_URL:-}" ] || AZURE_DEVOPS_URL=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("AZURE_DEVOPS_URL", ""))' "$QODO_CONFIG")
  fi
  export AZURE_DEVOPS_EXT_PAT
  if [ -z "${AZURE_DEVOPS_EXT_PAT:-}" ]; then
    az login || { echo "Error: az login failed" >&2; exit 1; }
  fi
  # Normalize the configured service/collection URL. For Azure DevOps Cloud,
  # the organization is the first path component after dev.azure.com. For
  # Azure DevOps Server, AZURE_DEVOPS_URL is the collection URL itself.
  ADO_BASE_URL=${AZURE_DEVOPS_URL:-https://dev.azure.com}
  ADO_BASE_URL=${ADO_BASE_URL%/}
  # Validate ADO_BASE_URL uses HTTPS scheme
  if ! printf '%s\n' "$ADO_BASE_URL" | grep -qE '^https://'; then
    echo "Error: AZURE_DEVOPS_URL must use HTTPS scheme" >&2
    exit 1
  fi
  ADO_REMOTE=$(git remote get-url origin)
  case "$ADO_REMOTE" in
    git@ssh.dev.azure.com:v3/*) ADO_REMOTE=https://dev.azure.com/${ADO_REMOTE#git@ssh.dev.azure.com:v3/} ;;
    ssh://git@ssh.dev.azure.com/v3/*) ADO_REMOTE=https://dev.azure.com/${ADO_REMOTE#ssh://git@ssh.dev.azure.com/v3/} ;;
    https://*@*) ADO_REMOTE=https://${ADO_REMOTE#*@} ;;
  esac
  case "$ADO_REMOTE" in
    "$ADO_BASE_URL"/*) ADO_PATH=${ADO_REMOTE#"$ADO_BASE_URL"/} ;;
    *)
      echo "Error: remote does not use configured Azure DevOps URL: $ADO_BASE_URL" >&2
      exit 1
      ;;
  esac

  if [ "$ADO_BASE_URL" = "https://dev.azure.com" ]; then
    ADO_ORG=${ADO_PATH%%/*}
    ADO_PATH=${ADO_PATH#*/}
    ADO_ORGANIZATION=$ADO_BASE_URL/$ADO_ORG
  else
    ADO_ORGANIZATION=$ADO_BASE_URL
  fi
  ADO_PROJECT=${ADO_PATH%%/*}
  ADO_REPO=${ADO_PATH##*/}
  ADO_REPO=${ADO_REPO%.git}
  # Get repository ID (required for thread API calls):
  if ! ADO_REPO_ID=$(az repos show --organization "$ADO_ORGANIZATION" --project "$ADO_PROJECT" --repository "$ADO_REPO" --query id -o tsv); then
    echo "Error: Failed to retrieve Azure DevOps repository ID" >&2
    exit 1
  fi
  if [ -z "$ADO_REPO_ID" ]; then
    echo "Error: Azure DevOps repository ID is empty" >&2
    exit 1
  fi
  ```
- **Verify:**
  ```bash
  az --version && az devops configure --list
  ```

## Find Open PR/MR

Get the PR/MR number for the current branch:

### GitHub

```bash
gh pr list --head <branch-name> --state open --json number,title
```

### GitLab

```bash
glab mr list --source-branch <branch-name>
```

### Bitbucket

```bash
BRANCH=$(git branch --show-current)
NEXT_URL="$BB_API_URL/2.0/repositories/$BB_WORKSPACE/$BB_REPO/pullrequests?state=OPEN"
FOUND_PR=0
SEEN_URLS=""
PAGE_COUNT=0
MAX_PAGES=100

while [ -n "$NEXT_URL" ]; do
  # Check for URL cycle
  case " $SEEN_URLS " in
    *" $NEXT_URL "*)
      echo "Error: Bitbucket API returned a cyclic next URL; aborting to prevent infinite loop" >&2
      exit 1
      ;;
  esac
  SEEN_URLS="$SEEN_URLS $NEXT_URL"

  # Check page limit
  PAGE_COUNT=$((PAGE_COUNT + 1))
  if [ "$PAGE_COUNT" -gt "$MAX_PAGES" ]; then
    echo "Error: Exceeded maximum page limit ($MAX_PAGES) while searching for PR; aborting" >&2
    exit 1
  fi

  if ! RESPONSE=$(curl -s -w "\n%{http_code}" --connect-timeout 10 --max-time 30 --netrc-file "$BB_NETRC" "$NEXT_URL"); then
    echo "Error: Bitbucket API request failed (curl error)" >&2
    exit 1
  fi
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  BODY=$(echo "$RESPONSE" | sed '$d')

  case "$HTTP_CODE" in
    ''|*[!0-9]*)
      echo "Error: Bitbucket API returned an invalid HTTP status: ${HTTP_CODE:-empty}" >&2
      exit 1
      ;;
  esac

  if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
    echo "Error: API request failed with HTTP status $HTTP_CODE" >&2
    exit 1
  fi

  MATCH=$(printf '%s' "$BODY" | python3 -c '
import sys, json
data = json.load(sys.stdin)
branch = sys.argv[1]
for pr in data.get("values", []):
    if pr["source"]["branch"]["name"] == branch:
        print(json.dumps({"id": pr["id"], "title": pr["title"]}))
        break
' "$BRANCH"
  ) || exit 1

  if [ -n "$MATCH" ]; then
    printf '%s\n' "$MATCH"
    FOUND_PR=1
    break
  fi

  NEXT_URL=$(printf '%s' "$BODY" | python3 -c '
import sys, json
data = json.load(sys.stdin)
print(data.get("next", ""))
') || exit 1

  # Validate NEXT_URL points to the same host as BB_API_URL before using it
  if [ -n "$NEXT_URL" ]; then
    if ! python3 - "$NEXT_URL" "$BB_API_URL" <<'PY'
import sys
from urllib.parse import urlsplit

next_url = sys.argv[1]
api_url = sys.argv[2]

next_parsed = urlsplit(next_url)
api_parsed = urlsplit(api_url)

# Validate scheme, hostname, and port match exactly
if (next_parsed.scheme != api_parsed.scheme or
    next_parsed.hostname != api_parsed.hostname or
    next_parsed.port != api_parsed.port):
    print(f"Error: Bitbucket API returned next URL with mismatched host/scheme: {next_url}", file=sys.stderr)
    sys.exit(1)
PY
    then
      exit 1
    fi
  fi
done

if [ "$FOUND_PR" -eq 0 ]; then
  echo "No open pull request found for branch: $BRANCH" >&2
fi
```

### Azure DevOps

```bash
az repos pr list --organization "$ADO_ORGANIZATION" --project "$ADO_PROJECT" --repository "$ADO_REPO" --source-branch <branch-name> --status active --output json
```

## Fetch Review Comments

Qodo posts both **summary comments** (PR-level) and **inline review comments** (per-line). Fetch both.

### GitHub

```bash
# PR-level comments (includes the summary comment with all issues)
gh pr view <pr-number> --json comments

# Inline review comments (per-line comments on specific code)
# Use pagination and flatten page arrays
gh api repos/{owner}/{repo}/pulls/<pr-number>/comments --paginate --slurp | python3 -c 'import json, sys; print(json.dumps([item for page in json.load(sys.stdin) for item in page]))'
```

### GitLab

```bash
# All MR notes including inline comments
glab mr view <mr-iid> --comments
```

### Bitbucket

```bash
# All PR comments including inline comments
# Follow paginated "next" URLs and merge all values arrays
NEXT_URL="$BB_API_URL/2.0/repositories/$BB_WORKSPACE/$BB_REPO/pullrequests/<pr-id>/comments"
SEEN_URLS=""
PAGE_COUNT=0
MAX_PAGES=100
ALL_COMMENTS="[]"

while [ -n "$NEXT_URL" ]; do
  # Check for URL cycle
  case " $SEEN_URLS " in
    *" $NEXT_URL "*)
      echo "Error: Bitbucket API returned a cyclic next URL; aborting to prevent infinite loop" >&2
      exit 1
      ;;
  esac
  SEEN_URLS="$SEEN_URLS $NEXT_URL"

  # Check page limit
  PAGE_COUNT=$((PAGE_COUNT + 1))
  if [ "$PAGE_COUNT" -gt "$MAX_PAGES" ]; then
    echo "Error: Exceeded maximum page limit ($MAX_PAGES) while fetching comments; aborting" >&2
    exit 1
  fi

  if ! RESPONSE=$(curl -s -w "\n%{http_code}" --connect-timeout 10 --max-time 30 --netrc-file "$BB_NETRC" "$NEXT_URL"); then
    echo "Error: Bitbucket API request failed (curl error)" >&2
    exit 1
  fi
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  BODY=$(echo "$RESPONSE" | sed '$d')

  case "$HTTP_CODE" in
    ''|*[!0-9]*)
      echo "Error: Bitbucket API returned an invalid HTTP status: ${HTTP_CODE:-empty}" >&2
      exit 1
      ;;
  esac

  if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
    echo "Error: API request failed with HTTP status $HTTP_CODE" >&2
    exit 1
  fi

  # Merge this page's values array into accumulated results
  ALL_COMMENTS=$(printf '%s\n%s' "$ALL_COMMENTS" "$BODY" | python3 -c '
import sys, json
accumulated = json.loads(sys.stdin.readline())
page_data = json.load(sys.stdin)
accumulated.extend(page_data.get("values", []))
print(json.dumps(accumulated))
') || exit 1

  NEXT_URL=$(printf '%s' "$BODY" | python3 -c '
import sys, json
data = json.load(sys.stdin)
print(data.get("next", ""))
') || exit 1

  # Validate NEXT_URL points to the same host as BB_API_URL before using it
  if [ -n "$NEXT_URL" ]; then
    if ! python3 - "$NEXT_URL" "$BB_API_URL" <<'PY'
import sys
from urllib.parse import urlsplit

next_url = sys.argv[1]
api_url = sys.argv[2]

next_parsed = urlsplit(next_url)
api_parsed = urlsplit(api_url)

# Validate scheme, hostname, and port match exactly
if (next_parsed.scheme != api_parsed.scheme or
    next_parsed.hostname != api_parsed.hostname or
    next_parsed.port != api_parsed.port):
    print(f"Error: Bitbucket API returned next URL with mismatched host/scheme: {next_url}", file=sys.stderr)
    sys.exit(1)
PY
    then
      exit 1
    fi
  fi
done

printf '%s\n' "$ALL_COMMENTS"
```

### Azure DevOps

```bash
# List all PR threads (includes both summary and inline comments)
# Note: az repos pr thread subcommands do not exist — use az devops invoke
az devops invoke \
  --organization "$ADO_ORGANIZATION" \
  --area git \
  --resource pullRequestThreads \
  --route-parameters project="$ADO_PROJECT" repositoryId="$ADO_REPO_ID" pullRequestId=<pr-id> \
  --http-method GET \
  --api-version 7.1 \
  --output json
```

## Reply to Inline Comments

Use the inline comment ID preserved during deduplication to reply directly to Qodo's comments.

### GitHub

```bash
gh api repos/{owner}/{repo}/pulls/<pr-number>/comments/<inline-comment-id>/replies \
  -X POST \
  -f body='<reply-body>'
```

**Reply format:**
- **Fixed:** `✅ **Fixed** — <what changed, stated directionally (e.g. "added guard clause" / "removed guard clause" / "inverted condition") so a later round can detect a reversal>`
- **Deferred:** `⏭️ **Deferred** — <reason for deferring>`

### GitLab

```bash
glab api "/projects/:id/merge_requests/<mr-iid>/discussions/<discussion-id>/notes" \
  -X POST \
  -f body='<reply-body>'
```

### Bitbucket

```bash
# Serialize dynamic value before embedding in JSON
REPLY_BODY_JSON=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "<reply-body>")

if ! RESPONSE=$(curl -s -w "\n%{http_code}" --connect-timeout 10 --max-time 30 --netrc-file "$BB_NETRC" \
  -H "Content-Type: application/json" \
  -X POST \
  "$BB_API_URL/2.0/repositories/$BB_WORKSPACE/$BB_REPO/pullrequests/<pr-id>/comments" \
  -d "{\"content\": {\"raw\": ${REPLY_BODY_JSON}}, \"parent\": {\"id\": <inline-comment-id>}}"); then
  echo "Error: Bitbucket inline reply failed (curl error)" >&2
  continue
fi
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
  ''|*[!0-9]*)
    echo "Error: Bitbucket inline reply returned invalid HTTP status: ${HTTP_CODE:-empty}" >&2
    continue
    ;;
esac

if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
  echo "Error: Bitbucket inline reply failed with HTTP status $HTTP_CODE" >&2
  continue
fi

echo "$BODY"
```

### Azure DevOps

```bash
# Add a reply comment to an existing thread (az repos pr thread does not exist)
REPLY_BODY=$(cat <<'EOF'
<reply-body>
EOF
)
REPLY_BODY_JSON=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$REPLY_BODY") || { echo "Error: Failed to serialize Azure DevOps reply body" >&2; continue; }
ADO_COMMENT_FILE=$(mktemp "${TMPDIR:-/tmp}/ado_comment.XXXXXX") || { echo "Error: Failed to create temp file for Azure DevOps reply" >&2; continue; }
trap 'rm -f "$ADO_COMMENT_FILE"' EXIT
trap 'rm -f "$ADO_COMMENT_FILE"; exit 129' HUP
trap 'rm -f "$ADO_COMMENT_FILE"; exit 130' INT
trap 'rm -f "$ADO_COMMENT_FILE"; exit 143' TERM
printf '%s\n' "{\"content\": ${REPLY_BODY_JSON}, \"commentType\": 1}" > "$ADO_COMMENT_FILE" || { echo "Error: Failed to write Azure DevOps reply payload" >&2; rm -f "$ADO_COMMENT_FILE"; continue; }
if ! az devops invoke \
  --organization "$ADO_ORGANIZATION" \
  --area git \
  --resource pullRequestThreadComments \
  --route-parameters project="$ADO_PROJECT" repositoryId="$ADO_REPO_ID" pullRequestId="<pr-id>" threadId="<thread-id>" \
  --http-method POST \
  --api-version 7.1 \
  --in-file "$ADO_COMMENT_FILE" \
  --output json; then
  echo "Error: Failed to post reply comment to Azure DevOps thread" >&2
  rm -f "$ADO_COMMENT_FILE"
  continue
fi
rm -f "$ADO_COMMENT_FILE"
```

## Resolve Inline Threads

Posting a reply does **not** resolve its inline thread. After the reply succeeds, use the operation for the active provider. Resolve only the thread correlated with the finding's preserved inline comment or discussion ID.

### GitHub

GitHub resolves pull-request review threads through GraphQL. First map the preserved inline comment database ID to its review-thread node ID, then resolve that node:

```bash
THREAD_ID=""
CURSOR=""
PAGE_COUNT=0
MAX_PAGES=100
while true; do
  PAGE_COUNT=$((PAGE_COUNT + 1))
  if [ "$PAGE_COUNT" -gt "$MAX_PAGES" ]; then
    echo "Error: Exceeded maximum page limit ($MAX_PAGES) while searching for GitHub review thread; aborting" >&2
    break
  fi

  THREAD_ID=$(gh api graphql \
    -f owner='{owner}' -f repo='{repo}' -F number=<pr-number> \
    ${CURSOR:+-f after="$CURSOR"} \
    -f query='query($owner:String!,$repo:String!,$number:Int!,$after:String){repository(owner:$owner,name:$repo){pullRequest(number:$number){reviewThreads(first:100,after:$after){nodes{id isResolved comments(first:100){nodes{databaseId}}} pageInfo{hasNextPage endCursor}}}}}' \
    --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(any(.comments.nodes[]; .databaseId == <inline-comment-id>)) | .id') || exit 1

  if [ -n "$THREAD_ID" ]; then
    break
  fi

  HAS_NEXT=$(gh api graphql \
    -f owner='{owner}' -f repo='{repo}' -F number=<pr-number> \
    ${CURSOR:+-f after="$CURSOR"} \
    -f query='query($owner:String!,$repo:String!,$number:Int!,$after:String){repository(owner:$owner,name:$repo){pullRequest(number:$number){reviewThreads(first:100,after:$after){nodes{id isResolved comments(first:100){nodes{databaseId}}} pageInfo{hasNextPage endCursor}}}}}' \
    --jq '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage') || exit 1
  if [ "$HAS_NEXT" != "true" ]; then
    break
  fi

  NEW_CURSOR=$(gh api graphql \
    -f owner='{owner}' -f repo='{repo}' -F number=<pr-number> \
    ${CURSOR:+-f after="$CURSOR"} \
    -f query='query($owner:String!,$repo:String!,$number:Int!,$after:String){repository(owner:$owner,name:$repo){pullRequest(number:$number){reviewThreads(first:100,after:$after){nodes{id isResolved comments(first:100){nodes{databaseId}}} pageInfo{hasNextPage endCursor}}}}}' \
    --jq '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor') || exit 1

  # Validate the new cursor is non-empty and different from current cursor
  if [ -z "$NEW_CURSOR" ] || [ "$NEW_CURSOR" = "$CURSOR" ]; then
    echo "Error: GitHub API returned empty or unchanged endCursor; aborting to prevent infinite loop" >&2
    break
  fi
  CURSOR="$NEW_CURSOR"
done

[ -n "${THREAD_ID}" ] || { echo 'Error: GitHub review thread not found.' >&2; exit 1; }
gh api graphql \
  -f threadId="${THREAD_ID}" \
  -f query='mutation($threadId:ID!){resolveReviewThread(input:{threadId:$threadId}){thread{id isResolved}}}'
```

### GitLab

```bash
glab api "/projects/:id/merge_requests/<mr-iid>/discussions/<discussion-id>" \
  -X PUT \
  -f resolved=true
```

### Bitbucket

```bash
curl --fail --silent --show-error --connect-timeout 10 --max-time 30 --netrc-file "$BB_NETRC" \
  -X POST \
  "$BB_API_URL/2.0/repositories/$BB_WORKSPACE/$BB_REPO/pullrequests/<pr-id>/comments/<inline-comment-id>/resolve"
```

### Azure DevOps

```bash
umask 077
ADO_STATUS_FILE=$(mktemp "${TMPDIR:-/tmp}/ado_status.XXXXXX") || exit 1
trap 'rm -f "${ADO_STATUS_FILE}"' EXIT
trap 'rm -f "${ADO_STATUS_FILE}"; exit 129' HUP
trap 'rm -f "${ADO_STATUS_FILE}"; exit 130' INT
trap 'rm -f "${ADO_STATUS_FILE}"; exit 143' TERM
printf '%s\n' '{"status": "fixed"}' > "${ADO_STATUS_FILE}" || exit 1
if ! az devops invoke \
  --organization "$ADO_ORGANIZATION" \
  --area git \
  --resource pullRequestThreads \
  --route-parameters project="$ADO_PROJECT" repositoryId="$ADO_REPO_ID" pullRequestId="<pr-id>" threadId="<thread-id>" \
  --http-method PATCH \
  --api-version 7.1 \
  --in-file "${ADO_STATUS_FILE}" \
  --output json; then
  echo "Error: Failed to resolve Azure DevOps inline thread" >&2
  rm -f "${ADO_STATUS_FILE}"
  exit 1
fi
rm -f "${ADO_STATUS_FILE}"
```

## Post Summary Comment

After reviewing all issues, post a summary comment to the PR/MR.

### GitHub

```bash
gh pr comment <pr-number> --body '<comment-body>'
```

### GitLab

```bash
glab mr comment <mr-iid> --message '<comment-body>'
```

### Bitbucket

```bash
# Serialize dynamic value before embedding in JSON
COMMENT_BODY_JSON=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "<comment-body>")

if ! RESPONSE=$(curl -s -w "\n%{http_code}" --connect-timeout 10 --max-time 30 --netrc-file "$BB_NETRC" \
  -H "Content-Type: application/json" \
  -X POST \
  "$BB_API_URL/2.0/repositories/$BB_WORKSPACE/$BB_REPO/pullrequests/<pr-id>/comments" \
  -d "{\"content\": {\"raw\": ${COMMENT_BODY_JSON}}}"); then
  echo "Error: Bitbucket API request failed (curl error)" >&2
  exit 1
fi
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
  ''|*[!0-9]*)
    echo "Error: Bitbucket API returned an invalid HTTP status: ${HTTP_CODE:-empty}" >&2
    exit 1
    ;;
esac

if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
  echo "Error: API request failed with HTTP status $HTTP_CODE" >&2
  exit 1
fi

echo "$BODY"
```

### Azure DevOps

```bash
# Create a new top-level comment thread (az repos pr thread create does not exist)
COMMENT_BODY=$(cat <<'EOF'
<comment-body>
EOF
)
COMMENT_BODY_JSON=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$COMMENT_BODY") || exit 1
ADO_THREAD_FILE=$(mktemp "${TMPDIR:-/tmp}/ado_thread.XXXXXX") || exit 1
trap 'rm -f "$ADO_THREAD_FILE"' EXIT
trap 'rm -f "$ADO_THREAD_FILE"; exit 129' HUP
trap 'rm -f "$ADO_THREAD_FILE"; exit 130' INT
trap 'rm -f "$ADO_THREAD_FILE"; exit 143' TERM
printf '%s\n' "{\"comments\": [{\"content\": ${COMMENT_BODY_JSON}, \"commentType\": 1}], \"status\": \"active\"}" > "$ADO_THREAD_FILE" || exit 1
if ! az devops invoke \
  --organization "$ADO_ORGANIZATION" \
  --area git \
  --resource pullRequestThreads \
  --route-parameters project="$ADO_PROJECT" repositoryId="$ADO_REPO_ID" pullRequestId="<pr-id>" \
  --http-method POST \
  --api-version 7.1 \
  --in-file "$ADO_THREAD_FILE" \
  --output json; then
  echo "Error: Failed to create Azure DevOps summary comment thread" >&2
  rm -f "$ADO_THREAD_FILE"
  exit 1
fi
rm -f "$ADO_THREAD_FILE"
```

**Summary format:** (the `— Round N` heading and `Generated by Qodo PR Resolver skill` footer are how the *next* resolver run detects this round — see SKILL.md Step 3c; `N` = current round number)

```markdown
## Qodo Fix Summary — Round N

Reviewed and addressed Qodo review issues:

### ✅ Fixed Issues
- **Issue Title** (Severity) - what changed, stated directionally (e.g. "added guard clause" / "removed guard clause" / "inverted condition") so a later round can detect a reversal

### ⏭️ Deferred Issues
- **Issue Title** (Severity) - Reason for deferring

<!-- Include the next section ONLY when the oscillation guard held or hard-stopped an issue (see SKILL.md Step 8); omit it entirely otherwise. -->
### 🛑 Skipped to prevent oscillation — recommend human resolution
- **Issue Title** (`file:line`) - oscillation reason (e.g. held prior decision from round N / flipped ≥2 times)

---
[![Qodo](https://www.qodo.ai/wp-content/uploads/2025/03/qodo-logo.svg)](https://qodo.ai)
Generated by Qodo PR Resolver skill
```

## Resolve Qodo Review Comment

After posting the summary, resolve the main Qodo review comment.

**Steps:**
1. Fetch all PR/MR comments
2. Find the Qodo bot comment containing "Code Review by Qodo"
3. Resolve or react to the comment

### GitHub

```bash
# 1. Fetch comments to find the comment ID
gh pr view <pr-number> --json comments

# 2. React with thumbs up to acknowledge
gh api "repos/{owner}/{repo}/issues/comments/<comment-id>/reactions" \
  -X POST \
  -f content='+1'
```

### GitLab

```bash
# 1. Fetch discussions to find the discussion ID
glab api "/projects/:id/merge_requests/<mr-iid>/discussions"

# 2. Resolve the discussion
glab api "/projects/:id/merge_requests/<mr-iid>/discussions/<discussion-id>" \
  -X PUT \
  -f resolved=true
```

### Bitbucket

```bash
# Resolve a comment using the dedicated /resolve endpoint (POST, no body required)
if ! RESPONSE=$(curl -s -w "\n%{http_code}" --connect-timeout 10 --max-time 30 --netrc-file "$BB_NETRC" \
  -X POST \
  "$BB_API_URL/2.0/repositories/$BB_WORKSPACE/$BB_REPO/pullrequests/<pr-id>/comments/<comment-id>/resolve"); then
  echo "Error: Bitbucket API request failed (curl error)" >&2
  exit 1
fi
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
  ''|*[!0-9]*)
    echo "Error: Bitbucket API returned an invalid HTTP status: ${HTTP_CODE:-empty}" >&2
    exit 1
    ;;
esac

if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
  echo "Error: API request failed with HTTP status $HTTP_CODE" >&2
  exit 1
fi

echo "$BODY"
```

### Azure DevOps

```bash
# Mark the thread as fixed (Azure DevOps uses "fixed" not "resolved"; az repos pr thread update does not exist)
umask 077
ADO_STATUS_FILE=$(mktemp "${TMPDIR:-/tmp}/ado_status.XXXXXX") || exit 1
trap 'rm -f "${ADO_STATUS_FILE}"' EXIT
trap 'rm -f "${ADO_STATUS_FILE}"; exit 129' HUP
trap 'rm -f "${ADO_STATUS_FILE}"; exit 130' INT
trap 'rm -f "${ADO_STATUS_FILE}"; exit 143' TERM
printf '%s\n' '{"status": "fixed"}' > "${ADO_STATUS_FILE}" || exit 1
if ! az devops invoke \
  --organization "$ADO_ORGANIZATION" \
  --area git \
  --resource pullRequestThreads \
  --route-parameters project="$ADO_PROJECT" repositoryId="$ADO_REPO_ID" pullRequestId="<pr-id>" threadId="<thread-id>" \
  --http-method PATCH \
  --api-version 7.1 \
  --in-file "${ADO_STATUS_FILE}" \
  --output json; then
  echo "Error: Failed to mark Azure DevOps thread as fixed" >&2
  rm -f "${ADO_STATUS_FILE}"
  exit 1
fi
rm -f "${ADO_STATUS_FILE}"
```

## Create PR/MR

If no PR/MR exists for the current branch, create one. The user chooses between draft or regular mode — add the `--draft` flag when creating in draft mode.

### GitHub

```bash
gh pr create --title '<title>' --body '<body>'
```

Add `--draft` flag when creating in draft mode.

### GitLab

```bash
glab mr create --title '<title>' --description '<body>'
```

Add `--draft` flag when creating in draft mode.

### Bitbucket

```bash
BRANCH=$(git branch --show-current)
DEST_BRANCH=${BB_DEST_BRANCH:-}
if [ -z "$DEST_BRANCH" ]; then
  if ! REPO_METADATA=$(curl -fsS --connect-timeout 10 --max-time 30 --netrc-file "$BB_NETRC" \
    "$BB_API_URL/2.0/repositories/$BB_WORKSPACE/$BB_REPO"); then
    echo "Error: Unable to retrieve the Bitbucket repository's main branch" >&2
    exit 1
  fi
  DEST_BRANCH=$(printf '%s' "$REPO_METADATA" | \
    python3 -c 'import json,sys; print((json.load(sys.stdin).get("mainbranch") or {}).get("name") or "")')
fi
if [ -z "$DEST_BRANCH" ]; then
  echo "Error: Bitbucket did not provide a destination branch; set BB_DEST_BRANCH explicitly" >&2
  exit 1
fi
# Serialize dynamic values before embedding in JSON
TITLE_JSON=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "<title>")
BODY_JSON=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "<body>")
BRANCH_JSON=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$BRANCH")
DEST_BRANCH_JSON=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$DEST_BRANCH")

if ! RESPONSE=$(curl -s -w "\n%{http_code}" --connect-timeout 10 --max-time 30 --netrc-file "$BB_NETRC" \
  -H "Content-Type: application/json" \
  -X POST \
  "$BB_API_URL/2.0/repositories/$BB_WORKSPACE/$BB_REPO/pullrequests" \
  -d "{
    \"title\": ${TITLE_JSON},
    \"description\": ${BODY_JSON},
    \"source\": {\"branch\": {\"name\": ${BRANCH_JSON}}},
    \"destination\": {\"branch\": {\"name\": ${DEST_BRANCH_JSON}}}
  }"); then
  echo "Error: Bitbucket API request failed (curl error)" >&2
  exit 1
fi
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
  ''|*[!0-9]*)
    echo "Error: Bitbucket API returned an invalid HTTP status: ${HTTP_CODE:-empty}" >&2
    exit 1
    ;;
esac

if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
  echo "Error: API request failed with HTTP status $HTTP_CODE" >&2
  exit 1
fi

echo "$BODY"
```

Set `BB_DEST_BRANCH` before running the example to target an explicitly selected branch. Otherwise, the example retrieves Bitbucket Cloud's configured `mainbranch` for the repository instead of assuming `main`.

**Note:** Bitbucket Cloud has no native draft PR API. When creating in draft mode, prefix the title with `[DRAFT]` as a convention (e.g. `[DRAFT] <title>`).

### Azure DevOps

```bash
# Determine target branch: use ADO_TARGET_BRANCH if set, otherwise query the repo default
if [ -z "${ADO_TARGET_BRANCH:-}" ]; then
  if ! ADO_DEFAULT_BRANCH=$(az repos show \
    --organization "$ADO_ORGANIZATION" \
    --project "$ADO_PROJECT" \
    --repository "$ADO_REPO" \
    --query defaultBranch -o tsv); then
    echo "Error: Failed to query Azure DevOps repository default branch" >&2
    exit 1
  fi
  # Strip refs/heads/ prefix
  ADO_TARGET_BRANCH=${ADO_DEFAULT_BRANCH#refs/heads/}
  if [ -z "$ADO_TARGET_BRANCH" ]; then
    echo "Error: Azure DevOps repository default branch is empty" >&2
    exit 1
  fi
fi

az repos pr create \
  --organization "$ADO_ORGANIZATION" \
  --project "$ADO_PROJECT" \
  --repository "$ADO_REPO" \
  --title '<title>' \
  --description '<body>' \
  --source-branch <branch-name> \
  --target-branch "$ADO_TARGET_BRANCH"
```

Add `--draft` flag when creating in draft mode.

## Mark PR Ready for Review

After all fixes are applied, if the PR was created as a draft, optionally mark it as ready for review.

### GitHub

```bash
gh pr ready <pr-number>
```

### GitLab

```bash
glab mr update <mr-iid> --ready
```

### Bitbucket

If the title was prefixed with `[DRAFT]`, update it to remove the prefix:

```bash
TITLE_JSON=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "<title-without-draft-prefix>")

if ! RESPONSE=$(curl -s -w "\n%{http_code}" --connect-timeout 10 --max-time 30 --netrc-file "$BB_NETRC" \
  -H "Content-Type: application/json" \
  -X PUT \
  "$BB_API_URL/2.0/repositories/$BB_WORKSPACE/$BB_REPO/pullrequests/<pr-id>" \
  -d "{\"title\": ${TITLE_JSON}}"); then
  echo "Error: Bitbucket API request failed (curl error)" >&2
  exit 1
fi
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
  ''|*[!0-9]*)
    echo "Error: Bitbucket API returned an invalid HTTP status: ${HTTP_CODE:-empty}" >&2
    exit 1
    ;;
esac

if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
  echo "Error: API request failed with HTTP status $HTTP_CODE" >&2
  exit 1
fi

echo "$BODY"
```

### Azure DevOps

```bash
az repos pr update --organization "$ADO_ORGANIZATION" --project "$ADO_PROJECT" --id <pr-id> --draft false
```

## Error Handling

### Missing CLI Tool

If the detected provider's CLI is not installed:
1. Inform the user: "❌ Missing required CLI tool: `<cli-name>`"
2. Provide installation instructions from the Prerequisites section
3. Exit the skill

### Unsupported Provider

If the remote URL doesn't match any supported provider:
1. Inform: "❌ Unsupported git provider detected: `<url>`"
2. List supported providers: GitHub, GitLab, Bitbucket, Azure DevOps, Gerrit
3. Exit the skill

### API Failures

**Summary posting failures:** If the summary comment (Step 9) fails to post, stop the workflow before resolving remaining review state. Record that the round record from Step 3c was not created. Report that the user must retry summary publication before proceeding with resolution operations.

**Inline reply failures:** If an individual inline reply fails, log the error and continue with remaining operations. The workflow should not abort due to inline comment posting failures.
