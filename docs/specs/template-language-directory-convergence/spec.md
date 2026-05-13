# Work Spec

- **Title**: Template Language Directory Convergence
- **Slug**: template-language-directory-convergence
- **Status**: Active
- **Owner**: Codex
- **Updated**: 2026-05-13

## 1. Summary
- Converge template directories after v0.4.1 so the repository exposes one
  language-scoped template entry model:
  `templates/languages/<language>/project-root|project-agent`.
- Remove the legacy top-level and `project-memory` template trees without
  keeping compatibility mirrors.

## 2. Current Context
- Issue #51 tracks the requested convergence.
- Current `main` is tagged `v0.4.1` and still contains a mixed model:
  top-level `project-root` / `project-agent` templates plus
  `project-memory/<language>/project-root|project-agent` language templates.
- Bootstrap, language setting, migration, hub initialization, release
  validation, and documentation contain path assumptions that must move
  together.

## 3. Goals
- Keep only these authoritative template entries:
  `knowledge-hub/templates/languages/en/project-root/`,
  `knowledge-hub/templates/languages/en/project-agent/`,
  `knowledge-hub/templates/languages/zh-CN/project-root/`, and
  `knowledge-hub/templates/languages/zh-CN/project-agent/`.
- Keep only the matching bundled snapshot entries under
  `skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/`.
- Remove legacy `project-root`, `project-agent`, and `project-memory` template
  trees from both authority and bundled snapshot locations, plus the old
  standalone `skills/project-bootstrap/templates/project-memory/` tree.
- Make plain bootstrap default to behavior equivalent to `ProjectLanguage=en`.
- Update `bootstrap_project.ps1`, `set_project_language.ps1`, and
  `language_migration.ps1` to read
  `templates/languages/<language>/project-root|project-agent`.
- Update `init_hub.ps1`, release validation, READMEs, SKILL docs, and path
  references.
- Open a draft PR for #51 without merging or pushing directly to `main`.

## 4. Non-Goals
- Do not keep compatibility mirrors for old template paths.
- Do not change bootstrap overwrite, backup, or force-reset safety semantics.
- Do not add unrelated language migration features.
- Do not change release metadata except documentation/validation references
  needed for #51.
- Do not merge the draft PR or push directly to `main`.

## 5. Constraints
- Public repository engineering memory and specs are English-first.
- Scope control: do not include unrelated refactors, cleanup, or behavior
  changes unless they are explicit goals.
- Existing project memory must not be overwritten aggressively by bootstrap or
  language tooling.
- Release validation must fail when required new paths are missing or forbidden
  old paths reappear.

## 6. Assumptions
- `en` is the default language for ordinary bootstrap.
- The `languages/<language>` layout should carry both root-level project
  templates and `.agents` project-agent templates for each supported language.
- `en` fallback remains acceptable when a requested localized language template
  is missing.

## 7. Risks
- Hardcoded old paths may remain in scripts or docs and create another split
  authority model.
- Directory moves can accidentally change bootstrap safety behavior if copy
  paths and overwrite checks are mixed.
- Release validation fixture setup may still create old trees unless updated.

## 8. Proposed Approach
- Inventory all `templates/project-root`, `templates/project-agent`,
  `templates/project-memory`, and `skills/project-bootstrap/templates/project-memory`
  references.
- Move the current authoritative template contents into
  `templates/languages/en|zh-CN/project-root|project-agent` and mirror the same
  layout in the bundled snapshot.
- Update bootstrap and language scripts to resolve language template roots from
  the new layout, with `en` as the default.
- Update docs and SKILL files to describe only the new path model.
- Strengthen release validation to assert required new directories, reject old
  directories, and exercise bootstrap/language operations through the new
  sources.

## 9. Acceptance / Evidence
- Issue #51 exists.
- Required new authority and bundled snapshot directories exist.
- Forbidden old directories do not exist.
- Plain bootstrap behaves like `ProjectLanguage=en`.
- `bootstrap_project.ps1`, `set_project_language.ps1`, and
  `language_migration.ps1` read the new language directory layout.
- `init_hub.ps1`, `scripts/validate-release.ps1`, README/SKILL/docs path
  references are updated.
- `git diff --check` passes.
- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1`
  passes.
- Draft PR is open and not merged.

Current evidence:
- Issue #51: https://github.com/Huangshier/agent-ecosystem/issues/51
- `git diff --check`: passed.
- Release validation: `PASS=40 FAIL=0 WARN=0 DEFERRED=0`.

## 10. Loop Contract
- Not used.

## 11. Execution Contract
- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Create issue, branch, and work package.
  - P02: Inventory path references and template consumers.
  - P03: Move template trees and update scripts/docs.
  - P04: Update validation and run requested checks.
  - P05: Sync public engineering memory, commit, push branch, and open draft PR.
- **Continue rule**: Continue to the next phase when the current phase remains
  inside #51 scope and requested validation evidence is available or blockers
  are recorded.
- **Stop rule**: Stop for scope drift, unrelated refactor pressure, skipped
  acceptance checks without a recorded reason, safety or permission blockers,
  direct-main push risk, or unresolved ambiguity.
- **State record**: `docs/specs/template-language-directory-convergence/tasks.md`
  and `.agents/plan.md`.

## 12. Open Questions
- None currently blocking execution.
