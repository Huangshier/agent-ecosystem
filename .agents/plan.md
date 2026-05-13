# Active Plan

Active Spec
- `docs/specs/template-language-directory-convergence/spec.md` (Active)

Current Task
- Implement issue #51: converge template directories to
  `templates/languages/<language>/project-root|project-agent`, remove the old
  `project-root`, `project-agent`, and `project-memory` template entry trees,
  update scripts/docs/release validation, and open a draft PR.

Session Status
- Working branch: `codex/issue-51-template-language-convergence`.
- Issue #51 is open:
  https://github.com/Huangshier/agent-ecosystem/issues/51
- Template authority and bundled snapshot have been moved to the new language
  layout.
- `bootstrap_project.ps1`, `set_project_language.ps1`,
  `language_migration.ps1`, `init_hub.ps1`, `check_hub_lock.ps1`, docs, and
  release validation have been updated for the new structure.
- Requested local checks passed:
  - `git diff --check`
  - `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1`
    with `PASS=40 FAIL=0 WARN=0 DEFERRED=0`

Next Work
- Inspect final diff, commit, push the topic branch, and open a draft PR for
  #51.

Notes
- Durable task state lives in
  `docs/specs/template-language-directory-convergence/tasks.md`.
- Do not push directly to `main`; do not merge the draft PR from this session.
