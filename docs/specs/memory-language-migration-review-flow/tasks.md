# Task Plan

- **Spec**: `docs/specs/memory-language-migration-review-flow/spec.md`
- **Status**: Active
- **Updated**: 2026-05-22

## Tasks

- [x] T01: Confirm context and prerequisites
  - Scope: Public repo root, branch/status, latest `main`, root AGENTS
    guidance, private report, #67 merge status, and #79 issue context.
  - Validation: `main` fast-forwarded to `origin/main`; #67 is closed by PR
    #84; #79 remains open after #79-A PR #85.
  - Notes: Public writes are scoped to #79-B only.

- [x] T02: Patch migration validation semantics
  - Scope: `skills/project-bootstrap/scripts/language_migration.ps1` and any
    wrapper docs needed to expose the behavior.
  - Validation: Targeted smoke and release validation prove reviewed narrative
    passes and leftover source-language body text fails audit validation.
  - Notes: Keep backup/proposal/hash safety and protected literal preservation.

- [x] T03: Extend release validation and docs
  - Scope: `scripts/validate-release.ps1`, `skills/project-bootstrap/README.md`,
    `skills/project-bootstrap/SKILL.md`, and relevant public language docs.
  - Validation: Full release validator passed with
    `PASS=50 FAIL=0 WARN=0 DEFERRED=0`.
  - Notes: Manual review should be framed as exception routing.

- [ ] T04: Publish PR and wait for checks
  - Scope: Commit, push branch, open PR for #79-B, monitor hosted checks.
  - Validation: GitHub checks pass before merge recommendation.
  - Notes: Do not merge PR or push `main`.

## Task-to-Spec Notes
- This work follows #67 and #79-A and may close #79 only if the PR body and
  final scope cover the remaining workflow/validation acceptance criteria.

## Conditional Loop Tasks
- Not applicable.

## Execution Contract Tasks

- [x] P01: Complete phase 1 and record validation
  - Goal: Establish latest-public-main context and active work package.
  - Inputs: Root AGENTS, #67/#79 issue metadata, private audit report, existing
    specs.
  - Outputs: New branch and this work package.
  - Validation: Root/branch/status confirmed; #67 closure confirmed.
  - Continue / stop decision: Continue.

- [x] P02: Complete phase 2 and record validation
  - Goal: Implement workflow/validation/docs changes.
  - Inputs: `language_migration.ps1`, audit helper, release validator fixtures.
  - Outputs: Patched scripts/docs.
  - Validation: `git diff --check` passed; full release validation passed with
    `PASS=50 FAIL=0 WARN=0 DEFERRED=0`.
  - Continue / stop decision: Continue to publish.

- [ ] P03: Complete phase 3 and record validation
  - Goal: Validate locally and publish PR.
  - Inputs: Final diff and validation evidence.
  - Outputs: Commit, pushed branch, PR, hosted check evidence.
  - Validation: Local release validation and hosted checks pass.
  - Continue / stop decision: Stop before merge and recommend.
