---
name: project-bootstrap
description: Initialize and maintain project-level `.agents` memory scaffolds from a global git-tracked knowledge hub at `%USERPROFILE%\\.agents\\knowledge-hub`. Use when creating a new project scaffold, refreshing existing project memory, upgrading memory templates, migrating project memory language, refreshing shared templates with a pinned lock file (`.agents/hub.lock.json`), or standardizing cross-project AGENTS/context/plan/process/notes structures. Also use for requests such as 刷新旧工程记忆, 升级工程记忆模板, 迁移工程记忆语言到中文, 迁移工程记忆语言到英文, 重新初始化工程记忆, or 重置工程记忆模板.
category: kernel
stability: stable
scope: cross-project
metadata:
  category: kernel
  stability: stable
  scope: cross-project
compatibility: Bundled scripts require PowerShell 7+. The metadata map is an additive compatibility layer; top-level category, stability, and scope aliases remain supported.
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
- `init_hub.ps1` also syncs the minimal hub runtime scripts for candidate intake, experience promotion, and index rebuild from the bootstrap compatibility copies.
- `init_hub.ps1` does not create `.git` by default. Use `-InitializeGit` or `-CommitInitial` only when the target hub should be an independent Git repository.

## Step 2: Bootstrap a Project

Run the project bootstrap script from any location:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/bootstrap_project.ps1 -ProjectDir <project_path>
```

Default behavior:
- `-HubDir` identifies the knowledge hub root itself. That directory must
  directly contain `templates/languages`; do not pass a repository root that
  merely contains a `knowledge-hub` child directory.
- If an explicitly supplied hub path already exists, is non-empty, and does
  not directly contain `templates/languages`, bootstrap fails before writing
  to the hub or project. It does not silently correct the path or initialize
  content inside that directory.
- If the default runtime hub is missing its template folders, bootstrap first
  attempts to initialize it from bundled bootstrap assets. Explicit new or
  empty hub directories remain supported initialization targets.
- Copy template files only when missing.
- Keep project-local edits untouched.
- Write/refresh `.agents/hub.lock.json` with the current hub commit.
- Run a read-only legacy memory analysis and print a short upgrade hint only when candidates are detected.
- Record the installed template tree hash and whether the hub worktree was dirty at install time.
- Install the shared `Global Experience Discovery` behavior contract from the language-specific `project-root/AGENTS.md` template, not `project-agent/AGENTS.md`, so projects know when to search the global experience index and when to keep lessons local.
- Install the full `templates/languages/<language>/project-root/` tree, not only root `AGENTS.md`, so long-lived project docs like `docs/specs/_templates/` can be scaffolded safely.
- Install the declarative `.claude/guardrails/` template reliability contract
  for Claude Code projects. This is not a security sandbox, permission
  isolation layer, or automatic external-write authorization.
- Install `.claude/settings.json` and the `.claude/hooks/guardrail.ps1` runner
  so SessionStart, PreToolUse, and Stop checks execute against that contract.
  The runner must leave ordinary permissions and no-bot public contributor
  paths intact.
- When `-ProjectLanguage` is supplied, write first-session language scaffolds for hot memory, `.agents/context/`, `.agents/commands/`, and `docs/specs/`.
- Language scaffolds are loaded from the bundled hub snapshot under
  `skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/<language>/`.
- Supported project memory template languages are `en` and `zh-CN` only. English remains the default for a new project without language metadata.
- If a `zh-CN` template file is missing, the language helper falls back to the matching English template and reports fallback metadata. Treat that as a validation finding to fix, not as a reason to overwrite project-specific memory.
- For existing projects, the wrapper inherits `project_language` from
  `.agents/hub.lock.json` when `-ProjectLanguage` is omitted, with the
  `.agents/AGENTS.md` declaration as a fallback when no lock language exists.
  Conflicting lock and guide declarations fail before scaffold or lock writes
  even when callers pass `-ProjectLanguage` explicitly. Do not infer project
  memory language from the current chat.
- Unknown named parameters fail before bootstrap writes. The common
  `-ProjectRoot` mistake reports that callers must use `-ProjectDir`.
- The resolved project directory is printed before any bootstrap write.

Optional flags:
- `-HubDir <path>`: custom knowledge hub root; it must directly contain
  `templates/languages` once initialized.
- `-RefreshUnmodifiedTemplates`: refresh files that still match the previously installed template hash; preserve modified files for manual review.
- `-OverwriteTemplates`: compatibility alias for `-RefreshUnmodifiedTemplates`. It emits a warning and does not overwrite modified project memory.
- `-ForceResetScaffold`: explicit reset path for discarding scaffold customizations. It emits a warning, backs up existing files first, and cannot be combined with memory upgrade modes.
- `-AnalyzeMemoryUpgrade`: after the normal conservative bootstrap wrapper
  flow, inspect legacy `.agents` memory and report issues without changing
  memory files. The wrapper may still create missing scaffold files or refresh
  `.agents/hub.lock.json` before the memory analysis step.
- `-PlanMemoryUpgrade`: generate a reviewable `.agents/upgrade/<timestamp>/proposal.md`.
- `-ApplyMemoryUpgrade -UpgradePlan <path>`: after user review, back up and normalize hot memory files according to the proposal.
- `-AutoUpgrade`: when the caller has explicitly approved memory normalization, analyze candidates, create the default proposal, apply it, and print the proposal, backup, and result paths.
- `-AnalyzeLanguageMigration -SourceLanguage en|zh-CN -TargetLanguage en|zh-CN`: inspect existing project memory for conservative language migration without editing memory.
- `-PlanLanguageMigration -SourceLanguage en|zh-CN -TargetLanguage en|zh-CN`: write a reviewable language migration proposal and create the required backup before apply.
- `-ApplyLanguageMigration -MigrationPlan <proposal.json>`: apply approved language migration actions after review, requiring the proposal and recorded backup.
- `-ValidateLanguageMigration -MigrationPlan <proposal.json>`: validate result metadata, backup presence, migration metadata, per-action output hashes, and manual-review source hash records.
- `-PlanNarrativeMigration -MigrationPlan <proposal.json>`: read Phase 1 manual-review artifacts and write a second narrative proposal with actions unapproved by default.
- `-ApplyNarrativeMigration -MigrationPlan <narrative-proposal.json>`: apply reviewed narrative actions only after proposal, backup, source hash, and target hash checks.
- `-ValidateNarrativeMigration -MigrationPlan <narrative-proposal.json>`: validate narrative result metadata, source artifacts, backup, and review markers.
- `-SkipMemoryUpgradeAnalysis`: skip the default read-only legacy memory check.
- `-ProjectLanguage en|zh-CN`: explicitly set the project memory language during bootstrap. The agent or workflow supplies the user's primary language; the script does not infer chat language.

Intent semantics:
- Refresh or template upgrade means preserve project-specific memory by
  default. Refresh missing scaffolds, update files that still match old
  template hashes when requested, and route modified project memory to review.
- Language migration means move between the supported `en` and `zh-CN`
  project-memory languages. The workflow uses target-language templates as
  structural baselines, drafts target-language narrative for review, and keeps
  protected literals such as commands, paths, APIs, filenames, raw errors, and
  code symbols in their original form.
- Reset or reinitialize means discard existing scaffold customizations only
  when the caller explicitly asks not to preserve old project memory, for
  example "do not keep old memory", "reset to the latest templates", or
  "重新初始化工程记忆，不保留旧内容". Reset remains backup-first.

Standalone body-level language audit:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/audit_memory_language.ps1 -ProjectDir <project_path> -ExpectedLanguage zh-CN -IncludeSpecs -IncludeCommands -Json
```

