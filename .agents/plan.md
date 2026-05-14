# Active Plan

Active Spec
- None. The active work is tracked by public issue #57 and this fresh
  release-prep branch replaces the stale old #61 branch state.

Current Task
- PR #63 release-prep metadata and public engineering memory refresh now also
  includes template-scaffold alignment while preserving running/project-specific
  memory.

Session Status
- Working branch: `codex/rebuild-v0.4.3-release-prep`.
- Draft PR: #63 `[codex] Rebuild v0.4.3 release-prep from main`.
- Current published public release is `v0.4.2`.
- PR #58 and PR #62 have been squash-merged to `main`.
- PR #62 restored the final #59 legacy template-path audit and #60 existing
  project upgrade path content onto `main`.
- PR #63 replaces the stale old #61 release-prep branch and is the active
  review surface for issue #57.
- The old #61 branch is stale and must not be continued, force-pushed, rebased,
  or merged.
- Issue #56 is deferred planning and has no implementation PR in this release
  prep pass.

Next Work
- Wait for hosted Release validation on the latest PR #63 head after the
  template-scaffold refresh commit is pushed.
- Maintainer decision remains required before marking ready for review,
  merging, tagging `v0.4.3`, or publishing a GitHub Release.

Notes
- Do not push directly to `main`, merge PRs, tag releases, publish releases,
  mark PRs ready for review, continue old #61, close issues, or change
  repository settings.
