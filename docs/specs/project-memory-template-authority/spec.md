# Work Spec

- **Title**: Project Memory Template Authority Refactor
- **Slug**: project-memory-template-authority
- **Status**: Active
- **Owner**: Codex
- **Updated**: 2026-05-13

## 1. Summary
- Refactor project-memory template ownership for issue #49 so
  `knowledge-hub/templates/project-memory/en|zh-CN/**` is the authority,
  bundled bootstrap assets carry a synchronized snapshot, and the legacy
  `skills/project-bootstrap/templates/project-memory/` tree is removed.

## 2. Current Context
- Issue #49 is accepted and requests a template authority refactor, not a
  narrow path cleanup.
- Current `main` still has standalone language templates under
  `skills/project-bootstrap/templates/project-memory/**`.
- `set_project_language.ps1` defaults to that standalone tree.
- `bootstrap_project.ps1` installs shared hub templates from
  `templates/project-root` and `templates/project-agent`, so the refactor must
  keep ordinary bootstrap working while language scaffolds use the new
  project-memory tree.
- `scripts/validate-release.ps1` contains old-path assertions and language
  fixture setup that must move to the new authority and bundled snapshot.

## 3. Goals
- Add authoritative `en` and `zh-CN` project-memory templates under
  `knowledge-hub/templates/project-memory/`.
- Add synchronized bundled snapshots under
  `skills/project-bootstrap/assets/knowledge-hub-template/templates/project-memory/`.
- Remove `skills/project-bootstrap/templates/project-memory/` entirely.
- Update language scaffold scripts and validation to use the bundled snapshot.
- Preserve normal bootstrap behavior and safety semantics.
- Update public documentation that names the old template path.
- Open a draft PR with `Fixes #49` in the body.

## 4. Non-Goals
- Do not change #30 migration apply behavior or add a new #30 migration path.
- Do not mix English and Simplified Chinese within a single `AGENTS.md`
  template beyond the existing language-specific template split.
- Do not change bootstrap overwrite, backup, or force-reset safety semantics.
- Do not change repository rulesets, branch protection, runners, GitHub App
  authentication, releases, or version metadata.
- Do not include unrelated cleanup.

## 5. Constraints
- Public repository engineering memory and specs are English-first.
- Do not push directly to `main`; work must land on a topic branch and draft PR.
- Keep old-path compatibility mirrors out of the repository.
- Scope control: do not include unrelated refactors, cleanup, or behavior
  changes unless they are explicit goals.

## 6. Assumptions
- English remains the fallback language for missing localized project-memory
  templates.
- The bundled hub snapshot may contain both ordinary shared templates
  (`templates/project-root`, `templates/project-agent`) and language-specific
  project-memory templates (`templates/project-memory/en|zh-CN`).

## 7. Risks
- Release validation hardcoded path drift was addressed by checking authority
  paths, bundled snapshot paths, and forbidden legacy paths.
- Ordinary bootstrap still installs `templates/project-root` and
  `templates/project-agent`; language scaffolds use the bundled
  `templates/project-memory` snapshot.
- Missing fallback coverage is covered by the release validation fallback
  fixture.

## 8. Proposed Approach
- Copy current language template trees into the authoritative hub path and the
  bundled snapshot path.
- Remove the standalone `skills/project-bootstrap/templates/project-memory/`
  tree.
- Point `set_project_language.ps1` at the bundled snapshot by default.
- Keep `bootstrap_project.ps1` ordinary template installation on
  `templates/project-root` and `templates/project-agent`, while documenting and
  recording language scaffolds from `templates/project-memory`.
- Update release validation path assertions, source checks, scaffold tests, and
  fallback fixtures.
- Update documentation references to the new authority and bundled snapshot.

## 9. Acceptance / Evidence
- `knowledge-hub/templates/project-memory/en|zh-CN/**` exists and contains the
  language template trees.
- `skills/project-bootstrap/assets/knowledge-hub-template/templates/project-memory/en|zh-CN/**`
  exists and mirrors the authority.
- `skills/project-bootstrap/templates/project-memory/` does not exist.
- English and Simplified Chinese scaffold generation still pass.
- Missing `zh-CN` template fallback to English is still validated.
- Release validation fails if the legacy standalone directory reappears.
- `git diff --check` passes.
- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1`
  passes with `PASS=40 FAIL=0 WARN=0 DEFERRED=0`.

## 10. Loop Contract
- Not used.

## 11. Execution Contract
- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Establish branch, spec, and current issue evidence.
  - P02: Move template authority and update script/documentation references.
  - P03: Update validation and run requested checks.
  - P04: Sync public engineering memory, commit, push branch, and open draft PR.
- **Continue rule**: Continue to the next phase when the current phase changes
  only issue #49 scope and its validation evidence is available.
- **Stop rule**: Stop for scope drift, unrelated refactor pressure, skipped
  acceptance checks without a recorded reason, safety or permission blockers,
  direct-main push risk, or unresolved ambiguity.
- **State record**: `docs/specs/project-memory-template-authority/tasks.md`
  and `.agents/plan.md`.

## 12. Open Questions
- None currently blocking execution.
