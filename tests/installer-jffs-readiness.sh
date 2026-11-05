#!/bin/sh
# Verify JFFS diagnostics distinguish failed reads, legacy absence and transaction stages.
set -u
INSTALLER_PATH="${1:-installer}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/installer-jffs-readiness.XXXXXX")" || exit 1
# fail reports a failed fixture assertion and exits the test.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}
# cleanup removes only the private fixture directory when the test exits.
cleanup() { rm -rf "${TEST_ROOT}"; }
trap cleanup 0
trap 'exit 1' HUP INT TERM
{
	sed -n '/^jffs_read_settings() {$/,/^preflight_check_jffs_ready() {$/p' "${INSTALLER_PATH}" | sed '$d'
	sed -n '/^preflight_check_jffs_ready() {$/,/^preflight_check_router_eligibility() {$/p' "${INSTALLER_PATH}" | sed '$d'
	sed -n '/^check_jffs_enabled() {$/,/^check_version() {$/p' "${INSTALLER_PATH}" | sed '$d'
} >"${TEST_ROOT}/functions"
# Each fixture exposes only the four JFFS keys; no package tooling participates.
# run_case runs the real JFFS helper against one modeled read or enablement failure.
run_case() {
	case_name="$1"
	entry="$2"
	expected_status="$3"
	expected_text="$4"
	(
		. "${TEST_ROOT}/functions"
		# PTXT captures installer diagnostics without terminal formatting.
		PTXT() { printf '%s\n' "$*"; }
		ERROR=ERROR INFO=INFO
		# nvram models JFFS key reads and inventory outcomes for the selected readiness case.
		# installer_nvram forwards calls to this fixture's NVRAM model.
		installer_nvram() { nvram "$@"; }
		nvram() {
			if [ "$1" = show ]; then
				case "${case_name}" in
					legacy | legacy-hnd | legacy-disabled) printf '%s\n' jffs2_scripts=1 jffs2_on=1 ;;
					absent-scripts | absent-scripts-zero) printf '%s\n' jffs2_format=0 jffs2_enable=1 ;;
					absent-enable | absent-enable-zero) printf '%s\n' jffs2_format=0 jffs2_scripts=1 ;;
					empty-scripts) printf '%s\n' jffs2_format=0 jffs2_scripts= jffs2_enable=1 ;;
					empty-on) printf '%s\n' jffs2_format=0 jffs2_scripts=1 jffs2_on= ;;
					failed-on) printf '%s\n' jffs2_format=0 jffs2_scripts=1 jffs2_on=1 ;;
					empty-inventory) return 0 ;;
					partial-failed-scripts) printf '%s\n' jffs2_format=0 jffs2_enable=1 ;;
					*) printf '%s\n' jffs2_format=0 jffs2_scripts=1 jffs2_enable=1 ;;
				esac
				[ "${case_name}" != legacy-hnd ]
				return "$?"
			fi
			[ "$1" = get ] || return 1
			case "${case_name}:$2" in
				failed-read:jffs2_format) return 1 ;;
				failed-enable:jffs2_enable) return 1 ;;
				failed-scripts:jffs2_scripts) return 1 ;;
				absent-scripts:jffs2_scripts | absent-enable:jffs2_enable | absent-enable:jffs2_on | empty-on:jffs2_enable | failed-on:jffs2_enable | failed-on:jffs2_on) return 1 ;;
				absent-scripts-zero:jffs2_scripts | absent-enable-zero:jffs2_enable | absent-enable-zero:jffs2_on | empty-scripts:jffs2_scripts | empty-on:jffs2_on) return 0 ;;
				unknown:jffs2_scripts) printf '%s\n' invalid ;;
				legacy:jffs2_format | legacy:jffs2_enable | legacy-hnd:jffs2_format | legacy-hnd:jffs2_enable | legacy-disabled:jffs2_format | legacy-disabled:jffs2_enable | empty-inventory:jffs2_format | empty-inventory:jffs2_enable) return 1 ;;
				partial-failed-scripts:jffs2_scripts)
					printf '%s\n' 1
					return 1
					;;
				pending:jffs2_format) printf '%s\n' 1 ;;
				lock:jffs2_scripts | storage:jffs2_scripts | legacy-disabled:jffs2_scripts) printf '%s\n' 0 ;;
				*:jffs2_format) printf '%s\n' 0 ;;
				*:jffs2_scripts | *:jffs2_enable | *:jffs2_on) printf '%s\n' 1 ;;
				*) return 1 ;;
			esac
		}
		# nvram_transaction_begin models snapshots and stage failures without touching router NVRAM.
		nvram_transaction_begin() {
			printf '%s\n' transaction >>"${TEST_ROOT}/${case_name}.writes"
			case "${case_name}" in
				absent-scripts | absent-scripts-zero | absent-enable | absent-enable-zero)
					NVRAM_TRANSACTION_DIR="${TEST_ROOT}/${case_name}.snapshot"
					mkdir "${NVRAM_TRANSACTION_DIR}" || return 1
					for key in jffs2_format jffs2_scripts jffs2_enable jffs2_on; do
						nvram get "${key}" >"${NVRAM_TRANSACTION_DIR}/${key}" || true
						if nvram show | grep -q "^${key}="; then
							: >"${NVRAM_TRANSACTION_DIR}/exists.${key}"
						fi
					done
					return 0
					;;
				lock)
					NVRAM_TRANSACTION_BEGIN_STAGE=lock
					return 1
					;;
				storage)
					NVRAM_TRANSACTION_BEGIN_STAGE=snapshot-storage
					return 1
					;;
				*) return 1 ;;
			esac
		}
		# nvram_transaction_set records the enablement values requested for an absent legacy key.
		nvram_transaction_set() { printf '%s=%s\n' "$1" "$2" >>"${TEST_ROOT}/${case_name}.writes"; }
		# nvram_transaction_apply marks the successful modeled enablement boundary.
		nvram_transaction_apply() { printf '%s\n' 'legacy enablement applied'; }
		"${entry}"
	) >"${TEST_ROOT}/${case_name}.out" 2>&1
	status=$?
	[ "${status}" -eq "${expected_status}" ] || fail "${case_name}: expected ${expected_status}, got ${status}"
	grep -Fq "${expected_text}" "${TEST_ROOT}/${case_name}.out" || fail "${case_name}: missing ${expected_text}"
	case "${case_name}" in
		lock | storage) ;;
		absent-scripts | absent-scripts-zero) grep -Fxq jffs2_scripts=1 "${TEST_ROOT}/${case_name}.writes" || fail 'absent scripts flag was not enabled' ;;
		absent-enable | absent-enable-zero) grep -Fxq jffs2_on=1 "${TEST_ROOT}/${case_name}.writes" || fail 'absent legacy enable flag was not enabled' ;;
		*) [ ! -e "${TEST_ROOT}/${case_name}.writes" ] || fail "${case_name}: unexpected JFFS transaction" ;;
	esac
}
run_case failed-read preflight_check_jffs_ready 1 'preflight.jffs.reason=read-failed:jffs2_format'
run_case failed-enable preflight_check_jffs_ready 1 'preflight.jffs.reason=read-failed:jffs2_enable'
run_case unknown preflight_check_jffs_ready 1 'preflight.jffs.reason=invalid-value:jffs2_scripts'
run_case empty-scripts preflight_check_jffs_ready 1 'preflight.jffs.reason=missing-value:jffs2_scripts'
run_case failed-scripts preflight_check_jffs_ready 1 'preflight.jffs.reason=read-failed:jffs2_scripts'
run_case empty-on preflight_check_jffs_ready 1 'preflight.jffs.reason=missing-value:jffs2_on'
run_case failed-on preflight_check_jffs_ready 1 'preflight.jffs.reason=read-failed:jffs2_on'
run_case empty-inventory preflight_check_jffs_ready 1 'preflight.jffs.reason=read-failed:nvram-inventory'
run_case partial-failed-scripts preflight_check_jffs_ready 1 'preflight.jffs.reason=read-failed:jffs2_scripts'
run_case pending preflight_check_jffs_ready 1 'preflight.jffs.reason=format-pending'
run_case ready preflight_check_jffs_ready 0 'preflight.jffs.result=OK'
run_case legacy preflight_check_jffs_ready 0 'preflight.jffs.format_pending=legacy-absent'
run_case legacy-hnd preflight_check_jffs_ready 0 'preflight.jffs.format_pending=legacy-absent'
run_case legacy-disabled preflight_check_jffs_ready 1 'preflight.jffs.format_pending=legacy-absent'
run_case ready check_jffs_enabled 0 'already enabled'
run_case failed-read check_jffs_enabled 1 'read-failed:jffs2_format'
run_case lock check_jffs_enabled 1 'JFFS transaction failed at lock'
run_case storage check_jffs_enabled 1 'JFFS transaction failed at snapshot-storage'
run_case absent-scripts check_jffs_enabled 0 'legacy enablement applied'
run_case absent-scripts-zero check_jffs_enabled 0 'legacy enablement applied'
run_case absent-enable check_jffs_enabled 0 'legacy enablement applied'
run_case absent-enable-zero check_jffs_enabled 0 'legacy enablement applied'

