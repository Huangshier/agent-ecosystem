# Active Plan

Active Spec
- `docs/specs/project-memory-template-authority/spec.md` (Active)

Current Task
- Implement issue #49: refactor project-memory template authority to
  `knowledge-hub/templates/project-memory/`, update bundled bootstrap assets,
  remove the standalone `skills/project-bootstrap/templates/project-memory/`
  tree, validate, and keep draft PR #50 ready for maintainer review.

Session Status
- Working branch: `codex/issue-49-project-memory-authority`.
- Issue #49 body and maintainer review note have been read.
- Work package created under
  `docs/specs/project-memory-template-authority/`.
- Template authority move, script updates, document updates, and release
  validation updates are implemented.
- Release validation passed with `PASS=40 FAIL=0 WARN=0 DEFERRED=0`.
- PR #50 is open as a draft:
  https://github.com/Huangshier/agent-ecosystem/pull/50
- Current PR head SHA:
  `54b2498366a611589638f1e8aac68c73c95c7b30`.
- Hosted Release validation passed for the current head on Windows PowerShell
  5.1, Windows PowerShell 7, Ubuntu, and macOS:
  https://github.com/Huangshier/agent-ecosystem/actions/runs/25800447160

Next Work
- Wait for maintainer review on draft PR #50.
- Address review feedback if requested.
- When approved, prepare PR #50 for ready-for-review; do not merge from this
  session.

Notes
- Durable task state lives in
  `docs/specs/project-memory-template-authority/tasks.md`.
- Do not store private mappings, local paths, automation identity material, or
  private audit findings here.
- Do not push directly to `main`; do not expand this work to #30 migration
  apply behavior.
- Keep PR #50 as draft until maintainer explicitly approves ready-for-review.
