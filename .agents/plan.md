# Active Plan

Active Spec
- `docs/specs/conservative-language-migration/spec.md` (Active)

Current Task
- Resolve issue #30 with a conservative `en` / `zh-CN` project-memory
  migration workflow.

Session Status
- Branch `issue-30-conservative-language-migration` is active.
- `main` was synchronized to `origin/main` before branching.
- Issues #30, #32, #33, and #44 plus related merged PRs were inspected.
- PR split decision: implement one scoped draft PR for deterministic
  conservative migration; avoid arbitrary-language i18n and unattended
  translation claims.
- Implementation and release validation are complete.
- PR #46 review blocking concerns have been addressed locally while keeping
  scope limited to issue #30 conservative language migration.
- `git diff --check` passed after the blocking-concern fixes.
- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1`
  passed after the blocking-concern fixes with `PASS=40 FAIL=0 WARN=0
  DEFERRED=0`.
- PR body validation evidence and conservative completion scope have been
  updated while keeping PR #46 draft.

Next Work
- Push the scoped PR #46 review-fix commit if needed.
- Keep PR #46 draft; do not merge or mark ready for review. Wait for maintainer
  review after the pushed fix commit.

Notes
- Durable task state lives in
  `docs/specs/conservative-language-migration/tasks.md`.
- Do not store private mappings, local paths, automation identity material, or
  private audit findings here.
