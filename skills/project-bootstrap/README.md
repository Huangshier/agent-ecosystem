# Project Bootstrap

Bootstrap and maintain project-level `.agents` structure from a shared knowledge hub.

## Main Files
- `SKILL.md`: workflow and usage entry
- `scripts/init_hub.ps1`: initialize global knowledge-hub template repo and minimal runtime scripts
- `scripts/bootstrap_project.ps1`: install/update project `.agents` scaffold; auto-initializes a missing hub template set from bundled assets
- `scripts/set_project_language.ps1`: write first-session project memory language scaffolds when an agent/workflow supplies the language
- `scripts/memory_upgrade.ps1`: analyze, plan, and apply legacy project memory upgrades
- `scripts/check_hub_lock.ps1`: compare project `hub.lock.json` against the installed hub git state
- `scripts/promote_experience.ps1`: compatibility copy; prefer `knowledge-hub/scripts/promote_experience.ps1` for routine hub maintenance
- `scripts/rebuild_experience_index.ps1`: compatibility copy used by hub initialization; prefer `knowledge-hub/scripts/rebuild_experience_index.ps1` after manual hub edits
- `templates/project-memory/en/`: English project memory templates used for language setup and fallback
- `templates/project-memory/zh-CN/`: Simplified Chinese project memory templates used for language setup
- `references/maintenance-model.md`: long-term maintenance model
- `assets/knowledge-hub-template/templates/project-root/`: root-level committed docs and scaffolds, including `docs/specs/_templates/`

## Lock Metadata
- `bootstrap_project.ps1` writes hub git metadata plus `template_tree_hash_sha256`.
- `init_hub.ps1` leaves the hub as an ordinary directory unless `-InitializeGit` or `-CommitInitial` is supplied.
- When `-ProjectLanguage` is supplied, the lock records the normalized project language.
- When language templates are missing, the lock records fallback warnings and paths; English is the fallback template language.
- `check_hub_lock.ps1` compares the template hash when present and fails on dirty hub state, so uncommitted hub changes are not treated as reproducible pins.

## Repository Role
- Source repository for the skill itself
- Upstream source for `knowledge-hub` aggregate sync
- Bootstrap does not own routine global experience promotion. It installs project scaffolds and upgrade helpers; the installed `knowledge-hub/scripts` directory is the runtime entrypoint for promoted experience.

## Legacy Memory Upgrade
- `bootstrap_project.ps1 -AnalyzeMemoryUpgrade` reports old memory issues without editing memory.
- `bootstrap_project.ps1 -PlanMemoryUpgrade` writes a reviewable proposal under `.agents/upgrade/`.
- `bootstrap_project.ps1 -ApplyMemoryUpgrade -UpgradePlan <path>` backs up and normalizes hot memory after review.
- `bootstrap_project.ps1 -AutoUpgrade` runs Analyze, then creates and applies the default proposal when the caller has explicitly approved memory normalization.
- When ordinary bootstrap detects memory upgrade candidates, the skill workflow decides whether to auto-upgrade, ask first, or skip based on the user's stated intent.

## Operating Modes
- Empty project initialization: default bootstrap writes missing scaffold files and optional first-session language scaffolds.
- Missing-template refresh: default bootstrap on an existing project copies only missing files and preserves local memory.
- Unmodified-template refresh: `-RefreshUnmodifiedTemplates` updates files that still match the prior installed template hash and preserves modified files for manual review.
- Compatibility overwrite: `-OverwriteTemplates` is retained as a warning-emitting alias for unmodified-template refresh. It is not a force reset.
- Conservative memory migration: use Analyze, Plan, and Apply memory upgrade modes with reviewable proposals and backups.
- Explicit force reset: `-ForceResetScaffold` is the only reset path for intentionally discarding scaffold customizations. It warns, backs up first, and cannot be combined with memory upgrade modes.

## Project Memory Templates
- `en` and `zh-CN` are the only first-class project memory template languages.
- English remains the public default and fallback language.
- Template files under `templates/project-memory/<language>/project-root/` map to project-root files such as `AGENTS.md` and `docs/specs/_templates/`.
- Template files under `templates/project-memory/<language>/project-agent/` map to `.agents/` files such as `.agents/AGENTS.md`, hot memory, context starters, and commands starters.
- The templates are structural baselines for scaffold generation, language updates, and future conservative migration planning. They do not authorize overwriting project-specialized memory.
