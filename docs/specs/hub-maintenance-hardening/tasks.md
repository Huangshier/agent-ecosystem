# Task Plan

- **Spec**: docs/specs/hub-maintenance-hardening/spec.md
- **Status**: Done
- **Updated**: 2026-05-09

## Tasks

- [x] T01: Create and audit GitHub issues #7 and #8.
  - Scope: Issue triage and necessity review.
  - Validation: Issues are open and project-relevant.
  - Notes: Both require fixes.

- [x] T02: Make hub Git initialization explicit.
  - Scope: `init_hub.ps1`, docs, and release validation.
  - Validation: Targeted smoke and release validator coverage passed.
  - Notes: `-InitializeGit` was added; `-CommitInitial` still initializes Git when an initial commit is requested.

- [x] T03: Make experience registry rebuild idempotent.
  - Scope: Rebuild helpers, compatibility copies, and release validation.
  - Validation: Targeted no-op hash smoke and release validator coverage passed.
  - Notes: No-op rebuilds preserve existing registry bytes; promotion helpers received the same guard for consistency.

- [x] T04: Merge PR and confirm issues close.
  - Scope: GitHub PR flow.
  - Validation: Hosted release validation passed for Windows PowerShell 5.1, Windows pwsh, Ubuntu pwsh, and macOS pwsh.
  - Notes: PR #9 merged on 2026-05-09 and closed issues #7 and #8.

## Task-to-Spec Notes

- T02 maps to issue #7.
- T03 maps to issue #8.

## Execution Contract Tasks

- [x] P01: Complete phase 1 and record validation.
  - Goal: Create issues and decide whether they are necessary.
  - Inputs: Session review findings.
  - Outputs: Issues #7 and #8.
  - Validation: Issue bodies reviewed after creation.
  - Continue / stop decision: Continue.

- [x] P02: Complete phase 2 and record validation.
  - Goal: Script and validation changes.
  - Inputs: Current hub maintenance scripts.
  - Outputs: Explicit hub Git initialization, idempotent registry saves, docs, and validator coverage.
  - Validation: PowerShell parser checks passed; targeted smoke passed.
  - Continue / stop decision: Continue.

- [x] P03: Complete phase 3 and record validation.
  - Goal: Local validation.
  - Inputs: Implementation diff.
  - Outputs: Passing local release validation.
  - Validation: `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-release.ps1 -ScratchRoot <temp>` passed with `PASS=32 FAIL=0 WARN=0 DEFERRED=0`.
  - Continue / stop decision: Continue to GitHub PR flow.

- [x] P04: Complete phase 4 and record validation.
  - Goal: GitHub PR flow.
  - Inputs: Pushed branch and passing checks.
  - Outputs: PR #9 merged; issues #7 and #8 closed.
  - Validation: GitHub Actions release validation passed for all four jobs; issue closure confirmed after merge.
  - Continue / stop decision: Done.
