# Project Bootstrap

Bootstrap and maintain project-level `.agents` structure from a shared knowledge hub.

## Main Files
- `SKILL.md`: workflow and usage entry
- `scripts/init_hub.ps1`: initialize global knowledge-hub template repo and minimal runtime scripts
- `scripts/bootstrap_project.ps1`: install/update project `.agents` scaffold; auto-initializes a missing hub template set from bundled assets
- `scripts/set_project_language.ps1`: write first-session project memory language scaffolds when an agent/workflow supplies the language
- `scripts/language_migration.ps1`: analyze, plan, apply, and validate conservative `en` / `zh-CN` project memory language migration, including Phase 2 narrative proposals from manual-review artifacts
- `scripts/audit_memory_language.ps1`: read-only body-level project-memory language audit that ignores discovery metadata, fenced code, and protected literals before reporting heuristic findings
- `scripts/memory_upgrade.ps1`: analyze, plan, and apply legacy project memory upgrades
- `scripts/check_hub_lock.ps1`: compare project `hub.lock.json` against the installed hub git state
- `scripts/promote_experience.ps1`: compatibility copy; prefer `knowledge-hub/scripts/promote_experience.ps1` for routine hub maintenance
- `scripts/rebuild_experience_index.ps1`: compatibility copy used by hub initialization; prefer `knowledge-hub/scripts/rebuild_experience_index.ps1` after manual hub edits
- `assets/knowledge-hub-template/templates/languages/en/`: bundled English project memory template snapshot used for default bootstrap, language setup, and fallback
- `assets/knowledge-hub-template/templates/languages/zh-CN/`: bundled Simplified Chinese project memory template snapshot used for language setup
- `references/maintenance-model.md`: long-term maintenance model
- `assets/knowledge-hub-template/templates/languages/<language>/project-root/`: root-level committed docs and scaffolds, including `docs/specs/_templates/`

## Lock Metadata
- `bootstrap_project.ps1` writes hub git metadata plus `template_tree_hash_sha256`.
- `init_hub.ps1` leaves the hub as an ordinary directory unless `-InitializeGit` or `-CommitInitial` is supplied.
- The lock records the normalized project language; plain bootstrap records `en`.
- When language templates are missing, the lock records fallback warnings and paths; English is the fallback template language.
- `check_hub_lock.ps1` compares the template hash when present and fails on dirty hub state, so uncommitted hub changes are not treated as reproducible pins.

## Repository Role
- Source repository for the skill itself
- Upstream source for `knowledge-hub` aggregate sync
- Bootstrap does not own routine global experience promotion. It installs project scaffolds and upgrade helpers; the installed `knowledge-hub/scripts` directory is the runtime entrypoint for promoted experience.

## Legacy Memory Upgrade
- `memory_upgrade.ps1 -Mode Analyze` is the strict no-edit memory-only
  analysis path.
- `bootstrap_project.ps1 -AnalyzeMemoryUpgrade` reports old memory issues
  without editing memory files, but it is a wrapper flow: it may first refresh
  missing scaffold files or `.agents/hub.lock.json`.
- `bootstrap_project.ps1 -PlanMemoryUpgrade` writes a reviewable proposal under `.agents/upgrade/`.
- `bootstrap_project.ps1 -ApplyMemoryUpgrade -UpgradePlan <path>` backs up and normalizes hot memory after review.
- `bootstrap_project.ps1 -AutoUpgrade` runs Analyze, then creates and applies the default proposal when the caller has explicitly approved memory normalization.
- When ordinary bootstrap detects memory upgrade candidates, the skill workflow decides whether to auto-upgrade, ask first, or skip based on the user's stated intent.
- For existing projects moving to the post-`v0.4.2` template model, see
  `docs/existing-project-upgrade.md` before applying changes.

