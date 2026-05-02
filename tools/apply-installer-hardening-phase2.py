#!/usr/bin/env python3
"""Apply phase 2 targeted installer hardening changes.

This script is designed for the manual GitHub Actions apply workflow. It performs
exact-context replacements only and exits if a target block is ambiguous.
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


def harden_phase2(text: str) -> tuple[str, int]:
    changes = 0

    old = '''AdGuardHome_authen() {
\tif [ -z "${PW1}" ] || [ -z "${PW2}" ]; then
\t\tlocal USERNAME
\t\tPTXT -n "${INPUT} Please enter AdGuardHome username${NORM}: "
\t\tread -r USERNAME
\tfi
\tlocal PW1 PW2
\tPTXT -n "${INPUT} Please enter AdGuardHome password${NORM}: "
\tread -rs PW1
\tPTXT " "
\tPTXT -n "${INPUT} Please reenter AdGuardHome password${NORM}: "
\tread -rs PW2
\tPTXT " "
\tif [ -z "${PW1}" ] || [ -z "${PW2}" ] || [ "${PW1}" != "${PW2}" ]; then
\t\tPTXT "${ERROR} Password entered incorrectly!"
\t\tAdGuardHome_authen "$1"
\tfi
'''
    new = '''AdGuardHome_authen() {
\tlocal USERNAME PW1 PW2
\tPTXT -n "${INPUT} Please enter AdGuardHome username${NORM}: "
\tread -r USERNAME
\twhile :; do
\t\tPTXT -n "${INPUT} Please enter AdGuardHome password${NORM}: "
\t\tread -rs PW1
\t\tPTXT " "
\t\tPTXT -n "${INPUT} Please reenter AdGuardHome password${NORM}: "
\t\tread -rs PW2
\t\tPTXT " "
\t\tif [ -n "${PW1}" ] && [ -n "${PW2}" ] && [ "${PW1}" = "${PW2}" ]; then
\t\t\tbreak
\t\tfi
\t\tPTXT "${ERROR} Password entered incorrectly!"
\tdone
'''
    text, changed = replace_once(text, old, new, "replace recursive password prompt with loop")
    changes += int(changed)

    old = '''\t\ttar -czvf "${BASE_DIR}/backup_AdGuardHome.tar.gz" -C "${TARG_DIR}" ../AdGuardHome/ >/dev/null 2>&1
\t\tPTXT "${INFO} Backup complete"
'''
    new = '''\t\tlocal BACKUP_FILE
\t\tBACKUP_FILE="${BASE_DIR}/backup_AdGuardHome-$(date +%Y%m%d-%H%M%S 2>/dev/null || date +%s).tar.gz"
\t\ttar -czvf "${BACKUP_FILE}" -C "${TARG_DIR}" ../AdGuardHome/ >/dev/null 2>&1
\t\tcp -f "${BACKUP_FILE}" "${BASE_DIR}/backup_AdGuardHome.tar.gz"
\t\tPTXT "${INFO} Backup complete: ${BACKUP_FILE}"
'''
    text, changed = replace_once(text, old, new, "create timestamped backup and refresh latest backup")
    changes += int(changed)

    old = '''\t\t\t\tif { ! curl --retry 5 --connect-timeout 25 --retry-delay 5 --max-time $((5 * 25)) --retry-connrefused -Is "http://${i}" | head -n 1 >/dev/null 2>&1; } || { ! wget --no-cache --no-cookies --tries=5 --timeout=25 --waitretry=5 --retry-connrefused -q --spider "http://${i}" >/dev/null 2>&1; }; then
\t\t\t\t\tsleep 1s
\t\t\t\t\tcontinue
\t\t\t\tfi
'''
    new = '''\t\t\t\tif { ! curl --retry 5 --connect-timeout 25 --retry-delay 5 --max-time $((5 * 25)) --retry-connrefused -Is "http://${i}" | head -n 1 >/dev/null 2>&1; } && { ! wget --no-cache --no-cookies --tries=5 --timeout=25 --waitretry=5 --retry-connrefused -q --spider "http://${i}" >/dev/null 2>&1; }; then
\t\t\t\t\tsleep 1s
\t\t\t\t\tcontinue
\t\t\t\tfi
'''
    text, changed = replace_once(text, old, new, "allow either curl or wget connectivity check to pass")
    changes += int(changed)

    old = '''\t\t	if [ "$(nvram get dnsfilter_enable_x)" -ne 0 ]; then
'''
    new = '''\t\t\tif [ "$(nvram get dnsfilter_enable_x)" != "0" ]; then
'''
    text, changed = replace_once(text, old, new, "avoid numeric test on possibly empty dnsfilter_enable_x disable path")
    changes += int(changed)

    old = '''\t\tif [ "$(nvram get dnsfilter_enable_x)" -ne 1 ]; then
'''
    new = '''\t\tif [ "$(nvram get dnsfilter_enable_x)" != "1" ]; then
'''
    text, changed = replace_once(text, old, new, "avoid numeric test on possibly empty dnsfilter_enable_x enable path")
    changes += int(changed)

    old = '''\tif [ "${JFFS2_ENABLED}" -ne 1 ] || [ "${JFFS2_SCRIPTS}" -ne 1 ]; then
'''
    new = '''\tif [ "${JFFS2_ENABLED}" != "1" ] || [ "${JFFS2_SCRIPTS}" != "1" ]; then
'''
    text, changed = replace_once(text, old, new, "avoid numeric test on possibly empty jffs settings")
    changes += int(changed)

    return text, changes


def main() -> int:
    if not INSTALLER.exists():
        print("Error: installer file not found", file=sys.stderr)
        return 1

    with INSTALLER.open("r", encoding="utf-8", newline="") as fh:
        original = fh.read()

    updated, changes = harden_phase2(original)

    if changes == 0:
        print("No phase 2 installer changes were needed.")
        return 0

    with INSTALLER.open("w", encoding="utf-8", newline="\n") as fh:
        fh.write(updated)

    print(f"Applied {changes} phase 2 installer hardening change(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
