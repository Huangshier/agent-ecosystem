# Task Plan

- **Spec**: `docs/specs/zh-cn-spec-validator-contract/spec.md`
- **Status**: Done
- **Updated**: 2026-05-27

## Tasks

- [x] T01: Confirm issue and repository scope
  - Scope: Issue #94, local `main`, open PR state, validator, release fixture, and zh-CN templates.
  - Validation: `gh issue view 94`, `gh pr list`, `git status -sb`, and template inspection.
  - Notes: Scope excludes #96 modularization and unrelated memory template changes.

- [x] T02: Update validator bilingual anchor matching
  - Scope: `skills/workflow-spec-lite/scripts/validate_spec.ps1`.
  - Validation: Focused positive and negative `validate_spec.ps1` fixtures.
  - Notes: Canonical anchors now allow optional localized parenthetical suffixes while keeping the canonical required label mandatory.

- [x] T03: Update release validation fixtures
  - Scope: `scripts/validate-release.ps1` spec-lite validator fixture block.
  - Validation: `scripts/validate-release.ps1` plus focused negative fixture expectations.
  - Notes: The zh-CN positive fixture now uses bilingual anchors; negative fixtures cover missing title and missing autonomy level in addition to required sections.

- [x] T04: Verify template synchronization
  - Scope: zh-CN spec-lite template source and project-bootstrap bundled snapshot.
  - Validation: Hash or content comparison.
  - Notes: The two zh-CN spec-lite template copies match: `SHA256 32BC05E05E1324C4C02E331DC766231208C873E7CD3425A5F9E193CFB5525A19`.

- [x] T05: Finalize PR evidence
  - Scope: Spec/tasks evidence, commit, push, and draft PR body.
  - Validation: `git diff --check`, focused validator checks, release validation, clean staged diff, PR creation.
  - Notes: Draft PR #105 exists and is waiting for maintainer review.

## Task-to-Spec Notes
- T02 and T03 satisfy Goals 1 through 4.
- T04 satisfies template synchronization acceptance.
- T05 satisfies the scoped PR delivery stop point.

## Conditional Loop Tasks
- Not applicable.

## Execution Contract Tasks

- [x] P01: Confirm issue scope and current evidence
  - Goal: Ground the implementation in #94 and current repository state.
  - Inputs: Issue #94, validator source, release fixture block, zh-CN templates.
  - Outputs: Active branch and this work package.
  - Validation: Repository is on a fresh branch from current `origin/main`.
  - Continue / stop decision: Continue.

- [x] P02: Implement validator and fixture updates
  - Goal: Accept bilingual zh-CN anchors without weakening required checks.
  - Inputs: `validate_spec.ps1`, `validate-release.ps1`.
  - Outputs: Scoped code changes.
  - Validation: Focused validator checks passed for English and zh-CN positive fixtures plus missing-title, missing-goals, and missing-autonomy negative fixtures.
  - Continue / stop decision: Continue.

- [x] P03: Run validation and record evidence
  - Goal: Prove the change is safe and release validation still passes.
  - Inputs: Local working tree.
  - Outputs: Validation evidence in this work package and PR body.
  - Validation: `git diff --check`; spec validation for this work package; focused validator checks; release validation `PASS=52 FAIL=0 WARN=0 DEFERRED=0`.
  - Continue / stop decision: Continue to draft PR publication.

- [x] P04: Publish draft PR
  - Goal: Submit a scoped PR for maintainer review.
  - Inputs: Validated local branch.
  - Outputs: Commit `1bfd06f`, pushed branch, draft PR #105.
  - Validation: PR URL exists: <https://github.com/Huangshier/agent-ecosystem/pull/105>.
  - Continue / stop decision: Stop and wait for maintainer review.
