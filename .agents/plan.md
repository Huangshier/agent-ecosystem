# Active Plan

Active Spec
- `docs/specs/bootstrap-operating-modes/spec.md` (Active)
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
- Resolve issue #33: clarify `project-bootstrap` operating modes and make
  dangerous overwrite/reset semantics explicit, warning-heavy, and backup-first.

Session Status
- PR #39 has been merged and issue #38 is closed as completed.
- Local `main` has been fast-forwarded to the PR #39 merge commit.
- The old #38 topic branch was cleaned locally and remotely after merge.
- Issue #33 has been accepted for this implementation pass.
- Branch `issue-33-bootstrap-operating-modes` is active.
- Issues #32 and #30 were re-read for dependency order and remain out of scope
  for this PR.

Next Work
- [x] Sync public `main` after PR #39.
- [x] Confirm #38 is closed as completed and PR #39 is merged.
- [x] Clean the old #38 branch locally and remotely.
- [x] Re-read #33, #32, and #30 and confirm dependency order.
- [x] Create #33 branch and work package.
- [x] Update bootstrap script mode semantics and warnings.
- [x] Update docs, skill guidance, and release validation coverage.
- [x] Run `git diff --check`.
- [x] Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1`.
- [ ] Commit, push, and open a draft PR for #33.

Notes
- Do not store private mappings, local paths, automation identity material, or
  private audit findings here.
- Do not implement #32 or #30 in the #33 PR.
