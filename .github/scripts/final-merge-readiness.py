#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path.cwd()


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def replace_exact(path: str, old: str, new: str, expected: int = 1) -> None:
    text = read(path)
    count = text.count(old)
    if count != expected:
        raise SystemExit(f"{path}: expected {expected} exact match(es), found {count}")
    write(path, text.replace(old, new))


# 1. Emergency monitor-stop fallback must always restore dnsmasq even when the
# persisted stop configuration is malformed while dnsmasq is intentionally down.
monitor_old = '''\t\t\tif ! load_operation_config stop; then
\t\t\t\tset_operation_config_defaults
\t\t\t\tagh_log warning start_monitor "state=stop action=load_config reason=invalid_snapshot result=using_defaults"
\t\t\tfi
'''
monitor_new = '''\t\t\tif ! load_operation_config stop; then
\t\t\t\tset_operation_config_defaults
\t\t\t\tCONFIG_DNSMASQ_MODE="enabled"
\t\t\t\tagh_log warning start_monitor "state=stop action=load_config reason=invalid_snapshot result=using_defaults"
\t\t\tfi
'''
replace_exact("AdGuardHome.sh", monitor_old, monitor_new, expected=2)

# 2. A restart must not report success by calling start after a failed stop.
restart_old = '''\t\t"restart")
\t\t\t{ check >/dev/null; } && stop
\t\t\tstart
\t\t\t;;
'''
restart_new = '''\t\t"restart")
\t\t\tif check >/dev/null; then
\t\t\t\tstop
\t\t\t\tRESTART_STOP_STATUS="$?"
\t\t\t\t[ "${RESTART_STOP_STATUS}" -eq 0 ] || exit "${RESTART_STOP_STATUS}"
\t\t\tfi
\t\t\tstart
\t\t\t;;
'''
replace_exact("rc.func.AdGuardHome", restart_old, restart_new)

# 3. Permanent regression for malformed monitor stop configuration.
write(
    "tests/monitor-stop-config-fallback.sh",
    r'''#!/bin/sh
# Verify a malformed monitor stop snapshot forces dnsmasq restoration semantics.

set -u

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/AdGuardHome.sh"
TEST_ROOT="${TMPDIR:-/tmp}/agh-monitor-stop-config.$$"
FUNCTIONS_FILE="${TEST_ROOT}/functions.sh"
READY_FILE="${TEST_ROOT}/ready"
MODE_FILE="${TEST_ROOT}/mode"
MONITOR_TEST_PID=""

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

cleanup() {
	if [ -n "${MONITOR_TEST_PID:-}" ] && kill -0 "${MONITOR_TEST_PID}" 2>/dev/null; then
		kill -KILL "${MONITOR_TEST_PID}" 2>/dev/null || true
		wait "${MONITOR_TEST_PID}" 2>/dev/null || true
	fi
	rm -rf "${TEST_ROOT}"
}

wait_for_file() {
	_file="$1"
	_attempts=0
	while [ ! -f "${_file}" ] && [ "${_attempts}" -lt 10 ]; do
		command sleep 1
		_attempts="$((_attempts + 1))"
	done
	[ -f "${_file}" ]
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
umask 077
mkdir "${TEST_ROOT}" || fail 'could not create test workspace'

sed -n '/^set_operation_config_defaults() {$/,/^}$/p; /^start_monitor() {$/,/^}$/p' "${SCRIPT_PATH}" >"${FUNCTIONS_FILE}" ||
	fail 'could not extract monitor configuration helpers'
[ -s "${FUNCTIONS_FILE}" ] || fail 'monitor configuration helper extraction was empty'
[ "$(grep -c 'CONFIG_DNSMASQ_MODE="enabled"' "${FUNCTIONS_FILE}")" -eq 2 ] ||
	fail 'both monitor stop fallback paths must force managed dnsmasq restoration'

# shellcheck disable=SC1090
. "${FUNCTIONS_FILE}"

DEFAULT_ADGUARD_NETCHECK_HOSTS='google.com github.com snbforums.com'
DEFAULT_ADGUARD_NETCHECK_DNS='127.0.0.1'
DEFAULT_ADGUARD_NETCHECK_REQUIRE_HTTP='NO'
DEFAULT_ADGUARD_NETCHECK_TIMEOUT='300'
DEFAULT_ADGUARD_NETCHECK_MODE='wan'
DEFAULT_ADGUARD_PROC_OPTIMIZE='NO'
DEFAULT_ADGUARD_PROC_PROFILE='aggressive'
ADGUARDHOME_BINARY=/bin/sh
PROCS=AdGuardHome

agh_log() {
	[ "${2:-}" != start_monitor ] || : >"${READY_FILE}"
}
service_wait() { return 0; }
check_dns_environment() { :; }
load_operation_config() {
	[ "${1:-}" != stop ] || return 1
	return 0
}
adguardhome_run() {
	case "${1:-}" in
		stop_adguardhome)
			printf '%s\n' "${CONFIG_DNSMASQ_MODE:-unset}" >"${MODE_FILE}"
			;;
	esac
	return 0
}
pidof() {
	[ "${1:-}" = "${PROCS}" ] || return 1
	printf '%s\n' 123
}
timezone() { :; }
adguard_lan_mode() { return 1; }
adguard_refresh_lan_bind_addresses() { return 0; }
netcheck_config() { printf '%s\n' wan; }
sleep() { command sleep 1; }

start_monitor &
MONITOR_TEST_PID="$!"
wait_for_file "${READY_FILE}" || fail 'monitor did not reach its running state'
kill -USR1 "${MONITOR_TEST_PID}" || fail 'could not request monitor stop'
wait_for_file "${MODE_FILE}" || fail 'monitor did not execute its stop path'
wait "${MONITOR_TEST_PID}" || fail 'monitor stop path returned failure'
MONITOR_TEST_PID=""

[ "$(cat "${MODE_FILE}")" = enabled ] ||
	fail 'malformed monitor stop configuration did not force dnsmasq restoration'

printf '%s\n' 'PASS: malformed monitor stop configuration forces dnsmasq restoration'
''',
)

