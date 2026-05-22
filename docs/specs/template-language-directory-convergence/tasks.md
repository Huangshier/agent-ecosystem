# Task Plan

- **Spec**: `docs/specs/template-language-directory-convergence/spec.md`
- **Status**: Done
- **Updated**: 2026-05-22

> Historical note: this task plan records the migration away from legacy
> template paths. References to `templates/project-root`,
> `templates/project-agent`, `templates/project-memory`, or
> `skills/project-bootstrap/templates/project-memory/` describe removed legacy
> state or negative validation, not current public template guidance.

## Tasks

- [x] T01: Create public issue, branch, and work package.
  - Scope: issue #51, branch from current `main`, spec/tasks.
  - Validation: issue URL exists and branch is not `main`.
  - Notes: Issue #51 was created at
    https://github.com/Huangshier/agent-ecosystem/issues/51.

- [x] T02: Inventory old path references and script consumers.
  - Scope: all script, docs, SKILL, README, validation, and template paths.
  - Validation: search results identify required edit set.
  - Notes: `rg` found mixed-model references in bootstrap scripts,
    `check_hub_lock.ps1`, `init_hub.ps1`, release validation, project-bootstrap
    docs, language policy docs, and the bundled hub README.

- [x] T03: Move authority and bundled snapshot templates to the new layout.
  - Scope: `knowledge-hub/templates/languages/**` and bundled
    `skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/**`.
  - Validation: required new trees exist and forbidden old trees are absent.
  - Notes: Authority and bundled snapshot now use
    `templates/languages/en|zh-CN/project-root|project-agent`; forbidden old
    template directories are absent.

- [x] T04: Update scripts and public documentation.
  - Scope: bootstrap, set-language, language migration, hub init, README,
    SKILL, and docs path references.
  - Validation: old path references remain only in historical specs or
    explicit negative validation.
  - Notes: Bootstrap defaults to `en`, script consumers resolve
    `templates/languages/<language>/`, hub init prunes known legacy template
    directories, and current README/SKILL/docs path guidance names the new
    structure.

- [x] T05: Update release validation and run requested checks.
  - Scope: `scripts/validate-release.ps1` and any validation fixtures.
  - Validation: `git diff --check` and release validation pass.
  - Notes: `git diff --check` passed. Release validation passed with
    `PASS=40 FAIL=0 WARN=0 DEFERRED=0`.

- [x] T06: Commit, push topic branch, and open draft PR.
  - Scope: only #51 implementation and required public memory/spec updates.
  - Validation: PR #52 merged to `main` at
    `e5367790469574a350bd9cbed28b56fd8b9f74bd`; issue #51 is closed.
  - Notes: Release validation passed locally with
    `PASS=40 FAIL=0 WARN=0 DEFERRED=0`.

## Task-to-Spec Notes
- Plain bootstrap must map to the `en` language templates.
- No compatibility mirrors should be retained for old paths.

## Conditional Loop Tasks
- Not used.

## Execution Contract Tasks

- [x] P01: Complete phase 1 and record validation.
  - Goal: Issue, branch, and work package are established.
  - Inputs: user request and latest `main`.
  - Outputs: issue #51, topic branch, spec/tasks.
  - Validation: `git branch --show-current`; issue creation output.
  - Continue / stop decision: Continue.

- [x] P02: Complete phase 2 and record validation.
  - Goal: Path reference inventory is complete.
  - Inputs: current tree and search results.
  - Outputs: edit set for templates, scripts, docs, and validation.
  - Validation: targeted `rg` output reviewed.
  - Continue / stop decision: Continue; edit set identified and implemented.

- [x] P03: Complete phase 3 and record validation.
  - Goal: Template moves plus script/docs updates are implemented.
  - Inputs: current template trees and script consumers.
  - Outputs: new language template model with old paths removed.
  - Validation: targeted path and reference checks.
  - Continue / stop decision: Continue; targeted path checks and PowerShell
    parser checks passed.

- [x] P04: Complete phase 4 and record validation.
  - Goal: Release validation covers #51 and requested checks pass.
  - Inputs: updated validator and scripts.
  - Outputs: passing validation evidence.
  - Validation: `git diff --check`; release validation command.
  - Continue / stop decision: Continue; requested checks passed.

- [x] P05: Complete phase 5 and record validation.
  - Goal: Draft PR is opened from the topic branch.
  - Inputs: validated working tree changes.
  - Outputs: commit, pushed branch, draft PR.
  - Validation: PR URL and branch status.
  - Continue / stop decision: Complete.
