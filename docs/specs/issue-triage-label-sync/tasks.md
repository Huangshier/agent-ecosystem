# Task Plan

- **Spec**: `docs/specs/issue-triage-label-sync/spec.md`
- **Status**: Active
- **Updated**: 2026-05-13

## Tasks

- [x] T01: Create and accept tracking issue
  - Scope: GitHub issue #42.
  - Validation: issue exists with `source:agent` and `triage:accepted`.
  - Notes: Created after issue #30 label drift was observed.

- [x] T02: Add issue triage label sync workflow
  - Scope: `.github/workflows/issue-triage-label-sync.yml`.
  - Validation: workflow has issue trigger, least permissions, source-agent guard, decision parsing, and conflict handling.
  - Notes: Uses `actions/github-script@v8`; multiple checked decisions fail without mutation.

- [x] T03: Document governance behavior
  - Scope: `docs/agent-governance.md` and `.github/ISSUE_TEMPLATE/agent-candidate.md`.
  - Validation: docs distinguish human decision from label synchronization.
  - Notes: Governance docs state the workflow mirrors explicit human decisions only.

- [x] T04: Add release validation coverage
  - Scope: `scripts/validate-release.ps1`.
  - Validation: local release validation checks required workflow/doc strings.
  - Notes: Added `issue triage label sync` release validation check.

- [ ] T05: Validate and publish PR
  - Scope: local validation, commit, push, draft PR.
  - Validation: `git diff --check`; full local release validation.
  - Notes: Local `git diff --check` passed; full local release validation passed with `PASS=38 FAIL=0 WARN=0 DEFERRED=0`.

## Task-to-Spec Notes

- This work maps to issue #42.
- Issue #30 conservative language migration remains separate.

## Execution Contract Tasks

- [x] P01: Create accepted issue #42 and work package
  - Goal: Preserve issue-first routing and durable context.
  - Inputs: issue #30 label drift and governance docs.
  - Outputs: issue #42, spec, tasks.
  - Validation: issue URL exists; spec/tasks created.
  - Continue / stop decision: Continue to implementation.

- [x] P02: Implement workflow, docs, validation, and public memory updates
  - Goal: Add deterministic metadata sync and validation coverage.
  - Inputs: issue template, governance docs, release validator.
  - Outputs: workflow/docs/validator/memory updates.
  - Validation: `git diff --check`; Node regex smoke; full local release validation `PASS=38 FAIL=0 WARN=0 DEFERRED=0`.
  - Continue / stop decision: Continue to publish phase.

- [ ] P03: Run local validation, commit, push branch, and open draft PR
  - Goal: Publish reviewable change for maintainer review.
  - Inputs: completed local diff.
  - Outputs: pushed branch and draft PR.
  - Validation: local checks pass and PR exists.
  - Continue / stop decision:
