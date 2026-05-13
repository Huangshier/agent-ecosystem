# Active Plan

Active Spec
- None. The active work is tracked by public issue #57.

Current Task
- Implement issue #57: prepare the `v0.4.3` stabilization release-prep draft.

Session Status
- Working branch: `codex/issue-57-v0.4.3-release-prep`.
- Current published public release is `v0.4.2`.
- Stabilization issues #53 through #57 are open.
- Draft PRs #58, #59, and #60 are open for issues #53, #54, and #55.
- Issue #56 is deferred planning and has no implementation PR in this release
  prep pass.
- This stacked branch builds on issues #53, #54, and #55 and prepares
  `v0.4.3` changelog, release notes, release readiness, and release validation
  coverage for issue #57.

Next Work
- Run `git diff --check`.
- Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1 -ScratchRoot <scratch>`.
- Commit, push the branch with the configured automation identity, and open a
  final stacked draft PR for #57.

Notes
- Do not push directly to `main`, merge PRs, tag releases, publish releases, or
  change repository settings.
