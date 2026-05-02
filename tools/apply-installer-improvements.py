#!/usr/bin/env python3
"""Apply a broad installer improvement pass.

The installer is intentionally edited with exact-context replacements only so the
large router-side shell script is not rewritten through a truncated API view.
"""

from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "installer"


def fail(message: str) -> None:
    print(f"Error: {message}", file=sys.stderr)
    raise SystemExit(1)


def replace_once(text: str, old: str, new: str, label: str) -> tuple[str, bool]:
    count = text.count(old)
    if count == 0:
        print(f"SKIP: {label} already applied or context not found")
        return text, False
    if count != 1:
        fail(f"{label}: expected one match, found {count}")
    print(f"APPLY: {label}")
    return text.replace(old, new, 1), True


def replace_all(text: str, old: str, new: str, label: str) -> tuple[str, int]:
    count = text.count(old)
    if count == 0:
        print(f"SKIP: {label} already applied or context not found")
        return text, 0
    print(f"APPLY: {label} ({count} replacement(s))")
    return text.replace(old, new), count


def improve_installer(text: str) -> tuple[str, int]:
    changes = 0

    old = '''until [ -n "${REMOTE_VER}" ] && [ -n "${REMOTE_BETA}" ]; do
	curl -D /tmp/$$_headers.out --retry 5 --connect-timeout 25 --retry-delay 5 --max-time $((5 * 25)) --retry-connrefused -sL "${LATEST_URL}?per_page=5" -o "${API_FILE}"
	if [ -s "${API_FILE}" ]; then
'''
    new = '''until [ -n "${REMOTE_VER}" ] && [ -n "${REMOTE_BETA}" ]; do
	if which curl >/dev/null 2>&1; then
		curl -D "/tmp/$$_headers.out" --retry 5 --connect-timeout 25 --retry-delay 5 --max-time $((5 * 25)) --retry-connrefused -sL "${LATEST_URL}?per_page=5" -o "${API_FILE}"
	elif which wget >/dev/null 2>&1; then
		wget --no-cache --no-cookies --tries=5 --timeout=25 --waitretry=5 -q "${LATEST_URL}?per_page=5" -O "${API_FILE}"
	else
		printf "%s\n" "Neither curl nor wget is available. The installer cannot query GitHub releases."
		exit 1
	fi
	if [ -s "${API_FILE}" ]; then
'''
    text, changed = replace_once(text, old, new, "add curl/wget fallback for GitHub release metadata fetch")
    changes += int(changed)

    old = '''		if [ -f "${BASE_DIR}/backup_AdGuardHome.tar.gz" ]; then
			PTXT "${INFO} There is an old backup detected."
			local USE_OLD
			if read_yesno "Do you want to continue?(this will remove the old backup)"; then USE_OLD="NO"; else USE_OLD="YES"; fi
			if [ "${USE_OLD}" = "YES" ]; then
				PTXT "${INFO} Leaving Old Backup."
				end_op_message 1
			elif [ "${USE_OLD}" = "NO" ]; then
				PTXT "${INFO} Removing Old Backup."
				rm -rf "${BASE_DIR}/backup_AdGuardHome.tar.gz"
			fi
		fi
'''
    new = '''		if [ -f "${BASE_DIR}/backup_AdGuardHome.tar.gz" ]; then
			PTXT "${INFO} There is an old backup detected."
			local USE_OLD
			if read_yesno "Do you want to continue?(this will rotate the old backup)"; then USE_OLD="NO"; else USE_OLD="YES"; fi
			if [ "${USE_OLD}" = "YES" ]; then
				PTXT "${INFO} Leaving Old Backup."
				end_op_message 1
			elif [ "${USE_OLD}" = "NO" ]; then
				local OLD_BACKUP_FILE
				OLD_BACKUP_FILE="${BASE_DIR}/backup_AdGuardHome-previous-$(date +%Y%m%d-%H%M%S 2>/dev/null || date +%s).tar.gz"
				PTXT "${INFO} Rotating old backup to ${OLD_BACKUP_FILE}."
				if ! mv "${BASE_DIR}/backup_AdGuardHome.tar.gz" "${OLD_BACKUP_FILE}"; then
					PTXT "${ERROR} Old backup could not be rotated."
					end_op_message 1
					return
				fi
			fi
		fi
'''
    text, changed = replace_once(text, old, new, "rotate old backup instead of deleting it")
    changes += int(changed)

    old = '''		mv "${YAML_FILE}" "${YAML_ERR_TS}"
		return 1
'''
    new = '''		if ! mv "${YAML_FILE}" "${YAML_ERR_TS}"; then
			PTXT "${ERROR} Invalid configuration file could not be moved aside."
			return 1
		fi
		return 1
'''
    text, changed = replace_once(text, old, new, "fail visibly if invalid YAML cannot be moved aside")
    changes += int(changed)

    text, count = replace_all(text, "rm -rf /opt/var/run/AdGuardHome.pid", "rm -f /opt/var/run/AdGuardHome.pid", "use rm -f for AdGuardHome pid file cleanup")
    changes += count

    text, count = replace_all(text, '''[ -f "/opt/sbin/AdGuardHome" ] && rm -rf /opt/sbin/AdGuardHome''', '''[ -e "/opt/sbin/AdGuardHome" ] && rm -f /opt/sbin/AdGuardHome''', "use rm -f for AdGuardHome symlink cleanup")
    changes += count

    text, count = replace_all(text, '''wget --no-cache --no-cookies --tries=5 --timeout=25 --waitretry=5 --retry-connrefused -q --spider''', '''wget --no-cache --no-cookies --tries=5 --timeout=25 --waitretry=5 -q --spider''', "remove unsupported wget --retry-connrefused option")
    changes += count

    text, count = replace_all(text, '''[ "$(nvram get dnsfilter_enable_x)" -ne 0 ]''', '''[ "$(nvram get dnsfilter_enable_x)" != "0" ]''', "use string comparison for dnsfilter_enable_x")
    changes += count

    text, count = replace_all(text, '''[ "$USE_SOME" -eq 0 ]''', '''[ "${USE_SOME}" = "0" ]''', "use string comparison for USE_SOME zero branch")
    changes += count

    text, count = replace_all(text, '''[ "$USE_SOME" -eq 1 ]''', '''[ "${USE_SOME}" = "1" ]''', "use string comparison for USE_SOME one branch")
    changes += count

    return text, changes


def main() -> int:
    if not INSTALLER.exists():
        print("Error: installer file not found", file=sys.stderr)
        return 1

    with INSTALLER.open("r", encoding="utf-8", newline="") as fh:
        original = fh.read()

    updated, changes = improve_installer(original)

    if changes == 0:
        print("No installer improvement changes were needed.")
        return 0

    with INSTALLER.open("w", encoding="utf-8", newline="\n") as fh:
        fh.write(updated)

    print(f"Applied {changes} installer improvement change(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
