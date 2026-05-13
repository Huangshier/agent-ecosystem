# Active Plan

Active Spec
- `docs/specs/agents-template-startup-guidance/spec.md` (Active)

Current Task
- Resolve issue #44: improve base AGENTS templates for lean startup context,
  project commands, PR-ready memory sync guidance, and large-issue planning.

Session Status
- Branch `issue-44-agents-template-guidance` is active.
- Implementation and release validation are complete.
- `git diff --check` passed.
- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1`
  passed with `PASS=39 FAIL=0 WARN=0 DEFERRED=0`.
- PR-ready memory sync is complete before PR creation.
- Issue #30 remains out of scope.

Next Work
- Commit the scoped #44 changes.
- Push the branch and open a draft PR.
- After PR creation, do not add a memory-only follow-up commit solely to refresh
  memory state or hosted-check timestamps unless explicitly approved.

Notes
- Durable task state lives in `docs/specs/agents-template-startup-guidance/tasks.md`.
- Do not store private mappings, local paths, automation identity material, or
  private audit findings here.
