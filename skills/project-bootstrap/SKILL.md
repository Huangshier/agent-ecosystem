---
name: project-bootstrap
description: Initialize and maintain project-level `.agents` memory scaffolds from a global git-tracked knowledge hub at `%USERPROFILE%\\.agents\\knowledge-hub`. Use when creating a new project scaffold, refreshing shared templates with a pinned lock file (`.agents/hub.lock.json`), or standardizing cross-project AGENTS/context/plan/process/notes structures.
category: kernel
stability: stable
scope: cross-project
---

# Agent Project Bootstrap

## Workflow

1. Ensure the global knowledge hub exists.
2. Install or refresh templates into the target project.
3. Write `.agents/hub.lock.json` with the pinned hub commit.
4. Keep project-local files as higher-priority overrides by default.

Command examples use Windows PowerShell 5.1-compatible invocation. On
non-Windows systems, or when PowerShell 7+ is already available, replace
`powershell -NoProfile -ExecutionPolicy Bypass -File` with
`pwsh -NoProfile -File`.

## Step 1: Initialize Global Hub

Run the initialization script when `%USERPROFILE%\\.agents\\knowledge-hub` is missing or when you want to refresh hub templates from this skill's assets.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/init_hub.ps1
```

Optional flags:
- `-HubDir <path>`: custom hub location.
- `-Overwrite`: replace existing hub template files.
- `-InitializeGit`: initialize the hub directory as a Git repository without committing.
- `-CommitInitial`: attempt an initial git commit after sync.

Notes:
- `init_hub.ps1` rebuilds `knowledge/experience/index.json` after syncing templates so an overwrite refresh does not leave the installed hub with a stale or empty registry.
- `init_hub.ps1` also syncs the minimal hub runtime scripts for experience promotion and index rebuild from the bootstrap compatibility copies.
- `init_hub.ps1` does not create `.git` by default. Use `-InitializeGit` or `-CommitInitial` only when the target hub should be an independent Git repository.

## Step 2: Bootstrap a Project

Run the project bootstrap script from any location:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/bootstrap_project.ps1 -ProjectDir <project_path>
```

Default behavior:
- If the configured hub is missing its template folders, bootstrap first attempts to initialize it from bundled bootstrap assets.
- Copy template files only when missing.
- Keep project-local edits untouched.
- Write/refresh `.agents/hub.lock.json` with the current hub commit.
- Run a read-only legacy memory analysis and print a short upgrade hint only when candidates are detected.
- Record the installed template tree hash and whether the hub worktree was dirty at install time.
- Install the shared `Global Experience Use` guidance from the hub template so projects know when to search the global experience index and when to keep lessons local.
- Install the full `templates/project-root/` tree, not only root `AGENTS.md`, so long-lived project docs like `docs/specs/_templates/` can be scaffolded safely.
- When `-ProjectLanguage` is supplied, write first-session language scaffolds for hot memory, `.agents/context/`, `.agents/commands/`, and `docs/specs/`.
- Language scaffolds are loaded from `skills/project-bootstrap/templates/project-memory/<language>/`.
- Supported project memory template languages are `en` and `zh-CN` only. English remains the default and fallback.
- If a `zh-CN` template file is missing, the language helper falls back to the matching English template and reports fallback metadata. Treat that as a validation finding to fix, not as a reason to overwrite project-specific memory.

