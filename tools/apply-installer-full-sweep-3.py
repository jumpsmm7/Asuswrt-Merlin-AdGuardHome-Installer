#!/usr/bin/env python3
"""Apply a third focused installer reliability sweep.

This pass adds more restore/backup validation and safer file operation handling
using exact-context replacements only.
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


def improve_full_3(text: str) -> tuple[str, int]:
    changes = 0

    old = '''		if ! cp -f "${BACKUP_FILE}" "${BASE_DIR}/backup_AdGuardHome.tar.gz"; then
			PTXT "${ERROR} Latest backup copy could not be refreshed."
			end_op_message 1
			return
		fi
		PTXT "${INFO} Backup complete: ${BACKUP_FILE}"
'''
    new = '''		if ! tar -tzf "${BACKUP_FILE}" >/dev/null 2>&1; then
			PTXT "${ERROR} Backup archive failed validation after creation."
			end_op_message 1
			return
		fi
		if ! cp -f "${BACKUP_FILE}" "${BASE_DIR}/backup_AdGuardHome.tar.gz"; then
			PTXT "${ERROR} Latest backup copy could not be refreshed."
			end_op_message 1
			return
		fi
		PTXT "${INFO} Backup complete: ${BACKUP_FILE}"
'''
    text, changed = replace_once(text, old, new, "validate backup archive immediately after creation")
    changes += int(changed)

    old = '''		for restored_file in "${TARG_DIR}"/*; do
			[ -e "${restored_file}" ] || continue
			chown "$(nvram get http_username)":root "${restored_file}"
		done
'''
    new = '''		local RESTORE_OWNER
		RESTORE_OWNER="$(nvram get http_username)"
		[ -n "${RESTORE_OWNER}" ] || RESTORE_OWNER="admin"
		for restored_file in "${TARG_DIR}"/*; do
			[ -e "${restored_file}" ] || continue
			if ! chown "${RESTORE_OWNER}:root" "${restored_file}"; then
				PTXT "${WARNING} Could not set ownership on ${restored_file}."
			fi
		done
'''
    text, changed = replace_once(text, old, new, "guard restored file ownership changes")
    changes += int(changed)

    text, count = replace_all(text, '''[ -e "/opt/sbin/AdGuardHome" ] && rm -f /opt/sbin/AdGuardHome''', '''if [ -e "/opt/sbin/AdGuardHome" ] && ! rm -f /opt/sbin/AdGuardHome; then
			PTXT "${ERROR} Could not remove existing /opt/sbin/AdGuardHome symlink."
			end_op_message 1
			return
		fi''', "fail cleanly if existing AdGuardHome symlink cannot be removed")
    changes += count

    text, count = replace_all(text, '''chmod 644 "${YAML_FILE}" || return 1''', '''if ! chmod 644 "${YAML_FILE}"; then
		PTXT "${ERROR} Could not set AdGuardHome YAML permissions."
		return 1
	fi''', "show error when YAML permission change fails")
    changes += count

    text, count = replace_all(text, '''mv -f "${YAML_FILE}" "${YAML_BAK}"''', '''if ! mv -f "${YAML_FILE}" "${YAML_BAK}"; then
			PTXT "${ERROR} Could not create backup copy of AdGuardHome YAML."
			end_op_message 1
			return
		fi''', "fail cleanly when YAML backup move fails")
    changes += count

    text, count = replace_all(text, '''cp -f "${YAML_BAK}" "${YAML_FILE}"''', '''if ! cp -f "${YAML_BAK}" "${YAML_FILE}"; then
			PTXT "${ERROR} Could not restore AdGuardHome YAML backup."
			end_op_message 1
			return
		fi''', "fail cleanly when YAML backup restore fails")
    changes += count

    text, count = replace_all(text, '''rm -f "${YAML_FILE}"''', '''rm -f "${YAML_FILE}" || PTXT "${WARNING} Could not remove ${YAML_FILE}."''', "warn when YAML file cleanup fails")
    changes += count

    text, count = replace_all(text, '''rm -f "${YAML_BAK}"''', '''rm -f "${YAML_BAK}" || PTXT "${WARNING} Could not remove ${YAML_BAK}."''', "warn when YAML backup cleanup fails")
    changes += count

    return text, changes


def main() -> int:
    if not INSTALLER.exists():
        print("Error: installer file not found", file=sys.stderr)
        return 1

    with INSTALLER.open("r", encoding="utf-8", newline="") as fh:
        original = fh.read()

    updated, changes = improve_full_3(original)

    if changes == 0:
        print("No third full installer sweep changes were needed.")
        return 0

    with INSTALLER.open("w", encoding="utf-8", newline="\n") as fh:
        fh.write(updated)

    print(f"Applied {changes} third full installer sweep change(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
