#!/usr/bin/env python3
"""Apply a second broad installer improvement pass.

This script keeps the same exact-context strategy used by earlier installer
passes so the large router-side installer is changed deterministically from a
full checkout instead of through a truncated API response.
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


def improve_installer_2(text: str) -> tuple[str, int]:
    changes = 0

    old = '''readonly API_FILE="/tmp/AGH_GIT_API_$$.json"
readonly LATEST_URL="https://api.github.com/repos/AdguardTeam/AdGuardHome/releases"
'''
    new = '''readonly API_FILE="/tmp/AGH_GIT_API_$$.json"
readonly HEADER_FILE="/tmp/AGH_GIT_HEADERS_$$.out"
readonly LATEST_URL="https://api.github.com/repos/AdguardTeam/AdGuardHome/releases"
'''
    text, changed = replace_once(text, old, new, "use named temporary header file for release metadata fetch")
    changes += int(changed)

    text, count = replace_all(text, '''"/tmp/$$_headers.out"''', '''"${HEADER_FILE}"''', "use HEADER_FILE variable in quoted contexts")
    changes += count
    text, count = replace_all(text, '''/tmp/$$_headers.out''', '''${HEADER_FILE}''', "use HEADER_FILE variable in unquoted messages")
    changes += count

    old = '''rm -f "$API_FILE" "${HEADER_FILE}"
wait
unset varcnt
'''
    new = '''rm -f "${API_FILE}" "${HEADER_FILE}"
unset varcnt
'''
    text, changed = replace_once(text, old, new, "remove unnecessary global wait after metadata fetch")
    changes += int(changed)

    old = '''safe_download() {
	_url="$1"
	_output="$2"
	[ -n "${_url}" ] && [ -n "${_output}" ] || return 1
	_tmp_output="${_output}.$$"
'''
    new = '''safe_download() {
	_url="$1"
	_output="$2"
	[ -n "${_url}" ] && [ -n "${_output}" ] || return 1
	case "${_output}" in
	/*) ;;
	*) return 1 ;;
	esac
	_tmp_output="${_output}.$$"
'''
    text, changed = replace_once(text, old, new, "require absolute output path for safe_download")
    changes += int(changed)

    text, count = replace_all(text, '''[ "$1" -eq 0 ]''', '''[ "${1:-}" = "0" ]''', "avoid numeric comparison for first argument zero checks")
    changes += count
    text, count = replace_all(text, '''[ "$1" -eq 1 ]''', '''[ "${1:-}" = "1" ]''', "avoid numeric comparison for first argument one checks")
    changes += count
    text, count = replace_all(text, '''[ "$1" = "BACKUP" ]''', '''[ "${1:-}" = "BACKUP" ]''', "guard BACKUP argument comparisons")
    changes += count
    text, count = replace_all(text, '''[ "$1" = "RESTORE" ]''', '''[ "${1:-}" = "RESTORE" ]''', "guard RESTORE argument comparisons")
    changes += count

    text, count = replace_all(text, '''service "restart_firewall;restart_dnsmasq" >/dev/null 2>&1''', '''service restart_firewall >/dev/null 2>&1
		service restart_dnsmasq >/dev/null 2>&1''', "restart firewall and dnsmasq as separate service calls")
    changes += count

    text, count = replace_all(text, '''ln -sf "${AGH_FILE}" /opt/sbin/AdGuardHome''', '''if ! ln -sf "${AGH_FILE}" /opt/sbin/AdGuardHome; then
			PTXT "${ERROR} Could not create /opt/sbin/AdGuardHome symlink."
			end_op_message 1
			return
		fi''', "fail cleanly if AdGuardHome symlink cannot be created")
    changes += count

    text, count = replace_all(text, '''chmod 755 "${AGH_FILE}"
		chmod 644 "${YAML_FILE}"''', '''if ! chmod 755 "${AGH_FILE}"; then
			PTXT "${ERROR} Could not set AdGuardHome executable permissions."
			end_op_message 1
			return
		fi
		if ! chmod 644 "${YAML_FILE}"; then
			PTXT "${ERROR} Could not set AdGuardHome YAML permissions."
			end_op_message 1
			return
		fi''', "fail cleanly if restored file permissions cannot be set")
    changes += count

    return text, changes


def main() -> int:
    if not INSTALLER.exists():
        print("Error: installer file not found", file=sys.stderr)
        return 1

    with INSTALLER.open("r", encoding="utf-8", newline="") as fh:
        original = fh.read()

    updated, changes = improve_installer_2(original)

    if changes == 0:
        print("No installer improvement pass 2 changes were needed.")
        return 0

    with INSTALLER.open("w", encoding="utf-8", newline="\n") as fh:
        fh.write(updated)

    print(f"Applied {changes} installer improvement pass 2 change(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
