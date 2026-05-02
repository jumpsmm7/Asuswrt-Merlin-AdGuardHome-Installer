#!/usr/bin/env python3
"""Apply phase 3 targeted installer hardening changes.

This phase focuses on download/update robustness and preserving diagnostic data.
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


def insert_after_once(text: str, marker: str, insertion: str, label: str) -> tuple[str, bool]:
    if insertion.strip() in text:
        print(f"SKIP: {label} already present")
        return text, False
    count = text.count(marker)
    if count != 1:
        fail(f"{label}: expected one marker, found {count}")
    print(f"APPLY: {label}")
    return text.replace(marker, marker + insertion, 1), True


def harden_phase3(text: str) -> tuple[str, int]:
    changes = 0

    helper_marker = '''hash_password_python3() {
	python3 -c 'import sys, bcrypt; password = sys.stdin.buffer.read(); print(bcrypt.hashpw(password, bcrypt.gensalt(prefix=b"2a", rounds=10)).decode("ascii"))'
}
'''
    helper_insertion = r'''

safe_download() {
	_url="$1"
	_output="$2"
	_tmp_output="${_output}.$$"

	rm -f "${_tmp_output}"

	if which curl >/dev/null 2>&1; then
		if curl --retry 5 --connect-timeout 25 --retry-delay 5 --max-time $((5 * 25)) --retry-connrefused -fsL "${_url}" -o "${_tmp_output}" && [ -s "${_tmp_output}" ]; then
			mv "${_tmp_output}" "${_output}"
			return 0
		fi
	fi

	if which wget >/dev/null 2>&1; then
		if wget --no-cache --no-cookies --tries=5 --timeout=25 --waitretry=5 -q "${_url}" -O "${_tmp_output}" && [ -s "${_tmp_output}" ]; then
			mv "${_tmp_output}" "${_output}"
			return 0
		fi
	fi

	rm -f "${_tmp_output}"
	return 1
}
'''
    text, changed = insert_after_once(text, helper_marker, helper_insertion, "add safe_download helper")
    changes += int(changed)

    old = '''\t\tPTXT "${INFO} Removing Old Backup."
\t\t\trm -rf "${BASE_DIR}/backup_AdGuardHome.tar.gz"
'''
    new = '''\t\tPTXT "${INFO} Rotating old backup."
\t\t\tmv "${BASE_DIR}/backup_AdGuardHome.tar.gz" "${BASE_DIR}/backup_AdGuardHome-previous-$(date +%Y%m%d-%H%M%S 2>/dev/null || date +%s).tar.gz"
'''
    text, changed = replace_once(text, old, new, "rotate old backup instead of deleting it")
    changes += int(changed)

    old = '''\t\tPTXT "${ERROR} No ${AGH_FILE} to Backup!"
\t\tend_op_message 1
\tfi
'''
    new = '''\t\tPTXT "${ERROR} No ${AGH_FILE} to Backup!"
\t\tend_op_message 1
\t\treturn
\tfi
'''
    text, changed = replace_once(text, old, new, "return after failed backup precheck")
    changes += int(changed)

    old = '''\t\tPTXT "${ERROR} No Backup found!" \\
\t\t\t"${ERROR} Please make sure Backup Resides in ${BASE_DIR}"
\t\tend_op_message 1
\t\treturn
'''
    new = '''\t\tPTXT "${ERROR} No Backup found!" \\
\t\t\t"${ERROR} Please make sure backup_AdGuardHome.tar.gz resides in ${BASE_DIR}"
\t\tend_op_message 1
\t\treturn
'''
    text, changed = replace_once(text, old, new, "clarify restore backup filename")
    changes += int(changed)

    old = '''\tif [ -f "${BASE_DIR}/backup_AdGuardHome.tar.gz" ] && [ "$1" = "RESTORE" ]; then
\t\tPTXT "${INFO} Please wait a moment."
\t\ttar -xzvf "${BASE_DIR}/backup_AdGuardHome.tar.gz" -C "${BASE_DIR}" >/dev/null 2>&1
'''
    new = '''\tif [ -f "${BASE_DIR}/backup_AdGuardHome.tar.gz" ] && [ "$1" = "RESTORE" ]; then
\t\tPTXT "${INFO} Please wait a moment."
\t\tif ! tar -tzf "${BASE_DIR}/backup_AdGuardHome.tar.gz" >/dev/null 2>&1; then
\t\t\tPTXT "${ERROR} Backup archive is invalid or unreadable."
\t\t\tend_op_message 1
\t\t\treturn
\t\tfi
\t\ttar -xzvf "${BASE_DIR}/backup_AdGuardHome.tar.gz" -C "${BASE_DIR}" >/dev/null 2>&1
'''
    text, changed = replace_once(text, old, new, "validate backup archive before restore")
    changes += int(changed)

    old = '''rm -rf "$API_FILE" "/tmp/$$_headers.out"
wait
unset varcnt
'''
    new = '''rm -f "$API_FILE" "/tmp/$$_headers.out"
wait
unset varcnt
'''
    text, changed = replace_once(text, old, new, "use rm -f for temporary files")
    changes += int(changed)

    return text, changes


def main() -> int:
    if not INSTALLER.exists():
        print("Error: installer file not found", file=sys.stderr)
        return 1

    with INSTALLER.open("r", encoding="utf-8", newline="") as fh:
        original = fh.read()

    updated, changes = harden_phase3(original)

    if changes == 0:
        print("No phase 3 installer changes were needed.")
        return 0

    with INSTALLER.open("w", encoding="utf-8", newline="\n") as fh:
        fh.write(updated)

    print(f"Applied {changes} phase 3 installer hardening change(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
