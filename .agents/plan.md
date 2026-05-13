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
- `git diff --check` passed.
- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1`
  passed with `PASS=40 FAIL=0 WARN=0 DEFERRED=0`.
- PR-ready memory sync is complete before PR creation.

Next Work
- Inspect the final diff, commit the scoped #30 changes, push the branch, and
  open a draft PR.
- After PR creation, do not add a memory-only follow-up commit solely to refresh
  memory state or hosted-check timestamps unless explicitly approved.

Notes
- Durable task state lives in
  `docs/specs/conservative-language-migration/tasks.md`.
- Do not store private mappings, local paths, automation identity material, or
  private audit findings here.
