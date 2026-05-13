# Task Plan

- **Spec**: `docs/specs/conservative-language-migration/spec.md`
- **Status**: Active
- **Updated**: 2026-05-13

## Tasks

- [x] T01: Inspect issue and dependency context
  - Scope: GitHub issues #30, #32, #33, #44; PRs #40, #41, #45; existing
    project-bootstrap scripts and validation coverage.
  - Validation: Confirmed #30 remains open and accepted; dependencies are
    merged into current `main`.
  - Notes: #30 is suitable for one scoped reviewable PR if it avoids
    arbitrary-language i18n and unattended translation claims.

- [x] T02: Implement language migration helper and bootstrap routing
  - Scope: `skills/project-bootstrap/scripts/language_migration.ps1` and
    `bootstrap_project.ps1` CLI routing.
  - Validation: Targeted fixture smoke checks for Analyze, Plan, Apply, and
    Validate modes passed; full release validator passed.
  - Notes: Apply requires a proposal and preexisting backup, and refuses
    changed source hashes.

- [x] T03: Update user-facing docs and skill guidance
  - Scope: `skills/project-bootstrap/README.md`,
    `skills/project-bootstrap/SKILL.md`, language/adoption/release docs as
    needed.
  - Validation: Release validator doc checks passed.
  - Notes: Manual-review boundary is explicit; no arbitrary-language i18n or
    unattended translation claim was added.

- [x] T04: Add release-validation fixture coverage
  - Scope: `scripts/validate-release.ps1`.
  - Validation: `scripts/validate-release.ps1` passed with
    `PASS=40 FAIL=0 WARN=0 DEFERRED=0`.
  - Notes: Fixtures are deterministic and local-only.

- [ ] T05: PR-ready memory sync, validation, commit, push, draft PR
  - Scope: Active spec/tasks plus `.agents/process.txt`, `.agents/plan.md`,
    and stable notes if needed.
  - Validation: `git diff --check` passed; full release validator passed;
    PR #46 blocking-concern fixes revalidated on 2026-05-13 with
    `PASS=40 FAIL=0 WARN=0 DEFERRED=0`.
  - Notes: Draft PR #46 remains the review vehicle; completion scope should
    stay conservative and avoid unattended-translation claims.

## Task-to-Spec Notes
- The first PR is planned as a complete #30 implementation for deterministic
  conservative migration, with explicit manual-review routing for customized
  narrative that cannot be safely translated without human or LLM review.

## Conditional Loop Tasks
- Not applicable.

## Execution Contract Tasks

- [x] P01: Complete phase 1 and record validation
  - Goal: Establish scope, dependencies, and PR split decision.
  - Inputs: Issue and PR metadata, current `main`, project memory, existing
    scripts.
  - Outputs: Active work package and branch.
  - Validation: Context gate completed; GitHub issues and merged PRs inspected.
  - Continue / stop decision: Continue; no scope blocker.

- [x] P02: Complete phase 2 and record validation
  - Goal: Implement migration helper and bootstrap routing.
  - Inputs: File-based templates and existing bootstrap conventions.
  - Outputs: Scripts and targeted smoke evidence.
  - Validation: Local fixture smoke checks and release validation passed.
  - Continue / stop decision: Continue.

- [x] P03: Complete phase 3 and record validation
  - Goal: Update docs and release validation.
  - Inputs: #30 acceptance criteria and release validator style.
  - Outputs: Docs and fixtures.
  - Validation: Full release validator passed with
    `PASS=40 FAIL=0 WARN=0 DEFERRED=0`.
  - Continue / stop decision: Continue.

- [ ] P04: Complete phase 4 and record validation
  - Goal: Produce draft PR and stop for maintainer review.
  - Inputs: Validated diff and public memory sync.
  - Outputs: Commit, pushed branch, draft PR.
  - Validation: `git diff --check` and release validator passed; PR #46 review
    blocking concerns were addressed and revalidated.
  - Continue / stop decision: Stop after draft PR creation.
