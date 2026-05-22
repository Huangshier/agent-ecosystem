# Task Plan

- **Spec**: `docs/specs/project-memory-template-authority/spec.md`
- **Status**: Done
- **Updated**: 2026-05-22

> Historical note: this task plan records the intermediate `v0.4.1` authority
> layout. References to `templates/project-memory` or
> `skills/project-bootstrap/templates/project-memory/` are legacy history after
> `v0.4.2`, not current public template guidance.

## Tasks

- [x] T01: Create implementation branch and record issue scope.
  - Scope: branch from latest `origin/main`; read issue #49 body and comments.
  - Validation: branch points at latest `origin/main`; spec captures accepted
    scope and non-goals.
  - Notes: Branch `codex/issue-49-project-memory-authority` was created from
    `origin/main` at `1736f9c82208977ad1cb78f312ecf0c0b64d4e34`.

- [x] T02: Move project-memory templates to the new authority and snapshot.
  - Scope: add `knowledge-hub/templates/project-memory/en|zh-CN/**`, add
    bundled snapshot mirrors, remove
    `skills/project-bootstrap/templates/project-memory/`.
  - Validation: authority and snapshot trees exist; old tree is absent.
  - Notes: Authority and bundled snapshot hashes match; the legacy standalone
    directory is absent.

- [x] T03: Update scripts and public docs.
  - Scope: `set_project_language.ps1`, `bootstrap_project.ps1` if needed, and
    docs that reference old paths.
  - Validation: no stale old-path references remain except historical specs or
    explicit negative validation.
  - Notes: `set_project_language.ps1` and `language_migration.ps1` now default
    to the bundled project-memory snapshot. `bootstrap_project.ps1` records the
    language template source when language scaffolds are written.

- [x] T04: Update release validation.
  - Scope: authority/snapshot checks, old-directory absence check, language
    scaffold generation, and missing `zh-CN` fallback fixture.
  - Validation: release validator covers #49 acceptance criteria.
  - Notes: Release validation checks required authority/snapshot directories,
    forbids the legacy standalone directory, compares authority and snapshot
    files, and runs the fallback fixture from the bundled snapshot.

- [x] T05: Run requested checks and fix failures.
  - Scope: `git diff --check` and `scripts/validate-release.ps1`.
  - Validation: both requested checks pass, or blockers are recorded.
  - Notes: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1`
    passed with `PASS=40 FAIL=0 WARN=0 DEFERRED=0`.

- [x] T06: Commit, push topic branch, and open draft PR.
  - Scope: only #49 implementation and required public memory/spec updates.
  - Validation: PR #50 merged to `main` at
    `7978d53542de5ce8c35af4f16ffc32e647fe4db0`; issue #49 is closed.
  - Notes: Hosted Release validation succeeded on Windows PowerShell 5.1,
    Windows PowerShell 7, Ubuntu, and macOS via run
    https://github.com/Huangshier/agent-ecosystem/actions/runs/25800447160.

## Task-to-Spec Notes
- This issue deliberately avoids changing #30 migration apply behavior.
- The bundled hub snapshot may include both ordinary hub templates and
  language-specific project-memory templates.

## Conditional Loop Tasks
- Not used.

## Execution Contract Tasks
- [x] P01: Complete phase 1 and record validation.
  - Goal: Branch and issue context are established.
  - Inputs: issue #49 body/comment and latest `origin/main`.
  - Outputs: active branch and work spec/tasks.
  - Validation: `git status --short --branch`.
  - Continue / stop decision: Continue; branch, issue context, and spec are in
    place.
- [x] P02: Complete phase 2 and record validation.
  - Goal: Template authority move plus script/docs updates are implemented.
  - Inputs: current language template trees and bootstrap scripts.
  - Outputs: new authority/snapshot trees, no old standalone tree, updated docs.
  - Validation: targeted path and reference checks.
  - Continue / stop decision: Continue; targeted path and parser checks passed.
- [x] P03: Complete phase 3 and record validation.
  - Goal: Release validation covers #49 and requested checks pass.
  - Inputs: updated validator and scripts.
  - Outputs: passing validation evidence.
  - Validation: `git diff --check`; `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1`.
  - Continue / stop decision: Continue; release validation passed with
    `PASS=40 FAIL=0 WARN=0 DEFERRED=0`.
- [x] P04: Complete phase 4 and record validation.
  - Goal: Draft PR is opened from the topic branch.
  - Inputs: validated working tree changes.
  - Outputs: commit, pushed branch, draft PR.
  - Validation: PR #50 exists at
    https://github.com/Huangshier/agent-ecosystem/pull/50, remains draft, and
    hosted Release validation succeeded for head
    `54b2498366a611589638f1e8aac68c73c95c7b30`.
  - Continue / stop decision: Complete.
