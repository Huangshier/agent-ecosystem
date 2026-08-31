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
- private control docs 和 private memory 遵循 private repository 自己的行为
  authority；
- project-local memory 遵循 target-project 的 root `AGENTS.md` 与当前 C3.3
  workspace contract；
- code identifiers、commands、paths、APIs、file names、Markdown field labels
  和 raw error text 可以保留英文或原文。

可复用的双边界说明见
[Bilingual Public/Private Routing](../knowledge-hub/knowledge/standards/bilingual-public-private-routing.md)。

## B. Target-Project ProjectLanguage And Runtime Language Behavior

以下规则只描述 target-project 的工程记忆和 Runtime 行为，不规定本公开仓库
的 Issue/PR 治理语言。

### Fresh C3.3 Contract

fresh bootstrap 支持 `en` 和 `zh-CN` 两个 `ProjectLanguage` 值；未显式传入时
默认使用 `en`。agent 或 workflow 可以在首次 bootstrap 时明确选择：

```powershell
pwsh -NoProfile -File .\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ProjectLanguage en
pwsh -NoProfile -File .\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ProjectLanguage zh-CN
```

`project-bootstrap` 不自行推断 chat language。fresh C3.3 路径从
`skills/project-bootstrap/assets/c3-3-project-template/<language>/` 选择模板，
写入对应语言的 root `AGENTS.md` 与 `.agents/README.md`，并把规范化后的值保存为
`.agents/hub.lock.json` 的 `project_language`。同一 lock 还记录
`workspace_model = "c3.3"`；`hub_dir = ""` 是 active C3.3 的预期状态。

root `AGENTS.md` 是项目行为 authority；`.agents/hub.lock.json` 是 bootstrap
metadata，不是第二份行为契约。fresh bootstrap 同时写入 `.agents/.gitignore`，
并创建 `.agents/work/`、`.agents/context/`、`.agents/procedures/`、
`.agents/skills/` 与 `docs/specs/` 空根目录，不创建占位 canonical asset。

fresh/default 路径不创建 nested project guide、hot-memory 文件、command index、
`CLAUDE.md` 或 legacy `.claude/**` scaffold。`-ProjectLanguage` 也不会把这些
retired surface 恢复为语言 authority。

对已经定制的 C3.3 项目，bootstrap 默认保留已有文件。不要把语言参数理解为
自动翻译或覆盖授权；需要改变现有叙述语言时，应先审阅 project-owned content
与目标项目自己的约束。

### Legacy Language Migration (Compatibility-Only)

以下行为只适用于 existing legacy project，不是 fresh/default C3.3 adoption path：

- legacy project 可能仍有 `.agents/AGENTS.md`、hot memory、
  `.agents/commands/`、`CLAUDE.md` 或 `.claude/**` project-owned content；
- wrapper 优先读取 `.agents/hub.lock.json` 的 `project_language`，仅在 lock
  没有语言值时把 nested guide declaration 作为 compatibility fallback；互相
  冲突的声明会在写入前失败；
- `knowledge-hub/templates/languages/<language>/project-root|project-agent/` 及
  bundled `assets/knowledge-hub-template/` 是 legacy scaffold、upgrade 和
  language-migration template source，不是 fresh C3.3 template authority；
- legacy template 的 `zh-CN` 文件缺失时可以回退到对应 English template，并
  报告 fallback metadata 供验证处理。

不要对 fresh C3.3 project 运行这些 language-migration 或 first-session helper；
其语言已经由 C3.3 lock 记录，这些 helper 会面向 legacy surface 规划动作。

legacy language migration 保留明确方向、proposal-first 与 backup-first 契约：

```powershell
pwsh -NoProfile -File .\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -AnalyzeLanguageMigration -SourceLanguage en -TargetLanguage zh-CN
pwsh -NoProfile -File .\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -PlanLanguageMigration -SourceLanguage en -TargetLanguage zh-CN
pwsh -NoProfile -File .\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ApplyLanguageMigration -MigrationPlan <proposal.json>
pwsh -NoProfile -File .\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ValidateLanguageMigration -MigrationPlan <proposal.json>
pwsh -NoProfile -File .\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -PlanNarrativeMigration -MigrationPlan <proposal.json>
pwsh -NoProfile -File .\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ApplyNarrativeMigration -MigrationPlan <narrative-proposal.json>
pwsh -NoProfile -File .\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ValidateNarrativeMigration -MigrationPlan <narrative-proposal.json>
```

反向迁移使用 `-SourceLanguage zh-CN -TargetLanguage en`。Plan 写入可审阅
proposal 并创建 Apply 所需 backup；Apply/Validate 在 proposal、backup、source
hash 或 recorded project path 失配时 fail closed。Narrative action 默认未批准，
必须先审阅目标语言文本。无法安全确定的内容保留并进入 manual review，不能静默
翻译或丢弃。

legacy review 需要独立 body-language audit 时可以运行：

```powershell
pwsh -NoProfile -File .\skills\project-bootstrap\scripts\audit_memory_language.ps1 -ProjectDir <project> -ExpectedLanguage zh-CN -IncludeSpecs -IncludeCommands -Json
```

该 helper 只读，不翻译、不重写、也不批准 migration。JSON 包含 resolved
`project_dir`；复制到公开产物前必须检查并去除 local path。

无论 fresh 或 legacy，filename、directory name、Markdown field label、command、
path、API name、code symbol 与 raw error text 均可保留 English 或原文。