Use this helper when review needs to verify narrative body language without
running a full migration apply flow. It ignores `Summary` / `Keywords`
discovery metadata, fenced code blocks, inline code, commands, paths, API
names, filenames, raw errors, and code identifiers before reporting heuristic
warning-level findings. It is read-only and must not be treated as automatic
translation, rewrite, or approval.
When using `-Json`, the output includes the resolved `project_dir`. Review or
redact local paths before copying audit output into public issues, pull
requests, or documents.

Operating modes:
- Initialize empty project: run bootstrap on a project without existing `AGENTS.md` or `.agents` memory. Missing templates and first-session language scaffolds may be written.
- Refresh missing templates: default for existing projects. Missing files are copied, existing files are preserved, and memory analysis remains read-only unless another mode is requested. This is the conservative answer to "refresh old project memory" when the user has not asked to rewrite content. Pass the project's current memory language explicitly when the project is not English-first or when lock metadata already records a language.
- Refresh unmodified templates: use `-RefreshUnmodifiedTemplates` when the lock has prior template hashes. Files that still match the previous installed hash may be updated; modified files are preserved for manual review. This is a safe template upgrade, not a reset.
- Conservative memory migration: use proposal-first and backup-first modes after review. Use `-AnalyzeMemoryUpgrade`, `-PlanMemoryUpgrade`, then `-ApplyMemoryUpgrade -UpgradePlan <path>` for legacy memory layout normalization. Use `-AnalyzeLanguageMigration`, `-PlanLanguageMigration`, `-ApplyLanguageMigration -MigrationPlan <path>`, then `-ValidateLanguageMigration -MigrationPlan <path>` for `en` / `zh-CN` language migration. Use `-PlanNarrativeMigration`, `-ApplyNarrativeMigration`, and `-ValidateNarrativeMigration` as the follow-up review step for manual-review artifacts.
- Explicit force reset: use `-ForceResetScaffold` only when the caller intentionally discards scaffold customizations. Do not infer this from "refresh", "upgrade", "migrate", or "reinitialize" unless the caller also says old memory may be discarded. This is not a language migration path and remains backup-first.

