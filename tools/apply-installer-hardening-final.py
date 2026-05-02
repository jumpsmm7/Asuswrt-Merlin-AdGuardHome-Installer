#!/usr/bin/env python3
"""Apply the final targeted installer hardening pass.

This pass avoids broad rewrites of the large installer file except for the
router-compatibility normalization of `command -v` to `which`. Other edits use
small exact-context replacements and remain BusyBox/Asuswrt-shell friendly.
"""

from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "installer"


def fail(message: str) -> None:
    print(f"Error: {message}", file=sys.stderr)
    raise SystemExit(1)


def replace_all(text: str, old: str, new: str, label: str) -> tuple[str, int]:
    count = text.count(old)
    if count == 0:
        print(f"SKIP: {label} already applied or context not found")
        return text, 0
    print(f"APPLY: {label} ({count} replacement(s))")
    return text.replace(old, new), count


def replace_once(text: str, old: str, new: str, label: str) -> tuple[str, bool]:
    count = text.count(old)
    if count == 0:
        print(f"SKIP: {label} already applied or context not found")
        return text, False
    if count != 1:
        fail(f"{label}: expected one match, found {count}")
    print(f"APPLY: {label}")
    return text.replace(old, new, 1), True


def replace_exact_count(text: str, old: str, new: str, expected: int, label: str) -> tuple[str, int]:
    count = text.count(old)
    if count == 0:
        print(f"SKIP: {label} already applied or context not found")
        return text, 0
    if count != expected:
        fail(f"{label}: expected {expected} matches, found {count}")
    print(f"APPLY: {label} ({count} replacement(s))")
    return text.replace(old, new), count


def harden_final(text: str) -> tuple[str, int]:
    changes = 0

    text, count = replace_all(
        text,
        "command -v ",
        "which ",
        "normalize router command detection from command -v to which",
    )
    changes += count

    old = '''safe_download() {
\t_url="$1"
\t_output="$2"
\t_tmp_output="${_output}.$$"

\trm -f "${_tmp_output}"
'''
    new = '''safe_download() {
\t_url="$1"
\t_output="$2"
\t[ -n "${_url}" ] && [ -n "${_output}" ] || return 1
\t_tmp_output="${_output}.$$"

\trm -f "${_tmp_output}"
'''
    text, changed = replace_once(text, old, new, "validate safe_download arguments")
    changes += int(changed)

    text, count = replace_exact_count(
        text,
        '''\t\t\tmv "${_tmp_output}" "${_output}"
''',
        '''\t\t\tmv -f "${_tmp_output}" "${_output}"
''',
        2,
        "force safe_download atomic replacement moves",
    )
    changes += count

    old = '''\t\tPTXT "${INFO} Rotating old backup."
\t\t\tmv "${BASE_DIR}/backup_AdGuardHome.tar.gz" "${BASE_DIR}/backup_AdGuardHome-previous-$(date +%Y%m%d-%H%M%S 2>/dev/null || date +%s).tar.gz"
'''
    new = '''\t\tPTXT "${INFO} Rotating old backup."
\t\t\tif ! mv "${BASE_DIR}/backup_AdGuardHome.tar.gz" "${BASE_DIR}/backup_AdGuardHome-previous-$(date +%Y%m%d-%H%M%S 2>/dev/null || date +%s).tar.gz"; then
\t\t\t\tPTXT "${ERROR} Old backup could not be rotated."
\t\t\t\tend_op_message 1
\t\t\t\treturn
\t\t\tfi
'''
    text, changed = replace_once(text, old, new, "fail cleanly if old backup rotation fails")
    changes += int(changed)

    old = '''\t\tBACKUP_FILE="${BASE_DIR}/backup_AdGuardHome-$(date +%Y%m%d-%H%M%S 2>/dev/null || date +%s).tar.gz"
\t\ttar -czvf "${BACKUP_FILE}" -C "${TARG_DIR}" ../AdGuardHome/ >/dev/null 2>&1
\t\tcp -f "${BACKUP_FILE}" "${BASE_DIR}/backup_AdGuardHome.tar.gz"
\t\tPTXT "${INFO} Backup complete: ${BACKUP_FILE}"
'''
    new = '''\t\tBACKUP_FILE="${BASE_DIR}/backup_AdGuardHome-$(date +%Y%m%d-%H%M%S 2>/dev/null || date +%s).tar.gz"
\t\tif ! tar -czvf "${BACKUP_FILE}" -C "${TARG_DIR}" ../AdGuardHome/ >/dev/null 2>&1; then
\t\t\tPTXT "${ERROR} Backup archive could not be created."
\t\t\tend_op_message 1
\t\t\treturn
\t\tfi
\t\tif ! cp -f "${BACKUP_FILE}" "${BASE_DIR}/backup_AdGuardHome.tar.gz"; then
\t\t\tPTXT "${ERROR} Latest backup copy could not be refreshed."
\t\t\tend_op_message 1
\t\t\treturn
\t\tfi
\t\tPTXT "${INFO} Backup complete: ${BACKUP_FILE}"
'''
    text, changed = replace_once(text, old, new, "fail cleanly if backup creation or latest copy refresh fails")
    changes += int(changed)

    return text, changes


def main() -> int:
    if not INSTALLER.exists():
        print("Error: installer file not found", file=sys.stderr)
        return 1

    with INSTALLER.open("r", encoding="utf-8", newline="") as fh:
        original = fh.read()

    updated, changes = harden_final(original)

    if changes == 0:
        print("No final installer changes were needed.")
        return 0

    with INSTALLER.open("w", encoding="utf-8", newline="\n") as fh:
        fh.write(updated)

    print(f"Applied {changes} final installer hardening change(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
