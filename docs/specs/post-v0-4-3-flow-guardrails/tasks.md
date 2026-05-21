# Task Plan

- **Spec**: `docs/specs/post-v0-4-3-flow-guardrails/spec.md`
- **Status**: Done
- **Updated**: 2026-05-21

## Tasks

- [x] T01: Complete P0 closeout through the repository-required PR path
  - Scope: PR #76.
  - Validation: required hosted release validation checks passed before merge;
    main push run `26182173732` passed.
  - Notes: Direct `main` push was blocked by `protect-main`, so the same
    closeout commit landed through PR.

- [x] T02: Implement PR base/stack safety guardrails
  - Scope: PR template, governance docs, and PR base guard workflow.
  - Validation: pending local release validation and hosted PR checks.
  - Notes: Non-`main` PRs require both `stack:allowed` and the explicit stacked
    declaration in the PR body.

- [x] T03: Add CI concurrency and decide whether to split CI
  - Scope: release validation workflow and release-process docs.
  - Validation: pending local release validation and hosted PR checks.
  - Notes: CI is not split in this change; required full release validation
    remains the merge gate.

- [x] T04: Validate and merge the repository-file PR
  - Scope: PR #77.
  - Validation: local release validation passed with
    `PASS=46 FAIL=0 WARN=0 DEFERRED=0`; hosted release validation passed before
    merge.
  - Notes: PR #77 landed the PR base guard and release-validation concurrency
    changes on `main`.

- [x] T05: Re-triage deferred issues
  - Scope: #67, #56, and #23 only.
  - Validation: public issue state readback.
  - Notes: #67 and #56 are accepted. #23 remains deferred for a later
    release-planning pass.

## Task-to-Spec Notes
- P1 and P2 are intentionally grouped because both update PR/CI workflow
  guardrails from the same audit.
- Repository settings changes are out of scope for this branch.
