# Work Spec

- **Title**: File-Based Memory Templates
- **Slug**: file-based-memory-templates
- **Status**: Active
- **Owner**: Maintainer + agent
- **Updated**: 2026-05-13

> Historical note: this closed work package predates the `v0.4.2`
> language-scoped template model. References to
> `skills/project-bootstrap/templates/project-memory/` are legacy history, not
> current public template guidance.

## 1. Summary
- Add file-based `en` and `zh-CN` engineering-memory templates for project bootstrap.
- Make those templates the structural source for scaffold generation, language updates, and future conservative migration planning.
- Keep the public repository English-first and keep English as the fallback language.

## 2. Current Context
- Issue #33 is complete via PR #40, merged at `19656e5f92264a960c8e6ac6039debd97166c10f`.
- Issue #32 is accepted for this implementation pass.
- Issue #30 remains open and is not implemented in this PR.
- `bootstrap_project.ps1` already copies default scaffold files from hub templates and preserves existing project memory by default.
- `set_project_language.ps1` now loads `en` and `zh-CN` scaffolds from tracked template files.
- Release validation checks first-session language scaffold output for both `en` and `zh-CN`, file-template coverage, and missing `zh-CN` file fallback.

## 3. Goals
- Add tracked file templates for `en` and `zh-CN` covering root `AGENTS.md`, `.agents/AGENTS.md`, hot memory files, context/commands starter files, and spec templates.
- Update project-bootstrap language setup to load templates from files instead of embedded scaffold strings.
- Keep missing-file behavior conservative: existing project-specific memory is not overwritten unless the caller explicitly requests scaffold overwrite/reset behavior.
- Fall back from missing `zh-CN` template files to `en` with an explicit warning or validation finding.
- Extend release validation to cover `en` and `zh-CN` scaffold generation from the file templates.

## 4. Non-Goals
- Do not implement #30 conservative migration apply flow.
- Do not add arbitrary-language i18n or languages beyond `en` and `zh-CN`.
- Do not change release version, repository rulesets, hooks, runners, GitHub App auth, or main-branch protection.
- Do not store private local machine details, automation auth material, or private overlay information.
- Do not use generic templates to overwrite existing project-specialized memory.

## 5. Constraints
- Public-facing repository artifacts stay English-first unless they are explicit `zh-CN` templates or translations.
- PowerShell scripts must remain compatible with Windows PowerShell 5.1.
- Non-ASCII PowerShell scripts must retain UTF-8 with BOM compatibility where required by release validation.
- The new template layout should be reviewable as ordinary files and easy to compare across `en` and `zh-CN`.

## 6. Assumptions
- The existing hub template layout remains the source for default English bootstrap when `-ProjectLanguage` is not supplied.
- First-session `-ProjectLanguage` remains the supported way to request localized engineering-memory scaffolds.
- Future #30 migration work can reuse the new template resolver as its structural baseline without applying migration in this PR.

## 7. Risks
- Moving embedded strings into files can accidentally change scaffold text.
- Missing-template fallback can hide incomplete `zh-CN` coverage if warnings are not validated.
- Release validation may need focused fixture coverage so regressions are caught without adding slow or brittle checks.

## 8. Proposed Approach
- Add `skills/project-bootstrap/templates/project-memory/<language>/project-root` and `project-agent` trees.
- Put English and Simplified Chinese versions of root guidance, agent guidance, hot memory files, context/commands starter files, and spec templates under that tree.
- Replace embedded scaffold builders in `set_project_language.ps1` with a file-template resolver that reads the requested language and falls back per missing file to `en`.
- Return warning metadata from `set_project_language.ps1` so callers and validation can surface fallback behavior.
- Update docs and release validation to describe and verify the supported `en` / `zh-CN` template source.

## 9. Acceptance / Evidence
- `git diff --check` passed on 2026-05-13.
- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1` passed on 2026-05-13 with `PASS=37 FAIL=0 WARN=0 DEFERRED=0`.
- Release validation covers `en` and `zh-CN` scaffold generation.
- Fallback from a missing `zh-CN` template file to `en` is covered by validation finding metadata.
- PR body says `Fixes #32`, `Depends on #33`, notes that #30 conservative migration is out of scope, and notes that arbitrary-language i18n is unsupported.

## 11. Execution Contract
- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Sync `main`, confirm #33/#32/#30 state, and create this work package.
  - P02: Add file-based `en` / `zh-CN` templates and update language setup to read them.
  - P03: Update docs and release validation for scaffold generation and fallback behavior.
  - P04: Run required validation, sync memory, commit, push, and open a draft PR.
- **Continue rule**: Continue while changes stay within #32, validations are deterministic, and no external high-impact setting changes are needed.
- **Stop rule**: Stop for #30 migration apply work, arbitrary-language i18n scope, release/version/ruleset/hook/runner/App-auth/main-protection changes, missing access, destructive actions, or unresolved ambiguity.
- **State record**: `docs/specs/file-based-memory-templates/tasks.md`, `.agents/plan.md`, and `.agents/process.txt`.

## 12. Open Questions
- None currently blocking.
