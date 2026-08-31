# 如何适配 Agent Ecosystem

本指南说明如何在其他项目中使用 public Workflow Kernel，而不复制本仓库的
private workflow。

从空项目开始的完整 first-use path 见
[minimal project adoption walkthrough](walkthroughs/minimal-project-adoption.md).
已经存在 `.agents` memory 的项目使用
[existing project upgrade path](existing-project-upgrade.md).

## 1. 安装 Runtime

安装 recommended public runtime：

```powershell
pwsh -NoProfile -NonInteractive -File .\scripts\install.ps1 -Profile recommended
```

评估时先使用 temporary runtime：

```powershell
pwsh -NoProfile -NonInteractive -File .\scripts\install.ps1 -Profile recommended -TargetDir <temp-runtime>
```

默认模式是 standalone copy。重复运行同一命令会恢复缺失的 managed files，且
只更新 source 已变化并且 installed copy 没有被本地修改的文件。只有明确需要
source-linked development runtime 时才使用 `-DevLink`。既有 `-Copy` 调用继续
兼容。

每次运行都会写入 `install-report.json`。unknown files 会保留，并以 warning
status 和 exit code 0 报告。文件同时在本地和 source 中发生变化时，默认产生
conflict 并返回 non-zero exit。使用 `-AllowPartial` 接受 skipped conflicts，或
使用 `-ReplaceManaged` 覆盖 managed files，同时继续保留 unknown files。`-Force`
仍是 `-ReplaceManaged` 的 deprecated compatibility alias。

C3.3 entrypoints 使用 `pwsh -NoProfile -NonInteractive -File`（PowerShell Core
7.6+）。active Runtime Skills 是 `project-bootstrap` 和 `project-workspace`；
`project-context-gate`、`workflow-spec-lite` 和 `memory-governance` 已 retired，
当前 public profiles 不安装它们。

之后要移除 generated runtime，请使用 manifest-based uninstaller：

```powershell
pwsh -NoProfile -NonInteractive -File .\scripts\uninstall.ps1 -TargetDir <runtime>
```

对于 schema-2 copy items，uninstaller 会先检查每个 managed destination 中是否有
nested unknown files 或 locally modified managed files。任何 finding 都会在删除
前阻止整个 uninstall，并保留 manifest/report 供 review。clean copy items 和
dev links 继续使用基本的 manifest-based uninstall path；manifest destinations
之外的 paths 不会被触碰。Schema-1 manifests 不提供这种 file-level protection。
如果 manifest 缺失，则不会自动执行 cleanup。

## 2. Bootstrap 项目

从已安装的 runtime 运行 `project-bootstrap`：

```powershell
pwsh -NoProfile -NonInteractive -File <runtime>\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project>
```

当 agent 或 workflow 已知项目需要的语言时，在 fresh bootstrap 时显式设置
`ProjectLanguage`：

```powershell
pwsh -NoProfile -NonInteractive -File <runtime>\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ProjectLanguage en
pwsh -NoProfile -NonInteractive -File <runtime>\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ProjectLanguage zh-CN
```

该 script 不会自行推断 chat language。支持的 C3.3 template languages 只有 `en`
和 `zh-CN`；English 是默认与 fallback。fresh bootstrap 使用对应模板写入根
`AGENTS.md` 和 `.agents/README.md`，并把规范化值记录在
`.agents/hub.lock.json`。这是 scaffold-language feature，不是
arbitrary-language i18n。

对于 existing project，应把 bootstrap 视为 conservative scaffold refresh，而
不是 legacy migration：

- Default bootstrap 会复制缺失的 scaffold file，并保留 existing memory。
- legacy project 使用
  [existing project upgrade path](existing-project-upgrade.md)，其唯一 migration
  authority 是 `<runtime>\scripts\migrate-project.ps1`。
- 只有希望仍匹配 previous installed template hash 的文件接收新 template 时，
  才使用 `-RefreshUnmodifiedTemplates`。
- 不要使用 reset language 进行 memory migration。使用 Analyze、Plan、Apply 和
  Validate flows，确保 project-specific content 在应用变更前经过 review 并完成
  backup。
- **Compatibility-only：** established legacy project memory language 变更使用
  带有明确方向的 conservative language migration switches，例如
  `-AnalyzeLanguageMigration -SourceLanguage en -TargetLanguage zh-CN`，然后使用
  `-PlanLanguageMigration`、`-ApplyLanguageMigration -MigrationPlan
  <proposal.json>` 和 `-ValidateLanguageMigration -MigrationPlan
  <proposal.json>`。
