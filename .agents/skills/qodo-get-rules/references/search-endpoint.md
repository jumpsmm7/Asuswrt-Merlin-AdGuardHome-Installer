# POST /rules/search Endpoint

## Request

```http
POST {API_URL}/rules/search
Content-Type: application/json
Authorization: Bearer {API_KEY}
request-id: {REQUEST_ID}
qodo-client-type: skill-qodo-get-rules
```

**Body:**
```json
{
  "query": "<generated search query>",
  "top_k": 20,
  "scopes": ["/org/repo/"]
}
```

`scopes` is **optional**. It is omitted when the repository scope cannot be determined (no git remote, unparseable URL). When omitted, the search falls back to org-wide matching. Do not send `"scopes": null` or `"scopes": []` — omit the field entirely.

**`TOP_K` (tunable constant):** The number of results to request per query. Default: `20`. The skill generates two queries (topic + cross-cutting) and calls this endpoint once per query, each with `top_k=TOP_K`. Results are merged and deduplicated by rule ID — the final count depends on overlap between the two result sets.

Increase `TOP_K` if retrieval quality data shows relevant rules are being missed. No pagination is needed regardless of the value — the search endpoint returns up to `top_k` results in a single response.

**Merge strategy:** When merging topic and cross-cutting results:
1. Start with topic query results (in order of relevance).
2. Append cross-cutting results not already present, in order of relevance.

Topic results always take priority, ensuring task-specific rules are never pushed out by cross-cutting results.

## Response

```json
{
  "rules": [
    { "id": "...", "name": "...", "content": "...", "severity": "..." },
    ...
  ]
}
```

Rules are returned ranked by relevance (most relevant first). The list may be empty if no matching rules exist — this is a valid response; do not treat it as an error.

## API URL Construction

Construct `{API_URL}` using the following priority:

1. **`QODO_API_URL` environment variable** (highest priority): If the `QODO_API_URL` environment variable is set, use `{QODO_API_URL}/rules/v1` as the full API URL. The URL must use HTTPS and point to a trusted `*.qodo.ai` domain. The `/rules/v1` path is always appended internally — do not include it in the environment variable value. Trailing slashes are removed from the base URL before appending `/rules/v1` to prevent double slashes.

2. **`QODO_API_URL` in config** (fallback): If the environment variable is not set but `QODO_API_URL` is present in `~/.qodo/config.json`, use that value with the same validation and path appending rules (including trailing-slash removal).

3. **`ENVIRONMENT_NAME`-based construction** (final fallback): If `QODO_API_URL` is not set in either location, construct from `ENVIRONMENT_NAME` (read from `~/.qodo/config.json`, overridable via `QODO_ENVIRONMENT_NAME` env var):

| `ENVIRONMENT_NAME` | `{API_URL}` |
|---|---|
| not set / empty | `https://qodo-platform.qodo.ai/rules/v1` |
| `staging` | `https://qodo-platform.staging.qodo.ai/rules/v1` |
| `qodost.st` | `https://qodo-platform.qodost.st.qodo.ai/rules/v1` |

The `ENVIRONMENT_NAME` value must match `^[a-zA-Z0-9_.-]+$` and be non-empty before being used as a subdomain segment. Reject invalid values before URL construction.

**URL resolution priority:** `QODO_API_URL` environment variable → `QODO_API_URL` config value → `ENVIRONMENT_NAME` → production default

## Attribution Headers

All requests must include attribution headers per the [usage tracking guidelines](../../../references/usage-tracking.md):

| Header | Value |
|---|---|
| `Authorization` | `Bearer {API_KEY}` |
| `request-id` | UUID generated once per invocation |
| `qodo-client-type` | `skill-qodo-get-rules` |
| `trace_id` (optional) | Value of `TRACE_ID` env var if set |

## Example (curl)

```bash
# Build body with JSON escaping — include scopes only when SCOPE is set
BODY=$(SEARCH_QUERY="$SEARCH_QUERY" SCOPE="${SCOPE:-}" python3 - <<'PY'
import json
import os

payload = {"query": os.environ["SEARCH_QUERY"], "top_k": 20}
if os.environ.get("SCOPE"):
    payload["scopes"] = [os.environ["SCOPE"]]
print(json.dumps(payload))
PY
) || exit 1

umask 077
AUTH_HEADER=$(mktemp) || exit 1
trap 'rm -f "${AUTH_HEADER}"' EXIT HUP INT TERM
printf 'Authorization: Bearer %s\n' "${API_KEY}" >"${AUTH_HEADER}" || exit 1

curl --fail --show-error --silent --connect-timeout 10 --max-time 30 -X POST \
  -H "Content-Type: application/json" \
  -H "@${AUTH_HEADER}" \
  -H "request-id: ${REQUEST_ID}" \
  -H "qodo-client-type: skill-qodo-get-rules" \
  -d "${BODY}" \
  "${API_URL}/rules/search"
```

