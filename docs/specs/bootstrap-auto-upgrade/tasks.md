# Task Plan

- **Spec**: docs/specs/bootstrap-auto-upgrade/spec.md
- **Status**: Active
- **Updated**: 2026-05-09

## Tasks

- [x] T01: Triage GitHub issues #4 and #5.
  - Scope: Determine whether the issues describe real project-bootstrap gaps.
  - Validation: Open issue bodies reviewed with `gh issue list`.
  - Notes: Both issues are necessary and complementary; #4 is script behavior, #5 is workflow guidance.

- [x] T02: Implement bootstrap auto-upgrade.
  - Scope: `skills/project-bootstrap/scripts/bootstrap_project.ps1`.
  - Validation: Targeted temporary-project smoke passed; release validator coverage added.
  - Notes: `-AutoUpgrade` is mutually exclusive with manual memory upgrade modes and `-SkipMemoryUpgradeAnalysis`.

- [x] T03: Document memory upgrade decision workflow.
  - Scope: `skills/project-bootstrap/SKILL.md` and README.
  - Validation: Diff review.
  - Notes: Added Step 2.5 decision rules for auto-upgrade, ask-first, and skip cases.

- [ ] T04: Validate, commit, push, and merge.
  - Scope: Local validation, GitHub PR, CI, merge, issue closure.
  - Validation: Windows PowerShell release validator passed with `PASS=31 FAIL=0 WARN=0 DEFERRED=0`; PR/merge pending.
  - Notes: `knowledge-hub/knowledge/experience/index.json` has a pre-existing unrelated timestamp diff and remains unstaged.

## Task-to-Spec Notes

- T02 maps to issue #4.
- T03 maps to issue #5.
- T04 completes the user-requested review, merge, and close workflow.

## Execution Contract Tasks

- [x] P01: Complete phase 1 and record validation.
  - Goal: Establish public work package and branch state.
  - Inputs: Current public repo and open GitHub issues.
  - Outputs: Spec, tasks, and branch.
  - Validation: Context gate completed; issues reviewed; branch created.
  - Continue / stop decision: Continue.

- [x] P02: Complete phase 2 and record validation.
  - Goal: Script and workflow implementation.
  - Inputs: Existing bootstrap and memory upgrade scripts.
  - Outputs: `-AutoUpgrade` script behavior, skill workflow docs, and README note.
  - Validation: PowerShell parser checks passed for `bootstrap_project.ps1` and `validate-release.ps1`; targeted smoke passed.
  - Continue / stop decision: Continue.

- [x] P03: Complete phase 3 and record validation.
  - Goal: Local validation.
  - Inputs: Implementation diff.
  - Outputs: Release validator coverage for manual and auto memory upgrade flows.
  - Validation: `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-release.ps1 -ScratchRoot <temp>` passed with `PASS=31 FAIL=0 WARN=0 DEFERRED=0`; `git diff --check` passed.
  - Continue / stop decision: Continue to GitHub PR flow.

- [ ] P04: Complete phase 4 and record validation.
  - Goal: GitHub PR flow and issue closure.
  - Inputs: Pushed branch and passing checks.
  - Outputs:
  - Validation:
  - Continue / stop decision:
