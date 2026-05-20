# Active Plan

Active Spec
- `docs/specs/accepted-stabilization-guardrails/spec.md` is complete.

Current Branch
- `codex/post-merge-memory-closeout`

Current Task
- Memory-governance closeout after the accepted stabilization PR merge
  sequence.

Completed
- #70, #75, #72, #73, and #74 are merged to `main`.
- #65, #66, #68, and #69 are closed as completed.
- Final local and hosted release validation passed on `main`.
- Open PRs are empty.

Deferred
- #67 remains deferred/open.
- #56 remains deferred/open.
- #23 remains deferred/open.

Next Work
- Commit public memory closeout.
- Refresh and commit private overlay memory for the same incident.
- Publish public memory closeout through a PR if it should land on protected
  `main`; do not push directly to `main`.

Notes
- The original #71 cannot be re-opened and merged to `main`; #75 is the
  replacement PR that landed the same Phase B/C scope on `main`.
- For future stacked PR incident recovery, prefer applying each remaining PR's
  net scoped diff to latest `main` over replaying old `.agents` state commits.
