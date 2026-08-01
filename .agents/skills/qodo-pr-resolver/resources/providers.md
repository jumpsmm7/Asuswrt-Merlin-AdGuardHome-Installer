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
- `dev.azure.com`, or the host configured by `AZURE_DEVOPS_URL` → Azure DevOps
- `.gitreview` file or port `29418` or `googlesource.com` → Gerrit (see [gerrit.md](./gerrit.md))

## Prerequisites by Provider

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
  QODO_CONFIG=${QODO_CONFIG:-${HOME}/.qodo/config.json}
  if [ -f "$QODO_CONFIG" ]; then
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
  BB_NETRC="${HOME}/.netrc.bitbucket"
  umask 077
  if ! BB_NETRC_TMP=$(mktemp "${BB_NETRC}.XXXXXX"); then
    echo "Failed to create temporary netrc file" >&2
    exit 1
  fi
  trap 'rm -f "$BB_NETRC_TMP"' EXIT INT TERM
  if ! cat > "$BB_NETRC_TMP" << EOF
machine $BB_HOST
login $BB_USERNAME
password $BB_APP_PASSWORD
EOF
  then
    echo "Failed to write netrc file" >&2
    exit 1
  fi
  if ! chmod 600 "$BB_NETRC_TMP"; then
    echo "Failed to set permissions on netrc file" >&2
    exit 1
  fi
  if ! mv -f "$BB_NETRC_TMP" "$BB_NETRC"; then
    echo "Failed to move netrc file into place" >&2
    exit 1
  fi
  trap - EXIT INT TERM
  ```
- **Verify:**
  ```bash
  curl -s --netrc-file "$BB_NETRC" \
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
  QODO_CONFIG=${QODO_CONFIG:-${HOME}/.qodo/config.json}
  if [ -f "$QODO_CONFIG" ]; then
    [ -n "${AZURE_DEVOPS_EXT_PAT:-}" ] || AZURE_DEVOPS_EXT_PAT=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("AZURE_DEVOPS_EXT_PAT", ""))' "$QODO_CONFIG")
    [ -n "${AZURE_DEVOPS_URL:-}" ] || AZURE_DEVOPS_URL=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("AZURE_DEVOPS_URL", ""))' "$QODO_CONFIG")
  fi
  export AZURE_DEVOPS_EXT_PAT
  if [ -z "${AZURE_DEVOPS_EXT_PAT:-}" ]; then
    az login
  fi
  # Normalize the configured service/collection URL. For Azure DevOps Cloud,
  # the organization is the first path component after dev.azure.com. For
  # Azure DevOps Server, AZURE_DEVOPS_URL is the collection URL itself.
  ADO_BASE_URL=${AZURE_DEVOPS_URL:-https://dev.azure.com}
  ADO_BASE_URL=${ADO_BASE_URL%/}
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
  az devops configure --defaults organization="$ADO_ORGANIZATION" project="$ADO_PROJECT"
  # Get repository ID (required for thread API calls):
  ADO_REPO_ID=$(az repos show --name "$ADO_REPO" --query id -o tsv)
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
if ! RESPONSE=$(curl -s -w "\n%{http_code}" --netrc-file "$BB_NETRC" \
  "$BB_API_URL/2.0/repositories/$BB_WORKSPACE/$BB_REPO/pullrequests?state=OPEN"); then
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

echo "$BODY" | python3 -c '
import sys, json
data = json.load(sys.stdin)
branch = sys.argv[1]
for pr in data.get('values', []):
    if pr["source"]["branch"]["name"] == branch:
        print(json.dumps({"id": pr["id"], "title": pr["title"]}, indent=2))
' "$BRANCH"
```

### Azure DevOps

```bash
az repos pr list --source-branch <branch-name> --status active --output json
```

## Fetch Review Comments

Qodo posts both **summary comments** (PR-level) and **inline review comments** (per-line). Fetch both.

### GitHub

```bash
# PR-level comments (includes the summary comment with all issues)
gh pr view <pr-number> --json comments

# Inline review comments (per-line comments on specific code)
gh api repos/{owner}/{repo}/pulls/<pr-number>/comments
```

### GitLab

```bash
# All MR notes including inline comments
glab mr view <mr-iid> --comments
```

### Bitbucket

```bash
# All PR comments including inline comments
curl --fail --silent --show-error --netrc-file "$BB_NETRC" \
  "$BB_API_URL/2.0/repositories/$BB_WORKSPACE/$BB_REPO/pullrequests/<pr-id>/comments"
```

### Azure DevOps

```bash
# List all PR threads (includes both summary and inline comments)
# Note: az repos pr thread subcommands do not exist — use az devops invoke
az devops invoke \
  --area git \
  --resource pullRequestThreads \
  --route-parameters project=$ADO_PROJECT repositoryId=$ADO_REPO_ID pullRequestId=<pr-id> \
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

if ! RESPONSE=$(curl -s -w "\n%{http_code}" --netrc-file "$BB_NETRC" \
  -H "Content-Type: application/json" \
  -X POST \
  "$BB_API_URL/2.0/repositories/$BB_WORKSPACE/$BB_REPO/pullrequests/<pr-id>/comments" \
  -d "{\"content\": {\"raw\": ${REPLY_BODY_JSON}}, \"parent\": {\"id\": <inline-comment-id>}}"); then
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
# Add a reply comment to an existing thread (az repos pr thread does not exist)
REPLY_BODY=$(cat <<'EOF'
<reply-body>
EOF
)
REPLY_BODY_JSON=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$REPLY_BODY") || exit 1
ADO_COMMENT_FILE=$(mktemp) || exit 1
trap 'rm -f "$ADO_COMMENT_FILE"' EXIT HUP INT TERM
printf '%s\n' "{\"content\": ${REPLY_BODY_JSON}, \"commentType\": 1}" > "$ADO_COMMENT_FILE" || exit 1
az devops invoke \
  --area git \
  --resource pullRequestThreadComments \
  --route-parameters project=$ADO_PROJECT repositoryId=$ADO_REPO_ID pullRequestId=<pr-id> threadId=<thread-id> \
  --http-method POST \
  --api-version 7.1 \
  --in-file "$ADO_COMMENT_FILE" \
  --output json
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

if ! RESPONSE=$(curl -s -w "\n%{http_code}" --netrc-file "$BB_NETRC" \
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
ADO_THREAD_FILE=$(mktemp) || exit 1
trap 'rm -f "$ADO_THREAD_FILE"' EXIT HUP INT TERM
printf '%s\n' "{\"comments\": [{\"content\": ${COMMENT_BODY_JSON}, \"commentType\": 1}], \"status\": \"active\"}" > "$ADO_THREAD_FILE" || exit 1
az devops invoke \
  --area git \
  --resource pullRequestThreads \
  --route-parameters project=$ADO_PROJECT repositoryId=$ADO_REPO_ID pullRequestId=<pr-id> \
  --http-method POST \
  --api-version 7.1 \
  --in-file "$ADO_THREAD_FILE" \
  --output json
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
if ! RESPONSE=$(curl -s -w "\n%{http_code}" --netrc-file "$BB_NETRC" \
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
trap 'rm -f "${ADO_STATUS_FILE}"' EXIT HUP INT TERM
printf '%s\n' '{"status": "fixed"}' > "${ADO_STATUS_FILE}" || exit 1
az devops invoke \
  --area git \
  --resource pullRequestThreads \
  --route-parameters project=$ADO_PROJECT repositoryId=$ADO_REPO_ID pullRequestId=<pr-id> threadId=<thread-id> \
  --http-method PATCH \
  --api-version 7.1 \
  --in-file "${ADO_STATUS_FILE}" \
  --output json
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
# Serialize dynamic values before embedding in JSON
TITLE_JSON=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "<title>")
BODY_JSON=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "<body>")
BRANCH_JSON=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$BRANCH")
DEST_BRANCH_JSON=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "main")

if ! RESPONSE=$(curl -s -w "\n%{http_code}" --netrc-file "$BB_NETRC" \
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

**Note:** Bitbucket Cloud has no native draft PR API. When creating in draft mode, prefix the title with `[DRAFT]` as a convention (e.g. `[DRAFT] <title>`).

### Azure DevOps

```bash
az repos pr create \
  --title '<title>' \
  --description '<body>' \
  --source-branch <branch-name> \
  --target-branch main
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

if ! RESPONSE=$(curl -s -w "\n%{http_code}" --netrc-file "$BB_NETRC" \
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
az repos pr update --id <pr-id> --draft false
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

If inline reply or summary posting fails:
- Log the error
- Continue with remaining operations
- The workflow should not abort due to comment posting failures
