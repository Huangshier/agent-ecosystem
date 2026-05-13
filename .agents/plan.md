# Active Plan

Active Spec
- `docs/specs/project-memory-template-authority/spec.md` (Active)

Current Task
- Implement issue #49: refactor project-memory template authority to
  `knowledge-hub/templates/project-memory/`, update bundled bootstrap assets,
  remove the standalone `skills/project-bootstrap/templates/project-memory/`
  tree, validate, and open a draft PR.

Session Status
- Working branch: `codex/issue-49-project-memory-authority`.
- Issue #49 body and maintainer review note have been read.
- Work package created under
  `docs/specs/project-memory-template-authority/`.
- Template authority move, script updates, document updates, and release
  validation updates are implemented.
- Release validation passed with `PASS=40 FAIL=0 WARN=0 DEFERRED=0`.

Next Work
- Run `git diff --check`.
- Commit, push the topic branch, and open a draft PR with `Fixes #49`.

Notes
- Durable task state lives in
  `docs/specs/project-memory-template-authority/tasks.md`.
- Do not store private mappings, local paths, automation identity material, or
  private audit findings here.
- Do not push directly to `main`; do not expand this work to #30 migration
  apply behavior.
