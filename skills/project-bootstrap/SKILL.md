---
name: project-bootstrap
description: Initialize and maintain project-level `.agents` memory scaffolds from a global git-tracked knowledge hub at `%USERPROFILE%\\.agents\\knowledge-hub`. Use when creating a new project scaffold, refreshing existing project memory, upgrading memory templates, migrating project memory language, or refreshing shared templates with a pinned lock file (`.agents/hub.lock.json`). Active C3.3 projects use the minimal canonical workspace (Work, Context, Procedure, Spec) and are verified through `project-workspace`. Legacy hub-lock validation, first-session hot-memory scaffold, and `.agents/AGENTS.md` / `process.txt` / `plan.md` / `notes.md` / `.agents/commands` / `CLAUDE.md` are compatibility-only and are not part of the active C3.3 default flow. Also use for requests such as 刷新旧工程记忆, 升级工程记忆模板, 迁移工程记忆语言到中文, 迁移工程记忆语言到英文, 重新初始化工程记忆, or 重置工程记忆模板.
category: kernel
stability: stable
scope: cross-project
metadata:
  category: kernel
  stability: stable
  scope: cross-project
compatibility: Bundled scripts require PowerShell 7.6+. The metadata map is an additive compatibility layer; top-level category, stability, and scope aliases remain supported.
---

# Agent Project Bootstrap

## Active C3.3 default flow

After the one-time default cutover, fresh and existing C3.3 projects use the
canonical minimal workspace. The default flow is:

1. Run `bootstrap_project.ps1` on the target project (see Step 2).
2. Verify the resulting workspace with
   `skills/project-workspace/scripts/check-project-workspace.ps1` (see
   Step 3).

Do not run `init_hub.ps1`, `check_hub_lock.ps1`, or `memory_upgrade.ps1` as
part of the active C3.3 default flow. Those tools remain available for the
legacy / compatibility-only scenarios described later in this Skill, and for
explicit maintenance of a separately tracked knowledge hub repository. A
fresh C3.3 project intentionally records `hub_dir = ""` in
`.agents/hub.lock.json`; an empty `hub_dir` is the expected C3.3 state and is
not a signal to Git-initialize a knowledge hub or to run hub-lock validation.

## Legacy / compatibility-only surface

The following are not part of the active C3.3 default flow. Use them only when
an existing legacy project or a separately tracked knowledge hub repository
requires them:

- `init_hub.ps1` (Step 1): hub template initialization for a separately
  tracked knowledge hub, not for project-local workspace authority.
- `check_hub_lock.ps1` (Step 4): pin-drift validation for projects that pin a
  non-empty `hub_dir`.
- `memory_upgrade.ps1` and the `bootstrap_project.ps1` memory-upgrade /
  language-migration wrappers (Steps 5 and 6): legacy hot-memory layout
  normalization and project-memory language migration.
- First-session language scaffolds for `.agents/AGENTS.md`, hot memory
  (`process.txt`, `plan.md`, `notes.md`), `.agents/commands/`, and
  `CLAUDE.md`: legacy scaffold surfaces, not generated for a fresh C3.3
  project.

## Workflow

1. Bootstrap the target project with `bootstrap_project.ps1` (Step 2).
2. Verify the resulting C3.3 workspace with
   `skills/project-workspace/scripts/check-project-workspace.ps1` (Step 3).
3. Only when an existing legacy project or a separately tracked knowledge hub
   requires it, use the legacy / compatibility-only steps later in this Skill
   (Steps 1, 2.5, 4, 5, 6).

Command examples use `pwsh -NoProfile -File` (PowerShell 7.6+).

## Step 1: Initialize Global Hub (legacy / compatibility-only)

This step is for maintaining a separately tracked knowledge hub repository.
The active C3.3 default flow does not require it; a fresh C3.3 project records
`hub_dir = ""` and does not Git-initialize a hub. Run this only when
`%USERPROFILE%\\.agents\\knowledge-hub` is missing and a non-empty hub pin is
required, or when refreshing hub templates for a separately tracked hub.

