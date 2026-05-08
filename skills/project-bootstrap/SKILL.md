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

## Step 1: Initialize Global Hub

Run the initialization script when `%USERPROFILE%\\.agents\\knowledge-hub` is missing or when you want to refresh hub templates from this skill's assets.

```powershell
pwsh -NoProfile -File scripts/init_hub.ps1
```

Optional flags:
- `-HubDir <path>`: custom hub location.
- `-Overwrite`: replace existing hub template files.
- `-CommitInitial`: attempt an initial git commit after sync.

Notes:
- `init_hub.ps1` rebuilds `knowledge/experience/index.json` after syncing templates so an overwrite refresh does not leave the installed hub with a stale or empty registry.
- `init_hub.ps1` also syncs the minimal hub runtime scripts for experience promotion and index rebuild from the bootstrap compatibility copies.

## Step 2: Bootstrap a Project

Run the project bootstrap script from any location:

```powershell
pwsh -NoProfile -File scripts/bootstrap_project.ps1 -ProjectDir <project_path>
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

Optional flags:
- `-HubDir <path>`: custom hub location.
- `-OverwriteTemplates`: overwrite existing project template files.
- `-AnalyzeMemoryUpgrade`: after bootstrap, inspect legacy `.agents` memory and report issues without changing memory.
- `-PlanMemoryUpgrade`: generate a reviewable `.agents/upgrade/<timestamp>/proposal.md`.
- `-ApplyMemoryUpgrade -UpgradePlan <path>`: after user review, back up and normalize hot memory files according to the proposal.
- `-SkipMemoryUpgradeAnalysis`: skip the default read-only legacy memory check.
- `-ProjectLanguage en|zh-CN`: explicitly set the project memory language during bootstrap. The agent or workflow supplies the user's primary language; the script does not infer chat language.

Standalone language update:

```powershell
pwsh -NoProfile -File scripts/set_project_language.ps1 -ProjectDir <project_path> -ProjectLanguage zh-CN -OverwriteScaffold
```

Use `-OverwriteScaffold` only for bootstrap-era scaffolds or intentional template refreshes; it rewrites the initial memory scaffold files.

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
pwsh -NoProfile -File scripts/check_hub_lock.ps1 -ProjectDir <project_path>
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
pwsh -NoProfile -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -AnalyzeMemoryUpgrade
pwsh -NoProfile -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -PlanMemoryUpgrade
pwsh -NoProfile -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -ApplyMemoryUpgrade -UpgradePlan <proposal_path>
```

Behavior:
- Analyze mode is read-only.
- Plan mode writes a proposal for user review.
- Apply mode requires a proposal path, backs up current memory under `.agents/_backup/<timestamp>/`, and normalizes hot memory (`process.txt`, `plan.md`, `notes.md`).
- Durable multi-stage work should move into `docs/specs/`; `.agents` remains session-local.

## Operating Rules

- Prefer pinned sync via `hub.lock.json` instead of dynamically reading live global state.
- Treat project `.agents` as a local overlay. Shared templates are defaults, not hard constraints.
- Treat `templates/project-root/` as the home for long-lived project docs that should be committed with source, including `docs/specs/` scaffolds.
- Use `check_hub_lock.ps1` when you need to verify whether a project's pin has drifted from the installed hub.
- Promote stable cross-project practices into the hub template, not per-project runtime files.
- Keep global experience retrieval lightweight: projects should search the hub index on demand rather than preload global experience into every session.
- Do not use bootstrap as a routine session-end promotion step. Cross-project experience promotion is a `knowledge-hub/scripts` maintenance action; bootstrap only installs the project guidance that points agents toward that hub workflow.
- Legacy memory upgrades should be proposal-first and backup-first. Do not overwrite old project memory without an explicit apply step.

## References

- `references/maintenance-model.md`