Standalone language update:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/set_project_language.ps1 -ProjectDir <project_path> -ProjectLanguage zh-CN -OverwriteScaffold
```

Use `-OverwriteScaffold` only for bootstrap-era scaffolds or intentional reset scenarios. It backs up existing files before rewriting initial memory scaffold files. For established project memory, use conservative migration instead of treating language selection as scaffold overwrite.

The standalone helper reads file templates from the bundled hub snapshot under
`skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/`
by default. `-TemplateRoot` is available for validation fixtures and controlled
template-source tests.

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
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/memory_upgrade.ps1 -ProjectDir <project_path> -Mode Analyze
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -AnalyzeMemoryUpgrade
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -PlanMemoryUpgrade
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -ApplyMemoryUpgrade -UpgradePlan <proposal_path>
```

Caller-approved non-interactive flow:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -AutoUpgrade
```

Behavior:
- Direct `memory_upgrade.ps1 -Mode Analyze` is the strict no-edit memory-only
  analysis path.
- Bootstrap wrapper `-AnalyzeMemoryUpgrade` runs the normal conservative
  bootstrap refresh first, so it may write missing scaffold or lock metadata
  before running the read-only memory analysis.
- Plan mode writes a proposal for user review.
- Apply mode requires a proposal path, backs up current memory under `.agents/_backup/<timestamp>/`, and normalizes hot memory (`process.txt`, `plan.md`, `notes.md`).
- When Apply normalizes `notes.md`, it preserves compact bullet facts only from
  explicit stable notes sections (`# Confirmed Notes`, `## Stable Facts`,
  `# 已确认记录`, or `## 稳定事实`) and filters volatile TODO, checkbox,
  next-step, branch / PR waiting, and temporary runtime lines. It does not infer
  stable facts from arbitrary prose; use the backup for manual review of
  anything outside the deterministic safe sections.
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
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -PlanNarrativeMigration -MigrationPlan <proposal.json>
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -ApplyNarrativeMigration -MigrationPlan <narrative-proposal.json>
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -ValidateNarrativeMigration -MigrationPlan <narrative-proposal.json>
```

Simplified Chinese to English reverses the source and target languages.

Behavior:
- Analyze mode is read-only.
- Plan mode writes `.agents/language-migration/<timestamp>/proposal.json` and
  `proposal.md`, and creates `.agents/_backup/language-migration-<timestamp>/`.
- Apply mode requires the proposal and recorded backup, then refuses to write if
  a planned source file changed after planning.
- Exact source-template matches are replaced with target-language templates.
- Customized project content is first backed up and staged for review; the
  normal completion path applies reviewed target-language narrative back to the
  right memory surface. Manual-review-only routing is an exception path for
  uncertain or unsupported content, not the default migration result.
- Narrative migration reads those manual-review artifacts, creates a second
  proposal with target-language narrative drafts, stable facts, active plan,
  process state, reusable lessons, and durable specs routed to the right memory
  surfaces, and leaves actions unapproved until a reviewer accepts or edits the
  draft text.
- Commands, paths, API names, filenames, commit types, raw errors, and code
  symbols remain in their original form.
- Validation uses the body-level language audit helper: Phase 1 validation can
  be structurally valid while `completion_ready` remains false, and final
  narrative validation rejects blocking source-language leftovers.
- This is not arbitrary-language i18n and does not claim perfect unattended
  translation.

## Operating Rules

- Prefer pinned sync via `hub.lock.json` instead of dynamically reading live global state.
- Treat project `.agents` as a local overlay. Shared templates are defaults, not hard constraints.
- Treat `templates/languages/<language>/project-root/` as the home for long-lived project docs that should be committed with source, including `docs/specs/` scaffolds.
- Use `check_hub_lock.ps1` when you need to verify whether a project's pin has drifted from the installed hub.
- Promote stable cross-project practices into the hub template, not per-project runtime files.
- Keep global experience retrieval lightweight: projects should search the hub index on demand rather than preload global experience into every session.
- Keep candidate intake separate from formal promotion. Use the installed hub's `scripts/manage_candidates.ps1` only with explicit project roots, explicit languages, and an explicit runtime inbox; it never promotes into `knowledge/experience/**`.
- Do not use bootstrap as a routine session-end promotion step. Cross-project experience promotion is a `knowledge-hub/scripts` maintenance action; bootstrap only installs the project guidance that points agents toward that hub workflow.
- Treat `-OverwriteTemplates` as deprecated compatibility wording. Prefer `-RefreshUnmodifiedTemplates` for safe refreshes and `-ForceResetScaffold` only for explicit reset scenarios.
- Legacy memory upgrades and language migrations should be proposal-first and backup-first. Do not hand-edit `.agents/**` in bulk or overwrite old project memory without an explicit apply step.
- File-based `en` and `zh-CN` templates are the structural baseline for conservative language migration, not overwrite authority for customized project memory.
- The authoritative source for project-memory templates in this repository is
  `knowledge-hub/templates/languages/<language>/project-root|project-agent/`.
  The bundled
  `assets/knowledge-hub-template/templates/languages/<language>/project-root|project-agent/`
  tree is the runtime snapshot used by `set_project_language.ps1` and language
  migration helpers.

## References

- `references/maintenance-model.md`
