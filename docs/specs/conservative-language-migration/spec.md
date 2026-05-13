# Work Spec

- **Title**: Conservative Language Migration
- **Slug**: conservative-language-migration
- **Status**: Active
- **Owner**: Maintainer + agent
- **Updated**: 2026-05-13

> Historical note: this work package predates the `v0.4.2` language-scoped
> template model. References to `skills/project-bootstrap/templates/project-memory/`
> are legacy history, not current public template guidance.

## 1. Summary
- Implement issue #30 by adding a conservative `en` / `zh-CN` project-memory
  migration workflow.
- The workflow must be proposal-first and backup-first, using file-based target
  language templates as structural baselines without overwriting
  project-specialized memory.
- PR #46 completed Phase 1: deterministic conservative migration scaffold,
  backup/proposal/apply/validate flow, and manual-review routing.
- The current follow-up implements Phase 2: narrative migration from retained
  manual-review artifacts back into target-language engineering memory.

## 2. Current Context
- Issue #33 is complete via PR #40: `project-bootstrap` operating modes now
  distinguish safe refresh, conservative migration, and explicit force reset.
- Issue #32 is complete via PR #41: file-based `en` and `zh-CN` project-memory
  templates are available under `skills/project-bootstrap/templates/project-memory/`.
- Issue #44 is complete via PR #45: base AGENTS templates include project
  commands, large-issue planning / PR split guidance, PR-ready memory sync, and
  no post-PR memory-only commit guidance.
- `memory_upgrade.ps1` already supports legacy hot-memory normalization, but it
  is not a bilingual language migration tool.
- `set_project_language.ps1` can write first-session scaffolds from language
  templates, but established project memory must not be treated as a scaffold
  overwrite.
- PR #46 merged on 2026-05-13 at
  `ee327e75aa35bd38c7495a019eaa932f4f9395f2`; #30 remains open for Phase 2
  narrative migration.

## 3. Goals
- Support conservative migration from `en` to `zh-CN`.
- Support conservative migration from `zh-CN` to `en`.
- Provide analyze, plan, reviewable proposal, apply, and validate modes.
- Create a backup before any apply path can write project memory.
- Use target language templates as structural baselines.
- Preserve commands, paths, API names, filenames, commit types, raw errors, and
  code symbols in their original form.
- Preserve project-specific content by keeping it unchanged, merging it into a
  target-language scaffold with explicit manual-review routing, or marking it
  for manual review in the proposal.
- Read Phase 1 `.agents/language-migration/<timestamp>/manual-review/`
  artifacts and generate a second narrative proposal.
- Route stable facts, active plan, process state, reusable lessons, and durable
  specs back to the appropriate target-language engineering-memory surfaces.
- Apply narrative output only after review, backup, source hash checks, and
  target hash checks.
- Add release-validation fixtures for both directions, mixed memory,
  project-specific preservation, untranslated command/path/API/error text, and
  proposal/backup requirements before apply.

## 4. Non-Goals
- Do not support arbitrary-language i18n beyond `en` and `zh-CN`.
- Do not claim perfect unattended translation for project-specific narrative.
- Do not use target language templates to discard customized project memory.
- Do not change repository rulesets, hooks, runners, GitHub App auth, release
  versioning, or main-branch protection.
- Do not store private overlay details, local machine paths, or sensitive audit
  material in this public repository.

## 5. Constraints
- Public repository docs, specs, and engineering memory stay English-first.
- PowerShell scripts must remain compatible with Windows PowerShell 5.1.
- The migration result must be deterministic and reviewable without network or
  AI translation services.
- Project-specific content that cannot be safely translated deterministically
  must be preserved and routed to manual review instead of being dropped.
- Narrative migration may draft conservative target-language prose for ordinary
  narrative text, but actions remain unapproved by default and must be reviewed
  before apply.
- Hot memory updates must stay concise; long source content remains in
  proposal/manual-review artifacts or durable memory surfaces.
- Scope control: do not include unrelated refactors, cleanup, or behavior
  changes outside #30.

## 6. Assumptions
- A first reviewable PR can deliver the deterministic conservative migration
  scaffold for #30 if it documents the manual-review boundary and validates the
  required safety properties.
- Known scaffold/template text can be migrated by replacing matching source
  templates with the corresponding target template.
- Customized files can be migrated conservatively by keeping target-language
  structural scaffolding where available and preserving the original
  project-specific body in a manual-review section or migration artifact.
- A deterministic phrase-level narrative draft is useful as a review starting
  point, but not sufficient as unattended translation.

## 7. Risks
- A deterministic helper may be mistaken for full automatic translation if docs
  are not explicit.
- Merging custom content into target-language scaffolds may create files that
  still need human language cleanup.
- Scanning `docs/specs/**` and `.agents/context/**` can find many files; the
  proposal must stay concise while retaining enough detail for review.
- Narrative proposal actions could re-inflate hot memory if they copy whole
  source artifacts; hot-memory proposals must be concise and backed by durable
  artifacts.

## 8. Proposed Approach
- Add `skills/project-bootstrap/scripts/language_migration.ps1` with
  `Analyze`, `Plan`, `Apply`, and `Validate` modes.
