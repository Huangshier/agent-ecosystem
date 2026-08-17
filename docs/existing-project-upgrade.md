# Existing Project Upgrade Path

本文适用于已经有 runtime 或 `.agents` content、需要在不丢失 project-owned
context 的前提下进入当前 C3.3 workspace 的 project。它把安全的 scaffold
refresh 与 legacy project migration 分开。

New empty project 应使用 [minimal project adoption walkthrough](walkthroughs/minimal-project-adoption.md)。
本文假设 project 已有 local memory、Spec，以及可能已经生成的 context entry。

## 应该使用哪条路径？

| 目标 | Recommended path |
| --- | --- |
| 在 new project 中采用 Agent Ecosystem | 使用 minimal project adoption walkthrough。 |
| 刷新 existing project 中缺失的 scaffold file | 执行保守的 `project-bootstrap` refresh；保留 project-specific content。 |
| 只升级未修改的旧 template | 检查当前 project memory language 后使用 `-RefreshUnmodifiedTemplates`。 |
| 修改 project memory language | 使用保守的 language migration Analyze -> Plan -> Apply -> Validate flow。 |
| 将 legacy project 迁移到 C3.3 | 运行 `scripts/migrate-project.ps1` 的 Analyze -> explicit Apply -> guarded Rollback。 |
| 丢弃旧 scaffold customizations | 仅在调用方明确确认 backup 后可以覆盖旧 scaffold content 时使用 `-ForceResetScaffold`；它不是 legacy migration authority。 |
| 只检查当前状态 | 不使用 apply mode，运行 `status.ps1`、`project-workspace check` 和 `project-workspace discover`。 |

## Command Ownership 边界

当前 Runtime 的 command ownership boundary 如下：

- `project-bootstrap` 负责 fresh scaffold creation、safe refresh、unmodified
  template refresh，以及显式的 backup-first force reset。
- `project-workspace` 负责 read-only workspace checks/discovery、canonical
  Work/Context/Procedure/Spec asset 的 discovery 和 authoring，以及通过
  `create-spec` 创建 durable Spec。
- `scripts/status.ps1` 从 `project.workspace` authority 报告顶层 Project status；
  不使用 retired memory helper。
- Runtime-level `scripts/migrate-project.ps1` 是 legacy project migration 的唯一
  current authority，提供 Analyze、explicit Apply 和 guarded Rollback mode。

旧的 bootstrap upgrade switch 和 helper 仅作为 compatibility 或 historical
surface 保留。它们不会使 retired Runtime Skill 重新 active，也不得作为 C3.3
legacy migration path。保留的 command boundary 和 standalone runtime packaging
constraint 见 [Project Bootstrap Command Boundaries](project-bootstrap-command-boundaries.md)。

## 当前 Template Model

public template model 使用 language-scoped project-memory templates：

```text
knowledge-hub/templates/languages/<language>/project-root|project-agent/
skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/<language>/project-root|project-agent/
```

支持的 public project-memory template language 是 `en` 和 `zh-CN`。English 仍是
public default 和 fallback language。当前 `recommended`、`full` 和 `dev` profile
安装 active C3.3 Runtime authority；`project-bootstrap` 和 `project-workspace`
是当前 Runtime Skill。它们不安装 retired `project-context-gate`、
`workflow-spec-lite` 或 `memory-governance` Skill。

不要将 legacy template directory 重新创建为 compatibility mirror。旧 path
reference 应作为 historical record 或 cleanup finding 处理，而不是 supported
current entrypoint。

## 保留 Local Memory

Existing project content 属于 project-owned。public template 是缺失文件、exact
template replacement 和可 review migration evidence 的 structural baseline，
不授权覆盖 project-specific memory。

应保留以下 local content：

- 包含 active project state 或 stable fact 的 `.agents/process.txt`、
  `.agents/plan.md` 和 `.agents/notes.md`。
- runtime work 创建的 `.agents/context/experience/` entry。
- project 添加了这些 local routing folder 时的 `.agents/context/patterns/` 和
  `.agents/context/standards/`。
- 定义 local goal、decision 或 acceptance evidence 的 `docs/specs/**` work
  package。
- 任何不完全匹配 public scaffold 的 project-specific command、context index 或
  note。

