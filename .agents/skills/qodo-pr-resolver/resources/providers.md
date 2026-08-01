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
- `dev.azure.com` → Azure DevOps
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
    "BB_APP_PASSWORD": "your-app-password",
    "BB_URL": "https://bitbucket.example.com"
  }
  ```
  `BB_URL` is optional — only needed for self-hosted Bitbucket (defaults to `https://api.bitbucket.org`).
- Workspace and repo slug are extracted from the remote URL at runtime:
  ```bash
  BB_REMOTE=$(git remote get-url origin)
  BB_WORKSPACE=$(echo "$BB_REMOTE" | sed -E 's|.*bitbucket\.org[:/]([^/]+)/.*|\1|')
  BB_REPO=$(echo "$BB_REMOTE" | sed -E 's|.*bitbucket\.org[:/][^/]+/([^/.]+)(\.git)?$|\1|')
  ```
- **Verify:**
  ```bash
  curl -s -u "$BB_USERNAME:$BB_APP_PASSWORD" \
    "https://api.bitbucket.org/2.0/user" | python3 -m json.tool
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
  az login
  # Extract org/project from remote URL and configure defaults:
  ADO_REMOTE=$(git remote get-url origin)
  ADO_ORG=$(echo "$ADO_REMOTE" | sed -E 's|https://[^@]*@?dev\.azure\.com/([^/]+)/.*|\1|')
  ADO_PROJECT=$(echo "$ADO_REMOTE" | sed -E 's|https://[^/]*/[^/]+/([^/]+)/.*|\1|')
  ADO_REPO=$(echo "$ADO_REMOTE" | sed -E 's|.*/([^/]+)$|\1|')
  az devops configure --defaults organization=https://dev.azure.com/$ADO_ORG project=$ADO_PROJECT
  # Get repository ID (required for thread API calls):
  ADO_REPO_ID=$(az repos show --name $ADO_REPO --query id -o tsv)
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
curl -s -u "$BB_USERNAME:$BB_APP_PASSWORD" \
  "https://api.bitbucket.org/2.0/repositories/$BB_WORKSPACE/$BB_REPO/pullrequests?state=OPEN" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
branch = '$BRANCH'
for pr in data.get('values', []):
    if pr['source']['branch']['name'] == branch:
        print(json.dumps({'id': pr['id'], 'title': pr['title']}, indent=2))
"
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
curl -s -u "$BB_USERNAME:$BB_APP_PASSWORD" \
  "https://api.bitbucket.org/2.0/repositories/$BB_WORKSPACE/$BB_REPO/pullrequests/<pr-id>/comments"
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
curl -s -u "$BB_USERNAME:$BB_APP_PASSWORD" \
  -H "Content-Type: application/json" \
  -X POST \
  "https://api.bitbucket.org/2.0/repositories/$BB_WORKSPACE/$BB_REPO/pullrequests/<pr-id>/comments" \
  -d '{"content": {"raw": "<reply-body>"}, "parent": {"id": <inline-comment-id>}}'
```

### Azure DevOps

```bash
# Add a reply comment to an existing thread (az repos pr thread does not exist)
echo '{"content": "<reply-body>", "commentType": 1}' > /tmp/ado_comment.json
az devops invoke \
  --area git \
  --resource pullRequestThreadComments \
  --route-parameters project=$ADO_PROJECT repositoryId=$ADO_REPO_ID pullRequestId=<pr-id> threadId=<thread-id> \
  --http-method POST \
  --api-version 7.1 \
  --in-file /tmp/ado_comment.json \
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
curl -s -u "$BB_USERNAME:$BB_APP_PASSWORD" \
  -H "Content-Type: application/json" \
  -X POST \
  "https://api.bitbucket.org/2.0/repositories/$BB_WORKSPACE/$BB_REPO/pullrequests/<pr-id>/comments" \
  -d '{"content": {"raw": "<comment-body>"}}'
```

### Azure DevOps

```bash
# Create a new top-level comment thread (az repos pr thread create does not exist)
cat > /tmp/ado_thread.json << 'EOF'
{"comments": [{"content": "<comment-body>", "commentType": 1}], "status": "active"}
EOF
az devops invoke \
  --area git \
  --resource pullRequestThreads \
  --route-parameters project=$ADO_PROJECT repositoryId=$ADO_REPO_ID pullRequestId=<pr-id> \
  --http-method POST \
  --api-version 7.1 \
  --in-file /tmp/ado_thread.json \
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
curl -s -u "$BB_USERNAME:$BB_APP_PASSWORD" \
  -X POST \
  "https://api.bitbucket.org/2.0/repositories/$BB_WORKSPACE/$BB_REPO/pullrequests/<pr-id>/comments/<comment-id>/resolve"
```

### Azure DevOps

```bash
# Mark the thread as fixed (Azure DevOps uses "fixed" not "resolved"; az repos pr thread update does not exist)
echo '{"status": "fixed"}' > /tmp/ado_status.json
az devops invoke \
  --area git \
  --resource pullRequestThreads \
  --route-parameters project=$ADO_PROJECT repositoryId=$ADO_REPO_ID pullRequestId=<pr-id> threadId=<thread-id> \
  --http-method PATCH \
  --api-version 7.1 \
  --in-file /tmp/ado_status.json \
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
curl -s -u "$BB_USERNAME:$BB_APP_PASSWORD" \
  -H "Content-Type: application/json" \
  -X POST \
  "https://api.bitbucket.org/2.0/repositories/$BB_WORKSPACE/$BB_REPO/pullrequests" \
  -d "{
    \"title\": \"<title>\",
    \"description\": \"<body>\",
    \"source\": {\"branch\": {\"name\": \"$BRANCH\"}},
    \"destination\": {\"branch\": {\"name\": \"main\"}}
  }"
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
curl -s -u "$BB_USERNAME:$BB_APP_PASSWORD" \
  -H "Content-Type: application/json" \
  -X PUT \
  "https://api.bitbucket.org/2.0/repositories/$BB_WORKSPACE/$BB_REPO/pullrequests/<pr-id>" \
  -d '{"title": "<title-without-draft-prefix>"}'
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
