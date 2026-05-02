#!/usr/bin/env python3
"""Apply additional installer reliability improvements.

This second sweep focuses on dependency installation and service/NVRAM command
error handling. It uses exact-context replacements only.
"""

from __future__ import annotations

from pathlib import Path
import re
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


def regex_replace(text: str, pattern: str, replacement: str, label: str) -> tuple[str, int]:
    updated, count = re.subn(pattern, replacement, text)
    if count == 0:
        print(f"SKIP: {label} already applied or context not found")
        return text, 0
    print(f"APPLY: {label} ({count} replacement(s))")
    return updated, count


def improve_full_2(text: str) -> tuple[str, int]:
    changes = 0

    text, count = replace_all(text, '''opkg install "${i}"''', '''if ! opkg install "${i}"; then
			PTXT "${ERROR} Failed to install required package: ${i}"
			end_op_message 1
			return
		fi''', "fail cleanly when required opkg package install fails")
    changes += count

    text, count = replace_all(text, '''opkg install go >/dev/null 2>&1''', '''if ! opkg install go >/dev/null 2>&1; then
				PTXT "${ERROR} Failed to install Go toolchain dependency."
				end_op_message 1
				return
			fi''', "fail cleanly when Go package install fails")
    changes += count

    text, count = replace_all(text, '''if opkg_available go_nohf; then opkg install go_nohf >/dev/null 2>&1; else opkg install go >/dev/null 2>&1; fi''', '''if opkg_available go_nohf; then
				if ! opkg install go_nohf >/dev/null 2>&1; then
					PTXT "${ERROR} Failed to install Go no-HF toolchain dependency."
					end_op_message 1
					return
				fi
			else
				if ! opkg install go >/dev/null 2>&1; then
					PTXT "${ERROR} Failed to install Go toolchain dependency."
					end_op_message 1
					return
				fi
			fi''', "fail cleanly when Go fallback package install fails")
    changes += count

    text, count = replace_all(text, '''go install gophers.dev/cmds/bcrypt-tool@latest >/dev/null 2>&1''', '''if ! go install gophers.dev/cmds/bcrypt-tool@latest >/dev/null 2>&1; then
			PTXT "${ERROR} Failed to build bcrypt-tool."
			end_op_message 1
			return
		fi''', "fail cleanly when bcrypt-tool build fails")
    changes += count

    text, count = replace_all(text, '''pip3 install bcrypt >/dev/null 2>&1''', '''if ! pip3 install bcrypt >/dev/null 2>&1; then
			PTXT "${ERROR} Failed to install Python bcrypt module."
			end_op_message 1
			return
		fi''', "fail cleanly when pip bcrypt install fails")
    changes += count

    text, count = replace_all(text, '''{ nvram commit; }''', '''if ! nvram commit; then
			PTXT "${WARNING} nvram commit did not complete successfully."
		fi''', "warn when nvram commit fails")
    changes += count

    text, count = replace_all(text, '''{ service restart_dnsmasq >/dev/null 2>&1; }''', '''if ! service restart_dnsmasq >/dev/null 2>&1; then
			PTXT "${WARNING} dnsmasq restart command did not complete successfully."
		fi''', "warn when dnsmasq restart fails")
    changes += count

    text, count = regex_replace(text, r'if \[ "\$\(pidof ([A-Za-z0-9_ -]+)\)" \]; then', r'if [ -n "$(pidof \1)" ]; then', "make pidof tests explicit")
    changes += count

    return text, changes


def main() -> int:
    if not INSTALLER.exists():
        print("Error: installer file not found", file=sys.stderr)
        return 1

    with INSTALLER.open("r", encoding="utf-8", newline="") as fh:
        original = fh.read()

    updated, changes = improve_full_2(original)

    if changes == 0:
        print("No additional full installer sweep changes were needed.")
        return 0

    with INSTALLER.open("w", encoding="utf-8", newline="\n") as fh:
        fh.write(updated)

    print(f"Applied {changes} additional full installer sweep change(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
