# Existing Project Upgrade Path

This guide is for projects that already have `.agents` memory and want to move
toward the post-`v0.4.2` public template model without losing local project
context.

New empty projects should use the
[minimal project adoption walkthrough](walkthroughs/minimal-project-adoption.md)
instead. This guide assumes the project already has local memory, specs, and
possibly generated context entries.

## Which Path Should I Use?

| Intent | Recommended path |
| --- | --- |
| Adopt Agent Ecosystem in a new project | Use the minimal project adoption walkthrough. |
| Refresh missing scaffold files in an existing project | Run conservative bootstrap refresh; preserve project-specific memory. |
| Upgrade only unmodified old templates | Use `-RefreshUnmodifiedTemplates` after checking the current project memory language. |
| Change project memory language | Use the conservative language migration Analyze -> Plan -> Apply -> Validate flow. |
| Discard old scaffold customizations | Use `-ForceResetScaffold` only after the caller explicitly confirms old scaffold content may be overwritten after backup. |
| Inspect current state only | Run `status.ps1` and `memory_upgrade.ps1 -Mode Analyze` without apply modes. |

## Command Ownership Boundary

The bootstrap command is the owner for scaffold creation, safe refresh,
unmodified-template refresh, and explicit backup-first force reset. Upgrade and
migration logic belongs in dedicated helpers:

- `memory_upgrade.ps1` for legacy memory analysis, proposal, and apply;
- `language_migration.ps1` for conservative project-memory language migration;
- `audit_memory_language.ps1` for read-only body-language evidence;
- `check_hub_lock.ps1` for lock drift checks.

`bootstrap_project.ps1` keeps existing upgrade and migration switches as
compatibility and discoverability wrappers, but future old-release upgrade
orchestration should not be added to the main bootstrap script by default. See
[Project Bootstrap Command Boundaries](project-bootstrap-command-boundaries.md)
for the full boundary, compatibility rules, and standalone runtime packaging
constraints.

## Current Template Model

`v0.4.2` uses language-scoped project-memory templates:

```text
knowledge-hub/templates/languages/<language>/project-root|project-agent/
skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/<language>/project-root|project-agent/
```

The supported public project-memory template languages are `en` and `zh-CN`.
English remains the public default and fallback language. The `full` and `dev`
profiles still install the same public content as `recommended`; they do not
install additional public domain packs yet.

Do not recreate legacy template directories as compatibility mirrors. Old path
references should be treated as historical records or cleanup findings, not as
supported current entrypoints.

## Preserve Local Memory

Existing project memory is project-owned. The public templates are structural
baselines for missing files, exact template replacement, and reviewable
migration proposals. They do not authorize overwriting project-specific memory.

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

This preservation rule applies to target projects being upgraded. The public
`agent-ecosystem` source repository no longer tracks root `docs/specs/**` as its
own maintenance record.

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

Use a conservative analyze -> plan -> backup -> apply -> validate flow.

Before running bootstrap wrapper refresh or analyze modes, determine the
project memory language from the project's `.agents/AGENTS.md` or existing
`.agents/hub.lock.json` `project_language` field. Pass that language explicitly
with `-ProjectLanguage` when the wrapper may create missing scaffold or lock
metadata. Do not infer project memory language from the current chat.

1. Analyze existing memory without editing files by calling the memory-upgrade
   helper directly.

   ```powershell
   pwsh -NoProfile -File <runtime>\skills\project-bootstrap\scripts\memory_upgrade.ps1 -ProjectDir <project> -Mode Analyze
   ```

   The bootstrap wrapper also exposes `-AnalyzeMemoryUpgrade`, but it runs the
   normal conservative bootstrap path before memory analysis. It may create
   missing scaffold files and `.agents/hub.lock.json` before reporting memory
   findings. Use the wrapper when a project also needs the current scaffold
   baseline refreshed; use the direct helper when the analysis must be
   memory-only and no-edit.

2. Plan a reviewable upgrade proposal.

   ```powershell
   pwsh -NoProfile -File <runtime>\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -PlanMemoryUpgrade
   ```

3. Review the generated plan. Confirm that project-specific memory is preserved
   and that old template path references are treated as historical notes or
   cleanup findings.

4. Back up before apply. The memory upgrade and language migration apply flows
   are backup-first; do not bypass that safety record.

5. Apply only the reviewed proposal.

   ```powershell
   pwsh -NoProfile -File <runtime>\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ApplyMemoryUpgrade -UpgradePlan <proposal>
   ```

6. Validate the result with the relevant project checks.

   ```powershell
   pwsh -NoProfile -File <runtime>\scripts\status.ps1 -RuntimeDir <runtime> -ProjectDir <project>
   pwsh -NoProfile -File <runtime>\skills\project-bootstrap\scripts\memory_upgrade.ps1 -ProjectDir <project> -Mode Analyze
   ```

For project-memory language changes, use the conservative language migration
Analyze, Plan, Apply, and Validate modes with explicit source and target
languages. Phase 1 replaces templates and stages project-specific content;
Phase 2 applies reviewed target-language narrative while preserving protected
literals. Manual-review-only artifacts are reserved for uncertain or unsupported
content, not the ordinary completion path.

When review needs a standalone body-level language check, run:

```powershell
pwsh -NoProfile -File <runtime>\skills\project-bootstrap\scripts\audit_memory_language.ps1 -ProjectDir <project> -ExpectedLanguage zh-CN -IncludeSpecs -IncludeCommands -Json
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

## Validation For Public Changes

When changing this public repository, run:

```powershell
git diff --check
pwsh -NoProfile -File scripts/validate-release.ps1 -ScratchRoot <scratch-root>
```

The release validator checks the language-scoped template structure, legacy
template-path audit, upgrade-flow coverage, and public/private boundary rules.
