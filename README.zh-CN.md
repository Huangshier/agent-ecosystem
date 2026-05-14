# Agent Ecosystem

Agent Ecosystem 是面向 agent-assisted software projects 的工作流内核。

公开文档以英文优先；本文件是简体中文入口，帮助快速理解项目定位和采用方式。

当前公开版本：`v0.4.2`。

## 它是什么

- 一套可安装、可验证、可扩展的 Workflow Kernel。
- 通过 `project-bootstrap` 初始化项目级 `.agents/` 记忆。
- 通过 `project-context-gate` 渐进加载项目上下文。
- 通过 `workflow-spec-lite` 建立轻量、可延续的 `docs/specs/` 工作包。
- 通过 `memory-governance` 维护项目记忆并沉淀可复用经验。
- 提供 public-safe knowledge hub templates、domain-pack scaffold、安装/卸载和
  release validation 工具。

## 它不是什么

- 不是 agent runtime。
- 不是模型编排框架。
- 不是任务调度系统。
- 不是要求所有项目原样照搬的万能工作流。
- 不存放 private overlay、本机迁移记录或私有运行时状态。

## 如何扩展

建议把公开 kernel 当作稳定起点，然后按项目需要调整：

- 在每个项目自己的 `.agents/` 中维护项目记忆。
- 在 `docs/specs/` 中保存需要跨会话延续的工作包。
- 在本地 `.agents/context/` 中沉淀项目或领域知识。
- 自定义 skill 先在私有项目中孵化，稳定且 public-safe 后再考虑公开。
- 不是每个 skill 或 workflow 都适合所有人；公开 kernel 只承担基础流。

## 快速开始

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Profile recommended
```

建议先安装到临时 runtime 做验证：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Profile recommended -TargetDir <temp-runtime> -Copy -Force
```

非 Windows 系统，或已经安装 PowerShell 7+ 时，可以用
`pwsh -NoProfile -File` 加相同脚本参数。当前公开脚本面是 PowerShell-first；
更多说明见英文 [Shell strategy](docs/shell-strategy.md)。

默认安装模式会优先创建链接；如果链接创建失败，安装器会回退到 copy mode。
安装器会在目标 runtime 下生成 `install-manifest.json`，记录 profile、skills 和
每个安装项使用的模式。

## Profiles

当前公开 profile：

- `minimal`：安装 bootstrap skill 和 public knowledge hub templates。
- `recommended`：安装 Workflow Kernel 和 public knowledge hub。
- `full`：当前安装内容与 `recommended` 相同。
- `dev`：当前安装内容与 `recommended` 相同。

`full` 和 `dev` 会在 kernel 基础流稳定后用于后续 public domain packs 和
developer maintenance tooling。

## 更多文档

英文文档是当前权威入口：

- [Architecture](docs/architecture.md)
- [Agent governance](docs/agent-governance.md)
- [How to adapt](docs/how-to-adapt.md)
- [Minimal project adoption walkthrough](docs/walkthroughs/minimal-project-adoption.md)
- [Release process](docs/release-process.md)
- [Release readiness](docs/release-readiness.md)
- [v0.4.2 release notes](docs/releases/v0.4.2.md)
- [v0.4.1 release notes](docs/releases/v0.4.1.md)
- [v0.4.0 release notes](docs/releases/v0.4.0.md)
- [v0.3.1 release notes](docs/releases/v0.3.1.md)
- [v0.3.0 release notes](docs/releases/v0.3.0.md)
- [Examples](examples/README.md)
