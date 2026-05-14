# Active Plan

Active Spec
- None. The active work is tracked by public issue #53.

Current Task
- Implement issue #53: normalize `v0.4.1` / `v0.4.2` public release records.

Session Status
- Working branch: `codex/issue-53-release-records`.
- Current published public release is `v0.4.2`.
- Stabilization issues #53 through #57 are open.
- This branch updates README entrypoints, changelog, release readiness,
  release process coverage, `v0.4.1` / `v0.4.2` release notes, and release
  validation coverage for issue #53.

Next Work
- Run `git diff --check`.
- Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1 -ScratchRoot <scratch>`.
- Commit, push the branch with the configured automation identity, and open a
  draft PR for #53.

Notes
- Do not push directly to `main`, merge PRs, tag releases, publish releases, or
  change repository settings.
