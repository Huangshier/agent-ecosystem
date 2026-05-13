# Active Plan

Active Spec
- `docs/specs/issue-triage-label-sync/spec.md` (Active)
- Completed reference:
  `docs/specs/file-based-memory-templates/spec.md` (Done via PR #41)
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
- Resolve issue #42: add an issue triage label sync workflow.

Session Status
- PR #41 has been merged and issue #32 is closed as completed.
- Local `main` is clean and matches `origin/main`.
- Issue #42 has been created and accepted for this implementation pass.
- Issue #30 remains out of scope for this PR.
- Branch `issue-42-triage-label-sync` is active.

Next Work
- [x] Create accepted issue #42.
- [x] Create #42 branch and work package.
- [x] Add issue triage label sync workflow.
- [x] Update governance docs and issue template.
- [x] Update release validation coverage.
- [x] Run `git diff --check`.
- [x] Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1`
  (`PASS=38 FAIL=0 WARN=0 DEFERRED=0`).
- [x] Commit, push, and open draft PR #43 for #42.
- [ ] Wait for hosted release validation run `25776495732`.

Notes
- Do not store private mappings, local paths, automation identity material, or
  private audit findings here.
- Do not implement #30 in this PR.
