#!/bin/sh
# Regression coverage for the final merge-readiness analysis and checksum contracts.

set -u

fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

WORKFLOW='.github/workflows/code-quality.yml'
CACHE_WORKFLOW='.github/workflows/cache-adguardhome-static.yml'
SONAR_REWRITE='.github/scripts/fix-sonar-shell-parse.py'
SEMGREP='.semgrep.yml'
SONAR='sonar-project.properties'
STATIC_DOWNLOADER='tools/download-adguardhome-static.sh'

for file in "${WORKFLOW}" "${CACHE_WORKFLOW}" "${SONAR_REWRITE}" "${SEMGREP}" "${SONAR}" "${STATIC_DOWNLOADER}"; do
	[ -f "${file}" ] || fail "expected merge-readiness config not found: ${file}"
done

# The Sonar rewrite must be safe to run repeatedly and its publisher must keep
# the checksum-covered script and both sidecars in one commit.
grep -Fq 'old_count == 1 and new_count == 0' "${SONAR_REWRITE}" ||
	fail 'Sonar parser rewrite no longer validates the pre-rewrite state'
grep -Fq 'old_count == 0 and new_count == 1' "${SONAR_REWRITE}" ||
	fail 'Sonar parser rewrite no longer accepts the already-applied state'
grep -Fq 'sh tools/update-checksums.sh AdGuardHome.sh' "${WORKFLOW}" ||
	fail 'Sonar parser workflow does not regenerate AdGuardHome.sh checksums'
grep -Fq 'git add -- AdGuardHome.sh AdGuardHome.sh.md5sum AdGuardHome.sh.sha256sum' "${WORKFLOW}" ||
	fail 'Sonar parser workflow does not stage both checksum sidecars atomically'
grep -Fq 'git diff --cached --quiet' "${WORKFLOW}" ||
	fail 'Sonar parser workflow does not handle an already-current rewrite as a no-op'

# Static archive publication already creates both checksum sidecars itself; the
# cache workflow stages the complete architecture directories so those sidecars
# are committed with every changed archive.
grep -Fq '_md5_file="${_archive_file}.md5sum"' "${STATIC_DOWNLOADER}" ||
	fail 'static archive publisher no longer derives the MD5 sidecar from the archive path'
grep -Fq '_sha256_file="${_archive_file}.sha256sum"' "${STATIC_DOWNLOADER}" ||
	fail 'static archive publisher no longer derives the SHA-256 sidecar from the archive path'
grep -Fq 'git add -- armv8 armv7 armv5' "${CACHE_WORKFLOW}" ||
	fail 'static archive workflow no longer stages complete architecture directories'

# Security policy must catch direct insecure downloader options even when the
# executable is invoked through an absolute trusted router path.
grep -Fq '(?:/[^ \t\n]*/)?curl' "${SEMGREP}" ||
	fail 'Semgrep curl policy no longer covers absolute executable paths'
grep -Fq '(?:/[^ \t\n]*/)?wget' "${SEMGREP}" ||
	fail 'Semgrep wget policy no longer covers absolute executable paths'

# Sonar must assign all three extensionless production entrypoints to Shell.
grep -Fqx 'sonar.lang.patterns.shell=**/*.sh,installer,S99AdGuardHome,rc.func.AdGuardHome' "${SONAR}" ||
	fail 'Sonar Shell language patterns no longer include every extensionless runtime entrypoint'

printf '%s\n' 'PASS: merge-readiness analysis, checksum, Semgrep, and Sonar contracts are covered'
