# Active Plan

Active Spec
- None. The active work is tracked by public issue #57 and this fresh
  release-prep branch replaces the stale old #61 branch state.

Current Task
- Rebuild the `v0.4.3` stabilization release-prep draft from current
  `origin/main`.

Session Status
- Working branch: `codex/rebuild-v0.4.3-release-prep`.
- Current published public release is `v0.4.2`.
- PR #58 and PR #62 have been squash-merged to `main`.
- PR #62 restored the final #59 legacy template-path audit and #60 existing
  project upgrade path content onto `main`.
- The old #61 branch is stale and must not be continued, force-pushed, rebased,
  or merged.
- Issue #56 is deferred planning and has no implementation PR in this release
  prep pass.

Next Work
- Commit the validated release-prep rebuild.
- Push this branch and open a replacement draft PR to `main` for issue #57.
- After the PR exists, record the PR number and hosted validation status.

Notes
- Do not push directly to `main`, merge PRs, tag releases, publish releases,
  close issues, or change repository settings.
