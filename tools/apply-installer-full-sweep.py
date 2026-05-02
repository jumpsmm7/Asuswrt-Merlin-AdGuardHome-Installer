#!/usr/bin/env python3
"""Apply one broad full-installer improvement sweep.

The installer is a large router-side POSIX/BusyBox shell script, so this script
uses exact-context and narrowly-scoped replacements. The goal is to improve
reliability and safety without reformatting or rewriting unrelated code.
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


def regex_replace(text: str, pattern: str, replacement: str, label: str) -> tuple[str, int]:
    updated, count = re.subn(pattern, replacement, text)
    if count == 0:
        print(f"SKIP: {label} already applied or context not found")
        return text, 0
    print(f"APPLY: {label} ({count} replacement(s))")
    return updated, count


def improve_full(text: str) -> tuple[str, int]:
    changes = 0

    old = '''readonly API_FILE="/tmp/AGH_GIT_API_$$.json"
readonly HEADER_FILE="/tmp/AGH_GIT_HEADERS_$$.out"
readonly LATEST_URL="https://api.github.com/repos/AdguardTeam/AdGuardHome/releases"
varcnt=0
readonly MAX_RETRIES="1"
'''
    new = '''readonly API_FILE="/tmp/AGH_GIT_API_$$.json"
readonly HEADER_FILE="/tmp/AGH_GIT_HEADERS_$$.out"
readonly LATEST_URL="https://api.github.com/repos/AdguardTeam/AdGuardHome/releases"
cleanup_startup_tmp() {
	rm -f "${API_FILE}" "${HEADER_FILE}"
}
trap cleanup_startup_tmp EXIT HUP INT TERM
varcnt=0
readonly MAX_RETRIES="2"
'''
    text, changed = replace_once(text, old, new, "add startup temp cleanup trap and allow one extra metadata retry")
    changes += int(changed)

    old = '''done
rm -f "${API_FILE}" "${HEADER_FILE}"
unset varcnt
readonly REMOTE_VER REMOTE_BETA
'''
    new = '''done
cleanup_startup_tmp
trap - EXIT HUP INT TERM
unset varcnt
readonly REMOTE_VER REMOTE_BETA
'''
    text, changed = replace_once(text, old, new, "use startup cleanup helper before continuing")
    changes += int(changed)

    old = '''cmd_exists() {
	[ -n "$1" ] || return 1
	which "$1" >/dev/null 2>&1
}

hash_password_python3() {
'''
    new = '''cmd_exists() {
	[ -n "$1" ] || return 1
	which "$1" >/dev/null 2>&1
}

wait_for_agh_pid_count() {
	_cmp="$1"
	_target="$2"
	_limit="${3:-30}"
	_count="0"
	while :; do
		_current="$(pidof AdGuardHome S99AdGuardHome | wc -w)"
		case "${_cmp}" in
		lt)
			[ "${_current}" -lt "${_target}" ] && return 0
			;;
	eq)
			[ "${_current}" -eq "${_target}" ] && return 0
			;;
		*)
			return 1
			;;
		esac
		_count="$((_count + 1))"
		[ "${_count}" -ge "${_limit}" ] && return 1
		sleep 1s
	done
}

hash_password_python3() {
'''
    text, changed = replace_once(text, old, new, "add bounded AdGuard Home PID wait helper")
    changes += int(changed)

    old = '''		({ until [ "$(pidof AdGuardHome S99AdGuardHome | wc -w)" -lt "1" ]; do sleep 1s; done; }) &
		local PID="$!"
		wait "${PID}" 2>/dev/null
'''
    new = '''		if ! wait_for_agh_pid_count lt 1 30; then
			PTXT "${WARNING} Timed out waiting for AdGuardHome processes to stop."
		fi
'''
    text, count = replace_all(text, old, new, "replace unbounded stop wait with bounded PID wait")
    changes += count

    old = '''		({ until [ "$(pidof AdGuardHome S99AdGuardHome | wc -w)" -eq "2" ]; do sleep 1s; done; }) &
		local PID="$!"
		wait "${PID}" 2>/dev/null
'''
    new = '''		if ! wait_for_agh_pid_count eq 2 30; then
			PTXT "${WARNING} Timed out waiting for AdGuardHome processes to start."
		fi
'''
    text, count = replace_all(text, old, new, "replace unbounded start wait with bounded PID wait")
    changes += count

    old = '''		({ until { check_connection && [ "$(pidof AdGuardHome S99AdGuardHome | wc -w)" -eq "2" ]; }; do sleep 1s; done; }) &
		local PID="$!"
		wait "${PID}" 2>/dev/null
'''
    new = '''		if ! check_connection || ! wait_for_agh_pid_count eq 2 30; then
			PTXT "${WARNING} Final connectivity or process check did not complete before timeout."
		fi
'''
    text, changed = replace_once(text, old, new, "replace unbounded final readiness wait with bounded checks")
    changes += int(changed)

    old = '''check_connection() {
	local livecheck="0" i
	while [ "${livecheck}" != "4" ]; do
		for i in google.com github.com snbforums.com; do
			if { ! nslookup "${i}" 127.0.0.1 >/dev/null 2>&1; } && { ping -q -w3 -c1 "${i}" >/dev/null 2>&1; }; then
				if { cmd_exists curl && curl --retry 5 --connect-timeout 25 --retry-delay 5 --max-time $((5 * 25)) --retry-connrefused -Is "http://${i}" | head -n 1 >/dev/null 2>&1; } || { cmd_exists wget && wget --no-cache --no-cookies --tries=5 --timeout=25 --waitretry=5 -q --spider "http://${i}" >/dev/null 2>&1; }; then
			:
		else
					sleep 1s
					continue
				fi
			fi
			return 0
		done
		livecheck="$((livecheck + 1))"
		if [ "${livecheck}" != "4" ]; then
			sleep 10s
			continue
		fi
		return 1
	done
}
'''
    new = '''check_connection() {
	local livecheck i
	livecheck="0"
	while [ "${livecheck}" -lt "4" ]; do
		for i in google.com github.com snbforums.com; do
			if nslookup "${i}" 127.0.0.1 >/dev/null 2>&1 || ping -q -w3 -c1 "${i}" >/dev/null 2>&1; then
				if { cmd_exists curl && curl --retry 5 --connect-timeout 25 --retry-delay 5 --max-time $((5 * 25)) --retry-connrefused -Is "http://${i}" | head -n 1 >/dev/null 2>&1; } || { cmd_exists wget && wget --no-cache --no-cookies --tries=5 --timeout=25 --waitretry=5 -q --spider "http://${i}" >/dev/null 2>&1; }; then
					return 0
				fi
			fi
		done
		livecheck="$((livecheck + 1))"
		[ "${livecheck}" -lt "4" ] && sleep 10s
	done
	return 1
}
'''
    text, changed = replace_once(text, old, new, "simplify and correct connectivity check flow")
    changes += int(changed)

    old = '''		(while { ! check_connection; }; do sleep 1s; done) &
		local PID="$!"
		wait "${PID}" 2>/dev/null
'''
    new = '''		if ! check_connection; then
			PTXT "${WARNING} Connectivity check did not pass after DNS environment changes."
		fi
'''
    text, count = replace_all(text, old, new, "replace unbounded connectivity wait with bounded check_connection result")
    changes += count

    text, count = replace_all(text, '''[ -z "$2" ] && end_op_message 0 || return 0''', '''[ -z "${2:-}" ] && end_op_message 0 || return 0''', "guard optional second positional parameter")
    changes += count

    text, count = replace_all(text, '''chmod 644 "${YAML_FILE}"''', '''chmod 644 "${YAML_FILE}" || return 1''', "fail YAML check early if chmod fails")
    changes += count

    text, count = replace_all(text, '''mv "${YAML_FILE}" "${YAML_BAK}"''', '''mv -f "${YAML_FILE}" "${YAML_BAK}"''', "force YAML backup replacement moves")
    changes += count

    text, count = replace_all(text, '''cp "${YAML_BAK}" "${YAML_FILE}"''', '''cp -f "${YAML_BAK}" "${YAML_FILE}"''', "force YAML restore copy replacements")
    changes += count

    text, count = replace_all(text, '''rm -rf "${YAML_FILE}"''', '''rm -f "${YAML_FILE}"''', "use rm -f for YAML file cleanup")
    changes += count

    text, count = replace_all(text, '''rm -rf "${YAML_BAK}"''', '''rm -f "${YAML_BAK}"''', "use rm -f for YAML backup cleanup")
    changes += count

    text, count = replace_all(text, '''rm -rf "${CONF_FILE}"''', '''rm -f "${CONF_FILE}"''', "use rm -f for installer config file cleanup")
    changes += count

    text, count = replace_all(text, '''rm -rf "${ADDON_DIR}/.installed"''', '''rm -f "${ADDON_DIR}/.installed"''', "use rm -f for addon installed marker cleanup")
    changes += count

    text, count = replace_all(text, '''rm -rf "${ADDON_DIR}/.needed"''', '''rm -f "${ADDON_DIR}/.needed"''', "use rm -f for addon needed marker cleanup")
    changes += count

    text, count = replace_all(text, '''rm -rf "${ADDON_DIR}/.installed" "${ADDON_DIR}/.needed"''', '''rm -f "${ADDON_DIR}/.installed" "${ADDON_DIR}/.needed"''', "use rm -f for addon marker cleanup pair")
    changes += count

    # Safer tests for optional positional parameters still using raw $1/$2.
    text, count = regex_replace(text, r'\[ -n "\$([12])" \]', r'[ -n "${\1:-}" ]', "guard non-empty checks for first two positional parameters")
    changes += count
    text, count = regex_replace(text, r'\[ -z "\$([12])" \]', r'[ -z "${\1:-}" ]', "guard empty checks for first two positional parameters")
    changes += count

    return text, changes


def main() -> int:
    if not INSTALLER.exists():
        print("Error: installer file not found", file=sys.stderr)
        return 1

    with INSTALLER.open("r", encoding="utf-8", newline="") as fh:
        original = fh.read()

    updated, changes = improve_full(original)

    if changes == 0:
        print("No full installer sweep changes were needed.")
        return 0

    with INSTALLER.open("w", encoding="utf-8", newline="\n") as fh:
        fh.write(updated)

    print(f"Applied {changes} full installer improvement sweep change(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
