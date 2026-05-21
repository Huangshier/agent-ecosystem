# Work Spec

- **Title**: Memory Language Migration Review Flow
- **Slug**: memory-language-migration-review-flow
- **Status**: Active
- **Owner**: Codex
- **Updated**: 2026-05-22

## 1. Summary
- Implement the #79-B workflow and validation behavior for project-memory
  language migration after #67 and #79-A.
- Make the normal migration path template replacement plus reviewed
  target-language narrative, while preserving protected literals and using the
  body-level audit helper to reject residual source-language body text.

## 2. Current Context
- Public `main` includes #67 via PR #84 and #79-A via PR #85.
- `skills/project-bootstrap/scripts/language_migration.ps1` already supports
  proposal-first migration, backup-first apply, Phase 1 manual-review
  artifacts, Phase 2 narrative proposals, and narrative validation.
- `skills/project-bootstrap/scripts/audit_memory_language.ps1` provides the
  read-only body-level language audit needed for completion validation.
- The remaining gap is default semantics: ordinary language migration still
  routes too much project-specific body text to manual review, and validation
  can pass while body-level source-language text remains.

## 3. Goals
- Treat ordinary project-specific narrative as reviewed migration content, not
  default manual-review completion.
- Keep template replacement, backups, proposal review, source hash checks, and
  apply safety.
- Preserve protected literals, including commands, paths, APIs, filenames,
  commit types, raw errors, and code symbols.
- Use the #67 audit helper during validation so migrations with leftover
  source-language narrative do not claim completion.
- Keep manual-review artifacts for exceptional or uncertain routing.
- Extend release validation fixtures for both migration directions.

## 4. Non-Goals
- Do not claim perfect unattended translation.
- Do not support arbitrary languages beyond `en` and `zh-CN`.
- Do not change tags, releases, repository settings, rulesets, sensitive
  repository configuration, branch protection, or default profile expansion.
- Do not merge a PR or push directly to `main`.

## 5. Constraints
- Public repository project memory language is English.
- Root `.agents/` remains local runtime memory and untracked.
- Private report content is read-only evidence and must not be copied as
  private local path or private state into public artifacts.
- PowerShell scripts must remain compatible with Windows PowerShell 5.1.

## 6. Assumptions
- A deterministic proposal plus reviewer-approved `proposed_target_text` is the
  right script boundary for translation support.
- The release validator can simulate reviewer approval by editing generated
  proposal JSON with target-language fixture text.
- Body-level audit findings should fail migration validation until resolved,
  except for manual-review-only exception paths outside applied narrative.

## 7. Risks
- A heuristic audit can false-positive on technical prose; protected literal
  stripping must remain part of the helper and validation evidence.
- Existing two-phase migration behavior should stay compatible for callers that
  explicitly use manual-review artifacts.
- Over-automating translation could mislead users; docs must keep review
  responsibility explicit.

## 8. Proposed Approach
- Add validation support that invokes `audit_memory_language.ps1` from
  language migration validation and narrative validation.
- Add result/proposal metadata that distinguishes applied narrative, skipped
  unapproved narrative, and manual-review-only exception routing.
- Tighten narrative validation so approved narrative actions require
  target-language body text according to the audit helper.
- Update release validation fixtures to exercise reviewer-edited target
  narrative and to prove source-language leftovers fail audit validation.
- Update project-bootstrap docs and the active spec/task evidence.

## 9. Acceptance / Evidence
- `language_migration.ps1 -Mode Validate` and `-Mode ValidateNarrative` include
  body-level audit evidence.
- A fixture with source-language narrative left in project memory fails
  validation.
- A fixture with reviewed target-language narrative passes validation.
- Protected literals remain unchanged in migrated output.
- Manual-review-only routing remains available as an exception path.
- `git diff --check` passes.
- `scripts/validate-release.ps1` passes locally.
- Hosted PR checks pass before merge recommendation.

Current evidence:
- `git diff --check` passed.
- `scripts/validate-release.ps1 -ScratchRoot "$env:TEMP\agent-ecosystem-79b-validation-r5"`
  passed with `PASS=50 FAIL=0 WARN=0 DEFERRED=0`.

## 10. Loop Contract
- Not applicable.

## 11. Execution Contract
- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Confirm synced public main, #67 merge status, and create this work
    package.
  - P02: Patch workflow validation and docs.
  - P03: Run local validation, commit, push, open PR, and wait for hosted
    checks.
- **Continue rule**: Continue while changes stay within #79-B workflow and
  validation scope, validation failures are understood, and no protected
  repository actions are needed.
- **Stop rule**: Stop for skipped acceptance checks, private data exposure,
  destructive actions, direct `main` pushes, merge requests, repository setting
  changes, or unresolved safety ambiguity.
- **State record**: This spec and `tasks.md`; PR and hosted-check state belongs
  in PR metadata and final handoff, not durable specs.

## 12. Open Questions
- None.
