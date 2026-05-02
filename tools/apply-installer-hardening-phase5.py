#!/usr/bin/env python3
"""Apply phase 5 targeted installer hardening changes.

This phase focuses on router-safe command detection and download helper reuse.
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


def harden_phase5(text: str) -> tuple[str, int]:
    changes = 0

    marker = '''opkg_available() {
	[ -n "$1" ] || return 1
	opkg list 2>/dev/null | awk -v pkg="$1" '$1 == pkg { found=1; exit } END { exit found ? 0 : 1 }'
}
'''
    insertion = r'''

cmd_exists() {
	[ -n "$1" ] || return 1
	which "$1" >/dev/null 2>&1
}
'''
    text, changed = insert_after_once(text, marker, insertion, "add router-safe cmd_exists helper")
    changes += int(changed)

    old = '''	if which curl >/dev/null 2>&1; then
		if curl --retry 5 --connect-timeout 25 --retry-delay 5 --max-time $((5 * 25)) --retry-connrefused -fsL "${_url}" -o "${_tmp_output}" && [ -s "${_tmp_output}" ]; then
'''
    new = '''	if cmd_exists curl; then
		if curl --retry 5 --connect-timeout 25 --retry-delay 5 --max-time $((5 * 25)) --retry-connrefused -fsL "${_url}" -o "${_tmp_output}" && [ -s "${_tmp_output}" ]; then
'''
    text, changed = replace_once(text, old, new, "use cmd_exists for curl in safe_download")
    changes += int(changed)

    old = '''	if which wget >/dev/null 2>&1; then
		if wget --no-cache --no-cookies --tries=5 --timeout=25 --waitretry=5 -q "${_url}" -O "${_tmp_output}" && [ -s "${_tmp_output}" ]; then
'''
    new = '''	if cmd_exists wget; then
		if wget --no-cache --no-cookies --tries=5 --timeout=25 --waitretry=5 -q "${_url}" -O "${_tmp_output}" && [ -s "${_tmp_output}" ]; then
'''
    text, changed = replace_once(text, old, new, "use cmd_exists for wget in safe_download")
    changes += int(changed)

    old = '''	if opkg_installed python3-bcrypt; then PW1_ENCRYPTED="$(printf '%s' "${PW1}" | hash_password_python3)"; elif [ -f "/opt/bin/bcrypt-tool" ]; then PW1_ENCRYPTED="$(/opt/bin/bcrypt-tool hash "${PW1}" 10)"; else
'''
    new = '''	if opkg_installed python3-bcrypt && cmd_exists python3; then PW1_ENCRYPTED="$(printf '%s' "${PW1}" | hash_password_python3)"; elif [ -x "/opt/bin/bcrypt-tool" ]; then PW1_ENCRYPTED="$(/opt/bin/bcrypt-tool hash "${PW1}" 10)"; else
'''
    text, changed = replace_once(text, old, new, "verify python3 command and executable bcrypt-tool before hashing")
    changes += int(changed)

    old = '''		if { ! curl --retry 5 --connect-timeout 25 --retry-delay 5 --max-time $((5 * 25)) --retry-connrefused -Is "http://${i}" | head -n 1 >/dev/null 2>&1; } && { ! wget --no-cache --no-cookies --tries=5 --timeout=25 --waitretry=5 --retry-connrefused -q --spider "http://${i}" >/dev/null 2>&1; }; then
'''
    new = '''		if { cmd_exists curl && curl --retry 5 --connect-timeout 25 --retry-delay 5 --max-time $((5 * 25)) --retry-connrefused -Is "http://${i}" | head -n 1 >/dev/null 2>&1; } || { cmd_exists wget && wget --no-cache --no-cookies --tries=5 --timeout=25 --waitretry=5 --retry-connrefused -q --spider "http://${i}" >/dev/null 2>&1; }; then
			:
		else
'''
    text, changed = replace_once(text, old, new, "guard connectivity checks by available downloader")
    changes += int(changed)

    old = '''			sleep 1s
			continue
		fi
'''
    new = '''			sleep 1s
			continue
		fi
'''
    # Keep this intentionally as a no-op placeholder so exact downstream context remains unchanged.

    return text, changes


def main() -> int:
    if not INSTALLER.exists():
        print("Error: installer file not found", file=sys.stderr)
        return 1

    with INSTALLER.open("r", encoding="utf-8", newline="") as fh:
        original = fh.read()

    updated, changes = harden_phase5(original)

    if changes == 0:
        print("No phase 5 installer changes were needed.")
        return 0

    with INSTALLER.open("w", encoding="utf-8", newline="\n") as fh:
        fh.write(updated)

    print(f"Applied {changes} phase 5 installer hardening change(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
