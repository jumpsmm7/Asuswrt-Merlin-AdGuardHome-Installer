#!/bin/sh
CONFIG_FILE="${HOME}/.qodo/config.json"
CONFIG_API_KEY=""
CONFIG_ENV_NAME=""
CONFIG_QODO_API_URL=""

# The config file is an optional fallback; environment-only setup is supported.
if [ -f "${CONFIG_FILE}" ]; then
	# Only validate permissions and parse the config when environment-only setup is insufficient
	if [ -z "${QODO_API_KEY:-}" ] || [ -z "${QODO_ENVIRONMENT_NAME:-}" ] || [ -z "${QODO_API_URL:-}" ]; then
		# Validate permissions before reading credentials
		CONFIG_DIR=$(dirname "${CONFIG_FILE}")
		if [ "$(stat -c '%a' "$CONFIG_DIR" 2>/dev/null || stat -f '%Lp' "$CONFIG_DIR" 2>/dev/null)" != "700" ]; then
			printf '%s\n' "Error: Qodo config directory $CONFIG_DIR must have mode 700 (owner-only access)" >&2
			exit 1
		fi
		if [ "$(stat -c '%a' "${CONFIG_FILE}" 2>/dev/null || stat -f '%Lp' "${CONFIG_FILE}" 2>/dev/null)" != "600" ]; then
			printf '%s\n' "Error: Qodo config file ${CONFIG_FILE} must have mode 600 (owner-only access)" >&2
			exit 1
		fi

		# Require jq for robust JSON parsing
		if ! command -v jq >/dev/null 2>&1; then
			printf '%s\n' "Error: jq is required to parse ${CONFIG_FILE}. Install jq or use environment variables (QODO_API_KEY, QODO_ENVIRONMENT_NAME, QODO_API_URL)." >&2
			exit 1
		fi

		# Use jq for robust JSON parsing with proper error handling
		JQ_OUTPUT=$(jq -r '
			if type != "object" then
				error("Config file must be a JSON object")
			else
				{
					API_KEY: (if .API_KEY then (if (.API_KEY | type) == "string" then .API_KEY else "" end) else "" end),
					ENVIRONMENT_NAME: (if .ENVIRONMENT_NAME then (if (.ENVIRONMENT_NAME | type) == "string" then .ENVIRONMENT_NAME else "NON_STRING_VALUE" end) else "" end),
					QODO_API_URL: (if .QODO_API_URL then (if (.QODO_API_URL | type) == "string" then .QODO_API_URL else "" end) else "" end)
				} | @json
			end
		' "${CONFIG_FILE}" 2>&1)
		JQ_EXIT=$?

		if [ "${JQ_EXIT}" -ne 0 ]; then
			printf '%s\n' "Unable to read ${CONFIG_FILE}. Fix or remove the invalid Qodo configuration file." >&2
			exit 1
		fi

		# Extract values from jq output
		if [ -z "${QODO_API_KEY:-}" ]; then
			CONFIG_API_KEY=$(printf '%s' "${JQ_OUTPUT}" | jq -r '.API_KEY // ""' 2>/dev/null)
		fi
		if [ -z "${QODO_ENVIRONMENT_NAME:-}" ]; then
			CONFIG_ENV_NAME=$(printf '%s' "${JQ_OUTPUT}" | jq -r '.ENVIRONMENT_NAME // ""' 2>/dev/null)
			if [ "${CONFIG_ENV_NAME}" = "NON_STRING_VALUE" ]; then
				printf '%s\n' "Error: ENVIRONMENT_NAME in ${CONFIG_FILE} must be a string value" >&2
				exit 1
			fi
		fi
		if [ -z "${QODO_API_URL:-}" ]; then
			CONFIG_QODO_API_URL=$(printf '%s' "${JQ_OUTPUT}" | jq -r '.QODO_API_URL // ""' 2>/dev/null)
		fi
	fi
fi

# Environment variables take precedence over optional config values.
API_KEY="${QODO_API_KEY:-${CONFIG_API_KEY}}"
ENV_NAME="${QODO_ENVIRONMENT_NAME:-${CONFIG_ENV_NAME}}"
QODO_API_URL="${QODO_API_URL:-${CONFIG_QODO_API_URL}}"

# Validate API_KEY: reject if empty or whitespace-only
if [ -z "${API_KEY}" ] || [ -z "$(printf '%s' "${API_KEY}" | tr -d '[:space:]')" ]; then
	printf '%s\n' 'Qodo API key not found. Set QODO_API_KEY or add API_KEY to ~/.qodo/config.json.' >&2
	exit 1
fi

# Generate REQUEST_ID without Python dependency
# Try multiple methods in order of preference
if command -v uuidgen >/dev/null 2>&1; then
	REQUEST_ID=$(uuidgen 2>/dev/null)
elif [ -r /proc/sys/kernel/random/uuid ]; then
	REQUEST_ID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null)
else
	# Fallback: generate UUID-like string from /dev/urandom
	# Format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx (UUID v4)
	if [ -r /dev/urandom ]; then
		REQUEST_ID=$(
			dd if=/dev/urandom bs=16 count=1 2>/dev/null |
				od -An -tx1 |
				tr -d ' \n' |
				sed 's/^\(........\)\(....\).\(...\).\(...\)\(............\)$/\1-\2-4\3-8\4-\5/'
		)
	fi
fi

if [ -z "${REQUEST_ID}" ] || ! printf '%s\n' "${REQUEST_ID}" | grep -qE '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'; then
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
	# Reject QODO_API_URL containing query string or fragment
	case "${QODO_API_URL}" in
		*\?*|*\#*)
			printf '%s\n' 'Invalid QODO_API_URL: must not contain query string or fragment' >&2
			exit 1
			;;
	esac
	# Remove trailing slash to prevent double slashes before /rules/v1
	# Normalize the optional /rules/v1 suffix to avoid appending it twice.
	QODO_API_URL="${QODO_API_URL%/}"
	case "${QODO_API_URL}" in
		*/rules/v1) API_URL="${QODO_API_URL}" ;;
		*) API_URL="${QODO_API_URL}/rules/v1" ;;
	esac
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
