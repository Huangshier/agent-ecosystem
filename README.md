# Agent Ecosystem

English: [README.en.md](README.en.md) | 简体中文（当前）

> 面向 Agent 辅助软件项目的轻量工作流内核（Workflow Kernel）。

当前版本：`v0.6.0`

## 1. 项目解决什么问题

### 一句话理解

Agent Ecosystem 提供一组可安装、可验证、可扩展的基础工作流，帮助 coding agent
可靠地读取项目规则、恢复上下文、固化复杂任务意图，并把项目记忆与可复用经验放在正确层级。

它适合希望改善以下工作的维护者和团队：

- 让 Codex、Claude Code 或其他 agent 在开始任务时加载正确的项目约束；
- 用热记忆和可选工作包跨会话保留状态、范围与验收证据；
- 安全地安装、检查和更新共享 runtime，同时保留项目特化内容；
- 将项目经验与跨项目公共知识分层维护。

它不是 agent runtime、模型编排框架或任务调度器，也不要求所有项目复制同一种流程。
公开仓库只保存 public-safe 的工作流内核；private overlay、凭据、本机迁移记录、敏感审计
材料和生成的 runtime metadata 必须留在公开仓库之外。

## 2. Release → Runtime → Agent bridge → Project

### 分层模型

```text
Release → installed Runtime → optional Agent bridge → Project
```

- **Release**：版本化、可审阅的 public source。先选择 release 或明确的 source revision，
  再从该来源安装；参见 [Release notes](docs/releases/README.md)。
- **Runtime**：安装到 `$HOME/.agents` 或其他目标目录的独立工作流副本，包含 skills、
  knowledge hub、`install-manifest.json` 和 `install-report.json`。
- **Agent bridge**：可选的显式发现层，把已安装 runtime 中选定的 skills 链接到已验证的
  agent client skill 目录。普通安装不会自动创建 bridge。
- **Project**：目标项目自己的行为契约、工程记忆和可选工作包。它们属于目标项目，不属于
  runtime 或本仓库。

在项目层，根 `AGENTS.md` 是唯一完整的项目行为契约。`.agents/AGENTS.md` 是工程记忆
指南，说明如何读取和维护 `.agents/`；它不是第二份行为契约。`.agents/process.txt` 与
`.agents/plan.md` 保存热状态，`.agents/context/` 保存按需发现的知识，`docs/specs/`
可供目标项目保存跨会话工作包。

完整边界见 [Architecture](docs/architecture.md) 和
[Runtime adoption bridge](docs/runtime-adoption-bridge.md)。

## 3. 首次安装

### 5 分钟上手

1. 从选定的 release/source checkout 安装 `recommended` profile。普通安装默认创建
   独立副本，并可安全增量重跑：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Profile recommended
   ```

   评估时可以先使用隔离目录：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Profile recommended -TargetDir <temp-runtime>
   ```

   只有贡献者需要 runtime 直接跟随 source checkout 时才使用 `-DevLink`。`-Copy` 仍是
   默认复制模式的兼容写法；`-ReplaceManaged` 只应在审阅冲突并决定覆盖受管内容后使用。

2. 如 agent client 需要专用 skill 目录，显式创建可选 bridge：

   ```powershell
   pwsh -NoProfile -File .\scripts\link-agent-skills.ps1 `
     -RuntimeDir <runtime> `
     -AgentSkillsDir <agent-skills-dir> `
     -Skill project-bootstrap,project-context-gate
   ```

   两个目录都必须显式提供；工具不会猜测 client 路径。完整预检、冲突与 metadata 契约见
   [Agent-specific skill link bridge](docs/agent-skill-bridge.md)。

3. 初始化目标项目，并明确项目记忆语言：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ProjectLanguage zh-CN
   ```

4. 在首次非平凡任务前运行 context gate：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>\skills\project-context-gate\scripts\context_gate.ps1 -ProjectRoot <project>
   ```

非 Windows 系统或已安装 PowerShell 7+ 时，可将命令前缀换为
`pwsh -NoProfile -File`。参见 [Shell strategy](docs/shell-strategy.md)。

### Profiles

- `minimal`：安装 bootstrap skill 和 public knowledge hub templates。
- `recommended`：安装工作流内核和 public knowledge hub。
- `full`、`dev`：当前与 `recommended` 相同，为未来 public domain packs 和维护工具预留。

Profile 生命周期见 [Domain pack governance](docs/domain-pack-governance.md)。

## 4. 日常使用

每次非平凡任务使用同一条短路径：

1. 从项目根 `AGENTS.md` 读取唯一完整的行为契约。
2. 运行 `project-context-gate`，渐进加载热记忆、active work package 和相关上下文。
3. 对需要跨会话保留目标、非目标、风险与验收的任务，使用 `workflow-spec-lite` 在目标
   项目本地创建 `docs/specs/<slug>/spec.md`。
4. 实现并运行项目自己的验证。
5. 在交接或阶段收尾时使用 `memory-governance`，压缩热记忆并把稳定事实和经验路由到
   正确位置。

空项目的完整示例见
[Minimal project adoption walkthrough](docs/walkthroughs/minimal-project-adoption.md)；适配原则见
[How to adapt](docs/how-to-adapt.md)。

## 5. 更新 Runtime

Runtime 更新与项目刷新是两个独立动作。更新 runtime 不会自动重写项目记忆，也不会自动
创建或修复 agent bridge。

1. 获取目标 release/source revision，并从该 checkout 重跑安装器：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Profile recommended -TargetDir <runtime>
   ```

