#!/bin/sh
if [ -z "${HOME:-}" ]; then
	printf '%s\n' 'Error: HOME environment variable is required to locate Qodo configuration' >&2
	exit 1
fi
CONFIG_FILE="${HOME}/.qodo/config.json"
CONFIG_API_KEY=""
CONFIG_ENV_NAME=""
CONFIG_QODO_API_URL=""
INVALID_QODO_API_URL='__INVALID_QODO_API_URL__'

qodo_url_authority_valid() {
	local authority url
	url="$1"
	case "${url}" in https://*) ;; *) return 1 ;; esac
	authority="${url#https://}"
	authority="${authority%%/*}"
	case "${authority}" in
		"" | *@* | *:*) return 1 ;;
		qodo.ai | ?*.qodo.ai) return 0 ;;
		*) return 1 ;;
	esac
}

config_mode() {
	stat -c '%a' "$1" 2>/dev/null || return 1
}

# Read a secure config when a required value is missing or when it can supply an
# optional endpoint value. If the environment already supplies the API key, an
# unusable optional config must not prevent the documented endpoint defaults.
CONFIG_REQUIRED=0
if [ -z "${QODO_API_KEY:-}" ]; then
	CONFIG_REQUIRED=1
fi
if [ -f "${CONFIG_FILE}" ] && { [ "${CONFIG_REQUIRED}" -eq 1 ] || [ -z "${QODO_ENVIRONMENT_NAME:-}" ] || [ -z "${QODO_API_URL:-}" ]; }; then
	CONFIG_USABLE=1
	if [ "$(config_mode "$(dirname "${CONFIG_FILE}")")" != "700" ] ||
		[ "$(config_mode "${CONFIG_FILE}")" != "600" ]; then
		CONFIG_USABLE=0
		if [ "${CONFIG_REQUIRED}" -eq 1 ]; then
			# Validate permissions before reading credentials
			CONFIG_DIR=$(dirname "${CONFIG_FILE}")
			if [ "$(config_mode "${CONFIG_DIR}")" != "700" ]; then
				printf '%s\n' "Error: Qodo config directory $CONFIG_DIR must have mode 700 (owner-only access)" >&2
				exit 1
			fi
			printf '%s\n' "Error: Qodo config file ${CONFIG_FILE} must have mode 600 (owner-only access)" >&2
			exit 1
		fi
	fi

	if [ "${CONFIG_USABLE}" -eq 1 ]; then
		# Require jq for robust JSON parsing
		if ! which jq >/dev/null 2>&1; then
			if [ "${CONFIG_REQUIRED}" -eq 1 ]; then
				printf '%s\n' "Error: jq is required to parse ${CONFIG_FILE}. Install jq or use environment variables (QODO_API_KEY, QODO_ENVIRONMENT_NAME, QODO_API_URL)." >&2
				exit 1
			fi
			CONFIG_USABLE=0
		fi
	fi

	if [ "${CONFIG_USABLE}" -eq 1 ]; then
		# Use jq for robust JSON parsing with proper error handling
		JQ_OUTPUT=$(jq -r '
			if type != "object" then
				error("Config file must be a JSON object")
			else
				{
					API_KEY: (if .API_KEY then (if (.API_KEY | type) == "string" then .API_KEY else "" end) else "" end),
					ENVIRONMENT_NAME: (if .ENVIRONMENT_NAME then (if (.ENVIRONMENT_NAME | type) == "string" then .ENVIRONMENT_NAME else "NON_STRING_VALUE" end) else "" end),
					QODO_API_URL: (if has("QODO_API_URL") then (if (.QODO_API_URL | type) == "string" and (.QODO_API_URL | length) > 0 then .QODO_API_URL else "__INVALID_QODO_API_URL__" end) else "" end)
				} | @json
			end
		' "${CONFIG_FILE}" 2>&1)
		JQ_EXIT=$?

		if [ "${JQ_EXIT}" -ne 0 ]; then
			if [ "${CONFIG_REQUIRED}" -eq 1 ]; then
				printf '%s\n' "Unable to read ${CONFIG_FILE}. Fix or remove the invalid Qodo configuration file." >&2
				exit 1
			fi
			CONFIG_USABLE=0
		fi
	fi

	if [ "${CONFIG_USABLE}" -eq 1 ]; then
		# Extract values from jq output
		if [ -z "${QODO_API_KEY:-}" ]; then
			CONFIG_API_KEY=$(printf '%s' "${JQ_OUTPUT}" | jq -r '.API_KEY // ""' 2>/dev/null)
		fi
		if [ -z "${QODO_ENVIRONMENT_NAME:-}" ]; then
			CONFIG_ENV_NAME=$(printf '%s' "${JQ_OUTPUT}" | jq -r '.ENVIRONMENT_NAME // ""' 2>/dev/null)
			if [ "${CONFIG_ENV_NAME}" = "NON_STRING_VALUE" ]; then
				if [ "${CONFIG_REQUIRED}" -eq 1 ]; then
					printf '%s\n' "Error: ENVIRONMENT_NAME in ${CONFIG_FILE} must be a string value" >&2
					exit 1
				fi
				CONFIG_ENV_NAME=""
			fi
		fi
		if [ -z "${QODO_API_URL:-}" ]; then
			CONFIG_QODO_API_URL=$(printf '%s' "${JQ_OUTPUT}" | jq -r '.QODO_API_URL // ""' 2>/dev/null)
		fi
	fi
fi

# Preserve a present-but-invalid configured endpoint until required/optional policy is known.
if [ -n "${CONFIG_QODO_API_URL}" ] && [ "${CONFIG_QODO_API_URL}" != "${INVALID_QODO_API_URL}" ]; then
	if ! qodo_url_authority_valid "${CONFIG_QODO_API_URL}"; then
		CONFIG_QODO_API_URL="${INVALID_QODO_API_URL}"
	else
		case "${CONFIG_QODO_API_URL}" in *\?* | *\#*) CONFIG_QODO_API_URL="${INVALID_QODO_API_URL}" ;; esac
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
REQUEST_ID=""
if which uuidgen >/dev/null 2>&1; then
	REQUEST_ID=$(uuidgen 2>/dev/null)
elif [ -r /proc/sys/kernel/random/uuid ]; then
	REQUEST_ID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null)