此保留规则适用于正在升级的 target project。canonical C3.3 project asset root
是 Work、Context、Procedure 和 Spec；migration 必须处理每个已声明的 target，
并将 unsupported 或 ambiguous legacy content 留给 human disposition。public
`agent-ecosystem` source repository 用 GitHub issue 和 pull request 记录自身
maintenance，不把 root `docs/specs/**` 作为 maintenance work package 跟踪。

## Intent 快速参考

选择 tool mode 前先明确使用意图：

- Refresh 或 template upgrade：保留 project-specific memory；补充缺失 scaffold，
  按请求更新仍匹配旧 template 的文件，并将已 custom 的文件送交 review。
- Language migration：在 `en` 和 `zh-CN` 之间变更 project memory。使用 target
  language template，review target-language narrative draft，并保持 command、
  path、API、filename、raw error 和 code symbol 等 protected literal 原文。
- Reset 或 reinitialize：仅当调用方明确说可以丢弃旧 memory 时，才丢弃 scaffold
  customization。这是 `-ForceResetScaffold` path，不是 refresh、upgrade、
  migrate 或 reinitialize 的默认含义。

可复制的 prompt：

```text
请保守刷新当前项目的工程记忆模板，保留项目特化内容，只更新安全的共享骨架和规则。
```

```text
请保守刷新当前项目的工程记忆模板，保留项目特化内容，只更新安全的共享骨架和规则。
```

```text
请把当前项目工程记忆迁移到 zh-CN。模板部分替换为中文模板，项目特化叙述内容翻译成中文供 review；命令、路径、API、文件名、错误文本和代码符号保持原文。
```

```text
请把当前项目工程记忆迁移到 zh-CN。模板部分替换为中文模板，项目特化叙述内容翻译成中文；命令、路径、API、文件名、错误文本和代码符号保持原文。
```

```text
请重新初始化工程记忆，不保留旧内容。我确认可以在备份后覆盖旧脚手架。
```

```text
请重新初始化工程记忆，不保留旧内容。我确认可以在备份后覆盖旧脚手架。
```

## Upgrade Flow

legacy project 使用当前 C3.3 flow：

`Analyze -> explicit Apply -> guarded Rollback`，随后执行 read-only status 和
workspace check。scaffold refresh 仍是独立的 `project-bootstrap` operation，不是
implicit migration。

scaffold refresh 前，从 project 的 `.agents/AGENTS.md` 或现有
`.agents/hub.lock.json` 的 `project_language` field 确定 project memory
language。当 `project-bootstrap` 可能创建缺失 scaffold 或 lock metadata 时，
使用 `-ProjectLanguage` 显式传入该 language。不要从当前 chat 推断 project
memory language。此 language check 不能替代 `scripts/migrate-project.ps1` 要求
的 migration evidence。

1. 不编辑文件，检查已安装的 Runtime 和 project。

   ```powershell
   pwsh -NoProfile -NonInteractive -File <runtime>\scripts\status.ps1 -RuntimeDir <runtime> -ProjectDir <project> -Json
   pwsh -NoProfile -NonInteractive -File <runtime>\skills\project-workspace\scripts\check-project-workspace.ps1 -ProjectRoot <project> -Json
   pwsh -NoProfile -NonInteractive -File <runtime>\skills\project-workspace\scripts\discover-project-assets.ps1 -ProjectRoot <project> -Query <query> -Json
   ```

2. 如果 workspace 是 legacy，或 status result 为 `migration-required`，使用
   Runtime-level migration authority 创建 deterministic migration evidence。
   Analyze 严格为 read-only。

   ```powershell
   pwsh -NoProfile -NonInteractive -File <runtime>\scripts\migrate-project.ps1 -Mode Analyze -ProjectRoot <project> -Json
   ```

3. Review Analyze evidence。确认 Work / Context / Procedure / Spec plan、project
   language、workspace model 和 project-specific preservation decision。
   Unsupported 或 ambiguous material 仍作为 human-disposition finding 保留。

4. 仅在显式确认后 Apply 已 review 的 evidence。Apply 会在修改 migration target
   前创建并验证完整的 project-owned backup。

   ```powershell
   pwsh -NoProfile -NonInteractive -File <runtime>\scripts\migrate-project.ps1 -Mode Apply -ProjectRoot <project> -AnalyzeEvidence <analyze-json> -ConfirmMigration -Json
   ```