# Force a real exec boundary even when the running shell implements printf as
# a builtin. Passing the complete inventory as one argument exceeds Linux's
# argument limit; feeding it through stdin to a bounded reader does not.
cat >"${TEST_ROOT}/external-printf" <<'EOF_PRINTF'
#!/bin/sh
printf "$@"
EOF_PRINTF
chmod 700 "${TEST_ROOT}/external-printf" || fail 'could not prepare external printf'
# The key-like text inside this unrelated value is not a JFFS record. Relevant
# records appear after the one-MiB value, so the reader must consume the stream.
awk 'BEGIN {
	value = "x"
	for (i = 0; i < 20; i++) value = value value
	printf "private_inventory_marker=%s jffs2_format=1\n", value
}' >"${TEST_ROOT}/large-inventory" || fail 'could not prepare synthetic inventory'

# run_large_case exercises the real readiness path with a large unrelated value
# while all firmware operations remain read-only private models.
run_large_case() {
	case_name="$1"
	entry="$2"
	expected_status="$3"
	expected_text="$4"
	case_output="${TEST_ROOT}/large-${case_name}-${entry}.out"
	(
		. "${TEST_ROOT}/functions"
		printf() { "${TEST_ROOT}/external-printf" "$@"; }
		PTXT() { printf '%s\n' "$*"; }
		ERROR=ERROR INFO=INFO
		installer_nvram() {
			case "$1" in
				show)
					case "${case_name}" in
						empty) return 1 ;;
						malformed)
							sed 's/^/#/' "${TEST_ROOT}/large-inventory"
							return "$?"
							;;
					esac
					cat "${TEST_ROOT}/large-inventory" || return 1
					case "${case_name}" in
						empty-format) printf '%s\n' jffs2_format= jffs2_scripts=1 jffs2_enable=1 ;;
						failed-format) printf '%s\n' jffs2_format=0 jffs2_scripts=1 jffs2_enable=1 ;;
						empty-scripts) printf '%s\n' jffs2_scripts= jffs2_enable=1 ;;
						empty-on) printf '%s\n' jffs2_scripts=1 jffs2_on= ;;
						failed-on) printf '%s\n' jffs2_scripts=1 jffs2_on=1 ;;
						enabled | enabled-hnd) printf '%s\n' jffs2_format=0 jffs2_scripts=1 jffs2_on=1 ;;
						pending) printf '%s\n' jffs2_format=1 jffs2_scripts=1 jffs2_on=1 ;;
						disabled) printf '%s\n' jffs2_scripts=0 jffs2_enable=1 ;;
						*) printf '%s\n' jffs2_scripts=1 jffs2_enable=1 ;;
					esac
					case "${case_name}" in ready-hnd | enabled-hnd) return 7 ;; *) return 0 ;; esac
					;;
				get)
					case "${case_name}:$2" in
						failed-format:jffs2_format | failed-scripts:jffs2_scripts | failed-on:jffs2_on) return 1 ;;
						empty-on:jffs2_enable | failed-on:jffs2_enable | pending:jffs2_enable | enabled:jffs2_enable | enabled-hnd:jffs2_enable | empty-on:jffs2_on | empty-scripts:jffs2_scripts) return 0 ;;
						pending:jffs2_format) printf '%s\n' 1 ;;
						enabled:jffs2_format | enabled-hnd:jffs2_format) printf '%s\n' 0 ;;
						*:jffs2_format) return 0 ;;
						disabled:jffs2_scripts) printf '%s\n' 0 ;;
						*:jffs2_scripts | *:jffs2_enable | *:jffs2_on) printf '%s\n' 1 ;;
						*) return 1 ;;
					esac
					;;
				*)
					printf '%s\n' "$1" >>"${TEST_ROOT}/large-${case_name}.writes"
					return 1
					;;
			esac
		}
		if [ "${case_name}" = filter-failed ]; then
			# Usable output does not excuse failure of the new inventory filter.
			awk() {
				command awk "$@"
				return 1
			}
		fi
		"${entry}"
	) >"${case_output}" 2>&1
	status=$?
	[ "${status}" -eq "${expected_status}" ] || fail "large ${case_name}: expected ${expected_status}, got ${status}"
	grep -Fq "${expected_text}" "${case_output}" || fail "large ${case_name}: missing ${expected_text}"
	if grep -Eq 'Argument list too long|private_inventory_marker' "${case_output}"; then
		fail "large ${case_name}: inventory crossed an argument or diagnostic boundary"
	fi
	[ ! -e "${TEST_ROOT}/large-${case_name}.writes" ] || fail "large ${case_name}: unexpected NVRAM mutation"
}
run_large_case ready preflight_check_jffs_ready 0 'preflight.jffs.result=OK'
run_large_case ready-hnd preflight_check_jffs_ready 0 'preflight.jffs.result=OK'
run_large_case enabled check_jffs_enabled 0 'already enabled'
run_large_case enabled-hnd check_jffs_enabled 0 'already enabled'
run_large_case failed-format preflight_check_jffs_ready 1 'preflight.jffs.reason=read-failed:jffs2_format'
run_large_case failed-scripts preflight_check_jffs_ready 1 'preflight.jffs.reason=read-failed:jffs2_scripts'
run_large_case empty-format preflight_check_jffs_ready 1 'preflight.jffs.reason=missing-value:jffs2_format'
run_large_case empty-scripts preflight_check_jffs_ready 1 'preflight.jffs.reason=missing-value:jffs2_scripts'
run_large_case empty-on preflight_check_jffs_ready 1 'preflight.jffs.reason=missing-value:jffs2_on'
run_large_case failed-on preflight_check_jffs_ready 1 'preflight.jffs.reason=read-failed:jffs2_on'
run_large_case pending preflight_check_jffs_ready 1 'preflight.jffs.reason=format-pending'
run_large_case disabled preflight_check_jffs_ready 1 'preflight.jffs.reason=enablement-required'
run_large_case malformed preflight_check_jffs_ready 1 'preflight.jffs.reason=read-failed:nvram-inventory'
run_large_case empty preflight_check_jffs_ready 1 'preflight.jffs.reason=read-failed:nvram-inventory'
run_large_case filter-failed preflight_check_jffs_ready 1 'preflight.jffs.reason=read-failed:nvram-inventory'

