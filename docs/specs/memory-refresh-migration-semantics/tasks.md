# Task Plan

- **Spec**: `docs/specs/memory-refresh-migration-semantics/spec.md`
- **Status**: Done
- **Updated**: 2026-05-22

## Tasks

- [x] T01: Confirm root, branch, status, and context
  - Scope: Public repo root, latest `main`, project AGENTS guidance, local
    `.agents` presence, and private report #79-A section.
  - Validation: Confirmed the public repo root, fast-forwarded `main` to
    `df20869`, then created `docs/memory-refresh-migration-semantics`.
  - Notes: Private report is read-only evidence; public writes are scoped to
    #79-A guidance semantics.

- [x] T02: Update guidance and templates
  - Scope: `project-bootstrap`, `memory-governance`, `project-context-gate`,
    project AGENTS templates, README navigation, and related docs.
  - Validation: Diff review completed; release validation passed with
    `PASS=50 FAIL=0 WARN=0 DEFERRED=0`.
  - Notes: Keep this guidance-only; no script behavior changes.

- [x] T03: Validate guidance and prepare PR handoff
  - Scope: `git diff --check`, release validation, and PR-ready scope review.
  - Validation: `git diff --cached --check` passed; release validation passed
    with `PASS=50 FAIL=0 WARN=0 DEFERRED=0`.
  - Notes: PR metadata must use `Refs #79` and must not claim #79 completion.

## Task-to-Spec Notes
- #79-A is intentionally split from #79-B. This PR should clarify triggers and
  intent while leaving workflow/validation changes for a later PR.

## Conditional Loop Tasks
- Not applicable.

## Execution Contract Tasks

- [x] P01: Complete phase 1 and record validation
  - Goal: Load context and establish safe branch/work package.
  - Inputs: Root AGENTS, local `.agents` check, relevant specs and skill docs,
    private report.
  - Outputs: Branch and work package.
  - Validation: Root/branch/status confirmed; latest `main` pulled.
  - Continue / stop decision: Continue.

- [x] P02: Complete phase 2 and record validation
  - Goal: Update guidance-only surfaces.
  - Inputs: Existing skill docs, templates, public docs.
  - Outputs: Patched guidance and docs.
  - Validation: Diff review completed; release validation passed with
    `PASS=50 FAIL=0 WARN=0 DEFERRED=0`.
  - Continue / stop decision: Continue to validation.

- [x] P03: Complete phase 3 and record validation
  - Goal: Validate locally and prepare PR handoff.
  - Inputs: Final diff and validation commands.
  - Outputs: Validated guidance diff and durable local evidence.
  - Validation: `git diff --cached --check` passed; release validation passed
    with `PASS=50 FAIL=0 WARN=0 DEFERRED=0`.
  - Continue / stop decision: Complete local implementation; publish PR.
