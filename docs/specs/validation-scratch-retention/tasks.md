# Task Plan

- **Spec**: `docs/specs/validation-scratch-retention/spec.md`
- **Status**: Active
- **Updated**: 2026-05-12

## Tasks

- [x] T01: Create and accept issue #38
  - Scope: GitHub issue metadata and issue-first routing.
  - Validation: #38 exists and was created by `agent-ecosystem-bot[bot]`.
  - Notes: Scope is limited to validation scratch retention pruning.

- [x] T02: Add guarded pruning helper
  - Scope: `scripts/prune-validation-scratch.ps1`.
  - Validation: Helper is dry-run by default and requires `-Apply` for deletion.
  - Notes: The helper only targets direct child directories with
    `validation-result.json`.

- [x] T03: Add validator coverage and docs
  - Scope: `scripts/validate-release.ps1`, `docs/release-process.md`, and
    `docs/release-readiness.md`.
  - Validation: Release validator creates a temporary fixture and checks both
    dry-run and apply behavior.
  - Notes: No hooks, rulesets, or default scratch-root behavior changes.

- [ ] T04: Validate, commit, push, and open PR
  - Scope: branch `issue-38-validation-scratch-retention`.
  - Validation:
    - `git diff --check` passed.
    - Spec validation passed for
      `docs/specs/validation-scratch-retention/spec.md`.
    - Local release validation passed:
      `PASS=35 FAIL=0 WARN=0 DEFERRED=0`.
    - PR references `Fixes #38`.
  - Notes: Commit, push, and PR publication remain pending. Do not merge
    directly.

## Task-to-Spec Notes

- #30 conservative bilingual migration remains out of scope.
- #32 template externalization remains out of scope.
- #33 CLI mode redesign remains out of scope.
- PR #37 is already merged and must not be expanded.

## Execution Contract Tasks

- [x] P01: Create/accept issue #38 and this work package
  - Goal: Make the scratch retention fix durable and bounded.
  - Inputs: read-only scratch inventory, issue-first policy, and public state.
  - Outputs: issue #38 and this spec/tasks pair.
  - Validation: Issue and work package exist.
  - Continue / stop decision: Continue to implementation.

- [x] P02: Implement the guarded pruning helper and validator coverage
  - Goal: Provide a safe minimal cleanup workflow.
  - Inputs: shared path guard helper and release validator.
  - Outputs: pruning helper and validator fixture.
  - Validation: Dry-run/apply behavior is covered by release validation.
  - Continue / stop decision: Continue to docs and memory sync.

- [x] P03: Update public docs and engineering memory
  - Goal: Make the helper discoverable and keep active work state current.
  - Inputs: release process/readiness docs and public hot memory.
  - Outputs: docs and tracked memory updates.
  - Validation: Active spec points at #38.
  - Continue / stop decision: Continue to validation and PR publication.

- [ ] P04: Validate, commit, push, and open a PR for #38
  - Goal: Produce a reviewable PR that fixes #38.
  - Inputs: completed implementation, docs, specs, and memory updates.
  - Outputs: commit, remote branch, and PR.
  - Validation:
    - `git diff --check` passed.
    - Spec validation passed.
    - Local release validation passed: `PASS=35 FAIL=0 WARN=0 DEFERRED=0`.
    - PR body must reference #38.
  - Continue / stop decision: Pending.
