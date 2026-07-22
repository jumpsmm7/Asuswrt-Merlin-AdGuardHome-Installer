#!/bin/sh
# Verify installer SHA-256 dependency helper behavior.

set -u

SCRIPT_PATH="${1:-installer}"
TMP_ROOT="${TMPDIR:-/tmp}/installer-sha256-helper.$$"
FUNCTIONS_FILE="${TMP_ROOT}/functions"

cleanup() {
	rm -rf "${TMP_ROOT}"
}

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

[ -f "${SCRIPT_PATH}" ] || fail "installer script not found: ${SCRIPT_PATH}"
grep -q 'ensure_sha256sum_tool' "${SCRIPT_PATH}" || fail 'installer is missing shared SHA-256 helper'
grep -q 'sha256_manifest_digest' "${SCRIPT_PATH}" || fail 'installer is missing strict SHA-256 manifest parsing'
grep -q 'SHA-256 metadata is unavailable' "${SCRIPT_PATH}" || fail 'installer does not report unavailable checksum metadata'
grep -q 'falling back to MD5 verification' "${SCRIPT_PATH}" || fail 'installer is missing its SHA-256-unavailable MD5 fallback'
grep -q 'opkg install coreutils-sha256sum' "${SCRIPT_PATH}" || fail 'installer does not explain the coreutils-sha256sum dependency'
grep -q 'ptxt_phase "Running AdGuardHome ${1:-install} orchestration."' "${SCRIPT_PATH}" || fail 'installer install/update orchestration phase is missing'
grep -q 'downloads will require matching MD5 metadata' "${SCRIPT_PATH}" || fail 'installer install/update path does not allow the MD5 fallback'
grep -q 'REMOTE_ADGUARD_SHA256="$(adguard_remote_sha256 "$2")"' "${SCRIPT_PATH}" || fail 'package install does not retain channel SHA-256 metadata'
grep -q 'ARCHIVE_SHA256.*REMOTE_ADGUARD_SHA256' "${SCRIPT_PATH}" || fail 'package install does not bind the archive to channel SHA-256 metadata'
grep -q 'ARCHIVE_MD5.*REMOTE_ADGUARD_MD5' "${SCRIPT_PATH}" || fail 'package install does not bind the archive to channel MD5 metadata'
grep -q 'ensure_blocklist_analyzer_dependencies || return 1' "${SCRIPT_PATH}" || fail 'option 9 does not require dependency checks before verification'
grep -q 'ensure_sha256sum_tool || return 1' "${SCRIPT_PATH}" || fail 'blocklist dependency helper does not require SHA-256 support'
grep -q 'if ! ensure_opkg_package python3 || \[ ! -x /opt/bin/python3 \]' "${SCRIPT_PATH}" || fail 'option 9 no longer requires Entware python3'
grep -q 'readonly BLOCKLIST_ANALYZER_FILE="${TARG_DIR}/blocklist_analyzer.py"' "${SCRIPT_PATH}" ||
	fail 'blocklist analyzer is not installed under the AdGuardHome target directory'
grep -q 'readonly BLOCKLIST_ANALYZER_URL="https://gist.githubusercontent.com/graysky2/8035291d1bf87b8fe3693668965337e1/raw/a4be7655095d6ff880c2f3748964b825d7c45bd2/blocklilst_analyzer.py"' "${SCRIPT_PATH}" ||
	fail 'blocklist analyzer URL is not pinned to the expected gist revision'
grep -q 'http_get_file "${BLOCKLIST_ANALYZER_URL}" "${BLOCKLIST_ANALYZER_FILE}.tmp"' "${SCRIPT_PATH}" ||
	fail 'blocklist analyzer is not downloaded to the target-directory temp path'
grep -q 'mv "${BLOCKLIST_ANALYZER_FILE}.tmp" "${BLOCKLIST_ANALYZER_FILE}"' "${SCRIPT_PATH}" ||
	fail 'blocklist analyzer temp download is not published to the target-directory path'
verify_line="$(grep -n 'Verifying blocklist analyzer SHA-256 checksum' "${SCRIPT_PATH}" | cut -d: -f1)" ||
	fail 'could not find blocklist checksum verification step'
guard_line="$(grep -n 'if ! ensure_sha256sum_tool; then' "${SCRIPT_PATH}" | head -n 1 | cut -d: -f1)" ||
	fail 'blocklist checksum verification does not offer coreutils-sha256sum before hashing'