With optional trace header:

```bash
BODY=$(SEARCH_QUERY="$SEARCH_QUERY" SCOPE="${SCOPE:-}" python3 - <<'PY'
import json
import os

payload = {"query": os.environ["SEARCH_QUERY"], "top_k": 20}
if os.environ.get("SCOPE"):
    payload["scopes"] = [os.environ["SCOPE"]]
print(json.dumps(payload))
PY
) || exit 1

umask 077
AUTH_HEADER=$(mktemp) || exit 1
trap 'rm -f "${AUTH_HEADER}"' EXIT HUP INT TERM
printf 'Authorization: Bearer %s\n' "${API_KEY}" >"${AUTH_HEADER}" || exit 1

if [ -n "${TRACE_ID:-}" ]; then
  curl --fail --show-error --silent --connect-timeout 10 --max-time 30 -X POST \
    -H "Content-Type: application/json" \
    -H "@${AUTH_HEADER}" \
    -H "request-id: ${REQUEST_ID}" \
    -H "qodo-client-type: skill-qodo-get-rules" \
    -H "trace_id:${TRACE_ID}" \
    -d "${BODY}" \
    "${API_URL}/rules/search"
else
  curl --fail --show-error --silent --connect-timeout 10 --max-time 30 -X POST \
    -H "Content-Type: application/json" \
    -H "@${AUTH_HEADER}" \
    -H "request-id: ${REQUEST_ID}" \
    -H "qodo-client-type: skill-qodo-get-rules" \
    -d "${BODY}" \
    "${API_URL}/rules/search"
fi
```

## Example (Python)

```python
import json
import os
from urllib.error import HTTPError, URLError
from urllib.request import urlopen, Request

headers = {
    "Content-Type": "application/json",
    "Authorization": f"Bearer {api_key}",
    "request-id": request_id,
    "qodo-client-type": "skill-qodo-get-rules",
}
if trace_id := os.environ.get("TRACE_ID"):
    headers["trace_id"] = trace_id

payload = {"query": search_query, "top_k": 20}
if scope:  # omit field entirely when scope is not available
    payload["scopes"] = [scope]

body = json.dumps(payload).encode()
req = Request(f"{api_url}/rules/search", data=body, headers=headers, method="POST")
try:
    with urlopen(req, timeout=30) as resp:
        data = json.loads(resp.read())
except HTTPError as exc:
    raise SystemExit(f"Qodo rules request failed with HTTP status {exc.code}")
except (URLError, TimeoutError) as exc:
    raise SystemExit(f"Qodo rules request failed: {exc}")
except json.JSONDecodeError as exc:
    raise SystemExit(f"Qodo rules request failed: invalid JSON response")
else:
    if not isinstance(data, dict) or not isinstance(data.get("rules"), list):
        raise SystemExit("Qodo rules request failed: malformed response (expected object with 'rules' array)")
    # Validate each rule's schema and severity before accepting
    rules = []
    for entry in data.get("rules", []):
        if not isinstance(entry, dict):
            raise SystemExit("Qodo rules request failed: malformed response (rules array contains non-object entry)")
        if not isinstance(entry.get("name"), str) or not isinstance(entry.get("content"), str):
            raise SystemExit("Qodo rules request failed: malformed response (rule missing required string fields 'name' or 'content')")
        severity = entry.get("severity")
        if severity not in ("ERROR", "WARNING", "RECOMMENDATION"):
            raise SystemExit(f"Qodo rules request failed: malformed response (rule has invalid severity: {severity!r}, expected ERROR, WARNING, or RECOMMENDATION)")
        rules.append(entry)
```

## Error Handling

| Status | Meaning | Action |
|---|---|---|
| 200 | Success | Parse `rules` array; empty list is valid |
| 401 | Invalid or expired API key | Inform user, exit gracefully |
| 403 | Access forbidden | Inform user, exit gracefully |
| 404 | Endpoint not found | Inform user to check `QODO_ENVIRONMENT_NAME`, exit gracefully |
| 429 | Rate limit exceeded | Inform user, exit gracefully |
| 5xx | API temporarily unavailable | Inform user, exit gracefully |
| Connection error | Network issue | Inform user to check internet connection, exit gracefully |

**Never crash on an empty `rules` list.** An empty result means no relevant rules exist — proceed with the coding task without constraints.
