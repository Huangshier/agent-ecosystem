# Work Spec

- **Title**: Bootstrap Operating Modes
- **Slug**: bootstrap-operating-modes
- **Status**: Active
- **Owner**: Maintainer + agent
- **Updated**: 2026-05-12

## 1. Summary
- Clarify `project-bootstrap` operating modes so existing project memory does not enter an unsafe overwrite path by default.
- Keep compatibility for `-OverwriteTemplates`, but make its risk explicit and steer existing projects toward conservative migration planning.

## 2. Current Context
- Issue #33 asks for clear mode semantics before the later template and language-migration work.
- Issue #32 depends on this boundary because file-based `en` / `zh-CN` templates must be structural baselines, not overwrite permission.
- Issue #30 depends on both the safe operating model and the later file-based templates for conservative language migration.
- `skills/project-bootstrap/scripts/bootstrap_project.ps1` currently supports missing-template refresh, protected overwrite behavior, language scaffold refresh, and memory upgrade analyze/plan/apply modes.
- `-OverwriteTemplates` already preserves modified protected memory on existing projects, but its name and docs still imply a broad overwrite-style operation.

## 3. Goals
- Document the supported operating modes:
  - initialize empty project
  - refresh missing templates
  - refresh unmodified templates
  - conservative memory migration
  - explicit force reset
- Keep existing project memory out of overwrite behavior by default.
- Add an explicit force-reset path for destructive scaffold reset scenarios.
- Preserve backup-first behavior for any replacement path.
- Emit clear warnings for compatibility overwrite and explicit force reset paths.
- Update project-bootstrap docs, skill guidance, user-facing examples, and release validation coverage.

## 4. Non-Goals
- Do not implement #32 file-based `en` / `zh-CN` templates.
- Do not implement #30 conservative language migration between `en` and `zh-CN`.
- Do not remove `-OverwriteTemplates` without a compatibility path.
- Do not change the release version.
- Do not change repository rulesets, hooks, runner configuration, App auth, or main-branch protection.

## 5. Constraints
- Public docs, specs, scripts, and engineering memory remain English-first.
- Do not store private paths, automation identity material, or private overlay details in this repository.
- PowerShell scripts must remain compatible with Windows PowerShell 5.1.
- The PR must be issue-first, reference #33, and keep #30 / #32 explicitly out of scope.
- Do not push directly to `main`.

## 6. Assumptions
- Backward-compatible warning semantics are safer than immediately removing `-OverwriteTemplates`.
- Explicit `-ForceResetScaffold` can own the dangerous reset semantics without changing ordinary refresh behavior.
- Conservative language migration can be documented as a mode now, while implementation remains deferred to #30 after #32.

## 7. Risks
- Existing automation that uses `-OverwriteTemplates` may see new warning output.
- A force-reset flag could be misused if warnings are too weak or if backups are not clearly reported.
- Over-documenting future migration behavior could imply #30 is already implemented.

## 8. Proposed Approach
- Add a clear mode resolver in `bootstrap_project.ps1` and report the selected mode in output, lock metadata, and evidence when relevant.
- Treat `-OverwriteTemplates` as a deprecated compatibility refresh with explicit warning text.
- Add `-ForceResetScaffold` for explicit reset scenarios and make it incompatible with conservative memory upgrade modes.
- Keep existing modified protected memory preserved unless force reset is supplied.
- Keep backing up files before replacement and surface backup / evidence paths in output.
- Update `project-bootstrap` README and skill docs with mode-specific examples.
- Update release validation with fixtures for existing-memory preservation, compatibility overwrite warning, and force-reset backup behavior.

## 9. Acceptance / Evidence
- Issue #33 is referenced by the PR.
- Docs clearly distinguish empty initialization, missing-template refresh, unmodified-template refresh, conservative memory migration, and force reset.
- Existing project memory defaults to analyze/plan behavior and is not overwritten by ordinary bootstrap or compatibility overwrite.
- Any force reset or compatibility overwrite path emits an explicit warning.
- Replacement paths remain backup-first and report evidence.
- Existing-project examples use conservative migration language, not overwrite language.
- `git diff --check` passes.
- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1` passes.
- Skipped or unavailable checks must be recorded before completion.

Current evidence:
- `git diff --check` passed.
- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1` passed with `PASS=35 FAIL=0 WARN=0 DEFERRED=0`.

## 10. Loop Contract
- Not required. This is a bounded maintenance change.

## 11. Execution Contract
- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Re-read #33, #32, and #30; create this work package and branch from current `main`.
  - P02: Update bootstrap mode semantics, warnings, and safe reset behavior.
  - P03: Update docs, skill guidance, and release validation coverage.
  - P04: Validate, commit, push, and open a draft PR for #33.
- **Continue rule**: Continue while changes stay limited to #33 mode semantics, docs, validation, specs, and tracked public engineering memory.
- **Stop rule**: Stop for scope drift into #30 or #32 implementation, direct `main` pushes, ruleset/hooks/runner/App auth changes, sensitive material disclosure, destructive actions without backup-first behavior, skipped acceptance checks, or unresolved ambiguity about destructive semantics.
- **State record**: `docs/specs/bootstrap-operating-modes/tasks.md` and `.agents/plan.md`.

## 12. Open Questions
- None blocking. `-OverwriteTemplates` will remain as a compatibility alias with warnings; future removal can be a later issue if maintainers want a breaking cleanup.
