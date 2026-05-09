# Task Plan

- **Spec**: `docs/specs/v0-3-1-stabilization/spec.md`
- **Status**: Active
- **Updated**: 2026-05-09

## Tasks

- [x] T01: Resolve #11 release validation metadata consistency.
  - Scope: `docs/releases/v0.3.0.md`, validator release-note coverage, public
    memory pointers.
  - Validation: PR #14 merged; issue #11 closed; hosted release validation
    passed on Windows PowerShell 5.1, Windows pwsh, Ubuntu pwsh, and macOS pwsh.
  - Notes: Expected current summary is `PASS=32 FAIL=0 WARN=0 DEFERRED=0`.

- [x] T02: Resolve #10 README positioning and extension story.
  - Scope: `README.md`, `README.zh-CN.md`, and docs links as needed.
  - Validation: PR #15 merged; issue #10 closed; hosted release validation
    passed on Windows PowerShell 5.1, Windows pwsh, Ubuntu pwsh, and macOS pwsh.
  - Notes: Lead with workflow kernel positioning and extension model.

- [x] T03: Resolve #12 lightweight public reader review.
  - Scope: `docs/release-process.md`, `CONTRIBUTING.md`, or a maintainer guide.
  - Validation: PR #15 merged; issue #12 closed; hosted release validation
    passed on Windows PowerShell 5.1, Windows pwsh, Ubuntu pwsh, and macOS pwsh.
  - Notes: Keep process lightweight.

- [ ] T04: Resolve #13 GitHub Actions runtime maintenance.
  - Scope: `.github/workflows/release-validation.yml`.
  - Validation: Local release validation and hosted CI pass; PR closes #13.
  - Notes: Use official action version/runtime information.

- [ ] T05: Prepare release confirmation handoff.
  - Scope: Public and private state records.
  - Validation: All stabilization issues closed and CI green.
  - Notes: Stop before tag/release publication.

## Task-to-Spec Notes

- T02 and T03 may ship together because positioning and public reader review
  reinforce the same adoption-surface correction.
- Release publication is out of scope until maintainer confirmation.

## Conditional Loop Tasks

Not applicable.

## Execution Contract Tasks

- [ ] P01: Complete phase 1 and record validation
  - Goal: Resolve #11.
  - Inputs: Current validator output and release docs.
  - Outputs: Merged PR and closed issue #11.
  - Validation: Local and hosted release validation.
  - Continue / stop decision:

- [x] P02: Complete phase 2 and record validation
  - Goal: Resolve #10 and #12.
  - Inputs: Positioning issue and process issue.
  - Outputs: PR #15 merged; issues #10/#12 closed.
  - Validation: Local and hosted release validation passed.
  - Continue / stop decision: Continue to P03.

- [ ] P03: Complete phase 3 and record validation
  - Goal: Resolve #13.
  - Inputs: Official action version/runtime information.
  - Outputs: Merged PR and closed issue #13.
  - Validation: Local and hosted release validation.
  - Continue / stop decision:

- [ ] P04: Complete phase 4 and record validation
  - Goal: Stop at release preparation.
  - Inputs: Merged stabilization PRs and CI evidence.
  - Outputs: Updated state records and release confirmation request.
  - Validation: Final status checks.
  - Continue / stop decision: Stop for maintainer release approval.
