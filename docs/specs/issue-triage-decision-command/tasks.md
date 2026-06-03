# Task Plan

- **Spec**: `docs/specs/issue-triage-decision-command/spec.md`
- **Status**: Done
- **Updated**: 2026-06-03

## Tasks

- [x] T01: Create accepted public issue
  - Scope: GitHub issue #123.
  - Validation: Issue author verified as `agent-ecosystem-bot[bot]`; body uses `Decision: accepted`.
  - Notes: Created before public branch work.

- [x] T02: Implement comment command workflow
  - Scope: `.github/scripts/issue-triage-decision-command.js` and `.github/workflows/issue-triage-decision-command.yml`.
  - Validation: Local harness covers parser, authorization, body update, and label convergence.
  - Notes: Workflow must ignore PR comments and unauthorized commenters.

- [x] T03: Update public governance and release validation
  - Scope: `docs/agent-governance.md`, `scripts/test-issue-triage-decision-command.ps1`, and `scripts/validate-release.ps1`.
  - Validation: `git diff --check`; local harness; full release validator.
  - Notes: Keep manual `Decision:` edit flow intact.

- [x] T04: Commit, push, and open draft PR
  - Scope: Branch `codex/issue-123-decision-comment-command`.
  - Validation: Draft PR #124 exists and references #123.
  - Notes: Push uses maintainer identity per explicit authorization because workflow-file pushes are outside current bot permissions.

## Task-to-Spec Notes
- T02 and T03 satisfy issue #123 acceptance criteria.

## Execution Contract Tasks

- [x] P01: Complete phase 1 and record validation
  - Goal: Create accepted issue and branch.
  - Inputs: Maintainer instruction and bot helper.
  - Outputs: Issue #123 and branch `codex/issue-123-decision-comment-command`.
  - Validation: Bot issue author verified.
  - Continue / stop decision: Continue.

- [x] P02: Complete phase 2 and record validation
  - Goal: Implement scoped workflow and docs.
  - Inputs: Existing triage label sync workflow and governance docs.
  - Outputs: Workflow, helper, tests, validator coverage, spec/tasks.
  - Validation: `scripts/test-issue-triage-decision-command.ps1 -Json`, `git diff --check`, and `scripts/validate-release.ps1 -ScratchRoot <scratch>` passed.
  - Continue / stop decision: Continue to draft PR creation.

- [x] P03: Complete phase 3 and record validation
  - Goal: Push branch and create draft PR.
  - Inputs: Validated local commit.
  - Outputs: Draft PR #124.
  - Validation: PR metadata and local validation evidence recorded in the PR body.
  - Continue / stop decision: Stop after reporting as requested.