- 对 retained manual-review artifacts，继续使用
  `-PlanNarrativeMigration -MigrationPlan <proposal.json>`，review 并批准生成的
  `narrative-proposal.json`，然后运行 `-ApplyNarrativeMigration` 和
  `-ValidateNarrativeMigration`。
- `-ForceResetScaffold` 仅用于有意丢弃 scaffold customizations。它会先发出
  warning 并 backup，但不是 conservative language migration path。

runtime-level legacy migration command 遵循 proposal-first 和 backup-first：

```powershell
pwsh -NoProfile -NonInteractive -File <runtime>\scripts\migrate-project.ps1 -Mode Analyze -ProjectRoot <project> -Json
pwsh -NoProfile -NonInteractive -File <runtime>\scripts\migrate-project.ps1 -Mode Apply -ProjectRoot <project> -AnalyzeEvidence <analyze-json> -ConfirmMigration -Json
pwsh -NoProfile -NonInteractive -File <runtime>\scripts\migrate-project.ps1 -Mode Rollback -ProjectRoot <project> -BackupId <backup-id> -ConfirmRollback -Json
```

## 3. 使用 Workflow Kernel

对非 trivial work，先读取根目录 `AGENTS.md`，再使用
`project-workspace` 的 `discover` / `check` 渐进发现 canonical Work、Context、
Procedure 和 Spec asset。不要把 retired 的 context-gate 或 memory-governance
helper 当作当前 entrypoint。

fresh C3.3 bootstrap 不生成 client-specific startup 或 hook scaffold。项目已在
`.agents/skills/` 发布本地 Skill 且需要 Claude Code discovery 时，可显式创建
`project-workspace` 的 `claude-code` adapter：

```powershell
pwsh -NoProfile -NonInteractive -File <runtime>\skills\project-workspace\scripts\project-workspace.ps1 -Operation create-adapter -ProjectRoot <project> -Target claude-code -Json
```

该 adapter 只管理 `.agents/skills/<name>` 到 `.claude/skills/<name>` 的派生副本；
它不创建行为入口、不修改 `.gitignore`，也不改变权限或外部写入授权。

在 target project 中，需要 durable goal、non-goal、acceptance evidence、risk
或 multi-phase execution 时，使用 `project-workspace create-spec`。

在交接时，使用 `project-workspace` 的 Work/Context continuity operation 记录
未完成工作和稳定事实。

打开单个 reusable knowledge entry 前，先查看 public
`knowledge-hub/knowledge-catalog.md`。

Codex、Claude Code 和 generic agent 的 runtime-specific startup path 见
[runtime adoption bridge](runtime-adoption-bridge.md)。

## 4. 保持层次分离

- Public source：可复用的 kernel 和 public-safe knowledge。
- Runtime：安装到 `$HOME/.agents` 或其他 target 的 generated runtime。
- Project local：target project 内的 `.agents/` 和可选 `docs/specs/`。
- Private overlay：位于本 public repository 之外的可选 private profile、skill 和
  knowledge。

本 public repository 使用 GitHub issue 和 pull request body 作为 maintenance
record。默认不要把它历史上的根目录 `docs/specs/**` work-package pattern 复制
到 public maintenance 中。

不要把 public tree 复制到 private overlay；只添加 private increment。

## 5. 验证设置

建议运行以下 workspace checks：

```powershell
pwsh -NoProfile -NonInteractive -File <runtime>\skills\project-workspace\scripts\check-project-workspace.ps1 -ProjectRoot <project> -Json
pwsh -NoProfile -NonInteractive -File <runtime>\skills\project-workspace\scripts\discover-project-assets.ps1 -ProjectRoot <project> -Query <query> -Json
```

对于本 public repository 的普通文档变更，运行 classifier-selected affected
`iteration` 和 `pre-push` validation，并执行 `git diff --check` 和 Public Reader
Review。完整 Release validator 仅用于明确的 Release/checkpoint decision；只有
存在该 decision 时才运行：

```powershell
pwsh -NoProfile -NonInteractive -File .\scripts\validate-release.ps1 -ScratchRoot <scratch-root>
```

## 示例

参见 [examples/minimal-project](../examples/minimal-project/README.md)，其中有
展示目标文件布局的 project-local scaffold。完整 adoption sequence 见
[minimal project adoption walkthrough](walkthroughs/minimal-project-adoption.md).