Optional flags:
- `-HubDir <path>`: custom hub location.
- `-RefreshUnmodifiedTemplates`: refresh files that still match the previously installed template hash; preserve modified files for manual review.
- `-OverwriteTemplates`: compatibility alias for `-RefreshUnmodifiedTemplates`. It emits a warning and does not overwrite modified project memory.
- `-ForceResetScaffold`: explicit reset path for discarding scaffold customizations. It emits a warning, backs up existing files first, and cannot be combined with memory upgrade modes.
- `-AnalyzeMemoryUpgrade`: after bootstrap, inspect legacy `.agents` memory and report issues without changing memory.
- `-PlanMemoryUpgrade`: generate a reviewable `.agents/upgrade/<timestamp>/proposal.md`.
- `-ApplyMemoryUpgrade -UpgradePlan <path>`: after user review, back up and normalize hot memory files according to the proposal.
- `-AutoUpgrade`: when the caller has explicitly approved memory normalization, analyze candidates, create the default proposal, apply it, and print the proposal, backup, and result paths.
- `-AnalyzeLanguageMigration -SourceLanguage en|zh-CN -TargetLanguage en|zh-CN`: inspect existing project memory for conservative language migration without editing memory.
- `-PlanLanguageMigration -SourceLanguage en|zh-CN -TargetLanguage en|zh-CN`: write a reviewable language migration proposal and create the required backup before apply.
- `-ApplyLanguageMigration -MigrationPlan <proposal.json>`: apply approved language migration actions after review, requiring the proposal and recorded backup.
- `-ValidateLanguageMigration -MigrationPlan <proposal.json>`: validate result metadata, backup presence, migration metadata, per-action output hashes, and manual-review source hash records.
- `-SkipMemoryUpgradeAnalysis`: skip the default read-only legacy memory check.
- `-ProjectLanguage en|zh-CN`: explicitly set the project memory language during bootstrap. The agent or workflow supplies the user's primary language; the script does not infer chat language.

Operating modes:
- Initialize empty project: run bootstrap on a project without existing `AGENTS.md` or `.agents` memory. Missing templates and first-session language scaffolds may be written.
- Refresh missing templates: default for existing projects. Missing files are copied, existing files are preserved, and memory analysis remains read-only unless another mode is requested.
- Refresh unmodified templates: use `-RefreshUnmodifiedTemplates` when the lock has prior template hashes. Files that still match the previous installed hash may be updated; modified files are preserved for manual review.
- Conservative memory migration: use proposal-first and backup-first modes after review. Use `-AnalyzeMemoryUpgrade`, `-PlanMemoryUpgrade`, then `-ApplyMemoryUpgrade -UpgradePlan <path>` for legacy memory layout normalization. Use `-AnalyzeLanguageMigration`, `-PlanLanguageMigration`, `-ApplyLanguageMigration -MigrationPlan <path>`, then `-ValidateLanguageMigration -MigrationPlan <path>` for `en` / `zh-CN` language migration.
- Explicit force reset: use `-ForceResetScaffold` only when the caller intentionally discards scaffold customizations. This is not a language migration path and remains backup-first.

Standalone language update:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/set_project_language.ps1 -ProjectDir <project_path> -ProjectLanguage zh-CN -OverwriteScaffold
```

Use `-OverwriteScaffold` only for bootstrap-era scaffolds or intentional reset scenarios. It backs up existing files before rewriting initial memory scaffold files. For established project memory, use conservative migration instead of treating language selection as scaffold overwrite.

The standalone helper reads file templates from
`skills/project-bootstrap/templates/project-memory/` by default. `-TemplateRoot`
is available for validation fixtures and controlled template-source tests.

## Step 2.5: Memory Upgrade Decision

When bootstrap reports `Memory upgrade candidates detected: N`, do not silently ignore it.

- If the user's request explicitly includes memory cleanup, organization, normalization, or upgrade, rerun bootstrap with `-AutoUpgrade` or run the manual `-PlanMemoryUpgrade` and `-ApplyMemoryUpgrade` flow after reviewing the proposal.
- If the user's request only asked for project bootstrap or reinitialization in an existing project, tell the user candidates were detected and ask before applying memory rewrites. Do not interpret reinitialization as force reset.
- If the user explicitly says not to upgrade memory, skip the upgrade and use `-SkipMemoryUpgradeAnalysis` on repeated bootstrap runs when the reminder would add noise.
- If no candidates are detected, or `-SkipMemoryUpgradeAnalysis` was intentionally supplied, continue to verification.

`-AutoUpgrade` is for non-interactive, caller-approved upgrades. It preserves the proposal-first and backup-first safety model by writing `.agents/upgrade/<timestamp>/proposal.md`, applying the checked default actions, and writing a result file next to the proposal.

## Step 3: Verify Installation

Check these paths:

- `<project>/AGENTS.md`
- `<project>/docs/specs/_templates/` (if present in the installed hub)
- `<project>/.agents/AGENTS.md`
- `<project>/.agents/context/`
- `<project>/.agents/hub.lock.json`

If needed, review `references/maintenance-model.md` for long-term update rules.

## Step 4: Validate Hub Lock Drift

Check whether a project's pinned `hub.lock.json` still matches the currently installed hub:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check_hub_lock.ps1 -ProjectDir <project_path>
```

