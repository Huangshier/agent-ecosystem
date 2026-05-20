# Active Plan

Active Spec
- `docs/specs/accepted-stabilization-guardrails/spec.md`

Current Branch
- `codex/issue-65-cross-workspace-goal-guardrails-main`

Current Task
- PR-B / #65 Phase B/C: prepare the replacement PR for `main`.

Session Status
- Public `main` and `origin/main` are at
  `a013ad2aca3c97630a592d14f3b3d06cac5d94e2`.
- Open public PRs were empty when this sequence started.
- PR #70 for PR-A / #69 was merged to `main`.
- Original PR #71 for PR-B / #65 Phase B/C was accidentally merged into the
  stacked base branch, not `main`.
- `codex/issue-65-cross-workspace-goal-guardrails-main` is the replacement
  branch for PR-B / #65 Phase B/C.
- Accepted issue order: #69, #65 Phase B/C, #65 Phase A, #68, #66.
- Deferred and out of scope: #67, #56, #23, and README redesign.

Next Work
- Validate, push, open, mark ready, and merge the PR #71 replacement branch
  into `main`.
- Rebase or replace PR-C, PR-D, and PR-E onto latest `main` in order after the
  replacement merge.

Notes
- Do not move tags, publish or edit GitHub Releases, close or edit issues, push
  directly to `main`, force-push `main`, or change repository settings without
  explicit maintainer approval.
- Do not use tracked `.agents` memory for repeated CI timestamp refresh commits.
- Do not introduce private overlay content, local-only paths, authentication
  material, or domain-specific incubator templates into this public repository.