# 4. Permanent regression for failed-stop restart status propagation.
write(
    "tests/rc-restart-stop-failure.sh",
    r'''#!/bin/sh
# Verify restart never calls start after a failed stop and propagates the stop status.

set -u

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
RC_PATH="${ROOT_DIR}/rc.func.AdGuardHome"
TEST_ROOT="${TMPDIR:-/tmp}/rc-restart-stop-failure.$$"
DISPATCHER="${TEST_ROOT}/dispatcher.sh"
EVENTS="${TEST_ROOT}/events"

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

cleanup() {
	rm -rf "${TEST_ROOT}"
}

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
umask 077
mkdir "${TEST_ROOT}" || fail 'could not create test workspace'

sed -n '/^rc_dependencies_available || exit 1$/,/^#logger /p' "${RC_PATH}" | sed '$d' >"${DISPATCHER}" ||
	fail 'could not extract rc action dispatcher'
[ -s "${DISPATCHER}" ] || fail 'rc action dispatcher extraction was empty'

: >"${EVENTS}"
(
	rc_dependencies_available() { return 0; }
	check() { return 0; }
	stop() { printf '%s\n' stop >>"${EVENTS}"; return 255; }
	start() { printf '%s\n' start >>"${EVENTS}"; return 0; }
	reload() { return 0; }
	PROCS=AdGuardHome
	DESC=AdGuardHome
	ACTION=restart
	ansi_white=''
	ansi_std=''
	# shellcheck disable=SC1090
	. "${DISPATCHER}"
)
_status="$?"
[ "${_status}" -eq 255 ] || fail "failed restart returned ${_status}, expected 255"
[ "$(cat "${EVENTS}")" = stop ] || fail 'restart called start after stop failure'

: >"${EVENTS}"
(
	rc_dependencies_available() { return 0; }
	check() { return 0; }
	stop() { printf '%s\n' stop >>"${EVENTS}"; return 0; }
	start() { printf '%s\n' start >>"${EVENTS}"; return 0; }
	reload() { return 0; }
	PROCS=AdGuardHome
	DESC=AdGuardHome
	ACTION=restart
	ansi_white=''
	ansi_std=''
	# shellcheck disable=SC1090
	. "${DISPATCHER}"
) || fail 'successful restart path returned failure'
[ "$(cat "${EVENTS}")" = "$(printf 'stop\nstart')" ] || fail 'successful restart did not stop before start'

: >"${EVENTS}"
(
	rc_dependencies_available() { return 0; }
	check() { return 1; }
	stop() { printf '%s\n' stop >>"${EVENTS}"; return 0; }
	start() { printf '%s\n' start >>"${EVENTS}"; return 0; }
	reload() { return 0; }
	PROCS=AdGuardHome
	DESC=AdGuardHome
	ACTION=restart
	ansi_white=''
	ansi_std=''
	# shellcheck disable=SC1090
	. "${DISPATCHER}"
) || fail 'restart of a stopped service returned failure'
[ "$(cat "${EVENTS}")" = start ] || fail 'restart of a stopped service did not start directly'

printf '%s\n' 'PASS: restart propagates stop failure and never starts over a surviving process'
''',
)

