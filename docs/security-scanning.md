# Repository security scans

The Semgrep job runs the pinned Semgrep Community Edition native executable on
Ubuntu x86_64. `requirements-semgrep.txt` inventories the official wheel artifact
and its SHA-256 for both installation and OSV package discovery. It is an artifact
inventory, not a Python-environment lockfile: CI verifies the complete wheel and
copies its `semgrep-core` member as `osemgrep` with the bundled native libraries
required by its `$ORIGIN/libs` runpath. No Python package is installed.

Semgrep's Python frontend currently requires exactly `mcp==1.29.0`, affected by
[GHSA-84m7-p3x7-pcfv](https://github.com/advisories/GHSA-84m7-p3x7-pcfv).
Installing MCP 1.30.0 conflicts with that requirement. Native scanning removes
the unused Python server dependency from the CI installation while retaining
Semgrep's version in OSV's supported requirements format. No ignore or severity
exception is added; full OSV reporting still uses `--fail-on-vuln=true`.

The upstream native CLI needs `--experimental` to select its native path. This
choice is limited to the existing local `.semgrep.yml` policy rules, JSON/SARIF
reporting and finding enforcement. The Python frontend is absent, so unsupported
fallbacks fail instead of introducing an untracked Python dependency. Future
command or rule changes must verify native support before being used in CI.

The change was checked against the original frontend: all three existing fixtures
and 58 injected findings across the 17 policy-scoped paths matched by rule, file
and line. SARIF generation and clean-repository enforcement pass, and positive
findings return exit 1. The workflow retains the fixture checks and now explicitly
tests that enforcement fails on the positive downloader fixture. Preserve these
checks, artifact verification and the existing policy/SARIF job names when updating
the scanner. These are validation-host tools; router runtime dependencies and the
shared repository MCP client catalog are unchanged.
