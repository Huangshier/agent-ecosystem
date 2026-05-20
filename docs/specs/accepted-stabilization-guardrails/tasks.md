# Task Plan

- **Spec**: `docs/specs/accepted-stabilization-guardrails/spec.md`
- **Status**: Active
- **Updated**: 2026-05-20

## Tasks

- [x] T01: Confirm initial public repository state
  - Scope: repo root, branch, status, baseline, open pull requests, and open
    issue triage.
  - Validation: `git fetch origin --prune`; `git status -sb`; `git rev-parse
    main origin/main HEAD`; `gh pr list`; `gh issue list`.
  - Notes: Work started from clean `main` at
    `5e217c9549a8436ab8e8b1a10a6aa400be6d0466`; open PRs were empty.

- [x] T02: Create public execution state
  - Scope: `docs/specs/accepted-stabilization-guardrails/`,
    `.agents/process.txt`, and `.agents/plan.md`.
  - Validation: Included in PR-A local validation.
  - Notes: Public memory is kept as a pointer, not a duplicate task list.

## Task-to-Spec Notes
- Draft PR order:
  1. PR-A / #69: `codex/issue-69-closeout-write-scope-guardrails` into
     `main`.
  2. PR-B / #65 Phase B/C:
     `codex/issue-65-cross-workspace-goal-guardrails`.
  3. PR-C / #65 Phase A: `codex/issue-65-high-risk-evidence-gate`.
  4. PR-D / #68: `codex/issue-68-bootstrap-analyze-semantics`.
  5. PR-E / #66: `codex/issue-66-memory-scope-language-governance`.
- Stacked PRs are allowed and should record their base branches in PR bodies.
- #67, #56, #23, and README redesign remain deferred.

## Conditional Loop Tasks
- Not applicable.

## Execution Contract Tasks

- [x] P01: Initialize public execution package and memory pointer
  - Goal: Establish public-safe phase state for the accepted PR sequence.
  - Inputs: accepted public issues #69, #65, #68, and #66.
  - Outputs: this spec/tasks package and refreshed `.agents` hot memory.
  - Validation: `git diff --check` passed; full local release validator passed
    with `PASS=46 FAIL=0 WARN=0 DEFERRED=0`.
  - Continue / stop decision: Continue to P02.

- [x] P02: Complete PR-A for #69
  - Goal: Add closeout write-scope guardrails for public/private boundary
    protection.
  - Inputs: #69 accepted issue body and existing `memory-governance` workflow.
  - Outputs: `codex/issue-69-closeout-write-scope-guardrails`, ready to push
    and open as draft PR-A.
  - Validation: `git diff --check` passed; full local release validator passed
    with `PASS=46 FAIL=0 WARN=0 DEFERRED=0` using scratch root
    `$env:TEMP\agent-ecosystem-pr-a-69-validation-2`.
  - Continue / stop decision: Continue to P03 after PR-A is pushed and opened
    as a draft PR; no stop rule triggered.

- [x] P03: Complete PR-B for #65 Phase B/C
  - Goal: Add cross-workspace root verification and `/goal` source evidence
    guardrails.
  - Inputs: #65 accepted issue body, excluding high-risk Phase A.
  - Outputs: Original draft PR #71:
    https://github.com/Huangshier/agent-ecosystem/pull/71
    was accidentally merged into the stacked base branch instead of `main`;
    replacement branch
    `codex/issue-65-cross-workspace-goal-guardrails-main` targets `main`.
  - Validation: `git diff --check` passed; full local release validator passed
    with `PASS=46 FAIL=0 WARN=0 DEFERRED=0` using scratch root
    `$env:TEMP\agent-ecosystem-pr-b-65bc-validation`.
  - Continue / stop decision: Continue through the replacement PR before P04.

- [x] P04: Complete PR-C for #65 Phase A
  - Goal: Add a generic high-risk evidence gate without adding a domain pack.
  - Inputs: #65 accepted issue body, Phase A scope.
  - Outputs: `codex/issue-65-high-risk-evidence-gate`, ready to push and open
    as PR-C. It is being restacked from the old stacked base to latest `main`
    after replacement PR #75 merged.
  - Validation: previous stacked `git diff --check` passed; previous full local
    release validator passed
    with `PASS=46 FAIL=0 WARN=0 DEFERRED=0` using scratch root
    `$env:TEMP\agent-ecosystem-pr-c-65a-validation`; validation must be rerun
    after restacking.
  - Continue / stop decision: Continue to P05 after PR-C is based on latest
    `main`, validated, and merged.

- [ ] P05: Complete PR-D for #68
  - Goal: Clarify project-bootstrap analyze, refresh, and language semantics.
  - Inputs: #68 accepted issue body and existing project-bootstrap docs.
  - Outputs: draft PR-D.
  - Validation: `git diff --check`; full local release validator.
  - Continue / stop decision: Continue to P06 after PR-D is based on latest
    `main`, validated, and merged.

- [ ] P06: Complete PR-E for #66
  - Goal: Close memory-scope discovery and language-governance gaps.
  - Inputs: #66 accepted issue body and #67 deferred boundary.
  - Outputs: draft PR-E.
  - Validation: `git diff --check`; full local release validator.
  - Continue / stop decision: Continue to P07 after PR-E is based on latest
    `main`, validated, and merged.

- [ ] P07: Hand off draft PR sequence
  - Goal: Provide maintainers with the full PR list, base relationship,
    validation evidence, hosted check status, and remaining risks.
  - Inputs: PR-A through PR-E URLs and validation results.
  - Outputs: maintainer review handoff.
  - Validation: `gh pr list --repo Huangshier/agent-ecosystem --state open`.
  - Continue / stop decision: Stop for maintainer review.