# 5. Register both regressions in the canonical quality runner.
quality_anchor = "run_check 'AdGuardHome process signaling regression' sh tests/rc-process-signaling.sh\n"
quality_insert = quality_anchor + "run_check 'AdGuardHome restart stop-failure propagation regression' sh tests/rc-restart-stop-failure.sh\nrun_check 'AdGuardHome monitor stop config fallback regression' sh tests/monitor-stop-config-fallback.sh\n"
replace_exact("tools/code-quality.sh", quality_anchor, quality_insert)

# 6. Execute the two lifecycle regressions under BusyBox ash in the dedicated gate.
shell_anchor = '''      - name: Run process signaling regression with BusyBox ash
        run: /usr/bin/timeout --kill-after=10 180 busybox ash tests/rc-process-signaling.sh

'''
shell_insert = shell_anchor + '''      - name: Run restart stop-failure propagation regression
        run: /usr/bin/timeout --kill-after=10 180 busybox ash tests/rc-restart-stop-failure.sh

      - name: Run monitor stop config fallback regression
        run: /usr/bin/timeout --kill-after=10 180 busybox ash tests/monitor-stop-config-fallback.sh

'''
replace_exact(".github/workflows/shell-validation.yml", shell_anchor, shell_insert)

# 7. Replace the reusable OSV calls with the same pinned scanner/reporter
# actions plus an explicit SARIF uploader. This preserves vulnerability gating
# and Code Scanning while making the required security-events write visible to
# Scorecard's recognized uploader exception.
write(
    ".github/workflows/osv-scanner.yml",
    '''name: OSV Dependency Scan

on:
  pull_request:
    branches: [dev]
  push:
    branches: [dev, master, main]
  schedule:
    - cron: '29 6 * * 1'
  workflow_dispatch:

permissions:
  contents: read

jobs:
  scan-pr:
    name: OSV new-vulnerability scan
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    timeout-minutes: 20
    permissions:
      actions: read
      contents: read
      security-events: write
    steps:
      - name: Check out pull request
        uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09 # v5
        with:
          fetch-depth: 0
          persist-credentials: false

      - name: Check out target branch
        run: git checkout --detach "origin/${GITHUB_BASE_REF}"

      - name: Scan existing code
        uses: google/osv-scanner-action/osv-scanner-action@8dc09193bb540e09b23da07ad7e30bd33bf87018 # v2.3.8
        continue-on-error: true
        with:
          scan-args: |-
            --format=json
            --output=old-results.json
            -r
            ./

      - name: Check out pull request merge
        run: git checkout -f "${GITHUB_SHA}"

      - name: Scan new code
        uses: google/osv-scanner-action/osv-scanner-action@8dc09193bb540e09b23da07ad7e30bd33bf87018 # v2.3.8
        continue-on-error: true
        with:
          scan-args: |-
            --format=json
            --output=new-results.json
            -r
            ./

      - name: Report newly introduced vulnerabilities
        uses: google/osv-scanner-action/osv-reporter-action@8dc09193bb540e09b23da07ad7e30bd33bf87018 # v2.3.8
        with:
          scan-args: |-
            --output=results.sarif
            --old=old-results.json
            --new=new-results.json
            --gh-annotations=true
            --fail-on-vuln=true

      - name: Upload OSV SARIF artifact
        if: ${{ !cancelled() }}
        uses: actions/upload-artifact@bbbca2ddaa5d8feaa63e36b76fdaad77386f024f # v7.0.0
        with:
          name: OSV Scanner PR SARIF
          path: results.sarif
          retention-days: 5

      - name: Upload OSV results to code scanning
        if: ${{ !cancelled() && github.event.pull_request.head.repo.full_name == github.repository }}
        uses: github/codeql-action/upload-sarif@e4fba868fa4b1b91e1fdab776edc8cfbe6e9fb81 # v4.37.3
        with:
          sarif_file: results.sarif
          category: osv-scanner-pr

  scan-full:
    name: OSV full vulnerability scan
    if: github.event_name != 'pull_request'
    runs-on: ubuntu-latest
    timeout-minutes: 20
    permissions:
      actions: read
      contents: read
      security-events: write
    steps:
      - name: Check out repository
        uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09 # v5
        with:
          persist-credentials: false

      - name: Scan repository
        uses: google/osv-scanner-action/osv-scanner-action@8dc09193bb540e09b23da07ad7e30bd33bf87018 # v2.3.8
        continue-on-error: true
        with:
          scan-args: |-
            --format=json
            --output=results.json
            -r
            ./

      - name: Report vulnerabilities
        uses: google/osv-scanner-action/osv-reporter-action@8dc09193bb540e09b23da07ad7e30bd33bf87018 # v2.3.8
        with:
          scan-args: |-
            --output=results.sarif
            --new=results.json
            --gh-annotations=false
            --fail-on-vuln=true

      - name: Upload OSV SARIF artifact
        if: ${{ !cancelled() }}
        uses: actions/upload-artifact@bbbca2ddaa5d8feaa63e36b76fdaad77386f024f # v7.0.0
        with:
          name: OSV Scanner SARIF
          path: results.sarif
          retention-days: 5

      - name: Upload OSV results to code scanning
        if: ${{ !cancelled() }}
        uses: github/codeql-action/upload-sarif@e4fba868fa4b1b91e1fdab776edc8cfbe6e9fb81 # v4.37.3
        with:
          sarif_file: results.sarif
          category: osv-scanner
''',
)

