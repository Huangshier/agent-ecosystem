# Agent Ecosystem

English: [README.en.md](README.en.md) | 简体中文（当前）

> 面向 agent-assisted software projects（Agent 辅助软件项目）的轻量
> Workflow Kernel（工作流内核）。

当前版本：`v0.4.3`

## 一句话理解

Agent Ecosystem 提供一组可安装、可验证、可扩展的基础工作流，帮助团队把
agent 协作中的项目记忆、上下文加载、轻量规格、记忆维护和可复用知识沉淀成
稳定的工程习惯。

它不是把每个项目都改造成同一种流程，而是提供一个 public-safe kernel。团队
可以从这个 kernel 开始，再把自己的 `.agents/` 记忆、`docs/specs/` 工作包、
领域知识和自定义 skills 叠加到项目本地。

## 适合谁

- 想让 Codex 或其他 coding agents 更可靠地读项目规则、记住上下文、交付可复核
  工作的维护者。
- 需要把 agent 会话中的临时计划沉淀为长期 `docs/specs/` 工作包的团队。
- 希望把项目经验、踩坑记录和跨项目知识分层管理的人。
- 想用 PowerShell-first 脚本安装、验证、刷新 workflow kernel 的项目。

## 不适合什么

- 它不是 agent runtime。
- 它不是模型编排框架。
- 它不是任务调度系统。
- 它不是要求所有项目原样照搬的万能流程。
- 它不存放 private overlay、本机迁移记录、凭据、敏感审计结果或生成的 runtime
  manifest。

## 核心工作流

1. 安装 runtime：把公开 Workflow Kernel 安装到 `$HOME/.agents` 或指定目录。
2. 初始化项目：用 `project-bootstrap` 生成项目级 `AGENTS.md`、`.agents/` 和
   `docs/specs/` 骨架。
3. 进入任务：用 `project-context-gate` 渐进读取项目指令、热记忆、active specs
   和相关上下文。
4. 固化意图：用 `workflow-spec-lite` 为非平凡工作建立轻量 spec，记录目标、非目标、
   约束和验收证据。
5. 收尾维护：用 `memory-governance` 压缩热记忆，把稳定事实、经验和下一步路由到正确
   位置。

## 5 分钟上手

安装 recommended profile：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Profile recommended
```

评估时建议先安装到临时 runtime：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Profile recommended -TargetDir <temp-runtime> -Copy -Force
```

初始化一个项目：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project>
```

如果首次写入项目记忆时已经知道项目记忆语言，可以显式指定：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>\skills\project-bootstrap\scripts\bootstrap_project.ps1 -ProjectDir <project> -ProjectLanguage zh-CN
```

进入项目任务前运行 context gate：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <runtime>\skills\project-context-gate\scripts\context_gate.ps1 -ProjectRoot <project>
```

然后让 agent 使用 `workflow-spec-lite` 为非平凡任务建立
`docs/specs/<slug>/spec.md`，再执行实现和验证。

非 Windows 系统，或已经安装 PowerShell 7+ 时，可以把
`powershell -NoProfile -ExecutionPolicy Bypass -File` 换成
`pwsh -NoProfile -File`。更多细节见 [Shell strategy](docs/shell-strategy.md)。

## 采用后会出现什么

在 runtime 侧，安装器会生成 skills、knowledge hub 和 `install-manifest.json`。
manifest 可能包含本机绝对路径，不应提交到项目仓库。

在项目侧，bootstrap 通常会创建或维护：

- `AGENTS.md`：项目级 agent 入口和 fallback 指令。
- `.agents/`：本地运行态记忆、上下文索引、命令卡和经验记录。
- `docs/specs/`：跨会话保留的工作包、任务清单和 spec 模板。

每个项目可以选择自己的项目记忆语言。命令、路径、API、文件名、代码符号和原始错误文本
可以保留原文。

## 分层模型

- Public source：本仓库，保存 public-safe kernel、脚本、模板和文档。
- Runtime layer：安装到 `$HOME/.agents` 或其他目标目录的可执行工作流层。
- Project local layer：目标项目自己的 `.agents/` 和 `docs/specs/`。
- Private overlay：可选的私有 profiles、skills、knowledge 和迁移记录，放在公开仓库之外。

## Profiles

当前公开 profiles：

- `minimal`：安装 bootstrap skill 和 public knowledge hub templates。
- `recommended`：安装 Workflow Kernel 和 public knowledge hub。
- `full`：当前安装内容与 `recommended` 相同。
- `dev`：当前安装内容与 `recommended` 相同。

`full` 和 `dev` 预留给未来可安装的 public domain packs 和 developer maintenance
tooling。当前不会额外启用 domain-pack content。生命周期和 profile 边界见
[Domain pack governance](docs/domain-pack-governance.md)。

## 示例和常见任务路径

- 从空项目开始：[Minimal project adoption walkthrough](docs/walkthroughs/minimal-project-adoption.md)
- 适配到现有项目：[Existing project upgrade path](docs/existing-project-upgrade.md)
- 刷新、迁移或重置工程记忆：[Existing project upgrade path](docs/existing-project-upgrade.md#intent-quick-reference)
- 查看最小项目布局：[examples/minimal-project](examples/minimal-project/README.md)
- 了解如何适配：[How to adapt](docs/how-to-adapt.md)
- 维护项目记忆：[Language policy](docs/language-policy.md) 和
  [Agent governance](docs/agent-governance.md)

## 文档导航

- [Architecture](docs/architecture.md)
- [Agent governance](docs/agent-governance.md)
- [Domain pack governance](docs/domain-pack-governance.md)
- [How to adapt](docs/how-to-adapt.md)
- [Existing project upgrade path](docs/existing-project-upgrade.md)
- [Minimal project adoption walkthrough](docs/walkthroughs/minimal-project-adoption.md)
- [Language policy](docs/language-policy.md)
- [Release process](docs/release-process.md)
- [Release readiness](docs/release-readiness.md)
- [Shell strategy](docs/shell-strategy.md)
- [Release notes](docs/releases/README.md)
- [Knowledge catalog](knowledge-hub/knowledge-catalog.md)
- [Examples](examples/README.md)

## 贡献、反馈与安全边界

欢迎通过 issues 和 pull requests 反馈 public kernel 的问题。提交前请保持变更可验证、
scope 清晰，并避免把 private overlay、本机路径、凭据、敏感审计材料或生成的 runtime
manifest 带入公开仓库。

公开仓库只承载可复用、public-safe 的 kernel 和知识。私有项目规则、内部环境假设和实验性
skills 应保留在项目本地或 private overlay 中。

## License

MIT
