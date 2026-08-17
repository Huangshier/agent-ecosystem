# Existing Project Upgrade Path

This guide is for projects that already have a runtime or `.agents` content and
need to reach the current C3.3 workspace without losing project-owned context.
It separates a safe scaffold refresh from legacy project migration.

New empty projects should use the
[minimal project adoption walkthrough](walkthroughs/minimal-project-adoption.md)
instead. This guide assumes the project already has local memory, specs, and
possibly generated context entries.

## Which Path Should I Use?

| Intent | Recommended path |
| --- | --- |
| Adopt Agent Ecosystem in a new project | Use the minimal project adoption walkthrough. |
| Refresh missing scaffold files in an existing project | Run a conservative `project-bootstrap` refresh; preserve project-specific content. |
| Upgrade only unmodified old templates | Use `-RefreshUnmodifiedTemplates` after checking the current project memory language. |
| Change project memory language | Use the conservative language migration Analyze -> Plan -> Apply -> Validate flow. |
| Migrate a legacy project into C3.3 | Run `scripts/migrate-project.ps1` Analyze -> explicit Apply -> guarded Rollback. |
| Discard old scaffold customizations | Use `-ForceResetScaffold` only after the caller explicitly confirms old scaffold content may be overwritten after backup; this is not the legacy migration authority. |
| Inspect current state only | Run `status.ps1`, `project-workspace check`, and `project-workspace discover` without apply modes. |

## Command Ownership Boundary

The command ownership boundary for the current Runtime is:

- `project-bootstrap` owns fresh scaffold creation, safe refresh, unmodified
  template refresh, and explicit backup-first force reset.
- `project-workspace` owns read-only workspace checks/discovery, canonical
  Work/Context/Procedure/Spec asset discovery and authoring, and durable Spec
  creation through `create-spec`.
- `scripts/status.ps1` reports top-level Project status from the
  `project.workspace` authority; it does not use retired memory helpers.
- The Runtime-level `scripts/migrate-project.ps1` is the only current authority
  for legacy project migration. It exposes Analyze, explicit Apply, and guarded
  Rollback modes.

Older bootstrap upgrade switches and helpers remain only as compatibility or
historical surfaces. They do not make retired Runtime Skills active and must
not be used as the C3.3 legacy migration path. See [Project Bootstrap Command
Boundaries](project-bootstrap-command-boundaries.md) for the preserved command
boundary and standalone runtime packaging constraints.

## Current Template Model

The public template model uses language-scoped project-memory templates:

```text
knowledge-hub/templates/languages/<language>/project-root|project-agent/
skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/<language>/project-root|project-agent/
```

The supported public project-memory template languages are `en` and `zh-CN`.
English remains the public default and fallback language. Current `recommended`,
`full`, and `dev` profiles install the active C3.3 Runtime authority;
`project-bootstrap` and `project-workspace` are the current Runtime Skills.
They do not install retired `project-context-gate`, `workflow-spec-lite`, or
`memory-governance` Skills.

Do not recreate legacy template directories as compatibility mirrors. Old path
references should be treated as historical records or cleanup findings, not as
supported current entrypoints.

## Preserve Local Memory

Existing project content is project-owned. The public templates are structural
baselines for missing files, exact template replacement, and reviewable
migration evidence. They do not authorize overwriting project-specific memory.

Preserve local content such as:

- `.agents/process.txt`, `.agents/plan.md`, and `.agents/notes.md` when they
  contain active project state or stable facts.
- `.agents/context/experience/` entries created by runtime work.
- `.agents/context/patterns/` and `.agents/context/standards/` when a project
  has added those local routing folders.
- `docs/specs/**` work packages that define local goals, decisions, or
  acceptance evidence.
- Any project-specific commands, context indexes, or notes that do not exactly
  match the public scaffold.

