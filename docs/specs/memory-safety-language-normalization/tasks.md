# Task Plan

- **Spec**: `docs/specs/memory-safety-language-normalization/spec.md`
- **Status**: Active
- **Updated**: 2026-05-12

## Tasks

- [x] T01: Read issues #29 and #31
  - Scope: issue bodies, current project-bootstrap scripts, release validator.
  - Validation: Acceptance criteria mapped into the active spec.
  - Notes: #29 and #31 are related safety bugs and should be fixed together.

- [x] T02: Create memory-safety work package
  - Scope: `docs/specs/memory-safety-language-normalization/`.
  - Validation: Spec and tasks describe goals, non-goals, acceptance, and
    execution contract.
  - Notes: #30-#33 are explicitly out of scope except where needed for warning
    clarity.

- [x] T03: Implement bootstrap overwrite safety
  - Scope: `skills/project-bootstrap/scripts/bootstrap_project.ps1`.
  - Validation: Customized project memory is preserved during refresh and any
    replacement has a backup.
  - Notes: Existing modified memory should be reported for manual review.

- [x] T04: Implement language-aware memory upgrade normalization
  - Scope: `skills/project-bootstrap/scripts/memory_upgrade.ps1`.
  - Validation: `project_language` controls normalized headings/defaults for
    `en` and `zh-CN`; unsupported metadata falls back with an explicit signal.
  - Notes: JSON mode must stay parseable.

- [x] T05: Add release validation fixtures
  - Scope: `scripts/validate-release.ps1`.
  - Validation: Fixtures cover #29 preservation, #31 zh-CN normalization, and
    unsupported language fallback.
  - Notes: Assertions should check stable headings, preserved sentinels, backup
    existence, and spec reference preservation.

- [ ] T06: Validate, publish PR, and wait for checks
  - Scope: branch `issue-29-31-memory-safety`.
  - Validation:
    - `git diff --check` passes.
    - Local release validation passes.
    - Hosted release validation checks pass on the PR.
  - Notes: Full validation is required because this touches bootstrap scripts,
    release validation, specs, and tracked public `.agents` memory. Local
    release validation passed: `PASS=34 FAIL=0 WARN=0 DEFERRED=0`. PR #35
    opened as a draft by `app/agent-ecosystem-bot`.

## Task-to-Spec Notes

- #30 conservative bilingual migration remains a follow-up.
- #32 template externalization remains a follow-up.
- #33 CLI design hardening remains a follow-up.

## Execution Contract Tasks

- [x] P01: Create work package and point public memory at #29/#31
  - Goal: Make the active safety fix durable and reviewable.
  - Inputs: #29 and #31 issue bodies, current scripts, validator.
  - Outputs: spec/tasks files and refreshed public memory.
  - Validation: Files added under
    `docs/specs/memory-safety-language-normalization/`.
  - Continue / stop decision: Continue to implementation.

- [x] P02: Implement bootstrap overwrite safety
  - Goal: Prevent silent overwrite of customized memory.
  - Inputs: bootstrap script and #29 acceptance criteria.
  - Outputs: safer copy/language-refresh behavior.
  - Validation: Targeted fixture passes.
  - Continue / stop decision: Continue to P03.

- [x] P03: Implement language-aware memory upgrade normalization
  - Goal: Respect project language during normalized memory apply.
  - Inputs: lock file metadata and current memory upgrade script.
  - Outputs: localized normalized text and fallback reporting.
  - Validation: Targeted fixture passes.
  - Continue / stop decision: Continue to P04.

- [x] P04: Add release validation fixtures
  - Goal: Keep the regressions covered in the release gate.
  - Inputs: implemented scripts.
  - Outputs: validator assertions for #29/#31.
  - Validation: `scripts/validate-release.ps1` passed:
    `PASS=34 FAIL=0 WARN=0 DEFERRED=0`.
  - Continue / stop decision: Continue to P05.

- [x] P05: Validate locally, commit, push, and open PR
  - Goal: Produce a reviewable PR for #29 and #31.
  - Inputs: completed implementation and validator updates.
  - Outputs:
    - Commit `cfb8869 fix project memory safety bugs`.
    - Remote branch `issue-29-31-memory-safety`.
    - Draft PR #35 `fix: protect project memory upgrades` by
      `app/agent-ecosystem-bot`.
  - Validation:
    - `git diff --check` passed.
    - Local release validation passed: `PASS=34 FAIL=0 WARN=0 DEFERRED=0`.
  - Continue / stop decision: Continue to hosted checks and maintainer review.

- [ ] P06: Wait for hosted checks and maintainer review
  - Goal: Ensure external checks pass before maintainer merge decision.
  - Inputs: opened PR.
  - Outputs: hosted check summary.
  - Validation: Required hosted release validation checks pass.
  - Continue / stop decision:
