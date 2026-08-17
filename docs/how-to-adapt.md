# How To Adapt Agent Ecosystem

This guide shows how to use the public Workflow Kernel in another project
without copying this repository's private workflow.

For a continuous first-use path from an empty project, see the
[minimal project adoption walkthrough](walkthroughs/minimal-project-adoption.md).
For projects that already have `.agents` memory, use the
[existing project upgrade path](existing-project-upgrade.md).

## 1. Install A Runtime

Install the recommended public runtime:

```powershell
pwsh -NoProfile -NonInteractive -File .\scripts\install.ps1 -Profile recommended
```

For evaluation, use a temporary runtime first:

```powershell
pwsh -NoProfile -NonInteractive -File .\scripts\install.ps1 -Profile recommended -TargetDir <temp-runtime>
```

The default is a standalone copy. Rerunning the same command restores missing
managed files and updates only source-changed files whose installed copies were
not modified locally. Use `-DevLink` only for an explicit source-linked
development runtime. Existing `-Copy` invocations remain compatible.

Every run writes `install-report.json`. Unknown files are preserved and produce
a warning status with exit code 0. A file changed both locally and in the source
produces a conflict and a non-zero exit by default. Use `-AllowPartial` to
accept skipped conflicts, or `-ReplaceManaged` to overwrite managed files while
still preserving unknown files. `-Force` remains a deprecated compatibility
alias for `-ReplaceManaged`.

C3.3 entrypoints use `pwsh -NoProfile -NonInteractive -File` (PowerShell Core
7.6+). The active Runtime Skills are `project-bootstrap` and
`project-workspace`; `project-context-gate`, `workflow-spec-lite`, and
`memory-governance` are retired and are not installed by current public profiles.

To remove a generated runtime later, use the manifest-based uninstaller:

```powershell
pwsh -NoProfile -NonInteractive -File .\scripts\uninstall.ps1 -TargetDir <runtime>
```

For schema-2 copy items, the uninstaller first checks every managed destination
for nested unknown files and locally modified managed files. Any finding blocks
the entire uninstall before deletion and preserves the manifest/report for
review. Clean copy items and dev links retain the basic manifest-based uninstall
path; paths outside manifest destinations are untouched. Schema-1 manifests do
not provide this file-level protection. If the manifest is missing, no cleanup
is performed automatically.

## 2. Bootstrap A Project

Run `project-bootstrap` from the installed runtime:

```powershell
pwsh -NoProfile -NonInteractive -File <runtime>\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project>
```

Set project memory language explicitly during the first non-trivial memory
write when the agent or workflow knows the user's primary language:

```powershell
pwsh -NoProfile -NonInteractive -File <runtime>\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ProjectLanguage en
pwsh -NoProfile -NonInteractive -File <runtime>\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ProjectLanguage zh-CN
```

The script does not infer chat language by itself.
The supported project memory template languages are `en` and `zh-CN` only;
English is the fallback. This is a scaffold-language feature, not
arbitrary-language i18n.

For an existing project, treat bootstrap as a conservative scaffold refresh,
not as a legacy migration:

- Default bootstrap copies missing scaffold files and preserves existing memory.
- For a legacy project, use the
  [existing project upgrade path](existing-project-upgrade.md), whose only
  migration authority is `<runtime>\scripts\migrate-project.ps1`.
- Use `-RefreshUnmodifiedTemplates` only when you want files that still match
  the previous installed template hash to pick up newer templates.
- Do not use reset language for memory migration. Use the Analyze, Plan, Apply,
  and Validate flows so project-specific content is reviewed and backed up
  before changes are applied.
- For established project memory language changes, use the conservative
  language migration switches with an explicit direction, for example
  `-AnalyzeLanguageMigration -SourceLanguage en -TargetLanguage zh-CN`,
  then `-PlanLanguageMigration`, `-ApplyLanguageMigration -MigrationPlan
  <proposal.json>`, and `-ValidateLanguageMigration -MigrationPlan
  <proposal.json>`.
- For retained manual-review artifacts, continue with
  `-PlanNarrativeMigration -MigrationPlan <proposal.json>`, review and approve
  the generated `narrative-proposal.json`, then run
  `-ApplyNarrativeMigration` and `-ValidateNarrativeMigration`.
- `-ForceResetScaffold` is only for intentionally discarding scaffold
  customizations. It warns and backs up first, but it is not a conservative
  language migration path.

The runtime-level legacy migration command is proposal-first and backup-first:

```powershell
pwsh -NoProfile -NonInteractive -File <runtime>\scripts\migrate-project.ps1 -Mode Analyze -ProjectRoot <project> -Json
pwsh -NoProfile -NonInteractive -File <runtime>\scripts\migrate-project.ps1 -Mode Apply -ProjectRoot <project> -AnalyzeEvidence <analyze-json> -ConfirmMigration -Json
pwsh -NoProfile -NonInteractive -File <runtime>\scripts\migrate-project.ps1 -Mode Rollback -ProjectRoot <project> -BackupId <backup-id> -ConfirmRollback -Json
```

## 3. Use The Workflow Kernel

- Start non-trivial work by reading root `AGENTS.md`, then use
  `project-workspace` `discover` / `check` to progressively find canonical
  Work, Context, Procedure, and Spec assets. Do not use a retired context-gate
  or memory-governance helper as the current entrypoint.
- For Claude Code projects, keep the generated `CLAUDE.md`,
  `.claude/settings.json`, `.claude/guardrails/`, and `.claude/hooks/` surfaces
  in place. The lifecycle hooks check entry loading, project context, write
  authorization profiles, dangerous memory reset modes, and stop points without
  becoming a security sandbox or bypassing normal permissions.
- Use `project-workspace create-spec` in the target project for work that needs
  durable goals, non-goals, acceptance evidence, risks, or multi-phase
  execution.
- Use the `project-workspace` Work/Context continuity operations to record
  unfinished work and stable facts at handoff.
- Use the public `knowledge-hub/knowledge-catalog.md` before opening individual
  reusable knowledge entries.
- For runtime-specific startup paths (Codex, Claude Code, generic agents), see
  the [runtime adoption bridge](runtime-adoption-bridge.md).

## 4. Keep Layers Separate

- Public source: reusable kernel and public-safe knowledge.
- Runtime: generated install under `$HOME/.agents` or another target.
- Project local: `.agents/` and optional `docs/specs/` inside the target
  project.
- Private overlay: optional private profiles, skills, and knowledge outside this
  public repository.

This public repository itself uses GitHub issues and pull request bodies as the
maintenance record. Do not copy its historical root `docs/specs/**` work-package
pattern into public maintenance by default.

Do not copy the public tree into a private overlay. Add only private increments.

## 5. Validate Your Setup

Recommended workspace checks:

```powershell
pwsh -NoProfile -NonInteractive -File <runtime>\skills\project-workspace\scripts\check-project-workspace.ps1 -ProjectRoot <project> -Json
pwsh -NoProfile -NonInteractive -File <runtime>\skills\project-workspace\scripts\discover-project-assets.ps1 -ProjectRoot <project> -Query <query> -Json
```

For an ordinary documentation change to this public repository, run the
classifier-selected affected validation at `iteration` and `pre-push`, plus
`git diff --check` and Public Reader Review. The full Release validator is only
for an explicit Release/checkpoint decision. When that decision exists, run:

```powershell
pwsh -NoProfile -NonInteractive -File .\scripts\validate-release.ps1 -ScratchRoot <scratch-root>
```

## Example

See [examples/minimal-project](../examples/minimal-project/README.md) for a
small project-local scaffold that shows the intended file layout. For the full
adoption sequence, use the
[minimal project adoption walkthrough](walkthroughs/minimal-project-adoption.md).
