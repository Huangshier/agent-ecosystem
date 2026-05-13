# Task Plan

- **Spec**: `docs/specs/file-based-memory-templates/spec.md`
- **Status**: Active
- **Updated**: 2026-05-13

> Historical note: this task plan predates the `v0.4.2` language-scoped
> template model. References to `skills/project-bootstrap/templates/project-memory/`
> are legacy history, not current public template guidance.

## Tasks

- [x] T01: Sync main and confirm issue dependency state
  - Scope: PR #40 merge commit, issue #33, issue #32, issue #30.
  - Validation: `origin/main` and local `main` at `19656e5f92264a960c8e6ac6039debd97166c10f`; #33 closed as completed; #32/#30 re-read.
  - Notes: #30 conservative migration apply remains out of scope.

- [x] T02: Create #32 work package
  - Scope: `docs/specs/file-based-memory-templates/spec.md` and `tasks.md`.
  - Validation: Active spec and task list exist.
  - Notes: This task records the scope boundary before implementation.

- [x] T03: Add file-based memory template tree
  - Scope: `skills/project-bootstrap/templates/project-memory/en/**` and `zh-CN/**`.
  - Validation: Release validation `file-based memory template sources` passed.
  - Notes: Keep English as public default and fallback.

- [x] T04: Update language setup logic
  - Scope: `skills/project-bootstrap/scripts/set_project_language.ps1` and callers as needed.
  - Validation: `set_project_language.ps1` parse check passed; `en` and `zh-CN` bootstrap fixtures passed; missing `zh-CN` template fallback fixture passed.
  - Notes: Do not implement #30 migration apply.

- [x] T05: Update docs and release validation
  - Scope: project-bootstrap docs and `scripts/validate-release.ps1`.
  - Validation: Release validation covers `en`, `zh-CN`, file template source presence, and missing `zh-CN` template fallback.
  - Notes: Document that this is not arbitrary-language i18n.

- [ ] T06: Final validation and PR publication
  - Scope: diff review, required validation commands, commit, push, draft PR.
  - Validation: `git diff --check` passed; `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1` passed with `PASS=37 FAIL=0 WARN=0 DEFERRED=0`; draft PR pending.
  - Notes: PR body must include `Fixes #32`, `Depends on #33`, #30 out-of-scope, and no arbitrary-language i18n.

## Task-to-Spec Notes
- Templates are structural baselines and defaults, not authorization to overwrite customized project memory.
- `en` and `zh-CN` are the only first-class project-memory template languages in this PR.
- Future conservative migration can reuse template structure, but applying migration belongs to #30.

## Execution Contract Tasks

- [x] P01: Complete phase 1 and record validation
  - Goal: Establish clean base and dependency state.
  - Inputs: PR #40, issues #33/#32/#30, local checkout.
  - Outputs: Branch `issue-32-file-based-memory-templates`, active spec/tasks.
  - Validation: Local `main` fast-forwarded to #40 merge commit.
  - Continue / stop decision: Continue to implementation.

- [x] P02: Complete phase 2 and record validation
  - Goal: Add file templates and code loader.
  - Inputs: Existing embedded language scaffolds and hub template layout.
  - Outputs: Template tree and file-loading language setup.
  - Validation: Focused `en`, `zh-CN`, and missing-template fallback checks passed.
  - Continue / stop decision: Continue to docs and release validation.

- [x] P03: Complete phase 3 and record validation
  - Goal: Document and release-validate supported behavior.
  - Inputs: Updated implementation.
  - Outputs: Docs and release validator updates.
  - Validation: `git diff --check` passed; release validation `PASS=37 FAIL=0 WARN=0 DEFERRED=0`.
  - Continue / stop decision: Continue to PR publication.

- [ ] P04: Complete phase 4 and record validation
  - Goal: Publish draft PR for maintainer review.
  - Inputs: Validated branch.
  - Outputs: Commit, pushed branch, draft PR.
  - Validation: Local validation passed; PR creation pending.
  - Continue / stop decision: Stop after PR creation for maintainer review.