else
	# Fallback: generate UUID-like string from /dev/urandom
	# Format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx (UUID v4)
	if [ -r /dev/urandom ]; then
		REQUEST_ID=$(
			dd if=/dev/urandom bs=16 count=1 2>/dev/null |
				sha256sum | cut -c1-32 |
				sed 's/^\(........\)\(....\).\(...\).\(...\)\(............\)$/\1-\2-4\3-8\4-\5/'
		)
	fi
fi

if [ -z "${REQUEST_ID}" ] || ! printf '%s\n' "${REQUEST_ID}" | grep -qE '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'; then
	printf '%s\n' 'Failed to generate a valid request ID' >&2
	exit 1
fi
# Reject control characters before validating complete endpoint values.
if [ "$(printf '%s' "${QODO_API_URL}" | tr -d '[:cntrl:]')" != "${QODO_API_URL}" ] ||
	[ "$(printf '%s' "${ENV_NAME}" | tr -d '[:cntrl:]')" != "${ENV_NAME}" ]; then
	printf '%s\n' 'Invalid Qodo endpoint configuration: control characters are not allowed' >&2
	exit 1
fi
if [ "${QODO_API_URL}" = "${INVALID_QODO_API_URL}" ]; then
	if [ "${CONFIG_REQUIRED}" -eq 1 ]; then
		printf '%s\n' "Invalid QODO_API_URL in ${CONFIG_FILE}: expected a non-empty string" >&2
		exit 1
	fi
	QODO_API_URL=""
fi

# Determine API_URL: QODO_API_URL takes precedence over ENVIRONMENT_NAME
if [ -n "${QODO_API_URL}" ]; then
	# Validate QODO_API_URL is HTTPS and points to a trusted Qodo endpoint
	if ! qodo_url_authority_valid "${QODO_API_URL}"; then
			printf '%s\n' 'Invalid QODO_API_URL: must use HTTPS and match a trusted Qodo domain (*.qodo.ai)' >&2
			exit 1
	fi
	# Reject QODO_API_URL containing query string or fragment
	case "${QODO_API_URL}" in
		*\?* | *\#*)
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
	case "${ENV_NAME}" in
		*[!a-zA-Z0-9_.-]* | "")
			printf '%s\n' 'Invalid ENVIRONMENT_NAME: must contain only alphanumeric, underscore, dot, or hyphen characters' >&2
			exit 1
			;;
	esac
	API_URL="https://qodo-platform.${ENV_NAME}.qodo.ai/rules/v1"
fi
