# Language Policy

本文件明确区分两种语言行为：本公开仓库的治理语言，以及
target-project 的 `ProjectLanguage` / Runtime 语言行为。两者不是同一套
产品语义。

## A. Public Repository Governance Language

本公开仓库的 maintainer-facing Issue/PR body、review、decision 和 closeout
默认使用简体中文。解释性正文优先中文，但不要求把整个仓库翻译成中文。

- Issue / PR title 可以使用简洁、稳定的英文技术标题，不强制双语。
- commit message 默认使用简洁英文，不重复写中英文两份。
- `labels`、`state`、`paths`、`commands`、code/API/config/JSON/YAML fields、
  `Refs #<number>` / `Fixes #<number>` 以及 raw errors/logs 保留英文或原文，
  以免破坏 GitHub、脚本和其他机器消费者。
- `README.md` 是项目选定的 Simplified Chinese repository homepage；
  `README.en.md` 是英文入口，`README.zh-CN.md` 保留为旧链接兼容 redirect。
- 新增或大幅改写的 maintainer-facing governance prose 默认遵循上述中文优先
  规则；既有英文文档不因本规则被要求全仓翻译。

## Conversation And Artifact Routing

用户对话可以遵循当前对话语言；public governance artifact 则遵循本段的
受众和机器契约，不把对话语言机械复制到所有文件。

在 public/private workflow 中：

- public GitHub Issue/PR 的解释性维护记录默认使用简体中文；
- private control docs 和 private memory 遵循 private repository 的
  `.agents/AGENTS.md`；
- project-local memory 遵循 target-project 的 `.agents/AGENTS.md`；
- code identifiers、commands、paths、APIs、file names、Markdown field labels
  和 raw error text 可以保留英文或原文。

可复用的双边界说明见
[Bilingual Public/Private Routing](../knowledge-hub/knowledge/standards/bilingual-public-private-routing.md)。

## B. Target-Project ProjectLanguage And Runtime Language Behavior

以下规则只描述 target-project 的工程记忆和 Runtime 行为，不规定本公开仓库
的 Issue/PR 治理语言。本 PR 不改变 existing runtime fallback、language
migration 或 `ProjectLanguage` product semantics。

## Project Memory

Project memory should follow the language declared by that project's
`Project Language Policy`. The authoritative declaration belongs in the
project's `.agents/AGENTS.md`.

Bootstrap templates install a `Project Language Policy` section into
`.agents/AGENTS.md`. If the project has not chosen a language yet, the first
non-trivial session that writes engineering memory should fill that section
from the user's primary language.

