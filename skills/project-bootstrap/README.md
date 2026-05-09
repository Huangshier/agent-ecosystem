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
- `references/maintenance-model.md`: long-term maintenance model
- `assets/knowledge-hub-template/templates/project-root/`: root-level committed docs and scaffolds, including `docs/specs/_templates/`

## Lock Metadata
- `bootstrap_project.ps1` writes hub git metadata plus `template_tree_hash_sha256`.
- When `-ProjectLanguage` is supplied, the lock records the normalized project language.
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