# 8. Make Sonar a real same-repository merge gate and migrate off the archived
# sonarcloud-specific action to the current pinned unified scanner.
sonar_old = '''  sonarcloud:
    name: SonarCloud Code Analysis
    runs-on: ubuntu-latest
    timeout-minutes: 15
    if: github.event_name == 'workflow_dispatch' || github.event.pull_request.draft == false
    permissions:
      contents: read
    steps:
      - name: Check out pull request merge
        if: github.event_name == 'pull_request'
        uses: actions/checkout@v5
        with:
          ref: refs/pull/${{ github.event.pull_request.number }}/merge
          fetch-depth: 0

      - name: Check out selected ref
        if: github.event_name != 'pull_request'
        uses: actions/checkout@v5
        with:
          fetch-depth: 0

      - name: SonarCloud Scan
        uses: SonarSource/sonarcloud-github-action@master
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
        continue-on-error: true
'''
sonar_new = '''  sonarcloud:
    name: SonarQube Cloud Quality Gate
    runs-on: ubuntu-latest
    timeout-minutes: 15
    if: github.event_name == 'workflow_dispatch' || (github.event.pull_request.draft == false && github.event.pull_request.head.repo.full_name == github.repository)
    permissions:
      contents: read
    steps:
      - name: Check out pull request merge
        if: github.event_name == 'pull_request'
        uses: actions/checkout@v5
        with:
          ref: refs/pull/${{ github.event.pull_request.number }}/merge
          fetch-depth: 0

      - name: Check out selected ref
        if: github.event_name != 'pull_request'
        uses: actions/checkout@v5
        with:
          fetch-depth: 0

      - name: SonarQube Cloud Scan and quality gate
        uses: SonarSource/sonarqube-scan-action@22918119ff8e1ca75a623e15c8296b6ea4fbe28f # v8.2.1
        with:
          args: >-
            -Dsonar.qualitygate.wait=true
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
'''
replace_exact(".github/workflows/code-quality-review.yml", sonar_old, sonar_new)

# 9. Add a pinned/checksummed actionlint gate without duplicating the existing
# ShellCheck pass over embedded workflow shell snippets.
quality_workflow_anchor = '''      - name: Install shell tooling
        run: |
          sudo apt-get update
          sudo apt-get install -y shellcheck shfmt ripgrep dnsmasq

      - name: Run code quality checks
'''
quality_workflow_insert = '''      - name: Install shell tooling
        run: |
          sudo apt-get update
          sudo apt-get install -y shellcheck shfmt ripgrep dnsmasq curl

      - name: Install actionlint
        env:
          ACTIONLINT_VERSION: '1.7.12'
          ACTIONLINT_SHA256: '8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8'
        run: |
          set -eu
          archive="/tmp/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz"
          curl -fsSL "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" -o "${archive}"
          printf '%s  %s\n' "${ACTIONLINT_SHA256}" "${archive}" | sha256sum -c -
          tar -xzf "${archive}" -C /tmp actionlint
          sudo install -m 0755 /tmp/actionlint /usr/local/bin/actionlint

      - name: Lint GitHub Actions workflows
        run: actionlint -shellcheck= -pyflakes=

      - name: Run code quality checks
'''
replace_exact(".github/workflows/code-quality.yml", quality_workflow_anchor, quality_workflow_insert)

# Update companion digests for the two changed distributed runtime artifacts.
for artifact in ("AdGuardHome.sh", "rc.func.AdGuardHome"):
    data = (ROOT / artifact).read_bytes()
    write(f"{artifact}.md5sum", hashlib.md5(data).hexdigest() + "\n")
    write(f"{artifact}.sha256sum", hashlib.sha256(data).hexdigest() + "\n")

# The one-shot staging mechanism must not survive the commit it creates.
for temporary in (
    ".github/scripts/final-merge-readiness.py",
    ".github/workflows/apply-final-merge-readiness.yml",
):
    path = ROOT / temporary
    if path.exists():
        path.unlink()
