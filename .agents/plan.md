# Active Plan

Active Spec
- None. The active work is tracked by public issue #54.

Current Task
- Implement issue #54: audit legacy template-path references after
  language-scoped convergence.

Session Status
- Working branch: `codex/issue-54-legacy-template-path-audit`.
- Current published public release is `v0.4.2`.
- Stabilization issues #53 through #57 are open.
- This stacked branch builds on issue #53 and adds explicit legacy template-path
  audit guidance, historical markers for old path mentions, and release
  validation coverage for issue #54.

Next Work
- Run `git diff --check`.
- Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1 -ScratchRoot <scratch>`.
- Commit, push the branch with the configured automation identity, and open a
  stacked draft PR for #54.

Notes
- Do not push directly to `main`, merge PRs, tag releases, publish releases, or
  change repository settings.