hash_line="$(grep -n 'file_sha256 "${BLOCKLIST_ANALYZER_FILE}.tmp"' "${SCRIPT_PATH}" | cut -d: -f1)" ||
	fail 'could not find blocklist file_sha256 call'
[ "${verify_line}" -lt "${guard_line}" ] ||
	fail 'coreutils-sha256sum offer does not run during checksum verification'
[ "${guard_line}" -lt "${hash_line}" ] ||
	fail 'file_sha256 can run before coreutils-sha256sum is offered'

mkdir -p "${TMP_ROOT}" || fail 'could not create test directory'
sed -n \
	-e '/^PTXT() {$/,/^}/p' \
	-e '/^ptxt_step() {$/,/^}/p' \
	-e '/^ptxt_ok() {$/,/^}/p' \
	-e '/^ptxt_warn() {$/,/^}/p' \
	-e '/^ptxt_fail() {$/,/^}/p' \
	-e '/^ai_have_cmd() {$/,/^}/p' \
	-e '/^sha256_is_valid() {$/,/^}/p' \
	-e '/^file_sha256() {$/,/^}/p' \
	-e '/^sha256sum_available() {$/,/^}/p' \
	-e '/^ensure_sha256sum_tool() {$/,/^}/p' \
	-e '/^ensure_blocklist_analyzer_dependencies() {$/,/^}/p' \
	"${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" ||
	fail 'could not extract SHA-256 helper functions'
[ -s "${FUNCTIONS_FILE}" ] || fail 'SHA-256 helper extraction was empty'
# Let the test mock the router absolute BusyBox probe separately from PATH.
# Hosts (and routers) may have /bin/busybox with a sha256sum applet, which
# would otherwise make the missing-tool cases observe the host environment.
sed -e 's#/bin/busybox#${BUSYBOX_BIN:-/bin/busybox}#g' \
	-e 's#/opt/bin/python3#${PYTHON3_BIN:-/opt/bin/python3}#g' \
	"${FUNCTIONS_FILE}" >"${FUNCTIONS_FILE}.tmp" ||
	fail 'could not make absolute helper probes mockable'
mv "${FUNCTIONS_FILE}.tmp" "${FUNCTIONS_FILE}" || fail 'could not update extracted SHA-256 helpers'

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	INFO='Info:'
	ERROR='Error:'
	WARNING='Warning:'
	INPUT='Input:'
	BOLD=''
	NORM=''
	ptxt_fail() {
		printf '%s\n' "$*"
		return 1
	}
	ensure_opkg_package() {
		printf '%s\n' 'install should not run when sha256sum exists'
		return 1
	}
	mkdir -p "${TMP_ROOT}/available-bin" || exit 1
	cat >"${TMP_ROOT}/available-bin/which" <<EOF_WHICH || exit 1
#!/bin/sh
[ "\$1" = "sha256sum" ] || exit 1
printf '%s\n' "${TMP_ROOT}/available-bin/sha256sum"
EOF_WHICH
	cat >"${TMP_ROOT}/available-bin/sha256sum" <<'EOF_SHA' || exit 1
#!/bin/sh
exit 0
EOF_SHA
	chmod 755 "${TMP_ROOT}/available-bin/which" "${TMP_ROOT}/available-bin/sha256sum" || exit 1
	BUSYBOX_BIN="${TMP_ROOT}/not-busybox"
	PATH="${TMP_ROOT}/available-bin"
	ensure_sha256sum_tool >"${TMP_ROOT}/available.out" 2>&1
) || fail 'SHA-256 helper failed when sha256sum was already available'
[ ! -s "${TMP_ROOT}/available.out" ] || fail 'SHA-256 helper prompted or installed when sha256sum was already available'

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	ERROR='Error:'
	BUSYBOX_BIN="${TMP_ROOT}/not-busybox"
	# ai_have_cmd reports whether the requested command is the supported `sha256sum` utility.
	ai_have_cmd() { [ "$1" = sha256sum ]; }
	# sha256sum prints a zero-filled digest for the specified file and exits with failure.
	sha256sum() {
		printf '%064d  %s\n' 0 "$1"
		return 1
	}
	if file_sha256 "${TMP_ROOT}/unused" >/dev/null 2>&1; then
		exit 1
	fi
) || fail 'file_sha256 accepted digest output from a failing SHA-256 applet'

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	INFO='Info:'
	ERROR='Error:'
	WARNING='Warning:'
	INPUT='Input:'
	BOLD=''
	NORM=''
	ptxt_fail() {
		printf '%s\n' "$*"
		return 1
	}
	ensure_opkg_package() {
		printf '%s\n' 'install should not run when BusyBox sha256sum exists'
		return 1
	}
	mkdir -p "${TMP_ROOT}/busybox-bin" || exit 1
	cat >"${TMP_ROOT}/busybox-bin/which" <<EOF_WHICH || exit 1
