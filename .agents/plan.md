# Active Plan

Active Spec
- None. The active work is tracked by public issue #55.

Current Task
- Review-fix PR #60: clarify that direct `memory_upgrade.ps1 -Mode Analyze` is
  the no-edit memory-only analysis path, while `bootstrap_project.ps1
  -AnalyzeMemoryUpgrade` may create missing scaffold files before analysis.

Session Status
- Working branch: `codex/issue-55-existing-project-upgrade-path`.
- Current published public release is `v0.4.2`.
- Stabilization issues #53 through #57 are open.
- This stacked branch builds on issues #53 and #54 and adds existing-project
  upgrade guidance plus release validation coverage for issue #55.

Next Work
- Final diff review.
- Commit and push the #60 branch update.
- Update PR #60 body with refreshed validation evidence.

Notes
- Do not push directly to `main`, merge PRs, tag releases, publish releases, or
  change repository settings.