Behavior:
- Reads `<project>/.agents/hub.lock.json`
- Resolves the hub directory from the lock or `-HubDir`
- Compares locked `hub_remote`, `hub_branch`, `hub_commit`, and `template_tree_hash_sha256` against the installed hub state when those fields are present
- Exits non-zero when drift, dirty hub state, or an invalid lock/hub setup is detected

Optional flags:
- `-ProjectDir <path1>,<path2>,...`: check more than one project in one run
- `-HubDir <path>`: compare against a specific installed hub instead of the lock's `hub_dir`

## Step 5: Upgrade Legacy Project Memory

Use this when re-running bootstrap in a project that already has old `.agents` memory.

Recommended flow:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -AnalyzeMemoryUpgrade
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -PlanMemoryUpgrade
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -ApplyMemoryUpgrade -UpgradePlan <proposal_path>
```

Caller-approved non-interactive flow:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -AutoUpgrade
```

Behavior:
- Analyze mode is read-only.
- Plan mode writes a proposal for user review.
- Apply mode requires a proposal path, backs up current memory under `.agents/_backup/<timestamp>/`, and normalizes hot memory (`process.txt`, `plan.md`, `notes.md`).
- Auto-upgrade mode runs Analyze first, then Plan and Apply only when findings exist.
- Durable multi-stage work should move into `docs/specs/`; `.agents` remains session-local.

## Step 6: Migrate Project Memory Language

Use this when an established project needs to move between the two supported
engineering-memory template languages without discarding project-specific
memory.

English to Simplified Chinese:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -AnalyzeLanguageMigration -SourceLanguage en -TargetLanguage zh-CN
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -PlanLanguageMigration -SourceLanguage en -TargetLanguage zh-CN
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -ApplyLanguageMigration -MigrationPlan <proposal.json>
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -ValidateLanguageMigration -MigrationPlan <proposal.json>
```

Simplified Chinese to English reverses the source and target languages.

Behavior:
- Analyze mode is read-only.
- Plan mode writes `.agents/language-migration/<timestamp>/proposal.json` and
  `proposal.md`, and creates `.agents/_backup/language-migration-<timestamp>/`.
- Apply mode requires the proposal and recorded backup, then refuses to write if
  a planned source file changed after planning.
- Exact source-template matches are replaced with target-language templates.
- Customized project content is preserved verbatim in manual-review sections,
  routed to manual-review artifacts for concise hot memory, or preserved
  unchanged when no matching target template exists.
- Commands, paths, API names, filenames, commit types, raw errors, and code
  symbols remain in their original form because project-specific content is not
  machine-translated.
- This is not arbitrary-language i18n and does not claim perfect unattended
  translation.

## Operating Rules

- Prefer pinned sync via `hub.lock.json` instead of dynamically reading live global state.
- Treat project `.agents` as a local overlay. Shared templates are defaults, not hard constraints.
- Treat `templates/project-root/` as the home for long-lived project docs that should be committed with source, including `docs/specs/` scaffolds.
- Use `check_hub_lock.ps1` when you need to verify whether a project's pin has drifted from the installed hub.
- Promote stable cross-project practices into the hub template, not per-project runtime files.
- Keep global experience retrieval lightweight: projects should search the hub index on demand rather than preload global experience into every session.
- Do not use bootstrap as a routine session-end promotion step. Cross-project experience promotion is a `knowledge-hub/scripts` maintenance action; bootstrap only installs the project guidance that points agents toward that hub workflow.
- Treat `-OverwriteTemplates` as deprecated compatibility wording. Prefer `-RefreshUnmodifiedTemplates` for safe refreshes and `-ForceResetScaffold` only for explicit reset scenarios.
- Legacy memory upgrades and language migrations should be proposal-first and backup-first. Do not overwrite old project memory without an explicit apply step.
- File-based `en` and `zh-CN` templates are the structural baseline for conservative language migration, not overwrite authority for customized project memory.

## References

- `references/maintenance-model.md`
