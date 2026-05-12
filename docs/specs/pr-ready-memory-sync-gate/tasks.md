# Task Plan

- **Spec**: `docs/specs/pr-ready-memory-sync-gate/spec.md`
- **Status**: Done
- **Updated**: 2026-05-12

## Tasks

- [x] T01: Read and accept issue #36
  - Scope: issue body, labels, current governance docs, and current skill
    guidance.
  - Validation: #36 scope is accepted and labeled `triage:accepted`.
  - Notes: `triage:needs-human` was removed. `review:needs-human` was not added
    because accepted process issue #27 used only `triage:accepted` plus
    `source:agent`, while PR review remains protected by repository controls.

- [x] T02: Close out PR #35 engineering memory
  - Scope: hot memory and
    `docs/specs/memory-safety-language-normalization/`.
  - Validation: #29/#31 and PR #35 no longer appear as active work.
  - Notes: PR #35 merged at
    `89a7bd7e893378c19a6930288bff8c081d1732c1`; issues #29 and #31 are closed
    with `state_reason=completed`.

- [x] T03: Add the memory sync gate
  - Scope: `.agents/AGENTS.md` and
    `skills/workflow-spec-lite/SKILL.md`.
  - Validation: Checklist names required files, boundary timing, intermediate
    commit behavior, and explicit non-goals.
  - Notes: No hooks, rulesets, or hosted-check workflow changes.

- [x] T04: Validate, commit, push, and open PR
  - Scope: branch `issue-36-pr-ready-memory-sync-gate`.
  - Validation:
    - `git diff --check` passed.
    - Local release validation passed: `PASS=34 FAIL=0 WARN=0 DEFERRED=0`.
  - Notes: PR #37 opened as a draft PR by `app/agent-ecosystem-bot`, later
    marked ready and merged.

## Task-to-Spec Notes

- #30 conservative bilingual migration remains out of scope.
- #32 template externalization remains out of scope.
- #33 CLI mode redesign remains out of scope.
- Hosted checks may be recorded once at a PR-ready or phase-close boundary, but
  should not trigger repeated memory-only commits solely to refresh timestamps.

## Execution Contract Tasks

- [x] P01: Accept #36 scope and create this work package
  - Goal: Make the governance follow-up durable and bounded.
  - Inputs: issue #36 body, labels, hot memory, and current guidance files.
  - Outputs: `docs/specs/pr-ready-memory-sync-gate/spec.md` and `tasks.md`.
  - Validation: Work package exists and states goals/non-goals.
  - Continue / stop decision: Continue to implementation.

- [x] P02: Add the PR-ready / phase-close gate to project and skill guidance
  - Goal: Define the required boundary checklist.
  - Inputs: `.agents/AGENTS.md` and `skills/workflow-spec-lite/SKILL.md`.
  - Outputs: Gate text and checklist.
  - Validation: Acceptance criteria are represented in the guidance.
  - Continue / stop decision: Continue to memory synchronization.

- [x] P03: Synchronize public engineering memory and close out PR #35 state
  - Goal: Remove stale #35 active-work state before this PR is published.
  - Inputs: PR #35 merge state, #29/#31 issue state, and public hot memory.
  - Outputs: Updated `.agents` memory and completed memory-safety spec/tasks.
  - Validation: Hot memory points at #36; memory-safety work package is Done.
  - Continue / stop decision: Continue to validation and PR publication.

- [x] P04: Validate, commit, push, and open a PR for #36
  - Goal: Produce a reviewable PR that fixes #36.
  - Inputs: completed docs, skill guidance, specs, and memory updates.
  - Outputs:
    - Commit `f51b77f docs: add PR-ready memory sync gate`.
    - Remote branch `issue-36-pr-ready-memory-sync-gate`.
    - Draft PR #37 `docs: add PR-ready memory sync gate`.
    - Merge commit `b5263c25512880e8f64c52d5a9dcab399de4a529`.
  - Validation:
    - `git diff --check` passed.
    - Local release validation passed: `PASS=34 FAIL=0 WARN=0 DEFERRED=0`.
    - Hosted release validation run `25719200593` passed.
  - Continue / stop decision: Completed and merged. Issue #36 is closed.
