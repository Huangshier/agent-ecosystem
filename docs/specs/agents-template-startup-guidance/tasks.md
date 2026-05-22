# Task Plan

- **Spec**: `docs/specs/agents-template-startup-guidance/spec.md`
- **Status**: Done
- **Updated**: 2026-05-22

## Tasks

- [x] T01: Inventory template mirrors and validation surfaces
  - Scope: Confirm all project-bootstrap base templates, knowledge-hub mirrors, commands README files, and release validation scripts that must change for #44.
  - Validation: List affected paths in the implementation review before editing.
  - Notes: Keep issue #30 and repository settings out of scope.

- [x] T02: Patch root startup read order guidance
  - Scope: Update en and zh-CN root AGENTS templates and necessary mirrors so `.agents/context/` is discovered progressively through README/index and matching entries.
  - Validation: Diff confirms no wording implies loading the whole cold context tree at startup.
  - Notes: Root files should stay short and cross-agent compatible.

- [x] T03: Patch project-agent and commands guidance
  - Scope: Add Project Commands guidance, connect `.agents/AGENTS.md` to `.agents/commands/README.md`, add PR-ready memory sync/no post-PR memory-only commit guidance, and add large issue implementation-plan/PR-split guidance.
  - Validation: Equivalent en/zh-CN and mirror changes exist.
  - Notes: Make targeted additions rather than rewriting the whole guide.

- [x] T04: Add release validation coverage
  - Scope: Extend validation to assert the new template guidance markers and mirrored copies.
  - Validation: The validation script fails if key guidance is removed from the relevant templates.
  - Notes: Avoid brittle exact-prose assertions where marker coverage is enough.

## Task-to-Spec Notes
- This work implements accepted issue #44 only.
- PR creation must happen after public engineering memory sync.
- After PR creation, do not add memory-only commits just to refresh state or hosted-check timestamps unless explicitly approved.

## Execution Contract Tasks

- [x] P01: Complete phase 1 and record validation
  - Goal: Work package and inventory complete.
  - Inputs: Issue #44, project context, current templates, validation scripts.
  - Outputs: Active spec/tasks and inventory notes.
  - Validation: Existing files inspected and task list updated.
  - Continue / stop decision: Continue. Inventory confirmed project-memory en/zh-CN templates, knowledge-hub mirrors, asset mirrors, `.agents` command guidance, and `scripts/validate-release.ps1`.

- [x] P02: Complete phase 2 and record validation
  - Goal: Template and mirrored documentation changes complete.
  - Inputs: Inventory and accepted issue scope.
  - Outputs: Patched root/project-agent/commands template files.
  - Validation: Local diff review.
  - Continue / stop decision: Continue. Targeted template changes stayed within #44 scope and did not add tool-specific instruction files.

- [x] P03: Complete phase 3 and record validation
  - Goal: Validation coverage and local checks complete.
  - Inputs: Patched templates and validation scripts.
  - Outputs: Updated validation plus command results.
  - Validation: `git diff --check` and release validation.
  - Continue / stop decision: Continue. `git diff --check` passed, and `scripts/validate-release.ps1` passed with `PASS=39 FAIL=0 WARN=0 DEFERRED=0`.

- [x] P04: Complete phase 4 and record validation
  - Goal: PR-ready memory sync, commit, push, and PR handoff.
  - Inputs: Passing validation and clean scoped diff.
  - Outputs: PR #45 merged to `main`.
  - Validation: PR #45 merge commit
    `458e3834abf2648e907ce20a3c48e9d4fb5a6b9c`; issue #44 is closed.
  - Continue / stop decision: Complete.