# Exercise the real transaction begin seam, including filesystem failure.
sed -n '/^nvram_transaction_begin() {$/,/^}/p; /^nvram_transaction_begin_locked() {$/,/^}/p' "${INSTALLER_PATH}" >"${TEST_ROOT}/transaction-functions"
for stage_case in lock storage inventory key; do
	(
		. "${TEST_ROOT}/transaction-functions"
		BASE_DIR="${TEST_ROOT}/transaction-${stage_case}"
		# nvram_transaction_lock_acquire injects lock contention while the real snapshot-begin helper runs.
		nvram_transaction_lock_acquire() { [ "${stage_case}" != lock ]; }
		# nvram_transaction_lock_release isolates transaction-begin failures from lock-release behavior.
		nvram_transaction_lock_release() { return 0; }
		# nvram_transaction_finalize_setup_pair models a clean prior recovery state before snapshot capture.
		nvram_transaction_finalize_setup_pair() { return 0; }
		# nvram injects inventory or key-read failure while the real snapshot helper runs.
		# installer_nvram forwards calls to this fixture's NVRAM model.
		installer_nvram() { nvram "$@"; }
		nvram() {
			if [ "$1" = show ]; then
				[ "${stage_case}" != inventory ] || return 1
				printf '%s\n' jffs2_scripts=0
				return 0
			fi
			return 1
		}
		if [ "${stage_case}" = storage ]; then
			: >"${BASE_DIR}" || exit 1
		fi
		if nvram_transaction_begin jffs-enable jffs2_scripts; then exit 1; fi
		case "${stage_case}:${NVRAM_TRANSACTION_BEGIN_STAGE:-}" in
			lock:lock | storage:snapshot-storage | inventory:snapshot-inventory | key:snapshot-key:jffs2_scripts) ;;
			*) exit 1 ;;
		esac
	) >"${TEST_ROOT}/transaction-${stage_case}.out" 2>&1 || fail "real ${stage_case} transaction failure was misreported"
done

printf '%s\n' 'PASS: JFFS readiness handles large inventories, legacy flags and failed stages'