This preservation rule applies to target projects being upgraded. The canonical
C3.3 project asset roots are Work, Context, Procedure, and Spec; a migration
must account for each declared target and leave unsupported or ambiguous legacy
content for human disposition. The public `agent-ecosystem` source repository
uses GitHub issues and pull requests for its own maintenance record and does not
track root `docs/specs/**` as a maintenance work package.

## Intent Quick Reference

Use precise wording before choosing a tool mode:

- Refresh or template upgrade: keep project-specific memory. Add missing
  scaffolds, update files that still match old templates when requested, and
  route customized files to review.
- Language migration: change project memory between `en` and `zh-CN`. Use
  target-language templates, review target-language narrative drafts, and keep
  protected literals such as commands, paths, APIs, filenames, raw errors, and
  code symbols in their original form.
- Reset or reinitialize: discard scaffold customizations only when the caller
  explicitly says old memory can be discarded. This is the `-ForceResetScaffold`
  path, not the default meaning of refresh, upgrade, migrate, or reinitialize.

Copyable prompts:

```text
Please conservatively refresh this project's memory templates. Preserve project-specific content and update only safe shared scaffold and rule surfaces.
```

```text
请保守刷新当前项目的工程记忆模板，保留项目特化内容，只更新安全的共享骨架和规则。
```

```text
Please migrate this project's memory to zh-CN. Replace template portions with zh-CN templates, draft project-specific narrative in zh-CN for review, and keep commands, paths, APIs, filenames, raw errors, and code symbols in their original form.
```

```text
请把当前项目工程记忆迁移到 zh-CN。模板部分替换为中文模板，项目特化叙述内容翻译成中文；命令、路径、API、文件名、错误文本和代码符号保持原文。
```

```text
Please reinitialize project memory and do not preserve old content. I confirm old scaffold customizations may be overwritten after backup.
```

```text
请重新初始化工程记忆，不保留旧内容。我确认可以在备份后覆盖旧脚手架。
```

## Upgrade Flow

Use the current C3.3 flow for a legacy project:

`Analyze -> explicit Apply -> guarded Rollback`, followed by read-only status
and workspace checks. A scaffold refresh remains a separate `project-bootstrap`
operation and is not an implicit migration.

Before a scaffold refresh, determine the project memory language from the
project's `.agents/AGENTS.md` or existing `.agents/hub.lock.json`
`project_language` field. Pass that language explicitly with `-ProjectLanguage`
when `project-bootstrap` may create missing scaffold or lock metadata. Do not
infer project memory language from the current chat. This language check does
not replace the migration evidence required by `scripts/migrate-project.ps1`.

1. Inspect the installed Runtime and the project without editing files.

   ```powershell
   pwsh -NoProfile -NonInteractive -File <runtime>\scripts\status.ps1 -RuntimeDir <runtime> -ProjectDir <project> -Json
   pwsh -NoProfile -NonInteractive -File <runtime>\skills\project-workspace\scripts\check-project-workspace.ps1 -ProjectRoot <project> -Json
   pwsh -NoProfile -NonInteractive -File <runtime>\skills\project-workspace\scripts\discover-project-assets.ps1 -ProjectRoot <project> -Query <query> -Json
   ```

2. If the workspace is legacy or the status result is `migration-required`,
   create deterministic migration evidence with the Runtime-level migration
   authority. Analyze is strictly read-only.

   ```powershell
   pwsh -NoProfile -NonInteractive -File <runtime>\scripts\migrate-project.ps1 -Mode Analyze -ProjectRoot <project> -Json
   ```

3. Review the Analyze evidence. Confirm the Work / Context / Procedure / Spec
   plan, project language, workspace model, and project-specific preservation
   decisions. Unsupported or ambiguous material remains a human-disposition
   finding.

4. Apply only the reviewed evidence with explicit confirmation. Apply creates
   and verifies a complete project-owned backup before changing migration
   targets.

   ```powershell
   pwsh -NoProfile -NonInteractive -File <runtime>\scripts\migrate-project.ps1 -Mode Apply -ProjectRoot <project> -AnalyzeEvidence <analyze-json> -ConfirmMigration -Json
   ```