#!/bin/sh
[ "\$1" = "busybox" ] || exit 1
printf '%s\n' "${TMP_ROOT}/busybox-bin/busybox"
EOF_WHICH
	cat >"${TMP_ROOT}/busybox-bin/busybox" <<'EOF_BUSYBOX' || exit 1
#!/bin/sh
[ "$1" = "sha256sum" ] || exit 1
printf '%s  %s\n' 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' "$2"
EOF_BUSYBOX
	chmod 755 "${TMP_ROOT}/busybox-bin/which" "${TMP_ROOT}/busybox-bin/busybox" || exit 1
	BUSYBOX_BIN="${TMP_ROOT}/busybox-bin/busybox"
	PATH="${TMP_ROOT}/busybox-bin"
	ensure_sha256sum_tool >"${TMP_ROOT}/busybox.out" 2>&1
) || fail 'SHA-256 helper failed when only BusyBox sha256sum applet was available'
[ ! -s "${TMP_ROOT}/busybox.out" ] || fail 'SHA-256 helper prompted or installed when BusyBox sha256sum was available'

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	INFO='Info:'
	ERROR='Error:'
	WARNING='Warning:'
	INPUT='Input:'
	BOLD=''
	NORM=''
	mkdir -p "${TMP_ROOT}/install-bin" || exit 1
	cat >"${TMP_ROOT}/install-bin/which" <<EOF_WHICH || exit 1
#!/bin/sh
if [ "\$1" = "sha256sum" ] && [ -f "${TMP_ROOT}/install-bin/installed" ]; then
	printf '%s\n' "${TMP_ROOT}/install-bin/sha256sum"
	exit 0
fi
exit 1
EOF_WHICH
	cat >"${TMP_ROOT}/install-bin/sha256sum" <<'EOF_SHA' || exit 1
#!/bin/sh
exit 0
EOF_SHA
	chmod 755 "${TMP_ROOT}/install-bin/which" "${TMP_ROOT}/install-bin/sha256sum" || exit 1
	BUSYBOX_BIN="${TMP_ROOT}/not-busybox"
	PATH="${TMP_ROOT}/install-bin"
	ensure_opkg_package() {
		[ "$1" = "coreutils-sha256sum" ] || return 1
		: >"${TMP_ROOT}/install-bin/installed"
	}
	ensure_sha256sum_tool >"${TMP_ROOT}/install.out" 2>&1
) || fail 'SHA-256 helper failed after accepted coreutils-sha256sum install'
grep -q 'Installing Entware coreutils-sha256sum package' "${TMP_ROOT}/install.out" || fail 'SHA-256 helper did not install accepted package'

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	INFO='Info:'
	ERROR='Error:'
	WARNING='Warning:'
	INPUT='Input:'
	BOLD=''
	NORM=''
	mkdir -p "${TMP_ROOT}/missing-bin" || exit 1
	cat >"${TMP_ROOT}/missing-bin/which" <<'EOF_WHICH' || exit 1
#!/bin/sh
exit 1
EOF_WHICH
	chmod 755 "${TMP_ROOT}/missing-bin/which" || exit 1
	BUSYBOX_BIN="${TMP_ROOT}/not-busybox"
	PATH="${TMP_ROOT}/missing-bin"
	ensure_opkg_package() { [ "$1" = "coreutils-sha256sum" ]; }
	if ensure_sha256sum_tool >"${TMP_ROOT}/missing.out" 2>&1; then
		exit 1
	fi
) || fail 'SHA-256 helper succeeded even though sha256sum was still missing after install'
grep -q 'sha256sum is still unavailable' "${TMP_ROOT}/missing.out" || fail 'SHA-256 helper did not clearly fail when sha256sum remained missing'

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	INFO='Info:'
	ERROR='Error:'
	WARNING='Warning:'
	INPUT='Input:'
	BOLD=''
	NORM=''
	mkdir -p "${TMP_ROOT}/blocklist-bin" || exit 1
	cat >"${TMP_ROOT}/blocklist-bin/which" <<EOF_WHICH || exit 1
