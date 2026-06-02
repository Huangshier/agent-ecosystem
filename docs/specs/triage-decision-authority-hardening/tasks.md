# Task Plan

- **Spec**: `docs/specs/triage-decision-authority-hardening/spec.md`
- **Status**: Done
- **Updated**: 2026-06-02

## Tasks

- [x] T01: Create accepted tracking issue
  - Scope: GitHub issue #121.
  - Validation: issue exists and author is verified as `agent-ecosystem-bot[bot]`.
  - Notes: User authorized implementation and PR publication; merge remains out of scope.

- [x] T02: Implement issue template and workflow hardening
  - Scope: `.github/ISSUE_TEMPLATE/agent-candidate.md` and `.github/workflows/issue-triage-label-sync.yml`.
  - Validation: workflow parser supports normalized `Decision:` values, legacy checklist compatibility, actor guard, and same-issue concurrency.
  - Notes: Label event execution was narrowed to adding `source:agent`; `unlabeled` no longer triggers the workflow.

- [x] T03: Update docs and release validation
  - Scope: `docs/agent-governance.md` and `scripts/validate-release.ps1`.
  - Validation: release validation checks the new workflow/template/doc authority model.
  - Notes: The validator now checks expected single-field and actor-guard markers and rejects legacy checkbox template markers.

- [x] T04: Run local validation
  - Scope: full changed worktree.
  - Validation: `git diff --check`; release validation with scratch root.
  - Notes: `git diff --check` passed; workflow YAML parsed; local Node harness covered parser/actor paths; release validation passed with `PASS=54 FAIL=0 WARN=0 DEFERRED=0`.

- [x] T05: Publish PR and stop before merge
  - Scope: branch, commit, push, PR for #121.
  - Validation: PR exists and is ready for maintainer review.
  - Notes: PR #122 is open and non-draft. Bot push failed because the App lacks workflow-file write permission, so the branch was pushed with the maintainer-authenticated account as authorized. PR author was verified as `agent-ecosystem-bot[bot]`.

## Task-to-Spec Notes
- T02 and T03 map to P02.
- T04 maps to P03.
- T05 maps to P04 and is the user-defined stop point.

## Execution Contract Tasks

- [x] P01: Create accepted issue #121 and durable public work package
  - Goal: Preserve issue-first routing and durable context.
  - Inputs: Maintainer request and audit findings.
  - Outputs: Issue #121, spec, tasks.
  - Validation: Bot issue author verified.
  - Continue / stop decision: Continue.

- [x] P02: Implement template, workflow, governance docs, and release validation updates
  - Goal: Harden parsing and authority boundaries.
  - Inputs: Current template, workflow, governance docs, release validator.
  - Outputs: In-scope file changes.
  - Validation: Focused review plus release validator structural coverage.
  - Continue / stop decision: Continue.

- [x] P03: Run local validation and fix in-scope failures
  - Goal: Prove the scoped change is locally coherent.
  - Inputs: Completed diff.
  - Outputs: Validation evidence.
  - Validation: `git diff --check`; release validation.
  - Continue / stop decision: Continue.

- [x] P04: Commit, push, open PR, mark ready for review, and stop before merge
  - Goal: Publish a reviewable PR for #121.
  - Inputs: Validated diff and authenticated GitHub access.
  - Outputs: Commit, branch push, PR URL.
  - Validation: PR #122 exists, targets `main`, is non-draft, and PR author is verified as `agent-ecosystem-bot[bot]`.
  - Continue / stop decision: Stop for maintainer review and merge decision.