## Conservative Language Migration
- `language_migration.ps1 -Mode Analyze -SourceLanguage en -TargetLanguage zh-CN` reports planned actions without editing memory.
- `language_migration.ps1 -Mode Plan -SourceLanguage en -TargetLanguage zh-CN` writes a reviewable proposal under `.agents/language-migration/` and creates a backup under `.agents/_backup/language-migration-<timestamp>/`.
- `language_migration.ps1 -Mode Apply -MigrationPlan <proposal.json>` requires the proposal and recorded backup, refuses changed source hashes, and applies only approved actions.
- `language_migration.ps1 -Mode Validate -MigrationPlan <proposal.json>` checks result metadata, backup presence, migration metadata, per-action output hashes, and manual-review source hash records.
- `language_migration.ps1 -Mode PlanNarrative -MigrationPlan <proposal.json>` reads Phase 1 `.agents/language-migration/<timestamp>/manual-review/` artifacts and writes a second, unapproved-by-default narrative proposal.
- `language_migration.ps1 -Mode ApplyNarrative -MigrationPlan <narrative-proposal.json>` applies only reviewed narrative actions after checking the proposal, backup, source artifact hashes, and target file hashes.
- `language_migration.ps1 -Mode ValidateNarrative -MigrationPlan <narrative-proposal.json>` validates the narrative result, source artifacts, backup, and review markers.
- The same flow supports `zh-CN` to `en` by reversing `SourceLanguage` and `TargetLanguage`.
- Target language templates are structural baselines. Customized project content is preserved verbatim, merged into a manual-review section, routed to a manual-review artifact for concise hot memory, or left unchanged for manual review. The narrative phase creates deterministic translation drafts for ordinary prose, routes stable facts, active plan, process state, reusable lessons, and durable specs to the right memory surfaces, and still requires review before apply.
- Run `audit_memory_language.ps1 -ProjectDir <project> -ExpectedLanguage zh-CN -IncludeSpecs -IncludeCommands -Json` when review needs a standalone body-level audit. The helper is read-only and reports warning-level findings; it does not translate, rewrite, or approve memory changes.

## Operating Modes
- Empty project initialization: default bootstrap writes missing scaffold files and optional first-session language scaffolds.
- Missing-template refresh: default bootstrap on an existing project copies only missing files and preserves local memory. For existing non-English projects, read `.agents/AGENTS.md` or `.agents/hub.lock.json` and pass the current project language explicitly.
- Unmodified-template refresh: `-RefreshUnmodifiedTemplates` updates files that still match the prior installed template hash and preserves modified files for manual review.
- Compatibility overwrite: `-OverwriteTemplates` is retained as a warning-emitting alias for unmodified-template refresh. It is not a force reset.
- Conservative memory migration: use Analyze, Plan, Apply, and Validate modes with reviewable proposals and backups. Use legacy memory upgrade modes for layout normalization, and language migration modes for `en` / `zh-CN` project memory language changes.
- Explicit force reset: `-ForceResetScaffold` is the only reset path for intentionally discarding scaffold customizations. It warns, backs up first, and cannot be combined with memory upgrade modes.

## Project Memory Templates
- `en` and `zh-CN` are the only first-class project memory template languages.
- English remains the public default and fallback language. Plain bootstrap is equivalent to `-ProjectLanguage en`.
- The bootstrap helper does not infer project memory language from chat. Agents
  and workflows should pass `-ProjectLanguage` from project rules or existing
  lock metadata when refreshing or analyzing established projects.
- The authoritative source lives under `knowledge-hub/templates/languages/<language>/project-root|project-agent/`.
- The bundled runtime snapshot lives under `assets/knowledge-hub-template/templates/languages/<language>/project-root|project-agent/`.
- Template files under `assets/knowledge-hub-template/templates/languages/<language>/project-root/` map to project-root files such as `AGENTS.md` and `docs/specs/_templates/`.
- Template files under `assets/knowledge-hub-template/templates/languages/<language>/project-agent/` map to `.agents/` files such as `.agents/AGENTS.md`, hot memory, context starters, and commands starters.
- The templates are structural baselines for scaffold generation, language updates, and future conservative migration planning. They do not authorize overwriting project-specialized memory.
- Conservative language migration uses these templates to replace exact source-template matches and to frame customized content for manual review without dropping it.