- Add `bootstrap_project.ps1` switches that route to the language migration
  helper:
  - `-AnalyzeLanguageMigration`
  - `-PlanLanguageMigration`
  - `-ApplyLanguageMigration -MigrationPlan <path>`
  - `-ValidateLanguageMigration -MigrationPlan <path>`
  - `-SourceLanguage en|zh-CN`
  - `-TargetLanguage en|zh-CN`
- Plan mode writes `.agents/language-migration/<timestamp>/proposal.json` and
  `proposal.md`, and creates `.agents/_backup/language-migration-<timestamp>/`
  before apply can run.
- Apply mode requires a proposal path, verifies the recorded backup exists, and
  refuses to write if source file hashes changed since the proposal.
- For exact source-template matches, apply writes the target template.
- For customized files with a target template, apply writes the target template
  plus a clearly labeled project-specific source-content manual-review section.
- For customized hot memory files, apply writes the concise target template and
  routes the original source content to a manual-review artifact under
  `.agents/language-migration/`.
- For files without a target template, apply preserves the file unchanged and
  records manual review.
- Apply and Validate reject a proposal whose recorded project path differs from
  the current `-ProjectDir`.
- Validate mode checks proposal/result/backup metadata, per-action output
  hashes, manual-review source hash records, and verifies that project language
  metadata was updated to the target language after apply.
- Narrative plan mode reads retained manual-review artifacts and writes
  `.agents/language-migration/<timestamp>/narrative-proposal.json` with actions
  unapproved by default.
- Narrative apply mode checks the narrative proposal, backup, source artifact
  hashes, and current target file hashes before writing reviewed narrative
  sections.
- Narrative validation checks result metadata, source artifacts, backup, target
  review markers, and source hash records.
- Narrative routing maps stable facts to durable technical context, active
  plan/process state to concise hot memory updates, reusable lessons to
  `.agents/context/experience/`, and durable specs to `docs/specs/`.
- Extend release validation with fixture projects for both directions and the
  safety invariants requested by #30.

## 9. Acceptance / Evidence
- `git diff --check` passed on 2026-05-13.
- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-release.ps1`
  passed on 2026-05-13 with `PASS=40 FAIL=0 WARN=0 DEFERRED=0`.
- Fixture coverage includes:
  - `en` project memory to `zh-CN` conservative migration.
  - `zh-CN` project memory to `en` conservative migration.
  - Mixed memory and project-specific content preservation.
  - Read-only analyze through the bootstrap wrapper.
  - Project path mismatch rejection for Apply and Validate.
  - Concise hot memory with source content routed to manual-review artifacts.
  - Per-action validation for template writes, manual-review source hashes,
    preserved files, result actions, and backups.
  - Commands, paths, API names, filenames, commit types, raw errors, and code
    symbols remain unchanged.
  - Apply requires an existing proposal and backup.
  - Phase 2 narrative proposal/apply/validate reads manual-review artifacts,
    covers stable facts, active plan, process state, reusable lessons, and
    durable specs, and keeps protected literals unchanged.
- PR body links #30, notes dependencies on #33/#32/#44, and states that this is
  a deterministic conservative scaffold with manual-review routing, not
  unattended translation of project-specific narrative.
- Skipped or unavailable checks must be recorded before completion.

Current evidence:
- Local smoke fixture for `language_migration.ps1` passed before release
  validation.
- Full release validation includes a `conservative language migration` check
  covering both migration directions, mixed memory, project-specific
  preservation, read-only analyze, project path mismatch rejection, hot memory
  artifact routing, per-action validation, proposal-first apply, and
  backup-first apply.
- PR #46 blocking concerns were addressed on 2026-05-13 and revalidated with
  `git diff --check` plus `scripts/validate-release.ps1` reporting
  `PASS=40 FAIL=0 WARN=0 DEFERRED=0`.
- Phase 2 validation evidence will be recorded after the new narrative
  fixtures pass on this branch.
- Phase 2 validation passed on 2026-05-13 with `git diff --check` and
  `scripts/validate-release.ps1` reporting
  `PASS=40 FAIL=0 WARN=0 DEFERRED=0`.

## 10. Loop Contract
- Not required. This is a bounded implementation and validation change.

## 11. Execution Contract
- **Autonomy level**: bounded-autonomous
- **Phase list**:
  - P01: Sync `main`, read #30/#32/#33/#44 issues, PRs, and implementation;
    decide PR split and create this work package.
  - P02: Implement deterministic conservative migration helper and bootstrap
    routing.
  - P03: Update docs, skill guidance, and validation fixtures.
  - P04: Run validation, sync public engineering memory, commit, push, and open
    a draft PR for #30.
  - P05: Implement narrative migration from Phase 1 manual-review artifacts,
    update docs/fixtures/memory, commit, push, and open a draft PR.
- **Continue rule**: Continue while changes stay within #30, remain
  deterministic and backup/proposal-first, and required validations are
  available.
- **Stop rule**: Stop for arbitrary-language i18n scope, claims of perfect
  automatic translation, destructive writes without proposal and backup,
  direct `main` pushes, ruleset/hooks/runner/App-auth changes, private material
  disclosure, skipped acceptance checks, or unresolved ambiguity.
- **State record**: `docs/specs/conservative-language-migration/tasks.md`,
  `.agents/plan.md`, and `.agents/process.txt`.

## 12. Open Questions
- None blocking. The PR will document that project-specific narrative is
  preserved and routed to manual review instead of automatically translated.
