#!/usr/bin/env python3
"""
Apply targeted installer hardening changes to the full installer file.

This script is intended to be run from a local clone where the complete installer
file is available. It performs exact, conservative replacements. Matching
.md5sum checksum files are handled by the shell helpers/workflow.

Usage:
    python3 tools/apply-installer-hardening.py
    python3 tools/apply-installer-hardening.py --check

After running:
    sh tools/update-changed-md5.sh --all
    sh tools/check-md5.sh
    sh -n installer
"""

from __future__ import annotations

import argparse
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


def harden_installer(text: str) -> tuple[str, int]:
    changes = 0

    helper_insertion = r'''

opkg_installed() {
	[ -n "$1" ] || return 1
	opkg list-installed 2>/dev/null | awk -v pkg="$1" '$1 == pkg { found=1; exit } END { exit found ? 0 : 1 }'
}

opkg_available() {
	[ -n "$1" ] || return 1
	opkg list 2>/dev/null | awk -v pkg="$1" '$1 == pkg { found=1; exit } END { exit found ? 0 : 1 }'
}

hash_password_python3() {
	python3 -c 'import sys, bcrypt; password = sys.stdin.buffer.read(); print(bcrypt.hashpw(password, bcrypt.gensalt(prefix=b"2a", rounds=10)).decode("ascii"))'
}
'''

    marker = '''PTXT() {
	case "$1" in
	-n)
		shift
		while [ $# -gt 0 ]; do
			printf "%s" "$1"
			shift
		done
		;;
	*)
		while [ $# -gt 0 ]; do
			printf "%s\\n" "$1"
			shift
		done
		;;
	esac
}
'''
    text, changed = insert_after_once(text, marker, helper_insertion, "add package/password helper functions")
    changes += int(changed)

    old = '''\tfor i in python3 python3-pip python3-bcrypt; do
\t\tif ! opkg list-installed | grep -q $i; then
\t\t\topkg install $i &
\t\telse
\t\t\topkg install $i --force-reinstall &
\t\tfi
\t\twait 2>/dev/null
\tdone
\twait 2>/dev/null
\topkg install python3 python3-pip python3-bcrypt >/dev/null 2>&1
\tif opkg list-installed | grep -q apache; then
\t\topkg flag user apache apache-utils >/dev/null 2>&1
\t\topkg remove apache apache-utils --force-removal-of-dependent-packages >/dev/null 2>&1
\tfi
\tif ! opkg list-installed | grep -q python3-bcrypt; then
'''
    new = '''\tfor i in python3 python3-pip python3-bcrypt; do
\t\tif ! opkg_installed "${i}"; then
\t\t\topkg install "${i}"
\t\tfi
\tdone
\tif opkg_installed apache || opkg_installed apache-utils; then
\t\topkg flag user apache apache-utils >/dev/null 2>&1
\t\topkg remove apache apache-utils --force-removal-of-dependent-packages >/dev/null 2>&1
\tfi
\tif ! opkg_installed python3-bcrypt; then
'''
    text, changed = replace_once(text, old, new, "harden opkg package detection")
    changes += int(changed)

    old = '''\t\t"armv7l" | *)
\t\t\tif ! opkg list | grep -qw 'go_nohf'; then opkg install go >/dev/null 2>&1; else opkg install go_nohf >/dev/null 2>&1; fi
\t\t\t;;
'''
    new = '''\t\t"armv7l" | *)
\t\t\tif opkg_available go_nohf; then opkg install go_nohf >/dev/null 2>&1; else opkg install go >/dev/null 2>&1; fi
\t\t\t;;
'''
    text, changed = replace_once(text, old, new, "use exact opkg list match for go_nohf")
    changes += int(changed)

    old = '''\tlocal PW1_ENCRYPTED
\tif opkg list-installed | grep -q python3-bcrypt; then PW1_ENCRYPTED="$(python -c 'import bcrypt; password = b"'"${PW1}"'"; print(bcrypt.hashpw(password, bcrypt.gensalt(prefix=b"2a", rounds=10)).decode("ascii"))')"; elif [ -f "/opt/bin/bcrypt-tool" ]; then PW1_ENCRYPTED="$(/opt/bin/bcrypt-tool hash "${PW1}" 10)"; else
'''
    new = '''\tlocal PW1_ENCRYPTED
\tif opkg_installed python3-bcrypt; then PW1_ENCRYPTED="$(printf '%s' "${PW1}" | hash_password_python3)"; elif [ -f "/opt/bin/bcrypt-tool" ]; then PW1_ENCRYPTED="$(/opt/bin/bcrypt-tool hash "${PW1}" 10)"; else
'''
    text, changed = replace_once(text, old, new, "hash password through stdin")
    changes += int(changed)

    old = '''\t\ttar -xzvf "${BASE_DIR}/backup_AdGuardHome.tar.gz" -C "${BASE_DIR}" >/dev/null 2>&1
\t\tchown "$(nvram get http_username)":root ${TARG_DIR}/*
\t\tchmod 755 "${AGH_FILE}"
'''
    new = '''\t\ttar -xzvf "${BASE_DIR}/backup_AdGuardHome.tar.gz" -C "${BASE_DIR}" >/dev/null 2>&1
\t\tfor restored_file in "${TARG_DIR}"/*; do
\t\t\t[ -e "${restored_file}" ] || continue
\t\t\tchown "$(nvram get http_username)":root "${restored_file}"
\t\tdone
\t\tchmod 755 "${AGH_FILE}"
'''
    text, changed = replace_once(text, old, new, "quote restore chown glob")
    changes += int(changed)

    old = '''\tif ! "${AGH_FILE}" --check-config -c "${YAML_FILE}" --no-check-update -l "/dev/null"; then
\t\tPTXT "${INFO} Moving invalid configuration file to ${YAML_ERR}." \\
\t\t\t"${INFO} Operation will continue with clean config file."
\t\tmv "${YAML_FILE}" "${YAML_ERR}"
\t\treturn 1
\tfi
'''
    new = '''\tif ! "${AGH_FILE}" --check-config -c "${YAML_FILE}" --no-check-update -l "/dev/null"; then
\t\tlocal YAML_ERR_TS
\t\tYAML_ERR_TS="${YAML_ERR}.$(date +%Y%m%d-%H%M%S 2>/dev/null || date +%s)"
\t\tPTXT "${INFO} Moving invalid configuration file to ${YAML_ERR_TS}." \\
\t\t\t"${INFO} Operation will continue with clean config file."
\t\tmv "${YAML_FILE}" "${YAML_ERR_TS}"
\t\treturn 1
\tfi
'''
    text, changed = replace_once(text, old, new, "timestamp invalid yaml backup")
    changes += int(changed)

    old = '''\t\tnvram set ${jffs2_on}="1"
'''
    new = '''\t\tnvram set "${jffs2_on}=1"
'''
    text, changed = replace_once(text, old, new, "quote jffs nvram set")
    changes += int(changed)

    return text, changes


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="report whether changes would be applied without writing")
    args = parser.parse_args()

    if not INSTALLER.exists():
        fail("installer file not found; run from the repository root")

    with INSTALLER.open("r", encoding="utf-8", newline="") as fh:
        original = fh.read()
    updated, changes = harden_installer(original)

    if changes == 0:
        print("No installer changes were needed.")
        return

    if args.check:
        print(f"Would apply {changes} installer hardening change(s).")
        return

    with INSTALLER.open("w", encoding="utf-8", newline="\n") as fh:
        fh.write(updated)
    print(f"Applied {changes} installer hardening change(s).")


if __name__ == "__main__":
    main()
