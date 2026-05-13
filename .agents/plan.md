# Active Plan

Active Spec
- `docs/specs/conservative-language-migration/spec.md` (Active)

Current Task
- Finalize issue #30 Phase 2 draft PR: narrative migration for `en` /
  `zh-CN` project-memory language migration.

Session Status
- Branch `issue-30-narrative-language-migration` was created from latest
  `origin/main` after PR #46 merged.
- PR #46 merged on 2026-05-13 at merge commit
  `ee327e75aa35bd38c7495a019eaa932f4f9395f2`.
- #30 Phase 1 is complete: deterministic conservative language migration
  scaffold plus manual-review routing.
- Phase 1 intentionally does not claim unattended perfect translation of
  project-specific narrative content.
- Phase 2 implementation is complete locally: manual-review artifacts now feed
  an unapproved-by-default narrative proposal, reviewed narrative actions can be
  applied after backup/source/target hash checks, and validation covers both
  directions.
- Local validation passed on 2026-05-13:
  `git diff --check` and
  `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1`
  with `PASS=40 FAIL=0 WARN=0 DEFERRED=0`.

Next Work
- Commit and push `issue-30-narrative-language-migration`.
- Open a draft PR for #30 Phase 2.
- Do not merge directly to `main`.

Notes
- Durable task state lives in
  `docs/specs/conservative-language-migration/tasks.md`.
- Do not store private mappings, local paths, automation identity material, or
  private audit findings here.