#!/bin/sh
case "\$1" in
	python3)
		[ -f "${TMP_ROOT}/blocklist-bin/python-installed" ] || exit 1
		printf '%s\n' "${TMP_ROOT}/blocklist-bin/python3"
		;;
	sha256sum)
		exit 1
		;;
	*)
		exit 1
		;;
esac
EOF_WHICH
	cat >"${TMP_ROOT}/blocklist-bin/python3.src" <<'EOF_PYTHON' || exit 1
#!/bin/sh
exit 0
EOF_PYTHON
	chmod 755 "${TMP_ROOT}/blocklist-bin/which" "${TMP_ROOT}/blocklist-bin/python3.src" || exit 1
	BUSYBOX_BIN="${TMP_ROOT}/not-busybox"
	PATH="${TMP_ROOT}/blocklist-bin"
	PYTHON3_BIN="${TMP_ROOT}/blocklist-bin/python3"
	read_yesno() { return 0; }
	ensure_opkg_package() {
		case "$1" in
			python3) /bin/cp "${TMP_ROOT}/blocklist-bin/python3.src" "${TMP_ROOT}/blocklist-bin/python3" && /bin/chmod 755 "${TMP_ROOT}/blocklist-bin/python3" && : >"${TMP_ROOT}/blocklist-bin/python-installed" ;;
			coreutils-sha256sum) : >"${TMP_ROOT}/blocklist-bin/sha-requested" ;;
			*) return 1 ;;
		esac
	}
	if ensure_blocklist_analyzer_dependencies >"${TMP_ROOT}/blocklist-deps.out" 2>&1; then
		exit 1
	fi
	[ -f "${TMP_ROOT}/blocklist-bin/python-installed" ] || exit 1
	[ -f "${TMP_ROOT}/blocklist-bin/sha-requested" ] || exit 1
) || fail 'blocklist dependency helper did not require python3 before SHA-256 support'
grep -q 'python3 is available' "${TMP_ROOT}/blocklist-deps.out" || fail 'blocklist dependency helper did not proceed through python3 check'
grep -q 'sha256sum is still unavailable' "${TMP_ROOT}/blocklist-deps.out" || fail 'blocklist dependency helper did not stop clearly when SHA-256 remained unavailable'

(
	# shellcheck disable=SC1090
	. "${FUNCTIONS_FILE}"
	INFO='Info:'
	ERROR='Error:'
	WARNING='Warning:'
	INPUT='Input:'
	BOLD=''
	NORM=''
	mkdir -p "${TMP_ROOT}/blocklist-ready-bin" || exit 1
	cat >"${TMP_ROOT}/blocklist-ready-bin/which" <<EOF_WHICH || exit 1
#!/bin/sh
case "\$1" in
	python3) printf '%s\n' "${TMP_ROOT}/blocklist-ready-bin/python3" ;;
	sha256sum) printf '%s\n' "${TMP_ROOT}/blocklist-ready-bin/sha256sum" ;;
	*) exit 1 ;;
esac
EOF_WHICH
	cat >"${TMP_ROOT}/blocklist-ready-bin/python3" <<'EOF_PYTHON' || exit 1
#!/bin/sh
exit 0
EOF_PYTHON
	cat >"${TMP_ROOT}/blocklist-ready-bin/sha256sum" <<'EOF_SHA' || exit 1
#!/bin/sh
exit 0
EOF_SHA
	chmod 755 "${TMP_ROOT}/blocklist-ready-bin/which" \
		"${TMP_ROOT}/blocklist-ready-bin/python3" \
		"${TMP_ROOT}/blocklist-ready-bin/sha256sum" || exit 1
	BUSYBOX_BIN="${TMP_ROOT}/not-busybox"
	PATH="${TMP_ROOT}/blocklist-ready-bin"
	PYTHON3_BIN="${TMP_ROOT}/blocklist-ready-bin/python3"
	ensure_opkg_package() { exit 1; }
	ensure_blocklist_analyzer_dependencies >"${TMP_ROOT}/blocklist-ready.out" 2>&1
) || fail 'blocklist dependency helper failed when python3 and sha256sum were available'

printf '%s\n' 'PASS: installer SHA-256 helper handles available, BusyBox applet, automatic install, post-install failure, and option 9 dependency paths'