```powershell
pwsh -NoProfile -File scripts/init_hub.ps1
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
pwsh -NoProfile -File scripts/bootstrap_project.ps1 -ProjectDir <project_path>
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
- Record the installed template tree hash and whether the hub worktree was dirty at install time.
- Unknown named parameters fail before bootstrap writes. The common
  `-ProjectRoot` mistake reports that callers must use `-ProjectDir`.
- The resolved project directory is printed before any bootstrap write.

C3.3 default path (fresh and existing C3.3 projects):
- For a fresh project, create the minimal C3.3 workspace layout: a short
  `AGENTS.md`, `.agents/README.md`, empty `work/`, `context/`, `procedures/`,
  and `skills/` roots, and `docs/specs/`. Do not create placeholder Work,
  Context, Procedure, Spec, glossary, or promoted Skill content. Fresh projects
  always use this path after the one-time default cutover.
- Do not create `.agents/AGENTS.md`, `process.txt`, `plan.md`, `notes.md`,
  `.agents/commands`, `CLAUDE.md`, or any legacy hot-memory first-session
  scaffold. These are legacy surfaces and are not part of the fresh C3.3
  workspace.
- An existing C3.3 workspace is refreshed through the same minimal template
  contract.
- The C3.3 lock records `hub_dir = ""` on purpose. Do not interpret an empty
  `hub_dir` as drift, a missing hub, or a reason to Git-initialize a knowledge
  hub. Hub-lock validation is not part of the C3.3 default flow.
- For a fresh C3.3 workspace, a read-only legacy memory analysis is not run by
  default and no upgrade hint is printed. The C3.3 workspace is an empty
  canonical layout; use `memory_upgrade.ps1 -Mode Analyze` only for an explicit
  read-only check when a legacy project is being inspected.
- Do not install the legacy project-root `.claude/**` guardrail / hook
  scaffold. The C3.3 project template
  (`skills/project-bootstrap/assets/c3-3-project-template/<language>/`) does
  not include `.claude/**`, and `bootstrap_project.ps1` does not create it on
  the C3.3 path. `.claude/guardrails/`, `.claude/settings.json`, and
  `.claude/hooks/guardrail.ps1` are legacy project-root template surfaces and
  are not part of the fresh C3.3 workspace.
- The C3.3 fresh-project path writes only layout metadata and preserves the
  existing language contract. It does not write current branch, checks,
  next-step state, or any temporary run state.

Legacy project path (compatibility-only):
- An existing legacy project keeps the legacy scaffold path until an explicit
  reviewed `migrate-project.ps1` Analyze -> Apply. Bootstrap on a legacy
  project may still write `.agents/AGENTS.md`, hot memory (`process.txt`,
  `plan.md`, `notes.md`), `.agents/commands/`, and `CLAUDE.md` first-session
  scaffolds, and may run a read-only legacy memory analysis that prints a
  short upgrade hint only when candidates are detected.
- Install the declarative `.claude/guardrails/` template reliability contract
  for Claude Code projects from the legacy `project-root` template. This is
  not a security sandbox, permission isolation layer, or automatic
  external-write authorization.
- Install `.claude/settings.json` and the `.claude/hooks/guardrail.ps1` runner
  so SessionStart, PreToolUse, and Stop checks execute against that contract.
  The runner must leave ordinary permissions and no-bot public contributor
  paths intact.
- Install the shared `Global Experience Discovery` behavior contract from the language-specific `project-root/AGENTS.md` template, not `project-agent/AGENTS.md`, so projects know when to search the global experience index and when to keep lessons local.
- Install the full `templates/languages/<language>/project-root/` tree, not only root `AGENTS.md`, so long-lived project docs like `docs/specs/_templates/` can be scaffolded safely.
- When `-ProjectLanguage` is supplied on a legacy project, write first-session
  language scaffolds for hot memory, `.agents/context/`, `.agents/commands/`,
  and `docs/specs/`. This does not apply to a fresh C3.3 project.
- Language scaffolds are loaded from the bundled hub snapshot under
  `skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/<language>/`.
- Supported project memory template languages are `en` and `zh-CN` only. English remains the default for a new project without language metadata.
- If a `zh-CN` template file is missing, the language helper falls back to the matching English template and reports fallback metadata. Treat that as a validation finding to fix, not as a reason to overwrite project-specific memory.
- For existing legacy projects, the wrapper inherits `project_language` from
  `.agents/hub.lock.json` when `-ProjectLanguage` is omitted, with the
  `.agents/AGENTS.md` declaration as a fallback when no lock language exists.
  Conflicting lock and guide declarations fail before scaffold or lock writes
  even when callers pass `-ProjectLanguage` explicitly. Do not infer project
  memory language from the current chat.

Optional flags:
- `-HubDir <path>`: custom knowledge hub root; it must directly contain
  `templates/languages` once initialized.
- `-RefreshUnmodifiedTemplates`: refresh files that still match the previously installed template hash; preserve modified files for manual review.
- `-OverwriteTemplates`: compatibility alias for `-RefreshUnmodifiedTemplates`. It emits a warning and does not overwrite modified project memory.
- `-ForceResetScaffold`: explicit reset path for discarding scaffold customizations. It emits a warning, backs up existing files first, and cannot be combined with memory upgrade modes.
- `-SkipMemoryUpgradeAnalysis`: skip the default read-only legacy memory check.
- `-ProjectLanguage en|zh-CN`: explicitly set the project memory language during bootstrap. The agent or workflow supplies the user's primary language; the script does not infer chat language. On a fresh C3.3 project this only records the project language in the C3.3 lock; it does not write legacy first-session hot-memory scaffolds.

Legacy / compatibility-only flags (existing legacy projects and explicit
memory-upgrade / language-migration workflows only; not part of the fresh C3.3
default flow):
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

The C3.3 fresh-project path writes only layout metadata and preserves the
existing language contract. It does not write current branch, checks, next-step
state, or any temporary run state. Direct
`memory_upgrade.ps1 -Mode Analyze -Json` remains the strict read-only path;
the compatibility `bootstrap_project.ps1 -AnalyzeMemoryUpgrade` wrapper may
write missing bootstrap templates and `hub.lock.json` before it delegates to
analysis.

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
pwsh -NoProfile -File scripts/audit_memory_language.ps1 -ProjectDir <project_path> -ExpectedLanguage zh-CN -IncludeSpecs -IncludeCommands -Json
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
- Initialize empty project: run bootstrap on a project without existing `AGENTS.md` or `.agents` memory. A fresh C3.3 project gets the minimal canonical workspace; legacy first-session language scaffolds are not written on the C3.3 path.
- Refresh missing templates: default for existing projects. Missing files are copied, existing files are preserved, and memory analysis remains read-only unless another mode is requested. This is the conservative answer to "refresh old project memory" when the user has not asked to rewrite content. Pass the project's current memory language explicitly when the project is not English-first or when lock metadata already records a language.
- Refresh unmodified templates: use `-RefreshUnmodifiedTemplates` when the lock has prior template hashes. Files that still match the previous installed hash may be updated; modified files are preserved for manual review. This is a safe template upgrade, not a reset.
- Conservative memory migration (legacy / compatibility-only): use proposal-first and backup-first modes after review. Use `-AnalyzeMemoryUpgrade`, `-PlanMemoryUpgrade`, then `-ApplyMemoryUpgrade -UpgradePlan <path>` for legacy memory layout normalization. Use `-AnalyzeLanguageMigration`, `-PlanLanguageMigration`, `-ApplyLanguageMigration -MigrationPlan <path>`, then `-ValidateLanguageMigration -MigrationPlan <path>` for `en` / `zh-CN` language migration. Use `-PlanNarrativeMigration`, `-ApplyNarrativeMigration`, and `-ValidateNarrativeMigration` as the follow-up review step for manual-review artifacts.
- Explicit force reset: use `-ForceResetScaffold` only when the caller intentionally discards scaffold customizations. Do not infer this from "refresh", "upgrade", "migrate", or "reinitialize" unless the caller also says old memory may be discarded. This is not a language migration path and remains backup-first.

Standalone language update:

```powershell
pwsh -NoProfile -File scripts/set_project_language.ps1 -ProjectDir <project_path> -ProjectLanguage zh-CN -OverwriteScaffold
```

Use `-OverwriteScaffold` only for bootstrap-era scaffolds or intentional reset scenarios. It backs up existing files before rewriting initial memory scaffold files. For established project memory, use conservative migration instead of treating language selection as scaffold overwrite.

The standalone helper reads file templates from the bundled hub snapshot under
`skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/`
by default. `-TemplateRoot` is available for validation fixtures and controlled
template-source tests.

## Step 2.5: Memory Upgrade Decision (legacy / compatibility-only)

This step applies to existing legacy projects with old `.agents` memory. A
fresh C3.3 workspace does not run a legacy memory analysis by default and does
not print a `Memory upgrade candidates detected` hint; continue directly to
Step 3.

When bootstrap reports `Memory upgrade candidates detected: N`, do not silently ignore it.

- If the user's request explicitly includes memory cleanup, organization, normalization, or upgrade, rerun bootstrap with `-AutoUpgrade` or run the manual `-PlanMemoryUpgrade` and `-ApplyMemoryUpgrade` flow after reviewing the proposal.
- If the user's request only asked for project bootstrap or reinitialization in an existing project, tell the user candidates were detected and ask before applying memory rewrites. Do not interpret reinitialization as force reset.
- If the user explicitly says not to upgrade memory, skip the upgrade and use `-SkipMemoryUpgradeAnalysis` on repeated bootstrap runs when the reminder would add noise.
- If no candidates are detected, or `-SkipMemoryUpgradeAnalysis` was intentionally supplied, continue to verification.

`-AutoUpgrade` is for non-interactive, caller-approved upgrades. It preserves the proposal-first and backup-first safety model by writing `.agents/upgrade/<timestamp>/proposal.md`, applying the checked default actions, and writing a result file next to the proposal.

## Step 3: Verify the C3.3 workspace

After a fresh or active C3.3 bootstrap, verify the workspace through the
`project-workspace` Skill, not through hub-lock validation:

```powershell
pwsh -NoProfile -NonInteractive -File skills/project-workspace/scripts/check-project-workspace.ps1 -ProjectRoot <project_path> -Json
```

`check-project-workspace.ps1` is strictly read-only and never creates or
refreshes the disposable Catalog cache. For a fresh C3.3 project it reports the
minimal canonical layout (Work, Context, Procedure, Spec roots, `AGENTS.md`,
`.agents/README.md`, `.agents/hub.lock.json`) without requiring a non-empty
`hub_dir`. For canonical asset discovery and authoring, see the
`project-workspace` Skill.

For a fresh C3.3 project, do not check for `.agents/AGENTS.md`, `process.txt`,
`plan.md`, `notes.md`, `.agents/commands`, or `CLAUDE.md`; those are legacy
surfaces and are not part of the C3.3 workspace. If needed, review
`references/maintenance-model.md` for long-term update rules.

## Step 4: Validate Hub Lock Drift (legacy / compatibility-only)

This step is for projects that pin a non-empty `hub_dir` against a separately
tracked knowledge hub repository. A fresh C3.3 project records `hub_dir = ""`
and is not a target for this check; running it on a fresh C3.3 project returns
`invalid_hub_dir`, which is the expected behavior for the empty-pin contract,
not a defect to fix by Git-initializing a knowledge hub. Do not run this as
part of the active C3.3 default flow.

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

## Step 5: Upgrade Legacy Project Memory (legacy / compatibility-only)

Use this only when re-running bootstrap in a project that already has old
`.agents` memory (`.agents/AGENTS.md`, `process.txt`, `plan.md`, `notes.md`,
`.agents/commands`, or `CLAUDE.md`). It is not part of the fresh C3.3 default
flow.

Recommended flow:

```powershell
pwsh -NoProfile -File scripts/memory_upgrade.ps1 -ProjectDir <project_path> -Mode Analyze
pwsh -NoProfile -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -AnalyzeMemoryUpgrade
pwsh -NoProfile -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -PlanMemoryUpgrade
pwsh -NoProfile -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -ApplyMemoryUpgrade -UpgradePlan <proposal_path>
```

Caller-approved non-interactive flow:

```powershell
pwsh -NoProfile -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -AutoUpgrade
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

## Step 6: Migrate Project Memory Language (legacy / compatibility-only)

Use this only when an established legacy project needs to move between the two
supported engineering-memory template languages without discarding
project-specific memory. It is not part of the fresh C3.3 default flow; a fresh
C3.3 project records its language in the C3.3 lock and does not require
language migration.

English to Simplified Chinese:

```powershell
pwsh -NoProfile -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -AnalyzeLanguageMigration -SourceLanguage en -TargetLanguage zh-CN
pwsh -NoProfile -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -PlanLanguageMigration -SourceLanguage en -TargetLanguage zh-CN
pwsh -NoProfile -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -ApplyLanguageMigration -MigrationPlan <proposal.json>
pwsh -NoProfile -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -ValidateLanguageMigration -MigrationPlan <proposal.json>
pwsh -NoProfile -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -PlanNarrativeMigration -MigrationPlan <proposal.json>
pwsh -NoProfile -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -ApplyNarrativeMigration -MigrationPlan <narrative-proposal.json>
pwsh -NoProfile -File scripts/bootstrap_project.ps1 -ProjectDir <project_path> -ValidateNarrativeMigration -MigrationPlan <narrative-proposal.json>
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
- Use `check_hub_lock.ps1` only for legacy / compatibility-only pin-drift checks on projects that pin a non-empty `hub_dir`. It is not part of the active C3.3 default flow; a fresh C3.3 project records `hub_dir = ""` and is verified through `skills/project-workspace/scripts/check-project-workspace.ps1`.
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
