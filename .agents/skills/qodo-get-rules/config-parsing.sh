CONFIG_FILE="${HOME}/.qodo/config.json"
CONFIG_API_KEY=""
CONFIG_ENV_NAME=""
CONFIG_QODO_API_URL=""

# The config file is an optional fallback; environment-only setup is supported.
if [ -f "${CONFIG_FILE}" ]; then
	# Only validate permissions when environment-only setup is insufficient
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
	fi
	# Only parse config values not already set in environment
	if [ -z "${QODO_API_KEY:-}" ]; then
		if ! CONFIG_API_KEY=$(python3 -c 'import json,sys; v=json.load(open(sys.argv[1])).get("API_KEY", ""); print(v if isinstance(v, str) and v.strip() else "")' "${CONFIG_FILE}"); then
			printf '%s\n' "Unable to read ${CONFIG_FILE}. Fix or remove the invalid Qodo configuration file." >&2
			exit 1
		fi
	fi
	if [ -z "${QODO_ENVIRONMENT_NAME:-}" ]; then
		if ! CONFIG_ENV_NAME=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("ENVIRONMENT_NAME", ""))' "${CONFIG_FILE}"); then
			printf '%s\n' "Unable to read ${CONFIG_FILE}. Fix or remove the invalid Qodo configuration file." >&2
			exit 1
		fi
	fi
	if [ -z "${QODO_API_URL:-}" ]; then
		if ! CONFIG_QODO_API_URL=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("QODO_API_URL", ""))' "${CONFIG_FILE}"); then
			printf '%s\n' "Unable to read ${CONFIG_FILE}. Fix or remove the invalid Qodo configuration file." >&2
			exit 1
		fi
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
	# Remove trailing slash to prevent double slashes before /rules/v1
	QODO_API_URL="${QODO_API_URL%/}"
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
