# Sonar Shell Analysis Guardrails

These rules govern how Sonar Shell analysis is interpreted in this repository. They supplement `AGENTS.md` and `REVIEW.md` and apply to automated coding and review agents, including Codex, Amazon Q Developer, CodeRabbit, and Qodo.

## Runtime authority

The router runtime target is POSIX `/bin/sh` under BusyBox `ash` v1.25.1 on Asuswrt-Merlin. Sonar is an additional analyzer; it is not the shell grammar authority.

For router-runtime shell, compatibility evidence should be evaluated using the target runtime and repository checks:

1. BusyBox `ash` syntax and behavior on the supported target when available.
2. POSIX `sh -n` and the repository shell-portability checks.
3. ShellCheck with the POSIX `sh` dialect and the nearest targeted regression.
4. Sonar Shell analysis as additional corroborating evidence.

A Sonar parser diagnostic alone does not prove a defect. A construct that fails the actual BusyBox/POSIX contract remains a defect even if Sonar accepts it.

## Parser findings

- Investigate every new Sonar parser diagnostic against the current code and target-shell evidence.
- Do not replace valid POSIX/BusyBox `ash` code with Bash-only, GNU-only, or behavior-changing code solely to satisfy Sonar.
- If Sonar cannot parse a valid target construct, keep the runtime code unless an equally clear target-compatible form removes the warning without changing behavior or portability.
- Do not hide parser limitations by broadly excluding runtime files. Sonar parser grammar cannot be extended from `sonar-project.properties`.
- Do not create filename-based parser exemptions. A recurring analyzer limitation should be documented with the exact construct and independent compatibility evidence, or reported upstream to Sonar.

## Scope and suppressions

- Keep `**/*.sh`, `installer`, `S99AdGuardHome`, and `rc.func.AdGuardHome` in Sonar Shell scope. `AdGuardHome.sh` is covered by `**/*.sh`.
- Do not add `installer`, `S99AdGuardHome`, `rc.func.AdGuardHome`, `AdGuardHome.sh`, or a blanket `*.sh` pattern to `sonar.exclusions`.
- Do not use blanket `shell:*` or `shelldre:*` issue suppressions.
- Rule suppressions must identify an exact rule, use the smallest practical path, include a rationale in `sonar-project.properties`, and retain independent validation when behavior-sensitive.
- Test-only maintainability suppressions may remain scoped to `tests/**`; security and reliability rules remain active unless separately justified.

## Review rule

Automated reviewers must treat Sonar parser output as a signal to verify, not as authority to rewrite router code. A Sonar-only parser complaint is not actionable until it is checked against BusyBox/POSIX compatibility and the relevant repository validation. Conversely, confirmed target-shell incompatibility remains actionable even when Sonar does not report it.

## CI contract

`tools/check-sonar-shell-contract.sh` enforces the repository-controlled parts of this policy:

- required Sonar Shell file scope;
- no broad runtime-shell exclusions;
- no blanket Shell rule suppression;
- continued alignment with the canonical BusyBox `ash` target documented in `AGENTS.md`, `.amazonq/rules/AGENTS.md`, and `REVIEW.md`.

New Sonar parser diagnostics still require investigation. CI does not silently allowlist parser errors.