2. 查看 `install-report.json`。默认增量更新会恢复缺失的受管文件、更新 source 已变化但
   本地未修改的文件，并保留未知文件与本地修改；冲突不会被静默覆盖。
3. 检查 runtime 与 bridge 的只读状态：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\status.ps1 -RuntimeDir <runtime>
   ```

4. 只有在审阅冲突后才选择 `-ReplaceManaged`；只有 bridge 预检仍满足时才按既有显式参数
   重跑 bridge helper。

从旧版本升级时，先查看 [Old-release upgrade path](docs/old-release-upgrade-path.md)。

## 6. 检查与刷新已有项目

先检查，再选择保守刷新、迁移或重置：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\status.ps1 -RuntimeDir <runtime> -ProjectDir <project> -Json
powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>\skills\project-context-gate\scripts\context_gate.ps1 -ProjectRoot <project>
```

- `current`：已检查的项目基线与工程记忆不需要刷新。
- `optional-refresh`：存在模板基线漂移或缺失的脚手架；默认 bootstrap 保留项目特化内容，
  `-RefreshUnmodifiedTemplates` 只更新仍匹配旧模板的文件。
- `migration-required`：先运行 `memory_upgrade.ps1 -Mode Analyze`，再执行可审阅、backup-first
  的 Plan → Apply → Validate 流程。
- `unknown`：helper、lock、语言或 metadata 无法可信解析；先人工检查，不要猜测或强制覆盖。

“刷新”默认意味着保留项目特化内容。只有调用者明确允许丢弃旧脚手架定制时，才使用
backup-first 的 `-ForceResetScaffold`。完整决策表与命令见
[Existing project upgrade path](docs/existing-project-upgrade.md#intent-quick-reference)。

## 7. 常见状态与故障

`scripts/status.ps1` 是只读聚合器；它不会联网、安装、刷新、修复或删除内容。

| 区域 | 常见状态 | 下一步 |
| --- | --- | --- |
| Runtime managed files | `current` | 无需操作。 |
| Runtime managed files | `modified` / `missing` / `conflict` | 查看受管问题与 `install-report.json`；重新安装前先审阅本地修改。 |
| Runtime provenance | `not-recorded` / `unknown` | 这不等于损坏；source archive 等安装可能没有 Git provenance。 |
| Agent bridge | `not-configured` | 仅表示此 runtime 没有 bridge manifest；若需要 client discovery，再显式配置。 |
| Agent bridge | `stale` / `broken` / `conflict` / `unknown` | 按 bridge 文档检查受管 source、目标 link 与占用内容；status 不会自动修复。 |
| Project | `optional-refresh` | 使用保守 refresh，保留项目特化内容。 |
| Project | `migration-required` | 走 Analyze → Plan → backup → Apply → Validate。 |
| Project | `unknown` | 检查 helper 可用性、hub lock、项目语言与诊断输出，保持 fail-soft。 |

需要结构化输出时添加 `-Json`。状态字段的精确定义见 [Scripts](scripts/README.md)，bridge
故障边界见 [Agent-specific skill link bridge](docs/agent-skill-bridge.md)，项目迁移故障见
[Existing project upgrade path](docs/existing-project-upgrade.md)。

## 8. 高级架构和维护者文档入口

### 示例和常见任务路径（Examples And Common Paths）

- 从空项目开始：[Minimal project adoption walkthrough](docs/walkthroughs/minimal-project-adoption.md)
- 适配现有项目：[How to adapt](docs/how-to-adapt.md)
- 查看最小布局：[Examples](examples/README.md) 与
  [examples/minimal-project](examples/minimal-project/README.md)
- 维护项目记忆：[Language policy](docs/language-policy.md) 与
  [Agent governance](docs/agent-governance.md)
- 理解目标项目工作包：[Target-project spec lifecycle](docs/spec-lifecycle.md)

高级架构：

- [Architecture](docs/architecture.md)
- [Runtime adoption bridge](docs/runtime-adoption-bridge.md)
- [Agent-specific skill link bridge](docs/agent-skill-bridge.md)
- [Knowledge catalog](knowledge-hub/knowledge-catalog.md)
- [Claude Code hooks guardrails](docs/claude-code-hooks-guardrails.md)

维护者入口：

- [Release notes](docs/releases/README.md)
- [Release process](docs/release-process.md)
- [Release readiness](docs/release-readiness.md)
- [Domain pack governance](docs/domain-pack-governance.md)
- [Shell strategy](docs/shell-strategy.md)

Issues 与 pull requests 应保持 scope 清晰、可验证且 public-safe。不要提交 private overlay、
本机路径、凭据、敏感审计材料或生成的 runtime metadata。

## License

MIT
