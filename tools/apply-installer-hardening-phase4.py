#!/usr/bin/env python3
"""Apply phase 4 targeted installer hardening changes.

This phase focuses on credential-input validation and safer cleanup behavior.
The script uses exact-context replacements only and exits on ambiguous matches.
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


def harden_phase4(text: str) -> tuple[str, int]:
    changes = 0

    old = '''AdGuardHome_authen() {
\tlocal USERNAME PW1 PW2
\tPTXT -n "${INPUT} Please enter AdGuardHome username${NORM}: "
\tread -r USERNAME
\twhile :; do
'''
    new = '''AdGuardHome_authen() {
\tlocal USERNAME PW1 PW2
\twhile :; do
\t\tPTXT -n "${INPUT} Please enter AdGuardHome username${NORM}: "
\t\tread -r USERNAME
\t\tcase "${USERNAME}" in
\t\t''|*[!A-Za-z0-9._-]*)
\t\t\tPTXT "${ERROR} Username must contain only letters, numbers, dots, underscores, or hyphens."
\t\t\t;;
\t\t*)
\t\t\tbreak
\t\t\t;;
\t\tesac
\tdone
\twhile :; do
'''
    text, changed = replace_once(text, old, new, "validate AdGuard Home username before YAML insertion")
    changes += int(changed)

    old = '''\t\tgo install gophers.dev/cmds/bcrypt-tool@latest >/dev/null 2>&1
\t\trm -rf go
\telse
'''
    new = '''\t\tgo install gophers.dev/cmds/bcrypt-tool@latest >/dev/null 2>&1
\t\trm -rf "${HOME:-/tmp}/go"
\telse
'''
    text, changed = replace_once(text, old, new, "clean Go workspace from HOME instead of relative path")
    changes += int(changed)

    old = '''\tlocal PW1_ENCRYPTED
\tif opkg_installed python3-bcrypt; then PW1_ENCRYPTED="$(printf '%s' "${PW1}" | hash_password_python3)"; elif [ -f "/opt/bin/bcrypt-tool" ]; then PW1_ENCRYPTED="$(/opt/bin/bcrypt-tool hash "${PW1}" 10)"; else
\t\tPTXT "${ERROR} Password could not be set!" "${ERROR} Please contact dev."
\t\tend_op_message 1
\t\treturn
\tfi
\tif [ "$1" -eq 0 ]; then
'''
    new = '''\tlocal PW1_ENCRYPTED
\tif opkg_installed python3-bcrypt; then PW1_ENCRYPTED="$(printf '%s' "${PW1}" | hash_password_python3)"; elif [ -f "/opt/bin/bcrypt-tool" ]; then PW1_ENCRYPTED="$(/opt/bin/bcrypt-tool hash "${PW1}" 10)"; else
\t\tPTXT "${ERROR} Password could not be set!" "${ERROR} Please contact dev."
\t\tend_op_message 1
\t\treturn
\tfi
\tif [ -z "${PW1_ENCRYPTED}" ]; then
\t\tPTXT "${ERROR} Password hash could not be generated!" "${ERROR} Please contact dev."
\t\tend_op_message 1
\t\treturn
\tfi
\tif [ "$1" -eq 0 ]; then
'''
    text, changed = replace_once(text, old, new, "validate generated password hash before writing YAML")
    changes += int(changed)

    old = '''\t\tif ! tar -tzf "${BASE_DIR}/backup_AdGuardHome.tar.gz" >/dev/null 2>&1; then
\t\t\tPTXT "${ERROR} Backup archive is invalid or unreadable."
\t\t\tend_op_message 1
\t\t\treturn
\t\tfi
\t\ttar -xzvf "${BASE_DIR}/backup_AdGuardHome.tar.gz" -C "${BASE_DIR}" >/dev/null 2>&1
'''
    new = '''\t\tif ! tar -tzf "${BASE_DIR}/backup_AdGuardHome.tar.gz" >/dev/null 2>&1; then
\t\t\tPTXT "${ERROR} Backup archive is invalid or unreadable."
\t\t\tend_op_message 1
\t\t\treturn
\t\tfi
\t\tif ! tar -xzvf "${BASE_DIR}/backup_AdGuardHome.tar.gz" -C "${BASE_DIR}" >/dev/null 2>&1; then
\t\t\tPTXT "${ERROR} Backup archive could not be restored."
\t\t\tend_op_message 1
\t\t\treturn
\t\tfi
'''
    text, changed = replace_once(text, old, new, "fail cleanly if backup extraction fails")
    changes += int(changed)

    return text, changes


def main() -> int:
    if not INSTALLER.exists():
        print("Error: installer file not found", file=sys.stderr)
        return 1

    with INSTALLER.open("r", encoding="utf-8", newline="") as fh:
        original = fh.read()

    updated, changes = harden_phase4(original)

    if changes == 0:
        print("No phase 4 installer changes were needed.")
        return 0

    with INSTALLER.open("w", encoding="utf-8", newline="\n") as fh:
        fh.write(updated)

    print(f"Applied {changes} phase 4 installer hardening change(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
