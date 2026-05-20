# Active Plan

Active Spec
- `docs/specs/accepted-stabilization-guardrails/spec.md`

Current Branch
- `codex/issue-65-high-risk-evidence-gate`

Current Task
- PR-C / #65 Phase A: finish restacking onto latest `main`, validate, update
  PR #72, mark ready, and merge after hosted checks pass.

Session Status
- Public `main` and `origin/main` are at
  `80858a4d88151714d5a5a7e85e91f12381c581fb`.
- Open public PRs were empty when this sequence started.
- PR #70 for PR-A / #69 was merged to `main`.
- Original PR #71 for PR-B / #65 Phase B/C was accidentally merged into the
  stacked base branch, not `main`.
- Replacement PR #75 for PR-B / #65 Phase B/C was merged to `main`.
- PR #72 for PR-C / #65 Phase A is being restacked from its old stacked base to
  latest `main`.
- Accepted issue order: #69, #65 Phase B/C, #65 Phase A, #68, #66.
- Deferred and out of scope: #67, #56, #23, and README redesign.

Next Work
- Finish the #72 rebase, preserving only Phase A high-risk evidence gate scope.
- Run local validation, force-push the #72 issue branch with lease, retarget PR
  #72 to `main`, mark it ready, wait for hosted checks, then merge.
- Rebase or replace PR-D and PR-E onto latest `main` in order after #72 merges.

Notes
- Do not move tags, publish or edit GitHub Releases, close or edit issues, push
  directly to `main`, force-push `main`, or change repository settings without
  explicit maintainer approval.
- Issue branch restacking may use `--force-with-lease` when needed.
- Do not use tracked `.agents` memory for repeated CI timestamp refresh commits.
- Do not introduce private overlay content, local-only paths, authentication
  material, or domain-specific incubator templates into this public repository.
