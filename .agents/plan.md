# Active Plan

Active Spec
- None. The active work is tracked by public issue #55.

Current Task
- Implement issue #55: document the post-`v0.4.2` upgrade path for existing
  `.agents` projects.

Session Status
- Working branch: `codex/issue-55-existing-project-upgrade-path`.
- Current published public release is `v0.4.2`.
- Stabilization issues #53 through #57 are open.
- This stacked branch builds on issues #53 and #54 and adds existing-project
  upgrade guidance plus release validation coverage for issue #55.

Next Work
- Run `git diff --check`.
- Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1 -ScratchRoot <scratch>`.
- Commit, push the branch with the configured automation identity, and open a
  stacked draft PR for #55.

Notes
- Do not push directly to `main`, merge PRs, tag releases, publish releases, or
  change repository settings.