5. 使用 read-only status 和 workspace check 验证结果。

   ```powershell
   pwsh -NoProfile -NonInteractive -File <runtime>\scripts\status.ps1 -RuntimeDir <runtime> -ProjectDir <project> -Json
   pwsh -NoProfile -NonInteractive -File <runtime>\skills\project-workspace\scripts\check-project-workspace.ps1 -ProjectRoot <project> -Json
   pwsh -NoProfile -NonInteractive -File <runtime>\skills\project-workspace\scripts\discover-project-assets.ps1 -ProjectRoot <project> -Query <query> -Json
   ```

6. 如果 unchanged-project guard 允许 rollback，使用 Apply 返回的 backup ID。
   Rollback 会保留 backup；如果 Apply 后 migration-relevant project content
   发生变化，则 fail closed。

   ```powershell
   pwsh -NoProfile -NonInteractive -File <runtime>\scripts\migrate-project.ps1 -Mode Rollback -ProjectRoot <project> -BackupId <backup-id> -ConfirmRollback -Json
   ```

变更 project-memory language 时，使用带有 explicit source 和 target language 的
保守 language migration Analyze、Plan、Apply 和 Validate mode。Phase 1 替换
template 并 stage project-specific content；Phase 2 应用已 review 的
target-language narrative，同时保留 protected literal。Manual-review-only
artifact 只用于 uncertain 或 unsupported content，不是普通完成路径。

project-memory language migration 需要单独进行 body-level language check 时，
运行：

```powershell
pwsh -NoProfile -NonInteractive -File <runtime>\skills\project-bootstrap\scripts\audit_memory_language.ps1 -ProjectDir <project> -ExpectedLanguage zh-CN -IncludeSpecs -IncludeCommands -Json
```

该 audit 是 read-only。它报告可能的 body-language mismatch，但不翻译或重写
project memory。language migration validator 使用相同的 audit evidence，因此
残留的 source-language blocker 会阻止宣称 migration 已完成。

## 处理旧 Path Reference

编辑前先对旧 path reference 分类：

- active setup、install、bootstrap、migration 或 upgrade guidance 应迁移到
  `templates/languages/<language>/project-root|project-agent/` model。
- historical release note、closed Spec 和 old experience entry 只有明确标记为
  legacy、deprecated、removed、superseded 或 historical state 时，才可以保留
  old path。
- 不要仅因为 generated 或 local project record 提到 old path 就删除它。保留
  record，并在 path 属于历史内容时添加简短说明。

不要为旧 template directory 添加 compatibility mirror。如果 local tool 仍依赖
old path，更新该 tool，或把 compatibility layer 留在 local project 内，不要放入
public kernel。

## Historical Compatibility Wording

旧 release record 和 mechanical validator 仍保留 `memory_upgrade.ps1`、
`-Mode Analyze`、`-AnalyzeMemoryUpgrade`、`ApplyMemoryUpgrade` 和 `Validate`。
这些词描述 C3.3 之前的 `language-scoped project-memory templates` flow 及其
`analyze -> plan -> backup -> apply -> validate` wording，其中包括
`memory-only and no-edit` distinction；rule `Do not recreate legacy template directories`；
与之配套的 `missing scaffold files` 也是保留的历史机器词。
它们仅是 historical 或 compatibility reference，不是当前 legacy migration
authority。当前 migration 使用 `scripts/migrate-project.ps1`；
retired `project-context-gate`、`workflow-spec-lite` 和 `memory-governance`
helper 不是 current Runtime entrypoint。

## Public Change 验证

本 public repository 的普通文档变更使用 affected validation contract：

```powershell
git diff --check
pwsh -NoProfile -NonInteractive -File scripts/invoke-local-validation.ps1 -Stage iteration
pwsh -NoProfile -NonInteractive -File scripts/invoke-local-validation.ps1 -Stage pre-push
```

当 classifier 选择 targeted documentation 或 workspace-consumer check 时运行它们，
并完成 Public Reader Review。完整 Release validator 仅保留给明确的
Release/checkpoint decision。