5. Validate the result with read-only status and workspace checks.

   ```powershell
   pwsh -NoProfile -NonInteractive -File <runtime>\scripts\status.ps1 -RuntimeDir <runtime> -ProjectDir <project> -Json
   pwsh -NoProfile -NonInteractive -File <runtime>\skills\project-workspace\scripts\check-project-workspace.ps1 -ProjectRoot <project> -Json
   pwsh -NoProfile -NonInteractive -File <runtime>\skills\project-workspace\scripts\discover-project-assets.ps1 -ProjectRoot <project> -Query <query> -Json
   ```

6. If the unchanged-project guard permits rollback, use the backup ID returned
   by Apply. Rollback keeps the backup and fails closed if migration-relevant
   project content changed after Apply.

   ```powershell
   pwsh -NoProfile -NonInteractive -File <runtime>\scripts\migrate-project.ps1 -Mode Rollback -ProjectRoot <project> -BackupId <backup-id> -ConfirmRollback -Json
   ```

For project-memory language changes, use the conservative language migration
Analyze, Plan, Apply, and Validate modes with explicit source and target
languages. Phase 1 replaces templates and stages project-specific content;
Phase 2 applies reviewed target-language narrative while preserving protected
literals. Manual-review-only artifacts are reserved for uncertain or unsupported
content, not the ordinary completion path.

When a separate body-level language check is needed for a project-memory
language migration, run:

```powershell
pwsh -NoProfile -NonInteractive -File <runtime>\skills\project-bootstrap\scripts\audit_memory_language.ps1 -ProjectDir <project> -ExpectedLanguage zh-CN -IncludeSpecs -IncludeCommands -Json
```

The audit is read-only. It reports likely body-language mismatches without
translating or rewriting project memory. The language migration validator uses
the same audit evidence so blocking source-language leftovers prevent a
completed migration claim.

## Handling Old Path References

Classify old path references before editing:

- Active setup, install, bootstrap, migration, or upgrade guidance should move
  to the `templates/languages/<language>/project-root|project-agent/` model.
- Historical release notes, closed specs, and old experience entries can keep
  old paths only when they are clearly marked as legacy, deprecated, removed,
  superseded, or historical state.
- Generated or local project records should not be deleted only because they
  mention an old path. Preserve the record and add a short note when the path is
  historical.

Do not add compatibility mirrors for old template directories. If a local tool
still depends on an old path, update the tool or keep the compatibility layer
inside the local project, not in the public kernel.

## Historical Compatibility Wording

Older release records and mechanical validators retain the terms `memory_upgrade.ps1`,
`-Mode Analyze`, `-AnalyzeMemoryUpgrade`, `ApplyMemoryUpgrade`, and `Validate`.
They describe the pre-C3.3 `language-scoped project-memory templates` flow and
its `analyze -> plan -> backup -> apply -> validate` wording, including the
`memory-only and no-edit` distinction and the rule `Do not recreate legacy
template directories`. These are historical or compatibility references only;
they are not the current legacy migration authority. Current migration uses
`scripts/migrate-project.ps1`, and retired `project-context-gate`,
`workflow-spec-lite`, and `memory-governance` helpers are not current Runtime
entrypoints.

## Validation For Public Changes

For this public repository, ordinary documentation changes use the affected
validation contract:

```powershell
git diff --check
pwsh -NoProfile -NonInteractive -File scripts/invoke-local-validation.ps1 -Stage iteration
pwsh -NoProfile -NonInteractive -File scripts/invoke-local-validation.ps1 -Stage pre-push
```

Run targeted documentation or workspace-consumer checks when the classifier
selects them, and complete Public Reader Review. The full Release validator is
reserved for an explicit Release/checkpoint decision.
