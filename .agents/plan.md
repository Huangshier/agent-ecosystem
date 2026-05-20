# Active Plan

Active Spec
- `docs/specs/accepted-stabilization-guardrails/spec.md` is complete.
- `docs/specs/post-v0-4-3-flow-guardrails/spec.md` is active.

Current Branch
- `codex/pr-ci-flow-guardrails`

Current Task
- Add PR base/stack safety guardrails and release-validation concurrency, then
  re-triage deferred issues after the PR lands.

Completed
- #70, #75, #72, #73, and #74 are merged to `main`.
- #65, #66, #68, and #69 are closed as completed.
- Final local and hosted release validation passed on `main`.
- PR #76 merged the accepted stabilization memory closeout to `main`.
- Hosted Release validation after PR #76 passed.

Deferred
- #67 remains deferred/open.
- #56 remains deferred/open.
- #23 remains deferred/open.

Next Work
- Open and merge the `codex/pr-ci-flow-guardrails` PR after hosted checks pass.
- Re-triage #67, #56, and #23.

Notes
- The original #71 cannot be re-opened and merged to `main`; #75 is the
  replacement PR that landed the same Phase B/C scope on `main`.
- For future stacked PR incident recovery, prefer applying each remaining PR's
  net scoped diff to latest `main` over replaying old `.agents` state commits.
- CI is not being split in this change; only concurrency is added.
- Local `git diff --check` and full release validation passed for the guardrail
  branch with `PASS=46 FAIL=0 WARN=0 DEFERRED=0`.
