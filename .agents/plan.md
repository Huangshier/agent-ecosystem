# Active Plan

Active Spec
- `docs/specs/file-based-memory-templates/spec.md` (Active)
- Completed reference:
  `docs/specs/bootstrap-operating-modes/spec.md` (Done via PR #40)
- Completed reference:
  `docs/specs/validation-scratch-retention/spec.md` (Done via PR #39)
- Completed reference:
  `docs/specs/pr-ready-memory-sync-gate/spec.md` (Done via PR #37)
- Completed reference:
  `docs/specs/memory-safety-language-normalization/spec.md` (Done)
- Completed reference:
  `docs/specs/validation-tier-policy/spec.md` (Done)
- Completed reference:
  `docs/specs/minimal-project-adoption-walkthrough/spec.md` (Done)

Current Task
- Resolve issue #32: add file-based `en` and `zh-CN` engineering-memory
  templates for project-bootstrap scaffold generation and language setup.

Session Status
- PR #40 has been merged and issue #33 is closed as completed.
- Local `main` has been fast-forwarded to PR #40 merge commit
  `19656e5f92264a960c8e6ac6039debd97166c10f`.
- Issue #32 has been re-read and is accepted for this implementation pass.
- Issue #30 has been re-read and remains out of scope for this PR.
- Branch `issue-32-file-based-memory-templates` is active.

Next Work
- [x] Sync public `main` after PR #40.
- [x] Confirm #33 is closed as completed and PR #40 is merged.
- [x] Re-read #32 and #30 and confirm #30 remains out of scope.
- [x] Create #32 branch and work package.
- [x] Add file-based `en` and `zh-CN` memory template trees.
- [x] Update language setup to load templates from files with `zh-CN` to `en`
  fallback warnings.
- [x] Update docs and release validation coverage.
- [x] Run `git diff --check`.
- [x] Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1`
  (`PASS=37 FAIL=0 WARN=0 DEFERRED=0`).
- [ ] Commit, push, and open a draft PR for #32.

Notes
- Do not store private mappings, local paths, automation identity material, or
  private audit findings here.
- Do not implement #32 or #30 in the #33 PR.