`project-bootstrap` provides a script-driven closeout path for that first write.
An agent or workflow can pass the user's primary language explicitly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ProjectLanguage en
powershell -NoProfile -ExecutionPolicy Bypass -File .\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ProjectLanguage zh-CN
```

On non-Windows systems, or when PowerShell 7+ is already available, use
`pwsh -NoProfile -File` with the same script arguments.

The helper does not infer chat language by itself. It writes the supplied
language into `.agents/AGENTS.md` and localizes the initial project memory
scaffolds for hot memory, `.agents/context/`, `.agents/commands/`, and
`docs/specs/`.

Project memory scaffolds are backed by tracked file templates under
`knowledge-hub/templates/languages/<language>/project-root|project-agent/` as
the repository authority, with a bundled runtime snapshot under
`skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/<language>/project-root|project-agent/`.
The only first-class template languages are `en` and `zh-CN`; this is not
arbitrary-language i18n. For target-project memory, English remains the default
and fallback language, so plain bootstrap is equivalent to `-ProjectLanguage en`.
If a `zh-CN` template file is missing, the helper falls back to the matching
English template and reports fallback metadata so validation can flag the gap.

For established project memory, changing the project memory language is a
conservative migration task, not a scaffold overwrite. Bootstrap preserves
existing files by default; migration work should follow a backup, analyze,
plan, review, apply, and validate flow. Force reset options are only for
intentional scaffold reset scenarios where project-specific memory can be
discarded.

Intent matters:

- Refresh or template upgrade preserves project-specific memory by default and
  updates only missing or unmodified scaffold surfaces unless a reviewed
  proposal says otherwise.
- Language migration changes the project-memory language with target-language
  templates and reviewed target-language narrative. Commands, paths, APIs,
  filenames, raw errors, and code symbols stay in their original form.
- Reset or reinitialize discards old scaffold customizations only when the
  caller explicitly says old project memory may be discarded. Do not treat
  refresh, upgrade, migrate, or casual reinitialization wording as reset
  permission.

The supported conservative language migration flow is explicit about direction:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -AnalyzeLanguageMigration -SourceLanguage en -TargetLanguage zh-CN
powershell -NoProfile -ExecutionPolicy Bypass -File .\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -PlanLanguageMigration -SourceLanguage en -TargetLanguage zh-CN
powershell -NoProfile -ExecutionPolicy Bypass -File .\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ApplyLanguageMigration -MigrationPlan <proposal.json>
powershell -NoProfile -ExecutionPolicy Bypass -File .\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ValidateLanguageMigration -MigrationPlan <proposal.json>
powershell -NoProfile -ExecutionPolicy Bypass -File .\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -PlanNarrativeMigration -MigrationPlan <proposal.json>
powershell -NoProfile -ExecutionPolicy Bypass -File .\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ApplyNarrativeMigration -MigrationPlan <narrative-proposal.json>
powershell -NoProfile -ExecutionPolicy Bypass -File .\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ValidateNarrativeMigration -MigrationPlan <narrative-proposal.json>
```

Use `-SourceLanguage zh-CN -TargetLanguage en` for the reverse direction. Plan
mode writes a reviewable proposal and creates the backup required by apply.
Apply mode refuses to write if the proposal, backup, or planned source hashes no
longer match. Apply and validate also refuse a proposal whose recorded project
path differs from the current `-ProjectDir`.

The narrative follow-up reads retained review artifacts and creates a second
proposal. It routes stable facts to durable context, active plan and process
state to concise hot memory updates, reusable lessons to
`.agents/context/experience/`, and durable specs to `docs/specs/`. Narrative
actions are unapproved by default; review the proposed target-language text
before applying it. The normal completion path applies reviewed narrative back
to project memory while protected literals stay unchanged. Manual-review-only
items are exception paths for uncertain or unsupported content.

For review-only body-language checks, run the standalone audit helper:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\skills\project-bootstrap\scripts\audit_memory_language.ps1 -ProjectDir <project> -ExpectedLanguage zh-CN -IncludeSpecs -IncludeCommands -Json
```

The audit ignores `Summary` / `Keywords` discovery metadata, fenced code, and
protected literals before reporting heuristic findings. It is read-only and
does not translate or rewrite project memory. Language migration validation
records this audit evidence and treats blocking source-language leftovers as a
completion failure. When using `-Json`, the output includes the resolved
`project_dir`; review or redact local paths before copying audit output into
public issues, pull requests, or documents.

The file templates are structural baselines for scaffold generation, language
updates, and conservative migration planning. They are not a reason to replace
customized project memory with generic scaffolds. Exact source-template matches
can be replaced with target-language templates. Project-specific narrative that
cannot be safely migrated deterministically is preserved verbatim and routed to
manual review instead of being silently translated or dropped. Concise hot
memory files route original source content to migration artifacts instead of
appending the full source back into `.agents/plan.md`, `.agents/process.txt`, or
`.agents/notes.md`.

Memory governance and upgrade diagnostics recognize English discovery headings
and localized Simplified Chinese equivalents for context discovery metadata.
For target-project memory only, Public templates remain English-first; this
existing runtime rule does not govern the public GitHub templates in `.github/`.

Filenames, directory names, Markdown field labels, commands, paths, API names,
and error text should remain in English or in their original form.
