# Active Plan

Active Spec
- None. The active work is a stacked-PR merge-state repair requested by the
  maintainer.

Current Task
- Restore #59 legacy template path audit and #60 existing project upgrade path
  content onto current `origin/main` without continuing #61.

Session Status
- Working branch: `codex/restore-stabilization-audit-upgrade-docs`.
- Current published public release is `v0.4.2`.
- Stabilization issues #53 through #57 are open.
- PR #58 was squash-merged to `main`; #59 and #60 were merged into stacked base
  branches instead of `main`, so this branch restores their final reviewed
  content on top of current `origin/main`.

Next Work
- Run `git diff --check`.
- Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1 -ScratchRoot <scratch>`.
- Commit, push this branch, and open the requested draft PR to `main`.

Notes
- Do not push directly to `main`, merge PRs, tag releases, publish releases, or
  change repository settings.
