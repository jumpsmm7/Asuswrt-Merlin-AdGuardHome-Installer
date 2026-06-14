#!/bin/sh
# Verify legacy hook cleanup succeeds with unrelated content and reports edit failures.

set -u

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP_DIR="${TMPDIR:-/tmp}/agh-installer-legacy-hook-cleanup.$$"
FUNCTIONS_FILE="${TMP_DIR}/functions.sh"

cleanup() {
	rm -rf "${TMP_DIR}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

mkdir -p "${TMP_DIR}" || exit 1
awk '
	/^_quote\(\)/,/^}/
	/^PTXT\(\)/,/^}/
	/^del_jffs_script\(\)/,/^}/
' "${REPO_DIR}/installer" >"${FUNCTIONS_FILE}"

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	ADDON_DIR="/opt/etc/AdGuardHome"
	TARGET="${TMP_DIR}/mixed-script"
	cat >"${TARGET}" <<'EOF'
#!/bin/sh

[ -x /opt/etc/AdGuardHome/AdGuardHome.sh ] && /opt/etc/AdGuardHome/AdGuardHome.sh legacy
echo unrelated
EOF

	del_jffs_script "${TARGET}" !manager ||
		fail "successful legacy hook cleanup returned failure"
	grep -q '^echo unrelated$' "${TARGET}" ||
		fail "unrelated script content was removed"
	if grep -q 'AdGuardHome.sh' "${TARGET}"; then
		fail "legacy hook was not removed"
	fi
) || exit 1

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	ADDON_DIR="/opt/etc/AdGuardHome"
	TARGET="${TMP_DIR}/failed-edit"
	printf '%s\n' '#!/bin/sh' '[ -x /opt/etc/AdGuardHome/old ] && old' >"${TARGET}"
	sed() {
		case "$1" in
			-i) return 1 ;;
		esac
		command sed "$@"
	}
	if del_jffs_script "${TARGET}"; then
		fail "legacy hook cleanup ignored an edit failure"
	fi
) || exit 1

printf '%s\n' 'OK: installer legacy hook cleanup regression'
